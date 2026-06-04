// SPDX-License-Identifier: MPL-2.0
// Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// eval.rs — Tree-walking interpreter for TANGLE
//
// Implements the operational semantics from FORMAL-SEMANTICS.md:
//   - Call-by-value evaluation (D1.13.5)
//   - Pattern matching on Word structure (D1.3, D1.4)
//   - Lexical scoping with shadowing (D1.3.5, D1.4.5, D1.15.3)
//   - Two-pass definition collection (D1.13)
//   - Halt/panic error model (D1.15)
//   - Reidemeister simplification (D1.16)
//   - Auto-widening on composition (D1.8.5)
//   - Isotopy checking via word normalization (D1.2)
//   - Close, mirror, reverse, twist operations (D1.16-D1.18)

use std::collections::HashMap;
use std::fmt;

use crate::ast::*;

// ============================================================================
// VALUES
// ============================================================================

/// Runtime values in the TANGLE interpreter.
///
/// Per D1.1 and D1.5, the value types are:
///   - Word (braid word = list of generators)
///   - Num (integers and floats, unified)
///   - Str (strings)
///   - Bool (booleans)
///   - Closure (for function definitions)
///   - Tangle (closed tangle = link, represented as a closed braid word)
#[derive(Debug, Clone)]
pub enum Value {
    /// A braid word: a sequence of generators (D1.1).
    /// The empty word (`identity`) is represented as an empty Vec.
    Word(Vec<Generator>),

    /// A numeric value (integers and floats unified as f64 per D1.5).
    Num(f64),

    /// A string value.
    Str(String),

    /// A boolean value.
    Bool(bool),

    /// A closed tangle (result of `close`). Stores the braid word that was
    /// closed (D1.17). Two closed tangles can be combined with `+` (disjoint
    /// union, D1.7).
    ClosedTangle(Vec<Generator>),

    /// A function closure — captures the definition environment (D1.13).
    Closure {
        name: String,
        params: Vec<String>,
        body: Expr,
    },
}

impl fmt::Display for Value {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Value::Word(gens) => {
                if gens.is_empty() {
                    write!(f, "identity")
                } else {
                    write!(f, "braid[")?;
                    for (i, g) in gens.iter().enumerate() {
                        if i > 0 {
                            write!(f, ", ")?;
                        }
                        write!(f, "s{}", g.index)?;
                        if g.inverse {
                            write!(f, "^-1")?;
                        }
                    }
                    write!(f, "]")
                }
            }
            Value::Num(n) => {
                if *n == (*n as i64) as f64 && n.is_finite() {
                    write!(f, "{}", *n as i64)
                } else {
                    write!(f, "{}", n)
                }
            }
            Value::Str(s) => write!(f, "\"{}\"", s),
            Value::Bool(b) => write!(f, "{}", b),
            Value::ClosedTangle(gens) => {
                write!(f, "close(braid[")?;
                for (i, g) in gens.iter().enumerate() {
                    if i > 0 {
                        write!(f, ", ")?;
                    }
                    write!(f, "s{}", g.index)?;
                    if g.inverse {
                        write!(f, "^-1")?;
                    }
                }
                write!(f, "])")
            }
            Value::Closure { name, params, .. } => {
                write!(f, "<fn {}({})>", name, params.join(", "))
            }
        }
    }
}

impl PartialEq for Value {
    fn eq(&self, other: &Self) -> bool {
        match (self, other) {
            (Value::Word(a), Value::Word(b)) => a == b,
            (Value::Num(a), Value::Num(b)) => a == b,
            (Value::Str(a), Value::Str(b)) => a == b,
            (Value::Bool(a), Value::Bool(b)) => a == b,
            (Value::ClosedTangle(a), Value::ClosedTangle(b)) => a == b,
            _ => false,
        }
    }
}

// ============================================================================
// RUNTIME ERRORS
// ============================================================================

/// Runtime error — corresponds to D1.15 (halt/panic for MVP).
#[derive(Debug, Clone)]
pub struct RuntimeError {
    pub message: String,
    pub span: crate::lexer::Span,
}

impl fmt::Display for RuntimeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Runtime error at {}: {}", self.span, self.message)
    }
}

impl std::error::Error for RuntimeError {}

type EvalResult = Result<Value, RuntimeError>;

// ============================================================================
// ENVIRONMENT
// ============================================================================

/// Lexically scoped environment (D1.3.5, D1.4.5, D1.15.3).
///
/// Uses a chain of HashMaps for efficient lookup with proper scoping.
/// Innermost binding wins (pattern var > strand name > let > global def).
#[derive(Debug, Clone)]
pub struct Env {
    frames: Vec<HashMap<String, Value>>,
}

impl Env {
    /// Create a new empty environment.
    pub fn new() -> Self {
        Self {
            frames: vec![HashMap::new()],
        }
    }

    /// Look up a variable in the environment (innermost scope first).
    pub fn get(&self, name: &str) -> Option<&Value> {
        for frame in self.frames.iter().rev() {
            if let Some(val) = frame.get(name) {
                return Some(val);
            }
        }
        None
    }

    /// Define a variable in the current (innermost) scope.
    pub fn define(&mut self, name: String, val: Value) {
        if let Some(frame) = self.frames.last_mut() {
            frame.insert(name, val);
        }
    }

    /// Push a new scope frame.
    pub fn push_scope(&mut self) {
        self.frames.push(HashMap::new());
    }

    /// Pop the innermost scope frame.
    pub fn pop_scope(&mut self) {
        if self.frames.len() > 1 {
            self.frames.pop();
        }
    }
}

impl Default for Env {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// INTERPRETER
// ============================================================================

/// The TANGLE tree-walking interpreter.
///
/// Implements the two-pass evaluation strategy from D1.13:
///   Pass 1: Collect all `def` names into the environment
///   Pass 2: Execute `compute` and `assert` statements in source order
pub struct Interpreter {
    /// Global environment (Gamma in the formal semantics).
    pub env: Env,
    /// Output produced by `compute` statements.
    pub output: Vec<String>,
    /// Warnings emitted during evaluation.
    pub warnings: Vec<String>,
}

impl Interpreter {
    /// Create a new interpreter with an empty environment.
    pub fn new() -> Self {
        Self {
            env: Env::new(),
            output: Vec::new(),
            warnings: Vec::new(),
        }
    }

