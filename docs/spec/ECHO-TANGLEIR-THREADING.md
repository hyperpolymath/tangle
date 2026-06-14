<!--
SPDX-License-Identifier: MPL-2.0
Owner: Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
# Echo residue threading into TangleIR — cross-repo contract

**Status:** design / coordination contract (2026-06-14). Authored in `tangle`
(the semantics owner). The TangleIR type change and the QuandleDB consumer
change live in **`KRLAdapter.jl`** (TangleIR definition + adapters) and
**`quandledb`** — both Julia, outside this session's scope — so this file is
the *contract* those repos implement, not the implementation.

## 1. Why threading the residue matters

Tangle's `close : Word[n] → Word[0]` is the canonical **lossy** map: it
collapses a braid to the identity, discarding the word. Echo types
(`proofs/Tangle.lean` §ECHO-TYPES; `compiler/lib/typecheck.ml`) make that loss
recoverable — `echoClose b` retains the braid as a **residue**, and
`residue (echoClose b) ⟶ b` (`echo_residue_recovers`).

The seam with QuandleDB is exact, not incidental:

> A **quandle presentation is an invariant of the knot**, and the knot is the
> **closure of the braid**. `close` is precisely the braid→knot step. So the
> residue retained by `echoClose` — the *pre-closure braid* — is exactly the
> object `quandle_presentation(ir::TangleIR)::QuandlePresentation` derives the
> quandle from.

**A note on what the Lean model proves.** The mechanized `close`/`lower`
(`proofs/Tangle.lean`) is a *type-level* collapse: every braid reduces to the
single `Word[0]` value `.identity` (a collapse to one point), **not** to a knot
diagram. So `echo_distinguishes_collapsed` proves only that distinct braids
share that identity result while their residues stay distinct — it is **not**
the knot-theoretic statement "distinct braids close to the same knot diagram."
That geometric closure is a separate notion, modelled by the compositional PD
compiler (`compositional.ml`) and `FORMAL-SEMANTICS.md` (`close : Tangle[I,I]`),
and is **not** mechanized here. What the proofs *do* establish — residue
recovery (`echo_residue_recovers`) and type-safe round-trip
(`echo_roundtrip_typed`) — is sufficient to justify threading the residue braid
to QuandleDB for **provenance** (which braid produced a given closed diagram),
even though the knot-level conflation itself is an external knot-theory fact.

## 2. The contract per layer

| Layer | Repo | Responsibility |
|---|---|---|
| Semantics | `tangle` (this repo) | Defines echo types + residue semantics. `residue (echoClose b) = b`; `lower (echoClose b) = identity`. Mechanised in `proofs/Tangle.lean`; checked in `typecheck.ml` (`TEcho`/`TProd`, rules `[T-Echo-Close]`/`[T-Lower]`/`[T-Residue]`). |
| Interchange | `KRLAdapter.jl` | TangleIR represents an echo-closed term **carrying the residue braid alongside the closed result** (see §3). A plain `close` node is unchanged (no residue). |
| Consumer | `quandledb` | `quandle_presentation` reads the residue braid of an echo-closed node to compute the quandle (the pre-closure braid determines the knot). Plain-`close` behaviour unchanged. |

## 3. Proposed TangleIR representation (for KRLAdapter.jl)

Mirror the Lean `echoVal (residue, result)` shape. Two equivalent options;
recommend (a):

* **(a) Residue-carrying closure node.** Add an IR node
  `EchoClosed(residue::BraidWord, result::ClosedDiagram)` — the closed diagram
  plus the braid it came from. `lower`/`residue` IR projections read `.result`
  / `.residue`. This keeps the closed diagram identical to the plain-`close`
  output (so existing consumers are unaffected) while exposing the braid.
* **(b) Residue as closure metadata.** Keep the existing closure node and attach
  the pre-closure braid as an optional metadata field
  (`residue::Union{BraidWord,Nothing}`). Lighter, but makes the residue
  optional rather than type-guaranteed — weaker than the Lean guarantee.

Products (`Ty.prod` / `pair`/`fst`/`snd`) are the residue carrier for the
binary lossy ops (`echoAdd`/`echoEq`): their residue is the **pair of operands**.
If TangleIR needs to represent those, add a `Pair(a, b)` IR node with `fst`/`snd`
projections. (For QuandleDB specifically, only the `echoClose` residue is
knot-relevant; `echoAdd`/`echoEq` residues are scalar provenance.)

## 4. Consumer contract (for quandledb)

```
quandle_presentation(ir::TangleIR) =
    case ir of
      EchoClosed(residue, _result) -> quandle_of_braid(residue)   # use the braid
      Close(diagram)               -> quandle_of_diagram(diagram) # unchanged
      ...
```

The invariant to preserve: for any braid `b`,
`quandle_presentation(EchoClosed(b, close(b)))` ≡
`quandle_presentation(Close(close(b)))` whenever the closed diagram alone
suffices — the residue path must agree with the diagram path on the quandle,
and additionally retains `b` for provenance.

**This quandle invariant is an unproven knot-theoretic obligation** that
QuandleDB must establish itself: it is *not* mechanized in Lean nor checked in
OCaml (the word `quandle` appears in neither). The Lean theorem
`echo_roundtrip_typed` only guarantees that the residue/result projections are
**well-typed** (`residue : Word[n]`, `lower : Word[0]`); it says nothing about
quandle equality, and `lower`/`residue` project *different* components (they
diverge by design — `echo_distinguishes_collapsed` — they do not "agree"). The
mechanized backing for threading is narrower than quandle agreement: residue
recovery plus type-safe round-trip.

## 5. Scope / coordination

- **No TangleIR or QuandleDB code is changed by this document.** Those are
  KRLAdapter.jl/quandledb (Julia) changes, to be made by the quandle session.
- **An OCaml-side `EchoClosed` node now exists** in tangle's own compositional
  PD compiler (`compiler/lib/compositional.ml`), reachable via `tanglec
  --compile-pd`. It mirrors option (a) and emits the residue braid, but it is a
  *different* IR from the Julia TangleIR this contract specifies — it is the
  producer-side reference, not the interchange schema. The Julia TangleIR /
  QuandleDB consumer work remains pending.
- This contract is additive and conservative: plain `close` is untouched, so
  existing TangleIR producers/consumers keep working; echo-closed nodes are new.
- Cross-reference: `proofs/Tangle.lean` (`echo_residue_recovers`,
  `echo_distinguishes_collapsed`, `echo_roundtrip_typed`),
  `.machine_readable/6a2/ECOSYSTEM.a2ml` (the echo↔quandle seam),
  and `quandledb`'s `quandle_presentation`.
