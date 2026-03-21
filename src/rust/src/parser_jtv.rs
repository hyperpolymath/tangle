// SPDX-License-Identifier: PMPL-1.0-or-later
// parser_jtv.rs — Parsers for TANGLE-JTV injection blocks
//
// Harvard data expression precedence (lowest to highest):
//   1. if ... then ... else ... (conditional, total)
//   2. || (logical or, left-assoc)
//   3. && (logical and, left-assoc)
//   4. ==, !=, <, <=, >, >= (comparison, non-assoc)
//   5. +, - (additive, left-assoc)
//   6. *, /, % (multiplicative, left-assoc)
//   7. -, ! (unary prefix)
//   8. primary (literals, identifiers, calls, parens, list, tuple)

use crate::ast_jtv::*;
use crate::lexer::{Span, TokenKind};
use crate::parser::{ParseError, Parser};

type Result<T> = std::result::Result<T, ParseError>;

impl Parser {
    /// In Harvard context, many TANGLE keywords can be used as identifiers.
    /// This method accepts both `Ident(name)` and TANGLE keywords that don't
    /// conflict with Harvard keywords.
    fn expect_hv_ident(&mut self) -> Result<String> {
        match self.peek().clone() {
            TokenKind::Ident(name) => {
                self.advance();
                Ok(name)
            }
            // TANGLE keywords that are valid as identifiers inside harvard/add blocks
            TokenKind::Add => { self.advance(); Ok("add".to_string()) }
            TokenKind::Braid => { self.advance(); Ok("braid".to_string()) }
            TokenKind::Close => { self.advance(); Ok("close".to_string()) }
            TokenKind::Compute => { self.advance(); Ok("compute".to_string()) }
            TokenKind::Cup => { self.advance(); Ok("cup".to_string()) }
            TokenKind::Cap => { self.advance(); Ok("cap".to_string()) }
            TokenKind::Def => { self.advance(); Ok("def".to_string()) }
            TokenKind::Identity => { self.advance(); Ok("identity".to_string()) }
            TokenKind::Mirror => { self.advance(); Ok("mirror".to_string()) }
            TokenKind::Simplify => { self.advance(); Ok("simplify".to_string()) }
            TokenKind::Strands => { self.advance(); Ok("strands".to_string()) }
            TokenKind::Weave => { self.advance(); Ok("weave".to_string()) }
            TokenKind::Yield => { self.advance(); Ok("yield".to_string()) }
            TokenKind::Assert => { self.advance(); Ok("assert".to_string()) }
            TokenKind::Harvard => { self.advance(); Ok("harvard".to_string()) }
            TokenKind::End => { self.advance(); Ok("end".to_string()) }
            TokenKind::Match => { self.advance(); Ok("match".to_string()) }
            TokenKind::With => { self.advance(); Ok("with".to_string()) }
            // `Reverse` is both a TANGLE keyword and a Harvard keyword,
            // but as a statement keyword it's handled before we get here.
            other => Err(ParseError {
                message: format!("expected identifier, found {other}"),
                span: self.span(),
            }),
        }
    }

    /// Check if the current token can be treated as an identifier in Harvard context.
    fn is_hv_ident(&self) -> bool {
        matches!(
            self.peek(),
            TokenKind::Ident(_)
                | TokenKind::Add
                | TokenKind::Braid
                | TokenKind::Close
                | TokenKind::Compute
                | TokenKind::Cup
                | TokenKind::Cap
                | TokenKind::Def
                | TokenKind::Identity
                | TokenKind::Mirror
                | TokenKind::Simplify
                | TokenKind::Strands
                | TokenKind::Weave
                | TokenKind::Yield
                | TokenKind::Assert
                | TokenKind::Harvard
                | TokenKind::End
                | TokenKind::Match
                | TokenKind::With
        )
    }
}

/// Extension methods on Parser for JTV blocks.
impl Parser {
    // ================================================================
    // add{ hv_data_expr }
    // ================================================================

    /// Parse an `add{ hv_data_expr }` block — called when `add` token is current.
    /// The `add` keyword has already been consumed. Expects `{`, data expr, `}`.
    pub(crate) fn parse_add_block(&mut self) -> Result<HvDataExpr> {
        self.expect(&TokenKind::LBrace)?;
        let expr = self.parse_hv_data_expr()?;
        self.expect(&TokenKind::RBrace)?;
        Ok(expr)
    }

    // ================================================================
    // harvard{ hv_program }
    // ================================================================

    /// Parse a `harvard{ hv_program }` block — called when `harvard` keyword is current.
    /// The `harvard` keyword has already been consumed. Expects `{`, items, `}`.
    pub(crate) fn parse_harvard_block(&mut self) -> Result<HvProgram> {
        self.expect(&TokenKind::LBrace)?;
        let mut items = Vec::new();
        while !self.check(&TokenKind::RBrace) && !self.at_eof() {
            items.push(self.parse_hv_item()?);
        }
        self.expect(&TokenKind::RBrace)?;
        Ok(HvProgram { items })
    }

    // ================================================================
    // Harvard data expressions (total language)
    // ================================================================

    /// Top-level data expression: conditional or logical_or.
    pub(crate) fn parse_hv_data_expr(&mut self) -> Result<HvDataExpr> {
        if self.check(&TokenKind::If) {
            self.parse_hv_conditional()
        } else {
            self.parse_hv_logical_or()
        }
    }

    /// `if cond then then_branch else else_branch`
    fn parse_hv_conditional(&mut self) -> Result<HvDataExpr> {
        let span = self.span();
        self.expect(&TokenKind::If)?;
        let cond = self.parse_hv_data_expr()?;
        self.expect(&TokenKind::Then)?;
        let then_branch = self.parse_hv_data_expr()?;
        self.expect(&TokenKind::Else)?;
        let else_branch = self.parse_hv_data_expr()?;
        Ok(HvDataExpr::new(
            HvDataExprKind::Conditional {
                cond,
                then_branch,
                else_branch,
            },
            span,
        ))
    }