    /// Execute a complete program (D1.13 two-pass strategy).
    ///
    /// Pass 1: Collect all definitions into the environment.
    /// Pass 2: Execute compute and assert statements in order.
    pub fn exec_program(&mut self, program: &Program) -> Result<(), RuntimeError> {
        // Pass 1: Collect all definitions (forward references allowed)
        for stmt in &program.stmts {
            if let StmtKind::Def { name, params, body } = &stmt.kind {
                if params.is_empty() {
                    // Value definition — evaluate eagerly
                    // Note: This allows forward references because we collect
                    // all names first, but for simplicity in the MVP interpreter
                    // we evaluate definitions lazily via closures
                    let val = Value::Closure {
                        name: name.clone(),
                        params: Vec::new(),
                        body: body.clone(),
                    };
                    self.env.define(name.clone(), val);
                } else {
                    // Function definition — store as closure
                    let val = Value::Closure {
                        name: name.clone(),
                        params: params.clone(),
                        body: body.clone(),
                    };
                    self.env.define(name.clone(), val);
                }
            }
        }

        // Pass 2: Execute statements in order
        for stmt in &program.stmts {
            self.exec_stmt(stmt)?;
        }

        Ok(())
    }

    /// Execute a single statement.
    fn exec_stmt(&mut self, stmt: &Stmt) -> Result<(), RuntimeError> {
        match &stmt.kind {
            StmtKind::Def { .. } => {
                // Already handled in pass 1
                Ok(())
            }
            StmtKind::Weave {
                input_strands,
                body,
                output_strands,
            } => {
                // Weave blocks at statement level are executed for their side
                // effects (crossing verification). We evaluate the body in an
                // environment with strand names bound.
                self.eval_weave(input_strands, body, output_strands, stmt.span)?;
                Ok(())
            }
            StmtKind::Compute { invariant, expr } => {
                let val = self.eval_expr(expr)?;
                let result = self.compute_invariant(invariant, &val, stmt.span)?;
                let output_line = format!("compute {}({}) = {}", invariant, val, result);
                self.output.push(output_line);
                Ok(())
            }
            StmtKind::Assert { expr } => {
                let val = self.eval_expr(expr)?;
                match val {
                    Value::Bool(true) => Ok(()),
                    Value::Bool(false) => Err(RuntimeError {
                        message: format!("Assertion failed at line {}", stmt.span.line),
                        span: stmt.span,
                    }),
                    other => Err(RuntimeError {
                        message: format!(
                            "Assertion expression must be Bool, got {}",
                            type_name(&other)
                        ),
                        span: stmt.span,
                    }),
                }
            }
            StmtKind::HarvardBlock { .. } => {
                // Harvard blocks: not yet implemented in the interpreter.
                // They define functions in Delta/Pi environments (D2.1-D2.3).
                self.warnings.push(
                    "harvard{} blocks not yet interpreted (JTV extension)".to_string(),
                );
                Ok(())
            }
        }
    }

    /// Evaluate an expression to a value.
    pub fn eval_expr(&mut self, expr: &Expr) -> EvalResult {
        match expr.kind.as_ref() {
            // --- Literals ---
            ExprKind::IntLit(n) => Ok(Value::Num(*n as f64)),
            ExprKind::FloatLit(n) => Ok(Value::Num(*n)),
            ExprKind::StrLit(s) => Ok(Value::Str(s.clone())),
            ExprKind::BoolLit(b) => Ok(Value::Bool(*b)),
            ExprKind::Identity => Ok(Value::Word(Vec::new())),
            ExprKind::BraidLit(gens) => Ok(Value::Word(gens.clone())),

            // --- Variable reference ---
            ExprKind::Var(name) => self.eval_var(name, expr.span),

            // --- Binary operations ---
            ExprKind::Pipeline(lhs, rhs) => {
                // Pipeline is sugar for vertical composition (D1.20)
                let l = self.eval_expr(lhs)?;
                let r = self.eval_expr(rhs)?;
                self.compose_values(l, r, expr.span)
            }
            ExprKind::Eq(lhs, rhs) => {
                // Structural equality (D1.2)
                let l = self.eval_expr(lhs)?;
                let r = self.eval_expr(rhs)?;
                Ok(Value::Bool(l == r))
            }
            ExprKind::Isotopy(lhs, rhs) => {
                // Isotopy equivalence (D1.2) — uses Reidemeister normalization
                let l = self.eval_expr(lhs)?;
                let r = self.eval_expr(rhs)?;
                self.check_isotopy(l, r, expr.span)
            }
            ExprKind::Add(lhs, rhs) => {
                let l = self.eval_expr(lhs)?;
                let r = self.eval_expr(rhs)?;
                self.eval_add(l, r, expr.span)
            }
            ExprKind::Sub(lhs, rhs) => {
                let l = self.eval_expr(lhs)?;
                let r = self.eval_expr(rhs)?;
                self.eval_arith(l, r, "-", |a, b| a - b, expr.span)
            }
            ExprKind::Mul(lhs, rhs) => {
                let l = self.eval_expr(lhs)?;
                let r = self.eval_expr(rhs)?;
                self.eval_arith(l, r, "*", |a, b| a * b, expr.span)
            }
            ExprKind::Div(lhs, rhs) => {
                let l = self.eval_expr(lhs)?;
                let r = self.eval_expr(rhs)?;
                match (&l, &r) {
                    (Value::Num(_), Value::Num(b)) if *b == 0.0 => Err(RuntimeError {
                        message: "Division by zero".to_string(),
                        span: expr.span,
                    }),
                    _ => self.eval_arith(l, r, "/", |a, b| a / b, expr.span),
                }
            }
            ExprKind::Compose(lhs, rhs) => {
                // Vertical composition / word cons (D1.8, D1.8.5)
                let l = self.eval_expr(lhs)?;
                let r = self.eval_expr(rhs)?;
                self.compose_values(l, r, expr.span)
            }
            ExprKind::Tensor(lhs, rhs) => {
                // Horizontal tensor (D1.8)
                let l = self.eval_expr(lhs)?;
                let r = self.eval_expr(rhs)?;
                self.tensor_values(l, r, expr.span)
            }

            // --- Unary operations ---
            ExprKind::Twist(inner) => {
                let val = self.eval_expr(inner)?;
                self.eval_twist(val, expr.span)
            }
            ExprKind::Close(inner) => {
                let val = self.eval_expr(inner)?;
                self.eval_close(val, expr.span)
            }
            ExprKind::Mirror(inner) => {
                let val = self.eval_expr(inner)?;
                self.eval_mirror(val, expr.span)
            }
            ExprKind::Reverse(inner) => {
                let val = self.eval_expr(inner)?;
                self.eval_reverse(val, expr.span)
            }
            ExprKind::Simplify(inner) => {
                let val = self.eval_expr(inner)?;
                self.eval_simplify(val, expr.span)
            }
            ExprKind::Cap(a, b) => {
                let _va = self.eval_expr(a)?;
                let _vb = self.eval_expr(b)?;
                // Cap creates a connection between two strands.
                // For MVP, cap/cup are structural markers.
                self.warnings
                    .push("cap() evaluated as identity (MVP)".to_string());
                Ok(Value::Word(Vec::new()))
            }
            ExprKind::Cup(a, b) => {
                let _va = self.eval_expr(a)?;
                let _vb = self.eval_expr(b)?;
                self.warnings
                    .push("cup() evaluated as identity (MVP)".to_string());
                Ok(Value::Word(Vec::new()))
            }

            // --- Crossings ---
            ExprKind::CrossOver { a, b } => {
                // In weave context, (a > b) produces a crossing.
                // We represent this as a generator based on strand positions.
                // For standalone evaluation, treat as a braid generator
                // between the two named strands.
                self.eval_crossing(a, b, false, expr.span)
            }
            ExprKind::CrossUnder { a, b } => {
                self.eval_crossing(a, b, true, expr.span)
            }

            // --- Control flow ---
            ExprKind::App { func, args } => self.eval_app(func, args, expr.span),
            ExprKind::Match { scrutinee, arms } => {
                self.eval_match(scrutinee, arms, expr.span)
            }
            ExprKind::Let { name, value, body } => {
                self.eval_let(name, value, body, expr.span)
            }

            // --- Weave as expression ---
            ExprKind::WeaveExpr {
                input_strands,
                body,
                output_strands,
            } => self.eval_weave(input_strands, body, output_strands, expr.span),

            // --- JTV injection ---
            ExprKind::AddBlock { expr: hv_expr } => {
                self.eval_add_block(hv_expr, expr.span)
            }
        }
    }

