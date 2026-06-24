<!--
SPDX-License-Identifier: CC-BY-SA-4.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
<!-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk> -->

# Virtual Knot Calculus — Tangle DSL Sketch

**Status:** sketch. Grammar drafted; no parser or implementation yet.

## Domain

Virtual knot calculus, following Kauffman (1999). Virtual knots extend
classical braid/knot theory by adding a second, purely formal crossing
type — the *virtual crossing* — which arises when a knot diagram on a
higher-genus surface Σ_g is projected to the plane. Virtual crossings
are NOT real crossings; they are placeholders recording where strands
pass each other in the diagram without interacting.

This DSL is strictly an extension of `braid-calculus/`. Every
braid-calculus program is valid virtual-knot source; the converse
is false — virtual crossings have no classical counterpart.

## Key concepts

### Classical vs virtual crossings

| Generator | Symbol | Meaning |
|---|---|---|
| `sigma n` | σₙ | Positive classical crossing at strand n |
| `sigma_inv n` | σₙ⁻¹ | Negative classical crossing at strand n |
| `virtual n` | νₙ | Virtual crossing at strand n (unsigned) |

Virtual crossings obey the *virtual Reidemeister moves* (vR1–vR3) but
are immune to the classical R3 move when mixed with classical crossings.
The *forbidden move* — letting a classical crossing pass a virtual one
via an R3-like move — is explicitly banned; including it collapses
virtual knot theory to classical.

### Detour move

Any arc that passes through only virtual crossings can be rerouted
freely (the *detour move*). This is virtual knot theory's analogue of
the classical isotopy invariance under planar isotopy.

### Gauss codes

Virtual knots are conveniently specified by their Gauss codes — an
alternative to braid words. The Gauss code records, for each crossing,
whether the strand is over or under, and the sign. Virtual crossings
appear in the Gauss code as unsigned entries. This DSL supports both
notations.

## What it supports

- Classical generators σᵢ, σᵢ⁻¹ with integer strand index
- Virtual generators νᵢ (unsigned) at strand index
- Braid-word multiplication (`*`)
- Inverse of a braid word
- Closure to a virtual knot diagram (`close`)
- Gauss code literals for direct specification
- Predicate: `is_classical?` (tests whether a virtual knot is equivalent
  to a classical one — decidable for small Gauss codes)

## What it does NOT do

- Perform the forbidden move (explicitly excluded — doing so collapses
  the theory)
- Classical knot invariants directly (hand off to KRL → KnotTheory.jl)
- Slice genus computation (open problem for virtual knots)
- Arrow calculus (Kauffman's signed arrow variant — future extension)

## Example

```vk
-- The virtual trefoil: a Gauss code unrealisable on S²
-- Gauss code: O1+ U2+ O2+ U1+ O3+ U3+  (virtual at positions 2,3)
let vtrefoil = gauss_code [O 1 +, U 2 +, virtual 2, U 1 +, O 3 +, U 3 +] ;

-- A classical knot expressed as a virtual braid word
let trefoil_braid = sigma 1 * sigma 1 * sigma 1 ;

-- Mixed classical-virtual braid (the forbidden move is NOT applied here)
let mixed = sigma 1 * virtual 2 * sigma_inv 1 ;

-- Test whether a virtual knot is equivalent to a classical knot
is_classical? vtrefoil ;           -- expected: false
is_classical? (close trefoil_braid) ;  -- expected: true

-- Closure of a virtual braid
let closed_mixed = close mixed ;
```

## Connection to TangleIR

In TangleIR terms, virtual crossings can be represented as
`CrossingIR` nodes with `sign = 0` (a value unused by classical
crossings, which use ±1). The lowering rule is:

    virtual_gen(n)    → CrossingIR(id, 0, (1,2,3,4))   -- sign = 0

The detour move corresponds to a rewrite on the `crossings` vector
that removes consecutive virtual crossings on the same arc pair. A
future `simplify_virtual_ir` function would implement this.

## Relationship to other dialects

- **braid-calculus**: this dialect extends it — every braid-calculus program
  parses as valid virtual-knot source
- **KRL**: classical virtual knots that pass `is_classical?` can be
  exported to KRL for invariant computation via `as krl`
- **string-diagram**: virtual knots are morphisms in a *free braided
  monoidal category without the Yang-Baxter equation on virtual crossings*

## See also

- `grammar-sketch.ebnf` — formal grammar
- Kauffman, L.H. (1999). *Virtual Knot Theory*. European J. Combinatorics, 20(7), 663–690.
- `../../krl/` — knot resolution language (classical knots only)
- `../braid-calculus/` — classical Artin braid group (this dialect extends it)
