// SPDX-License-Identifier: MPL-2.0
//! Backend implementation for the Tangle LSP server.
//!
//! Handles all LSP lifecycle events and request dispatching.  Document state
//! is stored in a concurrent `DashMap` keyed by URI.  On every open/change
//! event the document is re-parsed and re-type-checked, producing diagnostics
//! that are pushed to the client.

use dashmap::DashMap;
use std::sync::Arc;
use tower_lsp::jsonrpc::Result;
use tower_lsp::lsp_types::*;
use tower_lsp::{Client, LanguageServer};

// ---------------------------------------------------------------------------
// Document state
// ---------------------------------------------------------------------------

/// Parsed information about a single document.
struct DocumentState {
    /// Raw source text.
    source: String,
    /// Byte offset of each line start (for position conversion).
    line_starts: Vec<usize>,
    /// Definitions found in this document: (name, line, col, kind_label).
    definitions: Vec<(String, u32, u32, &'static str)>,
    /// Identifiers used in the document: (name, line, col).
    references: Vec<(String, u32, u32)>,
    /// Diagnostics produced by the last parse/type-check pass.
    diagnostics: Vec<Diagnostic>,
}

impl DocumentState {
    fn new(source: String) -> Self {
        let line_starts = std::iter::once(0)
            .chain(source.char_indices().filter_map(|(i, c)| {
                if c == '\n' { Some(i + 1) } else { None }
            }))
            .collect::<Vec<_>>();

        let mut state = Self {
            source,
            line_starts,
            definitions: Vec::new(),
            references: Vec::new(),
            diagnostics: Vec::new(),
        };
        state.analyze();
        state
    }

    // -----------------------------------------------------------------------
    // Position helpers
    // -----------------------------------------------------------------------

    fn offset_to_position(&self, offset: usize) -> Position {
        let line = self
            .line_starts
            .binary_search(&offset)
            .unwrap_or_else(|i| i.saturating_sub(1));
        let col = offset.saturating_sub(self.line_starts[line]);
        Position::new(line as u32, col as u32)
    }

    fn line_range(&self, line: u32) -> Range {
        let l = line as usize;
        let start = self.line_starts.get(l).copied().unwrap_or(0);
        let end = self
            .line_starts
            .get(l + 1)
            .map(|s| s.saturating_sub(1))
            .unwrap_or(self.source.len());
        Range {
            start: self.offset_to_position(start),
            end: self.offset_to_position(end),
        }
    }

    // -----------------------------------------------------------------------
    // Analysis — lightweight lexical + structural pass
    // -----------------------------------------------------------------------