    // ---- Variable resolution ----

    /// Resolve a variable name, forcing thunks for zero-arity definitions.
    fn eval_var(&mut self, name: &str, span: crate::lexer::Span) -> EvalResult {
        match self.env.get(name) {
            Some(val) => {
                let val = val.clone();
                match &val {
                    // Zero-argument closure = thunk; force it
                    Value::Closure {
                        params, body, name: fn_name, ..
                    } if params.is_empty() => {
                        let body = body.clone();
                        let fn_name = fn_name.clone();
                        let result = self.eval_expr(&body)?;
                        // Cache the result (memoize the thunk)
                        self.env.define(fn_name, result.clone());
                        Ok(result)
                    }
                    // Multi-argument closure = return the closure itself
                    Value::Closure { .. } => Ok(val),
                    // All other values: return directly
                    _ => Ok(val),
                }
            }
            None => Err(RuntimeError {
                message: format!("Undefined variable '{}'", name),
                span,
            }),
        }
    }

    // ---- Arithmetic ----

    /// Evaluate addition with overloading (D1.6):
    /// Num + Num = Num (arithmetic)
    /// ClosedTangle + ClosedTangle = ClosedTangle (disjoint union, D1.7)
    fn eval_add(
        &self,
        lhs: Value,
        rhs: Value,
        span: crate::lexer::Span,
    ) -> EvalResult {
        match (&lhs, &rhs) {
            (Value::Num(a), Value::Num(b)) => Ok(Value::Num(a + b)),
            (Value::ClosedTangle(a), Value::ClosedTangle(b)) => {
                // Disjoint union: concatenate generator sequences
                // with index offset for the second component.
                let width_a = word_width(a);
                let shifted_b: Vec<Generator> = b
                    .iter()
                    .map(|g| Generator {
                        index: g.index + width_a,
                        inverse: g.inverse,
                    })
                    .collect();
                let mut result = a.clone();
                result.extend(shifted_b);
                Ok(Value::ClosedTangle(result))
            }
            _ => Err(RuntimeError {
                message: format!(
                    "Type error: cannot add {} and {}",
                    type_name(&lhs),
                    type_name(&rhs)
                ),
                span,
            }),
        }
    }

    /// Generic arithmetic operation on Num values.
    fn eval_arith(
        &self,
        lhs: Value,
        rhs: Value,
        op_name: &str,
        op: impl Fn(f64, f64) -> f64,
        span: crate::lexer::Span,
    ) -> EvalResult {
        match (&lhs, &rhs) {
            (Value::Num(a), Value::Num(b)) => Ok(Value::Num(op(*a, *b))),
            _ => Err(RuntimeError {
                message: format!(
                    "Type error: cannot {} {} and {}",
                    op_name,
                    type_name(&lhs),
                    type_name(&rhs)
                ),
                span,
            }),
        }
    }

    // ---- Composition ----

    /// Vertical composition of two words (D1.8, D1.8.5).
    /// Word . Word = Word (concatenation with auto-widening)
    fn compose_values(
        &self,
        lhs: Value,
        rhs: Value,
        span: crate::lexer::Span,
    ) -> EvalResult {
        match (lhs, rhs) {
            (Value::Word(mut a), Value::Word(b)) => {
                // Auto-widening is implicit: we just concatenate generators.
                // The width is max(width(a), width(b)) per D1.8.5.
                a.extend(b);
                Ok(Value::Word(a))
            }
            (l, r) => Err(RuntimeError {
                message: format!(
                    "Type error: cannot compose {} and {}",
                    type_name(&l),
                    type_name(&r)
                ),
                span,
            }),
        }
    }

