<!--
SPDX-License-Identifier: CC-BY-SA-4.0
Owner: Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
# Tangle proofs

Mechanised metatheory for the Tangle core type system, in Lean 4.

- [`Tangle.lean`](Tangle.lean) — the proofs (the repo's **build oracle**).
- [`lean-toolchain`](lean-toolchain) — the pinned Lean version
  (`leanprover/lean4:v4.14.0`). Single source of truth for the toolchain.
- [`bootstrap-lean.sh`](bootstrap-lean.sh) — installs that toolchain.

## What is proven

`Tangle.lean` mechanises type safety for the core language, all under Lean's
kernel with **no `sorry`/`axiom`/`admit`** (enforced by CI):

- **Progress, Preservation, Determinism, Type Safety** — for the let-free
  fragment *and* the echo-types fragment.
- **Echo types** (structured loss): `Ty.echo`, `echoClose`/`lower`/`residue`,
  with the residue-recovery / non-injectivity capstones. See the
  `§ECHO-TYPES` section of `Tangle.lean` and
  [`../PROOF-NARRATIVE.md`](../PROOF-NARRATIVE.md) §2.5.
- **Decidability** (TG-2): `infer ≡ HasType`, type uniqueness, and a
  `Decidable (HasType [] e τ)` instance.

## Building / verifying

```sh
# 1. Install the pinned toolchain (idempotent).
./proofs/bootstrap-lean.sh

# 2. Put lean on PATH for this shell.
eval "$(./proofs/bootstrap-lean.sh --print-path)"

# 3. Verify — 0 errors means the proofs check.
cd proofs && lean Tangle.lean
```

### Why `bootstrap-lean.sh` exists

`elan` (the Lean toolchain manager) resolves toolchains from
`release.lean-lang.org`, which is **not on the network allowlist** in
sandboxed environments such as Claude Code on the web. GitHub release assets
*are* reachable, so when the normal install path is blocked the script fetches
the pinned toolchain directly from `github.com`. On an open network (e.g.
GitHub Actions runners) it uses the normal `elan` path. Either way it reads the
version from `lean-toolchain`, so it stays correct when the pin is bumped.

CI runs the same oracle in [`.github/workflows/lean-proofs.yml`](../.github/workflows/lean-proofs.yml):
`lean Tangle.lean` must report 0 errors and the file must contain no
`sorry`/`axiom`/`admit`/`Admitted` outside comments.
