// SPDX-License-Identifier: MPL-2.0
// Owner: Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//! Backend implementation for the Tangle LSP server.
//!
//! Handles all LSP lifecycle events and request dispatching.  Document state
//! is stored in a concurrent `DashMap` keyed by URI.  On every open/change
//! event the document is re-parsed and re-type-checked, producing diagnostics
//! that are pushed to the client.

use dashmap::DashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use tower_lsp::jsonrpc::Result;
use tower_lsp::lsp_types::*;
use tower_lsp::{Client, LanguageServer};

/// Monotonic counter for unique per-check temp-file names (avoids collisions
/// when concurrent documents of equal byte-length are checked at once).
static CHECK_SEQ: AtomicU64 = AtomicU64::new(0);

// ---------------------------------------------------------------------------
// Compiler-delegated diagnostics (TG-9)
// ---------------------------------------------------------------------------

/// Resolve the `tanglec` binary: `$TANGLEC` if set, else `tanglec` on `PATH`.
fn tanglec_binary() -> String {
    std::env::var("TANGLEC").unwrap_or_else(|_| "tanglec".to_string())
}

/// Parse one line of `tanglec --check` output —
/// `"SEVERITY<TAB>LINE<TAB>COL<TAB>MESSAGE"` (LINE 1-based) — into its parts.
/// Returns `None` for unrecognised lines so malformed output is ignored rather
/// than turned into a spurious diagnostic.
fn parse_check_line(line: &str) -> Option<(DiagnosticSeverity, u32, u32, String)> {
    let mut parts = line.splitn(4, '\t');
    let severity = match parts.next()? {
        "ERROR" => DiagnosticSeverity::ERROR,
        "WARNING" => DiagnosticSeverity::WARNING,
        _ => return None,
    };
    let line_no: u32 = parts.next()?.parse().ok()?;
    let col: u32 = parts.next()?.parse().ok()?;
    let message = parts.next()?.to_string();
    Some((severity, line_no, col, message))
}

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
        state.run_compiler_diagnostics();
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

    /// Extract definition sites and identifier references for IDE navigation
    /// (hover, completion, go-to-definition).  This is a lightweight lexical
    /// scan — it does NOT produce diagnostics.  Diagnostics come solely from the
    /// real compiler via [`run_compiler_diagnostics`], so that what the LSP
    /// reports is by construction a subset of the compiler's parse / `HasType`
    /// failures (proof obligation TG-9).
    fn analyze(&mut self) {
        self.definitions.clear();
        self.references.clear();

        for (line_idx, line) in self.source.lines().enumerate() {
            let trimmed = line.trim();
            let ln = line_idx as u32;

            // Skip line comments (`#` and the legacy `--`).
            if trimmed.starts_with('#') || trimmed.starts_with("--") {
                continue;
            }

            // def name(params) = body
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

            // weave strands ...
            if trimmed.starts_with("weave ") {
                let col = line.find("weave ").unwrap_or(0) as u32;
                self.definitions.push(("(weave block)".to_string(), ln, col, "Struct"));
            }

            // let x = ...
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

            // Collect identifier references for navigation.
            for word in trimmed.split(|c: char| !c.is_alphanumeric() && c != '_') {
                if word.is_empty() {
                    continue;
                }
                if !TANGLE_KEYWORDS.contains(&word)
                    && word.chars().next().map(|c| c.is_alphabetic()).unwrap_or(false)
                {
                    let col = line.find(word).unwrap_or(0) as u32;
                    self.references.push((word.to_string(), ln, col));
                }
            }
        }
    }

    /// Populate `self.diagnostics` by delegating to the real compiler's
    /// `tanglec --check` pass.  The LSP forwards the compiler's diagnostics
    /// rather than computing its own, so every LSP diagnostic corresponds to a
    /// genuine parse / `HasType` failure (TG-9).  If the compiler binary is
    /// unavailable, no diagnostics are emitted — the empty set is trivially a
    /// subset, never a false positive.
    fn run_compiler_diagnostics(&mut self) {
        self.diagnostics.clear();

        // Write the in-memory buffer to a temp file so the compiler checks the
        // live (possibly unsaved) text, not stale on-disk content.
        let mut path = std::env::temp_dir();
        path.push(format!(
            "tangle-lsp-{}-{}.tangle",
            std::process::id(),
            CHECK_SEQ.fetch_add(1, Ordering::Relaxed)
        ));
        if std::fs::write(&path, &self.source).is_err() {
            return;
        }

        let output = std::process::Command::new(tanglec_binary())
            .arg("--check")
            .arg(&path)
            .output();
        let _ = std::fs::remove_file(&path);

        let output = match output {
            Ok(o) => o,
            Err(_) => return, // compiler unavailable: emit nothing (∅ ⊆ failures)
        };

        let stdout = String::from_utf8_lossy(&output.stdout);
        for line in stdout.lines() {
            if let Some((severity, line_no, col, message)) = parse_check_line(line) {
                let range = self.diagnostic_range(line_no.saturating_sub(1), col);
                self.diagnostics.push(Diagnostic {
                    range,
                    severity: Some(severity),
                    source: Some("tanglec".into()),
                    message,
                    ..Default::default()
                });
            }
        }
    }

    /// A range starting at `(line, col)` and spanning to end of line (or the
    /// whole line when `col` is 0), for highlighting a compiler diagnostic.
    fn diagnostic_range(&self, line: u32, col: u32) -> Range {
        let full = self.line_range(line);
        let start = Position::new(line, col);
        let end = full.end;
        if end.line > start.line || end.character > start.character {
            Range { start, end }
        } else {
            full
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

        // Built-in operations
        for b in TANGLE_BUILTINS {
            if b.starts_with(&prefix) || prefix.is_empty() {
                items.push(CompletionItem {
                    label: b.to_string(),
                    kind: Some(CompletionItemKind::FUNCTION),
                    detail: Some("Built-in".into()),
                    sort_text: Some(format!("1_{}", b)),
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_error_line() {
        let (sev, line, col, msg) =
            parse_check_line("ERROR\t3\t5\tCannot compare words of differing width").unwrap();
        assert_eq!(sev, DiagnosticSeverity::ERROR);
        assert_eq!(line, 3);
        assert_eq!(col, 5);
        assert_eq!(msg, "Cannot compare words of differing width");
    }

    #[test]
    fn parses_warning_and_keeps_tabs_in_message() {
        let (sev, _l, _c, msg) =
            parse_check_line("WARNING\t1\t0\tunused\tbinding").unwrap();
        assert_eq!(sev, DiagnosticSeverity::WARNING);
        // Only the first three tabs are structural; the rest belongs to the message.
        assert_eq!(msg, "unused\tbinding");
    }

    #[test]
    fn rejects_malformed_lines() {
        // Unknown severity, missing fields, and non-numeric positions are ignored
        // rather than surfaced as spurious diagnostics (preserves the TG-9 subset).
        assert!(parse_check_line("").is_none());
        assert!(parse_check_line("INFO\t1\t0\tnot an error or warning").is_none());
        assert!(parse_check_line("ERROR\tx\t0\tbad line number").is_none());
        assert!(parse_check_line("ERROR\t1").is_none());
    }

    /// End-to-end delegation check, gated on a real compiler being available
    /// via `$TANGLEC` (skipped otherwise so CI without the binary stays green).
    /// Establishes the TG-9 subset relation concretely: a type-erroneous program
    /// yields diagnostics sourced from `tanglec`, while a valid one yields none.
    #[test]
    fn delegates_to_compiler_when_available() {
        if std::env::var("TANGLEC").is_err() {
            eprintln!("skipping: TANGLEC not set");
            return;
        }
        // Unequal-width word equality — rejected by the tightened tEqWord rule.
        let bad = DocumentState::new("def bad = braid[s1] == braid[s1, s2]\n".to_string());
        assert!(!bad.diagnostics.is_empty(), "type error should produce diagnostics");
        assert!(bad.diagnostics.iter().all(|d| d.source.as_deref() == Some("tanglec")),
            "every diagnostic must originate from the compiler");

        let good = DocumentState::new("def ok = close(braid[s1, s1, s1])\n".to_string());
        assert!(good.diagnostics.is_empty(), "valid program should produce no diagnostics");
    }

    #[test]
    fn analyze_produces_no_diagnostics() {
        // Navigation extraction must never emit diagnostics — those come only
        // from the compiler. A previously-false-positive case (multiple defs,
        // delimiters inside a string/comment) yields zero LSP-authored diagnostics.
        let mut state = DocumentState {
            source: "def a = braid[s1]\ndef b = \"text with ( unbalanced\"\n# (comment\n".to_string(),
            line_starts: vec![0],
            definitions: Vec::new(),
            references: Vec::new(),
            diagnostics: Vec::new(),
        };
        state.analyze();
        assert!(state.diagnostics.is_empty(), "analyze() must not author diagnostics");
        // Definitions are still extracted for navigation.
        assert!(state.definitions.iter().any(|(n, _, _, _)| n == "a"));
        assert!(state.definitions.iter().any(|(n, _, _, _)| n == "b"));
    }
}
