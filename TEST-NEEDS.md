<!--
SPDX-License-Identifier: MPL-2.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
# TEST-NEEDS: tangle

## CRG Grade: C — ACHIEVED 2026-04-04

## Current State

| Category | Count | Details |
|----------|-------|---------|
| **Source modules** | 11 | Rust: ast, ast_jtv, lexer, parser, parser_jtv, eval, lib, main, sexpr + 3 Idris2 ABI |
| **Unit tests (inline)** | 252 | lexer=151, parser=40, parser_jtv=32, eval=29 |
| **Integration tests** | 0 | None |
| **E2E tests** | 0 | None |
| **Benchmarks** | 4 files | bench_lexer.rs (135L), bench_parser_rust.rs (106L), bench_lexer.ml (113L), bench_parser.ml (88L) |
| **Fuzz tests** | 2 | fuzz_lexer.rs, fuzz_parser.rs |

## What's Missing

### E2E Tests
- [ ] No test that parses a Tangle program and evaluates it end-to-end
- [ ] No test for the sexpr output format
- [ ] No test for the main binary

### Aspect Tests
- [ ] **Security**: No injection/escape tests for the parser
- [ ] **Performance**: Benchmarks exist -- need to verify they actually run
- [ ] **Concurrency**: N/A for a language parser
- [ ] **Error handling**: No tests for error recovery, partial parse, unterminated strings

### Build & Execution
- [ ] OCaml benchmarks (bench_lexer.ml, bench_parser.ml) -- does OCaml build config exist?
- [ ] No Idris2 ABI compilation test

### Benchmarks Status
- [x] bench_lexer.rs (135 lines) -- appears real
- [x] bench_parser_rust.rs (106 lines) -- appears real
- [?] bench_lexer.ml (113 lines) -- needs OCaml build verification
- [?] bench_parser.ml (88 lines) -- needs OCaml build verification

### Self-Tests
- [ ] No self-diagnostic mode

## FLAGGED ISSUES
- **252 inline unit tests is good** for a parser/lexer
- **Benchmarks appear genuine** -- best benchmark setup among scanned repos
- **Fuzz tests exist** -- rare and commendable
- **ast.rs, ast_jtv.rs, sexpr.rs have 0 tests** -- structural modules untested
- **No integration/E2E despite having eval** -- can't verify programs actually run correctly

## Priority: P2 (MEDIUM) -- solid unit/bench/fuzz foundation, needs E2E and integration