    /// Logical or: `logical_and { || logical_and }`
    fn parse_hv_logical_or(&mut self) -> Result<HvDataExpr> {
        let mut left = self.parse_hv_logical_and()?;
        while self.check(&TokenKind::PipePipe) {
            let span = self.span();
            self.advance();
            let right = self.parse_hv_logical_and()?;
            left = HvDataExpr::new(
                HvDataExprKind::BinOp {
                    op: HvBinOp::Or,
                    lhs: left,
                    rhs: right,
                },
                span,
            );
        }
        Ok(left)
    }

    /// Logical and: `comparison { && comparison }`
    fn parse_hv_logical_and(&mut self) -> Result<HvDataExpr> {
        let mut left = self.parse_hv_comparison()?;
        while self.check(&TokenKind::AmpAmp) {
            let span = self.span();
            self.advance();
            let right = self.parse_hv_comparison()?;
            left = HvDataExpr::new(
                HvDataExprKind::BinOp {
                    op: HvBinOp::And,
                    lhs: left,
                    rhs: right,
                },
                span,
            );
        }
        Ok(left)
    }

    /// Comparison: `additive [ comparator additive ]` (non-associative)
    fn parse_hv_comparison(&mut self) -> Result<HvDataExpr> {
        let left = self.parse_hv_additive()?;
        let op = match self.peek() {
            TokenKind::EqEq => Some(HvBinOp::Eq),
            TokenKind::BangEq => Some(HvBinOp::NotEq),
            TokenKind::Lt => Some(HvBinOp::Lt),
            TokenKind::LtEq => Some(HvBinOp::LtEq),
            TokenKind::Gt => Some(HvBinOp::Gt),
            TokenKind::GtEq => Some(HvBinOp::GtEq),
            _ => None,
        };
        if let Some(op) = op {
            let span = self.span();
            self.advance();
            let right = self.parse_hv_additive()?;
            Ok(HvDataExpr::new(
                HvDataExprKind::BinOp {
                    op,
                    lhs: left,
                    rhs: right,
                },
                span,
            ))
        } else {
            Ok(left)
        }
    }

    /// Additive: `multiplicative { (+ | -) multiplicative }`
    fn parse_hv_additive(&mut self) -> Result<HvDataExpr> {
        let mut left = self.parse_hv_multiplicative()?;
        loop {
            let op = match self.peek() {
                TokenKind::Plus => Some(HvBinOp::Add),
                TokenKind::Minus => Some(HvBinOp::Sub),
                _ => None,
            };
            if let Some(op) = op {
                let span = self.span();
                self.advance();
                let right = self.parse_hv_multiplicative()?;
                left = HvDataExpr::new(
                    HvDataExprKind::BinOp {
                        op,
                        lhs: left,
                        rhs: right,
                    },
                    span,
                );
            } else {
                break;
            }
        }
        Ok(left)
    }

    /// Multiplicative: `unary { (* | / | %) unary }`
    fn parse_hv_multiplicative(&mut self) -> Result<HvDataExpr> {
        let mut left = self.parse_hv_unary()?;
        loop {
            let op = match self.peek() {
                TokenKind::Star => Some(HvBinOp::Mul),
                TokenKind::Slash => Some(HvBinOp::Div),
                TokenKind::Percent => Some(HvBinOp::Mod),
                _ => None,
            };
            if let Some(op) = op {
                let span = self.span();
                self.advance();
                let right = self.parse_hv_unary()?;
                left = HvDataExpr::new(
                    HvDataExprKind::BinOp {
                        op,
                        lhs: left,
                        rhs: right,
                    },
                    span,
                );
            } else {
                break;
            }
        }
        Ok(left)
    }

    /// Unary: `-factor`, `!factor`, or `factor`
    fn parse_hv_unary(&mut self) -> Result<HvDataExpr> {
        let span = self.span();
        match self.peek() {
            TokenKind::Minus => {
                self.advance();
                let operand = self.parse_hv_factor()?;
                Ok(HvDataExpr::new(
                    HvDataExprKind::UnaryOp {
                        op: HvUnaryOp::Neg,
                        operand,
                    },
                    span,
                ))
            }
            TokenKind::Bang => {
                self.advance();
                let operand = self.parse_hv_factor()?;
                Ok(HvDataExpr::new(
                    HvDataExprKind::UnaryOp {
                        op: HvUnaryOp::Not,
                        operand,
                    },
                    span,
                ))
            }
            _ => self.parse_hv_factor(),
        }
    }

