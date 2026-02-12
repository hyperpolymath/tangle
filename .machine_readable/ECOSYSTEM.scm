;; SPDX-License-Identifier: PMPL-1.0-or-later
;; ECOSYSTEM.scm - Ecosystem relationships for tangle
;; Media-Type: application/vnd.ecosystem+scm

(ecosystem
  (version "1.0.0")
  (name "tangle")
  (type "specification")
  (purpose "A Turing-complete topological programming language where programs are isotopy classes of tangles")

  (position-in-ecosystem
    "TANGLE is a novel programming language in the hyperpolymath ecosystem. "
    "It bridges knot theory and computation, implementing programs as morphisms "
    "in the free strict ribbon category FR(T). TANGLE-JTV extends the base "
    "language with Julia-the-Viper injection blocks for arithmetic and "
    "imperative control.")

  (related-projects
    (sibling-standard "eclexia" "Another novel programming language with carbon-aware scheduling")
    (dependency "hypatia" "Neurosymbolic CI/CD intelligence and security scanning")
    (dependency "panic-attacker" "Security vulnerability scanning")
    (consumer "gitbot-fleet" "Quality enforcement via bot orchestration")
    (inspiration "julia-the-viper" "Data and control grammar for injection blocks"))

  (what-this-is
    "TANGLE is a topological programming language where computation is braiding. "
    "Data flows along strands that interact at crossings. Programs are isotopy "
    "classes of tangles. The language supports recursive definitions, pattern "
    "matching on braid words, knot invariant computation, and formal verification "
    "of topological equivalence. TANGLE-JTV adds total arithmetic (add{}) and "
    "imperative control (harvard{}) via embedded Julia-the-Viper grammar.")

  (what-this-is-not
    "TANGLE is not a general-purpose language. It is a domain-specific language "
    "for topological computation. It does not replace conventional languages but "
    "offers a novel computational model for knot theory, quantum topology, and "
    "program equivalence reasoning."))