    /// Perform a lightweight analysis pass over the document text.
    ///
    /// This is intentionally a simplified lexical scan rather than a full parse
    /// (the real OCaml parser is not linked here).  It catches common errors
    /// and extracts definition sites for IDE navigation.
    fn analyze(&mut self) {
        self.definitions.clear();
        self.references.clear();
        self.diagnostics.clear();

        let mut depth: i32 = 0; // nesting: weave/match/let blocks
        let mut open_weave = false;
        let mut paren_depth: i32 = 0;
        let mut bracket_depth: i32 = 0;
        let mut brace_depth: i32 = 0;

        for (line_idx, line) in self.source.lines().enumerate() {
            let trimmed = line.trim();
            let ln = line_idx as u32;

            // Skip comments (lines starting with --)
            if trimmed.starts_with("--") {
                continue;
            }

            // Track bracket/paren/brace balance
            for ch in trimmed.chars() {
                match ch {
                    '(' => paren_depth += 1,
                    ')' => paren_depth -= 1,
                    '[' => bracket_depth += 1,
                    ']' => bracket_depth -= 1,
                    '{' => brace_depth += 1,
                    '}' => brace_depth -= 1,
                    _ => {}
                }
            }

            // ------ Definitions ------

            // def name(params) = body
            if trimmed.starts_with("def ") {
                if let Some(rest) = trimmed.strip_prefix("def ") {
                    let name = rest
                        .split(|c: char| !c.is_alphanumeric() && c != '_')
                        .next()
                        .unwrap_or("");
                    if !name.is_empty() {
                        let col = line.find("def ").unwrap_or(0) as u32 + 4;
                        self.definitions.push((name.to_string(), ln, col, "Function"));
                    }
                }
                depth += 1;
            }

            // weave strands ...
            if trimmed.starts_with("weave ") {
                open_weave = true;
                depth += 1;
                let col = line.find("weave ").unwrap_or(0) as u32;
                self.definitions.push(("(weave block)".to_string(), ln, col, "Struct"));
            }

            // yield strands ...
            if trimmed.starts_with("yield ") && open_weave {
                open_weave = false;
                depth -= 1;
            }

            // let x = ...
            if trimmed.starts_with("let ") {
                if let Some(rest) = trimmed.strip_prefix("let ") {
                    let name = rest
                        .split(|c: char| !c.is_alphanumeric() && c != '_')
                        .next()
                        .unwrap_or("");
                    if !name.is_empty() {
                        let col = line.find("let ").unwrap_or(0) as u32 + 4;
                        self.definitions.push((name.to_string(), ln, col, "Variable"));
                    }
                }
            }

            // match ... with
            if trimmed.starts_with("match ") {
                depth += 1;
            }
            if trimmed == "end" {
                depth -= 1;
            }

            // Collect identifier references (simple word extraction)
            for word in trimmed.split(|c: char| !c.is_alphanumeric() && c != '_') {
                if word.is_empty() {
                    continue;
                }
                if !TANGLE_KEYWORDS.contains(&word) && word.chars().next().map(|c| c.is_alphabetic()).unwrap_or(false) {
                    let col = line.find(word).unwrap_or(0) as u32;
                    self.references.push((word.to_string(), ln, col));
                }
            }

            // ------ Diagnostics ------

            // Check for unknown keywords that look like misspellings
            if trimmed.starts_with("comput ") || trimmed.starts_with("asert ") {
                self.diagnostics.push(Diagnostic {
                    range: self.line_range(ln),
                    severity: Some(DiagnosticSeverity::ERROR),
                    source: Some("tangle-lsp".into()),
                    message: format!("Possible misspelling: `{}`", trimmed.split_whitespace().next().unwrap_or("")),
                    ..Default::default()
                });
            }
        }

        // Check unmatched delimiters
        if paren_depth != 0 {
            self.diagnostics.push(Diagnostic {
                range: Range {
                    start: Position::new(0, 0),
                    end: Position::new(0, 1),
                },
                severity: Some(DiagnosticSeverity::ERROR),
                source: Some("tangle-lsp".into()),
                message: format!("Unbalanced parentheses (depth: {})", paren_depth),
                ..Default::default()
            });
        }
        if bracket_depth != 0 {
            self.diagnostics.push(Diagnostic {
                range: Range {
                    start: Position::new(0, 0),
                    end: Position::new(0, 1),
                },
                severity: Some(DiagnosticSeverity::ERROR),
                source: Some("tangle-lsp".into()),
                message: format!("Unbalanced brackets (depth: {})", bracket_depth),
                ..Default::default()
            });
        }
        if brace_depth != 0 {
            self.diagnostics.push(Diagnostic {
                range: Range {
                    start: Position::new(0, 0),
                    end: Position::new(0, 1),
                },
                severity: Some(DiagnosticSeverity::ERROR),
                source: Some("tangle-lsp".into()),
                message: format!("Unbalanced braces (depth: {})", brace_depth),
                ..Default::default()
            });
        }
        if open_weave {
            self.diagnostics.push(Diagnostic {
                range: Range {
                    start: Position::new(0, 0),
                    end: Position::new(0, 1),
                },
                severity: Some(DiagnosticSeverity::WARNING),
                source: Some("tangle-lsp".into()),
                message: "Unclosed `weave` block — expected `yield strands`".into(),
                ..Default::default()
            });
        }
        if depth > 0 {
            self.diagnostics.push(Diagnostic {
                range: Range {
                    start: Position::new(0, 0),
                    end: Position::new(0, 1),
                },
                severity: Some(DiagnosticSeverity::WARNING),
                source: Some("tangle-lsp".into()),
                message: format!("Possible unclosed block (nesting depth: {})", depth),
                ..Default::default()
            });
        }

        // Check for undefined references (identifiers not matching any def)
        let defined_names: Vec<&str> = self.definitions.iter().map(|(n, _, _, _)| n.as_str()).collect();
        for (name, ln, col) in &self.references {
            if !defined_names.contains(&name.as_str())
                && !TANGLE_BUILTINS.contains(&name.as_str())
                && !TANGLE_INVARIANTS.contains(&name.as_str())
                && !name.starts_with('s') // generator references like s1, s2
            {
                // Only warn, not error — the name may be defined in an import
                self.diagnostics.push(Diagnostic {
                    range: Range {
                        start: Position::new(*ln, *col),
                        end: Position::new(*ln, *col + name.len() as u32),
                    },
                    severity: Some(DiagnosticSeverity::HINT),
                    source: Some("tangle-lsp".into()),
                    message: format!("Possibly undefined: `{}`", name),
                    ..Default::default()
                });
            }
        }
    }