    /// Factor (primary): literals, identifiers/calls, parens, list, tuple.
    fn parse_hv_factor(&mut self) -> Result<HvDataExpr> {
        let span = self.span();
        match self.peek().clone() {
            TokenKind::Integer(n) => {
                self.advance();
                Ok(HvDataExpr::new(HvDataExprKind::IntLit(n), span))
            }
            TokenKind::Float(n) => {
                self.advance();
                Ok(HvDataExpr::new(HvDataExprKind::FloatLit(n), span))
            }
            TokenKind::HexLit(n) => {
                self.advance();
                Ok(HvDataExpr::new(HvDataExprKind::IntLit(n as i64), span))
            }
            TokenKind::BinaryLit(n) => {
                self.advance();
                Ok(HvDataExpr::new(HvDataExprKind::IntLit(n as i64), span))
            }
            TokenKind::StringLit(s) => {
                self.advance();
                Ok(HvDataExpr::new(HvDataExprKind::StrLit(s), span))
            }
            TokenKind::True => {
                self.advance();
                Ok(HvDataExpr::new(HvDataExprKind::BoolLit(true), span))
            }
            TokenKind::False => {
                self.advance();
                Ok(HvDataExpr::new(HvDataExprKind::BoolLit(false), span))
            }

            // Identifier or function call (including TANGLE keywords used as names)
            _ if self.is_hv_ident() => {
                let name = self.expect_hv_ident()?;
                if self.eat(&TokenKind::LParen) {
                    let args = if !self.check(&TokenKind::RParen) {
                        self.parse_hv_arg_list()?
                    } else {
                        Vec::new()
                    };
                    self.expect(&TokenKind::RParen)?;
                    Ok(HvDataExpr::new(
                        HvDataExprKind::Call { func: name, args },
                        span,
                    ))
                } else {
                    Ok(HvDataExpr::new(HvDataExprKind::Var(name), span))
                }
            }

            // List literal: [e1, e2, ...]
            TokenKind::LBracket => {
                self.advance();
                let mut elems = Vec::new();
                if !self.check(&TokenKind::RBracket) {
                    elems.push(self.parse_hv_data_expr()?);
                    while self.eat(&TokenKind::Comma) {
                        elems.push(self.parse_hv_data_expr()?);
                    }
                }
                self.expect(&TokenKind::RBracket)?;
                Ok(HvDataExpr::new(HvDataExprKind::ListLit(elems), span))
            }

            // Parenthesized expression or tuple literal
            TokenKind::LParen => {
                self.advance();
                let first = self.parse_hv_data_expr()?;
                if self.eat(&TokenKind::Comma) {
                    // Tuple: (e1, e2, ...)
                    let mut elems = vec![first];
                    elems.push(self.parse_hv_data_expr()?);
                    while self.eat(&TokenKind::Comma) {
                        elems.push(self.parse_hv_data_expr()?);
                    }
                    self.expect(&TokenKind::RParen)?;
                    Ok(HvDataExpr::new(HvDataExprKind::TupleLit(elems), span))
                } else {
                    // Parenthesized expression
                    self.expect(&TokenKind::RParen)?;
                    Ok(first)
                }
            }

            other => Err(ParseError {
                message: format!("expected Harvard data expression, found {other}"),
                span,
            }),
        }
    }

    /// Parse comma-separated Harvard data expression list.
    fn parse_hv_arg_list(&mut self) -> Result<Vec<HvDataExpr>> {
        let mut args = vec![self.parse_hv_data_expr()?];
        while self.eat(&TokenKind::Comma) {
            args.push(self.parse_hv_data_expr()?);
        }
        Ok(args)
    }

    // ================================================================
    // Harvard program items (modules, imports, fn decls, stmts)
    // ================================================================

    /// Parse a single Harvard item.
    fn parse_hv_item(&mut self) -> Result<HvItem> {
        let span = self.span();
        match self.peek() {
            TokenKind::Module => self.parse_hv_module(span),
            TokenKind::Import => self.parse_hv_import(span),
            TokenKind::Fn => {
                let decl = self.parse_hv_fn_decl()?;
                Ok(HvItem {
                    kind: HvItemKind::FnDecl(decl),
                    span,
                })
            }
            _ => {
                let stmt = self.parse_hv_control_stmt()?;
                Ok(HvItem {
                    kind: HvItemKind::Stmt(stmt),
                    span,
                })
            }
        }
    }

    /// `module name { ... }`
    fn parse_hv_module(&mut self, span: Span) -> Result<HvItem> {
        self.expect(&TokenKind::Module)?;
        let name = self.expect_hv_ident()?;
        self.expect(&TokenKind::LBrace)?;
        let mut body = Vec::new();
        while !self.check(&TokenKind::RBrace) && !self.at_eof() {
            body.push(self.parse_hv_item()?);
        }
        self.expect(&TokenKind::RBrace)?;
        Ok(HvItem {
            kind: HvItemKind::Module { name, body },
            span,
        })
    }

    /// `import path.to.module [as alias]`
    fn parse_hv_import(&mut self, span: Span) -> Result<HvItem> {
        self.expect(&TokenKind::Import)?;
        let mut path = vec![self.expect_hv_ident()?];
        while self.eat(&TokenKind::Dot) {
            path.push(self.expect_hv_ident()?);
        }
        let alias = if self.eat(&TokenKind::As) {
            Some(self.expect_hv_ident()?)
        } else {
            None
        };
        Ok(HvItem {
            kind: HvItemKind::Import { path, alias },
            span,
        })
    }

    /// `fn name(params) [: return_type] [@pure|@total] { stmts }`
    fn parse_hv_fn_decl(&mut self) -> Result<HvFnDecl> {
        let span = self.span();
        self.expect(&TokenKind::Fn)?;
        let name = self.expect_hv_ident()?;
        self.expect(&TokenKind::LParen)?;
        let params = if !self.check(&TokenKind::RParen) {
            self.parse_hv_param_list()?
        } else {
            Vec::new()
        };
        self.expect(&TokenKind::RParen)?;

        // Optional return type: `: Type`
        let return_type = if self.eat(&TokenKind::Colon) {
            Some(self.parse_hv_type()?)
        } else {
            None
        };

        // Optional purity marker: @pure or @total
        let purity = match self.peek() {
            TokenKind::AtPure => {
                self.advance();
                Some(HvPurity::Pure)
            }
            TokenKind::AtTotal => {
                self.advance();
                Some(HvPurity::Total)
            }
            _ => None,
        };

        // Body: { stmts }
        self.expect(&TokenKind::LBrace)?;
        let mut body = Vec::new();
        while !self.check(&TokenKind::RBrace) && !self.at_eof() {
            body.push(self.parse_hv_control_stmt()?);
        }
        self.expect(&TokenKind::RBrace)?;

        Ok(HvFnDecl {
            name,
            params,
            return_type,
            purity,
            body,
            span,
        })
    }

    /// Parse parameter list: `name [: type], ...`
    fn parse_hv_param_list(&mut self) -> Result<Vec<HvParam>> {
        let mut params = vec![self.parse_hv_param()?];
        while self.eat(&TokenKind::Comma) {
            params.push(self.parse_hv_param()?);
        }
        Ok(params)
    }