    /// Horizontal tensor of two words (D1.8).
    /// Word[n] | Word[m] = Word[n+m] (side by side with index offset)
    fn tensor_values(
        &self,
        lhs: Value,
        rhs: Value,
        span: crate::lexer::Span,
    ) -> EvalResult {
        match (lhs, rhs) {
            (Value::Word(a), Value::Word(b)) => {
                let width_a = word_width(&a);
                // Shift all generators in b by width of a
                let shifted_b: Vec<Generator> = b
                    .iter()
                    .map(|g| Generator {
                        index: g.index + width_a,
                        inverse: g.inverse,
                    })
                    .collect();
                let mut result = a;
                result.extend(shifted_b);
                Ok(Value::Word(result))
            }
            (l, r) => Err(RuntimeError {
                message: format!(
                    "Type error: cannot tensor {} and {}",
                    type_name(&l),
                    type_name(&r)
                ),
                span,
            }),
        }
    }

    // ---- Unary operations ----

    /// Twist operation (D1.18).
    /// Standalone: all-strand twist (compose with twist_n).
    fn eval_twist(
        &self,
        val: Value,
        span: crate::lexer::Span,
    ) -> EvalResult {
        match val {
            Value::Word(gens) => {
                // All-strand twist: add a full twist on all n strands.
                // A full twist on n strands is the product of all sigma_i
                // for i from 1 to n-1, squared. For MVP, we represent it
                // as the Garside element squared.
                let n = word_width(&gens);
                let mut result = gens;
                // Full positive twist: (s1 s2 ... s_{n-1})^2
                // This is a simplification — the full twist is actually
                // Delta^2 where Delta = s1(s2 s1)(s3 s2 s1)...
                // For MVP, use the Garside element:
                for _ in 0..2 {
                    for i in 1..n {
                        result.push(Generator {
                            index: i,
                            inverse: false,
                        });
                    }
                }
                Ok(Value::Word(result))
            }
            other => Err(RuntimeError {
                message: format!(
                    "Type error: cannot twist {}",
                    type_name(&other)
                ),
                span,
            }),
        }
    }

    /// Close operation (D1.17).
    /// close : Word[n] -> ClosedTangle
    /// Connects output strand i to input strand i.
    fn eval_close(
        &self,
        val: Value,
        span: crate::lexer::Span,
    ) -> EvalResult {
        match val {
            Value::Word(gens) => Ok(Value::ClosedTangle(gens)),
            Value::ClosedTangle(_) => Err(RuntimeError {
                message: "Cannot close an already closed tangle".to_string(),
                span,
            }),
            other => Err(RuntimeError {
                message: format!(
                    "Type error: cannot close {}",
                    type_name(&other)
                ),
                span,
            }),
        }
    }

    /// Mirror operation (D1.16).
    /// mirror(braid[s1, s2]) = braid[s1^-1, s2^-1]
    /// Flips all generator inversions.
    fn eval_mirror(
        &self,
        val: Value,
        span: crate::lexer::Span,
    ) -> EvalResult {
        match val {
            Value::Word(gens) => {
                let mirrored: Vec<Generator> = gens
                    .iter()
                    .map(|g| Generator {
                        index: g.index,
                        inverse: !g.inverse,
                    })
                    .collect();
                Ok(Value::Word(mirrored))
            }
            other => Err(RuntimeError {
                message: format!(
                    "Type error: cannot mirror {}",
                    type_name(&other)
                ),
                span,
            }),
        }
    }

    /// Reverse operation (D1.16).
    /// reverse(braid[s1, s2, s3]) = braid[s3, s2, s1]
    /// Reverses the sequence of generators.
    fn eval_reverse(
        &self,
        val: Value,
        span: crate::lexer::Span,
    ) -> EvalResult {
        match val {
            Value::Word(mut gens) => {
                gens.reverse();
                Ok(Value::Word(gens))
            }
            other => Err(RuntimeError {
                message: format!(
                    "Type error: cannot reverse {}",
                    type_name(&other)
                ),
                span,
            }),
        }
    }

    /// Simplify operation (D1.16).
    /// Applies Reidemeister moves to reduce the braid word:
    ///   - R2: Cancel adjacent inverse pairs (si . si^-1 = identity)
    ///   - R3: Braid relations (si . sj = sj . si when |i-j| >= 2)
    ///
    /// This is the core of the topological computation engine.
    fn eval_simplify(
        &self,
        val: Value,
        span: crate::lexer::Span,
    ) -> EvalResult {
        match val {
            Value::Word(gens) => {
                let simplified = simplify_word(&gens);
                Ok(Value::Word(simplified))
            }
            other => Err(RuntimeError {
                message: format!(
                    "Type error: cannot simplify {}",
                    type_name(&other)
                ),
                span,
            }),
        }
    }

    // ---- Crossings ----

    /// Evaluate a crossing expression (a > b) or (a < b).
    /// In the interpreter, crossings produce a single generator based
    /// on strand positions in the current weave context.
    fn eval_crossing(
        &self,
        a: &str,
        b: &str,
        inverse: bool,
        _span: crate::lexer::Span,
    ) -> EvalResult {
        // Look up strand positions. In a weave context, strands are
        // bound to their position indices. Outside weave, treat as
        // an abstract crossing generator.
        let _a_val = self.env.get(a);
        let _b_val = self.env.get(b);

        // For MVP: produce a generator at index 1 (two-strand crossing)
        // A more complete implementation would track strand positions
        // through the weave body.
        Ok(Value::Word(vec![Generator {
            index: 1,
            inverse,
        }]))
    }

    // ---- Isotopy checking ----

