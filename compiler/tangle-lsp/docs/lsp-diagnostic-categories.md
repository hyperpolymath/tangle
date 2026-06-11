<!--
SPDX-License-Identifier: MPL-2.0
Owner: Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
# `tangle-lsp` diagnostic categories

This file documents the four categories `tangle-lsp` diagnostics fall
into. Together with the updated assumption `A-TG-9.1` in the repo-root
`ASSUMPTIONS.md`, they formalise the **TG-9 Option B** resolution from
issue #28.

The bigger picture: obligation **TG-9** in `PROOF-NARRATIVE.md` says
every LSP diagnostic should correspond to a failure of the `HasType`
typing judgment in `proofs/Tangle.lean`. The 2026-06-01 audit
(issue #28) found that 6 of 7 diagnostic call sites have no `HasType`
counterpart. There were two options for closing the gap:

- **Option A** — route every diagnostic through `compiler/lib/typecheck.ml`
  via an OCaml↔Rust FFI. Higher engineering cost; the most principled.
- **Option B** — accept LSP-only diagnostics, document the categories,
  and tag each call site with which category it belongs to. Lower cost;
  what this file describes.

Option B keeps the diagnostics where they help users while making the
"this is not a `HasType` failure" status explicit. Option A is queued
in #28 for follow-up.

## The categories

Each is denoted in the `Diagnostic.source` field as
`tangle-lsp[CATEGORY]`.

### `PARSE_ERROR`

Grammar-level rejection. Corresponds to the parser refusing malformed
input. Not a `HasType` failure but a legitimate language-level
rejection.

Examples:
- Unbalanced parentheses, brackets, braces.

Source location markers in `backend.rs`:
- `tangle-lsp[PARSE_ERROR]` — 3 sites (paren / bracket / brace).

### `MISSPELLING_HINT`

IDE-convenience hint. The user typed something close to a keyword.
No spec counterpart — the spec doesn't know about misspellings.

Examples:
- `comput` instead of `compute`.
- `asert` instead of `assert`.

Source location markers in `backend.rs`:
- `tangle-lsp[MISSPELLING_HINT]` — 1 site.

### `STRUCTURAL_HINT`

LSP-only structural heuristic. Tracks block nesting, weave-block
balance, etc. without a corresponding `HasType` rule. The `weave`
keyword in particular is part of a proposed v0.2 dialect not yet in
the core typing relation.

Examples:
- Unclosed `weave` block.
- Suspicious block nesting depth.

Source location markers in `backend.rs`:
- `tangle-lsp[STRUCTURAL_HINT]` — 2 sites.

### `NAME_HINT`

Possibly-undefined-reference hint. Implemented as `HINT` severity (the
softest LSP level) because identifiers may resolve via future imports
the lexical pass can't see. The OCaml typechecker raises a hard
exception on unbound variables; this LSP hint is the softer IDE-side
analogue.

Source location markers in `backend.rs`:
- `tangle-lsp[NAME_HINT]` — 1 site.

## How to add a new diagnostic

1. Pick a category. If none fits, propose a new category in a PR that
   updates this file **and** `ASSUMPTIONS.md` A-TG-9.1.
2. Tag the `Diagnostic.source` field with `tangle-lsp[CATEGORY]`.
3. Add a `// [CATEGORY]` comment immediately above the
   `self.diagnostics.push(...)` call so reviewers can audit the
   category set at-a-glance.

## How this discharges TG-9 (Option B)

`A-TG-9.1` previously said _"`tangle-lsp` reuses `compiler/lib/
typecheck.ml` as the diagnostic engine (no LSP-only diagnostics)"_.
That was false; the audit (#28) confirmed it.

Option B updates `A-TG-9.1` to:

> `tangle-lsp` emits diagnostics in **four documented categories**
> (`PARSE_ERROR`, `MISSPELLING_HINT`, `STRUCTURAL_HINT`, `NAME_HINT`);
> only `PARSE_ERROR` corresponds to a grammar-level rejection. The
> other three are LSP-only by design, documented in
> `compiler/tangle-lsp/docs/lsp-diagnostic-categories.md`.

This is a discipline shift: instead of pretending the LSP refines the
spec, we acknowledge the gap and document each step out. Option A
(real refinement via FFI to `typecheck.ml`) remains the long-term
target and is tracked in #28.

## CI gate (proposed; queued for follow-up)

A grep-based CI check could enforce:

```bash
grep -rE 'self\.diagnostics\.push' compiler/tangle-lsp/src/ |
  grep -v 'tangle-lsp\[(PARSE_ERROR|MISSPELLING_HINT|STRUCTURAL_HINT|NAME_HINT)\]'
```

Any unmatched diagnostic line means an untagged emission site. This
would be a 1d follow-up PR.

## Cross-references

- `PROOF-NARRATIVE.md` §3 TG-9
- `ASSUMPTIONS.md` A-TG-9.1 (updated by this PR)
- Issue #28 — TG-9 audit findings + Options A/B
- `compiler/tangle-lsp/src/backend.rs` — 7 call sites, all now tagged
