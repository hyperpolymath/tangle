// SPDX-License-Identifier: MPL-2.0
// lexer.rs — TANGLE + TANGLE-JTV tokenizer with mode switching
//
// Three lexing modes:
//   Tangle     — base language (braid algebra, pattern matching, weave blocks)
//   HvData     — inside add{...} (total arithmetic, no control flow)
//   HvControl  — inside harvard{...} (imperative, Turing-complete)
//
// Mode transitions occur on `add{` and `harvard{` keywords followed by `{`.
// Brace depth tracking determines when to exit back to the parent mode.

use std::fmt;

/// Source location for error reporting.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub struct Span {
    pub offset: usize,
    pub line: u32,
    pub col: u32,
}

impl fmt::Display for Span {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}:{}", self.line, self.col)
    }
}

/// Lexer mode — determines which keywords and operators are active.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    Tangle,
    HvData,
    HvControl,
}

/// Token produced by the lexer.
#[derive(Debug, Clone, PartialEq)]
pub struct Token {
    pub kind: TokenKind,
    pub span: Span,
    pub text: String,
}

/// All token kinds for TANGLE + TANGLE-JTV.
#[derive(Debug, Clone, PartialEq)]
pub enum TokenKind {
    // --- TANGLE keywords ---
    Def,
    Weave,
    Into,
    Yield,
    Strands,
    Compute,
    Assert,
    Match,
    With,
    End,
    Let,
    In,
    Braid,
    Identity,
    True,
    False,
    Close,
    Mirror,
    Reverse,
    Simplify,
    Cap,
    Cup,
    Add,
    Harvard,

    // --- Harvard keywords (only in HV modes) ---
    Fn,
    If,
    Else,
    While,
    For,
    Return,
    Print,
    Module,
    Import,
    As,
    Then,

    // --- Purity markers ---
    AtPure,
    AtTotal,

    // --- Operators (TANGLE) ---
    Pipeline,    // >>
    EqEq,       // ==
    Tilde,      // ~
    Plus,       // +
    Minus,      // -
    Star,       // *
    Slash,      // /
    Dot,        // .
    Pipe,       // |
    Gt,         // >
    Lt,         // <
    Caret,      // ^
    Eq,         // =
    FatArrow,   // =>
    Bang,       // !
    Comma,      // ,
    Colon,      // :
    Underscore, // _

    // --- Delimiters ---
    LParen,     // (
    RParen,     // )
    LBracket,   // [
    RBracket,   // ]
    LBrace,     // {
    RBrace,     // }

    // --- Harvard operators (only in HV modes) ---
    AmpAmp,     // &&
    PipePipe,   // ||
    BangEq,     // !=
    LtEq,       // <=
    GtEq,       // >=
    Percent,    // %
    PlusEq,     // +=
    MinusEq,    // -=
    DotDot,     // ..
    Arrow,      // ->

    // --- Harvard comment tokens ---
    HvLineComment,
    HvBlockComment,

    // --- Literals ---
    Integer(i64),
    Float(f64),
    HexLit(u64),
    BinaryLit(u64),
    StringLit(String),

    // --- Generator token: s followed by digits (e.g. s1, s23) ---
    Generator(u32),

    // --- Identifiers ---
    Ident(String),

    // --- Special ---
    Eof,
    Error(String),
}

impl fmt::Display for TokenKind {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            TokenKind::Def => write!(f, "def"),
            TokenKind::Weave => write!(f, "weave"),
            TokenKind::Into => write!(f, "into"),
            TokenKind::Yield => write!(f, "yield"),
            TokenKind::Strands => write!(f, "strands"),
            TokenKind::Compute => write!(f, "compute"),
            TokenKind::Assert => write!(f, "assert"),
            TokenKind::Match => write!(f, "match"),
            TokenKind::With => write!(f, "with"),
            TokenKind::End => write!(f, "end"),
            TokenKind::Let => write!(f, "let"),
            TokenKind::In => write!(f, "in"),
            TokenKind::Braid => write!(f, "braid"),
            TokenKind::Identity => write!(f, "identity"),
            TokenKind::True => write!(f, "true"),
            TokenKind::False => write!(f, "false"),
            TokenKind::Close => write!(f, "close"),
            TokenKind::Mirror => write!(f, "mirror"),
            TokenKind::Reverse => write!(f, "reverse"),
            TokenKind::Simplify => write!(f, "simplify"),
            TokenKind::Cap => write!(f, "cap"),
            TokenKind::Cup => write!(f, "cup"),
            TokenKind::Add => write!(f, "add"),
            TokenKind::Harvard => write!(f, "harvard"),
            TokenKind::Fn => write!(f, "fn"),
            TokenKind::If => write!(f, "if"),
            TokenKind::Else => write!(f, "else"),
            TokenKind::While => write!(f, "while"),
            TokenKind::For => write!(f, "for"),
            TokenKind::Return => write!(f, "return"),
            TokenKind::Print => write!(f, "print"),
            TokenKind::Module => write!(f, "module"),
            TokenKind::Import => write!(f, "import"),
            TokenKind::As => write!(f, "as"),
            TokenKind::Then => write!(f, "then"),
            TokenKind::AtPure => write!(f, "@pure"),
            TokenKind::AtTotal => write!(f, "@total"),
            TokenKind::Pipeline => write!(f, ">>"),
            TokenKind::EqEq => write!(f, "=="),
            TokenKind::Tilde => write!(f, "~"),
            TokenKind::Plus => write!(f, "+"),
            TokenKind::Minus => write!(f, "-"),
            TokenKind::Star => write!(f, "*"),
            TokenKind::Slash => write!(f, "/"),
            TokenKind::Dot => write!(f, "."),
            TokenKind::Pipe => write!(f, "|"),
            TokenKind::Gt => write!(f, ">"),
            TokenKind::Lt => write!(f, "<"),
            TokenKind::Caret => write!(f, "^"),
            TokenKind::Eq => write!(f, "="),
            TokenKind::FatArrow => write!(f, "=>"),
            TokenKind::Bang => write!(f, "!"),
            TokenKind::Comma => write!(f, ","),
            TokenKind::Colon => write!(f, ":"),
            TokenKind::Underscore => write!(f, "_"),
            TokenKind::LParen => write!(f, "("),
            TokenKind::RParen => write!(f, ")"),
            TokenKind::LBracket => write!(f, "["),
            TokenKind::RBracket => write!(f, "]"),
            TokenKind::LBrace => write!(f, "{{"),
            TokenKind::RBrace => write!(f, "}}"),
            TokenKind::AmpAmp => write!(f, "&&"),
            TokenKind::PipePipe => write!(f, "||"),
            TokenKind::BangEq => write!(f, "!="),
            TokenKind::LtEq => write!(f, "<="),
            TokenKind::GtEq => write!(f, ">="),
            TokenKind::Percent => write!(f, "%"),
            TokenKind::PlusEq => write!(f, "+="),
            TokenKind::MinusEq => write!(f, "-="),
            TokenKind::DotDot => write!(f, ".."),
            TokenKind::Arrow => write!(f, "->"),
            TokenKind::HvLineComment => write!(f, "// comment"),
            TokenKind::HvBlockComment => write!(f, "/* comment */"),
            TokenKind::Integer(n) => write!(f, "{n}"),
            TokenKind::Float(n) => write!(f, "{n}"),
            TokenKind::HexLit(n) => write!(f, "0x{n:x}"),
            TokenKind::BinaryLit(n) => write!(f, "0b{n:b}"),
            TokenKind::StringLit(s) => write!(f, "\"{s}\""),
            TokenKind::Generator(n) => write!(f, "s{n}"),
            TokenKind::Ident(s) => write!(f, "{s}"),
            TokenKind::Eof => write!(f, "EOF"),
            TokenKind::Error(msg) => write!(f, "error: {msg}"),
        }
    }
}

/// Mode stack entry for tracking brace depth across mode switches.
#[derive(Debug, Clone)]
struct ModeFrame {
    mode: Mode,
    brace_depth: u32,
}

/// The TANGLE lexer with mode switching support.
pub struct Lexer {
    src: Vec<char>,
    pos: usize,
    line: u32,
    col: u32,
    mode_stack: Vec<ModeFrame>,
}

impl Lexer {
    pub fn new(source: &str) -> Self {
        Self {
            src: source.chars().collect(),
            pos: 0,
            line: 1,
            col: 1,
            mode_stack: vec![ModeFrame {
                mode: Mode::Tangle,
                brace_depth: 0,
            }],
        }
    }

    fn current_mode(&self) -> Mode {
        self.mode_stack
            .last()
            .map(|f| f.mode)
            .unwrap_or(Mode::Tangle)
    }

    fn is_hv_mode(&self) -> bool {
        matches!(self.current_mode(), Mode::HvData | Mode::HvControl)
    }

    fn span(&self) -> Span {
        Span {
            offset: self.pos,
            line: self.line,
            col: self.col,
        }
    }

    fn peek(&self) -> Option<char> {
        self.src.get(self.pos).copied()
    }

    fn peek_ahead(&self, n: usize) -> Option<char> {
        self.src.get(self.pos + n).copied()
    }

    fn advance(&mut self) -> Option<char> {
        let ch = self.src.get(self.pos).copied()?;
        self.pos += 1;
        if ch == '\n' {
            self.line += 1;
            self.col = 1;
        } else {
            self.col += 1;
        }
        Some(ch)
    }

    fn skip_whitespace(&mut self) {
        while let Some(ch) = self.peek() {
            if ch.is_ascii_whitespace() {
                self.advance();
            } else {
                break;
            }
        }
    }

    /// Skip a TANGLE line comment: # through end of line.
    fn skip_line_comment(&mut self) {
        // consume the #
        self.advance();
        while let Some(ch) = self.peek() {
            if ch == '\n' {
                break;
            }
            self.advance();
        }
    }

    /// Skip a TANGLE block comment: (* ... *) with nesting.
    fn skip_block_comment(&mut self) -> Result<(), String> {
        // consume the opening (*
        self.advance(); // (
        self.advance(); // *
        let mut depth: u32 = 1;
        while depth > 0 {
            match self.peek() {
                None => {
                    return Err("unterminated block comment".to_string());
                }
                Some('(') if self.peek_ahead(1) == Some('*') => {
                    self.advance();
                    self.advance();
                    depth += 1;
                }
                Some('*') if self.peek_ahead(1) == Some(')') => {
                    self.advance();
                    self.advance();
                    depth -= 1;
                }
                _ => {
                    self.advance();
                }
            }
        }
        Ok(())
    }

