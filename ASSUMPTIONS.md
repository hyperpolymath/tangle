<!--
SPDX-License-Identifier: MPL-2.0
Owner: Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
# Assumptions Registry — Tangle

Every load-bearing **unproven** assumption used in this repo, with an
ID, classification, and the obligation it supports.

Classifications:
- **MATH** — true by an external mathematical theorem (cite it)
- **DESIGN** — true by construction in our code (must remain true; flag if you change the named code)
- **EMPIRICAL** — believed from testing; not formally verified
- **CRYPTO** — standard cryptographic-primitive assumption

Cross-references use `[[A-TG-N.M]]` syntax, resolved here.

---

| ID | Class | Statement | Cited by | Where it lives |
|----|-------|-----------|----------|----------------|
| A-TG-1.1 | DESIGN | Capture-avoiding substitution is well-defined on the de Bruijn representation `HasType` uses | TG-1 | `Tangle.lean` `Ctx` definition + de Bruijn discipline |
| A-TG-1.2 | MATH | Standard weakening + substitution lemmas hold for the `HasType` rules (POPLmark / TAPL §8) | TG-1 | TAPL Ch. 9; Pierce 2002 |
| A-TG-2.1 | DESIGN | Type-checking proceeds by syntactic recursion on `Expr` (no impredicative steps; matches `typecheck.ml`'s shape) | TG-2 | `compiler/lib/typecheck.ml` |
| A-TG-2.2 | DESIGN | Equality on `Ty` is decidable (Lean: `deriving DecidableEq`; OCaml: structural `=`) | TG-2 | `Tangle.lean::Ty`; `compiler/lib/ast.ml` |
| A-TG-3.1 | DESIGN | The OCaml AST in `compiler/lib/ast.ml` is in bijection with the Lean AST in `Tangle.lean::Expr` | TG-3 | Both files, by construction |
| A-TG-3.2 | DESIGN | OCaml `String.equal`, `Int.equal` coincide with Lean's `==` on the values used at runtime | TG-3 | Standard library agreement; verify at the FFI boundary |
| A-TG-4.1 | DESIGN | `pretty.ml`'s bracketing is unambiguous w.r.t. `parser.mly`'s precedence | TG-4 | `compiler/lib/pretty.ml`, `compiler/lib/parser.mly` |
| A-TG-4.2 | DESIGN | Lexer never strips information needed by the parser (e.g. whitespace within braid literals) | TG-4 | `compiler/lib/lexer.mll` |
| A-TG-5.1 | DESIGN | Every rewrite in `compositional.ml` is `Expr → Expr` (no mutation) | TG-5 | `compiler/lib/compositional.ml` |
| A-TG-5.2 | DESIGN | No rewrite introduces a new free variable | TG-5 | Each rewrite, individually |
| A-TG-6.1 | MATH | WASM small-step semantics is well-defined; assume the official Wasm spec / WasmCert-Isabelle definition | TG-6 | wasm-spec, WasmCert-Isabelle |
| A-TG-6.2 | DESIGN | Source semantics has no floating-point non-determinism (Tangle has only `Int` currently) | TG-6 | `Tangle.lean::Ty` lacks `.float` |
| A-TG-7.1 | MATH | Word problem in the braid group `B_n` is solvable in polynomial time (Birman–Ko–Lee / Garside normal form) | TG-7 | Birman–Ko–Lee 1998; _A New Approach to the Word and Conjugacy Problems in the Braid Groups_ |
| A-TG-8.1 | DESIGN | Each dialect's grammar is a strict superset of core's EBNF (`tangle.ebnf`) | TG-8 | `dialects/*/grammar.ebnf` |
| A-TG-8.2 | DESIGN | Each dialect's typing rules are additive (new constructors + their typing rules only; no modification of existing rules) | TG-8 | Per-dialect spec |
| A-TG-9.1 | DESIGN | `tangle-lsp` emits diagnostics in four documented categories (`PARSE_ERROR`, `MISSPELLING_HINT`, `STRUCTURAL_HINT`, `NAME_HINT`); only `PARSE_ERROR` corresponds to a grammar-level rejection. The other three are LSP-only by design (Option B from TG-9 audit; Option A — full refinement via FFI to `typecheck.ml` — remains queued at #28). Each emission site is tagged in the `Diagnostic.source` field as `tangle-lsp[CATEGORY]`. | TG-9 | `compiler/tangle-lsp/src/backend.rs`; `compiler/tangle-lsp/docs/lsp-diagnostic-categories.md` |

---

## How to use this file

- **Reading code.** When you see a function whose correctness depends
  on something not enforced by the local types — _that's an
  assumption_. Find or add the entry here and reference it by ID.
- **Writing a proof.** Every proof obligation in
  [PROOF-NARRATIVE.md](PROOF-NARRATIVE.md) names its assumptions by ID.
  Before discharging the proof, audit the assumptions block.
- **Modifying load-bearing code.** Each DESIGN assumption names a
  file/component. If you edit that file, re-validate the assumption
  (or update the obligation if the design changed intentionally).

## Promoting / demoting assumptions

| From | To | Trigger |
|------|-----|---------|
| EMPIRICAL → MATH | discharge with a citation |
| EMPIRICAL → DESIGN | refactor to make it a structural invariant |
| MATH → (delete) | obligation has been re-cast not to need it |
| DESIGN → MATH (rare) | the design happens to encode a known theorem |

When you change a row, leave a one-line note in the changelog with the
date and reason.

---

## Changelog

| Date | Change | By |
|------|--------|-----|
| 2026-06-01 | Initial registry, scoped to Tangle metatheory + implementation refinement obligations | Audit |
| 2026-06-01 | A-TG-9.1 reformulated under TG-9 Option B — accept LSP-only categories instead of pretending refinement (full Option A queued at #28). See `compiler/tangle-lsp/docs/lsp-diagnostic-categories.md`. | TG-9 Option B PR |
