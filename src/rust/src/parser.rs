// SPDX-License-Identifier: PMPL-1.0-or-later
// parser.rs — Recursive descent parser for TANGLE
//
// Precedence (lowest to highest):
//   1. match / let (prefix, lowest)
//   2. >> (pipeline, left-assoc)
//   3. == / ~ (equality / isotopy, non-associative)
//   4. + / - (sum, left-assoc)
//   5. * / / (product, left-assoc)
//   6. . (vertical composition, left-assoc)
//   7. | (horizontal tensor, left-assoc)
//   8. unary prefix: close, mirror, reverse, simplify, cap, cup, twist
//   9. primary: literals, identifiers, braid[], crossings, parens

use crate::ast::*;
use crate::lexer::{Lexer, Span, Token, TokenKind};

/// Parse error with location.
#[derive(Debug, Clone)]
pub struct ParseError {
    pub message: String,
    pub span: Span,
}

impl std::fmt::Display for ParseError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}: {}", self.span, self.message)
    }
}

impl std::error::Error for ParseError {}

type Result<T> = std::result::Result<T, ParseError>;

/// Result of parsing with error recovery: partial AST + collected diagnostics.
pub struct ParseOutput {
    pub program: Program,
    pub diagnostics: Vec<ParseError>,
}

/// Recursive descent parser for TANGLE.
pub struct Parser {
    tokens: Vec<Token>,
    pos: usize,
    /// When true, `|` is NOT consumed as tensor — it's reserved for match arm separation.
    in_match_arm: bool,
    /// Diagnostics collected during error recovery.
    diagnostics: Vec<ParseError>,
}

impl Parser {
    pub fn new(source: &str) -> Self {
        Self {
            tokens: Lexer::tokenize(source),
            pos: 0,
            in_match_arm: false,
            diagnostics: Vec::new(),
        }
    }

    /// Parse a complete program with error recovery.
    /// Returns partial AST + all diagnostics collected.
    pub fn parse_program_recovering(&mut self) -> ParseOutput {
        let mut stmts = Vec::new();
        while !self.at_eof() {
            match self.parse_stmt() {
                Ok(stmt) => stmts.push(stmt),
                Err(err) => {
                    self.diagnostics.push(err);
                    self.synchronize();
                }
            }
        }
        ParseOutput {
            program: Program { stmts },
            diagnostics: std::mem::take(&mut self.diagnostics),
        }
    }

    /// Parse a complete program. Returns first error if any occurred.
    pub fn parse_program(&mut self) -> Result<Program> {
        let mut stmts = Vec::new();
        while !self.at_eof() {
            match self.parse_stmt() {
                Ok(stmt) => stmts.push(stmt),
                Err(err) => {
                    self.diagnostics.push(err);
                    self.synchronize();
                }
            }
        }
        if !self.diagnostics.is_empty() {
            return Err(self.diagnostics.remove(0));
        }
        Ok(Program { stmts })
    }

    /// Synchronize after a parse error by skipping to the next statement boundary.
    fn synchronize(&mut self) {
        while !self.at_eof() {
            match self.peek() {
                // Keywords that start new statements
                TokenKind::Def | TokenKind::Weave | TokenKind::Compute
                | TokenKind::Assert | TokenKind::Let | TokenKind::Match => return,
                _ => { self.advance(); }
            };
        }
    }

    /// Get all collected diagnostics.
    pub fn diagnostics(&self) -> &[ParseError] {
        &self.diagnostics
    }

    // ---- Token helpers ----

    pub(crate) fn peek(&self) -> &TokenKind {
        self.tokens
            .get(self.pos)
            .map(|t| &t.kind)
            .unwrap_or(&TokenKind::Eof)
    }

    pub(crate) fn span(&self) -> Span {
        self.tokens
            .get(self.pos)
            .map(|t| t.span)
            .unwrap_or(Span {
                offset: 0,
                line: 1,
                col: 1,
            })
    }

    pub(crate) fn at_eof(&self) -> bool {
        matches!(self.peek(), TokenKind::Eof)
    }

    pub(crate) fn advance(&mut self) -> &Token {
        let tok = &self.tokens[self.pos];
        if !self.at_eof() {
            self.pos += 1;
        }
        tok
    }

    pub(crate) fn expect(&mut self, expected: &TokenKind) -> Result<&Token> {
        if self.peek() == expected {
            Ok(self.advance())
        } else {
            Err(ParseError {
                message: format!("expected {expected}, found {}", self.peek()),
                span: self.span(),
            })
        }
    }

    pub(crate) fn expect_ident(&mut self) -> Result<String> {
        match self.peek().clone() {
            TokenKind::Ident(name) => {
                self.advance();
                Ok(name)
            }
            // Allow invariant names that are also identifiers
            other => Err(ParseError {
                message: format!("expected identifier, found {other}"),
                span: self.span(),
            }),
        }
    }

    pub(crate) fn check(&self, kind: &TokenKind) -> bool {
        self.peek() == kind
    }

    pub(crate) fn eat(&mut self, kind: &TokenKind) -> bool {
        if self.check(kind) {
            self.advance();
            true
        } else {
            false
        }
    }

    // ---- Statement parsing ----

    fn parse_stmt(&mut self) -> Result<Stmt> {
        let span = self.span();
        match self.peek() {
            TokenKind::Def => self.parse_def(span),
            TokenKind::Weave => self.parse_weave(span),
            TokenKind::Compute => self.parse_compute(span),
            TokenKind::Assert => self.parse_assert(span),
            TokenKind::Harvard => self.parse_harvard_stmt(span),
            _ => Err(ParseError {
                message: format!(
                    "expected statement (def, weave, compute, assert, harvard), found {}",
                    self.peek()
                ),
                span,
            }),
        }
    }

