<!--
SPDX-License-Identifier: MPL-2.0
Owner: Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
# Proof Narrative — Tangle

This file is the **single coherent story** of what Tangle proves, what
it assumes, and what it has left to prove.

For the per-obligation checklist with status/prover/effort, see
[PROOF-NEEDS.md](PROOF-NEEDS.md).
For the registry of every load-bearing unproven assumption, see
[ASSUMPTIONS.md](ASSUMPTIONS.md).

---

## 1. Position in the stack

Tangle is the **semantic core** of a four-layer federated stack:

```
┌─────────────────────────────────────────────────────────┐
│  KRL surface language     (hyperpolymath/krl)           │
└─────────────────┬───────────────────────────────────────┘
                  │ lowers via KR-1, KR-2 to
                  ▼
┌─────────────────────────────────────────────────────────┐
│  TangleIR                  (canonical interchange obj)  │
└─────────────────┬───────────────────────────────────────┘
                  │ has semantics via
                  ▼
┌─────────────────────────────────────────────────────────┐
│  Tangle CORE  (THIS REPO)                               │
│    proofs/Tangle.lean — mechanised results (26 HasType, 55 Step) │
│    compiler/lib/*.ml — OCaml implementation             │
│    compiler/tangle-wasm — WASM backend                  │
│    compiler/tangle-lsp — LSP server                     │
│    dialects/ — braid-calculus, quantum-circuit, etc.    │
└─────────────────┬───────────────────────────────────────┘
                  │ persisted/queried via
                  ▼
┌─────────────────────────────────────────────────────────┐
│  Skein.jl + QuandleDB                                   │
└─────────────────────────────────────────────────────────┘
```

Consequence: **Tangle owes a real metatheory.** It owns the type
system that everyone above and below depends on. Tangle.lean already
delivers a substantial slice of this; this document makes the
delivered slice and the remaining gap explicit.

## 2. Proven now

All results live in [`proofs/Tangle.lean`](proofs/Tangle.lean)
(Lean 4, no `sorry`, no `axiom`).