    /// Skip a Harvard line comment: // through end of line.
    fn skip_hv_line_comment(&mut self) {
        self.advance(); // /
        self.advance(); // /
        while let Some(ch) = self.peek() {
            if ch == '\n' {
                break;
            }
            self.advance();
        }
    }

    /// Skip a Harvard block comment: /* ... */ (non-nesting).
    fn skip_hv_block_comment(&mut self) -> Result<(), String> {
        self.advance(); // /
        self.advance(); // *
        loop {
            match self.peek() {
                None => return Err("unterminated /* comment".to_string()),
                Some('*') if self.peek_ahead(1) == Some('/') => {
                    self.advance();
                    self.advance();
                    return Ok(());
                }
                _ => {
                    self.advance();
                }
            }
        }
    }

    /// Skip whitespace and comments for the current mode.
    fn skip_trivia(&mut self) -> Result<(), String> {
        loop {
            self.skip_whitespace();
            match self.peek() {
                // TANGLE comments
                Some('#') if !self.is_hv_mode() => {
                    self.skip_line_comment();
                }
                Some('(') if self.peek_ahead(1) == Some('*') && !self.is_hv_mode() => {
                    self.skip_block_comment()?;
                }
                // Harvard comments
                Some('/') if self.peek_ahead(1) == Some('/') && self.is_hv_mode() => {
                    self.skip_hv_line_comment();
                }
                Some('/') if self.peek_ahead(1) == Some('*') && self.is_hv_mode() => {
                    self.skip_hv_block_comment()?;
                }
                _ => break,
            }
        }
        Ok(())
    }

    /// Read a string literal (shared across all modes).
    /// The opening `"` has already been consumed by the caller.
    fn read_string(&mut self) -> TokenKind {
        let mut s = String::new();
        loop {
            match self.peek() {
                None => return TokenKind::Error("unterminated string literal".to_string()),
                Some('"') => {
                    self.advance();
                    return TokenKind::StringLit(s);
                }
                Some('\\') => {
                    self.advance();
                    match self.peek() {
                        Some('n') => {
                            self.advance();
                            s.push('\n');
                        }
                        Some('t') => {
                            self.advance();
                            s.push('\t');
                        }
                        Some('r') => {
                            self.advance();
                            s.push('\r');
                        }
                        Some('\\') => {
                            self.advance();
                            s.push('\\');
                        }
                        Some('"') => {
                            self.advance();
                            s.push('"');
                        }
                        Some(c) => {
                            self.advance();
                            s.push('\\');
                            s.push(c);
                        }
                        None => {
                            return TokenKind::Error(
                                "unterminated escape in string".to_string(),
                            );
                        }
                    }
                }
                Some(ch) => {
                    self.advance();
                    s.push(ch);
                }
            }
        }
    }

    /// Read a number literal. Supports integers, floats, hex (0x), binary (0b).
    fn read_number(&mut self, first: char) -> TokenKind {
        let mut num_str = String::new();
        num_str.push(first);

        // Check for hex/binary prefix
        if first == '0' {
            match self.peek() {
                Some('x') | Some('X') => {
                    self.advance();
                    let mut hex = String::new();
                    while let Some(ch) = self.peek() {
                        if ch.is_ascii_hexdigit() || ch == '_' {
                            if ch != '_' {
                                hex.push(ch);
                            }
                            self.advance();
                        } else {
                            break;
                        }
                    }
                    if hex.is_empty() {
                        return TokenKind::Error("empty hex literal".to_string());
                    }
                    return match u64::from_str_radix(&hex, 16) {
                        Ok(n) => TokenKind::HexLit(n),
                        Err(e) => TokenKind::Error(format!("invalid hex: {e}")),
                    };
                }
                Some('b') | Some('B') => {
                    self.advance();
                    let mut bin = String::new();
                    while let Some(ch) = self.peek() {
                        if ch == '0' || ch == '1' || ch == '_' {
                            if ch != '_' {
                                bin.push(ch);
                            }
                            self.advance();
                        } else {
                            break;
                        }
                    }
                    if bin.is_empty() {
                        return TokenKind::Error("empty binary literal".to_string());
                    }
                    return match u64::from_str_radix(&bin, 2) {
                        Ok(n) => TokenKind::BinaryLit(n),
                        Err(e) => TokenKind::Error(format!("invalid binary: {e}")),
                    };
                }
                _ => {}
            }
        }

        // Collect remaining integer digits
        while let Some(ch) = self.peek() {
            if ch.is_ascii_digit() {
                num_str.push(ch);
                self.advance();
            } else {
                break;
            }
        }

        // Check for float (dot followed by digit)
        if self.peek() == Some('.') && self.peek_ahead(1).is_some_and(|c| c.is_ascii_digit()) {
            // But not if next is ".." (range operator in HV mode)
            if self.peek_ahead(1) != Some('.') {
                num_str.push('.');
                self.advance();
                while let Some(ch) = self.peek() {
                    if ch.is_ascii_digit() {
                        num_str.push(ch);
                        self.advance();
                    } else {
                        break;
                    }
                }
                // Scientific notation
                if matches!(self.peek(), Some('e') | Some('E')) {
                    num_str.push('e');
                    self.advance();
                    if matches!(self.peek(), Some('+') | Some('-')) {
                        // invariant: peek() returned Some, so advance() will return Some
                        num_str.push(self.advance().expect("invariant: peek() confirmed char is present"));
                    }
                    while let Some(ch) = self.peek() {
                        if ch.is_ascii_digit() {
                            num_str.push(ch);
                            self.advance();
                        } else {
                            break;
                        }
                    }
                }
                return match num_str.parse::<f64>() {
                    Ok(n) => TokenKind::Float(n),
                    Err(e) => TokenKind::Error(format!("invalid float: {e}")),
                };
            }
        }

        match num_str.parse::<i64>() {
            Ok(n) => TokenKind::Integer(n),
            Err(e) => TokenKind::Error(format!("invalid integer: {e}")),
        }
    }

    /// Read an identifier or keyword. In TANGLE mode, `s` followed by digits
    /// is a generator token (e.g. s1, s23).
    fn read_word(&mut self, first: char) -> TokenKind {
        let mut word = String::new();
        word.push(first);
        while let Some(ch) = self.peek() {
            if ch.is_ascii_alphanumeric() || ch == '_' {
                word.push(ch);
                self.advance();
            } else {
                break;
            }
        }

        // Generator tokens: s followed by digits only (e.g. s1, s23)
        // Must be exactly "s" + digits with no other letters
        if word.starts_with('s')
            && word.len() > 1
            && word[1..].chars().all(|c| c.is_ascii_digit())
            && let Ok(n) = word[1..].parse::<u32>()
        {
            return TokenKind::Generator(n);
        }

        // TANGLE keywords (available in all modes)
        match word.as_str() {
            "def" => TokenKind::Def,
            "weave" => TokenKind::Weave,
            "into" => TokenKind::Into,
            "yield" => TokenKind::Yield,
            "strands" => TokenKind::Strands,
            "compute" => TokenKind::Compute,
            "assert" => TokenKind::Assert,
            "match" => TokenKind::Match,
            "with" => TokenKind::With,
            "end" => TokenKind::End,
            "let" => TokenKind::Let,
            "in" => TokenKind::In,
            "braid" => TokenKind::Braid,
            "identity" => TokenKind::Identity,
            "true" => TokenKind::True,
            "false" => TokenKind::False,
            "close" => TokenKind::Close,
            "mirror" => TokenKind::Mirror,
            "reverse" => TokenKind::Reverse,
            "simplify" => TokenKind::Simplify,
            "cap" => TokenKind::Cap,
            "cup" => TokenKind::Cup,
            "add" => TokenKind::Add,
            "harvard" => TokenKind::Harvard,

            // Harvard keywords (only meaningful in HV modes, but lexed everywhere
            // so the parser can produce good errors)
            "fn" if self.is_hv_mode() => TokenKind::Fn,
            "if" if self.is_hv_mode() => TokenKind::If,
            "else" if self.is_hv_mode() => TokenKind::Else,
            "while" if self.is_hv_mode() => TokenKind::While,
            "for" if self.is_hv_mode() => TokenKind::For,
            "return" if self.is_hv_mode() => TokenKind::Return,
            "print" if self.is_hv_mode() => TokenKind::Print,
            "module" if self.is_hv_mode() => TokenKind::Module,
            "import" if self.is_hv_mode() => TokenKind::Import,
            "as" if self.is_hv_mode() => TokenKind::As,
            "then" if self.is_hv_mode() => TokenKind::Then,

            _ => TokenKind::Ident(word),
        }
    }

    /// Read a purity marker: @pure or @total (only in HV modes).
    /// The `@` has already been consumed by the caller.
    fn read_at_marker(&mut self) -> TokenKind {
        let mut word = String::new();
        while let Some(ch) = self.peek() {
            if ch.is_ascii_alphabetic() {
                word.push(ch);
                self.advance();
            } else {
                break;
            }
        }
        match word.as_str() {
            "pure" => TokenKind::AtPure,
            "total" => TokenKind::AtTotal,
            _ => TokenKind::Error(format!("unknown marker @{word}")),
        }
    }

