<!--
SPDX-License-Identifier: CC-BY-SA-4.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
<!-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk> -->

# Changelog — Tangle

Tangle is a Turing-complete topological programming language. This file
tracks notable changes to the compiler, stdlib, tooling, and WASM runtime.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### TG-8 (template): virtual-knot dialect as a conservative extension of core

- **`compiler/lib/dialect_vk.ml`** models the virtual-knot dialect (the virtual
  braid monoid VBₙ ⊃ Bₙ — braids plus involutive virtual crossings vᵢ) as a
  *conservative extension* of the core braid language: a real crossing or a
  virtual crossing, with the core (real) fragment embedding via `embed` and every
  decision on it DELEGATED to `Braid_equiv` (TG-7). Conservativity therefore
  holds by construction — the dialect cannot change core typing/semantics.
- **`compiler/test/tg8/tg8_conservativity.ml`** (2311 assertions) verifies:
  faithful embedding (`project ∘ embed = id`); the dialect decides core terms
  exactly as the core procedure; permutation/writhe invariants agree on the real
  fragment; proper extension (a virtual crossing is a genuinely-new non-real
  element, `vᵢ vᵢ = ε`); and an honest partial-decision frontier (irreducible
  mixed virtual content → `None`, never guessed).
- Built as a separate module — no core-AST or Lean-oracle edits (avoids the
  `Warning 8` exhaustiveness cascade). Surface-syntax integration, the other four
  dialects, and a Lean conservativity proof are the next rungs (PROOF-NEEDS TG-8).

### TG-6 (differential rung): execute generated wasm and check it preserves semantics

- **`compiler/tangle-wasm/tests/differential.rs`** adds `wasmi` (a pure-Rust wasm
  interpreter) as a dev-dependency and EXECUTES the generated wasm modules,
  supplying reference host primitives (`tangle_rt.alloc_strands` initialises the
  identity strand array; `tangle_rt.swap_strands` swaps two cells). It then
  checks the executed strand permutation equals an independent in-Rust reference
  model — over the trefoil, non-commuting pairs (`s1 s2` ≠ `s2 s1`),
  braid-relation pairs (`s1 s2 s1` = `s2 s1 s2`), and a 5-strand weave. Run via
  `cargo test` in `compiler/tangle-wasm`.
- This validates the wasm **codegen** against the braid permutation semantics
  (catches wrong crossing indices, call order, strand counts, or a
  non-instantiable module). It is not a cross-binary diff against `eval.ml`, and
  the Markov-move helpers are not yet exercised; full source↔wasm bisimulation
  remains research-grade (PROOF-NEEDS.md TG-6). The shipped backend keeps no
  runtime dependency (`wasmi` is dev-only).

### TG-7 (non-semantic rung): out-of-band braid-group equivalence

- **`compiler/lib/braid_equiv.ml`** decides braid-GROUP equivalence via Dehornoy
  handle reduction (`equiv`, `is_trivial`, plus `writhe`/`permutation`
  invariants). It is **out-of-band**: the language's `==` on braids (`eval.ml`
  and the Lean `Step.eqBraids` rule) is left as list equality — no semantics
  change. Routing `==` through it remains an owner decision (PROOF-NEEDS.md TG-7).
- Tested in `compiler/test/tg7/tg7_braid_equiv.ml` (2220 assertions): the
  defining relations (commutation, braid relation, cancellation), 400
  randomly-constructed equivalent pairs (relation-preserving moves give ground
  truth; writhe/permutation invariants guard the generator), and
  invariant-distinguished negatives. Correctness is by-testing; a mechanised
  Garside/Dehornoy proof is the research-grade rung.

### TG-5 LANDED + readiness map for TG-6/7/8

- **TG-5 LANDED**: `compiler/test/tg5/tg5_invariants.ml` (189 assertions, in
  `dune runtest`) — a structural-invariant property test for the compositional
  PD lowering (`compiler/lib/compositional.ml`). compositional sits below the
  type layer, so "the rewriter preserves types" is realised as preserving the
  lowering's structural invariants + the echo residue-recovery property:
  `OpenWord` unit-expanded; `ClosedDiagram` closed / `components=[]` / source
  unit-expanded / `|crossings| = |source| = unit-count`; `EchoClosed` residue
  **verbatim** (`echoClose(s1^3)` keeps `[s1^3]` while the diagram is the
  3-crossing unit closure), `expand(residue) = diagram word`, and echo-diagram
  pdv1-identical to plain `close`; plus error-path and crossing-count pins.
  Asserts only invariants the lowering guarantees (no arc-balance/planarity).
