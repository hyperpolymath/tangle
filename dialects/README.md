<!--
SPDX-License-Identifier: CC-BY-SA-4.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
# Tangle Dialects — hosted DSL scaffolds

Tangle is a Turing-complete topological programming language. It is NOT
a DSL host by accident — it was designed to support compositional
calculi grounded in knot theory, category theory, and related algebraic
structures.

This directory holds *scaffolds* for DSLs that could be hosted on Tangle.
Each scaffold is an EBNF grammar sketch — evidence that the idea is
coherent and could be built out, not a complete implementation.

## The pattern

When a DSL matures from sketch → alpha implementation:

1. Start with an EBNF grammar sketch here (`grammar-sketch.ebnf`)
2. Write 1-3 example programs
3. When ready to implement, decide whether it stays in-tree or graduates to
   its own repository
4. Implement the parser in Tangle's OCaml front end or a sibling language
5. Define its IR type

No dialect has yet made this journey, so there is no precedent to follow —
these are all still at step 1.

These sketches set out what a general multi-DSL host *would* cover. They do not
yet evidence the claim: nothing here is implemented, and nothing is currently
built on Tangle. Implementing one of them end to end is what would turn the
claim into evidence.

## Current scaffolds

| Dialect | Status | Domain |
|---|---|---|
| [braid-calculus](braid-calculus/) | sketch | Artin braid group Bn calculus |
| [quantum-circuit](quantum-circuit/) | sketch | Quantum circuit compositional calculus |
| [string-diagram](string-diagram/) | sketch | Monoidal/braided category string diagrams |
| [virtual-knot](virtual-knot/) | sketch | Kauffman virtual knot calculus (extends braid-calculus with virtual crossings) |
| [skein-algebra](skein-algebra/) | sketch | Skein algebra calculus (Jones/HOMFLY-PT/Alexander; connects to Skein.jl + KnotTheory.jl) |

## Relationship to KRL

**KRL is not a Tangle dialect and never was.** It was previously listed here as
one that had "graduated" to its own repository; that was part of a wider
conflation of the two projects, corrected in `README.adoc` and in the erratum to
`AFFIRMATION.adoc`.

KRL is the resolution language for
[QuandleDB](https://github.com/hyperpolymath/quandledb), developed jointly with
it, and lives at [hyperpolymath/krl](https://github.com/hyperpolymath/krl). It
does not compile to, lower into, or otherwise depend on Tangle. The two share a
subject matter, not an architecture.

The scaffolds listed above are Tangle's own dialects.

## Contribution

To propose a new DSL scaffold:

1. Create `dialects/<name>/` with at minimum `grammar-sketch.ebnf`
2. Write `dialects/<name>/README.md` explaining the domain + 1-2 example programs
3. Link from this README
4. Keep it to a sketch — no implementation yet
