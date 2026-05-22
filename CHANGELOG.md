<!-- SPDX-License-Identifier: MPL-2.0 -->
<!-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk> -->

# Changelog — Tangle

Tangle is a Turing-complete topological programming language. This file
tracks notable changes to the compiler, stdlib, tooling, and WASM runtime.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
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