- **Readiness map (TG-6/7/8)**: a parallel assessment found each remaining
  obligation is blocked on a *prerequisite*, not effort — recorded in
  PROOF-NEEDS.md. **TG-8** blocked: the five dialects are prose READMEs with no
  implementation. **TG-7** needs an owner decision: braid-group equivalence
  changes the observable semantics of `==` on braids in both the evaluator and
  the Lean `Step` relation. **TG-6** blocked: no wasm runtime is wired in, so
  even differential testing has nothing to execute.

### TG-3 LANDED: OCaml type checker refines the Lean spec (translation validation)

Proof obligation TG-3 — "`compiler/lib/typecheck.ml` refines the mechanised
`HasType` spec" — is discharged at the translation-validation level. Full
write-up, closure argument, type translation, divergence catalogue and
extra-core feature list: `proofs/TG3-REFINEMENT.md`.

- **Reduction.** TG-2 proves Lean `infer ≡ HasType`, so TG-3 reduces to "OCaml
  `infer_expr` ≡ Lean `infer` on the shared core fragment".
- **Closure proof.** The core fragment (literals, let/var, compose/tensor/
  pipeline, add, eq, and the echo/product ops — excluding `close` and the whole
  Tangle layer) is closed under `infer_expr`: it never produces a `TTangle`,
  under a strengthened *entire-type-tree* induction hypothesis (a Tangle must not
  hide inside a `TProd`/`TEcho` and leak out via `fst`/`snd`/`lower`/`residue`).
- **Machine-checked half.** `proofs/TG3Differential.lean` — 496 obligations
  `infer [] <term> = <infer_expr result> := by decide`, **generated from the
  OCaml checker** by `compiler/test/tg3/tg3_emit.ml` and kernel-verified by
  Lean's *proven* `infer`. New `proofs/check-tg3-differential.sh` (builds the
  Tangle `.olean`, checks the obligations); wired into `lean-proofs.yml`.
- **OCaml half.** `compiler/test/tg3/` runs `tg3_emit --check` under
  `dune runtest`: 1008 assertions over a 490-term corpus — closure invariant,
  curated type pins, named→de Bruijn translation (incl. `let`-shadowing), and the
  OCaml side of every divergence.
- **Divergence catalogue (complete).** **D1** `close` (OCaml `Tangle[I,I]` vs
  Lean `Word[0]` — the sole core boundary gateway) and its downstream vectors
  D1b `pipeline(close,close)`, D1c `compose(braid,close)` (OCaml rejects), D1d
  `add(close,close)`; **D2** `bool == bool` (OCaml accepts as extra-core, Lean
  rejects). Both sides of each are pinned.
- **Honest boundary.** Translation validation over a broad corpus plus a
  structural argument — not a single Lean theorem quantifying over all OCaml
  runs (that would require reflecting `typecheck.ml`). Refinement is OCaml→Lean.

### Proof documentation catch-up (TG-1, TG-2, echo-types design note)

Both TG-1 and TG-2 were already fully proved in `proofs/Tangle.lean` but not
reflected in PROOF-NEEDS.md / PROOF-NARRATIVE.md. This entry documents the
retrospective correction.

- **TG-1 LANDED**: `weakening` + `subst_preserves` + all four theorems (Progress,
  Preservation, Determinism, TypeSafety) extended to `var`/`let`. The "let-free
  fragment" caveat in PROOF-NARRATIVE.md is retired.
- **TG-2 LANDED**: `infer` (structural recursion over all 26 HasType rules),
  `infer_sound`, `infer_complete`, `infer_iff_hasType`, `type_unique`,
  `decidableHasType` — all in `proofs/Tangle.lean` §TG-2.
