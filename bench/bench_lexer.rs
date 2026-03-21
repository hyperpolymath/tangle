// SPDX-License-Identifier: PMPL-1.0-or-later
//! Lexer performance benchmark for TANGLE (Rust frontend)
//!
//! Measures:
//!   - Tokens per second on synthetic source (10K+ tokens)
//!   - Time to lex an empty file vs a large file
//!   - Memory allocation per token (via Vec capacity)
//!
//! Run:
//!   cargo run --release --example bench_lexer
//!   (from the tangle/src/rust/ directory)

use std::time::Instant;

// The tangle_rust crate exposes lexer::Lexer::tokenize(source)
// Adjust the crate path if the binary name differs.

/// Generate a realistic TANGLE source string with braid operations.
/// Uses TANGLE + TANGLE-JTV keywords and mode-switching syntax.
fn generate_source(num_statements: usize) -> String {
    let mut buf = String::with_capacity(num_statements * 100);
    let keywords = [
        "def", "weave", "into", "yield", "strands", "compute", "assert",
        "match", "with", "end", "let", "in", "braid", "identity",
        "true", "false", "close", "mirror", "reverse", "simplify",
        "cap", "cup",
    ];
    let operators = [
        ">>", "==", "=>", ".", "|", "+", "-", "*", "/", "~",
        ">", "<", "^", "=", ":",
    ];
    for i in 0..num_statements {
        let kw = keywords[i % keywords.len()];
        let op = operators[i % operators.len()];
        buf.push_str(&format!("{} strand_{} {} {} ;\n", kw, i, op, i * 5));
        if i % 8 == 0 {
            // Braid generators
            buf.push_str(&format!("s{} ", i % 9 + 1));
            buf.push_str(&format!("\"knot_{}\" ", i));
            buf.push_str("{ [ ( ) ] } , : _ \n");
        }
    }
    buf
}

/// Count tokens using the Tangle Rust lexer.
fn count_tokens(source: &str) -> usize {
    tangle_rust::lexer::Lexer::tokenize(source).len()
}

/// Get current RSS in bytes (Linux only).
fn get_rss_bytes() -> usize {
    #[cfg(target_os = "linux")]
    {
        if let Ok(statm) = std::fs::read_to_string("/proc/self/statm") {
            if let Some(rss_pages) = statm.split_whitespace().nth(1) {
                if let Ok(pages) = rss_pages.parse::<usize>() {
                    return pages * 4096;
                }
            }
        }
        0
    }
    #[cfg(not(target_os = "linux"))]
    { 0 }
}

fn main() {
    let iterations = 100;

    // --- Benchmark 1: Empty file ---
    let start = Instant::now();
    for _ in 0..iterations {
        let _ = count_tokens("");
    }
    let empty_elapsed = start.elapsed();
    println!("=== TANGLE (Rust) Lexer Benchmark ===\n");
    println!("Empty file:");
    println!(
        "  {} iterations in {:.4} s ({:.2} us/iter)",
        iterations,
        empty_elapsed.as_secs_f64(),
        empty_elapsed.as_secs_f64() / iterations as f64 * 1e6
    );

    // --- Generate large source ---
    let source = generate_source(2000);
    let source_bytes = source.len();
    let token_count = count_tokens(&source);
    println!("\nLarge file ({} bytes, {} tokens):", source_bytes, token_count);

    // --- Benchmark 2: Tokens/sec on large file ---
    let start = Instant::now();
    for _ in 0..iterations {
        let _ = count_tokens(&source);
    }
    let large_elapsed = start.elapsed();
    let total_tokens = (token_count * iterations) as f64;
    let tokens_per_sec = total_tokens / large_elapsed.as_secs_f64();
    println!("  {} iterations in {:.4} s", iterations, large_elapsed.as_secs_f64());
    println!("  {:.2} tokens/sec", tokens_per_sec);
    println!(
        "  {:.2} us/token",
        large_elapsed.as_secs_f64() / total_tokens * 1e6
    );
    println!(
        "  {:.2} MB/sec",
        (source_bytes * iterations) as f64 / large_elapsed.as_secs_f64() / 1e6
    );

    // --- Benchmark 3: Memory estimation ---
    let tokens = tangle_rust::lexer::Lexer::tokenize(&source);
    let rss_before = get_rss_bytes();
    let _ = tangle_rust::lexer::Lexer::tokenize(&source);
    let rss_after = get_rss_bytes();
    println!("\nMemory (approximate):");
    println!("  {} tokens produced", tokens.len());
    let token_size = std::mem::size_of::<tangle_rust::lexer::Token>();
    let vec_overhead = tokens.capacity() * token_size;
    println!(
        "  Vec backing store: {} bytes ({:.1} bytes/token, size_of Token = {})",
        vec_overhead,
        vec_overhead as f64 / tokens.len().max(1) as f64,
        token_size
    );
    if rss_after > rss_before {
        println!(
            "  RSS delta: {} bytes ({:.1} bytes/token)",
            rss_after - rss_before,
            (rss_after - rss_before) as f64 / tokens.len().max(1) as f64
        );
    }

    println!("\nDone.");
}
