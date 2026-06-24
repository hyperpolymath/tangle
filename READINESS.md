<!--
SPDX-License-Identifier: CC-BY-SA-4.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
<!-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk> -->

# Component Readiness — Tangle (language)

**Current Grade:** C
**Assessed:** 2026-04-05
**Standard:** [CRG v2.0 STRICT](../standards/component-readiness-grades/)

## Grade rationale (evidence for C)

Works reliably on own project + annotated. Tangle is a Turing-complete
topological programming language with a compiler, LSP, and wasm backend.

### Evidence

- **Tests:** 6 dune test suites (parser, typecheck, eval, e2e, property, compositional)
- **Annotation:** 8 per-directory READMEs across compiler/, lib/, examples/, docs/
- **Dogfooding:** Used internally as host for the KRL (Knot Resolution Language) DSL
- **RSR compliance:** 0-AI-MANIFEST.a2ml, `.machine_readable/6a2/`, 14+ workflows, SECURITY/CONTRIBUTING/CODE_OF_CONDUCT, EXPLAINME.adoc, TEST-NEEDS.md, PROOF-NEEDS.md
- **Formal proofs:** Lean 4 proofs for progress, preservation, determinism
- **WASM backend:** Compositional PD compiler with wasm codegen
- **CI:** Clean; panic-attack assail 0 findings

## Gaps preventing higher grades

### Blocks B (6+ diverse external targets)
- No external language users outside hyperpolymath.
- KRL is the only DSL built on Tangle so far — need 5 more distinct domain DSLs
  to demonstrate the host-language claim.
- No external submissions to language research venues confirming the phase
  separation or compositional PD model.

### Blocks A
- Requires B first.

## What to do for B

1. Build 5 more DSLs on top of Tangle (not just KRL) — e.g. a braid-group
   calculus, a category-theory calculus, a quantum-circuit calculus.
2. Get external feedback on the surface syntax and compiler from language
   researchers.
3. Track the 6 targets here.

## Review cycle

Reassess per release. Next review: on any compiler/LSP/wasm behavioural change.