    /// Return the word under the given position.
    fn word_at(&self, line: u32, col: u32) -> Option<String> {
        let line_str = self.source.lines().nth(line as usize)?;
        let c = col as usize;
        if c > line_str.len() {
            return None;
        }

        let start = line_str[..c]
            .rfind(|ch: char| !ch.is_alphanumeric() && ch != '_')
            .map(|i| i + 1)
            .unwrap_or(0);
        let end = line_str[c..]
            .find(|ch: char| !ch.is_alphanumeric() && ch != '_')
            .map(|i| c + i)
            .unwrap_or(line_str.len());

        if start < end {
            Some(line_str[start..end].to_string())
        } else {
            None
        }
    }
}

// ---------------------------------------------------------------------------
// Tangle language constants
// ---------------------------------------------------------------------------

/// Reserved keywords in the Tangle language.
const TANGLE_KEYWORDS: &[&str] = &[
    "def", "weave", "into", "yield", "strands", "compute", "assert",
    "match", "with", "end", "let", "in", "identity", "true", "false",
    "close", "mirror", "reverse", "simplify", "cap", "cup", "braid",
    "twist",
];

/// Built-in invariant names.
const TANGLE_INVARIANTS: &[&str] = &[
    "jones", "alexander", "homfly", "kauffman", "writhe", "linking",
];

/// Built-in operations that act as implicit definitions.
const TANGLE_BUILTINS: &[&str] = &[
    "close", "mirror", "reverse", "simplify", "cap", "cup", "twist",
    "identity", "true", "false",
];

/// Type documentation for built-in operations.
fn builtin_type_doc(name: &str) -> Option<&'static str> {
    match name {
        "def" => Some("**def** name(params) = body\n\nDefine a named binding or function."),
        "weave" => Some("**weave** strands <inputs> into <body> yield strands <outputs>\n\nDeclare named strands, compose them, and yield output strands.\n\nType: Tangle[A, B]"),
        "compute" => Some("**compute** invariant(expr)\n\nCompute a knot/link invariant on a closed tangle.\n\nRequires: Tangle[I, I] (closed)"),
        "assert" => Some("**assert** expr\n\nAssert that `expr` evaluates to `true`.\n\nRequires: Bool"),
        "match" => Some("**match** expr **with**\n  | pattern => body\n  ...\n**end**\n\nPattern match on braid words."),
        "let" => Some("**let** name = expr **in** body\n\nLocal binding."),
        "identity" => Some("**identity** : Word[0]\n\nThe empty braid word (identity element)."),
        "close" => Some("**close**(expr) : Tangle[I, I]\n\nClose a braid or tangle into a link.\n\nInput: Word[n] or Tangle[A, B] where |A| = |B|"),
        "mirror" => Some("**mirror**(expr)\n\nMirror image (swap all crossings).\n\nWord[n] -> Word[n]\nTangle[A, B] -> Tangle[B, A]"),
        "reverse" => Some("**reverse**(expr) : Word[n]\n\nReverse generator order in a braid word."),
        "simplify" => Some("**simplify**(expr)\n\nApply algebraic simplification (free reductions, Reidemeister moves)."),
        "cap" => Some("**cap**(a, b) : Tangle[[a, b], I]\n\nCreate a cap connecting two strands from above."),
        "cup" => Some("**cup**(a, b) : Tangle[I, [a, b]]\n\nCreate a cup emitting two strands below."),
        "twist" => Some("**twist**(expr)\n\nAdd a full twist to a braid or tangle."),
        "jones" => Some("**jones** — Jones polynomial invariant\n\nComputes the Jones polynomial of a closed tangle."),
        "alexander" => Some("**alexander** — Alexander polynomial invariant\n\nComputes the Alexander polynomial."),
        "homfly" => Some("**homfly** — HOMFLY-PT polynomial\n\nTwo-variable polynomial invariant."),
        "kauffman" => Some("**kauffman** — Kauffman bracket polynomial"),
        "writhe" => Some("**writhe** — Writhe number\n\nSigned sum of crossings."),
        "linking" => Some("**linking** — Linking number\n\nInteger invariant of a two-component link."),
        "braid" => Some("**braid**[g1, g2, ...]\n\nBraid literal from generators.\n\nType: Word[max(index + 1)]"),
        "true" => Some("**true** : Bool"),
        "false" => Some("**false** : Bool"),
        _ => None,
    }
}