    /// Parse a single parameter: `name [: type]`
    fn parse_hv_param(&mut self) -> Result<HvParam> {
        let name = self.expect_hv_ident()?;
        let type_ann = if self.eat(&TokenKind::Colon) {
            Some(self.parse_hv_type()?)
        } else {
            None
        };
        Ok(HvParam { name, type_ann })
    }

    /// Parse a type annotation.
    fn parse_hv_type(&mut self) -> Result<HvType> {
        match self.peek().clone() {
            // Tuple type: (T1, T2, ...)
            TokenKind::LParen => {
                self.advance();
                let first = self.parse_hv_type()?;
                if self.eat(&TokenKind::Comma) {
                    let mut types = vec![first];
                    types.push(self.parse_hv_type()?);
                    while self.eat(&TokenKind::Comma) {
                        types.push(self.parse_hv_type()?);
                    }
                    self.expect(&TokenKind::RParen)?;
                    Ok(HvType::Tuple(types))
                } else {
                    self.expect(&TokenKind::RParen)?;
                    Ok(first)
                }
            }

            // Named type — might be `List<T>`, `Fn(T) -> R`, or basic
            TokenKind::Ident(name) => {
                self.advance();
                if name == "Fn" && self.eat(&TokenKind::LParen) {
                    let mut params = Vec::new();
                    if !self.check(&TokenKind::RParen) {
                        params.push(self.parse_hv_type()?);
                        while self.eat(&TokenKind::Comma) {
                            params.push(self.parse_hv_type()?);
                        }
                    }
                    self.expect(&TokenKind::RParen)?;
                    self.expect(&TokenKind::Arrow)?;
                    let ret = self.parse_hv_type()?;
                    return Ok(HvType::Func {
                        params,
                        ret: Box::new(ret),
                    });
                }
                if name == "List" && self.eat(&TokenKind::Lt) {
                    let inner = self.parse_hv_type()?;
                    self.expect(&TokenKind::Gt)?;
                    Ok(HvType::List(Box::new(inner)))
                } else {
                    Ok(HvType::Basic(name))
                }
            }

            other => Err(ParseError {
                message: format!("expected type annotation, found {other}"),
                span: self.span(),
            }),
        }
    }

    // ================================================================
    // Harvard control statements
    // ================================================================

    /// Parse a single control statement.
    pub(crate) fn parse_hv_control_stmt(&mut self) -> Result<HvStmt> {
        let span = self.span();
        match self.peek() {
            TokenKind::If => self.parse_hv_if(span),
            TokenKind::While => self.parse_hv_while(span),
            TokenKind::For => self.parse_hv_for(span),
            TokenKind::Return => self.parse_hv_return(span),
            TokenKind::Print => self.parse_hv_print(span),
            TokenKind::Reverse => self.parse_hv_reverse(span),
            TokenKind::LBrace => self.parse_hv_bare_block(span),
            // Assignment: ident = expr (including TANGLE keywords as variable names)
            _ if self.is_hv_ident() => self.parse_hv_assignment(span),
            other => Err(ParseError {
                message: format!(
                    "expected Harvard statement (if, while, for, return, print, assignment), found {other}"
                ),
                span,
            }),
        }
    }

    /// `x = expr`
    fn parse_hv_assignment(&mut self, span: Span) -> Result<HvStmt> {
        let target = self.expect_hv_ident()?;
        self.expect(&TokenKind::Eq)?;
        let value = self.parse_hv_data_expr()?;
        Ok(HvStmt {
            kind: HvStmtKind::Assignment { target, value },
            span,
        })
    }

    /// `if cond { stmts } [else { stmts }]`
    fn parse_hv_if(&mut self, span: Span) -> Result<HvStmt> {
        self.expect(&TokenKind::If)?;
        let cond = self.parse_hv_data_expr()?;
        self.expect(&TokenKind::LBrace)?;
        let then_body = self.parse_hv_stmt_list()?;
        self.expect(&TokenKind::RBrace)?;

        let else_body = if self.eat(&TokenKind::Else) {
            self.expect(&TokenKind::LBrace)?;
            let stmts = self.parse_hv_stmt_list()?;
            self.expect(&TokenKind::RBrace)?;
            Some(stmts)
        } else {
            None
        };

        Ok(HvStmt {
            kind: HvStmtKind::If {
                cond,
                then_body,
                else_body,
            },
            span,
        })
    }

    /// `while cond { stmts }`
    fn parse_hv_while(&mut self, span: Span) -> Result<HvStmt> {
        self.expect(&TokenKind::While)?;
        let cond = self.parse_hv_data_expr()?;
        self.expect(&TokenKind::LBrace)?;
        let body = self.parse_hv_stmt_list()?;
        self.expect(&TokenKind::RBrace)?;
        Ok(HvStmt {
            kind: HvStmtKind::While { cond, body },
            span,
        })
    }

    /// `for x in start..end[..step] { stmts }`
    fn parse_hv_for(&mut self, span: Span) -> Result<HvStmt> {
        self.expect(&TokenKind::For)?;
        let var = self.expect_hv_ident()?;
        self.expect(&TokenKind::In)?;
        let start = self.parse_hv_data_expr()?;
        self.expect(&TokenKind::DotDot)?;
        let end = self.parse_hv_data_expr()?;
        let step = if self.eat(&TokenKind::DotDot) {
            Some(self.parse_hv_data_expr()?)
        } else {
            None
        };
        self.expect(&TokenKind::LBrace)?;
        let body = self.parse_hv_stmt_list()?;
        self.expect(&TokenKind::RBrace)?;
        Ok(HvStmt {
            kind: HvStmtKind::For {
                var,
                start,
                end,
                step,
                body,
            },
            span,
        })
    }

