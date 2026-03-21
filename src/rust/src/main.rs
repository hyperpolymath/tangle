// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// main.rs — tanglec CLI entry point
//
// Provides parse, tokenize, and version subcommands.
// The parse subcommand supports --output pretty|sexpr|json for AST dump.

use std::fs;
use std::process;

mod sexpr;

fn main() {
    let args: Vec<String> = std::env::args().collect();

    if args.len() < 2 {
        print_usage();
        return;
    }

    match args[1].as_str() {
        "parse" => {
            if args.len() < 3 {
                eprintln!("Usage: tanglec parse <file.tgl> [--output pretty|sexpr|json]");
                process::exit(1);
            }
            let file = &args[2];
            let format = if args.len() >= 5 && args[3] == "--output" {
                args[4].as_str()
            } else {
                "pretty"
            };
            cmd_parse(file, format);
        }
        "tokenize" => {
            if args.len() < 3 {
                eprintln!("Usage: tanglec tokenize <file.tgl>");
                process::exit(1);
            }
            cmd_tokenize(&args[2]);
        }
        "version" | "--version" => {
            println!("tanglec 0.1.0");
            println!("TANGLE — Turing-complete topological programming language");
        }
        "help" | "--help" | "-h" => print_usage(),
        other => {
            eprintln!("Unknown command: {}", other);
            print_usage();
            process::exit(1);
        }
    }
}

/// Print usage information.
fn print_usage() {
    println!("tanglec — TANGLE language compiler");
    println!();
    println!("USAGE:");
    println!("  tanglec <command> [options]");
    println!();
    println!("COMMANDS:");
    println!("  parse <file> [--output pretty|sexpr|json]   Parse and dump AST");
    println!("  tokenize <file>                              Show lexer tokens");
    println!("  version                                      Show version info");
    println!("  help                                         Show this help");
}

/// Parse a file and output the AST in the chosen format.
///
/// Supported formats:
/// - `pretty` (default): Rust Debug formatting
/// - `sexpr` / `sexp`: S-expression representation
/// - `json`: JSON serialization (requires serde feature)
fn cmd_parse(path: &str, format: &str) {
    let source = match fs::read_to_string(path) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("Error reading {}: {}", path, e);
            process::exit(1);
        }
    };

    let mut parser = tanglec::parser::Parser::new(&source);
    let program = match parser.parse_program() {
        Ok(p) => p,
        Err(e) => {
            eprintln!("Parse error: {}", e);
            process::exit(1);
        }
    };

    match format {
        "sexpr" | "sexp" => {
            println!("{}", sexpr::program_to_sexpr(&program));
        }
        "json" => {
            println!("{}", sexpr::program_to_json(&program));
        }
        "pretty" | _ => {
            println!("{:#?}", program);
        }
    }
}

/// Tokenize a file and display all tokens.
fn cmd_tokenize(path: &str) {
    let source = match fs::read_to_string(path) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("Error reading {}: {}", path, e);
            process::exit(1);
        }
    };

    let tokens = tanglec::lexer::Lexer::tokenize(&source);
    for tok in &tokens {
        println!("{:?}", tok);
    }
    println!("\nTokenized {} tokens.", tokens.len());
}