    /// Check isotopy equivalence (D1.2).
    /// Two braid words are isotopic if they simplify to the same normal form
    /// (modulo Reidemeister moves and braid relations).
    fn check_isotopy(
        &self,
        lhs: Value,
        rhs: Value,
        span: crate::lexer::Span,
    ) -> EvalResult {
        match (&lhs, &rhs) {
            (Value::Word(a), Value::Word(b)) => {
                let norm_a = simplify_word(a);
                let norm_b = simplify_word(b);
                Ok(Value::Bool(norm_a == norm_b))
            }
            (Value::ClosedTangle(a), Value::ClosedTangle(b)) => {
                let norm_a = simplify_word(a);
                let norm_b = simplify_word(b);
                Ok(Value::Bool(norm_a == norm_b))
            }
            _ => Err(RuntimeError {
                message: format!(
                    "Type error: isotopy (~) requires two Words or two ClosedTangles, got {} and {}",
                    type_name(&lhs),
                    type_name(&rhs)
                ),
                span,
            }),
        }
    }

    // ---- Weave blocks ----

    /// Evaluate a weave block (D1.9-D1.11, D2.8).
    /// Sets up strand bindings, evaluates the body, and verifies the yield.
    fn eval_weave(
        &mut self,
        input_strands: &[TypedStrand],
        body: &Expr,
        _output_strands: &[TypedStrand],
        span: crate::lexer::Span,
    ) -> EvalResult {
        self.env.push_scope();

        // Bind strand names to position indices
        for (i, strand) in input_strands.iter().enumerate() {
            self.env
                .define(strand.name.clone(), Value::Num(i as f64));
        }

        let result = self.eval_expr(body);

        self.env.pop_scope();

        result.map_err(|mut e| {
            e.message = format!("In weave block: {}", e.message);
            e.span = span;
            e
        })
    }

    // ---- Function application ----

    /// Evaluate a function application (D1.3, D1.13.5 call-by-value).
    fn eval_app(
        &mut self,
        func_name: &str,
        arg_exprs: &[Expr],
        span: crate::lexer::Span,
    ) -> EvalResult {
        // Evaluate arguments first (call-by-value, D1.13.5)
        let mut arg_vals = Vec::with_capacity(arg_exprs.len());
        for arg in arg_exprs {
            arg_vals.push(self.eval_expr(arg)?);
        }

        // Look up the function
        let func = match self.env.get(func_name) {
            Some(val) => val.clone(),
            None => {
                return Err(RuntimeError {
                    message: format!("Undefined function '{}'", func_name),
                    span,
                })
            }
        };

        match func {
            Value::Closure {
                params, body, ..
            } => {
                if params.len() != arg_vals.len() {
                    return Err(RuntimeError {
                        message: format!(
                            "Function '{}' expects {} arguments, got {}",
                            func_name,
                            params.len(),
                            arg_vals.len()
                        ),
                        span,
                    });
                }

                // Push scope, bind parameters
                self.env.push_scope();
                for (param, val) in params.iter().zip(arg_vals) {
                    self.env.define(param.clone(), val);
                }

                let result = self.eval_expr(&body);

                self.env.pop_scope();
                result
            }
            _ => Err(RuntimeError {
                message: format!("'{}' is not a function", func_name),
                span,
            }),
        }
    }

    // ---- Pattern matching ----

    /// Evaluate a match expression (D1.3, D1.4).
    /// Arms are tried in order; first matching arm wins.
    /// If no arm matches, halt with MatchFailure (D1.15).
    fn eval_match(
        &mut self,
        scrutinee: &Expr,
        arms: &[MatchArm],
        span: crate::lexer::Span,
    ) -> EvalResult {
        let val = self.eval_expr(scrutinee)?;

        for arm in arms {
            let mut bindings = HashMap::new();
            if match_pattern(&arm.pattern, &val, &mut bindings) {
                // Pattern matched — evaluate body with bindings
                self.env.push_scope();
                for (name, bound_val) in bindings {
                    self.env.define(name, bound_val);
                }
                let result = self.eval_expr(&arm.body);
                self.env.pop_scope();
                return result;
            }
        }

        // No pattern matched (D1.4, D1.15)
        Err(RuntimeError {
            message: format!(
                "MatchFailure: no pattern matched value {}",
                val
            ),
            span,
        })
    }

    // ---- Let binding ----

    /// Evaluate a let binding (D1.4.5).
    /// let x = e1 in e2: evaluate e1, bind x, evaluate e2.
    fn eval_let(
        &mut self,
        name: &str,
        value: &Expr,
        body: &Expr,
        _span: crate::lexer::Span,
    ) -> EvalResult {
        let val = self.eval_expr(value)?;
        self.env.push_scope();
        self.env.define(name.to_string(), val);
        let result = self.eval_expr(body);
        self.env.pop_scope();
        result
    }

    // ---- Invariant computation ----

    /// Compute a topological invariant (D1.12, D1.16).
    /// MVP: writhe is implemented; others report placeholder values.
    fn compute_invariant(
        &self,
        name: &str,
        val: &Value,
        span: crate::lexer::Span,
    ) -> EvalResult {
        let gens = match val {
            Value::Word(g) => g,
            Value::ClosedTangle(g) => g,
            other => {
                return Err(RuntimeError {
                    message: format!(
                        "Invariant '{}' requires a Word or ClosedTangle, got {}",
                        name,
                        type_name(other)
                    ),
                    span,
                })
            }
        };

        match name {
            "writhe" => {
                // Writhe = sum of crossing signs (+1 for positive, -1 for inverse)
                let w: i64 = gens
                    .iter()
                    .map(|g| if g.inverse { -1i64 } else { 1i64 })
                    .sum();
                Ok(Value::Num(w as f64))
            }
            "jones" | "alexander" | "homfly" | "kauffman" => {
                // Full polynomial invariants require significant algebraic
                // computation. For MVP, compute writhe as a proxy and note
                // the limitation.
                let w: i64 = gens
                    .iter()
                    .map(|g| if g.inverse { -1i64 } else { 1i64 })
                    .sum();
                self.warnings.iter().count(); // suppress unused warning
                Ok(Value::Str(format!(
                    "{} (MVP: writhe={}, full polynomial not yet implemented)",
                    name, w
                )))
            }
            "linking" => {
                // Linking number between components in a link
                // MVP: return 0 as placeholder
                Ok(Value::Num(0.0))
            }
            other => Err(RuntimeError {
                message: format!("Unknown invariant '{}'", other),
                span,
            }),
        }
    }

    // ---- JTV add{} block ----