// ---------------------------------------------------------------------------
// Backend
// ---------------------------------------------------------------------------

/// Tangle LSP backend — holds client handle and per-document state.
pub struct TangleBackend {
    client: Client,
    documents: Arc<DashMap<Url, DocumentState>>,
}

impl TangleBackend {
    pub fn new(client: Client) -> Self {
        Self {
            client,
            documents: Arc::new(DashMap::new()),
        }
    }

    async fn publish_diagnostics(&self, uri: &Url) {
        if let Some(doc) = self.documents.get(uri) {
            self.client
                .publish_diagnostics(uri.clone(), doc.diagnostics.clone(), None)
                .await;
        }
    }
}

#[tower_lsp::async_trait]
impl LanguageServer for TangleBackend {
    async fn initialize(&self, _params: InitializeParams) -> Result<InitializeResult> {
        Ok(InitializeResult {
            capabilities: ServerCapabilities {
                text_document_sync: Some(TextDocumentSyncCapability::Kind(
                    TextDocumentSyncKind::FULL,
                )),
                completion_provider: Some(CompletionOptions {
                    trigger_characters: Some(vec![" ".into(), ".".into(), "|".into()]),
                    resolve_provider: Some(false),
                    ..Default::default()
                }),
                hover_provider: Some(HoverProviderCapability::Simple(true)),
                definition_provider: Some(OneOf::Left(true)),
                document_symbol_provider: Some(OneOf::Left(true)),
                ..Default::default()
            },
            server_info: Some(ServerInfo {
                name: "tangle-lsp".into(),
                version: Some("0.1.0".into()),
            }),
        })
    }

    async fn initialized(&self, _: InitializedParams) {
        self.client
            .log_message(MessageType::INFO, "Tangle LSP server initialized")
            .await;
    }

    async fn shutdown(&self) -> Result<()> {
        Ok(())
    }

    // -----------------------------------------------------------------------
    // Document sync
    // -----------------------------------------------------------------------

    async fn did_open(&self, params: DidOpenTextDocumentParams) {
        let uri = params.text_document.uri;
        let doc = DocumentState::new(params.text_document.text);
        self.documents.insert(uri.clone(), doc);
        self.publish_diagnostics(&uri).await;
    }

    async fn did_change(&self, params: DidChangeTextDocumentParams) {
        let uri = params.text_document.uri;
        if let Some(change) = params.content_changes.first() {
            let doc = DocumentState::new(change.text.clone());
            self.documents.insert(uri.clone(), doc);
            self.publish_diagnostics(&uri).await;
        }
    }

    async fn did_close(&self, params: DidCloseTextDocumentParams) {
        self.documents.remove(&params.text_document.uri);
    }

    // -----------------------------------------------------------------------
    // Hover
    // -----------------------------------------------------------------------

    async fn hover(&self, params: HoverParams) -> Result<Option<Hover>> {
        let uri = &params.text_document_position_params.text_document.uri;
        let pos = params.text_document_position_params.position;

        let doc = match self.documents.get(uri) {
            Some(d) => d,
            None => return Ok(None),
        };

        let word = match doc.word_at(pos.line, pos.character) {
            Some(w) => w,
            None => return Ok(None),
        };

        // Check for built-in documentation
        if let Some(doc_text) = builtin_type_doc(&word) {
            return Ok(Some(Hover {
                contents: HoverContents::Markup(MarkupContent {
                    kind: MarkupKind::Markdown,
                    value: doc_text.to_string(),
                }),
                range: None,
            }));
        }

        // Check definitions in the current document
        for (name, _ln, _col, kind) in &doc.definitions {
            if name == &word {
                return Ok(Some(Hover {
                    contents: HoverContents::Markup(MarkupContent {
                        kind: MarkupKind::Markdown,
                        value: format!("**{}** `{}`\n\nDefined in this file.", kind, name),
                    }),
                    range: None,
                }));
            }
        }

        Ok(None)
    }

