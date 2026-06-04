// SPDX-License-Identifier: MPL-2.0
// Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
// bench_parser_rust.rs -- Parser benchmark harness for Tangle (Rust)
//
// Generates a large synthetic Tangle program and measures
// parse throughput: LOC/sec, total parse time, AST node count.
//
// Tangle is a topological/knot-theoretic DSL with definitions,
// weave blocks, braid literals, match/with/end, let/in, pipelines.
//
// Usage:  cargo run --release --example bench_parser_rust

use std::time::Instant;

/// Generate a synthetic Tangle program.
fn generate_program(num_defs: usize) -> String {
    let mut buf = String::with_capacity(num_defs * 400);

    for i in 0..num_defs {
        // Definition with composition and tensor
        buf.push_str(&format!("def knot_{}(a, b) = a . b + b . a\n\n", i));
        buf.push_str(&format!("def compose_{}(x, y) = x . y | y . x\n\n", i));

        // Weave blocks every 5th
        if i % 5 == 0 {
            buf.push_str(&format!(
                "weave strands s{}: wire into\n  s{} . s{}\nyield strands out{}\n\n",
                i, i, i, i
            ));
        }

        // Compute invariant every 8th
        if i % 8 == 0 {
            buf.push_str(&format!("compute jones(knot_{}(1, 2))\n\n", i));
        }

        // Match expression every 7th
        if i % 7 == 0 {
            buf.push_str(&format!("def classify_{}(x) =\n", i));
            buf.push_str("  match x with\n");
            buf.push_str("  | identity -> 0\n");
            buf.push_str(&format!("  | y -> {}\n", i + 1));
            buf.push_str("  end\n\n");
        }

        // Let-in expression every 6th
        if i % 6 == 0 {
            buf.push_str(&format!(
                "def bind_{} = let t = {} + {} in t * 2\n\n",
                i, i, i + 1
            ));
        }

        // Assert every 10th
        if i % 10 == 0 {
            buf.push_str(&format!(
                "assert knot_{}(1, 2) == knot_{}(1, 2)\n\n",
                i, i
            ));
        }
    }

    buf
}

fn count_lines(s: &str) -> usize {
    s.lines().count()
}

fn main() {
    let num_defs = 40;
    let iterations = 100;
    let source = generate_program(num_defs);
    let loc = count_lines(&source);

    println!("=== Tangle (Rust) Parser Benchmark ===");
    println!("Source: {} LOC, {} bytes", loc, source.len());
    println!("Iterations: {}\n", iterations);

    // Warm up
    {
        use tangle::parser::Parser;
        let mut parser = Parser::new(&source);
        match parser.parse_program() {
            Ok(prog) => println!("AST nodes (stmts): {}", prog.len()),
            Err(e) => eprintln!("Warm-up parse error: {}", e),
        }
    }

    let start = Instant::now();
    for _ in 0..iterations {
        use tangle::parser::Parser;
        let mut parser = Parser::new(&source);
        let result = parser.parse_program();
        std::hint::black_box(&result);
    }
    let elapsed = start.elapsed();

    let total_sec = elapsed.as_secs_f64();
    let per_iter = total_sec / iterations as f64;
    let loc_per_sec = (loc * iterations) as f64 / total_sec;

    println!("Total parse time : {:.4} s", total_sec);
    println!("Time per parse   : {:.6} s", per_iter);
    println!("LOC/sec          : {:.0}", loc_per_sec);
    println!("Bytes/sec        : {:.0}", (source.len() * iterations) as f64 / total_sec);
}