    /// Evaluate an add{} block (D2.1, D2.4).
    /// Evaluates the Harvard data expression and embeds the result.
    fn eval_add_block(
        &mut self,
        hv_expr: &crate::ast_jtv::HvDataExpr,
        span: crate::lexer::Span,
    ) -> EvalResult {
        self.eval_hv_data_expr(hv_expr, span)
    }

    /// Evaluate a Harvard data expression (total, guaranteed terminating).
    fn eval_hv_data_expr(
        &mut self,
        expr: &crate::ast_jtv::HvDataExpr,
        span: crate::lexer::Span,
    ) -> EvalResult {
        use crate::ast_jtv::HvDataExprKind;

        match expr.kind.as_ref() {
            HvDataExprKind::IntLit(n) => Ok(Value::Num(*n as f64)),
            HvDataExprKind::FloatLit(n) => Ok(Value::Num(*n)),
            HvDataExprKind::StrLit(s) => Ok(Value::Str(s.clone())),
            HvDataExprKind::BoolLit(b) => Ok(Value::Bool(*b)),
            HvDataExprKind::Var(name) => self.eval_var(name, span),
            HvDataExprKind::Conditional {
                cond,
                then_branch,
                else_branch,
            } => {
                let c = self.eval_hv_data_expr(cond, span)?;
                match c {
                    Value::Bool(true) => self.eval_hv_data_expr(then_branch, span),
                    Value::Bool(false) => self.eval_hv_data_expr(else_branch, span),
                    other => Err(RuntimeError {
                        message: format!(
                            "Conditional requires Bool, got {}",
                            type_name(&other)
                        ),
                        span,
                    }),
                }
            }
            HvDataExprKind::BinOp { op, lhs, rhs } => {
                let l = self.eval_hv_data_expr(lhs, span)?;
                let r = self.eval_hv_data_expr(rhs, span)?;
                self.eval_hv_binop(op, l, r, span)
            }
            HvDataExprKind::UnaryOp { op, operand } => {
                let v = self.eval_hv_data_expr(operand, span)?;
                self.eval_hv_unary(op, v, span)
            }
            HvDataExprKind::Call { func, args } => {
                let mut arg_vals = Vec::new();
                for a in args {
                    arg_vals.push(self.eval_hv_data_expr(a, span)?);
                }
                // Resolve in Pi (pure functions only)
                // For MVP: resolve in global env
                let func_val = match self.env.get(func) {
                    Some(v) => v.clone(),
                    None => {
                        return Err(RuntimeError {
                            message: format!(
                                "Undefined function '{}' in add{{}} block",
                                func
                            ),
                            span,
                        })
                    }
                };
                match func_val {
                    Value::Closure { params, body, .. } => {
                        if params.len() != arg_vals.len() {
                            return Err(RuntimeError {
                                message: format!(
                                    "Function '{}' expects {} args, got {}",
                                    func,
                                    params.len(),
                                    arg_vals.len()
                                ),
                                span,
                            });
                        }
                        self.env.push_scope();
                        for (p, v) in params.iter().zip(arg_vals) {
                            self.env.define(p.clone(), v);
                        }
                        let result = self.eval_expr(&body);
                        self.env.pop_scope();
                        result
                    }
                    _ => Err(RuntimeError {
                        message: format!("'{}' is not callable", func),
                        span,
                    }),
                }
            }
            HvDataExprKind::ListLit(_) | HvDataExprKind::TupleLit(_) => {
                // Lists and tuples not embeddable per D2.4
                Err(RuntimeError {
                    message: "Lists and tuples not embeddable in TANGLE (D2.4)"
                        .to_string(),
                    span,
                })
            }
        }
    }

    /// Evaluate a Harvard binary operation.
    fn eval_hv_binop(
        &self,
        op: &crate::ast_jtv::HvBinOp,
        lhs: Value,
        rhs: Value,
        span: crate::lexer::Span,
    ) -> EvalResult {
        use crate::ast_jtv::HvBinOp;

        match (op, &lhs, &rhs) {
            (HvBinOp::Add, Value::Num(a), Value::Num(b)) => Ok(Value::Num(a + b)),
            (HvBinOp::Sub, Value::Num(a), Value::Num(b)) => Ok(Value::Num(a - b)),
            (HvBinOp::Mul, Value::Num(a), Value::Num(b)) => Ok(Value::Num(a * b)),
            (HvBinOp::Div, Value::Num(a), Value::Num(b)) => {
                if *b == 0.0 {
                    Err(RuntimeError {
                        message: "Division by zero".to_string(),
                        span,
                    })
                } else {
                    Ok(Value::Num(a / b))
                }
            }
            (HvBinOp::Mod, Value::Num(a), Value::Num(b)) => {
                if *b == 0.0 {
                    Err(RuntimeError {
                        message: "Modulo by zero".to_string(),
                        span,
                    })
                } else {
                    Ok(Value::Num(a % b))
                }
            }
            (HvBinOp::Eq, _, _) => Ok(Value::Bool(lhs == rhs)),
            (HvBinOp::NotEq, _, _) => Ok(Value::Bool(lhs != rhs)),
            (HvBinOp::Lt, Value::Num(a), Value::Num(b)) => Ok(Value::Bool(a < b)),
            (HvBinOp::LtEq, Value::Num(a), Value::Num(b)) => Ok(Value::Bool(a <= b)),
            (HvBinOp::Gt, Value::Num(a), Value::Num(b)) => Ok(Value::Bool(a > b)),
            (HvBinOp::GtEq, Value::Num(a), Value::Num(b)) => Ok(Value::Bool(a >= b)),
            (HvBinOp::And, Value::Bool(a), Value::Bool(b)) => Ok(Value::Bool(*a && *b)),
            (HvBinOp::Or, Value::Bool(a), Value::Bool(b)) => Ok(Value::Bool(*a || *b)),
            _ => Err(RuntimeError {
                message: format!(
                    "Type error in Harvard expression: {:?} applied to {} and {}",
                    op,
                    type_name(&lhs),
                    type_name(&rhs)
                ),
                span,
            }),
        }
    }

