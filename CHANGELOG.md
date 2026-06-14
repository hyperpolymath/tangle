<!--
SPDX-License-Identifier: MPL-2.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
<!-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk> -->

# Changelog — Tangle

Tangle is a Turing-complete topological programming language. This file
tracks notable changes to the compiler, stdlib, tooling, and WASM runtime.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Proof documentation catch-up (TG-1, TG-2, echo-types design note)

Both TG-1 and TG-2 were already fully proved in `proofs/Tangle.lean` but not
reflected in PROOF-NEEDS.md / PROOF-NARRATIVE.md. This entry documents the
retrospective correction.

- **TG-1 LANDED**: `weakening` + `subst_preserves` + all four theorems (Progress,
  Preservation, Determinism, TypeSafety) extended to `var`/`let`. The "let-free
  fragment" caveat in PROOF-NARRATIVE.md is retired.
- **TG-2 LANDED**: `infer` (structural recursion over all 26 HasType rules),
  `infer_sound`, `infer_complete`, `infer_iff_hasType`, `type_unique`,
  `decidableHasType` — all in `proofs/Tangle.lean` §TG-2.
- **echo-types grade semiring design note** (§2.8 of PROOF-NARRATIVE.md): the
  experimental ℕ∪{∞} min-plus grade semiring in `hyperpolymath/echo-types`
  (`f7a965f`) uses the combining/monadic direction — the same direction as
  Tangle's `echoAdd`/`echoEq`. The splitting/comonadic direction requires a full
  graded adjunction and is under experimental investigation (firewalled). No
  Tangle design change required now.

### Echo-threading: EchoClosed compositional IR node

The compositional PD compiler (`compositional.ml`) now threads the echo
residue through the IR. This is the OCaml-side implementation of the
cross-repo contract at `docs/spec/ECHO-TANGLEIR-THREADING.md`.

- **`EchoClose of expr`** added to the `expr` type; `echo_close` builder.
- **`EchoClosed { residue; diagram }`** added to `compiled` — carries
  the pre-closure braid word alongside the closed planar diagram
  (identical to the plain-`Close` output so existing consumers are
  unaffected).
- **`compile_echo_and_send_to_skein`** — residue-carrying Skein hook
  that emits `echo_closed_payload` with both `residue_blob`
  (`"s1,s2^-1,s1"` format) and the PDv1 blob.
- **`word_of_compiled (EchoClosed _)`** returns the residue braid —
  the pre-closure word is recoverable at the IR level.
- Parser adapter extended: `echoClose(braid[...])` compiles to
  `EchoClosed`.
- Validated against `EchoProvenance.agda` (echoes distinguish
  tag-differing records — exact analogue of distinct braids closing to
  the same diagram) and `EchoResidue.agda` (`no-section` theorem —
  the residue must be threaded, not recomputed after lowering).
- 9 new tests; total: **557/557** pass.

Downstream: Julia `KRLAdapter.jl` and `quandledb` implement the
consumer side per §3–4 of the contract doc.

### Echo types OCaml pipeline (PR #45 + #46)

### Added
- Echo/product type system fully landed in the OCaml pipeline (PR #45 + #46):
  - `ast.ml`: 8 new `expr` constructors (`echoClose`, `lower`, `residue`, `pair`, `fst`, `snd`, `echoAdd`, `echoEq`); 2 new `ty` constructors (`TProd`, `TEcho`)
  - `typecheck.ml`: 8 new `infer_expr` rules mirroring Lean `HasType` (`T-Echo-Close`, `T-Lower`, `T-Residue`, `T-Pair`, `T-Fst`, `T-Snd`, `T-Echo-Add`, `T-Echo-Eq`); `pp_ty` made `rec`
  - `eval.ml`: `VEcho`/`VPair` value forms; 8 new `eval_expr` arms; `pp_value` made `rec`
  - `lexer.mll` + `parser.mly` + `token.ml`: keyword tokens and grammar productions for all 8 surface forms (`echoClose(e)`, `lower(e)`, `residue(e)`, `pair(a,b)`, `fst(e)`, `snd(e)`, `echoAdd(a,b)`, `echoEq(a,b)`)
  - `pretty.ml`: pretty-printers for all 8 forms; round-trips through parser
- TG-4 (pretty-print/parse round-trip) discharged: `test_roundtrip.ml` extended with 16 new TG-4 entries covering every echo/product constructor (PR #46)
- `docs/spec/ECHO-TANGLEIR-THREADING.md`: cross-repo contract for how echo residue threads through TangleIR to QuandleDB (PR #45)
- Compositional PD compiler API (`compositional.ml` / `.mli`):
  `expr`, `planar_diagram`, `compiled`, `skein_payload` types
- `pdv1_blob_of_pd`: canonical text serialisation format
  (`pdv1|x=a,b,c,d,s;...|c=arc,arc;...`)
- `compile_and_send_to_skein`: direct Tangle → Skein integration entry point
- Playground scaffold in `playground/` (placeholder PWA + 2 example programs)
- README rewrite introducing KRL architecture + visual map (docs/krl_map.html)
- CRG v2 READINESS.md (grade C)

### Changed
- Tangle composition typecheck: correct permutation application
- WASM: fixed composed braid locals and helper expectations
- Zig ABI layer modernized

### Fixed
- `compiler/bin/main.ml` debug token printer: add 8 missing echo keyword token arms (Warning 8 exhaustiveness, PR #46)
- `compiler/lib/typecheck.ml` `strand_type_of_ty`: add `TProd`/`TEcho` arms (Warning 8 exhaustiveness, PR #46)
- EXPLAINME.adoc section heading quotes

## Earlier commits (no versions tagged)

### UX infrastructure
- Justfile with doctor, tour, help-me, assail recipes
- UX Manifesto deployment
- Agent instructions methodology layer

### Formal proofs
- Lean 4 proofs: progress, preservation, determinism
- TOPOLOGY.md documentation added

### RSR compliance
- A2ML migration of state files
- SPDX headers, license migration to MPL-2.0
- stapeln.toml container definition
- Standard workflow deployment (codeql, hypatia, scorecard, etc.)

### Language development
- Compiler (OCaml/dune): parser, typechecker, evaluator, pretty-printer, REPL
- WASM backend (`tangle-wasm/`)
- LSP server (`tangle-lsp/`)
- Stdlib (`lib/stdlib.tangle`)
