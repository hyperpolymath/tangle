// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// sexpr.rs — S-expression and JSON AST dump for TANGLE
//
// Covers every AST node type:
//   - Program, Stmt/StmtKind (Def, Weave, Compute, Assert, HarvardBlock)
//   - Expr/ExprKind (Var, IntLit, FloatLit, StrLit, BoolLit, Identity,
//     BraidLit, Pipeline, Eq, Isotopy, Add, Sub, Mul, Div, Compose, Tensor,
//     Twist, Close, Mirror, Reverse, Simplify, Cap, Cup,
//     CrossOver, CrossUnder, App, Match, Let, AddBlock)
//   - MatchArm, Pattern/PatternKind (Identity, Cons, Var, Wildcard)
//   - Generator, TypedStrand
//   - Harvard data expressions (HvDataExpr/HvDataExprKind)
//   - Harvard control statements (HvProgram, HvItem, HvStmt, HvFnDecl, etc.)

use tanglec::ast::*;
use tanglec::ast_jtv::*;

// ============================================================================
// S-EXPRESSION OUTPUT
// ============================================================================

/// Convert a complete TANGLE program to an S-expression string.
pub fn program_to_sexpr(program: &Program) -> String {
    let mut out = String::new();
    out.push_str("(program");
    for stmt in &program.stmts {
        out.push('\n');
        out.push_str("  ");
        stmt_to_sexpr(stmt, &mut out, 2);
    }
    out.push(')');
    out
}

/// Emit a newline followed by indentation.
fn nl(out: &mut String, indent: usize) {
    out.push('\n');
    for _ in 0..indent {
        out.push(' ');
    }
}

/// Convert a statement to S-expression form.
fn stmt_to_sexpr(stmt: &Stmt, out: &mut String, indent: usize) {
    match &stmt.kind {
        StmtKind::Def { name, params, body } => {
            out.push_str(&format!("(def \"{}\"", name));
            if !params.is_empty() {
                out.push_str(" (params");
                for p in params {
                    out.push_str(&format!(" \"{}\"", p));
                }
                out.push(')');
            }
            nl(out, indent + 2);
            expr_to_sexpr(body, out, indent + 2);
            out.push(')');
        }
        StmtKind::Weave {
            input_strands,
            body,
            output_strands,
        } => {
            out.push_str("(weave");
            out.push_str(" (input");
            for s in input_strands {
                out.push_str(&format!(" \"{}\"", s.name));
                if let Some(ref ty) = s.type_ann {
                    out.push_str(&format!(":{}", ty));
                }
            }
            out.push(')');
            nl(out, indent + 2);
            expr_to_sexpr(body, out, indent + 2);
            out.push_str(" (output");
            for s in output_strands {
                out.push_str(&format!(" \"{}\"", s.name));
                if let Some(ref ty) = s.type_ann {
                    out.push_str(&format!(":{}", ty));
                }
            }
            out.push_str("))");
        }
        StmtKind::Compute { invariant, expr } => {
            out.push_str(&format!("(compute \"{}\" ", invariant));
            expr_to_sexpr(expr, out, indent + 2);
            out.push(')');
        }
        StmtKind::Assert { expr } => {
            out.push_str("(assert ");
            expr_to_sexpr(expr, out, indent + 2);
            out.push(')');
        }
        StmtKind::HarvardBlock { program } => {
            out.push_str("(harvard");
            hv_program_to_sexpr(program, out, indent + 2);
            out.push(')');
        }
    }
}

/// Convert a generator to S-expression form.
fn generator_to_sexpr(g: &Generator, out: &mut String) {
    if g.inverse {
        out.push_str(&format!("(sigma-inv {})", g.index));
    } else {
        out.push_str(&format!("(sigma {})", g.index));
    }
}

/// Convert a pattern to S-expression form.
fn pattern_to_sexpr(pat: &Pattern, out: &mut String) {
    match &pat.kind {
        PatternKind::Identity => out.push_str("identity"),
        PatternKind::Cons { generator, rest } => {
            out.push_str("(cons ");
            generator_to_sexpr(generator, out);
            out.push(' ');
            pattern_to_sexpr(rest, out);
            out.push(')');
        }
        PatternKind::Var(name) => out.push_str(&format!("(pat-var \"{}\")", name)),
        PatternKind::Wildcard => out.push_str("_"),
    }
}

