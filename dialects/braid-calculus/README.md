# Braid Calculus — Tangle DSL Sketch

**Status:** sketch. Grammar drafted; no parser or implementation yet.

## Domain

A direct surface language for working in Artin braid groups Bₙ.
Distinct from KRL by being narrower: braids only, no closure, no knot
classification. The quotient map Bₙ → Knots is explicit via a `close`
primitive that hands off to KRL.

## What it supports

- Generators σᵢ (braid crossings) with exponent
- Inverses σᵢ⁻¹
- Multiplication of braid words
- Conjugation
- Markov moves (for knot invariant construction)

## What it does NOT do

- Closure to knots (that's KRL's job — use `as krl.close(b)`)
- Invariant computation (that's KnotTheory.jl's job)
- Persistence (that's Skein.jl's job)

## Example

```braid
let s1 = sigma 1
let s2 = sigma 2
let trefoil_braid = s1 * s1 * s1
let trefoil_conj = s2 * trefoil_braid * inverse s2
is_markov_equivalent(trefoil_braid, trefoil_conj)
```

## See also

- `grammar-sketch.ebnf` — formal grammar
- `../../../krl/` — knot resolution language (consumes braid words via `close`)
