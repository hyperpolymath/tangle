<!--
SPDX-License-Identifier: CC-BY-SA-4.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
<!-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk> -->

# Component Readiness — Tangle (language)

**Current Grade:** D
**Assessed:** 2026-07-21 (demoted C → D)
**Standard:** [CRG v2.0 STRICT](../standards/component-readiness-grades/)

## Why the grade moved C → D

Grade C means *self-validated in the home context*; the D → C promotion trigger
is *"dogfood it hard in the home context."* The previous assessment cited
exactly one piece of dogfooding evidence:

> **Dogfooding:** Used internally as host for the KRL (Knot Resolution Language) DSL

**That is not true.** KRL is not built on Tangle. KRL is QuandleDB's resolution
language, developed jointly with QuandleDB; it neither compiles to nor depends
on Tangle, and the `TangleIR` layer that was supposed to connect them does not
exist in any source file in either repository. See the erratum in
`AFFIRMATION.adoc`.

With that claim withdrawn there is no dogfooding evidence, so C is not
supported. Two further corrections to the previous assessment:

- **"CI: Clean" was false.** At the time of this assessment `main` was failing
  Governance and both Jekyll Pages workflows.
- **The test suites are not run by CI.** Eight OCaml test files exist under
  `compiler/test/`, but no workflow in this repository invokes `dune` or
  `cargo test`. Their passing state is unverified by this repository's own CI.

This is a correction to the record, not a regression in the work. The formal
core in particular got *stronger* this cycle — see below.

---

## Grade rationale (evidence for D)

Grade D: *"works on some inputs, some cases, or some configurations, but not
systematically … either needs to be narrowed in scope so that its documented
capabilities match its actual capabilities, or needs the inconsistencies
fixed."* Narrowing the documented scope is exactly what this revision does.

### Verified evidence

| Artefact | Check | Result |
|---|---|---|
| `proofs/Tangle.lean` | `cd proofs && lean Tangle.lean` (the repo's own documented oracle) | **exit 0, no errors** |
| `proofs/Tangle.lean` | `sorry` count | **0** |
| `proofs/Tangle.lean` | `axiom` count | **0** |
| Theorems | `progress`, `preservation`, `determinism`, `type_safety`, `infer_sound`, `infer_complete`, `infer_iff_hasType` | all present with real proof terms |
| Dependencies | `import` lines in `Tangle.lean` | **0** — self-contained, no Mathlib |

Run on 2026-07-21 with the pinned toolchain (`leanprover/lean4:v4.14.0`). This
is worth stating precisely: a Lean file full of `axiom` stubs compiles cleanly
while proving nothing, so "the build is green" and "the theorems are proved" are
different claims. Here they coincide, and that was checked.

### Present but unverified

- **OCaml compiler** (`compiler/`) — lexer, parser, AST, typechecker, evaluator,
  pretty-printer, REPL, braid equivalence, LSP and WASM targets. Not built by
  any workflow.
- **Test suites** — 8 files under `compiler/test/` (`test_parser`,
  `test_typecheck`, `test_eval`, `test_e2e`, `test_property`,
  `test_compositional`, `test_check`, `test_roundtrip`) plus `tg3`/`tg5`/`tg7`/
  `tg8` directories. Not run by any workflow.
- **Rust / Zig components** — 18 `.rs`, 3 `.zig`. Not built by any workflow.
- **Five dialects** — grammar sketches only.

### Structural evidence

- Per-directory README annotation across `compiler/`, `dialects/`, `docs/`.
- RSR compliance: `0-AI-MANIFEST.a2ml`, `.machine_readable/6a2/`, workflows,
  SECURITY / CONTRIBUTING / CODE_OF_CONDUCT, `EXPLAINME.adoc`, `TEST-NEEDS.md`,
  `PROOF-NEEDS.md`.

---

## Gaps preventing higher grades

### Blocks C (self-validated in the home context)

1. **No CI gate on the implementation.** The OCaml compiler, its 8 test suites,
   and the Rust and Zig components are not built or run by any workflow. Until
   they are, "works reliably" is not an evidenced claim. This is the single
   highest-value fix available to this repository.
2. **No dogfooding.** Nothing is currently built on Tangle. The previous claim
   to the contrary was false.

### Blocks B (6+ diverse external targets)

- No external language users outside hyperpolymath.
- No external submissions to language research venues confirming the phase
  separation or compositional PD model.

### Blocks A

- Requires B first.

---

## What to do next

1. **Add a workflow that runs `dune build && dune test`.** Eight test suites
   already exist; nothing executes them. This is the cheapest available uplift
   and is a precondition for any claim above D.
2. Add a workflow that builds the Rust and Zig components.
3. Build something real on Tangle, in its own right — a braid-group calculus, a
   category-theory calculus, a quantum-circuit calculus. The five dialects are
   the natural candidates and currently exist only as grammar sketches.
   Note that this must be genuine dogfooding of *Tangle*; KRL does not count and
   never did.

## Review cycle

Reassess when the compiler is built and its tests are run by CI.