/// Convert an expression to S-expression form.
fn expr_to_sexpr(expr: &Expr, out: &mut String, indent: usize) {
    match expr.kind.as_ref() {
        ExprKind::Var(name) => out.push_str(&format!("(id \"{}\")", name)),
        ExprKind::IntLit(n) => out.push_str(&format!("{}", n)),
        ExprKind::FloatLit(f) => out.push_str(&format!("{}", f)),
        ExprKind::StrLit(s) => out.push_str(&format!("\"{}\"", s)),
        ExprKind::BoolLit(b) => out.push_str(if *b { "#t" } else { "#f" }),
        ExprKind::Identity => out.push_str("identity"),
        ExprKind::BraidLit(gens) => {
            out.push_str("(braid");
            for g in gens {
                out.push(' ');
                generator_to_sexpr(g, out);
            }
            out.push(')');
        }
        ExprKind::Pipeline(l, r) => {
            out.push_str("(>> ");
            expr_to_sexpr(l, out, indent + 2);
            out.push(' ');
            expr_to_sexpr(r, out, indent + 2);
            out.push(')');
        }
        ExprKind::Eq(l, r) => {
            out.push_str("(== ");
            expr_to_sexpr(l, out, indent + 2);
            out.push(' ');
            expr_to_sexpr(r, out, indent + 2);
            out.push(')');
        }
        ExprKind::Isotopy(l, r) => {
            out.push_str("(~ ");
            expr_to_sexpr(l, out, indent + 2);
            out.push(' ');
            expr_to_sexpr(r, out, indent + 2);
            out.push(')');
        }
        ExprKind::Add(l, r) => {
            out.push_str("(+ ");
            expr_to_sexpr(l, out, indent + 2);
            out.push(' ');
            expr_to_sexpr(r, out, indent + 2);
            out.push(')');
        }
        ExprKind::Sub(l, r) => {
            out.push_str("(- ");
            expr_to_sexpr(l, out, indent + 2);
            out.push(' ');
            expr_to_sexpr(r, out, indent + 2);
            out.push(')');
        }
        ExprKind::Mul(l, r) => {
            out.push_str("(* ");
            expr_to_sexpr(l, out, indent + 2);
            out.push(' ');
            expr_to_sexpr(r, out, indent + 2);
            out.push(')');
        }
        ExprKind::Div(l, r) => {
            out.push_str("(/ ");
            expr_to_sexpr(l, out, indent + 2);
            out.push(' ');
            expr_to_sexpr(r, out, indent + 2);
            out.push(')');
        }
        ExprKind::Compose(l, r) => {
            out.push_str("(compose ");
            expr_to_sexpr(l, out, indent + 2);
            out.push(' ');
            expr_to_sexpr(r, out, indent + 2);
            out.push(')');
        }
        ExprKind::Tensor(l, r) => {
            out.push_str("(tensor ");
            expr_to_sexpr(l, out, indent + 2);
            out.push(' ');
            expr_to_sexpr(r, out, indent + 2);
            out.push(')');
        }
        ExprKind::Twist(e) => {
            out.push_str("(twist ");
            expr_to_sexpr(e, out, indent + 2);
            out.push(')');
        }
        ExprKind::Close(e) => {
            out.push_str("(close ");
            expr_to_sexpr(e, out, indent + 2);
            out.push(')');
        }
        ExprKind::Mirror(e) => {
            out.push_str("(mirror ");
            expr_to_sexpr(e, out, indent + 2);
            out.push(')');
        }
        ExprKind::Reverse(e) => {
            out.push_str("(reverse ");
            expr_to_sexpr(e, out, indent + 2);
            out.push(')');
        }
        ExprKind::Simplify(e) => {
            out.push_str("(simplify ");
            expr_to_sexpr(e, out, indent + 2);
            out.push(')');
        }
        ExprKind::Cap(a, b) => {
            out.push_str("(cap ");
            expr_to_sexpr(a, out, indent + 2);
            out.push(' ');
            expr_to_sexpr(b, out, indent + 2);
            out.push(')');
        }
        ExprKind::Cup(a, b) => {
            out.push_str("(cup ");
            expr_to_sexpr(a, out, indent + 2);
            out.push(' ');
            expr_to_sexpr(b, out, indent + 2);
            out.push(')');
        }
        ExprKind::CrossOver { a, b } => {
            out.push_str(&format!("(cross-over \"{}\" \"{}\")", a, b));
        }
        ExprKind::CrossUnder { a, b } => {
            out.push_str(&format!("(cross-under \"{}\" \"{}\")", a, b));
        }
        ExprKind::App { func, args } => {
            out.push_str(&format!("(app \"{}\"", func));
            for arg in args {
                out.push(' ');
                expr_to_sexpr(arg, out, indent + 2);
            }
            out.push(')');
        }
        ExprKind::Match { scrutinee, arms } => {
            out.push_str("(match ");
            expr_to_sexpr(scrutinee, out, indent + 2);
            for arm in arms {
                nl(out, indent + 2);
                out.push_str("(arm ");
                pattern_to_sexpr(&arm.pattern, out);
                out.push(' ');
                expr_to_sexpr(&arm.body, out, indent + 4);
                out.push(')');
            }
            out.push(')');
        }
        ExprKind::Let { name, value, body } => {
            out.push_str(&format!("(let \"{}\" ", name));
            expr_to_sexpr(value, out, indent + 2);
            nl(out, indent + 2);
            expr_to_sexpr(body, out, indent + 2);
            out.push(')');
        }
        ExprKind::WeaveExpr {
            input_strands,
            body,
            output_strands,
        } => {
            out.push_str("(weave-expr");
            out.push_str(" (input");
            for s in input_strands {
                out.push_str(&format!(" \"{}\"", s.name));
                if let Some(ref ty) = s.type_ann {
                    out.push_str(&format!(":{}", ty));
                }
            }
            out.push(')');
            nl(out, indent + 2);
            expr_to_sexpr(body, out, indent + 2);
            out.push_str(" (output");
            for s in output_strands {
                out.push_str(&format!(" \"{}\"", s.name));
                if let Some(ref ty) = s.type_ann {
                    out.push_str(&format!(":{}", ty));
                }
            }
            out.push_str("))");
        }
        ExprKind::AddBlock { expr } => {
            out.push_str("(add-block ");
            hv_data_expr_to_sexpr(expr, out, indent + 2);
            out.push(')');
        }
    }
}