    /// `def name = expr` or `def name(params) = expr`
    fn parse_def(&mut self, span: Span) -> Result<Stmt> {
        self.expect(&TokenKind::Def)?;
        let name = self.expect_ident()?;

        let params = if self.eat(&TokenKind::LParen) {
            let params = self.parse_ident_list()?;
            self.expect(&TokenKind::RParen)?;
            params
        } else {
            Vec::new()
        };

        self.expect(&TokenKind::Eq)?;
        let body = self.parse_expr()?;

        Ok(Stmt {
            kind: StmtKind::Def { name, params, body },
            span,
        })
    }

    /// `weave strands S_in into expr yield strands S_out`
    fn parse_weave(&mut self, span: Span) -> Result<Stmt> {
        self.expect(&TokenKind::Weave)?;
        self.expect(&TokenKind::Strands)?;
        let input_strands = self.parse_strand_list()?;
        self.expect(&TokenKind::Into)?;
        let body = self.parse_expr()?;
        self.expect(&TokenKind::Yield)?;
        self.expect(&TokenKind::Strands)?;
        let output_strands = self.parse_strand_list()?;

        Ok(Stmt {
            kind: StmtKind::Weave {
                input_strands,
                body,
                output_strands,
            },
            span,
        })
    }

    /// `compute invariant(expr)`
    fn parse_compute(&mut self, span: Span) -> Result<Stmt> {
        self.expect(&TokenKind::Compute)?;
        let invariant = self.parse_invariant_name()?;
        self.expect(&TokenKind::LParen)?;
        let expr = self.parse_expr()?;
        self.expect(&TokenKind::RParen)?;

        Ok(Stmt {
            kind: StmtKind::Compute { invariant, expr },
            span,
        })
    }

    /// `assert expr`
    fn parse_assert(&mut self, span: Span) -> Result<Stmt> {
        self.expect(&TokenKind::Assert)?;
        let expr = self.parse_expr()?;
        Ok(Stmt {
            kind: StmtKind::Assert { expr },
            span,
        })
    }

    /// `harvard{ hv_program }` — top-level Harvard block statement
    fn parse_harvard_stmt(&mut self, span: Span) -> Result<Stmt> {
        self.expect(&TokenKind::Harvard)?;
        let program = self.parse_harvard_block()?;
        Ok(Stmt {
            kind: StmtKind::HarvardBlock { program },
            span,
        })
    }

    // ---- Helper parsers ----

    fn parse_ident_list(&mut self) -> Result<Vec<String>> {
        let mut names = Vec::new();
        if let TokenKind::Ident(_) = self.peek() {
            names.push(self.expect_ident()?);
            while self.eat(&TokenKind::Comma) {
                names.push(self.expect_ident()?);
            }
        }
        Ok(names)
    }

    fn parse_strand_list(&mut self) -> Result<Vec<TypedStrand>> {
        let mut strands = Vec::new();
        strands.push(self.parse_typed_strand()?);
        while self.eat(&TokenKind::Comma) {
            strands.push(self.parse_typed_strand()?);
        }
        Ok(strands)
    }

    fn parse_typed_strand(&mut self) -> Result<TypedStrand> {
        let span = self.span();
        let name = self.expect_ident()?;
        let type_ann = if self.eat(&TokenKind::Colon) {
            Some(self.expect_ident()?)
        } else {
            None
        };
        Ok(TypedStrand {
            name,
            type_ann,
            span,
        })
    }

    fn parse_invariant_name(&mut self) -> Result<String> {
        match self.peek().clone() {
            TokenKind::Ident(name) => {
                self.advance();
                Ok(name)
            }
            // Builtin invariant names that might collide with keywords
            _ => Err(ParseError {
                message: format!("expected invariant name, found {}", self.peek()),
                span: self.span(),
            }),
        }
    }

    // ---- Expression parsing (precedence climbing) ----

    /// Top-level expression: match, let, weave (as expression), or pipeline.
    fn parse_expr(&mut self) -> Result<Expr> {
        match self.peek() {
            TokenKind::Match => self.parse_match(),
            TokenKind::Let => self.parse_let(),
            TokenKind::Weave => self.parse_weave_expr(),
            _ => self.parse_pipeline(),
        }
    }

    /// Parse a weave block as an expression (D1.9).
    /// `weave strands S_in into expr yield strands S_out`
    /// This allows weave blocks in def bodies: `def x = weave ... yield ...`
    fn parse_weave_expr(&mut self) -> Result<Expr> {
        let span = self.span();
        self.expect(&TokenKind::Weave)?;
        self.expect(&TokenKind::Strands)?;
        let input_strands = self.parse_strand_list()?;
        self.expect(&TokenKind::Into)?;
        let body = self.parse_expr()?;
        self.expect(&TokenKind::Yield)?;
        self.expect(&TokenKind::Strands)?;
        let output_strands = self.parse_strand_list()?;

        Ok(Expr::new(
            ExprKind::WeaveExpr {
                input_strands,
                body,
                output_strands,
            },
            span,
        ))
    }