- **echo-types grade semiring design note** (§2.8 of PROOF-NARRATIVE.md): the
  experimental ℕ∪{∞} min-plus grade semiring in `hyperpolymath/echo-types`
  (`f7a965f`) uses the combining/monadic direction — the same direction as
  Tangle's `echoAdd`/`echoEq`. The splitting/comonadic direction requires a full
  graded adjunction and is under experimental investigation (firewalled). No
  Tangle design change required now.

### Echo-threading: EchoClosed compositional IR node

The compositional PD compiler (`compositional.ml`) now threads the echo
residue through the IR. This is the OCaml-side implementation of the
cross-repo contract at `docs/spec/ECHO-TANGLEIR-THREADING.md`.

- **`EchoClose of expr`** added to the `expr` type; `echo_close` builder.
- **`EchoClosed { residue; diagram }`** added to `compiled` — carries
  the pre-closure braid word alongside the closed planar diagram
  (identical to the plain-`Close` output so existing consumers are
  unaffected).
- **`compile_echo_and_send_to_skein`** — residue-carrying Skein hook
  that emits `echo_closed_payload` with both `residue_blob`
  (`"s1,s2^-1,s1"` format) and the PDv1 blob.
- **`word_of_compiled (EchoClosed _)`** returns the residue braid —
  the pre-closure word is recoverable at the IR level.
- Parser adapter (`of_ast_expr`) maps `Ast.EchoClose` to the
  compositional `EchoClose`, reachable via the new `--compile-pd` CLI
  flag (see below).
- Validated against `EchoProvenance.agda` (echoes distinguish
  tag-differing records) and `EchoResidue.agda` (`no-section` theorem —
  the residue must be threaded, not recomputed after lowering).

Downstream: Julia `KRLAdapter.jl` and `quandledb` implement the
consumer side per §3–4 of the contract doc.

### Audit follow-up (correctness + coverage hardening)

A multi-agent adversarial audit of the echo/TG work surfaced fixes,
applied here:

- **Residue is now verbatim.** `compile (EchoClose b)` retains the
  *unexpanded* pre-closure braid as the residue (via a new
  `source_word_of_expr`), so `echoClose(braid[s1^3])` keeps residue
  `s1^3` rather than the unit-expanded `s1,s1,s1`. This matches the Lean
  `echo_residue_recovers` theorem and the eval interpreter (which were
  already exponent-faithful); only the planar diagram is unit-expanded.
- **`Eq` typecheck tightened to the spec.** Word equality now requires
  equal width (`Word[n] == Word[m]` ⇒ `n = m`), matching the Lean
  `tEqWord` rule; unequal-width comparisons are now rejected instead of
  silently evaluating to `false`. `Bool == Bool` is retained as an
  explicit extra-core convenience (used by `examples/braids_as_data`).
- **`--compile-pd <file>` CLI flag** wires the compositional/Skein path
  (previously test-only) into the shipped binary: each closed/echo-closed
  `def` is lowered to its PDv1 blob, with the residue blob for `echoClose`.
- **Test coverage for the surface echo pipeline.** Added direct
  typecheck (`test_typecheck.ml`) and eval (`test_eval.ml`) tests pinning
  the residue/result ordering of all 8 echo/product forms against the
  Lean `Step` rules — previously only parse/pretty round-trip was tested.
- Adds direct typecheck/eval coverage for the 8 echo forms (suite was 557
  before this batch; see the running total below).

### TG-9 LANDED: LSP diagnostics delegated to the compiler

`tangle-lsp` previously computed diagnostics from a hand-rolled lexical
scan that diverged from the real parser/typechecker, emitting LSP-only
false positives (wrong comment syntax, delimiters counted inside string
literals, "unclosed block" on every multi-def file, params flagged as
undefined). None corresponded to a `HasType` failure — violating TG-9.

- **`compiler/lib/check.ml`** (`check_source`) is now the single
  diagnostic source: parse-with-recovery + `Typecheck.check_program`.
- **`tanglec --check <file>`** exposes it as `SEVERITY⇥LINE⇥COL⇥MESSAGE`.
- **`tangle-lsp`** shells out to `tanglec --check` and forwards exactly
  those diagnostics; the lexical scan now only extracts definitions /
  references for navigation. With the compiler absent it emits nothing
  (`∅ ⊆ HasType failures`). The subset relation holds **by construction**.
- Built-in operations now appear in LSP completion (reusing the
  previously diagnostic-only `TANGLE_BUILTINS` list).
