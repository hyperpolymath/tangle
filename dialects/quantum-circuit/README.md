<!--
SPDX-License-Identifier: CC-BY-SA-4.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
# Quantum Circuit Calculus — Tangle DSL Sketch

**Status:** sketch. Grammar drafted; no parser or implementation yet.

## Domain

Compositional quantum-circuit calculus. Quantum gates map naturally
to Tangle's compositional operations (sequential = gate-in-time,
parallel = gate-in-space via tensor product).

## What it supports

- Standard gates (H, X, Y, Z, CNOT, T, S, Swap)
- Parameterised gates (Rx(θ), Ry(θ), Rz(θ), U3(θ, φ, λ))
- Sequential composition (;)
- Parallel composition (⊗) via tensor
- Measurement operators

## What it does NOT do

- Classical simulation (defer to Yao.jl / Qiskit)
- Hardware-specific calibration
- Noise modelling

## Example

```qc
-- Bell state preparation
let bell = H on 0 ; CNOT (0, 1) ;

-- Grover iteration kernel
let oracle = Z on 1 ;
let diffuser = (H on 0) ⊗ (H on 1) ; Z on 0 ; (H on 0) ⊗ (H on 1) ;
let grover_step = oracle ; diffuser ;
```

## See also

- `grammar-sketch.ebnf` — formal grammar