    // -----------------------------------------------------------------------
    // Completion
    // -----------------------------------------------------------------------

    async fn completion(&self, params: CompletionParams) -> Result<Option<CompletionResponse>> {
        let uri = &params.text_document_position.text_document.uri;
        let pos = params.text_document_position.position;

        let doc = match self.documents.get(uri) {
            Some(d) => d,
            None => return Ok(None),
        };

        let prefix = doc
            .word_at(pos.line, pos.character)
            .unwrap_or_default();

        let mut items = Vec::new();

        // Keywords
        for kw in TANGLE_KEYWORDS {
            if kw.starts_with(&prefix) || prefix.is_empty() {
                items.push(CompletionItem {
                    label: kw.to_string(),
                    kind: Some(CompletionItemKind::KEYWORD),
                    detail: Some("Keyword".into()),
                    sort_text: Some(format!("0_{}", kw)),
                    ..Default::default()
                });
            }
        }

        // Invariants
        for inv in TANGLE_INVARIANTS {
            if inv.starts_with(&prefix) || prefix.is_empty() {
                items.push(CompletionItem {
                    label: inv.to_string(),
                    kind: Some(CompletionItemKind::FUNCTION),
                    detail: Some("Invariant".into()),
                    sort_text: Some(format!("1_{}", inv)),
                    ..Default::default()
                });
            }
        }

        // Identifiers defined in this file
        for (name, _ln, _col, kind) in &doc.definitions {
            if (name.starts_with(&prefix) || prefix.is_empty()) && name != "(weave block)" {
                items.push(CompletionItem {
                    label: name.clone(),
                    kind: Some(match *kind {
                        "Function" => CompletionItemKind::FUNCTION,
                        "Variable" => CompletionItemKind::VARIABLE,
                        _ => CompletionItemKind::TEXT,
                    }),
                    detail: Some(kind.to_string()),
                    sort_text: Some(format!("2_{}", name)),
                    ..Default::default()
                });
            }
        }

        Ok(Some(CompletionResponse::Array(items)))
    }

    // -----------------------------------------------------------------------
    // Go to definition
    // -----------------------------------------------------------------------

    async fn goto_definition(
        &self,
        params: GotoDefinitionParams,
    ) -> Result<Option<GotoDefinitionResponse>> {
        let uri = &params.text_document_position_params.text_document.uri;
        let pos = params.text_document_position_params.position;

        let doc = match self.documents.get(uri) {
            Some(d) => d,
            None => return Ok(None),
        };

        let word = match doc.word_at(pos.line, pos.character) {
            Some(w) => w,
            None => return Ok(None),
        };

        // Search definitions
        for (name, ln, col, _kind) in &doc.definitions {
            if name == &word {
                return Ok(Some(GotoDefinitionResponse::Scalar(Location {
                    uri: uri.clone(),
                    range: Range {
                        start: Position::new(*ln, *col),
                        end: Position::new(*ln, *col + name.len() as u32),
                    },
                })));
            }
        }

        Ok(None)
    }

    // -----------------------------------------------------------------------
    // Document symbols
    // -----------------------------------------------------------------------

    async fn document_symbol(
        &self,
        params: DocumentSymbolParams,
    ) -> Result<Option<DocumentSymbolResponse>> {
        let uri = &params.text_document.uri;

        let doc = match self.documents.get(uri) {
            Some(d) => d,
            None => return Ok(None),
        };

        #[allow(deprecated)]
        let symbols: Vec<SymbolInformation> = doc
            .definitions
            .iter()
            .map(|(name, ln, col, kind)| SymbolInformation {
                name: name.clone(),
                kind: match *kind {
                    "Function" => SymbolKind::FUNCTION,
                    "Variable" => SymbolKind::VARIABLE,
                    "Struct" => SymbolKind::STRUCT,
                    _ => SymbolKind::KEY,
                },
                tags: None,
                deprecated: None,
                location: Location {
                    uri: uri.clone(),
                    range: Range {
                        start: Position::new(*ln, *col),
                        end: Position::new(*ln, *col + name.len() as u32),
                    },
                },
                container_name: None,
            })
            .collect();

        Ok(Some(DocumentSymbolResponse::Flat(symbols)))
    }
}
