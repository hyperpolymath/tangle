# Tangle Dialects — hosted DSL scaffolds

Tangle is a Turing-complete topological programming language. It is NOT
a DSL host by accident — it was designed to support compositional
calculi grounded in knot theory, category theory, and related algebraic
structures.

This directory holds *scaffolds* for DSLs that could be hosted on Tangle.
Each scaffold is an EBNF grammar sketch — evidence that the idea is
coherent and could be built out, not a complete implementation.

## The pattern

When a DSL matures from sketch → alpha implementation, it should follow
the KRL precedent:

1. Start with an EBNF grammar sketch here (`grammar-sketch.ebnf`)
2. Write 1-3 example programs
3. When ready to implement: graduate to its own top-level repo (like `krl/`)
4. Implement parser in Tangle OCaml or sibling language
5. Wire through to TangleIR or its own IR type

Keeping sketches here demonstrates Tangle's claim to be a general
multi-DSL host, not a single-purpose language.

## Current scaffolds

| Dialect | Status | Domain |
|---|---|---|
| [krl](../../krl/) (separate repo) | grade E → D (v0.2 parser 2026-04-12) | Knot resolution — construct, transform, resolve, retrieve |
| [braid-calculus](braid-calculus/) | sketch | Artin braid group Bn calculus |
| [quantum-circuit](quantum-circuit/) | sketch | Quantum circuit compositional calculus |
| [string-diagram](string-diagram/) | sketch | Monoidal/braided category string diagrams |
| [virtual-knot](virtual-knot/) | sketch | Kauffman virtual knot calculus (extends braid-calculus with virtual crossings) |
| [skein-algebra](skein-algebra/) | sketch | Skein algebra calculus (Jones/HOMFLY-PT/Alexander; connects to Skein.jl + KnotTheory.jl) |

## Relationship to KRL

KRL lives at `/var/mnt/eclipse/repos/krl` (sibling top-level repo), NOT
here. This is intentional: KRL has graduated past the scaffold stage and
earned its own repo. These scaffolds represent future candidates that
may graduate similarly.

## Contribution

To propose a new DSL scaffold:

1. Create `dialects/<name>/` with at minimum `grammar-sketch.ebnf`
2. Write `dialects/<name>/README.md` explaining the domain + 1-2 example programs
3. Link from this README
4. Keep it to a sketch — no implementation yet
