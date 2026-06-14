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
│    proofs/Tangle.lean — mechanised results (26 HasType, 57 Step) │
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
| **T-Progress** | Every well-typed closed term is either a value or can take a step. | `Tangle.lean:247-326` |
| **T-Preservation** | Stepping preserves types: `Γ ⊢ e : τ ∧ e → e' ⟹ Γ ⊢ e' : τ`. | `Tangle.lean:333-415` |
| **T-Determinism** | The step relation is deterministic: `e → e₁ ∧ e → e₂ ⟹ e₁ = e₂`. | `Tangle.lean:422-549` |
| **T-TypeSafety** | Well-typed closed terms never get stuck (Progress + Preservation corollary). | `Tangle.lean:556-558` |

Each is proven for the **let-free fragment** of the core: numerals,
strings, booleans, identity, braid literals, composition, tensor,
pipeline, close, addition, and equality.

### Supporting lemmas

| ID | Statement | Where |
|----|-----------|-------|
| T-ValueNoStep | Values are normal forms: `IsValue e ⟹ ¬ Step e e'`. | `Tangle.lean:189` |
| T-CanonicalNum | A typed-Num value is `.num n` for some `n`. | `Tangle.lean:193-194` |
| T-CanonicalStr | A typed-Str value is `.str s` for some `s`. | `Tangle.lean:197-198` |
| T-CanonicalWord | A typed-Word[n] value is `.identity` (n=0) or `.braidLit gs` (n = width gs). | `Tangle.lean:201-209` |
| T-WidthAppend | `width(gs₁ ++ gs₂) = max(width gs₁, width gs₂)`. | `Tangle.lean:219-221` |
| T-WidthShift | `width(shift gs n) = if gs=[] then 0 else width gs + n`. | `Tangle.lean:235-238` |
| T-FoldlMaxInit (private) | Algebraic identity for the width fold. | `Tangle.lean:212-217` |
| T-FoldlShiftInit (private) | Algebraic identity for the shifted width fold. | `Tangle.lean:223-233` |

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
- **`Step`** — small-step semantics, 57 rules: 27 base, 9 echo-close/lower/residue, 6 product, 11 echoAdd/echoEq, 2 let, 2 StepStar

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
| `test_roundtrip.ml` | TG-4 round-trip property test: 36 entries including all 8 echo/product constructors |

**Build oracle**: `dune build` + `dune test` (548/548) green since PR #46. The
pre-PR #46 `main` did not compile due to two `Warning 8` exhaustiveness gaps
(both fixed: `strand_type_of_ty` in `typecheck.ml`; debug token printer in `bin/main.ml`).

**TG-3 gap remains**: the OCaml typechecker is not yet proven to refine `HasType`;
the correspondence is validated by the test suite, not by a formal translation.

## 3. Remaining obligations (the narrative arc)

What's not yet proven, why it matters, and what assumption each rests on.

### TG-1 — Type safety extended to `let`-binding

**Claim.** Type safety extends to the language fragment with `let`.

**Why valuable.** The header comment of `Tangle.lean` explicitly
parks this: "T-Let: ... a future version can add the full substitution
machinery from e.g. Autosubst." Until then T-TypeSafety is for the
let-free fragment only. `let` is in the surface language (`compiler/
lib/ast.ml`), so users can write programs the proof doesn't cover.

**Assumptions.**
- [[A-TG-1.1]] Capture-avoiding substitution is well-defined on the
  de Bruijn representation already used by `HasType`.
- [[A-TG-1.2]] The standard "weakening" and "substitution" lemmas hold
  for the existing `HasType` rules.

**How to discharge.** Add the substitution lemma, extend `Step` with
a `let`-reduction rule, extend each cases-on-`hs` block in
preservation. Standard POPLmark machinery; ~150 LoC.

### TG-2 — Decidability of type checking

**Claim.** There is a total function `infer : Expr → Option Ty` such
that `infer e = some τ ↔ HasType [] e τ`.

**Why valuable.** `Tangle.lean` establishes the *relation* `HasType`
but not the *algorithm* `typecheck.ml`. Without TG-2 we have a proven
type system but no proof that the OCaml type checker actually decides
it.

**Assumptions.**
- [[A-TG-2.1]] Type-checking proceeds by syntactic recursion on `Expr`
  (no impredicative steps).
- [[A-TG-2.2]] Equality on `Ty` is decidable (it is — `deriving DecidableEq`).

**How to discharge.** Define `infer` in Lean as a structural recursion
on `Expr`. Prove the `↔` by case analysis matching the structure of
`HasType`'s rules.

### TG-3 — OCaml impl refines the Lean spec

**Claim.** For every `e` accepted by `compiler/lib/typecheck.ml` with
type `τ`, the Lean-level proposition `HasType [] e τ` holds (and
conversely).

**Why valuable.** Bridges the metatheory (Lean) to the implementation
(OCaml). Right now we have two systems claiming to be the same; the
claim is unchecked.

**Assumptions.**
- [[A-TG-3.1]] The OCaml AST in `compiler/lib/ast.ml` is in bijection
  with the Lean AST in `Tangle.lean`.
- [[A-TG-3.2]] OCaml's `String.equal`, `Int.equal` etc. coincide with
  Lean's notions on the values used.

**How to discharge.** Two routes:
1. _Translation validation._ Generate Lean witnesses from OCaml's
   typecheck results on a test corpus. Cheap but only empirical.
2. _Refinement._ Mechanise the OCaml algorithm in Lean and prove
   equivalence to `HasType`. Expensive but airtight.

### TG-4 — Pretty-print/parse round-trip

**Status: LANDED** (PR #46). `compiler/test/test_roundtrip.ml` extended with
36 entries including all 8 echo/product constructors; 548/548 tests pass.

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

### TG-9 — LSP diagnostics ⊆ `HasType` failures

**Claim.** Every diagnostic emitted by `tangle-lsp` corresponds to a
failure of the `HasType` judgment in `Tangle.lean`. (No
LSP-only diagnostics that the spec doesn't reject.)

**Why valuable.** Stops IDE drift from the language definition.
Without it, users get red squigglies in the editor for things that
compile, or vice versa.

**Assumptions.**
- [[A-TG-9.1]] `tangle-lsp` shares the OCaml `typecheck.ml` as its
  diagnostic engine (true by construction; verify after each refactor).

**How to discharge.** Audit `tangle-lsp/src/` for any
LSP-only diagnostic emission; route everything through `typecheck.ml`.
Single-PR scope.

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
