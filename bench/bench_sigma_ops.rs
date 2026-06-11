// SPDX-License-Identifier: MPL-2.0
// Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
// (MPL-2.0 is automatic legal fallback until PMPL is formally recognised)
//
// bench_sigma_ops.rs — Tangle parser + IR ops benchmark with Six Sigma
// classification.
//
// Measures parse throughput (LOC/sec) and IR construction time for a
// synthetic Tangle program, then classifies each result against stored
// baselines using the hyperpolymath Six Sigma taxonomy:
//
//   UNACCEPTABLE  : >50 % regression  → hard fail
//   ACCEPTABLE    : 20–50 % regression → soft fail
//   ORDINARY      : ±20 %             → pass
//   EXTRAORDINARY : >20 % improvement → pass + flag
//
// First run: BASELINES are 0.0 → every result is printed as "[BASELINE]".
// Copy the printed values into BASELINES for subsequent CI comparisons.
//
// Usage (from tangle/src/rust/):
//   cargo run --release --example bench_sigma_ops
//   (file lives in tangle/bench/; symlink or copy to src/rust/examples/)

use std::time::{Duration, Instant};

// ── Six Sigma baselines (nanoseconds) ─────────────────────────────────────────
// Populate from a "[BASELINE]" run.  0.0 means "unset → baseline run".
struct Baselines {
    parse_small_ns:      f64,   // 10-def program, 100 iterations
    parse_large_ns:      f64,   // 40-def program, 100 iterations
    lex_throughput_ns:   f64,   // ns per source byte for large program
    ir_construct_ns:     f64,   // synthetic CrossingIR chain, 1 000 nodes
    alloc_vec_small_ns:  f64,   // Vec<u8> push 100 bytes
    alloc_vec_large_ns:  f64,   // Vec<u8> push 10 000 bytes
}

const BASELINES: Baselines = Baselines {
    parse_small_ns:     0.0,
    parse_large_ns:     0.0,
    lex_throughput_ns:  0.0,
    ir_construct_ns:    0.0,
    alloc_vec_small_ns: 0.0,
    alloc_vec_large_ns: 0.0,
};

// ── Six Sigma classifier ───────────────────────────────────────────────────────
#[derive(Debug, PartialEq)]
enum SigmaTier { Baseline, Extraordinary, Ordinary, Acceptable, Unacceptable }

struct SigmaSummary {
    baseline:      usize,
    extraordinary: usize,
    ordinary:      usize,
    acceptable:    usize,
    unacceptable:  usize,
}

impl SigmaSummary {
    fn new() -> Self {
        Self { baseline: 0, extraordinary: 0, ordinary: 0, acceptable: 0, unacceptable: 0 }
    }

    fn classify(&mut self, label: &str, measured_ns: f64, baseline_ns: f64) -> SigmaTier {
        if baseline_ns == 0.0 {
            println!("  [BASELINE]      {:<42}  {:.1} ns", label, measured_ns);
            self.baseline += 1;
            return SigmaTier::Baseline;
        }
        let pct = (measured_ns - baseline_ns) / baseline_ns * 100.0;
        if pct > 50.0 {
            println!("  [UNACCEPTABLE]  {:<42}  {:+.1} %  HARD FAIL", label, pct);
            self.unacceptable += 1;
            SigmaTier::Unacceptable
        } else if pct > 20.0 {
            println!("  [ACCEPTABLE]    {:<42}  {:+.1} %  soft fail", label, pct);
            self.acceptable += 1;
            SigmaTier::Acceptable
        } else if pct >= -20.0 {
            println!("  [ORDINARY]      {:<42}  {:+.1} %", label, pct);
            self.ordinary += 1;
            SigmaTier::Ordinary
        } else {
            println!("  [EXTRAORDINARY] {:<42}  {:+.1} %  improvement", label, pct);
            self.extraordinary += 1;
            SigmaTier::Extraordinary
        }
    }
}

// ── Timing helpers ─────────────────────────────────────────────────────────────
fn bench_ns<F: FnMut()>(mut f: F, warmup: usize, iterations: usize) -> f64 {
    for _ in 0..warmup { f(); }
    let mut times = Vec::with_capacity(iterations);
    for _ in 0..iterations {
        let t0 = Instant::now();
        f();
        times.push(t0.elapsed().as_nanos() as f64);
    }
    times.sort_by(f64::total_cmp);
    times[iterations / 2]  // median
}