    /// `match e with | p => e | ... end`
    fn parse_match(&mut self) -> Result<Expr> {
        let span = self.span();
        self.expect(&TokenKind::Match)?;
        let scrutinee = self.parse_expr()?;
        self.expect(&TokenKind::With)?;

        let mut arms = Vec::new();
        while self.eat(&TokenKind::Pipe) {
            let arm_span = self.span();
            let pattern = self.parse_pattern()?;
            self.expect(&TokenKind::FatArrow)?;
            let prev = self.in_match_arm;
            self.in_match_arm = true;
            let body = self.parse_expr()?;
            self.in_match_arm = prev;
            arms.push(MatchArm {
                pattern,
                body,
                span: arm_span,
            });
        }

        if arms.is_empty() {
            return Err(ParseError {
                message: "match expression must have at least one arm".to_string(),
                span,
            });
        }

        self.expect(&TokenKind::End)?;

        Ok(Expr::new(
            ExprKind::Match { scrutinee, arms },
            span,
        ))
    }

    /// `let x = e1 in e2`
    fn parse_let(&mut self) -> Result<Expr> {
        let span = self.span();
        self.expect(&TokenKind::Let)?;
        let name = self.expect_ident()?;
        self.expect(&TokenKind::Eq)?;
        let value = self.parse_expr()?;
        self.expect(&TokenKind::In)?;
        let body = self.parse_expr()?;

        Ok(Expr::new(ExprKind::Let { name, value, body }, span))
    }

    /// Pipeline: `equality { >> equality }`
    fn parse_pipeline(&mut self) -> Result<Expr> {
        let mut left = self.parse_equality()?;
        while self.check(&TokenKind::Pipeline) {
            let span = self.span();
            self.advance();
            let right = self.parse_equality()?;
            left = Expr::new(ExprKind::Pipeline(left, right), span);
        }
        Ok(left)
    }

    /// Equality/isotopy: `sum [ (== | ~) sum ]` (non-associative)
    fn parse_equality(&mut self) -> Result<Expr> {
        let left = self.parse_sum()?;
        match self.peek() {
            TokenKind::EqEq => {
                let span = self.span();
                self.advance();
                let right = self.parse_sum()?;
                Ok(Expr::new(ExprKind::Eq(left, right), span))
            }
            TokenKind::Tilde => {
                let span = self.span();
                self.advance();
                let right = self.parse_sum()?;
                Ok(Expr::new(ExprKind::Isotopy(left, right), span))
            }
            _ => Ok(left),
        }
    }

    /// Sum: `product { (+ | -) product }`
    fn parse_sum(&mut self) -> Result<Expr> {
        let mut left = self.parse_product()?;
        loop {
            match self.peek() {
                TokenKind::Plus => {
                    let span = self.span();
                    self.advance();
                    let right = self.parse_product()?;
                    left = Expr::new(ExprKind::Add(left, right), span);
                }
                TokenKind::Minus => {
                    let span = self.span();
                    self.advance();
                    let right = self.parse_product()?;
                    left = Expr::new(ExprKind::Sub(left, right), span);
                }
                _ => break,
            }
        }
        Ok(left)
    }

    /// Product: `vertical { (* | /) vertical }`
    fn parse_product(&mut self) -> Result<Expr> {
        let mut left = self.parse_vertical()?;
        loop {
            match self.peek() {
                TokenKind::Star => {
                    let span = self.span();
                    self.advance();
                    let right = self.parse_vertical()?;
                    left = Expr::new(ExprKind::Mul(left, right), span);
                }
                TokenKind::Slash => {
                    let span = self.span();
                    self.advance();
                    let right = self.parse_vertical()?;
                    left = Expr::new(ExprKind::Div(left, right), span);
                }
                _ => break,
            }
        }
        Ok(left)
    }

    /// Vertical composition: `horizontal { . horizontal }`
    fn parse_vertical(&mut self) -> Result<Expr> {
        let mut left = self.parse_horizontal()?;
        while self.check(&TokenKind::Dot) {
            let span = self.span();
            self.advance();
            let right = self.parse_horizontal()?;
            left = Expr::new(ExprKind::Compose(left, right), span);
        }
        Ok(left)
    }

    /// Horizontal tensor: `unary { | unary }`
    /// Inside match arms, `|` is reserved for arm separation, so tensor requires parens.
    fn parse_horizontal(&mut self) -> Result<Expr> {
        let mut left = self.parse_unary()?;
        while !self.in_match_arm && self.check(&TokenKind::Pipe) {
            let span = self.span();
            self.advance();
            let right = self.parse_unary()?;
            left = Expr::new(ExprKind::Tensor(left, right), span);
        }
        Ok(left)
    }

    /// Unary prefix operations and primaries.
    fn parse_unary(&mut self) -> Result<Expr> {
        let span = self.span();
        match self.peek() {
            TokenKind::Close => {
                self.advance();
                self.expect(&TokenKind::LParen)?;
                let e = self.parse_expr()?;
                self.expect(&TokenKind::RParen)?;
                Ok(Expr::new(ExprKind::Close(e), span))
            }
            TokenKind::Mirror => {
                self.advance();
                self.expect(&TokenKind::LParen)?;
                let e = self.parse_expr()?;
                self.expect(&TokenKind::RParen)?;
                Ok(Expr::new(ExprKind::Mirror(e), span))
            }
            TokenKind::Reverse => {
                self.advance();
                self.expect(&TokenKind::LParen)?;
                let e = self.parse_expr()?;
                self.expect(&TokenKind::RParen)?;
                Ok(Expr::new(ExprKind::Reverse(e), span))
            }
            TokenKind::Simplify => {
                self.advance();
                self.expect(&TokenKind::LParen)?;
                let e = self.parse_expr()?;
                self.expect(&TokenKind::RParen)?;
                Ok(Expr::new(ExprKind::Simplify(e), span))
            }
            TokenKind::Cap => {
                self.advance();
                self.expect(&TokenKind::LParen)?;
                let e1 = self.parse_expr()?;
                self.expect(&TokenKind::Comma)?;
                let e2 = self.parse_expr()?;
                self.expect(&TokenKind::RParen)?;
                Ok(Expr::new(ExprKind::Cap(e1, e2), span))
            }
            TokenKind::Cup => {
                self.advance();
                self.expect(&TokenKind::LParen)?;
                let e1 = self.parse_expr()?;
                self.expect(&TokenKind::Comma)?;
                let e2 = self.parse_expr()?;
                self.expect(&TokenKind::RParen)?;
                Ok(Expr::new(ExprKind::Cup(e1, e2), span))
            }
            _ => self.parse_primary(),
        }
    }

