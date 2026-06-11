<!--
SPDX-License-Identifier: MPL-2.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
<!-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk> -->

# TOPOLOGY.md — tangle

## Purpose

TANGLE is a Turing-complete topological programming language where programs are represented as tangles—isotopy classes of braided strands in 3D space. Computation proceeds via strand braiding with interactions at crossings, leveraging deep connections between topology, algebra, and computation. Knot invariants (Jones polynomial) enable novel reasoning about program equivalence.

## Module Map

```
tangle/
├── src/                 # Core language implementation
│   ├── parser/         # Tangle source parser
│   ├── topology/       # Topological representation
│   ├── invariants/     # Knot invariant computation
│   ├── evaluator/      # Execution engine
│   └── backend/        # Code generation
├── examples/           # Example Tangle programs
├── tests/              # Language conformance tests
└── docs/               # Language specification
```

## Data Flow

```
[Tangle Source] ──► [Parser] ──► [Topological Representation] ──► [Invariant Extraction]
                                           ↓
                                    [Braiding Evaluation] ──► [Computation Result]
```

## Key Concepts

- **Strands**: Data-carrying topological objects
- **Crossings**: Interaction points where strands compute
- **Braiding**: Control flow via strand arrangement
- **Knot Invariants**: Jones polynomial for program analysis
- **Isotopy Classes**: Equivalent programs have same invariants