    /// Evaluate a Harvard unary operation.
    fn eval_hv_unary(
        &self,
        op: &crate::ast_jtv::HvUnaryOp,
        val: Value,
        span: crate::lexer::Span,
    ) -> EvalResult {
        use crate::ast_jtv::HvUnaryOp;
        match (op, &val) {
            (HvUnaryOp::Neg, Value::Num(n)) => Ok(Value::Num(-n)),
            (HvUnaryOp::Not, Value::Bool(b)) => Ok(Value::Bool(!b)),
            _ => Err(RuntimeError {
                message: format!(
                    "Type error: cannot apply {:?} to {}",
                    op,
                    type_name(&val)
                ),
                span,
            }),
        }
    }
}

impl Default for Interpreter {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// PATTERN MATCHING (D1.3, D1.4)
// ============================================================================

/// Attempt to match a value against a pattern.
///
/// Returns true if the pattern matches, populating `bindings` with bound
/// variable names. Implements the matching rules from FORMAL-SEMANTICS.md:
///   - M-Identity: `identity` matches empty word
///   - M-Cons: `g . p` matches if first generator equals g and rest matches p
///   - M-Var: `x` matches anything, binds x
///   - M-Wildcard: `_` matches anything, binds nothing
fn match_pattern(
    pattern: &Pattern,
    value: &Value,
    bindings: &mut HashMap<String, Value>,
) -> bool {
    match &pattern.kind {
        PatternKind::Identity => {
            // Matches empty word only
            matches!(value, Value::Word(gens) if gens.is_empty())
        }
        PatternKind::Cons { generator, rest } => {
            // Matches a word starting with a specific generator
            if let Value::Word(gens) = value {
                if let Some(first) = gens.first() {
                    if first.index == generator.index
                        && first.inverse == generator.inverse
                    {
                        // Match rest of the word against the rest pattern
                        let tail = Value::Word(gens[1..].to_vec());
                        return match_pattern(rest, &tail, bindings);
                    }
                }
            }
            false
        }
        PatternKind::Var(name) => {
            // Variable pattern: matches anything, binds the name
            bindings.insert(name.clone(), value.clone());
            true
        }
        PatternKind::Wildcard => {
            // Wildcard: matches anything, binds nothing
            true
        }
    }
}

// ============================================================================
// BRAID WORD OPERATIONS
// ============================================================================

/// Compute the width (number of strands) of a braid word (D1.8.5).
/// Width = max generator index + 1, or 0 for the empty word.
fn word_width(gens: &[Generator]) -> u32 {
    gens.iter()
        .map(|g| g.index + 1)
        .max()
        .unwrap_or(0)
}

/// Simplify a braid word by applying Reidemeister moves (D1.16).
///
/// Applies two simplification rules iteratively until no more changes:
///   1. R2 cancellation: si . si^-1 = identity (and si^-1 . si = identity)
///   2. Far commutativity: si . sj = sj . si when |i - j| >= 2
///      (used to bring cancellable pairs adjacent)
///
/// This is not a complete normal form algorithm (that would require
/// implementing Dehornoy's handle reduction or BKL normal form),
/// but it handles the common cases correctly.
fn simplify_word(gens: &[Generator]) -> Vec<Generator> {
    let mut result = gens.to_vec();
    let mut changed = true;

    while changed {
        changed = false;

        // Pass 1: Cancel adjacent inverse pairs (R2)
        let mut i = 0;
        let mut new_result = Vec::with_capacity(result.len());
        while i < result.len() {
            if i + 1 < result.len()
                && result[i].index == result[i + 1].index
                && result[i].inverse != result[i + 1].inverse
            {
                // Cancel si . si^-1 or si^-1 . si
                i += 2;
                changed = true;
            } else {
                new_result.push(result[i].clone());
                i += 1;
            }
        }
        result = new_result;

        // Pass 2: Try far commutation to expose new cancellations
        // si . sj -> sj . si when |i - j| >= 2
        // We do a single bubble pass: if swapping would bring a cancellation
        // opportunity closer, do it.
        let mut i = 0;
        while i + 1 < result.len() {
            let a = &result[i];
            let b = &result[i + 1];

            // Check if these generators commute (far apart)
            let diff = (a.index as i32 - b.index as i32).unsigned_abs();
            if diff >= 2 {
                // Check if swapping would create a cancellation opportunity
                let swap_helpful = (i + 2 < result.len()
                    && a.index == result[i + 2].index
                    && a.inverse != result[i + 2].inverse)
                    || (i > 0
                        && b.index == result[i - 1].index
                        && b.inverse != result[i - 1].inverse);

                if swap_helpful {
                    result.swap(i, i + 1);
                    changed = true;
                }
            }
            i += 1;
        }
    }

    result
}

/// Get the type name of a value for error messages.
fn type_name(val: &Value) -> &'static str {
    match val {
        Value::Word(_) => "Word",
        Value::Num(_) => "Num",
        Value::Str(_) => "Str",
        Value::Bool(_) => "Bool",
        Value::ClosedTangle(_) => "ClosedTangle",
        Value::Closure { .. } => "Function",
    }
}

// ============================================================================
// TESTS
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use crate::parser;

    /// Helper: parse and evaluate a program, returning the interpreter state.
    fn run(source: &str) -> Interpreter {
        let program = parser::parse(source).unwrap_or_else(|e| {
            panic!("Parse error: {}", e);
        });
        let mut interp = Interpreter::new();
        interp
            .exec_program(&program)
            .unwrap_or_else(|e| panic!("Runtime error: {}", e));
        interp
    }

    /// Helper: parse and evaluate, expecting a runtime error.
    fn run_err(source: &str) -> RuntimeError {
        let program = parser::parse(source).unwrap_or_else(|e| {
            panic!("Parse error: {}", e);
        });
        let mut interp = Interpreter::new();
        interp.exec_program(&program).unwrap_err()
    }

    // ---- Literal evaluation ----

    #[test]
    fn test_identity() {
        let _interp = run("def x = identity");
        // x is a thunk (zero-arg closure); force it
        let mut interp2 = run("def x = identity");
        let program = parser::parse("assert x == braid[]").unwrap();
        interp2.exec_program(&program).unwrap();
    }