    /// Primary expressions: literals, identifiers, braid[], crossings, parens.
    fn parse_primary(&mut self) -> Result<Expr> {
        let span = self.span();
        match self.peek().clone() {
            // Braid literal
            TokenKind::Braid => {
                self.advance();
                self.expect(&TokenKind::LBracket)?;
                let gens = if !self.check(&TokenKind::RBracket) {
                    self.parse_generator_seq()?
                } else {
                    Vec::new()
                };
                self.expect(&TokenKind::RBracket)?;
                Ok(Expr::new(ExprKind::BraidLit(gens), span))
            }

            // Identity
            TokenKind::Identity => {
                self.advance();
                Ok(Expr::new(ExprKind::Identity, span))
            }

            // Boolean literals
            TokenKind::True => {
                self.advance();
                Ok(Expr::new(ExprKind::BoolLit(true), span))
            }
            TokenKind::False => {
                self.advance();
                Ok(Expr::new(ExprKind::BoolLit(false), span))
            }

            // Numeric literals
            TokenKind::Integer(n) => {
                self.advance();
                Ok(Expr::new(ExprKind::IntLit(n), span))
            }
            TokenKind::Float(n) => {
                self.advance();
                Ok(Expr::new(ExprKind::FloatLit(n), span))
            }

            // String literal
            TokenKind::StringLit(s) => {
                self.advance();
                Ok(Expr::new(ExprKind::StrLit(s), span))
            }

            // Generator as expression (e.g. s1 in patterns used as exprs)
            TokenKind::Generator(_) => {
                // Generators in expression context are part of braid[] only.
                // If bare, treat as an identifier-like reference for pattern matching.
                Err(ParseError {
                    message: "bare generator (e.g. s1) can only appear inside braid[...] or patterns".to_string(),
                    span,
                })
            }

            // Identifier — possibly function call
            TokenKind::Ident(name) => {
                self.advance();
                if self.eat(&TokenKind::LParen) {
                    // Function call
                    let args = if !self.check(&TokenKind::RParen) {
                        self.parse_arg_list()?
                    } else {
                        Vec::new()
                    };
                    self.expect(&TokenKind::RParen)?;
                    Ok(Expr::new(ExprKind::App { func: name, args }, span))
                } else {
                    Ok(Expr::new(ExprKind::Var(name), span))
                }
            }

            // Parenthesized expression, crossing, or twist
            TokenKind::LParen => {
                self.advance();

                // Twist: (~ident) or (~(expr))
                if self.check(&TokenKind::Tilde) {
                    let tilde_span = self.span();
                    self.advance(); // ~

                    let inner = if self.check(&TokenKind::LParen) {
                        // (~(expr))
                        self.advance();
                        let e = self.parse_expr()?;
                        self.expect(&TokenKind::RParen)?;
                        e
                    } else {
                        // (~ident)
                        let name = self.expect_ident()?;
                        Expr::new(ExprKind::Var(name), tilde_span)
                    };

                    self.expect(&TokenKind::RParen)?;
                    return Ok(Expr::new(ExprKind::Twist(inner), span));
                }

                // Try crossing: (ident > ident) or (ident < ident)
                if let TokenKind::Ident(a) = self.peek().clone() {
                    let saved_pos = self.pos;
                    self.advance(); // ident

                    match self.peek() {
                        TokenKind::Gt => {
                            self.advance();
                            let b = self.expect_ident()?;
                            self.expect(&TokenKind::RParen)?;
                            return Ok(Expr::new(ExprKind::CrossOver { a, b }, span));
                        }
                        TokenKind::Lt => {
                            self.advance();
                            let b = self.expect_ident()?;
                            self.expect(&TokenKind::RParen)?;
                            return Ok(Expr::new(ExprKind::CrossUnder { a, b }, span));
                        }
                        _ => {
                            // Not a crossing — backtrack and parse as parenthesized expr
                            self.pos = saved_pos;
                        }
                    }
                }

                // Regular parenthesized expression
                let e = self.parse_expr()?;
                self.expect(&TokenKind::RParen)?;
                Ok(e)
            }

            // add{} block — switches to Harvard data expression parser
            TokenKind::Add => {
                self.advance();
                let expr = self.parse_add_block()?;
                Ok(Expr::new(ExprKind::AddBlock { expr }, span))
            }

            other => Err(ParseError {
                message: format!("expected expression, found {other}"),
                span,
            }),
        }
    }

