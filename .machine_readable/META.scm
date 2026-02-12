;; SPDX-License-Identifier: PMPL-1.0-or-later
;; META.scm - Architectural decisions and project meta-information
;; Media-Type: application/meta+scheme

(define-meta tangle
  (version "1.0.0")

  (architecture-decisions
    ((adr-001 accepted "2026-02-12"
      "Need to establish core type system for topological computation"
      "Two-level type system: Word[n] (matchable braid data) and Tangle[A,B] (morphisms)"
      "Enables pattern matching on braid structure while preserving isotopy equivalence. "
      "Implicit coercion from Word to Tangle via realize function.")
    (adr-002 accepted "2026-02-12"
      "Need to achieve Turing completeness in a topological language"
      "Recursion on definitions + pattern matching on braid words (identity=nil, g.w=cons)"
      "Words serve as inductively defined data, enabling unbounded computation. "
      "Braid words are isomorphic to cons-lists over generators.")
    (adr-003 accepted "2026-02-12"
      "Need arithmetic and imperative control alongside topology"
      "Julia-the-Viper injection blocks: add{} (total data) and harvard{} (imperative)"
      "Delimited syntax avoids ambiguity (+ means union in TANGLE, addition in add{}). "
      "Three environments: Gamma (TANGLE), Delta (Harvard full), Pi (pure subset).")
    (adr-004 accepted "2026-02-12"
      "Need to handle two kinds of equality"
      "== for structural equality on words, ~ for isotopy equivalence on tangles"
      "~ has fixed mathematical meaning (equality in free ribbon category FR(T)). "
      "Cannot be redefined or approximated without soundness loss.")
    (adr-005 accepted "2026-02-12"
      "Need a concrete strategy for simplification and invariant computation"
      "Three-tier architecture: Tier 1 primitives, Tier 2 invariants (pluggable), Tier 3 stdlib"
      "Simplify uses greedy Reidemeister reduction. Invariants are backend-pluggable. "
      "Standard library written in pure TANGLE."))

  (development-practices
    (code-style
      "Implementation in Rust (parser, type checker, evaluator). "
      "ABI definitions in Idris2 with Zig FFI bridge. "
      "Grammars in ISO/IEC 14977 EBNF.")
    (security
      "All commits signed. "
      "Hypatia neurosymbolic scanning enabled. "
      "panic-attack vulnerability scanning.")
    (testing
      "Comprehensive test suite alongside implementation. "
      "Every typing rule and evaluation rule has corresponding test cases.")
    (versioning
      "Semantic versioning. "
      "Specification version tracked separately from implementation.")
    (documentation
      "README.adoc for overview. "
      "docs/spec/ for formal specification. "
      "SONNET-TASKS.md for implementation plan.")
    (branching
      "Main branch protected. "
      "Feature branches for implementation work."))

  (design-rationale
    (why-topological
      "Topological programming offers novel reasoning about program equivalence. "
      "Knot invariants provide sound approximations to program equality. "
      "The mathematical foundation (ribbon categories) is well-studied.")
    (why-two-types
      "Words are intensional (matchable), tangles are extensional (isotopy). "
      "Conflating them breaks either pattern matching or equivalence reasoning.")
    (why-jtv
      "Pure topology lacks convenient data manipulation. "
      "Delimited injection blocks preserve TANGLE's topological purity while "
      "enabling arithmetic and imperative logic where needed.")))