    #[test]
    fn test_braid_literal() {
        let interp = run("def t = braid[s1, s1, s1]");
        // Force the thunk
        let mut interp = interp;
        let program =
            parser::parse("assert t == braid[s1, s1, s1]").unwrap();
        interp.exec_program(&program).unwrap();
    }

    #[test]
    fn test_num_literal() {
        let interp = run("def x = 42");
        let mut interp = interp;
        let program = parser::parse("assert x == 42").unwrap();
        interp.exec_program(&program).unwrap();
    }

    // ---- Arithmetic ----

    #[test]
    fn test_addition() {
        let interp = run("def x = 3\ndef y = 4\nassert x + y == 7");
        assert!(interp.output.is_empty()); // no compute output
    }

    #[test]
    fn test_multiplication() {
        run("def x = 6\nassert x * 7 == 42");
    }

    #[test]
    fn test_division_by_zero() {
        let err = run_err("assert 1 / 0 == 0");
        assert!(err.message.contains("Division by zero"));
    }

    // ---- Composition ----

    #[test]
    fn test_word_composition() {
        // braid[s1] . braid[s2] should equal braid[s1, s2]
        run("assert braid[s1] . braid[s2] == braid[s1, s2]");
    }

    #[test]
    fn test_identity_composition() {
        // identity . braid[s1] == braid[s1]
        run("assert identity . braid[s1] == braid[s1]");
    }

    // ---- Pattern matching ----

    #[test]
    fn test_match_identity() {
        run("def f(w) = match w with | identity => 0 | _ => 1 end\nassert f(identity) == 0");
    }

    #[test]
    fn test_match_cons() {
        run("def f(w) = match w with | identity => 0 | s1 . rest => 1 end\nassert f(braid[s1]) == 1");
    }

    #[test]
    fn test_recursive_length() {
        run(
            "def length(w) = match w with
               | identity => 0
               | s1 . rest => 1 + length(rest)
               | _ => 0
             end
             assert length(braid[s1, s1, s1]) == 3",
        );
    }

    #[test]
    fn test_match_failure() {
        let err = run_err(
            "def f(w) = match w with
               | identity => 0
             end
             assert f(braid[s1]) == 0",
        );
        assert!(err.message.contains("MatchFailure"));
    }

    // ---- Simplify / Reidemeister ----

    #[test]
    fn test_simplify_cancel() {
        // s1 . s1^-1 should simplify to identity
        run("assert simplify(braid[s1, s1^-1]) == identity");
    }

    #[test]
    fn test_simplify_no_cancel() {
        // s1 . s2 should not simplify (different indices)
        run("assert simplify(braid[s1, s2]) == braid[s1, s2]");
    }

    // ---- Isotopy ----

    #[test]
    fn test_isotopy_trivial() {
        // A word is isotopic to itself
        run("assert braid[s1, s1, s1] ~ braid[s1, s1, s1]");
    }

    #[test]
    fn test_isotopy_cancellation() {
        // s1 . s1^-1 is isotopic to identity
        run("assert braid[s1, s1^-1] ~ identity");
    }

    // ---- Mirror and Reverse ----

    #[test]
    fn test_mirror() {
        // mirror flips inversions
        run("assert mirror(braid[s1]) == braid[s1^-1]");
    }

    #[test]
    fn test_reverse() {
        // reverse reverses generator order
        run("assert reverse(braid[s1, s2]) == braid[s2, s1]");
    }

    // ---- Close ----

    #[test]
    fn test_close_creates_tangle() {
        // close(word) should produce a ClosedTangle
        let interp = run("def t = close(braid[s1, s1, s1])");
        let mut interp = interp;
        // Two closures of the same word are equal
        let prog = parser::parse(
            "assert close(braid[s1, s1, s1]) ~ close(braid[s1, s1, s1])",
        )
        .unwrap();
        interp.exec_program(&prog).unwrap();
    }

    // ---- Let binding ----

    #[test]
    fn test_let_binding() {
        run("assert let x = 5 in x + 3 == 8");
    }

    #[test]
    fn test_let_shadowing() {
        run(
            "def x = 10
             assert let x = 20 in x == 20",
        );
    }

    // ---- Compute ----

    #[test]
    fn test_compute_writhe() {
        let interp = run("compute writhe(braid[s1, s1, s1])");
        assert_eq!(interp.output.len(), 1);
        assert!(interp.output[0].contains("3"));
    }

    #[test]
    fn test_compute_writhe_inverse() {
        let interp = run("compute writhe(braid[s1^-1, s1^-1])");
        assert_eq!(interp.output.len(), 1);
        assert!(interp.output[0].contains("-2"));
    }

    // ---- Pipeline ----

    #[test]
    fn test_pipeline_is_compose() {
        // >> is sugar for . with lower precedence (D1.20)
        run("assert (braid[s1] >> braid[s2]) == braid[s1] . braid[s2]");
    }

    // ---- Tensor ----

    #[test]
    fn test_tensor() {
        // braid[s1] | braid[s1] should produce braid[s1, s3]
        // (second s1 shifted by width 2 becomes s3)
        run("assert (braid[s1] | braid[s1]) == braid[s1, s3]");
    }

    // ---- Boolean operations ----

    #[test]
    fn test_bool_equality() {
        run("assert true == true");
        run("assert false == false");
    }

    // ---- String literals ----

    #[test]
    fn test_string_equality() {
        run("assert \"hello\" == \"hello\"");
    }

    // ---- Weave blocks (statement-level) ----

    #[test]
    fn test_weave_statement() {
        // Weave blocks at statement level should execute without error
        run("weave strands a, b into (a > b) yield strands b, a");
    }

    // ---- Simplify with far commutativity ----

    #[test]
    fn test_simplify_far_commute() {
        // s1 . s3 . s1^-1 should simplify: s3 commutes past s1^-1
        // yielding s3 . s1 . s1^-1 = s3
        // Actually: s1 and s3 are far apart (|1-3|=2), so:
        // s1 . s3 . s1^-1 -> s3 . s1 . s1^-1 -> s3
        run("assert simplify(braid[s1, s3, s1^-1]) == braid[s3]");
    }
}
