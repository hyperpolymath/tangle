// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// ast.rs — Abstract syntax tree for TANGLE
//
// Matches the abstract syntax in FORMAL-SEMANTICS.md §1.
// JTV extensions (add{}, harvard{}) are defined separately in ast_jtv.rs.

use crate::ast_jtv::{HvDataExpr, HvProgram};
use crate::lexer::Span;

/// A complete TANGLE program.
#[derive(Debug, Clone, PartialEq)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub struct Program {
    pub stmts: Vec<Stmt>,
}

/// Top-level statement.
#[derive(Debug, Clone, PartialEq)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub struct Stmt {
    pub kind: StmtKind,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum StmtKind {
    /// `def x = e` or `def f(x1, ..., xk) = e`
    Def {
        name: String,
        params: Vec<String>,
        body: Expr,
    },
    /// `weave strands S_in into e yield strands S_out`
    Weave {
        input_strands: Vec<TypedStrand>,
        body: Expr,
        output_strands: Vec<TypedStrand>,
    },
    /// `compute jones(e)`
    Compute {
        invariant: String,
        expr: Expr,
    },
    /// `assert e`
    Assert {
        expr: Expr,
    },
    /// `harvard{ hv_program }` — embedded imperative block
    HarvardBlock {
        program: HvProgram,
    },
}

/// A strand declaration with optional type annotation.
#[derive(Debug, Clone, PartialEq)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub struct TypedStrand {
    pub name: String,
    pub type_ann: Option<String>,
    pub span: Span,
}

/// Expression node.
#[derive(Debug, Clone, PartialEq)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub struct Expr {
    pub kind: Box<ExprKind>,
    pub span: Span,
}

impl Expr {
    pub fn new(kind: ExprKind, span: Span) -> Self {
        Self {
            kind: Box::new(kind),
            span,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum ExprKind {
    /// Variable reference
    Var(String),
    /// Integer literal
    IntLit(i64),
    /// Float literal
    FloatLit(f64),
    /// String literal
    StrLit(String),
    /// `true` or `false`
    BoolLit(bool),
    /// `identity` — the empty braid word
    Identity,
    /// `braid[g1, ..., gk]`
    BraidLit(Vec<Generator>),

    // --- Binary operations (by precedence, lowest first) ---
    /// `e1 >> e2` — pipeline
    Pipeline(Expr, Expr),
    /// `e1 == e2` — structural equality
    Eq(Expr, Expr),
    /// `e1 ~ e2` — isotopy equivalence
    Isotopy(Expr, Expr),
    /// `e1 + e2` — addition / disjoint union
    Add(Expr, Expr),
    /// `e1 - e2` — subtraction
    Sub(Expr, Expr),
    /// `e1 * e2` — multiplication
    Mul(Expr, Expr),
    /// `e1 / e2` — division
    Div(Expr, Expr),
    /// `e1 . e2` — vertical composition (cons)
    Compose(Expr, Expr),
    /// `e1 | e2` — horizontal tensor
    Tensor(Expr, Expr),

    // --- Unary operations ---
    /// `(~e)` — twist (standalone or weave)
    Twist(Expr),
    /// `close(e)` — closure
    Close(Expr),
    /// `mirror(e)` — mirror image
    Mirror(Expr),
    /// `reverse(e)` — reverse word
    Reverse(Expr),
    /// `simplify(e)` — Reidemeister simplification
    Simplify(Expr),
    /// `cap(e1, e2)` — cap primitive
    Cap(Expr, Expr),
    /// `cup(e1, e2)` — cup primitive
    Cup(Expr, Expr),

    // --- Crossings (weave context) ---
    /// `(a > b)` — over-crossing
    CrossOver { a: String, b: String },
    /// `(a < b)` — under-crossing
    CrossUnder { a: String, b: String },

    // --- Control ---
    /// `f(e1, ..., ek)` — function application
    App { func: String, args: Vec<Expr> },
    /// `match e with | p1 => e1 | ... end`
    Match {
        scrutinee: Expr,
        arms: Vec<MatchArm>,
    },
    /// `let x = e1 in e2`
    Let {
        name: String,
        value: Expr,
        body: Expr,
    },

    // --- Weave as expression ---
    /// `weave strands S_in into e yield strands S_out`
    /// When used as an expression (e.g., in a def body), evaluates to a Tangle.
    WeaveExpr {
        input_strands: Vec<TypedStrand>,
        body: Expr,
        output_strands: Vec<TypedStrand>,
    },

    // --- JTV injection ---
    /// `add{ hv_data_expr }` — embedded total arithmetic
    AddBlock {
        expr: HvDataExpr,
    },
}

/// A match arm: `| pattern => expr`
#[derive(Debug, Clone, PartialEq)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub struct MatchArm {
    pub pattern: Pattern,
    pub body: Expr,
    pub span: Span,
}

/// Pattern for structural matching on braid words.
#[derive(Debug, Clone, PartialEq)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub struct Pattern {
    pub kind: PatternKind,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum PatternKind {
    /// `identity` — matches empty word
    Identity,
    /// `g . p` — matches generator g followed by pattern p
    Cons { generator: Generator, rest: Box<Pattern> },
    /// `x` — variable pattern (binds x to matched value)
    Var(String),
    /// `_` — wildcard (matches anything, binds nothing)
    Wildcard,
}

/// A braid generator: σᵢ or σᵢ⁻¹
#[derive(Debug, Clone, PartialEq)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub struct Generator {
    pub index: u32,
    pub inverse: bool,
}