    /// `return [expr]`
    fn parse_hv_return(&mut self, span: Span) -> Result<HvStmt> {
        self.expect(&TokenKind::Return)?;
        // Return value is optional — check if the next token could start an expression
        let value = if !self.check(&TokenKind::RBrace)
            && !self.at_eof()
            && self.can_start_hv_expr()
        {
            Some(self.parse_hv_data_expr()?)
        } else {
            None
        };
        Ok(HvStmt {
            kind: HvStmtKind::Return { value },
            span,
        })
    }

    /// `print(e1, e2, ...)`
    fn parse_hv_print(&mut self, span: Span) -> Result<HvStmt> {
        self.expect(&TokenKind::Print)?;
        self.expect(&TokenKind::LParen)?;
        let args = self.parse_hv_arg_list()?;
        self.expect(&TokenKind::RParen)?;
        Ok(HvStmt {
            kind: HvStmtKind::Print { args },
            span,
        })
    }

    /// `reverse { reversible_stmts }`
    fn parse_hv_reverse(&mut self, span: Span) -> Result<HvStmt> {
        self.expect(&TokenKind::Reverse)?;
        self.expect(&TokenKind::LBrace)?;
        let mut body = Vec::new();
        while !self.check(&TokenKind::RBrace) && !self.at_eof() {
            body.push(self.parse_hv_reversible_stmt()?);
        }
        self.expect(&TokenKind::RBrace)?;
        Ok(HvStmt {
            kind: HvStmtKind::ReverseBlock { body },
            span,
        })
    }

    /// `{ stmts }` — bare block
    fn parse_hv_bare_block(&mut self, span: Span) -> Result<HvStmt> {
        self.expect(&TokenKind::LBrace)?;
        let body = self.parse_hv_stmt_list()?;
        self.expect(&TokenKind::RBrace)?;
        Ok(HvStmt {
            kind: HvStmtKind::Block { body },
            span,
        })
    }

    /// Parse statements until `}`.
    fn parse_hv_stmt_list(&mut self) -> Result<Vec<HvStmt>> {
        let mut stmts = Vec::new();
        while !self.check(&TokenKind::RBrace) && !self.at_eof() {
            stmts.push(self.parse_hv_control_stmt()?);
        }
        Ok(stmts)
    }

    /// Parse a reversible statement: `x += expr`, `x -= expr`, or `if`.
    fn parse_hv_reversible_stmt(&mut self) -> Result<HvReversibleStmt> {
        let span = self.span();
        match self.peek() {
            TokenKind::If => {
                self.expect(&TokenKind::If)?;
                let cond = self.parse_hv_data_expr()?;
                self.expect(&TokenKind::LBrace)?;
                let mut then_body = Vec::new();
                while !self.check(&TokenKind::RBrace) && !self.at_eof() {
                    then_body.push(self.parse_hv_reversible_stmt()?);
                }
                self.expect(&TokenKind::RBrace)?;
                let else_body = if self.eat(&TokenKind::Else) {
                    self.expect(&TokenKind::LBrace)?;
                    let mut stmts = Vec::new();
                    while !self.check(&TokenKind::RBrace) && !self.at_eof() {
                        stmts.push(self.parse_hv_reversible_stmt()?);
                    }
                    self.expect(&TokenKind::RBrace)?;
                    Some(stmts)
                } else {
                    None
                };
                Ok(HvReversibleStmt {
                    kind: HvReversibleStmtKind::If {
                        cond,
                        then_body,
                        else_body,
                    },
                    span,
                })
            }
            TokenKind::Ident(_) => {
                let target = self.expect_hv_ident()?;
                match self.peek() {
                    TokenKind::PlusEq => {
                        self.advance();
                        let value = self.parse_hv_data_expr()?;
                        Ok(HvReversibleStmt {
                            kind: HvReversibleStmtKind::AddAssign { target, value },
                            span,
                        })
                    }
                    TokenKind::MinusEq => {
                        self.advance();
                        let value = self.parse_hv_data_expr()?;
                        Ok(HvReversibleStmt {
                            kind: HvReversibleStmtKind::SubAssign { target, value },
                            span,
                        })
                    }
                    other => Err(ParseError {
                        message: format!(
                            "expected += or -= in reverse block, found {other}"
                        ),
                        span: self.span(),
                    }),
                }
            }
            other => Err(ParseError {
                message: format!(
                    "expected reversible statement (ident += / -=, or if), found {other}"
                ),
                span,
            }),
        }
    }

    /// Check if the current token could start an hv_data_expr.
    fn can_start_hv_expr(&self) -> bool {
        matches!(
            self.peek(),
            TokenKind::Integer(_)
                | TokenKind::Float(_)
                | TokenKind::HexLit(_)
                | TokenKind::BinaryLit(_)
                | TokenKind::StringLit(_)
                | TokenKind::True
                | TokenKind::False
                | TokenKind::Ident(_)
                | TokenKind::LParen
                | TokenKind::LBracket
                | TokenKind::Minus
                | TokenKind::Bang
                | TokenKind::If
        )
    }
}

#[cfg(test)]
mod tests {
    use crate::ast::*;
    use crate::ast_jtv::*;
    use crate::parser::parse;

    fn parse_ok(src: &str) -> Program {
        parse(src).unwrap_or_else(|e| panic!("parse error: {e}"))
    }

    fn parse_err(src: &str) -> crate::parser::ParseError {
        parse(src).unwrap_err()
    }

    // ---- add{} block tests ----

    #[test]
    fn test_add_simple_arithmetic() {
        let prog = parse_ok("def x = add{1 + 2 + 3}");
        match &prog.stmts[0].kind {
            StmtKind::Def { body, .. } => match body.kind.as_ref() {
                ExprKind::AddBlock { expr } => match expr.kind.as_ref() {
                    HvDataExprKind::BinOp {
                        op: HvBinOp::Add,
                        lhs,
                        ..
                    } => {
                        // (1 + 2) + 3 — left-assoc
                        assert!(matches!(lhs.kind.as_ref(), HvDataExprKind::BinOp { .. }));
                    }
                    _ => panic!("expected BinOp Add"),
                },
                _ => panic!("expected AddBlock"),
            },
            _ => panic!("expected Def"),
        }
    }

