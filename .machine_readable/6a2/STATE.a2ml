;; SPDX-License-Identifier: PMPL-1.0-or-later
;; STATE.scm - Project state tracking for tangle
;; Media-Type: application/vnd.state+scm

(define-state tangle
  (metadata
    (version "0.1.0")
    (schema-version "1.0.0")
    (created "2026-02-12")
    (updated "2026-02-12")
    (project "tangle")
    (repo "hyperpolymath/tangle"))

  (project-context
    (name "TANGLE")
    (tagline "A Turing-complete topological programming language")
    (tech-stack
      ("Rust" . "parser, type checker, evaluator, CLI")
      ("Idris2" . "ABI definitions (src/abi/)")
      ("Zig" . "FFI bridge (ffi/zig/)")
      ("EBNF" . "grammar specification (src/)")))

  (current-position
    (phase "specification-complete")
    (overall-completion 35)
    (components
      (("specification" . 100)
       ("grammar-ebnf" . 100)
       ("formal-semantics" . 100)
       ("design-decisions" . 100)
       ("lexer" . 0)
       ("parser" . 0)
       ("type-checker" . 0)
       ("evaluator" . 0)
       ("invariant-backends" . 0)
       ("repl-cli" . 0)
       ("standard-library" . 0)
       ("test-suite" . 0)))
    (working-features
      ("EBNF grammar for TANGLE (ISO/IEC 14977)")
      ("EBNF grammar for TANGLE-JTV with Harvard/add blocks")
      ("44 locked design decisions")
      ("37+ formal typing rules")
      ("26+ operational semantics rules")
      ("Full precedence table")
      ("Metatheory conjectures")))

  (route-to-mvp
    (milestones
      ((name "Specification")
       (status "complete")
       (completion 100)
       (items
         ("Lock all 21 design questions" . done)
         ("Write EBNF grammars" . done)
         ("Write formal semantics" . done)
         ("Cross-verify grammar vs semantics" . done)
         ("Create SONNET-TASKS.md" . done)))
      ((name "Parser")
       (status "not-started")
       (completion 0)
       (items
         ("Implement lexer with mode switching" . todo)
         ("Implement TANGLE parser" . todo)
         ("Implement TANGLE-JTV parser extensions" . todo)
         ("Parser test suite" . todo)))
      ((name "Type System")
       (status "not-started")
       (completion 0)
       (items
         ("Implement TANGLE type checker" . todo)
         ("Implement TANGLE-JTV type extensions" . todo)
         ("Width inference" . todo)
         ("Auto-widening" . todo)
         ("Exhaustiveness warnings" . todo)))
      ((name "Evaluator")
       (status "not-started")
       (completion 0)
       (items
         ("Implement TANGLE evaluator" . todo)
         ("Implement TANGLE-JTV evaluator" . todo)
         ("Reidemeister simplification" . todo)
         ("Pattern matching" . todo)
         ("Error propagation" . todo)))
      ((name "Invariants")
       (status "not-started")
       (completion 0)
       (items
         ("Jones polynomial" . todo)
         ("Alexander polynomial" . todo)
         ("HOMFLY-PT polynomial" . todo)
         ("Writhe computation" . todo)
         ("Linking number" . todo)))))

  (blockers-and-issues
    (critical ())
    (high ())
    (medium
      ("Need to choose parser library (nom, pest, lalrpop, or hand-written)"))
    (low ()))

  (critical-next-actions
    (immediate
      "Begin lexer implementation (Task 1 in SONNET-TASKS.md)"
      "Set up Rust project structure with cargo")
    (this-week
      "Complete lexer with mode switching"
      "Begin TANGLE parser (recursive descent)")
    (this-month
      "Complete parser + type checker"
      "Begin evaluator"))

  (session-history
    (("2026-02-12" "specification-phase"
      "Locked all 21 design decisions. Wrote formal semantics (37 typing rules, "
      "26 eval rules). Fixed grammar mismatches. Created SONNET-TASKS.md. "
      "Updated all documentation."))))

;; Helper functions
(define (get-completion-percentage state)
  (current-position 'overall-completion state))

(define (get-blockers state severity)
  (blockers-and-issues severity state))

(define (get-milestone state name)
  (find (lambda (m) (equal? (car m) name))
        (route-to-mvp 'milestones state)))