// ---------------------------------------------------------------------------
// Harvard Data Expressions (JTV injection)
// ---------------------------------------------------------------------------

/// Convert a Harvard data expression to S-expression form.
fn hv_data_expr_to_sexpr(expr: &HvDataExpr, out: &mut String, indent: usize) {
    match expr.kind.as_ref() {
        HvDataExprKind::IntLit(n) => out.push_str(&format!("{}", n)),
        HvDataExprKind::FloatLit(f) => out.push_str(&format!("{}", f)),
        HvDataExprKind::StrLit(s) => out.push_str(&format!("\"{}\"", s)),
        HvDataExprKind::BoolLit(b) => out.push_str(if *b { "#t" } else { "#f" }),
        HvDataExprKind::Var(name) => out.push_str(&format!("(id \"{}\")", name)),
        HvDataExprKind::Conditional {
            cond,
            then_branch,
            else_branch,
        } => {
            out.push_str("(if ");
            hv_data_expr_to_sexpr(cond, out, indent + 2);
            nl(out, indent + 2);
            hv_data_expr_to_sexpr(then_branch, out, indent + 2);
            nl(out, indent + 2);
            hv_data_expr_to_sexpr(else_branch, out, indent + 2);
            out.push(')');
        }
        HvDataExprKind::BinOp { op, lhs, rhs } => {
            let op_str = match op {
                HvBinOp::Add => "+",
                HvBinOp::Sub => "-",
                HvBinOp::Mul => "*",
                HvBinOp::Div => "/",
                HvBinOp::Mod => "%",
                HvBinOp::Eq => "==",
                HvBinOp::NotEq => "!=",
                HvBinOp::Lt => "<",
                HvBinOp::LtEq => "<=",
                HvBinOp::Gt => ">",
                HvBinOp::GtEq => ">=",
                HvBinOp::And => "and",
                HvBinOp::Or => "or",
            };
            out.push_str(&format!("({} ", op_str));
            hv_data_expr_to_sexpr(lhs, out, indent + 2);
            out.push(' ');
            hv_data_expr_to_sexpr(rhs, out, indent + 2);
            out.push(')');
        }
        HvDataExprKind::UnaryOp { op, operand } => {
            let op_str = match op {
                HvUnaryOp::Neg => "neg",
                HvUnaryOp::Not => "not",
            };
            out.push_str(&format!("({} ", op_str));
            hv_data_expr_to_sexpr(operand, out, indent + 2);
            out.push(')');
        }
        HvDataExprKind::Call { func, args } => {
            out.push_str(&format!("(call \"{}\"", func));
            for a in args {
                out.push(' ');
                hv_data_expr_to_sexpr(a, out, indent + 2);
            }
            out.push(')');
        }
        HvDataExprKind::ListLit(items) => {
            out.push_str("(list");
            for item in items {
                out.push(' ');
                hv_data_expr_to_sexpr(item, out, indent + 2);
            }
            out.push(')');
        }
        HvDataExprKind::TupleLit(items) => {
            out.push_str("(tuple");
            for item in items {
                out.push(' ');
                hv_data_expr_to_sexpr(item, out, indent + 2);
            }
            out.push(')');
        }
    }
}