    #[test]
    fn test_add_precedence() {
        // * binds tighter than +
        let prog = parse_ok("def x = add{1 + 2 * 3}");
        match &prog.stmts[0].kind {
            StmtKind::Def { body, .. } => match body.kind.as_ref() {
                ExprKind::AddBlock { expr } => match expr.kind.as_ref() {
                    HvDataExprKind::BinOp {
                        op: HvBinOp::Add,
                        rhs,
                        ..
                    } => {
                        assert!(matches!(
                            rhs.kind.as_ref(),
                            HvDataExprKind::BinOp {
                                op: HvBinOp::Mul,
                                ..
                            }
                        ));
                    }
                    _ => panic!("expected BinOp Add"),
                },
                _ => panic!("expected AddBlock"),
            },
            _ => panic!("expected Def"),
        }
    }

    #[test]
    fn test_add_comparison() {
        let prog = parse_ok("def x = add{a == b}");
        match &prog.stmts[0].kind {
            StmtKind::Def { body, .. } => match body.kind.as_ref() {
                ExprKind::AddBlock { expr } => {
                    assert!(matches!(
                        expr.kind.as_ref(),
                        HvDataExprKind::BinOp {
                            op: HvBinOp::Eq,
                            ..
                        }
                    ));
                }
                _ => panic!("expected AddBlock"),
            },
            _ => panic!("expected Def"),
        }
    }

    #[test]
    fn test_add_logical() {
        let prog = parse_ok("def x = add{a && b || c}");
        match &prog.stmts[0].kind {
            StmtKind::Def { body, .. } => match body.kind.as_ref() {
                ExprKind::AddBlock { expr } => {
                    // || is lower precedence than &&, so (a && b) || c
                    assert!(matches!(
                        expr.kind.as_ref(),
                        HvDataExprKind::BinOp {
                            op: HvBinOp::Or,
                            ..
                        }
                    ));
                }
                _ => panic!("expected AddBlock"),
            },
            _ => panic!("expected Def"),
        }
    }

    #[test]
    fn test_add_conditional() {
        let prog = parse_ok("def x = add{if true then 1 else 0}");
        match &prog.stmts[0].kind {
            StmtKind::Def { body, .. } => match body.kind.as_ref() {
                ExprKind::AddBlock { expr } => {
                    assert!(matches!(
                        expr.kind.as_ref(),
                        HvDataExprKind::Conditional { .. }
                    ));
                }
                _ => panic!("expected AddBlock"),
            },
            _ => panic!("expected Def"),
        }
    }

    #[test]
    fn test_add_unary_negation() {
        let prog = parse_ok("def x = add{-42}");
        match &prog.stmts[0].kind {
            StmtKind::Def { body, .. } => match body.kind.as_ref() {
                ExprKind::AddBlock { expr } => {
                    assert!(matches!(
                        expr.kind.as_ref(),
                        HvDataExprKind::UnaryOp {
                            op: HvUnaryOp::Neg,
                            ..
                        }
                    ));
                }
                _ => panic!("expected AddBlock"),
            },
            _ => panic!("expected Def"),
        }
    }

    #[test]
    fn test_add_function_call() {
        let prog = parse_ok("def x = add{max(a, b)}");
        match &prog.stmts[0].kind {
            StmtKind::Def { body, .. } => match body.kind.as_ref() {
                ExprKind::AddBlock { expr } => match expr.kind.as_ref() {
                    HvDataExprKind::Call { func, args } => {
                        assert_eq!(func, "max");
                        assert_eq!(args.len(), 2);
                    }
                    _ => panic!("expected Call"),
                },
                _ => panic!("expected AddBlock"),
            },
            _ => panic!("expected Def"),
        }
    }

    #[test]
    fn test_add_list_literal() {
        let prog = parse_ok("def x = add{[1, 2, 3]}");
        match &prog.stmts[0].kind {
            StmtKind::Def { body, .. } => match body.kind.as_ref() {
                ExprKind::AddBlock { expr } => match expr.kind.as_ref() {
                    HvDataExprKind::ListLit(elems) => assert_eq!(elems.len(), 3),
                    _ => panic!("expected ListLit"),
                },
                _ => panic!("expected AddBlock"),
            },
            _ => panic!("expected Def"),
        }
    }

    #[test]
    fn test_add_tuple_literal() {
        let prog = parse_ok("def x = add{(1, 2)}");
        match &prog.stmts[0].kind {
            StmtKind::Def { body, .. } => match body.kind.as_ref() {
                ExprKind::AddBlock { expr } => match expr.kind.as_ref() {
                    HvDataExprKind::TupleLit(elems) => assert_eq!(elems.len(), 2),
                    _ => panic!("expected TupleLit"),
                },
                _ => panic!("expected AddBlock"),
            },
            _ => panic!("expected Def"),
        }
    }

    #[test]
    fn test_add_modulo() {
        let prog = parse_ok("def x = add{10 % 3}");
        match &prog.stmts[0].kind {
            StmtKind::Def { body, .. } => match body.kind.as_ref() {
                ExprKind::AddBlock { expr } => {
                    assert!(matches!(
                        expr.kind.as_ref(),
                        HvDataExprKind::BinOp {
                            op: HvBinOp::Mod,
                            ..
                        }
                    ));
                }
                _ => panic!("expected AddBlock"),
            },
            _ => panic!("expected Def"),
        }
    }

    #[test]
    fn test_add_not() {
        let prog = parse_ok("def x = add{!flag}");
        match &prog.stmts[0].kind {
            StmtKind::Def { body, .. } => match body.kind.as_ref() {
                ExprKind::AddBlock { expr } => {
                    assert!(matches!(
                        expr.kind.as_ref(),
                        HvDataExprKind::UnaryOp {
                            op: HvUnaryOp::Not,
                            ..
                        }
                    ));
                }
                _ => panic!("expected AddBlock"),
            },
            _ => panic!("expected Def"),
        }
    }

