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
| TG-9 | LSP diagnostics are a subset of `HasType` failures (no LSP-only diagnostics) | INV | Audit + refactor | P2 | — | **LANDED** (`tangle-lsp` delegates all diagnostics to `tanglec --check` ⇒ `compiler/lib/check.ml`; hand-rolled LSP-only false positives removed. Subset holds by construction. Tests: `test_check.ml` + tangle-lsp unit/delegation tests) |
| TG-10 | Echo-types integrated into the type system: `Echo[ρ,τ]` former + `echoClose`/`lower`/`residue`/`echoAdd`/`echoEq` + product type (`pair`/`fst`/`snd`), with Progress/Preservation/Determinism/TypeSafety extended to cover them and the non-injectivity / residue-recovery capstones proven | TP / DOM | Lean 4 | P1 | — | **LANDED** (`proofs/Tangle.lean` §ECHO-TYPES) |

For full per-obligation statements, _why valuable_, and the
assumptions each rests on, see PROOF-NARRATIVE.md.

## Scoping of the remaining obligations (2026-06-14)

Concrete approach, effort, risk, and dependencies for what is left after
TG-0/1/2/4/9/10 landed. **Recommended order: TG-3 → TG-5 → TG-7 → TG-8 → TG-6.**

### TG-3 — OCaml `typecheck.ml` refines Lean `HasType` *(keystone, recommended next)*
- **Key lever:** TG-2 already proves Lean `infer ≡ HasType`. So refinement
  reduces to **OCaml `infer_expr` agrees with Lean `infer` on the shared core
  fragment** — a cross-language differential check, not a fresh metatheorem.
- **Approach:** translation-validation harness. Generate core-fragment terms,
  type each with OCaml `infer_expr` and with Lean `infer`, assert equal types
  (and equal accept/reject). Seed from existing corpora + a small generator.
- **Honest boundary:** the OCaml checker is far larger than the 26-rule core
  (match, weave, compute, cap/cup, mirror/reverse/simplify, twist, pipeline,
  two-pass program typing, width inference, Bool-eq). Deliverable = refinement
  validated on the core fragment + an explicit "extra-core" feature list, each
  marked model-later or declare-non-core. A universal Lean proof is out of reach
  without modelling the OCaml program itself.
- **Started:** `Eq` aligned to `tEqWord` this session. **Effort:** ~3–5d.
  **Risk:** med (scoping the fragment). **Deps:** TG-2.

### TG-5 — `compositional.ml` rewriter preserves types *(cheap, do early)*
- **Approach:** OCaml property test first — random compositional exprs →
  `compile` → assert PD invariants (arc balance, crossing-count = unit-word
  length, closedness, residue = verbatim source for `EchoClose`). Lean model of
  the IR + a preservation theorem is a later, optional second rung.
- `test_compositional.ml` now exists (the old "no test file" blocker is gone).
- **Effort:** property test ~1–2d; Lean model ~3d. **Risk:** low. **Deps:** none.

### TG-7 — `eqBraids` decides braid-group equivalence *(high-value domain work)*
- Current `Step.eqBraids` is list equality = a **soundness floor**, not
  completeness (misses σᵢσⱼ=σⱼσᵢ for |i−j|≥2 and σᵢσᵢ₊₁σᵢ=σᵢ₊₁σᵢσᵢ₊₁).
- **Approach:** implement Dehornoy **handle reduction** (practical braid word
  problem) in OCaml with tests against known equivalences/trefoil; mechanize
  correctness (Garside/Dehornoy theory) in Lean later.
- **Effort:** OCaml ~1w; Lean proof ~2w+ (deep). **Risk:** med-high (the maths).
  **Deps:** none (pure domain algorithm).

### TG-8 — each dialect is a conservative extension of core *(mechanical, voluminous)*
- 5 dialects (braid-calculus, quantum-circuit, skein-algebra, string-diagram,
  virtual-knot). Conservativity = core `HasType`/`Step` unchanged; new rules
  fire only on new syntax.
- **Approach:** model + prove ONE dialect end-to-end as a template, replicate.
- **Effort:** ~1w each (+1w for the first/template). **Risk:** low. **Deps:** the
  dialect specs/impls must exist.

### TG-6 — WASM compilation preserves semantics *(research-grade, plan separately)*
- **Approach:** practical first rung = **differential testing** (source `eval`
  vs wasm exec over a corpus, assert equal observable outputs). Full
  bisimulation proof (WasmCert / Wasm-spec) is a multi-week research project.
- **Effort:** differential ~1w; proof ~3w+ research. **Risk:** high (proof),
  low (differential). **Deps:** a runnable wasm runtime to exec against.

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
