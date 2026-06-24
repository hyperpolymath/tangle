<!--
SPDX-License-Identifier: CC-BY-SA-4.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
<!-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk> -->

# Skein Algebra — Tangle DSL Sketch

**Status:** sketch. Grammar drafted; no parser or implementation yet.

## Domain

Skein algebras and skein modules. Given a 3-manifold M and a
commutative ring R with distinguished elements, the *skein module*
Sk(M; R) is the free R-module on isotopy classes of framed links in M,
quotiented by the local skein relations. When M = Σ × [0,1] for a
surface Σ, this acquires an algebra structure (via stacking) and is
called the *skein algebra* of Σ.

This is why `Skein.jl` is named what it is: it is the persistence and
indexing layer for the knot-invariant stack, and knot polynomials
arise precisely from evaluating skein algebra elements.

## The three classical skein relations

| Name | Relation | Polynomial family |
|---|---|---|
| HOMFLY-PT | P(L+) = a⁻¹ P(L₀) + z P(L-)  | HOMFLY-PT (2-variable) |
| Kauffman bracket | ⟨L+⟩ = A ⟨L0⟩ + A⁻¹ ⟨L∞⟩ | Jones (via trace) |
| Conway–Alexander | ∇(L+) − ∇(L-) = z ∇(L₀) | Alexander (1-variable) |

Each defines a different skein module. This DSL is parametrised: the
`using skein` declaration chooses which relations are in scope.

## What it supports

- Parameter declarations (the ring variables: `A`, `q`, `z`, etc.)
- Generator declarations (named framed link generators)
- Skein relation declarations (local rewriting rules)
- Linear combination expressions over the parameter ring
- Algebra product (stacking, written `*`)
- Predefined skein styles: `homflypt`, `jones`, `alexander`
- `evaluate` — apply a representation to produce a polynomial value
- Named element lookup against Skein.jl database (`lookup`)

## What it does NOT do

- Categorical coherence proofs (those need Idris2/Agda/Lean)
- Computation of the skein algebra of an arbitrary 3-manifold (only
  link complements and handlebodies are in scope for now)
- Quantum group module structure (future extension via TypeLL)

## Example

```sk
-- Work in the Jones skein of S³ with parameter A
using jones ;
parameter A ;

-- The Jones skein relation (Kauffman bracket normalised form)
-- Already built-in when "using jones" is declared.

-- Define the trefoil as a generator (matches Skein.jl name "3_1")
generator trefoil : framed_link ;
relation trefoil = L+ ;   -- shorthand: trefoil_braid closed

-- Compute the Jones polynomial: evaluate the generator in the
-- standard Burau / Temperley-Lieb representation
evaluate (jones_rep, trefoil) ;

-- Linear combination: HOMFLY-PT of (2 * unknot - trefoil)
using homflypt ;
parameter a, z ;
let combo = 2 * unknot - trefoil ;
evaluate (homflypt_rep, combo) ;

-- Temperley-Lieb generators (quotient of Hecke algebra)
-- e₁ e₂ e₁ = e₁  (TL relation)
generator e1, e2 : framed_link ;
relation (e1 * e2 * e1) = (delta * e1) ;   -- delta = -A² - A⁻²
relation (e1 * e1) = (delta * e1) ;

-- Lookup a named knot's skein polynomial from Skein.jl
lookup "3_1" jones_rep ;
lookup "8_18" homflypt_rep ;
```

## Connection to TangleIR

Skein algebra elements lower to TangleIR as follows:

- A *framed link generator* lowers to a closed `TangleIR` (via `close_tangle`)
- A *linear combination* stays in the skein layer — it is a formal sum
  of TangleIR values with ring-element coefficients, not a single IR
- A *relation* is a rewrite rule on TangleIR that mirrors Reidemeister
  simplification but is parametrised by the ring variables
- `evaluate(rep, e)` calls into KnotTheory.jl for the actual polynomial

The three skein styles (`jones`, `homflypt`, `alexander`) correspond
to the three polynomial families already computed by KnotTheory.jl.

## Relationship to other dialects

- **KRL**: KRL builds tangles (open diagrams); skein-algebra works with
  *closed* links (elements of the skein module). KRL's `close` operation
  is the bridge — `close` a KRL tangle to get a skein element.
- **string-diagram**: the Temperley-Lieb generators e₁…eₙ₋₁ are
  morphisms in a pivotal monoidal category — a special case of
  string-diagram calculus with the skein relation as the extra axiom.
- **Skein.jl**: the persistence layer. `lookup` queries it;
  `evaluate` writes computed polynomials back to it.
- **KnotTheory.jl**: the computation layer. `evaluate(jones_rep, e)`
  routes to `jones_polynomial` in KnotTheory.jl.

## See also

- `grammar-sketch.ebnf` — formal grammar
- Przytycki, J.H. & Traczyk, P. (1987). *Invariants of links of Conway type*.
  Kobe J. Math. 4, 115–139. (HOMFLY-PT relation)
- Kauffman, L.H. (1987). *State models and the Jones polynomial*.
  Topology 26(3), 395–407. (Kauffman bracket)
- `../../KRLAdapter.jl/` — adapter that lowers KRL → TangleIR (same IR target)
- `../string-diagram/` — monoidal category calculus (TL algebra is a special case)
- `../../krl/` — knot resolution language (constructs the TangleIR inputs)