    /// Produce the next token.
    pub fn next_token(&mut self) -> Token {
        if let Err(msg) = self.skip_trivia() {
            let span = self.span();
            return Token {
                kind: TokenKind::Error(msg),
                span,
                text: String::new(),
            };
        }

        let span = self.span();

        let Some(ch) = self.advance() else {
            return Token {
                kind: TokenKind::Eof,
                span,
                text: String::new(),
            };
        };

        let kind = match ch {
            // String literal
            '"' => self.read_string(),

            // Number literal
            c if c.is_ascii_digit() => self.read_number(c),

            // Identifier / keyword / generator
            c if c.is_ascii_alphabetic() || c == '_' => {
                if c == '_' && !self.peek().is_some_and(|ch| ch.is_ascii_alphanumeric() || ch == '_')
                {
                    TokenKind::Underscore
                } else {
                    self.read_word(c)
                }
            }

            // @ markers
            '@' if self.is_hv_mode() => self.read_at_marker(),

            // Two-character operators (check before single-char)
            '>' if self.peek() == Some('>') => {
                self.advance();
                TokenKind::Pipeline
            }
            '>' if self.peek() == Some('=') && self.is_hv_mode() => {
                self.advance();
                TokenKind::GtEq
            }
            '=' if self.peek() == Some('>') => {
                self.advance();
                TokenKind::FatArrow
            }
            '=' if self.peek() == Some('=') => {
                self.advance();
                TokenKind::EqEq
            }
            '!' if self.peek() == Some('=') && self.is_hv_mode() => {
                self.advance();
                TokenKind::BangEq
            }
            '<' if self.peek() == Some('=') && self.is_hv_mode() => {
                self.advance();
                TokenKind::LtEq
            }
            '&' if self.peek() == Some('&') && self.is_hv_mode() => {
                self.advance();
                TokenKind::AmpAmp
            }
            '|' if self.peek() == Some('|') && self.is_hv_mode() => {
                self.advance();
                TokenKind::PipePipe
            }
            '+' if self.peek() == Some('=') && self.is_hv_mode() => {
                self.advance();
                TokenKind::PlusEq
            }
            '-' if self.peek() == Some('=') && self.is_hv_mode() => {
                self.advance();
                TokenKind::MinusEq
            }
            '-' if self.peek() == Some('>') && self.is_hv_mode() => {
                self.advance();
                TokenKind::Arrow
            }
            '.' if self.peek() == Some('.') && self.is_hv_mode() => {
                self.advance();
                TokenKind::DotDot
            }

            // Single-character operators
            '~' => TokenKind::Tilde,
            '+' => TokenKind::Plus,
            '-' => TokenKind::Minus,
            '*' => TokenKind::Star,
            '/' => TokenKind::Slash,
            '.' => TokenKind::Dot,
            '|' => TokenKind::Pipe,
            '>' => TokenKind::Gt,
            '<' => TokenKind::Lt,
            '^' => TokenKind::Caret,
            '=' => TokenKind::Eq,
            '!' => TokenKind::Bang,
            ',' => TokenKind::Comma,
            ':' => TokenKind::Colon,
            '%' if self.is_hv_mode() => TokenKind::Percent,

            // Delimiters with mode management
            '(' => TokenKind::LParen,
            ')' => TokenKind::RParen,
            '[' => TokenKind::LBracket,
            ']' => TokenKind::RBracket,

            '{' => {
                // Track brace depth in current mode frame
                if let Some(frame) = self.mode_stack.last_mut() {
                    frame.brace_depth += 1;
                }
                TokenKind::LBrace
            }

            '}' => {
                // Decrement brace depth; pop mode if we've closed the injection block
                let should_pop = if let Some(frame) = self.mode_stack.last_mut() {
                    frame.brace_depth = frame.brace_depth.saturating_sub(1);
                    // Pop if we're in an injected mode and depth hits 0
                    frame.brace_depth == 0 && self.mode_stack.len() > 1
                } else {
                    false
                };
                if should_pop {
                    self.mode_stack.pop();
                }
                TokenKind::RBrace
            }

            _ => TokenKind::Error(format!("unexpected character '{ch}'")),
        };

        // Mode switching: if we just produced Add or Harvard, and the next
        // non-whitespace char is '{', push a new mode frame.
        if matches!(kind, TokenKind::Add | TokenKind::Harvard) {
            // Peek ahead past whitespace to see if '{' follows
            let mut lookahead = self.pos;
            while lookahead < self.src.len() && self.src[lookahead].is_ascii_whitespace() {
                lookahead += 1;
            }
            if lookahead < self.src.len() && self.src[lookahead] == '{' {
                let new_mode = if kind == TokenKind::Add {
                    Mode::HvData
                } else {
                    Mode::HvControl
                };
                self.mode_stack.push(ModeFrame {
                    mode: new_mode,
                    brace_depth: 0,
                });
            }
        }

        let text = self.src[span.offset..self.pos].iter().collect();

        Token { kind, span, text }
    }

    /// Tokenize the entire input into a Vec<Token>.
    pub fn tokenize(source: &str) -> Vec<Token> {
        let mut lexer = Lexer::new(source);
        let mut tokens = Vec::new();
        loop {
            let tok = lexer.next_token();
            let is_eof = tok.kind == TokenKind::Eof;
            tokens.push(tok);
            if is_eof {
                break;
            }
        }
        tokens
    }

