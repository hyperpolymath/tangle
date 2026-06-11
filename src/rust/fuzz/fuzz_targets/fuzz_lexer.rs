// SPDX-License-Identifier: MPL-2.0
// Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//! Fuzz target for the Tangle (Rust) lexer.
//!
//! Invariant: the lexer must NEVER panic on ANY input. It should always
//! return a token stream (possibly with Error tokens) without crashing.
//! The lexer has three modes (Tangle, HvData, HvControl) and mode
//! switching must be robust against malformed input.
//!
//! Run with:
//!   cargo +nightly fuzz run fuzz_lexer

#![no_main]

use libfuzzer_sys::fuzz_target;

use tanglec::lexer::Lexer;

fuzz_target!(|data: &[u8]| {
    // Convert arbitrary bytes to a UTF-8 string (lossy — replaces invalid
    // sequences with U+FFFD). The lexer must handle any valid UTF-8 string
    // without panicking.
    let input = String::from_utf8_lossy(data);

    // --- Test the convenience function ---
    let tokens = Lexer::tokenize(&input);

    // Walk every token to ensure none of the field accesses panic.
    for token in &tokens {
        let _ = &token.kind;
        let _ = &token.span;
        let _ = &token.text;
        let _ = format!("{:?}", token);
    }

    // --- Test the iterator-based Lexer::new path ---
    let mut lexer = Lexer::new(&input);
    loop {
        let token = lexer.next_token();
        let is_eof = token.kind == tanglec::lexer::TokenKind::Eof;
        let _ = format!("{:?}", token);
        if is_eof {
            break;
        }
    }
});