/// Convert a Harvard program (from harvard{} blocks) to S-expression form.
fn hv_program_to_sexpr(prog: &HvProgram, out: &mut String, indent: usize) {
    for item in &prog.items {
        nl(out, indent);
        hv_item_to_sexpr(item, out, indent);
    }
}

/// Convert a Harvard item to S-expression form.
fn hv_item_to_sexpr(item: &HvItem, out: &mut String, indent: usize) {
    match &item.kind {
        HvItemKind::Module { name, body } => {
            out.push_str(&format!("(module \"{}\"", name));
            for sub in body {
                nl(out, indent + 2);
                hv_item_to_sexpr(sub, out, indent + 2);
            }
            out.push(')');
        }
        HvItemKind::Import { path, alias } => {
            out.push_str(&format!("(import \"{}\"", path.join(".")));
            if let Some(a) = alias {
                out.push_str(&format!(" :as \"{}\"", a));
            }
            out.push(')');
        }
        HvItemKind::FnDecl(fd) => {
            out.push_str(&format!("(fn \"{}\"", fd.name));
            if let Some(ref pur) = fd.purity {
                out.push_str(&format!(" :{:?}", pur));
            }
            out.push_str(" (params");
            for p in &fd.params {
                out.push_str(&format!(" \"{}\"", p.name));
            }
            out.push(')');
            for stmt in &fd.body {
                nl(out, indent + 2);
                hv_stmt_to_sexpr(stmt, out, indent + 2);
            }
            out.push(')');
        }
        HvItemKind::Stmt(stmt) => {
            hv_stmt_to_sexpr(stmt, out, indent);
        }
    }
}

