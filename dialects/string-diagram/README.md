<!--
SPDX-License-Identifier: MPL-2.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
# String Diagram Calculus — Tangle DSL Sketch

**Status:** sketch. Grammar drafted; no parser or implementation yet.

## Domain

Monoidal/braided category string diagrams. Surface syntax for working
with morphisms in a symmetric or braided monoidal category, with
composition (∘), tensor (⊗), identity, and structural morphisms
(associator, unitor, braiding).

## What it supports

- Object and morphism declarations
- Sequential composition (∘, or `then`)
- Tensor product (⊗, or `tensor`)
- Identity morphism on an object
- Braiding / symmetry
- Unit object / unitor
- Associator

## What it does NOT do

- Type checking beyond domain/codomain matching (would need TypeLL for that)
- Categorical coherence proofs (would need Agda/Lean)
- Graphical rendering

## Example

```sd
object A, B, C ;
morphism f : A -> B ;
morphism g : B -> C ;
morphism h : A -> A ;

let gf    = f then g ;            -- sequential composition A -> C
let f_id  = f tensor (id A) ;     -- parallel with identity
let braid = braiding A B ;        -- symmetric structure
```

## Connection to TangleIR

String diagrams generalise tangles: a tangle is a specific string
diagram in a braided monoidal category where objects are "strands" and
morphisms are crossings/caps/cups. KRL's `close`, `tensor`, `mirror`
operations correspond to categorical operations on string diagrams.

## See also

- `grammar-sketch.ebnf` — formal grammar
