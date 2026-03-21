// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell
//
// Fuzz target for the TANGLE (Rust) parser.
//
// Invariant: the parser must NEVER panic on ANY input. It should return
// ParseError, never abort.
//
// TANGLE is a braid/knot theory language with operators for vertical
// composition (.), horizontal tensor (|), pipeline (>>), and braid
// generators. This harness generates structured inputs biased toward
// TANGLE syntax.
//
// Run with:
//   cargo fuzz run fuzz_parser

#![no_main]

use libfuzzer_sys::fuzz_target;

/// TANGLE keywords, operators, and syntax fragments.
const FRAGMENTS: &[&str] = &[
    // Keywords
    "def", "weave", "into", "yield", "strands", "compute", "assert",
    "match", "with", "end", "let", "in", "close", "mirror", "reverse",
    "simplify", "cap", "cup", "twist",
    // Operators
    ".", "|", ">>", "==", "~", "+", "-", "*", "/",
    // Braid generators
    "s1", "s2", "s3", "s1^-1", "s2^-1",
    // Delimiters
    "(", ")", "[", "]", "{", "}", ",", ";", ":",
    "->", "=>",
    // Literals
    "42", "0", "3.14", "true", "false",
    // Identifiers
    "x", "y", "braid", "knot", "link", "_",
    // Whitespace
    " ", "\t", "\n",
    // Braid notation
    "braid[", "]",
    // Comments
    "// comment\n", "/* block */",
];

fn structured_input(data: &[u8]) -> String {
    let mut out = String::with_capacity(data.len() * 4);
    for &b in data {
        let idx = (b as usize) % FRAGMENTS.len();
        out.push_str(FRAGMENTS[idx]);
        if b & 0x80 != 0 {
            out.push(' ');
        }
    }
    out
}

fuzz_target!(|data: &[u8]| {
    // Strategy 1: raw UTF-8
    let raw = String::from_utf8_lossy(data);
    {
        let mut parser = tanglec::parser::Parser::new(&raw);
        let _ = parser.parse_program();
    }

    // Strategy 2: structured token-plausible input
    if data.len() > 2 {
        let structured = structured_input(&data[2..]);
        let mut parser = tanglec::parser::Parser::new(&structured);
        let _ = parser.parse_program();
    }
});