    /// Parse a comma-separated list of expressions (function args).
    fn parse_arg_list(&mut self) -> Result<Vec<Expr>> {
        let mut args = vec![self.parse_expr()?];
        while self.eat(&TokenKind::Comma) {
            args.push(self.parse_expr()?);
        }
        Ok(args)
    }

    /// Parse a comma-separated list of generators: `s1, s2^-1, s1`
    fn parse_generator_seq(&mut self) -> Result<Vec<Generator>> {
        let mut gens = vec![self.parse_generator()?];
        while self.eat(&TokenKind::Comma) {
            gens.push(self.parse_generator()?);
        }
        Ok(gens)
    }

    /// Parse a single generator: `s1` or `s2^-1` or `s1^3`
    fn parse_generator(&mut self) -> Result<Generator> {
        match self.peek().clone() {
            TokenKind::Generator(index) => {
                self.advance();
                let inverse = if self.eat(&TokenKind::Caret) {
                    // ^-1 or ^n
                    if self.eat(&TokenKind::Minus) {
                        self.expect(&TokenKind::Integer(1))?;
                        true
                    } else {
                        // ^n (positive exponent — just consume)
                        if let TokenKind::Integer(_) = self.peek() {
                            self.advance();
                        }
                        false
                    }
                } else {
                    false
                };
                Ok(Generator { index, inverse })
            }
            other => Err(ParseError {
                message: format!("expected generator (e.g. s1), found {other}"),
                span: self.span(),
            }),
        }
    }

    // ---- Pattern parsing ----

    /// Parse a pattern: `identity`, `g . p`, `x`, `_`, or `(p)`
    fn parse_pattern(&mut self) -> Result<Pattern> {
        let span = self.span();

        match self.peek().clone() {
            TokenKind::Identity => {
                self.advance();
                Ok(Pattern {
                    kind: PatternKind::Identity,
                    span,
                })
            }

            TokenKind::Underscore => {
                self.advance();
                Ok(Pattern {
                    kind: PatternKind::Wildcard,
                    span,
                })
            }

            // Generator pattern: s1 . rest
            TokenKind::Generator(index) => {
                self.advance();
                let inverse = if self.eat(&TokenKind::Caret) {
                    if self.eat(&TokenKind::Minus) {
                        self.expect(&TokenKind::Integer(1))?;
                        true
                    } else {
                        if let TokenKind::Integer(_) = self.peek() {
                            self.advance();
                        }
                        false
                    }
                } else {
                    false
                };

                let generator = Generator { index, inverse };

                // Expect . followed by rest pattern (cons)
                if self.eat(&TokenKind::Dot) {
                    let rest = self.parse_pattern()?;
                    Ok(Pattern {
                        kind: PatternKind::Cons {
                            generator,
                            rest: Box::new(rest),
                        },
                        span,
                    })
                } else {
                    Err(ParseError {
                        message: "generator in pattern must be followed by `. rest`".to_string(),
                        span: self.span(),
                    })
                }
            }

            // Variable pattern
            TokenKind::Ident(name) => {
                self.advance();
                Ok(Pattern {
                    kind: PatternKind::Var(name),
                    span,
                })
            }

            // Parenthesized pattern
            TokenKind::LParen => {
                self.advance();
                let p = self.parse_pattern()?;
                self.expect(&TokenKind::RParen)?;
                Ok(p)
            }

            other => Err(ParseError {
                message: format!("expected pattern, found {other}"),
                span,
            }),
        }
    }
}

