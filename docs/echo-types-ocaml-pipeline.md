<!--
SPDX-License-Identifier: CC-BY-SA-4.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
# Echo Types — OCaml Pipeline Integration

> **Status**: Complete (PRs #45, #46, merged 2026-06-14).
> This page is the developer reference for the echo/product type integration
> in the OCaml compiler pipeline. For the formal metatheory see
> [PROOF-NARRATIVE.md §2.5](../PROOF-NARRATIVE.md) and
> [`proofs/Tangle.lean` §ECHO-TYPES](../proofs/Tangle.lean).
> For the cross-repo contract with QuandleDB see
> [ECHO-TANGLEIR-THREADING.md](spec/ECHO-TANGLEIR-THREADING.md).

---

## 1. What are echo types?

Echo types make structured loss **recoverable at the type level**. Tangle's
canonical lossy operation is `close : Word[n] → Word[0]`, which collapses any
braid to the identity, discarding the word. An `Echo ρ τ` value is a pair:

- **result** (`τ`) — what the lossy operation produces
- **residue** (`ρ`) — the pre-closure braid, retained in the type

The design mirrors `Echo f y := Σ (x : A), f x ≡ y` from
`hyperpolymath/echo-types` (`Echo.agda`) in Tangle's simply-typed setting.

The **product type** `ρ × σ` serves as the residue carrier for binary lossy
operations: `echoAdd` keeps both summands, `echoEq` keeps both operands.

---

## 2. Surface syntax

| Expression | Type | Meaning |
|------------|------|---------|
| `echoClose(e)` | `Word[n] → Echo (Word[n]) (Word[0])` | Close a braid, retaining the original as residue |
| `lower(e)` | `Echo ρ τ → τ` | Project to the result (forget the residue) |
| `residue(e)` | `Echo ρ τ → ρ` | Recover the witness braid |
| `pair(a, b)` | `α → β → α × β` | Construct a product |
| `fst(e)` | `α × β → α` | First projection |
| `snd(e)` | `α × β → β` | Second projection |
| `echoAdd(a, b)` | `Num → Num → Echo (Num × Num) Num` | Addition retaining summand pair as residue |
| `echoEq(a, b)` | `ρ → ρ → Echo (ρ × ρ) Bool` | Equality retaining operand pair as residue |

---

## 3. OCaml pipeline layers

### 3.1 AST (`compiler/lib/ast.ml`)

```ocaml
type expr =
  ...
  | EchoClose of expr
  | Lower     of expr
  | Residue   of expr
  | Pair      of expr * expr
  | Fst       of expr
  | Snd       of expr
  | EchoAdd   of expr * expr
  | EchoEq    of expr * expr

type ty =
  ...
  | TProd of ty * ty    (* ρ × σ — product residue carrier *)
  | TEcho of ty * ty    (* Echo ρ τ *)
```

### 3.2 Typechecker (`compiler/lib/typecheck.ml`)

Eight new `infer_expr` cases, all mirroring Lean `HasType`:

| OCaml rule | Lean rule | Type produced |
|-----------|-----------|--------------|
| `EchoClose e` | `tEchoClose` | `TEcho (TEcho(Word[n], inferred_width), TWord 0)` → simplified to `TEcho(ρ, TWord 0)` |
| `Lower e` | `tLower` | `τ` (from `TEcho ρ τ`) |
| `Residue e` | `tResidue` | `ρ` (from `TEcho ρ τ`) |
| `Pair(a, b)` | `tPair` | `TProd(α, β)` |
| `Fst e` | `tFst` | `α` (from `TProd α β`) |
| `Snd e` | `tSnd` | `β` (from `TProd α β`) |
| `EchoAdd(a, b)` | `tEchoAdd` | `TEcho(TProd(TNum, TNum), TNum)` |
| `EchoEq(a, b)` | `tEchoEqWord/Num/Str` | `TEcho(TProd(ρ, ρ), TBool)` |

### 3.3 Evaluator (`compiler/lib/eval.ml`)

New value forms:

```ocaml
type value =
  ...
  | VEcho of value * value   (* (residue, result) — Option B uniform form *)
  | VPair of value * value   (* product value *)
```

Echo values use the **Option B** uniform shape: `VEcho(residue, result)` in all
cases. `echoClose` produces `VEcho(v, VBraid [])`, where `VBraid []` is Tangle's
identity value (Word[0], the same point `close`/`Identity` yields). `echoAdd`
produces `VEcho(VPair(VInt n1, VInt n2), VInt(n1 + n2))`. `echoEq` produces
`VEcho(VPair(v1, v2), VBool(v1 = v2))`.

### 3.4 Lexer / parser / tokens

Tokens (`compiler/lib/token.ml`):
`ECHOCLOSE`, `LOWER`, `RESIDUE`, `PAIR`, `FST`, `SND`, `ECHOADD`, `ECHOEQ`

All 8 keywords are registered in the lexer (`lexer.mll`) and have dedicated
grammar productions in `parser.mly` following the existing unary
(`KW LPAREN expr RPAREN`) and binary (`KW LPAREN expr COMMA expr RPAREN`) patterns.

### 3.5 Pretty printer (`compiler/lib/pretty.ml`)

All 8 forms pretty-print to the same surface syntax that the parser accepts,
satisfying the TG-4 round-trip obligation.

---

## 4. Round-trip guarantee (TG-4)

`compiler/test/test_roundtrip.ml` tests `parse(pretty(e)) = e` and
`pretty(parse(pretty(parse(s)))) = pretty(parse(s))` for every constructor.

Echo/product entries:
`echoClose`, `lower`, `residue`, `pair`, `fst`, `snd`, `echoAdd`, `echoEq`
— 16 test cases (8 basic + 8 idempotent), all passing as of PR #46.

---

## 5. Proof coverage

The formal spec (`proofs/Tangle.lean`) covers the complete echo+product fragment:

| Lean theorem | Coverage |
|-------------|----------|
| `T-Progress` | All 8 echo/product expression forms |
| `T-Preservation` | All 8 echo/product expression forms |
| `T-Determinism` | All 8 echo/product expression forms |
| `T-TypeSafety` | Corollary (progress + preservation) |
| `echo_lower_collapses` | Every closed braid lowers to `identity` |
| `echo_residue_recovers` | `residue(echoClose(braid[gs])) →* braid[gs]` |
| `echo_distinguishes_collapsed` | Distinct braids keep distinct residues after `lower` |
| `echo_roundtrip_typed` | Round-trip is well-typed |

The OCaml typechecker is proven to refine `HasType` on the core fragment at the
translation-validation level (TG-3, **landed** — see
[`proofs/TG3-REFINEMENT.md`](../proofs/TG3-REFINEMENT.md)): `proofs/TG3Differential.lean`
emits 496 obligations `infer [] e = <infer_expr e> := by decide` that Lean's
proven `infer` kernel-checks, and the echo/product ops above are all in the
validated core. The two documented divergences are `close` (OCaml `Tangle[I,I]`
vs Lean `Word[0]`) and `Bool == Bool` (OCaml extra-core convenience; Lean rejects).

---

## 6. Known gaps and future work

| Gap | Tracking |
|-----|----------|
| TG-3 universal proof (reflect `typecheck.ml` in Lean) — current discharge is translation validation over a core-fragment corpus | PROOF-NEEDS.md TG-3 / TG3-REFINEMENT.md §7 |
| TangleIR: thread echo residue into the **Julia** schema (OCaml `EchoClosed` node landed) | ECHO-TANGLEIR-THREADING.md |
| `echoClose` in WASM backend | tangle-wasm (not yet implemented) |