/// Convert a Harvard statement to S-expression form.
fn hv_stmt_to_sexpr(stmt: &HvStmt, out: &mut String, indent: usize) {
    match &stmt.kind {
        HvStmtKind::Assignment { target, value } => {
            out.push_str(&format!("(assign \"{}\" ", target));
            hv_data_expr_to_sexpr(value, out, indent + 2);
            out.push(')');
        }
        HvStmtKind::If {
            cond,
            then_body,
            else_body,
        } => {
            out.push_str("(if ");
            hv_data_expr_to_sexpr(cond, out, indent + 2);
            out.push_str(" (then");
            for s in then_body {
                out.push(' ');
                hv_stmt_to_sexpr(s, out, indent + 4);
            }
            out.push(')');
            if let Some(els) = else_body {
                out.push_str(" (else");
                for s in els {
                    out.push(' ');
                    hv_stmt_to_sexpr(s, out, indent + 4);
                }
                out.push(')');
            }
            out.push(')');
        }
        HvStmtKind::While { cond, body } => {
            out.push_str("(while ");
            hv_data_expr_to_sexpr(cond, out, indent + 2);
            for s in body {
                nl(out, indent + 2);
                hv_stmt_to_sexpr(s, out, indent + 2);
            }
            out.push(')');
        }
        HvStmtKind::For {
            var,
            start,
            end: end_val,
            step,
            body,
        } => {
            out.push_str(&format!("(for \"{}\" ", var));
            hv_data_expr_to_sexpr(start, out, indent + 2);
            out.push_str(" .. ");
            hv_data_expr_to_sexpr(end_val, out, indent + 2);
            if let Some(s) = step {
                out.push_str(" .. ");
                hv_data_expr_to_sexpr(s, out, indent + 2);
            }
            for s in body {
                nl(out, indent + 2);
                hv_stmt_to_sexpr(s, out, indent + 2);
            }
            out.push(')');
        }
        HvStmtKind::Return { value } => {
            out.push_str("(return");
            if let Some(v) = value {
                out.push(' ');
                hv_data_expr_to_sexpr(v, out, indent + 2);
            }
            out.push(')');
        }
        HvStmtKind::Print { args } => {
            out.push_str("(print");
            for a in args {
                out.push(' ');
                hv_data_expr_to_sexpr(a, out, indent + 2);
            }
            out.push(')');
        }
        HvStmtKind::ReverseBlock { body } => {
            out.push_str("(reverse");
            for s in body {
                nl(out, indent + 2);
                hv_rev_stmt_to_sexpr(s, out, indent + 2);
            }
            out.push(')');
        }
        HvStmtKind::Block { body } => {
            out.push_str("(block");
            for s in body {
                nl(out, indent + 2);
                hv_stmt_to_sexpr(s, out, indent + 2);
            }
            out.push(')');
        }
    }
}

/// Convert a Harvard reversible statement to S-expression form.
fn hv_rev_stmt_to_sexpr(stmt: &HvReversibleStmt, out: &mut String, indent: usize) {
    match &stmt.kind {
        HvReversibleStmtKind::AddAssign { target, value } => {
            out.push_str(&format!("(+= \"{}\" ", target));
            hv_data_expr_to_sexpr(value, out, indent + 2);
            out.push(')');
        }
        HvReversibleStmtKind::SubAssign { target, value } => {
            out.push_str(&format!("(-= \"{}\" ", target));
            hv_data_expr_to_sexpr(value, out, indent + 2);
            out.push(')');
        }
        HvReversibleStmtKind::If {
            cond,
            then_body,
            else_body,
        } => {
            out.push_str("(if ");
            hv_data_expr_to_sexpr(cond, out, indent + 2);
            out.push_str(" (then");
            for s in then_body {
                out.push(' ');
                hv_rev_stmt_to_sexpr(s, out, indent + 4);
            }
            out.push(')');
            if let Some(els) = else_body {
                out.push_str(" (else");
                for s in els {
                    out.push(' ');
                    hv_rev_stmt_to_sexpr(s, out, indent + 4);
                }
                out.push(')');
            }
            out.push(')');
        }
    }
}

// ============================================================================
// JSON OUTPUT (manual — no serde dependency required)
// ============================================================================

/// Convert a complete TANGLE program to a JSON string (pretty-printed).
pub fn program_to_json(program: &Program) -> String {
    let mut out = String::new();
    out.push_str("{\n  \"format\": \"tangle-ast\",\n  \"version\": \"1.0\",\n  \"statements\": [\n");
    for (i, stmt) in program.stmts.iter().enumerate() {
        if i > 0 {
            out.push_str(",\n");
        }
        out.push_str("    ");
        stmt_to_json(stmt, &mut out, 4);
    }
    out.push_str("\n  ]\n}");
    out
}

/// Convert a statement to JSON.
fn stmt_to_json(stmt: &Stmt, out: &mut String, _indent: usize) {
    // Use Debug formatting wrapped in a JSON string for simplicity
    // since tangle does not have serde as a default dep
    let debug_str = format!("{:?}", stmt.kind);
    out.push_str(&format!("{{\"kind\": {}}}", json_escape(&debug_str)));
}

/// Escape a string for JSON output.
fn json_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if c < ' ' => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}