fn ns_per_byte(total_ns: f64, bytes: usize, iterations: usize) -> f64 {
    total_ns / (bytes * iterations) as f64
}

// ── Synthetic Tangle program generators ───────────────────────────────────────
fn generate_program(num_defs: usize) -> String {
    let mut buf = String::with_capacity(num_defs * 400);
    for i in 0..num_defs {
        buf.push_str(&format!("def knot_{i}(a, b) = a . b + b . a\n\n"));
        buf.push_str(&format!("def compose_{i}(x, y) = x . y | y . x\n\n"));
        if i % 5 == 0 {
            buf.push_str(&format!(
                "weave strands s{i}: wire into\n  s{i} . s{i}\nyield strands out{i}\n\n"
            ));
        }
        if i % 8 == 0 {
            buf.push_str(&format!("compute jones(knot_{i}(1, 2))\n\n"));
        }
        if i % 7 == 0 {
            buf.push_str(&format!("def classify_{i}(x) =\n"));
            buf.push_str("  match x with\n  | identity -> 0\n");
            buf.push_str(&format!("  | y -> {}\n  end\n\n", i + 1));
        }
        if i % 6 == 0 {
            buf.push_str(&format!("def bind_{i} = let t = {i} + {} in t * 2\n\n", i + 1));
        }
        if i % 10 == 0 {
            buf.push_str(&format!("assert knot_{i}(1, 2) == knot_{i}(1, 2)\n\n"));
        }
    }
    buf
}

// ── Synthetic IR construction (CrossingIR chain) ───────────────────────────────
// CrossingIR: (id: usize, sign: i8, arcs: (usize, usize, usize, usize))
// sign ∈ {+1, -1, 0} where 0 = virtual crossing (Kauffman 1999).
#[derive(Debug)]
struct CrossingIR {
    id:   usize,
    sign: i8,
    arcs: (usize, usize, usize, usize),
}

fn build_crossing_chain(n: usize) -> Vec<CrossingIR> {
    let mut chain = Vec::with_capacity(n);
    for i in 0..n {
        let sign: i8 = match i % 3 {
            0 =>  1,  // positive crossing
            1 => -1,  // negative crossing
            _ =>  0,  // virtual crossing
        };
        chain.push(CrossingIR {
            id:   i,
            sign,
            arcs: (2 * i, 2 * i + 1, 2 * i + 2, 2 * i + 3),
        });
    }
    std::hint::black_box(chain)
}