- Tests: `compiler/test/test_check.ml` and `tangle-lsp` Rust unit tests
  (`parse_check_line`, navigation authors no diagnostics, gated
  end-to-end delegation against a real `tanglec`).

### Type-error diagnostics carry source lines

- `definition` gains a `def_line` field (set from the parser's
  `$startpos`); `Typecheck.diagnostic` gains `diag_line`. Definition-scoped
  type errors now point at the `def` line instead of the file top, so the
  LSP highlights the right line.
- Removed a duplicate diagnostic: `check_program` pass 2 no longer
  re-checks definitions (pass 1b already does), so one type error yields
  one diagnostic. Statement-level errors (assert/compute/weave) remain
  unlocated for now.
- Test-suite total: **597/597** pass.

### Echo types OCaml pipeline (PR #45 + #46)

### Added
- Echo/product type system fully landed in the OCaml pipeline (PR #45 + #46):
  - `ast.ml`: 8 new `expr` constructors (`echoClose`, `lower`, `residue`, `pair`, `fst`, `snd`, `echoAdd`, `echoEq`); 2 new `ty` constructors (`TProd`, `TEcho`)
  - `typecheck.ml`: 8 new `infer_expr` rules mirroring Lean `HasType` (`T-Echo-Close`, `T-Lower`, `T-Residue`, `T-Pair`, `T-Fst`, `T-Snd`, `T-Echo-Add`, `T-Echo-Eq`); `pp_ty` made `rec`
  - `eval.ml`: `VEcho`/`VPair` value forms; 8 new `eval_expr` arms; `pp_value` made `rec`
  - `lexer.mll` + `parser.mly` + `token.ml`: keyword tokens and grammar productions for all 8 surface forms (`echoClose(e)`, `lower(e)`, `residue(e)`, `pair(a,b)`, `fst(e)`, `snd(e)`, `echoAdd(a,b)`, `echoEq(a,b)`)
  - `pretty.ml`: pretty-printers for all 8 forms; round-trips through parser
- TG-4 (pretty-print/parse round-trip) discharged: `test_roundtrip.ml` extended with 8 new echo/product corpus entries (16 round-trip runs) covering every echo/product constructor (PR #46)
- `docs/spec/ECHO-TANGLEIR-THREADING.md`: cross-repo contract for how echo residue threads through TangleIR to QuandleDB (PR #45)
- Compositional PD compiler API (`compositional.ml` / `.mli`):
  `expr`, `planar_diagram`, `compiled`, `skein_payload` types
- `pdv1_blob_of_pd`: canonical text serialisation format
  (`pdv1|x=a,b,c,d,s;...|c=arc,arc;...`)
- `compile_and_send_to_skein`: direct Tangle → Skein integration entry point
- Playground scaffold in `playground/` (placeholder PWA + 2 example programs)
- README rewrite introducing KRL architecture + visual map (docs/krl_map.html)
- CRG v2 READINESS.md (grade C)

### Changed
- Tangle composition typecheck: correct permutation application
- WASM: fixed composed braid locals and helper expectations
- Zig ABI layer modernized

### Fixed
- `compiler/bin/main.ml` debug token printer: add 8 missing echo keyword token arms (Warning 8 exhaustiveness, PR #46)
- `compiler/lib/typecheck.ml` `strand_type_of_ty`: add `TProd`/`TEcho` arms (Warning 8 exhaustiveness, PR #46)
- EXPLAINME.adoc section heading quotes

## Earlier commits (no versions tagged)

### UX infrastructure
- Justfile with doctor, tour, help-me, assail recipes
- UX Manifesto deployment
- Agent instructions methodology layer

### Formal proofs
- Lean 4 proofs: progress, preservation, determinism
- TOPOLOGY.md documentation added

### RSR compliance
- A2ML migration of state files
- SPDX headers, license migration to MPL-2.0
- stapeln.toml container definition
- Standard workflow deployment (codeql, hypatia, scorecard, etc.)

### Language development
- Compiler (OCaml/dune): parser, typechecker, evaluator, pretty-printer, REPL
- WASM backend (`tangle-wasm/`)
- LSP server (`tangle-lsp/`)
- Stdlib (`lib/stdlib.tangle`)
