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