    // ---- Mode boundary test ----

    #[test]
    fn test_add_plus_is_arithmetic_outside_is_union() {
        // Inside add{}, + is arithmetic; outside, + is TANGLE union
        let prog = parse_ok("def x = add{1 + 2} + identity");
        match &prog.stmts[0].kind {
            StmtKind::Def { body, .. } => {
                // Outer + is TANGLE Add (union)
                assert!(matches!(body.kind.as_ref(), ExprKind::Add(_, _)));
            }
            _ => panic!("expected Def"),
        }
    }

    // ---- harvard{} block tests ----

    #[test]
    fn test_harvard_assignment() {
        let prog = parse_ok("harvard{ x = 42 }");
        match &prog.stmts[0].kind {
            StmtKind::HarvardBlock { program } => {
                assert_eq!(program.items.len(), 1);
                match &program.items[0].kind {
                    HvItemKind::Stmt(stmt) => match &stmt.kind {
                        HvStmtKind::Assignment { target, .. } => {
                            assert_eq!(target, "x");
                        }
                        _ => panic!("expected Assignment"),
                    },
                    _ => panic!("expected Stmt"),
                }
            }
            _ => panic!("expected HarvardBlock"),
        }
    }

    #[test]
    fn test_harvard_if_else() {
        let prog = parse_ok("harvard{ if x > 0 { y = 1 } else { y = 0 } }");
        match &prog.stmts[0].kind {
            StmtKind::HarvardBlock { program } => {
                assert_eq!(program.items.len(), 1);
                match &program.items[0].kind {
                    HvItemKind::Stmt(stmt) => match &stmt.kind {
                        HvStmtKind::If {
                            else_body: Some(else_stmts),
                            ..
                        } => {
                            assert_eq!(else_stmts.len(), 1);
                        }
                        _ => panic!("expected If with else"),
                    },
                    _ => panic!("expected Stmt"),
                }
            }
            _ => panic!("expected HarvardBlock"),
        }
    }

    #[test]
    fn test_harvard_while() {
        let prog = parse_ok("harvard{ while n > 0 { n = n - 1 } }");
        match &prog.stmts[0].kind {
            StmtKind::HarvardBlock { program } => match &program.items[0].kind {
                HvItemKind::Stmt(stmt) => {
                    assert!(matches!(stmt.kind, HvStmtKind::While { .. }));
                }
                _ => panic!("expected Stmt"),
            },
            _ => panic!("expected HarvardBlock"),
        }
    }

    #[test]
    fn test_harvard_for_loop() {
        let prog = parse_ok("harvard{ for i in 0..10 { x = x + i } }");
        match &prog.stmts[0].kind {
            StmtKind::HarvardBlock { program } => match &program.items[0].kind {
                HvItemKind::Stmt(stmt) => match &stmt.kind {
                    HvStmtKind::For { var, .. } => assert_eq!(var, "i"),
                    _ => panic!("expected For"),
                },
                _ => panic!("expected Stmt"),
            },
            _ => panic!("expected HarvardBlock"),
        }
    }

    #[test]
    fn test_harvard_return() {
        let prog = parse_ok("harvard{ return 42 }");
        match &prog.stmts[0].kind {
            StmtKind::HarvardBlock { program } => match &program.items[0].kind {
                HvItemKind::Stmt(stmt) => match &stmt.kind {
                    HvStmtKind::Return { value: Some(v) } => {
                        assert!(matches!(v.kind.as_ref(), HvDataExprKind::IntLit(42)));
                    }
                    _ => panic!("expected Return with value"),
                },
                _ => panic!("expected Stmt"),
            },
            _ => panic!("expected HarvardBlock"),
        }
    }

    #[test]
    fn test_harvard_print() {
        let prog = parse_ok("harvard{ print(x, y) }");
        match &prog.stmts[0].kind {
            StmtKind::HarvardBlock { program } => match &program.items[0].kind {
                HvItemKind::Stmt(stmt) => match &stmt.kind {
                    HvStmtKind::Print { args } => assert_eq!(args.len(), 2),
                    _ => panic!("expected Print"),
                },
                _ => panic!("expected Stmt"),
            },
            _ => panic!("expected HarvardBlock"),
        }
    }

    #[test]
    fn test_harvard_fn_decl() {
        let prog = parse_ok(
            "harvard{ fn add(x: Int, y: Int): Int @pure { return x + y } }",
        );
        match &prog.stmts[0].kind {
            StmtKind::HarvardBlock { program } => match &program.items[0].kind {
                HvItemKind::FnDecl(decl) => {
                    assert_eq!(decl.name, "add");
                    assert_eq!(decl.params.len(), 2);
                    assert_eq!(decl.purity, Some(HvPurity::Pure));
                    assert!(matches!(
                        decl.return_type,
                        Some(HvType::Basic(ref s)) if s == "Int"
                    ));
                }
                _ => panic!("expected FnDecl"),
            },
            _ => panic!("expected HarvardBlock"),
        }
    }

    #[test]
    fn test_harvard_fn_total() {
        let prog = parse_ok(
            "harvard{ fn abs(x: Int): Int @total { if x < 0 { return -x } else { return x } } }",
        );
        match &prog.stmts[0].kind {
            StmtKind::HarvardBlock { program } => match &program.items[0].kind {
                HvItemKind::FnDecl(decl) => {
                    assert_eq!(decl.purity, Some(HvPurity::Total));
                    assert_eq!(decl.body.len(), 1); // single if stmt
                }
                _ => panic!("expected FnDecl"),
            },
            _ => panic!("expected HarvardBlock"),
        }
    }

