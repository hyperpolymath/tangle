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
| TG-3 | OCaml `typecheck.ml` refines the Lean `HasType` spec | TP | Lean 4 + translation validation | P1 | — | **LANDED** (translation-validation level — [`proofs/TG3-REFINEMENT.md`](proofs/TG3-REFINEMENT.md)). Reduced via TG-2 (`infer ≡ HasType`) to "OCaml `infer_expr` ≡ Lean `infer` on the core fragment", then discharged by: (a) a closure proof (core fragment never yields `TTangle`, strengthened tree-IH); (b) 496 Lean kernel-checked obligations in [`proofs/TG3Differential.lean`](proofs/TG3Differential.lean) generated from `infer_expr` by `compiler/test/tg3/tg3_emit.ml` (`by decide`; run `proofs/check-tg3-differential.sh`); (c) 1008 OCaml `--check` assertions (`dune runtest`). Complete divergence catalogue: **D1** `close` (OCaml `Tangle[I,I]` vs Lean `word 0` — sole boundary gateway, + downstream D1b/c/d) and **D2** `bool==bool` (OCaml accepts, Lean rejects). Extra-core feature list (model-later / declare-non-core) in TG3-REFINEMENT §3. Not claimed: a universal Lean proof over all OCaml runs (would require reflecting `typecheck.ml`); refinement is OCaml→Lean only |
| TG-4 | Pretty-print/parse round-trip on closed values | INV | OCaml property test (cheap) | P2 | 4h | **LANDED** (PR #46 — OCaml property test in `compiler/test/test_roundtrip.ml`, 26-entry corpus including 8 echo/product constructors; 52 round-trip runs) |
| TG-5 | `compositional.ml` (418 LoC) rewriter preserves types | TP | OCaml property test | P2 | — | **LANDED** (`compiler/test/tg5/tg5_invariants.ml`, 189 assertions in `dune runtest`). compositional is below the Ty layer, so "preserves types" = preserves the PD-lowering structural invariants + echo residue-recovery: `OpenWord`/`ClosedDiagram`/`EchoClosed` each pinned (closedness, `\|crossings\|`=unit-length, source unit-expanded, **verbatim residue** for `EchoClose` with `expand(residue)=diagram word` and echo-diagram pdv1-identical to plain `close`), error paths, count pins. Lean IR model = optional later rung |
| TG-6 | WASM compilation preserves semantics (source eval ≡ wasm exec) | TP / ALG | Lean 4 bisimulation | P1 | 3w (research-grade) | NOT STARTED |
| TG-7 | `Step.eqBraids` decides braid-group equivalence (not list equality) | ALG / DOM | OCaml + Lean 4 | P2 | 2w | NOT STARTED (current impl is soundness-floor, not completeness) |
| TG-8 | Each dialect (braid-calculus, quantum-circuit, skein-algebra, string-diagram, virtual-knot) is a conservative extension of core | TP | Lean 4 per-dialect | P3 | 1w each | NOT STARTED |
| TG-9 | LSP diagnostics are a subset of `HasType` failures (no LSP-only diagnostics) | INV | Audit + refactor | P2 | — | **LANDED** (`tangle-lsp` delegates all diagnostics to `tanglec --check` ⇒ `compiler/lib/check.ml`; hand-rolled LSP-only false positives removed. Subset holds by construction. Tests: `test_check.ml` + tangle-lsp unit/delegation tests) |
| TG-10 | Echo-types integrated into the type system: `Echo[ρ,τ]` former + `echoClose`/`lower`/`residue`/`echoAdd`/`echoEq` + product type (`pair`/`fst`/`snd`), with Progress/Preservation/Determinism/TypeSafety extended to cover them and the non-injectivity / residue-recovery capstones proven | TP / DOM | Lean 4 | P1 | — | **LANDED** (`proofs/Tangle.lean` §ECHO-TYPES) |

For full per-obligation statements, _why valuable_, and the
assumptions each rests on, see PROOF-NARRATIVE.md.

## Scoping of the remaining obligations (2026-06-14)

Concrete approach, effort, risk, and dependencies for what is left after
TG-0/1/2/3/4/5/9/10 landed. The three that remain are each **blocked on a
prerequisite, not on effort** (parallel readiness assessment, 2026-06-14):
TG-8 needs a dialect to actually exist as code; TG-7 needs an owner decision on
braid-equality semantics; TG-6 needs a wasm runtime stood up. **No further
auto-landing without those prerequisites.**

### TG-3 — OCaml `typecheck.ml` refines Lean `HasType` — ✅ **LANDED 2026-06-14**
- **Key lever (used):** TG-2 proves Lean `infer ≡ HasType`, so refinement
  reduced to **OCaml `infer_expr` ≡ Lean `infer` on the shared core fragment**.
- **Delivered:** (1) closure proof — the core fragment never yields `TTangle`
  under `infer_expr` (strengthened *entire-type-tree* IH; `close` is the sole
  boundary gateway, excluded); (2) machine-checked half — `proofs/TG3Differential.lean`,
  496 obligations `infer [] e = <infer_expr result> := by decide`, generated from
  the OCaml checker by `compiler/test/tg3/tg3_emit.ml`, kernel-verified by
  `proofs/check-tg3-differential.sh` (wired into `lean-proofs.yml`); (3) OCaml
  side — 1008 `dune runtest` assertions (closure invariant, curated pins, de
  Bruijn translation, divergence behaviours). Full write-up + extra-core list +
  divergence catalogue: `proofs/TG3-REFINEMENT.md`.
- **Divergences (complete):** D1 `close` (Tangle[I,I] vs word 0) + family
  D1b/c/d; D2 `bool==bool` (OCaml accepts / Lean rejects). Both pinned both sides.
- **Honest boundary:** translation validation over a broad corpus + a structural
  argument — NOT a universal Lean theorem over all OCaml runs (needs reflecting
  `typecheck.ml`). Extra-core features excluded, not modelled. OCaml→Lean only.

### TG-5 — `compositional.ml` rewriter preserves types — ✅ **LANDED 2026-06-14**
- **Delivered:** `compiler/test/tg5/tg5_invariants.ml` (189 assertions, in
  `dune runtest`). compositional has no `Ty`; "preserves types" is realised as
  preserving the PD-lowering structural invariants + the echo residue-recovery
  property. Per-variant pins: `OpenWord` unit-expanded; `ClosedDiagram`
  closed/`components=[]`/source unit-expanded/`|crossings|=|source|=unit-count`;
  `EchoClosed` residue **verbatim** (exponents preserved, e.g. `echoClose(s1^3)`
  keeps `[s1^3]` while the diagram is the 3-crossing unit closure),
  `expand(residue)=diagram word`, and echo-diagram pdv1-identical to plain
  `close`. Plus error-path message pins and concrete crossing-count pins.
- **Honest boundary:** asserts ONLY invariants the lowering guarantees — NOT arc
  balance, planarity, or crossing-index validity (the code makes no such claim).
  A Lean model of the PD IR + a mechanised preservation theorem is an optional
  later rung (Lean currently has no planar-diagram type).

### TG-7 — `eqBraids` decides braid-group equivalence — ⛔ **NEEDS OWNER DECISION**
- The only `eqBraids` is the Lean `Step` rule `eq (braidLit gs₁) (braidLit gs₂)
  → boolLit (gs₁ == gs₂)` = **list equality**; OCaml `eval.ml` matches it.
- Moving to Dehornoy handle reduction would **change the observable semantics of
  `==` on braids** (terms group-equal but not list-equal would newly compare
  true) on BOTH the OCaml evaluator AND the Lean `Step` relation, rippling into
  the Determinism/Preservation proofs. **This is a language-design decision, not
  just a proof — it must not be auto-landed.**
- **Owner decision needed:** (a) change `==` semantics to braid-group
  equivalence, or (b) keep `==` as-is and add an *out-of-band* `braid_equiv`
  checker (Dehornoy/BKL normal form) that does NOT touch `==`. The smallest
  non-semantic step is (b): an OCaml `braid_equiv : gen list -> gen list -> bool`
  with tests, no semantic change. Lean correctness (Garside/Dehornoy) remains
  research-grade either way.

### TG-8 — each dialect is a conservative extension of core — ⛔ **BLOCKED (no implementation)**
- All five dialects (`dialects/{braid-calculus,quantum-circuit,skein-algebra,
  string-diagram,virtual-knot}/`) are **prose + EBNF READMEs only** — zero
  parser, typing, or evaluation code. Conservativity is a property of a formal
  type system; there is no extended judgment/rules to state it over.
- **Prerequisite:** implement ONE dialect end-to-end as the template — e.g.
  virtual-knot: AST constructors (`ast.ml`), parser productions (`parser.mly`),
  `HasType`+`Step` rules (`Tangle.lean`), eval (`eval.ml`), then a conservativity
  test (core typed-in-core iff typed-in-dialect) mirroring the tg3/tg5 harness.
  Only then can conservativity be proven; replicate per dialect (~1w each).

### TG-6 — WASM compilation preserves semantics — ⛔ **BLOCKED (no wasm runtime)**
- `compiler/tangle-wasm` compiles Tangle→wasm but there is **no wasm runtime**
  (no wasmtime/wasmer dependency) to execute the output, and no FFI bridge to
  call it from the OCaml test harness. Differential testing has nothing to run.
- **Prerequisite (smallest rung):** add `wasmtime` (or `wasmer`) as a
  dev-dependency in `compiler/tangle-wasm/Cargo.toml`; stand up a harness that
  compiles an expr→wasm, instantiates it with the runtime, executes, reads the
  result from linear memory, and diffs against `eval.ml` on the same input
  (isolated test subdir, mirroring tg3/tg5). Full bisimulation (WasmCert /
  Wasm-spec) remains a multi-week research project on top of that.

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