    /// Return the current mode (for testing).
    pub fn mode(&self) -> Mode {
        self.current_mode()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tok_kinds(src: &str) -> Vec<TokenKind> {
        Lexer::tokenize(src)
            .into_iter()
            .map(|t| t.kind)
            .filter(|k| !matches!(k, TokenKind::Eof))
            .collect()
    }

    // ----- Basic tokens -----

    #[test]
    fn test_keywords() {
        let kinds = tok_kinds("def weave into yield strands compute assert");
        assert_eq!(
            kinds,
            vec![
                TokenKind::Def,
                TokenKind::Weave,
                TokenKind::Into,
                TokenKind::Yield,
                TokenKind::Strands,
                TokenKind::Compute,
                TokenKind::Assert,
            ]
        );
    }

    #[test]
    fn test_more_keywords() {
        let kinds = tok_kinds("match with end let in braid identity true false");
        assert_eq!(
            kinds,
            vec![
                TokenKind::Match,
                TokenKind::With,
                TokenKind::End,
                TokenKind::Let,
                TokenKind::In,
                TokenKind::Braid,
                TokenKind::Identity,
                TokenKind::True,
                TokenKind::False,
            ]
        );
    }

    #[test]
    fn test_unary_keywords() {
        let kinds = tok_kinds("close mirror reverse simplify cap cup");
        assert_eq!(
            kinds,
            vec![
                TokenKind::Close,
                TokenKind::Mirror,
                TokenKind::Reverse,
                TokenKind::Simplify,
                TokenKind::Cap,
                TokenKind::Cup,
            ]
        );
    }

    // ----- Generator tokens -----

    #[test]
    fn test_generators() {
        let kinds = tok_kinds("s1 s2 s23 s100");
        assert_eq!(
            kinds,
            vec![
                TokenKind::Generator(1),
                TokenKind::Generator(2),
                TokenKind::Generator(23),
                TokenKind::Generator(100),
            ]
        );
    }

    #[test]
    fn test_s_identifier_not_generator() {
        // "s" alone is an identifier, not a generator
        let kinds = tok_kinds("s sab");
        assert_eq!(
            kinds,
            vec![
                TokenKind::Ident("s".to_string()),
                TokenKind::Ident("sab".to_string()),
            ]
        );
    }

    // ----- Operators -----

    #[test]
    fn test_operators() {
        let kinds = tok_kinds(">> == ~ + - * / . | > < ^ = => !");
        assert_eq!(
            kinds,
            vec![
                TokenKind::Pipeline,
                TokenKind::EqEq,
                TokenKind::Tilde,
                TokenKind::Plus,
                TokenKind::Minus,
                TokenKind::Star,
                TokenKind::Slash,
                TokenKind::Dot,
                TokenKind::Pipe,
                TokenKind::Gt,
                TokenKind::Lt,
                TokenKind::Caret,
                TokenKind::Eq,
                TokenKind::FatArrow,
                TokenKind::Bang,
            ]
        );
    }

    #[test]
    fn test_delimiters() {
        let kinds = tok_kinds("( ) [ ] { } , : _");
        assert_eq!(
            kinds,
            vec![
                TokenKind::LParen,
                TokenKind::RParen,
                TokenKind::LBracket,
                TokenKind::RBracket,
                TokenKind::LBrace,
                TokenKind::RBrace,
                TokenKind::Comma,
                TokenKind::Colon,
                TokenKind::Underscore,
            ]
        );
    }

    // ----- Literals -----

    #[test]
    fn test_integers() {
        let kinds = tok_kinds("0 1 42 1000");
        assert_eq!(
            kinds,
            vec![
                TokenKind::Integer(0),
                TokenKind::Integer(1),
                TokenKind::Integer(42),
                TokenKind::Integer(1000),
            ]
        );
    }

    #[test]
    fn test_floats() {
        let kinds = tok_kinds("3.14 0.5 1.0");
        assert_eq!(
            kinds,
            vec![
                TokenKind::Float(3.14),
                TokenKind::Float(0.5),
                TokenKind::Float(1.0),
            ]
        );
    }

    #[test]
    fn test_hex_literal() {
        let kinds = tok_kinds("0xFF 0x1a2b");
        assert_eq!(
            kinds,
            vec![TokenKind::HexLit(0xFF), TokenKind::HexLit(0x1a2b)]
        );
    }

    #[test]
    fn test_binary_literal() {
        let kinds = tok_kinds("0b1010 0b11");
        assert_eq!(
            kinds,
            vec![TokenKind::BinaryLit(0b1010), TokenKind::BinaryLit(0b11)]
        );
    }

    #[test]
    fn test_string_literal() {
        let kinds = tok_kinds(r#""hello" "world\n""#);
        assert_eq!(
            kinds,
            vec![
                TokenKind::StringLit("hello".to_string()),
                TokenKind::StringLit("world\n".to_string()),
            ]
        );
    }

    // ----- Comments -----

    #[test]
    fn test_line_comment() {
        let kinds = tok_kinds("def # this is a comment\nweave");
        assert_eq!(kinds, vec![TokenKind::Def, TokenKind::Weave]);
    }

    #[test]
    fn test_block_comment() {
        let kinds = tok_kinds("def (* comment *) weave");
        assert_eq!(kinds, vec![TokenKind::Def, TokenKind::Weave]);
    }

    #[test]
    fn test_nested_block_comment() {
        let kinds = tok_kinds("def (* outer (* inner *) still outer *) weave");
        assert_eq!(kinds, vec![TokenKind::Def, TokenKind::Weave]);
    }

    // ----- Braid literal expression -----

    #[test]
    fn test_braid_literal_tokens() {
        let kinds = tok_kinds("braid[s1, s2^-1, s1]");
        assert_eq!(
            kinds,
            vec![
                TokenKind::Braid,
                TokenKind::LBracket,
                TokenKind::Generator(1),
                TokenKind::Comma,
                TokenKind::Generator(2),
                TokenKind::Caret,
                TokenKind::Minus,
                TokenKind::Integer(1),
                TokenKind::Comma,
                TokenKind::Generator(1),
                TokenKind::RBracket,
            ]
        );
    }

    // ----- Crossing and twist -----

    #[test]
    fn test_crossing() {
        let kinds = tok_kinds("(a > b)");
        assert_eq!(
            kinds,
            vec![
                TokenKind::LParen,
                TokenKind::Ident("a".to_string()),
                TokenKind::Gt,
                TokenKind::Ident("b".to_string()),
                TokenKind::RParen,
            ]
        );
    }

    #[test]
    fn test_twist() {
        let kinds = tok_kinds("(~a)");
        assert_eq!(
            kinds,
            vec![
                TokenKind::LParen,
                TokenKind::Tilde,
                TokenKind::Ident("a".to_string()),
                TokenKind::RParen,
            ]
        );
    }

    // ----- Mode switching -----

    #[test]
    fn test_add_block_mode_switch() {
        let src = "add{1 + 2}";
        let mut lexer = Lexer::new(src);

        // "add" — still in Tangle mode when produced, but pushes HvData for next
        let t = lexer.next_token();
        assert_eq!(t.kind, TokenKind::Add);

        // "{" — now in HvData mode
        let t = lexer.next_token();
        assert_eq!(t.kind, TokenKind::LBrace);
        assert_eq!(lexer.mode(), Mode::HvData);

        // "1"
        let t = lexer.next_token();
        assert_eq!(t.kind, TokenKind::Integer(1));

        // "+" (in HvData mode, still Plus)
        let t = lexer.next_token();
        assert_eq!(t.kind, TokenKind::Plus);

        // "2"
        let t = lexer.next_token();
        assert_eq!(t.kind, TokenKind::Integer(2));

        // "}" — pops back to Tangle
        let t = lexer.next_token();
        assert_eq!(t.kind, TokenKind::RBrace);
        assert_eq!(lexer.mode(), Mode::Tangle);
    }

    #[test]
    fn test_harvard_block_mode_switch() {
        let src = "harvard{ fn f() { return 1 } }";
        let mut lexer = Lexer::new(src);

        let t = lexer.next_token();
        assert_eq!(t.kind, TokenKind::Harvard);

        let t = lexer.next_token();
        assert_eq!(t.kind, TokenKind::LBrace);
        assert_eq!(lexer.mode(), Mode::HvControl);

        // "fn" is a keyword in HV mode
        let t = lexer.next_token();
        assert_eq!(t.kind, TokenKind::Fn);

        let t = lexer.next_token();
        assert_eq!(t.kind, TokenKind::Ident("f".to_string()));

        let t = lexer.next_token();
        assert_eq!(t.kind, TokenKind::LParen);
        let t = lexer.next_token();
        assert_eq!(t.kind, TokenKind::RParen);

        let t = lexer.next_token();
        assert_eq!(t.kind, TokenKind::LBrace);
        // Still HvControl (inner brace, depth=2)
        assert_eq!(lexer.mode(), Mode::HvControl);

        let t = lexer.next_token();
        assert_eq!(t.kind, TokenKind::Return);
        let t = lexer.next_token();
        assert_eq!(t.kind, TokenKind::Integer(1));

        let t = lexer.next_token();
        assert_eq!(t.kind, TokenKind::RBrace);
        // Still HvControl (depth=1 now)
        assert_eq!(lexer.mode(), Mode::HvControl);

        let t = lexer.next_token();
        assert_eq!(t.kind, TokenKind::RBrace);
        // Back to Tangle
        assert_eq!(lexer.mode(), Mode::Tangle);
    }

    #[test]
    fn test_harvard_operators() {
        let src = "harvard{ x && y || z != w <= 1 >= 2 }";
        let kinds = tok_kinds(src);
        assert_eq!(
            kinds,
            vec![
                TokenKind::Harvard,
                TokenKind::LBrace,
                TokenKind::Ident("x".to_string()),
                TokenKind::AmpAmp,
                TokenKind::Ident("y".to_string()),
                TokenKind::PipePipe,
                TokenKind::Ident("z".to_string()),
                TokenKind::BangEq,
                TokenKind::Ident("w".to_string()),
                TokenKind::LtEq,
                TokenKind::Integer(1),
                TokenKind::GtEq,
                TokenKind::Integer(2),
                TokenKind::RBrace,
            ]
        );
    }

    #[test]
    fn test_purity_markers() {
        let src = "harvard{ fn f(): Int @pure { return 1 } }";
        let kinds = tok_kinds(src);
        assert!(kinds.contains(&TokenKind::AtPure));
    }

    #[test]
    fn test_hv_comments() {
        let src = "harvard{ // line comment\n1 /* block */ + 2 }";
        let kinds = tok_kinds(src);
        assert_eq!(
            kinds,
            vec![
                TokenKind::Harvard,
                TokenKind::LBrace,
                TokenKind::Integer(1),
                TokenKind::Plus,
                TokenKind::Integer(2),
                TokenKind::RBrace,
            ]
        );
    }

    #[test]
    fn test_dotdot_range() {
        let src = "harvard{ for i in 0..10 { } }";
        let kinds = tok_kinds(src);
        assert!(kinds.contains(&TokenKind::DotDot));
    }

    #[test]
    fn test_plus_eq_minus_eq() {
        let src = "harvard{ x += 1 y -= 2 }";
        let kinds = tok_kinds(src);
        assert!(kinds.contains(&TokenKind::PlusEq));
        assert!(kinds.contains(&TokenKind::MinusEq));
    }

    // ----- Full program examples -----

    #[test]
    fn test_definition() {
        let kinds = tok_kinds("def trefoil = braid[s1, s1, s1]");
        assert_eq!(
            kinds,
            vec![
                TokenKind::Def,
                TokenKind::Ident("trefoil".to_string()),
                TokenKind::Eq,
                TokenKind::Braid,
                TokenKind::LBracket,
                TokenKind::Generator(1),
                TokenKind::Comma,
                TokenKind::Generator(1),
                TokenKind::Comma,
                TokenKind::Generator(1),
                TokenKind::RBracket,
            ]
        );
    }

    #[test]
    fn test_pattern_match() {
        let src = r#"def length(w) = match w with
  | identity => 0
  | s1 . rest => 1 + length(rest)
end"#;
        let kinds = tok_kinds(src);
        assert_eq!(kinds[0], TokenKind::Def);
        assert!(kinds.contains(&TokenKind::Match));
        assert!(kinds.contains(&TokenKind::With));
        assert!(kinds.contains(&TokenKind::Identity));
        assert!(kinds.contains(&TokenKind::FatArrow));
        assert!(kinds.contains(&TokenKind::End));
    }

    #[test]
    fn test_weave_block() {
        let src = "weave strands a, b into (a > b) yield strands b, a";
        let kinds = tok_kinds(src);
        assert_eq!(kinds[0], TokenKind::Weave);
        assert_eq!(kinds[1], TokenKind::Strands);
        assert!(kinds.contains(&TokenKind::Into));
        assert!(kinds.contains(&TokenKind::Yield));
    }

    #[test]
    fn test_compute() {
        let kinds = tok_kinds("compute jones(close(braid[s1, s1, s1]))");
        assert_eq!(kinds[0], TokenKind::Compute);
        assert_eq!(kinds[1], TokenKind::Ident("jones".to_string()));
    }

    #[test]
    fn test_assert_simplify() {
        let kinds = tok_kinds("assert simplify(braid[s1, s1^-1]) == identity");
        assert_eq!(kinds[0], TokenKind::Assert);
        assert_eq!(kinds[1], TokenKind::Simplify);
        assert!(kinds.contains(&TokenKind::EqEq));
        assert!(kinds.contains(&TokenKind::Identity));
    }

    #[test]
    fn test_mixed_tangle_and_add() {
        let src = "assert add{2 + 3} == 5";
        let kinds = tok_kinds(src);
        assert_eq!(
            kinds,
            vec![
                TokenKind::Assert,
                TokenKind::Add,
                TokenKind::LBrace,
                TokenKind::Integer(2),
                TokenKind::Plus,
                TokenKind::Integer(3),
                TokenKind::RBrace,
                TokenKind::EqEq,
                TokenKind::Integer(5),
            ]
        );
    }

    #[test]
    fn test_harvard_function_with_purity() {
        let src = r#"harvard{
  fn double(x: Int): Int @pure {
    return x * 2
  }
}"#;
        let kinds = tok_kinds(src);
        assert_eq!(kinds[0], TokenKind::Harvard);
        assert!(kinds.contains(&TokenKind::Fn));
        assert!(kinds.contains(&TokenKind::AtPure));
        assert!(kinds.contains(&TokenKind::Return));
        assert!(kinds.contains(&TokenKind::Colon));
    }

    // ----- Span tracking -----

    #[test]
    fn test_span_tracking() {
        let tokens = Lexer::tokenize("def\n  x");
        assert_eq!(tokens[0].span.line, 1);
        assert_eq!(tokens[0].span.col, 1);
        assert_eq!(tokens[1].span.line, 2);
        assert_eq!(tokens[1].span.col, 3);
    }

    // ----- Error recovery -----

    #[test]
    fn test_unexpected_char() {
        let kinds = tok_kinds("def $ weave");
        assert_eq!(kinds[0], TokenKind::Def);
        assert!(matches!(kinds[1], TokenKind::Error(_)));
        assert_eq!(kinds[2], TokenKind::Weave);
    }

    #[test]
    fn test_unterminated_string() {
        let kinds = tok_kinds(r#""unterminated"#);
        assert!(matches!(kinds[0], TokenKind::Error(_)));
    }

    #[test]
    fn test_unterminated_block_comment() {
        let kinds = tok_kinds("(* unterminated");
        assert!(matches!(kinds[0], TokenKind::Error(_)));
    }

    // ----- Edge cases -----

    #[test]
    fn test_empty_input() {
        let kinds = tok_kinds("");
        assert!(kinds.is_empty());
    }

    #[test]
    fn test_whitespace_only() {
        let kinds = tok_kinds("   \n\t  ");
        assert!(kinds.is_empty());
    }

    #[test]
    fn test_nested_add_in_assert() {
        // From spec examples
        let src = "assert add{double(21)} == 42";
        let kinds = tok_kinds(src);
        assert_eq!(kinds[0], TokenKind::Assert);
        assert_eq!(kinds[1], TokenKind::Add);
        assert_eq!(kinds[2], TokenKind::LBrace);
        // double is an identifier inside HvData
        assert_eq!(kinds[3], TokenKind::Ident("double".to_string()));
    }

    #[test]
    fn test_arrow_in_harvard() {
        let src = "harvard{ Fn(Int) -> Int }";
        let kinds = tok_kinds(src);
        assert!(kinds.contains(&TokenKind::Arrow));
    }

    // =====================================================================
    // Comprehensive lexer tests
    // SPDX-License-Identifier: MPL-2.0
    // =====================================================================

    // ----- 1. All TANGLE keywords (exhaustive) -----

    #[test]
    fn test_all_tangle_keywords_exhaustive() {
        let kinds = tok_kinds(
            "def weave into yield strands compute assert match with end \
             let in braid identity true false close mirror reverse simplify cap cup",
        );
        assert_eq!(
            kinds,
            vec![
                TokenKind::Def,
                TokenKind::Weave,
                TokenKind::Into,
                TokenKind::Yield,
                TokenKind::Strands,
                TokenKind::Compute,
                TokenKind::Assert,
                TokenKind::Match,
                TokenKind::With,
                TokenKind::End,
                TokenKind::Let,
                TokenKind::In,
                TokenKind::Braid,
                TokenKind::Identity,
                TokenKind::True,
                TokenKind::False,
                TokenKind::Close,
                TokenKind::Mirror,
                TokenKind::Reverse,
                TokenKind::Simplify,
                TokenKind::Cap,
                TokenKind::Cup,
            ]
        );
    }

    #[test]
    fn test_add_and_harvard_keywords() {
        // These are keywords in all modes but trigger mode switching
        let kinds = tok_kinds("add harvard");
        assert_eq!(kinds, vec![TokenKind::Add, TokenKind::Harvard]);
    }

    #[test]
    fn test_keyword_case_sensitivity() {
        // Keywords are lowercase only; uppercase variants should be identifiers
        let kinds = tok_kinds("Def DEF dEf Weave BRAID True FALSE");
        for k in &kinds {
            assert!(
                matches!(k, TokenKind::Ident(_)),
                "expected Ident, got {:?}",
                k
            );
        }
    }

    // ----- 2. Invariant names (lexed as identifiers in Tangle mode) -----

    #[test]
    fn test_invariant_names_as_identifiers() {
        // jones, alexander, homfly, kauffman, writhe, linking are not keywords;
        // they lex as identifiers and are resolved semantically
        let kinds = tok_kinds("jones alexander homfly kauffman writhe linking");
        assert_eq!(
            kinds,
            vec![
                TokenKind::Ident("jones".to_string()),
                TokenKind::Ident("alexander".to_string()),
                TokenKind::Ident("homfly".to_string()),
                TokenKind::Ident("kauffman".to_string()),
                TokenKind::Ident("writhe".to_string()),
                TokenKind::Ident("linking".to_string()),
            ]
        );
    }

    #[test]
    fn test_compute_with_each_invariant() {
        for name in &["jones", "alexander", "homfly", "kauffman", "writhe", "linking"] {
            let src = format!("compute {}(close(braid[s1]))", name);
            let kinds = tok_kinds(&src);
            assert_eq!(kinds[0], TokenKind::Compute);
            assert_eq!(kinds[1], TokenKind::Ident(name.to_string()));
            assert_eq!(kinds[2], TokenKind::LParen);
        }
    }

    // ----- 3. All operators (exhaustive) -----

    #[test]
    fn test_all_tangle_operators_individually() {
        assert_eq!(tok_kinds("."), vec![TokenKind::Dot]);
        assert_eq!(tok_kinds("|"), vec![TokenKind::Pipe]);
        assert_eq!(tok_kinds("+"), vec![TokenKind::Plus]);
        assert_eq!(tok_kinds("-"), vec![TokenKind::Minus]);
        assert_eq!(tok_kinds("*"), vec![TokenKind::Star]);
        assert_eq!(tok_kinds("/"), vec![TokenKind::Slash]);
        assert_eq!(tok_kinds("=="), vec![TokenKind::EqEq]);
        assert_eq!(tok_kinds("~"), vec![TokenKind::Tilde]);
        assert_eq!(tok_kinds(">>"), vec![TokenKind::Pipeline]);
        assert_eq!(tok_kinds(">"), vec![TokenKind::Gt]);
        assert_eq!(tok_kinds("<"), vec![TokenKind::Lt]);
        assert_eq!(tok_kinds("^"), vec![TokenKind::Caret]);
        assert_eq!(tok_kinds("=>"), vec![TokenKind::FatArrow]);
        assert_eq!(tok_kinds("="), vec![TokenKind::Eq]);
        assert_eq!(tok_kinds("!"), vec![TokenKind::Bang]);
    }

    #[test]
    fn test_pipeline_vs_two_gts() {
        // >> should be Pipeline, not two Gt tokens
        let kinds = tok_kinds(">>");
        assert_eq!(kinds, vec![TokenKind::Pipeline]);
        assert_eq!(kinds.len(), 1);
    }

    #[test]
    fn test_fat_arrow_vs_eq_gt() {
        // => should be FatArrow, not Eq + Gt
        let kinds = tok_kinds("=>");
        assert_eq!(kinds, vec![TokenKind::FatArrow]);
        assert_eq!(kinds.len(), 1);
    }

    #[test]
    fn test_eqeq_vs_two_eq() {
        // == should be EqEq, not two Eq tokens
        let kinds = tok_kinds("==");
        assert_eq!(kinds, vec![TokenKind::EqEq]);
        assert_eq!(kinds.len(), 1);
    }

    #[test]
    fn test_operators_without_spaces() {
        // Operators adjacent to identifiers
        let kinds = tok_kinds("a+b");
        assert_eq!(
            kinds,
            vec![
                TokenKind::Ident("a".to_string()),
                TokenKind::Plus,
                TokenKind::Ident("b".to_string()),
            ]
        );
    }

    #[test]
    fn test_harvard_only_operators() {
        // These multi-char operators only work in HV mode
        let src = "harvard{ && || != <= >= % += -= .. -> }";
        let kinds = tok_kinds(src);
        assert!(kinds.contains(&TokenKind::AmpAmp));
        assert!(kinds.contains(&TokenKind::PipePipe));
        assert!(kinds.contains(&TokenKind::BangEq));
        assert!(kinds.contains(&TokenKind::LtEq));
        assert!(kinds.contains(&TokenKind::GtEq));
        assert!(kinds.contains(&TokenKind::Percent));
        assert!(kinds.contains(&TokenKind::PlusEq));
        assert!(kinds.contains(&TokenKind::MinusEq));
        assert!(kinds.contains(&TokenKind::DotDot));
        assert!(kinds.contains(&TokenKind::Arrow));
    }

    #[test]
    fn test_ampamp_in_tangle_mode_is_error() {
        // In Tangle mode, & is an unexpected character (no && operator)
        let kinds = tok_kinds("&&");
        assert!(matches!(kinds[0], TokenKind::Error(_)));
    }

    #[test]
    fn test_percent_in_tangle_mode_is_error() {
        // % is only valid in HV mode
        let kinds = tok_kinds("%");
        assert!(matches!(kinds[0], TokenKind::Error(_)));
    }

    // ----- 4. All delimiters -----

    #[test]
    fn test_all_delimiters_individually() {
        assert_eq!(tok_kinds("("), vec![TokenKind::LParen]);
        assert_eq!(tok_kinds(")"), vec![TokenKind::RParen]);
        assert_eq!(tok_kinds("["), vec![TokenKind::LBracket]);
        assert_eq!(tok_kinds("]"), vec![TokenKind::RBracket]);
        assert_eq!(tok_kinds("{"), vec![TokenKind::LBrace]);
        assert_eq!(tok_kinds("}"), vec![TokenKind::RBrace]);
        assert_eq!(tok_kinds(","), vec![TokenKind::Comma]);
        assert_eq!(tok_kinds(":"), vec![TokenKind::Colon]);
        assert_eq!(tok_kinds(";"), vec![TokenKind::Error("unexpected character ';'".to_string())]);
    }

    #[test]
    fn test_nested_delimiters() {
        let kinds = tok_kinds("(([{}]))");
        assert_eq!(
            kinds,
            vec![
                TokenKind::LParen,
                TokenKind::LParen,
                TokenKind::LBracket,
                TokenKind::LBrace,
                TokenKind::RBrace,
                TokenKind::RBracket,
                TokenKind::RParen,
                TokenKind::RParen,
            ]
        );
    }

    #[test]
    fn test_underscore_standalone() {
        // Standalone _ is Underscore token, not an identifier
        let kinds = tok_kinds("_");
        assert_eq!(kinds, vec![TokenKind::Underscore]);
    }

    #[test]
    fn test_underscore_prefix_identifier() {
        // _foo is an identifier, not Underscore + Ident
        let kinds = tok_kinds("_foo");
        assert_eq!(kinds, vec![TokenKind::Ident("_foo".to_string())]);
    }

    // ----- 5. Braid generators -----

    #[test]
    fn test_generator_single_digit() {
        assert_eq!(tok_kinds("s1"), vec![TokenKind::Generator(1)]);
        assert_eq!(tok_kinds("s2"), vec![TokenKind::Generator(2)]);
        assert_eq!(tok_kinds("s3"), vec![TokenKind::Generator(3)]);
        assert_eq!(tok_kinds("s9"), vec![TokenKind::Generator(9)]);
    }

    #[test]
    fn test_generator_multi_digit() {
        assert_eq!(tok_kinds("s10"), vec![TokenKind::Generator(10)]);
        assert_eq!(tok_kinds("s23"), vec![TokenKind::Generator(23)]);
        assert_eq!(tok_kinds("s100"), vec![TokenKind::Generator(100)]);
        assert_eq!(tok_kinds("s999"), vec![TokenKind::Generator(999)]);
    }

    #[test]
    fn test_generator_zero() {
        // s0 should still be a valid generator
        assert_eq!(tok_kinds("s0"), vec![TokenKind::Generator(0)]);
    }

    #[test]
    fn test_generator_not_s_alone() {
        // "s" alone is an identifier
        assert_eq!(tok_kinds("s"), vec![TokenKind::Ident("s".to_string())]);
    }

    #[test]
    fn test_generator_not_s_with_letters() {
        // s followed by letters is an identifier
        assert_eq!(tok_kinds("sab"), vec![TokenKind::Ident("sab".to_string())]);
        assert_eq!(tok_kinds("str"), vec![TokenKind::Ident("str".to_string())]);
        assert_eq!(
            tok_kinds("simplify"),
            vec![TokenKind::Simplify]
        );
    }

    #[test]
    fn test_generator_mixed_letters_digits() {
        // s1a has letters after digits, so the whole thing is an identifier
        assert_eq!(tok_kinds("s1a"), vec![TokenKind::Ident("s1a".to_string())]);
    }

    #[test]
    fn test_generator_sequence() {
        let kinds = tok_kinds("s1 s2 s1");
        assert_eq!(
            kinds,
            vec![
                TokenKind::Generator(1),
                TokenKind::Generator(2),
                TokenKind::Generator(1),
            ]
        );
    }

    // ----- 6. Generator exponents -----

    #[test]
    fn test_generator_positive_exponent() {
        // s1^2 lexes as Generator(1), Caret, Integer(2)
        let kinds = tok_kinds("s1^2");
        assert_eq!(
            kinds,
            vec![
                TokenKind::Generator(1),
                TokenKind::Caret,
                TokenKind::Integer(2),
            ]
        );
    }

    #[test]
    fn test_generator_negative_exponent() {
        // s1^-1 lexes as Generator(1), Caret, Minus, Integer(1)
        let kinds = tok_kinds("s1^-1");
        assert_eq!(
            kinds,
            vec![
                TokenKind::Generator(1),
                TokenKind::Caret,
                TokenKind::Minus,
                TokenKind::Integer(1),
            ]
        );
    }

    #[test]
    fn test_generator_exponent_in_braid() {
        let kinds = tok_kinds("braid[s1^2, s2^-1]");
        assert_eq!(
            kinds,
            vec![
                TokenKind::Braid,
                TokenKind::LBracket,
                TokenKind::Generator(1),
                TokenKind::Caret,
                TokenKind::Integer(2),
                TokenKind::Comma,
                TokenKind::Generator(2),
                TokenKind::Caret,
                TokenKind::Minus,
                TokenKind::Integer(1),
                TokenKind::RBracket,
            ]
        );
    }

    #[test]
    fn test_generator_large_exponent() {
        let kinds = tok_kinds("s3^10");
        assert_eq!(
            kinds,
            vec![
                TokenKind::Generator(3),
                TokenKind::Caret,
                TokenKind::Integer(10),
            ]
        );
    }

    // ----- 7. Integer literals -----

    #[test]
    fn test_integer_zero() {
        assert_eq!(tok_kinds("0"), vec![TokenKind::Integer(0)]);
    }

    #[test]
    fn test_integer_large() {
        assert_eq!(tok_kinds("999999"), vec![TokenKind::Integer(999999)]);
    }

    #[test]
    fn test_integer_negative_is_minus_plus_int() {
        // Negative numbers are lexed as Minus + Integer (unary minus is parser's job)
        let kinds = tok_kinds("-42");
        assert_eq!(kinds, vec![TokenKind::Minus, TokenKind::Integer(42)]);
    }

    #[test]
    fn test_hex_literals() {
        assert_eq!(tok_kinds("0x0"), vec![TokenKind::HexLit(0)]);
        assert_eq!(tok_kinds("0xff"), vec![TokenKind::HexLit(255)]);
        assert_eq!(tok_kinds("0xFF"), vec![TokenKind::HexLit(255)]);
        assert_eq!(tok_kinds("0xDEAD"), vec![TokenKind::HexLit(0xDEAD)]);
    }

    #[test]
    fn test_hex_with_underscores() {
        assert_eq!(tok_kinds("0xFF_FF"), vec![TokenKind::HexLit(0xFFFF)]);
    }

    #[test]
    fn test_empty_hex_is_error() {
        let kinds = tok_kinds("0x");
        assert!(matches!(kinds[0], TokenKind::Error(_)));
    }

    #[test]
    fn test_binary_literals() {
        assert_eq!(tok_kinds("0b0"), vec![TokenKind::BinaryLit(0)]);
        assert_eq!(tok_kinds("0b1"), vec![TokenKind::BinaryLit(1)]);
        assert_eq!(tok_kinds("0b1010"), vec![TokenKind::BinaryLit(0b1010)]);
        assert_eq!(tok_kinds("0b11111111"), vec![TokenKind::BinaryLit(255)]);
    }

    #[test]
    fn test_binary_with_underscores() {
        assert_eq!(tok_kinds("0b1010_0101"), vec![TokenKind::BinaryLit(0b10100101)]);
    }

    #[test]
    fn test_empty_binary_is_error() {
        let kinds = tok_kinds("0b");
        assert!(matches!(kinds[0], TokenKind::Error(_)));
    }

    // ----- 8. Float literals -----

    #[test]
    fn test_float_basic() {
        assert_eq!(tok_kinds("3.14"), vec![TokenKind::Float(3.14)]);
        assert_eq!(tok_kinds("0.0"), vec![TokenKind::Float(0.0)]);
        assert_eq!(tok_kinds("1.0"), vec![TokenKind::Float(1.0)]);
    }

    #[test]
    fn test_float_many_decimals() {
        assert_eq!(tok_kinds("3.14159265"), vec![TokenKind::Float(3.14159265)]);
    }

    #[test]
    fn test_float_scientific_notation() {
        assert_eq!(tok_kinds("1.0e10"), vec![TokenKind::Float(1.0e10)]);
        assert_eq!(tok_kinds("2.5E3"), vec![TokenKind::Float(2.5e3)]);
    }

    #[test]
    fn test_float_scientific_positive_exponent() {
        assert_eq!(tok_kinds("1.0e+5"), vec![TokenKind::Float(1.0e+5)]);
    }

    #[test]
    fn test_float_scientific_negative_exponent() {
        assert_eq!(tok_kinds("1.0e-3"), vec![TokenKind::Float(1.0e-3)]);
    }

    #[test]
    fn test_integer_dot_no_digit_is_int_dot() {
        // "1." followed by non-digit should be Integer(1) then Dot
        let kinds = tok_kinds("1.a");
        assert_eq!(
            kinds,
            vec![
                TokenKind::Integer(1),
                TokenKind::Dot,
                TokenKind::Ident("a".to_string()),
            ]
        );
    }

    // ----- 9. String literals -----

    #[test]
    fn test_string_empty() {
        assert_eq!(
            tok_kinds(r#""""#),
            vec![TokenKind::StringLit("".to_string())]
        );
    }

    #[test]
    fn test_string_simple() {
        assert_eq!(
            tok_kinds(r#""hello world""#),
            vec![TokenKind::StringLit("hello world".to_string())]
        );
    }

    #[test]
    fn test_string_escape_newline() {
        assert_eq!(
            tok_kinds(r#""\n""#),
            vec![TokenKind::StringLit("\n".to_string())]
        );
    }

    #[test]
    fn test_string_escape_tab() {
        assert_eq!(
            tok_kinds(r#""\t""#),
            vec![TokenKind::StringLit("\t".to_string())]
        );
    }

    #[test]
    fn test_string_escape_carriage_return() {
        assert_eq!(
            tok_kinds(r#""\r""#),
            vec![TokenKind::StringLit("\r".to_string())]
        );
    }

    #[test]
    fn test_string_escape_backslash() {
        assert_eq!(
            tok_kinds(r#""\\""#),
            vec![TokenKind::StringLit("\\".to_string())]
        );
    }

    #[test]
    fn test_string_escape_quote() {
        assert_eq!(
            tok_kinds(r#""\"""#),
            vec![TokenKind::StringLit("\"".to_string())]
        );
    }

    #[test]
    fn test_string_unknown_escape() {
        // Unknown escape sequences pass through with the backslash
        assert_eq!(
            tok_kinds(r#""\z""#),
            vec![TokenKind::StringLit("\\z".to_string())]
        );
    }

    #[test]
    fn test_string_with_spaces_and_punctuation() {
        assert_eq!(
            tok_kinds(r#""hello, world! 123""#),
            vec![TokenKind::StringLit("hello, world! 123".to_string())]
        );
    }

    #[test]
    fn test_multiple_strings() {
        let kinds = tok_kinds(r#""a" "b" "c""#);
        assert_eq!(
            kinds,
            vec![
                TokenKind::StringLit("a".to_string()),
                TokenKind::StringLit("b".to_string()),
                TokenKind::StringLit("c".to_string()),
            ]
        );
    }

    // ----- 10. Line comments -----

    #[test]
    fn test_line_comment_at_start() {
        let kinds = tok_kinds("# comment\ndef");
        assert_eq!(kinds, vec![TokenKind::Def]);
    }

    #[test]
    fn test_line_comment_at_end() {
        let kinds = tok_kinds("def # trailing comment");
        assert_eq!(kinds, vec![TokenKind::Def]);
    }

    #[test]
    fn test_line_comment_with_special_chars() {
        let kinds = tok_kinds("def # !@$%^&*() comment with symbols\nweave");
        assert_eq!(kinds, vec![TokenKind::Def, TokenKind::Weave]);
    }

    #[test]
    fn test_multiple_line_comments() {
        let kinds = tok_kinds("# first\n# second\ndef");
        assert_eq!(kinds, vec![TokenKind::Def]);
    }

    #[test]
    fn test_hash_not_comment_in_hv_mode() {
        // In Harvard mode, # is not a comment character
        // It should produce an error token
        let src = "harvard{ # }";
        let kinds = tok_kinds(src);
        assert!(kinds.iter().any(|k| matches!(k, TokenKind::Error(_))));
    }

    // ----- 11. Block comments -----

    #[test]
    fn test_block_comment_single_line() {
        let kinds = tok_kinds("def (* comment *) weave");
        assert_eq!(kinds, vec![TokenKind::Def, TokenKind::Weave]);
    }

    #[test]
    fn test_block_comment_multiline() {
        let kinds = tok_kinds("def (* line1\nline2\nline3 *) weave");
        assert_eq!(kinds, vec![TokenKind::Def, TokenKind::Weave]);
    }

    #[test]
    fn test_block_comment_nested_one_level() {
        let kinds = tok_kinds("def (* outer (* inner *) outer *) weave");
        assert_eq!(kinds, vec![TokenKind::Def, TokenKind::Weave]);
    }

    #[test]
    fn test_block_comment_nested_two_levels() {
        let kinds = tok_kinds("def (* l1 (* l2 (* l3 *) l2 *) l1 *) weave");
        assert_eq!(kinds, vec![TokenKind::Def, TokenKind::Weave]);
    }

    #[test]
    fn test_block_comment_empty() {
        let kinds = tok_kinds("(**) def");
        assert_eq!(kinds, vec![TokenKind::Def]);
    }

    #[test]
    fn test_block_comment_with_stars() {
        // Stars inside block comment that aren't followed by )
        let kinds = tok_kinds("(* * ** *** *) def");
        assert_eq!(kinds, vec![TokenKind::Def]);
    }

    #[test]
    fn test_unterminated_block_comment_error() {
        let kinds = tok_kinds("(* no end");
        assert_eq!(kinds.len(), 1);
        assert!(matches!(&kinds[0], TokenKind::Error(msg) if msg.contains("unterminated")));
    }

    #[test]
    fn test_unterminated_nested_block_comment() {
        let kinds = tok_kinds("(* outer (* inner *)");
        assert!(matches!(&kinds[0], TokenKind::Error(msg) if msg.contains("unterminated")));
    }

    // ----- 12. Identifiers -----

    #[test]
    fn test_simple_identifiers() {
        let kinds = tok_kinds("foo bar baz");
        assert_eq!(
            kinds,
            vec![
                TokenKind::Ident("foo".to_string()),
                TokenKind::Ident("bar".to_string()),
                TokenKind::Ident("baz".to_string()),
            ]
        );
    }

    #[test]
    fn test_identifier_with_underscores() {
        assert_eq!(
            tok_kinds("my_var"),
            vec![TokenKind::Ident("my_var".to_string())]
        );
        assert_eq!(
            tok_kinds("_private"),
            vec![TokenKind::Ident("_private".to_string())]
        );
        assert_eq!(
            tok_kinds("__double"),
            vec![TokenKind::Ident("__double".to_string())]
        );
    }

    #[test]
    fn test_identifier_with_digits() {
        assert_eq!(
            tok_kinds("x1"),
            vec![TokenKind::Ident("x1".to_string())]
        );
        assert_eq!(
            tok_kinds("var2name"),
            vec![TokenKind::Ident("var2name".to_string())]
        );
    }

    #[test]
    fn test_identifier_single_char() {
        assert_eq!(tok_kinds("a"), vec![TokenKind::Ident("a".to_string())]);
        assert_eq!(tok_kinds("x"), vec![TokenKind::Ident("x".to_string())]);
        assert_eq!(tok_kinds("Z"), vec![TokenKind::Ident("Z".to_string())]);
    }

    #[test]
    fn test_identifier_starts_with_keyword_prefix() {
        // Words that start with a keyword but are longer should be identifiers
        assert_eq!(
            tok_kinds("define"),
            vec![TokenKind::Ident("define".to_string())]
        );
        assert_eq!(
            tok_kinds("weaver"),
            vec![TokenKind::Ident("weaver".to_string())]
        );
        assert_eq!(
            tok_kinds("matching"),
            vec![TokenKind::Ident("matching".to_string())]
        );
        assert_eq!(
            tok_kinds("letter"),
            vec![TokenKind::Ident("letter".to_string())]
        );
        assert_eq!(
            tok_kinds("endgame"),
            vec![TokenKind::Ident("endgame".to_string())]
        );
    }

    // ----- 13. Whitespace handling -----

    #[test]
    fn test_spaces_between_tokens() {
        let kinds = tok_kinds("def   weave");
        assert_eq!(kinds, vec![TokenKind::Def, TokenKind::Weave]);
    }

    #[test]
    fn test_tabs_between_tokens() {
        let kinds = tok_kinds("def\tweave");
        assert_eq!(kinds, vec![TokenKind::Def, TokenKind::Weave]);
    }

    #[test]
    fn test_newlines_between_tokens() {
        let kinds = tok_kinds("def\nweave\ninto");
        assert_eq!(
            kinds,
            vec![TokenKind::Def, TokenKind::Weave, TokenKind::Into]
        );
    }

    #[test]
    fn test_mixed_whitespace() {
        let kinds = tok_kinds("def \t \n \r\n weave");
        assert_eq!(kinds, vec![TokenKind::Def, TokenKind::Weave]);
    }

    #[test]
    fn test_no_whitespace_between_tokens() {
        // Tokens without whitespace between them
        let kinds = tok_kinds("def(weave)");
        assert_eq!(
            kinds,
            vec![
                TokenKind::Def,
                TokenKind::LParen,
                TokenKind::Weave,
                TokenKind::RParen,
            ]
        );
    }

    #[test]
    fn test_leading_whitespace() {
        let kinds = tok_kinds("   def");
        assert_eq!(kinds, vec![TokenKind::Def]);
    }

    #[test]
    fn test_trailing_whitespace() {
        let kinds = tok_kinds("def   ");
        assert_eq!(kinds, vec![TokenKind::Def]);
    }

    // ----- 14. Error cases -----

    #[test]
    fn test_unterminated_string_error() {
        let kinds = tok_kinds(r#""no closing quote"#);
        assert_eq!(kinds.len(), 1);
        assert!(matches!(&kinds[0], TokenKind::Error(msg) if msg.contains("unterminated")));
    }

    #[test]
    fn test_unterminated_escape_at_eof() {
        let kinds = tok_kinds(r#""trailing\"#);
        assert!(matches!(&kinds[0], TokenKind::Error(msg) if msg.contains("unterminated")));
    }

    #[test]
    fn test_invalid_char_dollar() {
        let kinds = tok_kinds("$");
        assert!(matches!(&kinds[0], TokenKind::Error(msg) if msg.contains("unexpected")));
    }

    #[test]
    fn test_invalid_char_at_sign_tangle_mode() {
        // @ is only valid in HV mode as a marker prefix
        let kinds = tok_kinds("@");
        assert!(matches!(&kinds[0], TokenKind::Error(msg) if msg.contains("unexpected")));
    }

    #[test]
    fn test_invalid_at_marker() {
        let src = "harvard{ @unknown }";
        let kinds = tok_kinds(src);
        assert!(kinds.iter().any(|k| matches!(k, TokenKind::Error(msg) if msg.contains("unknown marker"))));
    }

    #[test]
    fn test_error_recovery_continues() {
        // After an error, lexing should continue
        let kinds = tok_kinds("def $ weave % into");
        assert_eq!(kinds[0], TokenKind::Def);
        assert!(matches!(kinds[1], TokenKind::Error(_)));
        assert_eq!(kinds[2], TokenKind::Weave);
        assert!(matches!(kinds[3], TokenKind::Error(_)));
        assert_eq!(kinds[4], TokenKind::Into);
    }

    // ----- 15. Complex sequences -----

    #[test]
    fn test_braid_full_literal() {
        let kinds = tok_kinds("braid[s1, s2^-1, s1]");
        assert_eq!(
            kinds,
            vec![
                TokenKind::Braid,
                TokenKind::LBracket,
                TokenKind::Generator(1),
                TokenKind::Comma,
                TokenKind::Generator(2),
                TokenKind::Caret,
                TokenKind::Minus,
                TokenKind::Integer(1),
                TokenKind::Comma,
                TokenKind::Generator(1),
                TokenKind::RBracket,
            ]
        );
    }

    #[test]
    fn test_weave_block_full() {
        let kinds = tok_kinds("weave strands a, b, c into (a > b) . (b > c) yield strands c, b, a");
        assert_eq!(kinds[0], TokenKind::Weave);
        assert_eq!(kinds[1], TokenKind::Strands);
        assert_eq!(kinds[2], TokenKind::Ident("a".to_string()));
        assert_eq!(kinds[3], TokenKind::Comma);
        assert_eq!(kinds[4], TokenKind::Ident("b".to_string()));
        assert_eq!(kinds[5], TokenKind::Comma);
        assert_eq!(kinds[6], TokenKind::Ident("c".to_string()));
        assert_eq!(kinds[7], TokenKind::Into);
        assert!(kinds.contains(&TokenKind::Gt));
        assert!(kinds.contains(&TokenKind::Dot));
        assert!(kinds.contains(&TokenKind::Yield));
    }

    #[test]
    fn test_compute_jones_expression() {
        let kinds = tok_kinds("compute jones(close(braid[s1, s1, s1]))");
        assert_eq!(
            kinds,
            vec![
                TokenKind::Compute,
                TokenKind::Ident("jones".to_string()),
                TokenKind::LParen,
                TokenKind::Close,
                TokenKind::LParen,
                TokenKind::Braid,
                TokenKind::LBracket,
                TokenKind::Generator(1),
                TokenKind::Comma,
                TokenKind::Generator(1),
                TokenKind::Comma,
                TokenKind::Generator(1),
                TokenKind::RBracket,
                TokenKind::RParen,
                TokenKind::RParen,
            ]
        );
    }

    #[test]
    fn test_let_binding_with_pipeline() {
        let kinds = tok_kinds("let k = braid[s1, s2] >> close >> compute jones");
        assert_eq!(kinds[0], TokenKind::Let);
        assert_eq!(kinds[1], TokenKind::Ident("k".to_string()));
        assert_eq!(kinds[2], TokenKind::Eq);
        assert_eq!(kinds[3], TokenKind::Braid);
        assert!(kinds.contains(&TokenKind::Pipeline));
        assert!(kinds.contains(&TokenKind::Close));
        assert!(kinds.contains(&TokenKind::Compute));
    }

    #[test]
    fn test_match_with_multiple_arms() {
        let src = "match b with\n  | identity => 0\n  | s1 => 1\n  | _ => 2\nend";
        let kinds = tok_kinds(src);
        assert_eq!(kinds[0], TokenKind::Match);
        assert_eq!(kinds[2], TokenKind::With);
        // Count FatArrow occurrences (one per arm)
        let arrow_count = kinds.iter().filter(|k| **k == TokenKind::FatArrow).count();
        assert_eq!(arrow_count, 3);
        assert!(kinds.contains(&TokenKind::Identity));
        assert!(kinds.contains(&TokenKind::Underscore));
        assert_eq!(*kinds.last().unwrap(), TokenKind::End);
    }

    #[test]
    fn test_full_program_with_mixed_modes() {
        let src = r#"def trefoil = braid[s1, s1, s1]
# Compute the Jones polynomial
let j = compute jones(close(trefoil))
assert add{3 + 4} == 7
harvard{
  fn greet(name: String): String @pure {
    return "Hello, " + name
  }
}"#;
        let kinds = tok_kinds(src);
        // Should parse without errors
        assert!(
            !kinds.iter().any(|k| matches!(k, TokenKind::Error(_))),
            "unexpected error tokens: {:?}",
            kinds.iter().filter(|k| matches!(k, TokenKind::Error(_))).collect::<Vec<_>>()
        );
        // Verify key tokens present
        assert!(kinds.contains(&TokenKind::Def));
        assert!(kinds.contains(&TokenKind::Braid));
        assert!(kinds.contains(&TokenKind::Compute));
        assert!(kinds.contains(&TokenKind::Assert));
        assert!(kinds.contains(&TokenKind::Add));
        assert!(kinds.contains(&TokenKind::Harvard));
        assert!(kinds.contains(&TokenKind::Fn));
        assert!(kinds.contains(&TokenKind::AtPure));
        assert!(kinds.contains(&TokenKind::Return));
    }

    #[test]
    fn test_mirror_reverse_simplify_in_context() {
        let kinds = tok_kinds("simplify(mirror(reverse(braid[s1, s2])))");
        assert_eq!(
            kinds,
            vec![
                TokenKind::Simplify,
                TokenKind::LParen,
                TokenKind::Mirror,
                TokenKind::LParen,
                TokenKind::Reverse,
                TokenKind::LParen,
                TokenKind::Braid,
                TokenKind::LBracket,
                TokenKind::Generator(1),
                TokenKind::Comma,
                TokenKind::Generator(2),
                TokenKind::RBracket,
                TokenKind::RParen,
                TokenKind::RParen,
                TokenKind::RParen,
            ]
        );
    }

    #[test]
    fn test_cap_cup_in_context() {
        let kinds = tok_kinds("cap(1) . s1 . cup(1)");
        assert_eq!(
            kinds,
            vec![
                TokenKind::Cap,
                TokenKind::LParen,
                TokenKind::Integer(1),
                TokenKind::RParen,
                TokenKind::Dot,
                TokenKind::Generator(1),
                TokenKind::Dot,
                TokenKind::Cup,
                TokenKind::LParen,
                TokenKind::Integer(1),
                TokenKind::RParen,
            ]
        );
    }

    #[test]
    fn test_tilde_composition() {
        let kinds = tok_kinds("~s1 . s2 . ~s2");
        assert_eq!(
            kinds,
            vec![
                TokenKind::Tilde,
                TokenKind::Generator(1),
                TokenKind::Dot,
                TokenKind::Generator(2),
                TokenKind::Dot,
                TokenKind::Tilde,
                TokenKind::Generator(2),
            ]
        );
    }

    // ----- Token text and span verification -----

    #[test]
    fn test_token_text_preserved() {
        let tokens = Lexer::tokenize("braid[s1]");
        assert_eq!(tokens[0].text, "braid");
        assert_eq!(tokens[1].text, "[");
        assert_eq!(tokens[2].text, "s1");
        assert_eq!(tokens[3].text, "]");
    }

    #[test]
    fn test_span_offset_tracking() {
        let tokens = Lexer::tokenize("def x");
        assert_eq!(tokens[0].span.offset, 0);
        assert_eq!(tokens[0].span.col, 1);
        assert_eq!(tokens[1].span.offset, 4);
        assert_eq!(tokens[1].span.col, 5);
    }

    #[test]
    fn test_span_multiline() {
        let tokens = Lexer::tokenize("a\nb\nc");
        assert_eq!(tokens[0].span.line, 1);
        assert_eq!(tokens[1].span.line, 2);
        assert_eq!(tokens[2].span.line, 3);
        // Each is at column 1
        assert_eq!(tokens[0].span.col, 1);
        assert_eq!(tokens[1].span.col, 1);
        assert_eq!(tokens[2].span.col, 1);
    }

    // ----- Harvard mode keywords -----

    #[test]
    fn test_all_harvard_keywords() {
        let src = "harvard{ fn if else while for return print module import as then }";
        let kinds = tok_kinds(src);
        assert!(kinds.contains(&TokenKind::Fn));
        assert!(kinds.contains(&TokenKind::If));
        assert!(kinds.contains(&TokenKind::Else));
        assert!(kinds.contains(&TokenKind::While));
        assert!(kinds.contains(&TokenKind::For));
        assert!(kinds.contains(&TokenKind::Return));
        assert!(kinds.contains(&TokenKind::Print));
        assert!(kinds.contains(&TokenKind::Module));
        assert!(kinds.contains(&TokenKind::Import));
        assert!(kinds.contains(&TokenKind::As));
        assert!(kinds.contains(&TokenKind::Then));
    }

    #[test]
    fn test_harvard_keywords_are_idents_in_tangle_mode() {
        // Outside Harvard blocks, these words are plain identifiers
        let kinds = tok_kinds("fn if else while for return print module import as then");
        for k in &kinds {
            assert!(
                matches!(k, TokenKind::Ident(_)),
                "expected Ident in Tangle mode, got {:?}",
                k
            );
        }
    }

    // ----- Purity markers -----

    #[test]
    fn test_at_pure_marker() {
        let src = "harvard{ @pure }";
        let kinds = tok_kinds(src);
        assert!(kinds.contains(&TokenKind::AtPure));
    }

    #[test]
    fn test_at_total_marker() {
        let src = "harvard{ @total }";
        let kinds = tok_kinds(src);
        assert!(kinds.contains(&TokenKind::AtTotal));
    }

    // ----- Mode switching edge cases -----

    #[test]
    fn test_add_without_brace_no_mode_switch() {
        // "add" not followed by "{" should not switch mode
        let src = "add x";
        let mut lexer = Lexer::new(src);
        let t = lexer.next_token();
        assert_eq!(t.kind, TokenKind::Add);
        assert_eq!(lexer.mode(), Mode::Tangle);
    }

    #[test]
    fn test_harvard_without_brace_no_mode_switch() {
        let src = "harvard x";
        let mut lexer = Lexer::new(src);
        let t = lexer.next_token();
        assert_eq!(t.kind, TokenKind::Harvard);
        assert_eq!(lexer.mode(), Mode::Tangle);
    }

    #[test]
    fn test_nested_harvard_in_harvard() {
        // Harvard inside Harvard should nest mode frames
        let src = "harvard{ harvard{ 1 } }";
        let mut lexer = Lexer::new(src);

        lexer.next_token(); // harvard
        lexer.next_token(); // {
        assert_eq!(lexer.mode(), Mode::HvControl);

        lexer.next_token(); // harvard
        lexer.next_token(); // {
        assert_eq!(lexer.mode(), Mode::HvControl);

        lexer.next_token(); // 1

        lexer.next_token(); // } — pops inner
        assert_eq!(lexer.mode(), Mode::HvControl);

        lexer.next_token(); // } — pops outer
        assert_eq!(lexer.mode(), Mode::Tangle);
    }

    // ----- Tokenize helper -----

    #[test]
    fn test_tokenize_includes_eof() {
        let tokens = Lexer::tokenize("def");
        assert_eq!(tokens.len(), 2);
        assert_eq!(tokens[0].kind, TokenKind::Def);
        assert_eq!(tokens[1].kind, TokenKind::Eof);
    }

    #[test]
    fn test_tokenize_empty_has_eof() {
        let tokens = Lexer::tokenize("");
        assert_eq!(tokens.len(), 1);
        assert_eq!(tokens[0].kind, TokenKind::Eof);
    }

    // ----- Harvard comments in HV mode -----

    #[test]
    fn test_hv_line_comment_skipped() {
        let src = "harvard{ 1 // comment\n+ 2 }";
        let kinds = tok_kinds(src);
        assert_eq!(
            kinds,
            vec![
                TokenKind::Harvard,
                TokenKind::LBrace,
                TokenKind::Integer(1),
                TokenKind::Plus,
                TokenKind::Integer(2),
                TokenKind::RBrace,
            ]
        );
    }

    #[test]
    fn test_hv_block_comment_skipped() {
        let src = "harvard{ 1 /* block comment */ + 2 }";
        let kinds = tok_kinds(src);
        assert_eq!(
            kinds,
            vec![
                TokenKind::Harvard,
                TokenKind::LBrace,
                TokenKind::Integer(1),
                TokenKind::Plus,
                TokenKind::Integer(2),
                TokenKind::RBrace,
            ]
        );
    }

    #[test]
    fn test_unterminated_hv_block_comment() {
        let src = "harvard{ /* unterminated";
        let kinds = tok_kinds(src);
        assert!(kinds.iter().any(|k| matches!(k, TokenKind::Error(msg) if msg.contains("unterminated"))));
    }

    // ----- Operator disambiguation at mode boundaries -----

    #[test]
    fn test_slash_in_tangle_is_slash() {
        // In Tangle mode, / is Slash (not start of // comment)
        let kinds = tok_kinds("a / b");
        assert_eq!(
            kinds,
            vec![
                TokenKind::Ident("a".to_string()),
                TokenKind::Slash,
                TokenKind::Ident("b".to_string()),
            ]
        );
    }

    #[test]
    fn test_pipe_in_tangle_is_pipe() {
        // In Tangle mode, | is Pipe (not start of ||)
        let kinds = tok_kinds("| x |");
        assert_eq!(
            kinds,
            vec![
                TokenKind::Pipe,
                TokenKind::Ident("x".to_string()),
                TokenKind::Pipe,
            ]
        );
    }

    #[test]
    fn test_bang_in_tangle_is_bang() {
        // In Tangle mode, ! is Bang (not start of !=)
        let kinds = tok_kinds("!");
        assert_eq!(kinds, vec![TokenKind::Bang]);
    }
}