/// Convenience function: parse source string into a Program.
pub fn parse(source: &str) -> Result<Program> {
    Parser::new(source).parse_program()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse_ok(src: &str) -> Program {
        parse(src).unwrap_or_else(|e| panic!("parse error: {e}"))
    }

    fn parse_err(src: &str) -> ParseError {
        parse(src).unwrap_err()
    }

    // ----- Definitions -----

    #[test]
    fn test_value_def() {
        let prog = parse_ok("def x = identity");
        assert_eq!(prog.stmts.len(), 1);
        match &prog.stmts[0].kind {
            StmtKind::Def { name, params, body } => {
                assert_eq!(name, "x");
                assert!(params.is_empty());
                assert_eq!(*body.kind, ExprKind::Identity);
            }
            _ => panic!("expected Def"),
        }
    }

    #[test]
    fn test_function_def() {
        let prog = parse_ok("def f(x, y) = x");
        match &prog.stmts[0].kind {
            StmtKind::Def { name, params, .. } => {
                assert_eq!(name, "f");
                assert_eq!(params, &["x", "y"]);
            }
            _ => panic!("expected Def"),
        }
    }

    #[test]
    fn test_braid_def() {
        let prog = parse_ok("def trefoil = braid[s1, s1, s1]");
        match &prog.stmts[0].kind {
            StmtKind::Def { body, .. } => match body.kind.as_ref() {
                ExprKind::BraidLit(gens) => {
                    assert_eq!(gens.len(), 3);
                    assert_eq!(gens[0].index, 1);
                    assert!(!gens[0].inverse);
                }
                _ => panic!("expected BraidLit"),
            },
            _ => panic!("expected Def"),
        }
    }

    #[test]
    fn test_braid_inverse() {
        let prog = parse_ok("def x = braid[s2^-1]");
        match &prog.stmts[0].kind {
            StmtKind::Def { body, .. } => match body.kind.as_ref() {
                ExprKind::BraidLit(gens) => {
                    assert_eq!(gens.len(), 1);
                    assert_eq!(gens[0].index, 2);
                    assert!(gens[0].inverse);
                }
                _ => panic!("expected BraidLit"),
            },
            _ => panic!("expected Def"),
        }
    }

    #[test]
    fn test_empty_braid() {
        let prog = parse_ok("def x = braid[]");
        match &prog.stmts[0].kind {
            StmtKind::Def { body, .. } => match body.kind.as_ref() {
                ExprKind::BraidLit(gens) => assert!(gens.is_empty()),
                _ => panic!("expected BraidLit"),
            },
            _ => panic!("expected Def"),
        }
    }

    // ----- Assertions -----

    #[test]
    fn test_assert_equality() {
        let prog = parse_ok("assert braid[s1] == braid[s1]");
        match &prog.stmts[0].kind {
            StmtKind::Assert { expr } => {
                assert!(matches!(expr.kind.as_ref(), ExprKind::Eq(..)));
            }
            _ => panic!("expected Assert"),
        }
    }

    #[test]
    fn test_assert_isotopy() {
        let prog = parse_ok("assert braid[s1] ~ braid[s1]");
        match &prog.stmts[0].kind {
            StmtKind::Assert { expr } => {
                assert!(matches!(expr.kind.as_ref(), ExprKind::Isotopy(..)));
            }
            _ => panic!("expected Assert"),
        }
    }

    // ----- Compute -----

    #[test]
    fn test_compute() {
        let prog = parse_ok("compute jones(close(braid[s1, s1, s1]))");
        match &prog.stmts[0].kind {
            StmtKind::Compute { invariant, expr } => {
                assert_eq!(invariant, "jones");
                assert!(matches!(expr.kind.as_ref(), ExprKind::Close(..)));
            }
            _ => panic!("expected Compute"),
        }
    }

    // ----- Weave -----

    #[test]
    fn test_weave_block() {
        let prog = parse_ok("weave strands a, b into (a > b) yield strands b, a");
        match &prog.stmts[0].kind {
            StmtKind::Weave {
                input_strands,
                body,
                output_strands,
            } => {
                assert_eq!(input_strands.len(), 2);
                assert_eq!(input_strands[0].name, "a");
                assert_eq!(input_strands[1].name, "b");
                assert!(matches!(body.kind.as_ref(), ExprKind::CrossOver { .. }));
                assert_eq!(output_strands[0].name, "b");
                assert_eq!(output_strands[1].name, "a");
            }
            _ => panic!("expected Weave"),
        }
    }

    #[test]
    fn test_weave_typed_strands() {
        let prog = parse_ok("weave strands a: Q, b: R into (a > b) yield strands b, a");
        match &prog.stmts[0].kind {
            StmtKind::Weave { input_strands, .. } => {
                assert_eq!(input_strands[0].type_ann.as_deref(), Some("Q"));
                assert_eq!(input_strands[1].type_ann.as_deref(), Some("R"));
            }
            _ => panic!("expected Weave"),
        }
    }

    // ----- Precedence -----

    #[test]
    fn test_precedence_compose_over_add() {
        // a . b + c should parse as (a . b) + c
        let prog = parse_ok("def x = a . b + c");
        match &prog.stmts[0].kind {
            StmtKind::Def { body, .. } => {
                assert!(matches!(body.kind.as_ref(), ExprKind::Add(..)));
            }
            _ => panic!("expected Def"),
        }
    }

    #[test]
    fn test_precedence_add_over_eq() {
        // a + b == c should parse as (a + b) == c
        let prog = parse_ok("assert a + b == c");
        match &prog.stmts[0].kind {
            StmtKind::Assert { expr } => match expr.kind.as_ref() {
                ExprKind::Eq(lhs, _) => {
                    assert!(matches!(lhs.kind.as_ref(), ExprKind::Add(..)));
                }
                _ => panic!("expected Eq"),
            },
            _ => panic!("expected Assert"),
        }
    }

    #[test]
    fn test_precedence_mul_over_add() {
        // a + b * c should parse as a + (b * c)
        let prog = parse_ok("def x = a + b * c");
        match &prog.stmts[0].kind {
            StmtKind::Def { body, .. } => match body.kind.as_ref() {
                ExprKind::Add(_, rhs) => {
                    assert!(matches!(rhs.kind.as_ref(), ExprKind::Mul(..)));
                }
                _ => panic!("expected Add"),
            },
            _ => panic!("expected Def"),
        }
    }

    #[test]
    fn test_precedence_tensor_highest() {
        // a | b . c should parse as (a | b) . c? No!
        // | is highest (level 7), . is level 6, so | binds tighter
        // Actually: . has higher precedence than |? Let me re-check.
        // Precedence (lowest to highest): >> == ~ + - * / . |
        // So | is HIGHEST, . is second highest.
        // a | b . c => a | (b . c)? No:
        // . binds tighter than |? Wait:
        // From EBNF: horizontal = unary { "|" unary }, vertical = horizontal { "." horizontal }
        // That means vertical calls horizontal, so | binds tighter than .
        // a . b | c should parse as a . (b | c)
        let prog = parse_ok("def x = a . b | c");
        match &prog.stmts[0].kind {
            StmtKind::Def { body, .. } => match body.kind.as_ref() {
                ExprKind::Compose(_, rhs) => {
                    assert!(matches!(rhs.kind.as_ref(), ExprKind::Tensor(..)));
                }
                _ => panic!("expected Compose at top level"),
            },
            _ => panic!("expected Def"),
        }
    }

    #[test]
    fn test_pipeline() {
        let prog = parse_ok("def x = a >> b >> c");
        match &prog.stmts[0].kind {
            StmtKind::Def { body, .. } => match body.kind.as_ref() {
                ExprKind::Pipeline(lhs, _) => {
                    assert!(matches!(lhs.kind.as_ref(), ExprKind::Pipeline(..)));
                }
                _ => panic!("expected Pipeline"),
            },
            _ => panic!("expected Def"),
        }
    }

    // ----- Pattern matching -----

    #[test]
    fn test_pattern_match() {
        let prog = parse_ok(
            "def length(w) = match w with
               | identity => 0
               | s1 . rest => 1 + length(rest)
             end",
        );
        match &prog.stmts[0].kind {
            StmtKind::Def { body, .. } => match body.kind.as_ref() {
                ExprKind::Match { arms, .. } => {
                    assert_eq!(arms.len(), 2);
                    assert!(matches!(arms[0].pattern.kind, PatternKind::Identity));
                    assert!(matches!(arms[1].pattern.kind, PatternKind::Cons { .. }));
                }
                _ => panic!("expected Match"),
            },
            _ => panic!("expected Def"),
        }
    }

    #[test]
    fn test_wildcard_pattern() {
        let prog = parse_ok("def f(x) = match x with | _ => 0 end");
        match &prog.stmts[0].kind {
            StmtKind::Def { body, .. } => match body.kind.as_ref() {
                ExprKind::Match { arms, .. } => {
                    assert!(matches!(arms[0].pattern.kind, PatternKind::Wildcard));
                }
                _ => panic!("expected Match"),
            },
            _ => panic!("expected Def"),
        }
    }

    #[test]
    fn test_var_pattern() {
        let prog = parse_ok("def f(x) = match x with | y => y end");
        match &prog.stmts[0].kind {
            StmtKind::Def { body, .. } => match body.kind.as_ref() {
                ExprKind::Match { arms, .. } => {
                    assert!(matches!(&arms[0].pattern.kind, PatternKind::Var(n) if n == "y"));
                }
                _ => panic!("expected Match"),
            },
            _ => panic!("expected Def"),
        }
    }

    #[test]
    fn test_inverse_generator_pattern() {
        let prog = parse_ok("def f(w) = match w with | s2^-1 . rest => rest end");
        match &prog.stmts[0].kind {
            StmtKind::Def { body, .. } => match body.kind.as_ref() {
                ExprKind::Match { arms, .. } => match &arms[0].pattern.kind {
                    PatternKind::Cons { generator, .. } => {
                        assert_eq!(generator.index, 2);
                        assert!(generator.inverse);
                    }
                    _ => panic!("expected Cons pattern"),
                },
                _ => panic!("expected Match"),
            },
            _ => panic!("expected Def"),
        }
    }

    // ----- Let binding -----

    #[test]
    fn test_let_binding() {
        let prog = parse_ok("def x = let y = 1 in y + 2");
        match &prog.stmts[0].kind {
            StmtKind::Def { body, .. } => match body.kind.as_ref() {
                ExprKind::Let { name, .. } => {
                    assert_eq!(name, "y");
                }
                _ => panic!("expected Let"),
            },
            _ => panic!("expected Def"),
        }
    }

    // ----- Crossings and twists -----

    #[test]
    fn test_over_crossing() {
        let prog = parse_ok("def x = (a > b)");
        match &prog.stmts[0].kind {
            StmtKind::Def { body, .. } => match body.kind.as_ref() {
                ExprKind::CrossOver { a, b } => {
                    assert_eq!(a, "a");
                    assert_eq!(b, "b");
                }
                _ => panic!("expected CrossOver"),
            },
            _ => panic!("expected Def"),
        }
    }

    #[test]
    fn test_under_crossing() {
        let prog = parse_ok("def x = (a < b)");
        match &prog.stmts[0].kind {
            StmtKind::Def { body, .. } => {
                assert!(matches!(body.kind.as_ref(), ExprKind::CrossUnder { .. }));
            }
            _ => panic!("expected Def"),
        }
    }

    #[test]
    fn test_twist_ident() {
        let prog = parse_ok("def x = (~a)");
        match &prog.stmts[0].kind {
            StmtKind::Def { body, .. } => match body.kind.as_ref() {
                ExprKind::Twist(inner) => {
                    assert!(matches!(inner.kind.as_ref(), ExprKind::Var(n) if n == "a"));
                }
                _ => panic!("expected Twist"),
            },
            _ => panic!("expected Def"),
        }
    }

    #[test]
    fn test_twist_expr() {
        let prog = parse_ok("def x = (~(braid[s1]))");
        match &prog.stmts[0].kind {
            StmtKind::Def { body, .. } => match body.kind.as_ref() {
                ExprKind::Twist(inner) => {
                    assert!(matches!(inner.kind.as_ref(), ExprKind::BraidLit(_)));
                }
                _ => panic!("expected Twist"),
            },
            _ => panic!("expected Def"),
        }
    }

    // ----- Unary operations -----

    #[test]
    fn test_simplify() {
        let prog = parse_ok("assert simplify(braid[s1, s1^-1]) == identity");
        match &prog.stmts[0].kind {
            StmtKind::Assert { expr } => match expr.kind.as_ref() {
                ExprKind::Eq(lhs, rhs) => {
                    assert!(matches!(lhs.kind.as_ref(), ExprKind::Simplify(..)));
                    assert!(matches!(rhs.kind.as_ref(), ExprKind::Identity));
                }
                _ => panic!("expected Eq"),
            },
            _ => panic!("expected Assert"),
        }
    }

    #[test]
    fn test_close() {
        let prog = parse_ok("compute jones(close(braid[s1, s1, s1]))");
        match &prog.stmts[0].kind {
            StmtKind::Compute { expr, .. } => {
                assert!(matches!(expr.kind.as_ref(), ExprKind::Close(..)));
            }
            _ => panic!("expected Compute"),
        }
    }

    #[test]
    fn test_mirror_reverse() {
        let prog = parse_ok("def x = mirror(braid[s1])");
        match &prog.stmts[0].kind {
            StmtKind::Def { body, .. } => {
                assert!(matches!(body.kind.as_ref(), ExprKind::Mirror(..)));
            }
            _ => panic!("expected Def"),
        }

        let prog = parse_ok("def y = reverse(braid[s1])");
        match &prog.stmts[0].kind {
            StmtKind::Def { body, .. } => {
                assert!(matches!(body.kind.as_ref(), ExprKind::Reverse(..)));
            }
            _ => panic!("expected Def"),
        }
    }

    #[test]
    fn test_cap_cup() {
        let prog = parse_ok("def x = cap(a, b)");
        match &prog.stmts[0].kind {
            StmtKind::Def { body, .. } => {
                assert!(matches!(body.kind.as_ref(), ExprKind::Cap(..)));
            }
            _ => panic!("expected Def"),
        }

        let prog = parse_ok("def y = cup(a, b)");
        match &prog.stmts[0].kind {
            StmtKind::Def { body, .. } => {
                assert!(matches!(body.kind.as_ref(), ExprKind::Cup(..)));
            }
            _ => panic!("expected Def"),
        }
    }

    // ----- Function application -----

    #[test]
    fn test_function_call() {
        let prog = parse_ok("def x = f(a, b)");
        match &prog.stmts[0].kind {
            StmtKind::Def { body, .. } => match body.kind.as_ref() {
                ExprKind::App { func, args } => {
                    assert_eq!(func, "f");
                    assert_eq!(args.len(), 2);
                }
                _ => panic!("expected App"),
            },
            _ => panic!("expected Def"),
        }
    }

    #[test]
    fn test_recursive_call() {
        let prog = parse_ok("def f(x) = 1 + f(x)");
        match &prog.stmts[0].kind {
            StmtKind::Def { body, .. } => match body.kind.as_ref() {
                ExprKind::Add(_, rhs) => {
                    assert!(matches!(rhs.kind.as_ref(), ExprKind::App { .. }));
                }
                _ => panic!("expected Add"),
            },
            _ => panic!("expected Def"),
        }
    }

    // ----- Multiple statements -----

    #[test]
    fn test_multi_stmt_program() {
        let prog = parse_ok(
            "def trefoil = braid[s1, s1, s1]
             assert simplify(braid[s1, s1^-1]) == identity
             compute jones(close(trefoil))",
        );
        assert_eq!(prog.stmts.len(), 3);
        assert!(matches!(prog.stmts[0].kind, StmtKind::Def { .. }));
        assert!(matches!(prog.stmts[1].kind, StmtKind::Assert { .. }));
        assert!(matches!(prog.stmts[2].kind, StmtKind::Compute { .. }));
    }

    // ----- Parenthesized expressions -----

    #[test]
    fn test_parens() {
        let prog = parse_ok("def x = (a + b) * c");
        match &prog.stmts[0].kind {
            StmtKind::Def { body, .. } => match body.kind.as_ref() {
                ExprKind::Mul(lhs, _) => {
                    assert!(matches!(lhs.kind.as_ref(), ExprKind::Add(..)));
                }
                _ => panic!("expected Mul"),
            },
            _ => panic!("expected Def"),
        }
    }

    // ----- Comments -----

    #[test]
    fn test_comments_in_program() {
        let prog = parse_ok(
            "# Define trefoil
             def trefoil = braid[s1, s1, s1]
             (* Check simplification *)
             assert simplify(braid[s1, s1^-1]) == identity",
        );
        assert_eq!(prog.stmts.len(), 2);
    }

    // ----- Error cases -----

    #[test]
    fn test_missing_eq_in_def() {
        let err = parse_err("def x identity");
        assert!(err.message.contains("expected ="));
    }

    #[test]
    fn test_missing_end_in_match() {
        let err = parse_err("def f(x) = match x with | y => y");
        assert!(err.message.contains("expected end"));
    }

    #[test]
    fn test_empty_match() {
        let err = parse_err("def f(x) = match x with end");
        assert!(err.message.contains("at least one arm"));
    }

    // ----- Full spec examples -----

    #[test]
    fn test_spec_auto_widening() {
        let prog = parse_ok("assert braid[s1] . braid[s2] == braid[s1, s2]");
        assert_eq!(prog.stmts.len(), 1);
    }

    #[test]
    fn test_spec_simplification() {
        let prog = parse_ok("assert simplify(braid[s1, s1^-1]) == identity");
        assert_eq!(prog.stmts.len(), 1);
    }

    #[test]
    fn test_spec_length_function() {
        let prog = parse_ok(
            "def length(w) = match w with
               | identity => 0
               | s1 . rest => 1 + length(rest)
             end
             assert length(braid[s1, s2, s1]) == 3",
        );
        assert_eq!(prog.stmts.len(), 2);
    }

    #[test]
    fn test_spec_closure() {
        let prog = parse_ok("compute jones(close(braid[s1, s1, s1]))");
        assert_eq!(prog.stmts.len(), 1);
    }
}
