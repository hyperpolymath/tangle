<!--
SPDX-License-Identifier: MPL-2.0
Owner: Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
# Proof Requirements — Tangle

> Single coherent story: [PROOF-NARRATIVE.md](PROOF-NARRATIVE.md).
> Assumption registry: [ASSUMPTIONS.md](ASSUMPTIONS.md).
> This file is the **per-obligation checklist**.

## Proof tier

**Tier:** T1 — Critical.
Tangle owns the type system. KRL and QuandleDB rest on Tangle's
metatheory. The core (including let-binding) has been mechanised; the remaining gap is implementation-refinement and WASM/dialect proofs.

## Current state

- **LOC**: ~18,000 (OCaml + Rust + Tangle DSL + Lean proofs)
- **Languages**: OCaml (compiler), Rust (tangle-wasm), Lean 4 (proofs),
  Tangle DSL (lib/stdlib + examples)
- **Existing mechanised proofs**: `proofs/Tangle.lean` (~1604 LoC, 22+
  results, all `Qed`)
- **Dangerous patterns**: None detected

## What is already proven

Tracked in [PROOF-NARRATIVE.md §2](PROOF-NARRATIVE.md#2-proven-now)
and `proofs/Tangle.lean`:

| ID | Result | LoC |
|----|--------|-----|
| T-Progress | Every well-typed closed term is a value or steps | ~80 |
| T-Preservation | Stepping preserves types | ~180 |
| T-Determinism | Step relation is deterministic | ~250 |
| T-TypeSafety | Corollary: well-typed terms never get stuck | ~3 |
| T-Weakening | Context insertion preserves typing (TG-1) | ~70 |
| T-SubstPreserves | Substitution preserves typing (TG-1) | ~100 |
| `infer` + `infer_sound`/`infer_complete`/`infer_iff_hasType` | Algorithmic type inference ≡ HasType (TG-2) | ~120 |
| `type_unique` + `decidableHasType` | Type uniqueness + Decidable instance (TG-2) | ~15 |
| + canonical lemmas | canonical-num/str/word/echo/prod, value-no-step, width-append/shift, echo capstones, echoAdd/echoEq capstones | ~250 |

**Coverage:** the **full core fragment** of Tangle — `Num`, `Str`, `Bool`, `Identity`,
`BraidLit`, `Compose`, `Tensor`, `Pipeline`, `Close`, `Add`, `Eq`, `Var`, `Let`,
plus the **echo-types fragment** (`EchoClose`, `Lower`, `Residue`, `EchoAdd`,
`EchoEq`) and the **product type** (`Pair`, `Fst`, `Snd`). 26 typing rules,
55 step rules. All four theorems cover the full fragment including let-binding (TG-1)
and the echo/product fragment (TG-10). Type checking is decidable (TG-2).

## What remains

Cross-referenced to [PROOF-NARRATIVE.md §3](PROOF-NARRATIVE.md#3-remaining-obligations-the-narrative-arc).

| # | Statement | Category | Prover | Priority | Effort | Status |
|---|-----------|----------|--------|----------|--------|--------|
| TG-1 | Extend Progress/Preservation/Determinism/TypeSafety to `let`-binding | TP | Lean 4 | P1 | — | **LANDED** (`proofs/Tangle.lean` §METATHEORY — `weakening`, `subst_preserves`; all four theorems cover `var`/`let`) |
| TG-2 | Type checking is decidable: define `infer : Expr → Option Ty` proven equivalent to `HasType` | ALG | Lean 4 | P1 | — | **LANDED** (`proofs/Tangle.lean` §TG-2 — `infer`, `infer_sound`, `infer_complete`, `infer_iff_hasType`, `type_unique`, `decidableHasType`) |
| TG-3 | OCaml `typecheck.ml` refines the Lean `HasType` spec | TP | Lean 4 + translation validation | P1 | 5d | NOT STARTED (partial alignment: `Eq` now enforces same-width words to match `tEqWord`; `Bool == Bool` is a deliberate extra-core feature outside the 26-rule fragment, like `match`/`weave`/`mirror`/`compute` — these must be excluded from or added to the modelled core before TG-3 can close) |
| TG-4 | Pretty-print/parse round-trip on closed values | INV | OCaml property test (cheap) | P2 | 4h | **LANDED** (PR #46 — OCaml property test in `compiler/test/test_roundtrip.ml`, 26-entry corpus including 8 echo/product constructors; 52 round-trip runs) |
| TG-5 | `compositional.ml` (418 LoC) rewriter preserves types | TP | Lean 4 + OCaml test file | P2 | 3d | NOT STARTED (B6: no test file yet) |
| TG-6 | WASM compilation preserves semantics (source eval ≡ wasm exec) | TP / ALG | Lean 4 bisimulation | P1 | 3w (research-grade) | NOT STARTED |
| TG-7 | `Step.eqBraids` decides braid-group equivalence (not list equality) | ALG / DOM | OCaml + Lean 4 | P2 | 2w | NOT STARTED (current impl is soundness-floor, not completeness) |
| TG-8 | Each dialect (braid-calculus, quantum-circuit, skein-algebra, string-diagram, virtual-knot) is a conservative extension of core | TP | Lean 4 per-dialect | P3 | 1w each | NOT STARTED |
| TG-9 | LSP diagnostics are a subset of `HasType` failures (no LSP-only diagnostics) | INV | Audit + refactor | P2 | 1d | NOT STARTED |
| TG-10 | Echo-types integrated into the type system: `Echo[ρ,τ]` former + `echoClose`/`lower`/`residue`/`echoAdd`/`echoEq` + product type (`pair`/`fst`/`snd`), with Progress/Preservation/Determinism/TypeSafety extended to cover them and the non-injectivity / residue-recovery capstones proven | TP / DOM | Lean 4 | P1 | — | **LANDED** (`proofs/Tangle.lean` §ECHO-TYPES) |

For full per-obligation statements, _why valuable_, and the
assumptions each rests on, see PROOF-NARRATIVE.md.

## Proof categories

| Code | Meaning | Applies? |
|------|---------|----------|
| **TP** | Typing proofs | Yes |
| **INV** | Invariant proofs (round-trip, LSP discipline) | Yes |
| **SEC** | Security proofs | No |
| **CONC** | Concurrency proofs | No |
| **ALG** | Algorithm proofs (decidability, eqBraids, WASM compile) | Yes |
| **ABI** | ABI/FFI proofs | Out of scope (compiler-internal) |
| **DOM** | Domain proofs (braid-group, isotopy) | Yes |

## Dangerous patterns (BANNED)

CI rejects any PR introducing these:

| Pattern | Language | Meaning |
|---------|----------|---------|
| `believe_me` | Idris2 | Unsafe cast |
| `assert_total` | Idris2 | Skip totality check |
| `postulate` | Idris2 / Agda | Unproven axiom |
| `sorry` | Lean 4 | Incomplete proof |
| `axiom` (project-level) | Lean 4 | Unproven postulate |
| `Admitted` | Coq | Incomplete proof |
| `unsafeCoerce` | Haskell | Unsafe cast |
| `Obj.magic` | OCaml | Unsafe cast |
| `unsafe` (unaudited) | Rust | Unsafe block without safety comment |

Enforced by `panic-attack assail --proofs-only`.

## Recommended prover

- **Lean 4** for the core metatheory (already chosen; `proofs/Tangle.lean`).
- **Lean 4** for `infer`-decidability and `compositional`-preservation.
- **Lean 4 + Wasm-spec / WasmCert** for WASM compilation correctness.

## Template ABI cleanup (2026-03-29)

Template ABI files (Idris2 `Types.idr`, `Layout.idr`, `Foreign.idr`)
were removed in March 2026 — they contained only RSR template
scaffolding with unresolved placeholders and no domain-specific proofs.
This decision still stands; ABI proofs are out of scope here (Tangle
is compiler-internal; the FFI boundary is in KRL's repo).

## References

- Implementation: [`compiler/lib/`](compiler/lib/), [`compiler/tangle-wasm/`](compiler/tangle-wasm/), [`compiler/tangle-lsp/`](compiler/tangle-lsp/).
- Formal core: [`proofs/Tangle.lean`](proofs/Tangle.lean).
- Spec: [`docs/spec/FORMAL-SEMANTICS.md`](docs/spec/FORMAL-SEMANTICS.md).
- Companion narratives:
  `hyperpolymath/krl/PROOF-NARRATIVE.md`,
  `hyperpolymath/quandledb/PROOF-NARRATIVE.md`.
