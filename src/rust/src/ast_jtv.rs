// SPDX-License-Identifier: PMPL-1.0-or-later
// ast_jtv.rs — AST extensions for TANGLE-JTV injection blocks
//
// Two injection syntaxes:
//   add{ hv_data_expr }      — total arithmetic (no loops, no side effects)
//   harvard{ hv_program }    — imperative control with @pure/@total markers

use crate::lexer::Span;

// ---- Harvard Data Expressions (total, guaranteed terminating) ----

/// A Harvard data expression — the language inside `add{...}` blocks.
/// Also used as the expression language for RHS of assignments, conditions,
/// and return values inside `harvard{...}` blocks.
#[derive(Debug, Clone, PartialEq)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub struct HvDataExpr {
    pub kind: Box<HvDataExprKind>,
    pub span: Span,
}

impl HvDataExpr {
    pub fn new(kind: HvDataExprKind, span: Span) -> Self {
        Self {
            kind: Box::new(kind),
            span,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum HvDataExprKind {
    /// Integer literal
    IntLit(i64),
    /// Float literal
    FloatLit(f64),
    /// String literal
    StrLit(String),
    /// `true` or `false`
    BoolLit(bool),
    /// Variable reference
    Var(String),

    /// `if cond then then_branch else else_branch` (total: both branches required)
    Conditional {
        cond: HvDataExpr,
        then_branch: HvDataExpr,
        else_branch: HvDataExpr,
    },

    /// Binary operation: `+`, `-`, `*`, `/`, `%`, `==`, `!=`, `<`, `<=`, `>`, `>=`, `&&`, `||`
    BinOp {
        op: HvBinOp,
        lhs: HvDataExpr,
        rhs: HvDataExpr,
    },

    /// Unary operation: `-expr`, `!expr`
    UnaryOp {
        op: HvUnaryOp,
        operand: HvDataExpr,
    },

    /// Function call: `f(e1, e2, ...)`
    Call {
        func: String,
        args: Vec<HvDataExpr>,
    },

    /// List literal: `[e1, e2, ...]`
    ListLit(Vec<HvDataExpr>),

    /// Tuple literal: `(e1, e2, ...)`  (2+ elements)
    TupleLit(Vec<HvDataExpr>),
}

/// Binary operators in the Harvard data language.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum HvBinOp {
    // Arithmetic
    Add,
    Sub,
    Mul,
    Div,
    Mod,
    // Comparison
    Eq,
    NotEq,
    Lt,
    LtEq,
    Gt,
    GtEq,
    // Logical
    And,
    Or,
}

/// Unary operators in the Harvard data language.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum HvUnaryOp {
    /// Arithmetic negation: `-x`
    Neg,
    /// Logical not: `!x`
    Not,
}

// ---- Harvard Control Statements (imperative, Turing-complete) ----

/// A Harvard program — the content of `harvard{...}` blocks.
#[derive(Debug, Clone, PartialEq)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub struct HvProgram {
    pub items: Vec<HvItem>,
}

/// Top-level items inside a Harvard block.
#[derive(Debug, Clone, PartialEq)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub struct HvItem {
    pub kind: HvItemKind,
    pub span: Span,
}

/// The kinds of items in a Harvard program.
#[derive(Debug, Clone, PartialEq)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum HvItemKind {
    /// `module name { ... }`
    Module {
        name: String,
        body: Vec<HvItem>,
    },
    /// `import path.to.module [as alias]`
    Import {
        path: Vec<String>,
        alias: Option<String>,
    },
    /// Function declaration
    FnDecl(HvFnDecl),
    /// Control statement
    Stmt(HvStmt),
}

/// A Harvard control statement.
#[derive(Debug, Clone, PartialEq)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub struct HvStmt {
    pub kind: HvStmtKind,
    pub span: Span,
}

/// The kinds of control statements.
#[derive(Debug, Clone, PartialEq)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum HvStmtKind {
    /// `x = expr`
    Assignment {
        target: String,
        value: HvDataExpr,
    },
    /// `if cond { stmts } [else { stmts }]`
    If {
        cond: HvDataExpr,
        then_body: Vec<HvStmt>,
        else_body: Option<Vec<HvStmt>>,
    },
    /// `while cond { stmts }`
    While {
        cond: HvDataExpr,
        body: Vec<HvStmt>,
    },
    /// `for x in start..end [..step] { stmts }`
    For {
        var: String,
        start: HvDataExpr,
        end: HvDataExpr,
        step: Option<HvDataExpr>,
        body: Vec<HvStmt>,
    },
    /// `return [expr]`
    Return {
        value: Option<HvDataExpr>,
    },
    /// `print(e1, e2, ...)`
    Print {
        args: Vec<HvDataExpr>,
    },
    /// `reverse { reversible_stmts }`
    ReverseBlock {
        body: Vec<HvReversibleStmt>,
    },
    /// `{ stmts }` — bare block
    Block {
        body: Vec<HvStmt>,
    },
}

/// A reversible statement inside `reverse { ... }`.
#[derive(Debug, Clone, PartialEq)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub struct HvReversibleStmt {
    pub kind: HvReversibleStmtKind,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum HvReversibleStmtKind {
    /// `x += expr`
    AddAssign {
        target: String,
        value: HvDataExpr,
    },
    /// `x -= expr`
    SubAssign {
        target: String,
        value: HvDataExpr,
    },
    /// `if cond { stmts } [else { stmts }]` (reversible)
    If {
        cond: HvDataExpr,
        then_body: Vec<HvReversibleStmt>,
        else_body: Option<Vec<HvReversibleStmt>>,
    },
}

// ---- Function Declarations ----

/// A Harvard function declaration with optional purity marker.
#[derive(Debug, Clone, PartialEq)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub struct HvFnDecl {
    pub name: String,
    pub params: Vec<HvParam>,
    pub return_type: Option<HvType>,
    pub purity: Option<HvPurity>,
    pub body: Vec<HvStmt>,
    pub span: Span,
}

/// A function parameter with optional type annotation.
#[derive(Debug, Clone, PartialEq)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub struct HvParam {
    pub name: String,
    pub type_ann: Option<HvType>,
}

/// Purity markers for Harvard functions.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum HvPurity {
    /// `@pure` — no side effects
    Pure,
    /// `@total` — guaranteed to terminate
    Total,
}

/// Type annotations in the Harvard type system.
#[derive(Debug, Clone, PartialEq)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum HvType {
    /// Basic types: Int, Float, Rational, Complex, Hex, Binary, Symbolic, Bool, String
    Basic(String),
    /// `List<T>`
    List(Box<HvType>),
    /// `(T1, T2, ...)` — tuple type
    Tuple(Vec<HvType>),
    /// `Fn(T1, T2, ...) -> R` — function type
    Func {
        params: Vec<HvType>,
        ret: Box<HvType>,
    },
}