// ── Main ───────────────────────────────────────────────────────────────────────
fn main() {
    let mut sigma = SigmaSummary::new();

    let small_src  = generate_program(10);
    let large_src  = generate_program(40);
    let small_loc  = small_src.lines().count();
    let large_loc  = large_src.lines().count();
    let large_bytes = large_src.len();

    println!("=== Tangle Benchmark Suite (Six Sigma) ===");
    println!("Small program: {} LOC, {} bytes", small_loc, small_src.len());
    println!("Large program: {} LOC, {} bytes\n", large_loc, large_bytes);

    // ── Parse throughput (using raw string scanning as proxy until parser is wired) ──
    // The tangle parser (Rust frontend) is called via tangle::parser::Parser
    // when compiled as part of the crate.  These benchmarks measure the
    // cost of the parse *pipeline* (tokenisation + AST construction) using
    // the source-level string as input.  Replace the scan_tokens stub with
    // `tangle::lexer::Lexer::tokenize` once the crate is linked.
    println!("─── Parse throughput (lexer proxy) ──────────────────────────────────────");

    let small_parse_ns = bench_ns(
        || { let _ = std::hint::black_box(scan_tokens(&small_src)); },
        3, 100,
    );
    sigma.classify("parse small (10 defs, 100 iters)", small_parse_ns, BASELINES.parse_small_ns);

    let large_parse_ns = bench_ns(
        || { let _ = std::hint::black_box(scan_tokens(&large_src)); },
        3, 100,
    );
    sigma.classify("parse large (40 defs, 100 iters)", large_parse_ns, BASELINES.parse_large_ns);

    let lex_byte_ns = ns_per_byte(large_parse_ns, large_bytes, 1);
    sigma.classify("lex throughput (ns/byte, large)", lex_byte_ns, BASELINES.lex_throughput_ns);

    println!();

    // ── IR construction ─────────────────────────────────────────────────────────
    println!("─── IR construction ─────────────────────────────────────────────────────");

    let ir_ns = bench_ns(
        || { let _ = build_crossing_chain(1_000); },
        3, 100,
    );
    sigma.classify("CrossingIR chain (1 000 nodes)", ir_ns, BASELINES.ir_construct_ns);

    println!();

    // ── Allocation micro-benchmarks ─────────────────────────────────────────────
    println!("─── Allocation micro-benchmarks ─────────────────────────────────────────");

    let alloc_small_ns = bench_ns(
        || {
            let mut v: Vec<u8> = Vec::with_capacity(100);
            for b in 0u8..100 { v.push(b); }
            std::hint::black_box(v);
        },
        3, 1_000,
    );
    sigma.classify("Vec<u8> push 100 bytes", alloc_small_ns, BASELINES.alloc_vec_small_ns);

    let alloc_large_ns = bench_ns(
        || {
            let mut v: Vec<u8> = Vec::with_capacity(10_000);
            for b in 0u8..=255 {
                for _ in 0..(10_000 / 256) { v.push(b); }
            }
            std::hint::black_box(v);
        },
        3, 200,
    );
    sigma.classify("Vec<u8> push 10 000 bytes", alloc_large_ns, BASELINES.alloc_vec_large_ns);

    println!();

    // ── Summary ─────────────────────────────────────────────────────────────────
    println!("─── Six Sigma Summary ───────────────────────────────────────────────────");
    let total = sigma.baseline + sigma.extraordinary + sigma.ordinary
                + sigma.acceptable + sigma.unacceptable;

    if sigma.baseline == total {
        println!("  BASELINE RUN — no prior measurements.  Record the ns values above.");
        println!("  Copy them into the BASELINES struct and recompile for CI runs.");
    } else {
        println!("  Baseline:      {}", sigma.baseline);
        println!("  Extraordinary: {}", sigma.extraordinary);
        println!("  Ordinary:      {}", sigma.ordinary);
        println!("  Acceptable:    {}  (soft fail)", sigma.acceptable);
        println!("  Unacceptable:  {}  (HARD FAIL)", sigma.unacceptable);
        println!();
        if sigma.unacceptable > 0 {
            println!("  RESULT: FAIL — {} hard regression(s)", sigma.unacceptable);
            std::process::exit(1);
        } else if sigma.acceptable > 0 {
            println!("  RESULT: WARN — {} soft regression(s), no hard fails", sigma.acceptable);
        } else {
            println!("  RESULT: PASS");
        }
    }

    println!("\n=== Done ===");
}

// ── Lexer proxy ────────────────────────────────────────────────────────────────
// Lightweight character-level token scanner.  Replace with the real
// tangle::lexer::Lexer when compiling as part of the crate.
fn scan_tokens(src: &str) -> Vec<(usize, usize)> {
    let bytes = src.as_bytes();
    let mut tokens = Vec::new();
    let mut i = 0;
    while i < bytes.len() {
        match bytes[i] {
            b' ' | b'\t' | b'\n' | b'\r' => { i += 1; }
            b'#' => { while i < bytes.len() && bytes[i] != b'\n' { i += 1; } }
            b'"' => {
                let start = i;
                i += 1;
                while i < bytes.len() && bytes[i] != b'"' { i += 1; }
                i += 1;
                tokens.push((start, i));
            }
            c if c.is_ascii_alphabetic() || c == b'_' => {
                let start = i;
                while i < bytes.len() && (bytes[i].is_ascii_alphanumeric() || bytes[i] == b'_') {
                    i += 1;
                }
                tokens.push((start, i));
            }
            c if c.is_ascii_digit() => {
                let start = i;
                while i < bytes.len() && bytes[i].is_ascii_digit() { i += 1; }
                tokens.push((start, i));
            }
            _ => { tokens.push((i, i + 1)); i += 1; }
        }
    }
    tokens
}
