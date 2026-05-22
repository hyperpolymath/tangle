# PROOF-NEEDS.md
<!-- SPDX-License-Identifier: MPL-2.0 -->

## Current State

- **LOC**: ~18,000
- **Languages**: OCaml, Rust, Idris2, Zig
- **Existing ABI proofs**: `src/abi/*.idr` (template-level)
- **Dangerous patterns**: None detected

## What Needs Proving

### Type Checker (compiler/lib/typecheck.ml — 775 lines)
- Core type checker for a Turing-complete topological programming language
- Prove: type soundness (preservation + progress)
- Prove: type checking terminates on all inputs

### Evaluator (compiler/lib/eval.ml)
- Prove: evaluation preserves types (subject reduction)
- Prove: well-typed programs in the decidable fragment terminate

### Parser Correctness (compiler/lib/)
- `token.ml`, lexer/parser
- Prove: parser accepts exactly the language defined by the grammar
- Less critical than type system proofs but valuable for confidence

### WASM Compilation (compiler/tangle-wasm/src/lib.rs)
- Prove: compilation preserves semantics (source-level evaluation matches WASM execution)
- This is a compiler correctness theorem — high value but high effort

### Fuzz Testing Coverage
- `compiler/fuzz/fuzz_lexer.ml`, `fuzz_parser.ml` — fuzzing is present but not formal
- Proofs would subsume the need for fuzzing on core invariants

## Recommended Prover

- **Coq** or **Lean4** — OCaml type checkers have a strong tradition of Coq mechanisation (e.g., CompCert)
- **Idris2** for the ABI layer

## Priority

**HIGH** — Programming language with a type checker and evaluator. Type soundness is the minimum bar for a language claiming Turing-completeness with a type system. Without it, the topological type claims are unverified.

## Template ABI Cleanup (2026-03-29)

Template ABI removed -- was creating false impression of formal verification.
The removed files (Types.idr, Layout.idr, Foreign.idr) contained only RSR template
scaffolding with unresolved {{PROJECT}}/{{AUTHOR}} placeholders and no domain-specific proofs.