**Build oracle.** As of 2026-06-01 (PR closing TG-0, hyperpolymath/tangle#32),
the file is verified at every push/PR by `.github/workflows/lean-proofs.yml`,
pinned to `proofs/lean-toolchain = leanprover/lean4:v4.14.0`. Empirical
result on the original 2026-03-30 commit: 121 errors on every Lean 4
version 4.9–4.16 — the file had never compiled. The current commit
returns **0 errors**, verified locally on v4.10/4.11/4.12/4.13/4.14/4.15/4.16,
with CI gating both `lean Tangle.lean` and a `sorry`/`axiom`/`admit`
slippage check. Future drift will fail CI rather than land silently.

**Echo-types — now integrated as a type-system feature (2026-06-03).**
The earlier audit (`feedback_echo_types_audit_krl_tangle_quandledb_not_relevant.md`)
correctly found that the *external* echo-types Agda library
(hyperpolymath/echo-types) carries no lambda-calculus / progress /
preservation content of its own, so it does not perturb the four base
theorems. That verdict stands for the external library. **Tangle now
ships its own simply-typed shadow of echo-types as a first-class feature
of the type system** (`Ty.echo ρ τ`, constructors `echoClose`/`lower`/
`residue`, rules `T-Echo-Close`/`T-Lower`/`T-Residue`). The motivation is
intrinsic to Tangle: `close : Word[n] → Word[0]` is the canonical lossy
map (the analogue of echo-types' `collapse : Bool → ⊤`), and the echo
layer makes that loss recoverable at the type level — the residue
`Word[n]` is retained and projected back out. Progress, Preservation,
Determinism, and Type Safety in `proofs/Tangle.lean` now **cover the echo
fragment**, and three capstone theorems (`echo_lower_collapses`,
`echo_residue_recovers`, `echo_distinguishes_collapsed`) reproduce
echo-types' `no-section` / `sigma-distinguishes` barrier inside Tangle.
See PROOF-NARRATIVE §2.5.

### Theorems (the main results)

| ID | Statement | Where |
|----|-----------|-------|
| **T-Progress** | Every well-typed closed term is either a value or can take a step. | `Tangle.lean:670` |
| **T-Preservation** | Stepping preserves types: `Γ ⊢ e : τ ∧ e → e' ⟹ Γ ⊢ e' : τ`. | `Tangle.lean:870` |
| **T-Determinism** | The step relation is deterministic: `e → e₁ ∧ e → e₂ ⟹ e₁ = e₂`. | `Tangle.lean:1053` |
| **T-TypeSafety** | Well-typed closed terms never get stuck (Progress + Preservation corollary). | `Tangle.lean:1303` |

Each is proven for the **full core fragment**: numerals, strings, booleans, identity,
braid literals, composition, tensor, pipeline, close, addition, equality, variables,
let-binding, the complete echo/product fragment (see §2.5), and decidable type
inference (see §2.7). The "let-free fragment" caveat is retired — TG-1 and TG-2 are both landed.

### Supporting lemmas

| ID | Statement | Where |
|----|-----------|-------|
| T-ValueNoStep | Values are normal forms: `IsValue e ⟹ ¬ Step e e'`. | `Tangle.lean:394` |
| T-CanonicalNum | A typed-Num value is `.num n` for some `n`. | `Tangle.lean:405` |
| T-CanonicalStr | A typed-Str value is `.str s` for some `s`. | `Tangle.lean:409` |
| T-CanonicalWord | A typed-Word[n] value is `.identity` (n=0) or `.braidLit gs`. | `Tangle.lean:413` |
| T-CanonicalEcho | A typed-Echo value is `.echoVal r v` for values r, v. | `Tangle.lean:428` |
| T-CanonicalProd | A typed-Prod value is `.pair a b` for values a, b. | `Tangle.lean:443` |
| T-WidthAppend | `width(gs₁ ++ gs₂) = max(width gs₁, width gs₂)`. | `Tangle.lean:466` |
| T-WidthShift | `width(shift gs n) = if gs=[] then 0 else width gs + n`. | `Tangle.lean:485` |
| **T-Weakening** | Inserting a fresh hypothesis at de Bruijn position `Γ₁.length` preserves typing (TG-1). | `Tangle.lean:521` |
| **T-SubstPreserves** | Typing is preserved under capture-avoiding substitution of a typed term for a variable (TG-1). | `Tangle.lean:589` |

### Type-system and step-relation definitions

`Tangle.lean` also defines, as inductive types (so they are
themselves proofs of the form "these are the rules"):

- **`Expr`** — the AST (mirrors `compiler/lib/ast.ml`)
- **`Ty`** — `num`, `str`, `bool`, `word n`
- **`IsValue`** — value predicate
- **`HasType`** — typing judgment, 26 rules: 13 base (`tNum`, `tStr`, `tBool`,
  `tIdentity`, `tBraid`, `tComposeWord`, `tTensorWord`, `tPipeline`,
  `tCloseWord`, `tAddNum`, `tEqWord`, `tEqNum`, `tEqStr`); 4 echo-close
  (`tEchoClose`, `tLower`, `tResidue`, `tEchoVal`); 7 product+echo-binary
  (`tPair`, `tFst`, `tSnd`, `tEchoAdd`, `tEchoEqWord`, `tEchoEqNum`,
  `tEchoEqStr`); 2 let/var (`tVar`, `tLet`)
- **`Step`** — small-step semantics, 55 rules: 27 base, 9 echo-close/lower/residue, 6 product, 11 echoAdd/echoEq, 2 let (plus a separate 2-constructor `StepStar` reflexive-transitive closure: `refl`, `head`)

These are the formal spec the OCaml implementation is meant to refine
(see TG-3 below).

## 2.5 Echo types — structured loss as a type-system feature

Echo types are integrated into the core type system (not a separate
layer). The design mirrors echo-types' fibre definition
`Echo f y := Σ (x : A), f x ≡ y` (hyperpolymath/echo-types,
`Echo.agda`) in Tangle's simply-typed setting, motivated by Tangle's own
canonical lossy operation.

**Why `close`.** `close : Word[n] → Word[0]` collapses every braid word
to the identity, discarding the word — exactly the kind of
information-destroying map echo-types is about (cf. `collapse : Bool → ⊤`
in `EchoResidue.agda`). Echo types make that loss *recoverable in the
type system*.

| Construct | Form | Echo-types analogue |
|-----------|------|---------------------|
| Type former | `Ty.echo ρ τ` — a `τ`-result carrying a `ρ`-residue | `Echo f y` (ρ = domain witness, τ = codomain point) |
| `echoClose e` | `Word[n] → Echo (Word[n]) (Word[0])` | `echo-intro close` |
| `lower e` | `Echo ρ τ → τ` — project to result (forget residue) | the collapse / `proj₂` |
| `residue e` | `Echo ρ τ → ρ` — recover the witness braid | `proj₁` |
| `pair(a, b)` | `α → β → α × β` — product introduction | `Echo.Pair` (product as residue carrier) |
| `fst(e)` | `α × β → α` — first projection | `proj₁` |
| `snd(e)` | `α × β → β` — second projection | `proj₂` |
| `echoAdd(a, b)` | `Num → Num → Echo (Num × Num) Num` — addition with summand residue | `echo-intro add` |
| `echoEq(a, b)` | `ρ → ρ → Echo (ρ × ρ) Bool` — equality with operand residue | `echo-intro eq` |

**Metatheory.** Progress, Preservation, Determinism, and Type Safety all
cover `echoClose`/`lower`/`residue` (the inductions are exhaustive over
the extended `Step`/`HasType`). A new canonical-forms lemma
`canonical_echo` characterises echo values; `value_no_step` became
structurally recursive because a formed echo `echoClose v` is a value iff
its residue `v` is.

**Capstone theorems** (the echo-types *content*, `Tangle.lean` §ECHO-TYPES):
- `echo_lower_collapses` — every closed braid lowers to `identity`
  (the lossy step, re-derived through the echo).
- `echo_residue_recovers` — `residue (echoClose (braidLit gs)) ⟶ braidLit gs`
  (the witness is retained; `close` becomes reversible).
- `echo_distinguishes_collapsed` — distinct braids collapse to the *same*
  identity under `lower`, yet their residues stay distinct. This is the
  Tangle instantiation of echo-types' non-injectivity barrier
  (`collapse-residue-same` + `no-section-collapse-to-residue`).
- `echo_roundtrip_typed` — the round-trip is well-typed: `residue` returns
  a `Word[n]`, `lower` returns a `Word[0]`.

Tracked as obligation **TG-10** in PROOF-NEEDS.md (landed).

## 2.6 OCaml implementation completeness

As of 2026-06-14 (PRs #45–#46), the OCaml pipeline (`compiler/lib/`) covers the
complete echo + product fragment described in §2.5:

| Layer | Echo/product coverage |
|-------|-----------------------|
| `ast.ml` | `EchoClose`, `Lower`, `Residue`, `Pair`, `Fst`, `Snd`, `EchoAdd`, `EchoEq` in `expr`; `TProd`, `TEcho` in `ty` |
| `typecheck.ml` | 8 `infer_expr` rules matching Lean `HasType`; `pp_ty` made `rec` |
| `eval.ml` | `VEcho`, `VPair` values; 8 `eval_expr` arms; `pp_value` made `rec` |
| `lexer.mll` / `parser.mly` / `token.ml` | Keyword tokens + grammar productions for all 8 surface forms |
| `pretty.ml` | Pretty-printers for all 8 forms |
| `test_roundtrip.ml` | TG-4 round-trip property test: 26-entry corpus including all 8 echo/product constructors |

**Build oracle**: `dune build` + `dune test` green (run `dune runtest` for the
live count — ~597 across 8 suites). The
pre-PR #46 `main` did not compile due to two `Warning 8` exhaustiveness gaps
(both fixed: `strand_type_of_ty` in `typecheck.ml`; debug token printer in `bin/main.ml`).

**TG-3 landed** (translation validation): the OCaml typechecker is proven to
refine `HasType` on the core fragment — `proofs/TG3Differential.lean` emits 496
obligations generated from `infer_expr` that Lean's proven `infer` kernel-checks,
plus a closure proof and 1008 OCaml `--check` assertions. The two documented
divergences are `close` (D1) and `bool == bool` (D2). See `proofs/TG3-REFINEMENT.md`
and §TG-3 below.

## 2.7 Let-binding and decidability (TG-1 + TG-2)

Both obligations landed in `proofs/Tangle.lean` and are documented in §TG-1 and
§TG-2 of the remaining-obligations section below (those sections now carry LANDED
verdicts). Key structural points:

- **TG-1 (let-binding)**: `weakening` + `subst_preserves` use the de Bruijn
  combined-context invariant — `subst_preserves` types the substitutee in
  `Γ₁ ++ Γ₂`, not merely `Γ₂`. This is the genuine inductive invariant; the
  `letRed` consumer uses `Γ₁ := []` where both forms coincide.

- **TG-2 (decidability)**: `infer` is a single structural recursion covering all
  26 `HasType` rules. Both soundness and completeness are proven; `type_unique`
  follows as a corollary. The `decidableHasType` instance makes `HasType [] e τ`
  a decidable proposition directly usable by Lean's typeclass system.

## 2.8 Echo-types grade semiring — design note

`hyperpolymath/echo-types` (commit `f7a965f`, 2026-06-14) added an experimental
ℕ∪{∞} min-plus grade semiring (`experimental/echo-additive/Grade.agda`) and a
variance gate (`VarianceGate.agda`). Key findings and their implications for Tangle:

- The **combining direction** (`D_r(D_s A) → D_{r+s} A`) has **monadic** variance.
  Tangle's `echoAdd`/`echoEq` use exactly this direction: two residues are merged
  into a `pair` (the lax monoidal μ map). The current implementation is correct for
  this reading.

- The **splitting direction** (`D_{r+s} A → D_r(D_s A)`) has **comonadic** variance
  and requires a full graded adjunction F_r ⊣ U_r. If Tangle ever needs to split an
  `Echo(ρ×σ)` value back into independent `Echo(ρ)` and `Echo(σ)`, that is a
  non-trivial structural addition — it cannot be derived from the combining map alone.

- The **grade semiring** (`fin n` = information count, `inf` = total collapse) is a
  candidate carrier for a future grade-indexed type former `Echo[n] ρ τ` in Tangle.
  `echoAdd` would then have type `Num → Num → Echo[2] (Num×Num) Num` (2 units of
  information retained). This is prospective; the experimental subtree is firewalled
  until the comparative protocol (monadic vs comonadic) concludes.

- **No Tangle design change is required now.** The current `Ty.echo`/`Ty.prod`
  fragment is faithful to the monadic/combining direction and the experimental work
  is explicitly gated (`experimental/echo-additive/` is not imported by any shipped
  module in echo-types or Tangle).

## 3. Remaining obligations (the narrative arc)

What's not yet proven, why it matters, and what assumption each rests on.

### TG-1 — Type safety extended to `let`-binding

**Status: LANDED** (`proofs/Tangle.lean` §METATHEORY, lines 492–668).

**Claim.** Type safety (Progress, Preservation, Determinism, TypeSafety) extends
to the full core language including `var` and `let`.

**What was proven.**
- `weakening` (line 521) — inserting a fresh hypothesis `σ` at de Bruijn position
  `Γ₁.length` preserves typing, with the term shifted by `shift 1 Γ₁.length`.
- `subst_preserves` (line 589) — typing is closed under replacing the variable at
  `Γ₁.length` by a well-typed term `s`. The substitutee is typed in the combined
  context `Γ₁ ++ Γ₂` (the genuine inductive invariant; the `letRed` consumer
  instantiates `Γ₁ := []`).
- All four main theorems (Progress, Preservation, Determinism, TypeSafety) were
  extended with `var` and `letStep`/`letRed` cases. `Step` gained `letStep` and
  `letRed`; `HasType` gained `tVar` and `tLet`.

**Implementation notes.**
- Variable lookup uses `List.getElem?` (not the deprecated `List.get?`); the
  append splits go through `List.getElem?_append_left` / `_append_right`.
- Each derivation is taken apart with `cases h; rename_i` rather than
  `cases h with | tCtor`, because under `induction e` the binder arguments
  unify with the context and positional arm naming doesn't align.
- The `subst_preserves` combined-context invariant closes the `var = Γ₁.length`
  case by `exact hs` with no separate shift-composition lemma needed.

**Assumptions discharged.**
- [[A-TG-1.1]] ✓ — `subst` is defined by structural recursion on `Expr`, covering all 22 constructors.
- [[A-TG-1.2]] ✓ — `weakening` and `subst_preserves` both proven.

### TG-2 — Decidability of type checking

**Status: LANDED** (`proofs/Tangle.lean` §TG-2, lines 1399–1604).

**Claim.** There is a total function `infer : Expr → Option Ty` such
that `infer e = some τ ↔ HasType [] e τ`.

**What was proven.**
- `infer` (line 1410) — total structural recursion on `Expr`; covers all 26 `HasType`
  rules including the echo/product fragment and let-binding.
- `infer_complete` (line 1487) — `HasType Γ e τ → infer Γ e = some τ`.
- `infer_sound` (line 1493) — `infer Γ e = some τ → HasType Γ e τ`.
- `infer_iff_hasType` (line 1588) — the biconditional packaging both directions.
- `type_unique` (line 1593) — `HasType Γ e τ₁ → HasType Γ e τ₂ → τ₁ = τ₂` (follows
  from `infer_complete` + `infer_sound`).
- `decidableHasType` (line 1601) — `Decidable (HasType [] e τ)` instance via `infer`.

**Assumptions discharged.**
- [[A-TG-2.1]] ✓ — `infer` is defined by structural recursion; Lean's termination
  checker accepts it without any additional annotation.
- [[A-TG-2.2]] ✓ — `Ty` carries `deriving DecidableEq`; `Ty` comparisons in `infer`
  use it directly.

### TG-3 — OCaml impl refines the Lean spec

**Status: LANDED** (2026-06-14, translation-validation level). Full write-up:
`proofs/TG3-REFINEMENT.md`.

**Claim.** For every core-fragment `e` accepted by `compiler/lib/typecheck.ml`
with type `τ`, the Lean-level proposition `HasType [] e (T τ)` holds (and
conversely on rejection), where `T` is the type translation
`TNum↦num … TWord n↦word n, TEcho↦echo, TProd↦prod`.

**Why valuable.** Bridges the metatheory (Lean) to the implementation (OCaml) —
the two systems are now checked to be the same on the modelled fragment.

**How it was discharged.**
1. **Reduction (via TG-2).** `infer_iff_hasType` gives `infer ≡ HasType`, so the
   claim becomes "OCaml `infer_expr` ≡ Lean `infer` on the core fragment".
2. **Closure proof.** `infer_expr` keeps core terms inside the translatable types
   (never `TTangle`), under a strengthened *entire-type-tree* IH. `close` is the
   sole core gateway out of `T`'s domain and is excluded.
3. **Machine-checked half.** `proofs/TG3Differential.lean` — 496 obligations
   `infer [] e = T(infer_expr e) := by decide`, generated from the OCaml checker
   by `compiler/test/tg3/tg3_emit.ml`, verified by `proofs/check-tg3-differential.sh`.
4. **OCaml half.** `compiler/test/tg3` `--check`: 1008 `dune runtest` assertions
   (closure invariant, curated pins, named→de Bruijn translation, divergences).

**Divergences (complete).** D1 `close` (`Tangle[I,I]` vs `word 0`) + family
D1b/c/d through pipeline/compose/add; D2 `bool == bool` (OCaml accepts, Lean
rejects). Both sides pinned.

**Assumptions / boundary.**
- [[A-TG-3.1]] The core OCaml AST/`ty` is in bijection with the Lean AST/`Ty`
  under `T` (`TTangle` has no image — handled by the closure proof).
- Not claimed: a universal Lean theorem over all OCaml runs (route 2 below);
  extra-core features are excluded, not modelled; refinement is OCaml→Lean only.
- Future route 2 (_airtight refinement_): mechanise the OCaml algorithm in Lean
  and prove equivalence to `HasType` — out of scope here (see §7 of TG3-REFINEMENT.md).

### TG-4 — Pretty-print/parse round-trip

**Status: LANDED** (PR #46). `compiler/test/test_roundtrip.ml` is a 26-entry
corpus including all 8 echo/product constructors (52 round-trip runs); the
full suite is green (run `dune runtest` for the live total).

**Claim.** `parse(pretty e) = e` for every closed value `e`.

**Why valuable.** Free fuzz oracle. Also the foundation of any "IR
viewer" tooling that re-parses what `pretty` emitted.

**Assumptions.**
- [[A-TG-4.1]] `pretty.ml`'s bracketing is unambiguous w.r.t. the
  grammar.
- [[A-TG-4.2]] Lexer never strips information needed by the parser
  (e.g. whitespace within braid literals).

**How to discharge.** Property test in `compiler/test/` — discharged.

### TG-5 — `compositional.ml` rewriter preserves types

**Claim.** Every rewrite in `compiler/lib/compositional.ml` (418 LoC)
preserves typing: `Γ ⊢ e : τ ∧ e ↝ e' ⟹ Γ ⊢ e' : τ`.

**Why valuable.** That file has zero test coverage (see [B6] in the
bug audit) and is a high-blast-radius refactor target. Type
preservation is the cheapest soundness contract.

**Assumptions.**
- [[A-TG-5.1]] Each rewrite is a function from `Expr` to `Expr` —
  no in-place mutation.
- [[A-TG-5.2]] No rewrite introduces a new free variable.

**How to discharge.** First, add a test file
(`compiler/test/compositional_test.ml`) covering each rewrite.
Then add Lean-level rewrite-preservation lemmas, one per rewrite,
in a new file `proofs/Compositional.lean` parameterised on
`Tangle.lean`'s `HasType`.

### TG-6 — WASM compilation preserves semantics

**Claim.** For every closed well-typed `e`, the source-level
evaluation of `e` and the WASM execution of `compile_to_wasm(e)`
agree on the observable result.

**Why valuable.** The *compiler correctness* theorem. Warranted because
Tangle claims structural reasoning means *something* on the runtime.
Without this, Tangle's wasm backend is "trust us, the structure
survives."

**Assumptions.**
- [[A-TG-6.1]] Standard WASM semantics (assumed; specified by Wasm
  Cert / Wasm spec).
- [[A-TG-6.2]] No floating-point non-determinism in the source
  semantics (Tangle has only Int currently).

**How to discharge.** Bisimulation between OCaml `eval` and the WASM
small-step. Heavy — this is the high-value research-paper-grade slice
(see typed-wasm proof debt in the estate).

### TG-7 — Braid-axiom equality in `eqBraids`

**Claim.** `Step.eqBraids` should decide *braid-group equivalence*,
not list equivalence. I.e., `σ_i σ_j σ_i = σ_j σ_i σ_j when |i-j|=1`
and `σ_i σ_j = σ_j σ_i when |i-j|≥2` should be decidable in finite
generators.

**Why valuable.** The README claims "program equivalence is defined
by isotopy." Currently `eqBraids` only checks list equality, so
`σ_1 σ_2 σ_1` and `σ_2 σ_1 σ_2` are reported unequal. That's the
trivial reading.

**Status.** Current `eqBraids` is a soundness floor (if equal lists
then equal braids), not a completeness ceiling. Promoting it to
braid-group equivalence is a research-grade extension.

**Assumptions.**
- [[A-TG-7.1]] Word problem in the braid group is solvable in
  polynomial time on finitely many strands (Birman–Ko–Lee /
  Garside-normal-form algorithm — known true).

**How to discharge.** Implement Birman–Ko–Lee normal form;
re-prove `Step.eqBraids` against the normal form.

### TG-8 — Dialect conservativity

**Claim.** Each dialect under `dialects/`
(`braid-calculus`, `quantum-circuit`, `skein-algebra`, `string-diagram`,
`virtual-knot`) is a **conservative extension** of core Tangle: any
core program embedded into the dialect typechecks iff it typechecked
in core.

**Why valuable.** Lets dialect work proceed without re-proving safety
each time. Also stops dialect-introduced ambiguities from quietly
weakening core soundness.

**Assumptions.**
- [[A-TG-8.1]] Each dialect's grammar is a strict superset of core's
  EBNF.
- [[A-TG-8.2]] Each dialect's typing rules are *additive* — they only
  add new constructors and their typing rules, never modify existing
  ones.

**How to discharge.** Per dialect: define `HasType_dialect` in Lean as
`HasType` plus new rules; prove embedding preservation.

### TG-9 — LSP diagnostics ⊆ `HasType` failures — **LANDED**

**Claim.** Every diagnostic emitted by `tangle-lsp` corresponds to a
failure of the `HasType` judgment in `Tangle.lean`. (No
LSP-only diagnostics that the spec doesn't reject.)

**Why valuable.** Stops IDE drift from the language definition.
Without it, users get red squigglies in the editor for things that
compile, or vice versa.

**How discharged (by construction, not by proof).** The audit found the
LSP was emitting several **LSP-only false positives** from a hand-rolled
lexical scan: it skipped `--` comments (Tangle uses `#` / `(* *)`),
counted delimiters inside string literals, incremented block-depth on
every `def` (firing "unclosed block" on every multi-def file), and
flagged function parameters as "possibly undefined". None of these
corresponded to a `HasType` failure.

The refactor removes all hand-rolled diagnostics and routes the LSP
through the real compiler:
- `compiler/lib/check.ml` (`check_source`) is the single diagnostic
  source — parse-with-recovery + `Typecheck.check_program`.
- `tanglec --check` exposes it as `SEVERITY⇥LINE⇥COL⇥MESSAGE`.
- `tangle-lsp` shells out to `tanglec --check` and forwards exactly those
  diagnostics (`run_compiler_diagnostics`); the lexical scan now only
  extracts definitions/references for navigation. If the binary is
  absent it emits nothing — `∅ ⊆ HasType failures`, never a false positive.

So the subset relation holds *by construction*: the LSP cannot author a
diagnostic the compiler would not produce.

**Evidence.** `compiler/test/test_check.ml` (the diagnostic source is
exactly parse + type failures) and `tangle-lsp`'s unit tests
(`parse_check_line`, `analyze` authors no diagnostics, and a gated
end-to-end delegation test against a real `tanglec`).

**Locations.** Type errors scoped to a definition now carry that `def`'s
source line (`def_line`, threaded from the parser through `check_program`),
and the former duplicate diagnostic (pass 1b + pass 2 both reporting a def
error) is removed. Statement-level errors (assertions / computations /
weave blocks) are not yet located and still surface at the file top; column
spans for expressions remain future work. None of this affects the subset
property — only where a diagnostic points.

## 4. The "stupid proof" exclusions

For completeness, we explicitly do **not** pursue:

- _"`Expr` has exactly these constructors"_ — enforced by the inductive
  definition.
- _"Compose is left-associative"_ — surface syntax decision, not a
  semantic claim.
- _"`compile_to_wasm` returns a Vec<u8>"_ — Rust type assertion.
- _"`generatorWidth (g :: gs) ≥ g.idx + 1`"_ — implied by T-WidthAppend
  + cons semantics, no extra proof gains anything.

## 5. How to add a new obligation

1. Add a row to [PROOF-NEEDS.md](PROOF-NEEDS.md) with `TG-N` id,
   category, prover, priority, effort.
2. Add the narrative entry here with statement, _why valuable_,
   status, **assumptions**, _how to discharge_. Assumptions block
   is non-optional.
3. Each new assumption gets an entry in [ASSUMPTIONS.md](ASSUMPTIONS.md)
   with `A-TG-N.M` id and MATH/DESIGN/EMPIRICAL/CRYPTO classification.

## 6. References

- Implementation: [`compiler/lib/`](compiler/lib/) (OCaml, 2649 LoC).
- Formal core: [`proofs/Tangle.lean`](proofs/Tangle.lean) (Lean 4,
  560 LoC, all `Qed`).
- Spec: [`docs/spec/FORMAL-SEMANTICS.md`](docs/spec/FORMAL-SEMANTICS.md).
- Decisions: [`docs/spec/DECISIONS-LOCKED.md`](docs/spec/DECISIONS-LOCKED.md).
- Companion narratives:
  - `hyperpolymath/krl/PROOF-NARRATIVE.md` — surface-language obligations
  - `hyperpolymath/quandledb/PROOF-NARRATIVE.md` — quandle / DB proofs