    #[test]
    fn test_harvard_module() {
        let prog = parse_ok("harvard{ module math { fn square(x: Int): Int @pure { return x * x } } }");
        match &prog.stmts[0].kind {
            StmtKind::HarvardBlock { program } => match &program.items[0].kind {
                HvItemKind::Module { name, body } => {
                    assert_eq!(name, "math");
                    assert_eq!(body.len(), 1);
                }
                _ => panic!("expected Module"),
            },
            _ => panic!("expected HarvardBlock"),
        }
    }

    #[test]
    fn test_harvard_import() {
        let prog = parse_ok("harvard{ import math.utils as mu }");
        match &prog.stmts[0].kind {
            StmtKind::HarvardBlock { program } => match &program.items[0].kind {
                HvItemKind::Import { path, alias } => {
                    assert_eq!(path, &["math", "utils"]);
                    assert_eq!(alias.as_deref(), Some("mu"));
                }
                _ => panic!("expected Import"),
            },
            _ => panic!("expected HarvardBlock"),
        }
    }

    #[test]
    fn test_harvard_nested_braces() {
        let prog =
            parse_ok("harvard{ if true { if false { return 1 } } }");
        match &prog.stmts[0].kind {
            StmtKind::HarvardBlock { program } => {
                assert_eq!(program.items.len(), 1);
            }
            _ => panic!("expected HarvardBlock"),
        }
    }

    #[test]
    fn test_harvard_reverse_block() {
        let prog = parse_ok("harvard{ reverse { x += 1 y -= 2 } }");
        match &prog.stmts[0].kind {
            StmtKind::HarvardBlock { program } => match &program.items[0].kind {
                HvItemKind::Stmt(stmt) => match &stmt.kind {
                    HvStmtKind::ReverseBlock { body } => {
                        assert_eq!(body.len(), 2);
                        assert!(matches!(
                            body[0].kind,
                            HvReversibleStmtKind::AddAssign { .. }
                        ));
                        assert!(matches!(
                            body[1].kind,
                            HvReversibleStmtKind::SubAssign { .. }
                        ));
                    }
                    _ => panic!("expected ReverseBlock"),
                },
                _ => panic!("expected Stmt"),
            },
            _ => panic!("expected HarvardBlock"),
        }
    }

    #[test]
    fn test_harvard_fn_type() {
        let prog = parse_ok(
            "harvard{ fn apply(f: Fn(Int) -> Int, x: Int): Int @pure { return f(x) } }",
        );
        match &prog.stmts[0].kind {
            StmtKind::HarvardBlock { program } => match &program.items[0].kind {
                HvItemKind::FnDecl(decl) => {
                    assert_eq!(decl.params.len(), 2);
                    match &decl.params[0].type_ann {
                        Some(HvType::Func { params, ret }) => {
                            assert_eq!(params.len(), 1);
                            assert!(matches!(ret.as_ref(), HvType::Basic(s) if s == "Int"));
                        }
                        _ => panic!("expected Func type"),
                    }
                }
                _ => panic!("expected FnDecl"),
            },
            _ => panic!("expected HarvardBlock"),
        }
    }

    #[test]
    fn test_harvard_list_type() {
        let prog = parse_ok(
            "harvard{ fn sum(xs: List<Int>): Int @total { return 0 } }",
        );
        match &prog.stmts[0].kind {
            StmtKind::HarvardBlock { program } => match &program.items[0].kind {
                HvItemKind::FnDecl(decl) => match &decl.params[0].type_ann {
                    Some(HvType::List(inner)) => {
                        assert!(matches!(inner.as_ref(), HvType::Basic(s) if s == "Int"));
                    }
                    _ => panic!("expected List type"),
                },
                _ => panic!("expected FnDecl"),
            },
            _ => panic!("expected HarvardBlock"),
        }
    }

    #[test]
    fn test_harvard_empty_return() {
        let prog = parse_ok("harvard{ return }");
        match &prog.stmts[0].kind {
            StmtKind::HarvardBlock { program } => match &program.items[0].kind {
                HvItemKind::Stmt(stmt) => match &stmt.kind {
                    HvStmtKind::Return { value: None } => {}
                    _ => panic!("expected Return with no value"),
                },
                _ => panic!("expected Stmt"),
            },
            _ => panic!("expected HarvardBlock"),
        }
    }

    #[test]
    fn test_harvard_multiple_stmts() {
        let prog = parse_ok("harvard{ x = 1 y = 2 z = x + y }");
        match &prog.stmts[0].kind {
            StmtKind::HarvardBlock { program } => {
                assert_eq!(program.items.len(), 3);
            }
            _ => panic!("expected HarvardBlock"),
        }
    }

    // ---- Error cases ----

    #[test]
    fn test_add_missing_rbrace() {
        let err = parse_err("def x = add{1 + 2");
        assert!(err.message.contains("expected }"));
    }

    #[test]
    fn test_harvard_missing_rbrace() {
        let err = parse_err("harvard{ x = 1");
        assert!(err.message.contains("expected }"));
    }

    // ---- Mixed programs ----

    #[test]
    fn test_mixed_tangle_and_jtv() {
        let prog = parse_ok(
            "def x = add{1 + 2}
             harvard{ y = 42 }
             assert x == identity",
        );
        assert_eq!(prog.stmts.len(), 3);
        assert!(matches!(prog.stmts[0].kind, StmtKind::Def { .. }));
        assert!(matches!(prog.stmts[1].kind, StmtKind::HarvardBlock { .. }));
        assert!(matches!(prog.stmts[2].kind, StmtKind::Assert { .. }));
    }

    #[test]
    fn test_add_in_assert() {
        let prog = parse_ok("assert add{2 + 3} == add{5}");
        match &prog.stmts[0].kind {
            StmtKind::Assert { expr } => {
                assert!(matches!(expr.kind.as_ref(), ExprKind::Eq(_, _)));
            }
            _ => panic!("expected Assert"),
        }
    }
}
