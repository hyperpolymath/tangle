# TANGLE & TANGLE-JTV — Implementation Tasks for Sonnet

SPDX-License-Identifier: PMPL-1.0-or-later

**Generated**: 2026-02-12
**By**: Claude Opus 4.6
**For**: Claude Sonnet (implementation phase)

---

## Context

TANGLE is a Turing-complete topological programming language where programs are
isotopy classes of tangles — braided strands in 3D space. TANGLE-JTV extends it
with Julia-the-Viper injection blocks (`add{...}` for total arithmetic,
`harvard{...}` for imperative control).

**Specification is COMPLETE.** All 21 design questions have been answered and
locked. Grammars, formal typing rules, operational semantics, and precedence
are fully specified.

## Reference Files (READ THESE FIRST)

| File | Purpose |
|------|---------|
| `src/tangle.ebnf` | Base TANGLE grammar (ISO/IEC 14977 EBNF) |
| `src/tangle-jtv.ebnf` | Extended grammar with JTV injection blocks |
| `docs/spec/DECISIONS-LOCKED.md` | ALL 44 locked design decisions |
| `docs/spec/FORMAL-SEMANTICS.md` | Typing rules (37+) and evaluation rules (26+) |
| `docs/spec/UNANSWERED-QUESTIONS.md` | All 21 questions resolved (reference) |
| `docs/spec/FEATURE-COVERAGE.md` | Feature → decision mapping |

## Implementation Language

Per hyperpolymath standards:
- **Parser/Compiler**: Rust (preferred) or OCaml
- **ABI definitions**: Idris2 (`src/abi/`)
- **FFI bridge**: Zig (`ffi/zig/`)
- **REPL/CLI**: Rust
- **Test harness**: Rust (cargo test)
- **WASM target**: Rust → wasm32

---

## Task 1: Lexer (Priority: CRITICAL)

**Goal**: Tokenize TANGLE and TANGLE-JTV source files.

**Key requirements**:
- Two comment styles: `# line comment` and `(* block comment *)` (nestable)
- Mode switching: on `add{` enter HV_DATA_MODE, on `harvard{` enter HV_CONTROL_MODE
- Track brace depth for mode exit
- Keywords: `def`, `weave`, `into`, `yield`, `strands`, `compute`, `assert`,
  `match`, `with`, `end`, `let`, `in`, `braid`, `identity`, `true`, `false`,
  `close`, `mirror`, `reverse`, `simplify`, `cap`, `cup`, `add`, `harvard`
- Harvard keywords (only in HV modes): `fn`, `if`, `else`, `while`, `for`,
  `return`, `print`, `module`, `import`, `as`, `reverse`, `then`,
  `@pure`, `@total`
- Operators: `>>`, `==`, `~`, `+`, `-`, `*`, `/`, `.`, `|`, `>`, `<`,
  `^`, `=`, `=>`, `(`, `)`, `[`, `]`, `{`, `}`, `,`, `:`, `!`
- Harvard operators (in HV modes): `&&`, `||`, `!=`, `<=`, `>=`, `%`,
  `+=`, `-=`, `..`
- Literals: integers, floats, strings, hex (`0x...`), binary (`0b...`),
  rationals (`n/m`), complex (`n+mi`)
- Generator tokens: `s` followed by digits (e.g., `s1`, `s23`)

**Acceptance criteria**:
- Tokenizes all examples in README.adoc and README-jtv.adoc
- Correctly nests `(* (* inner *) outer *)`
- Mode switching tested with `add{1 + 2}` and `harvard{fn f() {...}}`
- Error recovery: report position on unexpected character

**Reference**: `src/tangle.ebnf` lines 340-363, `src/tangle-jtv.ebnf` lines 328-336

---

## Task 2: TANGLE Parser (Priority: CRITICAL)

**Goal**: Parse TANGLE source into AST matching the abstract syntax in
FORMAL-SEMANTICS.md §1.

**Key requirements**:
- Recursive descent or PEG parser (not LR — the grammar is LL-friendly)
- Precedence chain (lowest to highest):
  1. `>>` (pipeline, left-assoc)
  2. `==`, `~` (equality/isotopy, non-associative)
  3. `+`, `-` (sum, left-assoc)
  4. `*`, `/` (product, left-assoc)
  5. `.` (vertical composition, left-assoc)
  6. `|` (horizontal tensor, left-assoc)
- Unary prefix: `~e` (twist), `-e` (negation)
- `match ... with ... end` and `let ... in ...` at lowest precedence
- Braid literal: `braid[s1, s2^-1, s1]` with optional `^-1` or `^n` exponent
- Crossing: `(a > b)` and `(a < b)` — fully parenthesized by syntax
- Twist: `(~a)` or `(~(expr))`
- Weave block: `weave strands a:T, b into expr yield strands b, a`

**AST nodes** (from FORMAL-SEMANTICS.md §1.1-1.5):
```
Program { stmts: Vec<Stmt> }
Stmt::Def { name, params, body }
Stmt::Weave { input_strands, body, output_strands }
Stmt::Compute { invariant, expr }
Stmt::Assert { expr }
Expr::Var, Expr::NumLit, Expr::StrLit, Expr::BoolLit
Expr::Identity, Expr::BraidLit { generators }
Expr::Compose(lhs, rhs)        -- .
Expr::Tensor(lhs, rhs)         -- |
Expr::Add(lhs, rhs)            -- +
Expr::Sub(lhs, rhs)            -- -
Expr::Mul(lhs, rhs)            -- *
Expr::Div(lhs, rhs)            -- /
Expr::Pipeline(lhs, rhs)       -- >>
Expr::Eq(lhs, rhs)             -- ==
Expr::Isotopy(lhs, rhs)        -- ~
Expr::Twist(expr)              -- (~e)
Expr::Crossing { a, b, over }  -- (a > b) / (a < b)
Expr::Close(expr), Expr::Mirror(expr), Expr::Reverse(expr)
Expr::Simplify(expr), Expr::Cap(a, b), Expr::Cup(a, b)
Expr::App { func, args }
Expr::Match { scrutinee, arms }
Expr::Let { name, value, body }
Pattern::Identity, Pattern::Cons { gen, rest }
Pattern::Var(name), Pattern::Wildcard
Generator { index: u32, inverse: bool }
```

**Acceptance criteria**:
- Parses all valid TANGLE programs
- Precedence matches FORMAL-SEMANTICS.md §12
- Round-trips: parse → pretty-print → parse gives same AST
- Error messages: name-based with positional hints (D1.15.2)

**Reference**: `src/tangle.ebnf` (entire file), FORMAL-SEMANTICS.md §1

---

## Task 3: TANGLE-JTV Parser Extensions (Priority: HIGH)

**Goal**: Extend parser with `add{...}` and `harvard{...}` blocks.

**Key requirements**:
- `add{ hv_data_expr }` — switches to Harvard data parser
- `harvard{ hv_program }` — switches to Harvard control parser
- Harvard data expression precedence (inside add{}):
  1. `if ... then ... else ...` (conditional, total)
  2. `||` (logical or, left-assoc)
  3. `&&` (logical and, left-assoc)
  4. `==`, `!=`, `<`, `<=`, `>`, `>=` (comparison, non-assoc)
  5. `+`, `-` (additive, left-assoc)
  6. `*`, `/`, `%` (multiplicative, left-assoc)
  7. `-`, `!` (unary prefix)
- Harvard control statements: assignment, if/else, while, for, return, print,
  function declarations (with @pure/@total), modules, imports, reverse blocks
- Harvard data grammar is TOTAL (no loops, no assignments, no recursion)
- Harvard assignments use `hv_data_expr` for the RHS

**AST extensions**:
```
Expr::AddBlock { expr: HvDataExpr }
Stmt::HarvardBlock { program: HvProgram }
HvDataExpr::Num, HvDataExpr::Str, HvDataExpr::Bool, HvDataExpr::Var
HvDataExpr::BinOp { op, lhs, rhs }
HvDataExpr::UnaryOp { op, expr }
HvDataExpr::Conditional { cond, then_branch, else_branch }
HvDataExpr::Call { func, args }
HvDataExpr::ListLit, HvDataExpr::TupleLit
HvStmt::Assignment, HvStmt::If, HvStmt::While, HvStmt::For
HvStmt::Return, HvStmt::Print, HvStmt::FnDecl, HvStmt::Module
HvStmt::Import, HvStmt::ReverseBlock, HvStmt::Block
```

**Acceptance criteria**:
- `add{1 + 2 + 3}` parses as arithmetic (not TANGLE union)
- `harvard{ fn f(x: Int): Int @pure { return x + 1 } }` parses correctly
- Nested braces: `harvard{ if true { if false { return 1 } } }` works
- Mode boundary: `+` inside `add{}` is arithmetic, outside is union

**Reference**: `src/tangle-jtv.ebnf` (entire file), FORMAL-SEMANTICS.md §6

---

## Task 4: Type Checker — TANGLE Core (Priority: HIGH)

**Goal**: Implement typing rules from FORMAL-SEMANTICS.md §3.

**Key requirements**:
- Types: `Word[n]`, `Tangle[A, B]`, `Num`, `Str`, `Bool`
- Two-pass program typing (D1.13):
  - Pass 1: collect all `def` names and infer types into Γ
  - Pass 2: typecheck all statements against complete Γ
- Width inference (D1.21): track max generator index, infer Word[n]
- Auto-widening (D1.8.5): `Word[n] . Word[m] : Word[max(n,m)]`
- Implicit coercion Word → Tangle via realize (D1.1, T-Realize)
- Overloaded `+`: Num + Num → Num, Tangle[I,I] + Tangle[I,I] → Tangle[I,I]
- Pattern typing: P-Identity, P-Cons, P-Var, P-Wildcard (§3.9)
- Width-aware exhaustiveness WARNING (not error) (D1.4)
- Weave blocks: strand context Σ with position tracking (§3.10)
- Self-crossing desugars to twist with warning (D1.19)
- Unified namespace: variables, functions, strand names share one namespace (D1.15.3)
- Shadowing: allowed but warns

**Typing rules to implement** (from §3):
T-Num, T-Str, T-True, T-False, T-Identity, T-Braid, T-Braid-Empty,
T-Var, T-Compose-Word, T-Compose-Tangle, T-Tensor-Word, T-Tensor-Tangle,
T-Pipeline, T-Add-Num, T-Add-Tangle, T-Arith, T-Eq-Word, T-Eq-Num,
T-Eq-Str, T-Isotopy, T-Close-Tangle, T-Close-Word, T-Cap, T-Cup,
T-Mirror-Tangle, T-Mirror-Word, T-Reverse, T-Simplify-Word,
T-Simplify-Tangle, T-Twist-Word, T-Twist-Tangle, T-Match (+ P-*),
T-Weave, T-Cross-Over, T-Cross-Under, T-Twist-Strand, T-Self-Cross,
T-Let, T-Realize, T-Realize-Default, T-Def-Fun, T-Def-Val, T-App,
T-Assert, T-Compute, T-Program

**Acceptance criteria**:
- All typing rules from FORMAL-SEMANTICS.md §3 implemented
- Type errors include name-based messages with strand names (D1.15.2)
- Auto-widening preserves braid group semantics (§11.5)
- Forward references work (two-pass)

**Reference**: FORMAL-SEMANTICS.md §2-§3, DECISIONS-LOCKED.md D1.1-D1.25

---

## Task 5: Type Checker — TANGLE-JTV Extensions (Priority: HIGH)

**Goal**: Implement typing rules from FORMAL-SEMANTICS.md §9.

**Key requirements**:
- Three environments: Γ (TANGLE), Δ (Harvard full), Π ⊆ Δ (pure/total)
- Visibility: TANGLE sees Γ, add{} sees Π, harvard{} sees Δ
- Sequential Π construction: @pure/@total functions added in source order
- Embed/Unembed type bridges (§7.2)
- Harvard data typing (⊢_hd): HD-Num, HD-Str, HD-Bool, HD-Var, HD-App,
  HD-Arith, HD-Compare, HD-And, HD-Or, HD-Not, HD-Neg, HD-If
- Harvard calling TANGLE purity restriction (D2.9):
  - @pure/@total can call non-recursive TANGLE functions only
  - Recursive check: transitive closure of call graph
- Module imports private (D2.11)

**Reference**: FORMAL-SEMANTICS.md §7-§9, DECISIONS-LOCKED.md D2.1-D2.11

---

## Task 6: Evaluator — TANGLE Core (Priority: HIGH)

**Goal**: Implement big-step operational semantics from FORMAL-SEMANTICS.md §4.

**Key requirements**:
- Call-by-value evaluation (D1.13.5)
- Value types: num, str, bool, word (generator sequence), tangle (opaque), halt
- Word composition = concatenation (E-Compose-Word)
- Tensor = index-shifting concatenation (E-Tensor-Word)
- Pattern matching: first-match semantics (E-Match-Hit), halt on failure (E-Match-Fail)
- Simplify: Reidemeister reduction (R1 cancellation, R2 commutativity, R3 braid relation)
- Twist: full twist Δ² = (s₁s₂...s_{n-1})^n (E-Twist-Standalone)
- Close: trace operation (connect matching boundary strands)
- Mirror: invert all generators (sᵢ → sᵢ⁻¹)
- Reverse: reverse and invert generator sequence
- Error propagation: halt short-circuits all binary ops (E-Halt-Left/Right)
- Division by zero → halt
- Recursive functions via closures in ρ (E-App)
- Assert: evaluate to bool, halt on false (E-Assert-Pass/Fail)
- Compute: dispatch to invariant backend (E-Compute)

**Evaluation rules to implement** (from §4):
E-Num, E-Str, E-True, E-False, E-Identity, E-Braid, E-Var,
E-Compose-Word, E-Compose-Tangle, E-Tensor-Word, E-Pipeline,
E-Add-Num, E-Add-Tangle, E-Arith, E-Div-Zero,
E-Eq-Word, E-Eq-Num, E-Eq-Str, E-Isotopy,
E-Close-Word, E-Close-Tangle, E-Mirror-Word, E-Reverse, E-Simplify,
E-Twist-Standalone, E-Match-Hit, E-Match-Fail, E-Let, E-App,
E-Assert-Pass, E-Assert-Fail, E-Compute,
E-Halt-Left, E-Halt-Right

**Acceptance criteria**:
- `braid[s1, s1^-1]` simplifies to `identity`
- Recursive fibonacci on words terminates correctly
- Pattern matching finds first match and binds correctly
- All halt conditions produce messages with source spans

**Reference**: FORMAL-SEMANTICS.md §4, DECISIONS-LOCKED.md D1.13-D1.15

---

## Task 7: Evaluator — TANGLE-JTV Extensions (Priority: MEDIUM)

**Goal**: Implement Harvard block evaluation from FORMAL-SEMANTICS.md §10.

**Key requirements**:
- add{} evaluation: evaluate hv_data_expr in Π context, embed result (E-Add)
- Harvard data evaluation: EHD-Num, EHD-App, EHD-If-True/False
- Unembed: TANGLE values crossing into Harvard (E-Unembed-Num/Str/Bool)
- Harvard control: standard imperative semantics (while, for, assignment)
- Harvard block: extend Δ and Π for subsequent blocks (E-Harvard)
- Purity enforcement at runtime: @pure functions cannot access mutable state

**Reference**: FORMAL-SEMANTICS.md §10, DECISIONS-LOCKED.md D2.1-D2.11

---

## Task 8: Invariant Computation Backend (Priority: MEDIUM)

**Goal**: Implement knot invariant calculators.

**Invariants** (D1.12, D1.16 Tier 2):
- `jones(t)` — Jones polynomial (Kauffman bracket → Jones via writhe normalization)
- `alexander(t)` — Alexander polynomial (Fox calculus or Burau matrix)
- `homfly(t)` — HOMFLY-PT polynomial (skein relation recursion)
- `kauffman(t)` — Kauffman bracket polynomial
- `writhe(t)` — Sum of crossing signs (integer)
- `linking(t)` — Linking number of components

**MVP**: Return Num values (polynomials evaluated at fixed parameters).
**Future**: Return polynomial/symbolic types.

**Architecture**: Plugin system — each invariant is a separate module that
receives a tangle/word value and returns a result. D1.16 specifies these as
Tier 2 (built-in but with swappable backends).

**Reference**: FORMAL-SEMANTICS.md §4.14, DECISIONS-LOCKED.md D1.12, D1.16

---

## Task 9: Standard Library (Priority: LOW)

**Goal**: Implement Tier 3 standard library functions in pure TANGLE.

**Functions** (D1.16, D1.23):
- `length(w)` — count generators in a word
- `width(w)` — return the maximum generator index + 1
- `components(t)` — count connected components
- `is_knot(t)` — single-component check
- `is_link(t)` — multi-component check
- `trefoil`, `figure_eight`, `hopf_link` — named examples

These should be written as TANGLE definitions using pattern matching and
recursion, proving the language is self-hosting for basic operations.

**Reference**: DECISIONS-LOCKED.md D1.16, D1.23

---

## Task 10: REPL and CLI (Priority: LOW)

**Goal**: Interactive REPL and file execution CLI.

**Features**:
- `tanglec <file>.tgl` — parse, typecheck, evaluate
- `tanglec --repl` — interactive mode
- `tanglec --check <file>.tgl` — typecheck only
- `tanglec --ast <file>.tgl` — dump AST
- `tanglec --jtv <file>.tgl` — enable TANGLE-JTV extensions
- Output format: pretty-printed values, invariant results
- Error output: name-based with source spans (D1.15.2)

---

## Task 11: Test Suite (Priority: HIGH — run alongside all tasks)

**Goal**: Comprehensive test coverage.

**Test categories**:
1. **Lexer tests**: all token types, mode switching, comments, error recovery
2. **Parser tests**: every grammar production, precedence edge cases, error messages
3. **Type checker tests**: every typing rule, type errors, width inference, auto-widening
4. **Evaluator tests**: every evaluation rule, recursion, pattern matching, halts
5. **Integration tests**: full programs from README examples
6. **Invariant tests**: known knot invariant values (trefoil Jones = ..., etc.)
7. **Harvard tests**: add{} arithmetic, harvard{} control flow, purity violations

**Known test cases** (from spec):
```tangle
# Auto-widening
assert braid[s1] . braid[s2] == braid[s1, s2]

# Simplification
assert simplify(braid[s1, s1^-1]) == identity

# Pattern matching
def length(w) = match w with
  | identity => 0
  | s1 . rest => 1 + length(rest)
end
assert length(braid[s1, s2, s1]) == 3

# Closure
compute jones(close(braid[s1, s1, s1]))

# Harvard data
assert add{2 + 3} == 5

# Purity
harvard{
  fn double(x: Int): Int @pure {
    return x * 2
  }
}
assert add{double(21)} == 42
```

---

## Execution Order

```
Phase 1 (Foundation):    Task 1 (Lexer) → Task 2 (Parser) → Task 11 (Tests alongside)
Phase 2 (Type Safety):   Task 4 (Type Checker) → Task 6 (Evaluator)
Phase 3 (JTV):           Task 3 (JTV Parser) → Task 5 (JTV Types) → Task 7 (JTV Eval)
Phase 4 (Invariants):    Task 8 (Backend)
Phase 5 (Polish):        Task 9 (Stdlib) → Task 10 (REPL/CLI)
```

Tasks 1-2 and 4-6 are sequential (each depends on the previous).
Tasks 3, 5, 7 can be done after Task 2 (they extend the parser).
Task 8 is independent after Task 6.
Task 11 runs continuously.

---

## Critical Design Constraints (DO NOT VIOLATE)

1. **Word[n] ≠ Tangle[A,B]** — these are different types with implicit coercion (D1.1)
2. **`~` means isotopy** — mathematical equality in FR(T), NOT AST comparison (D1.2)
3. **Auto-widening is a group homomorphism** — B_n embeds into B_{n+1} via stabilization (D1.8.5, §11.5)
4. **`+` on tangles requires closed boundaries** — `Tangle[I,I] + Tangle[I,I]` only (D1.7)
5. **Pattern matching is structural** — on braid word form, NOT up to isotopy (D1.3)
6. **close() has no permutation check** — closing non-identity permutation = link (D1.17)
7. **Twist is context-dependent** — standalone `(~e)` = full twist, weave `(~a)` = single strand (D1.18)
8. **add{} is TOTAL** — no loops, no recursion, no side effects (D2.1)
9. **Harvard @pure can only call non-recursive TANGLE functions** (D2.9)
10. **Three environments: Γ, Δ, Π** — visibility rules are strict (D2.2)

---

## Mathematical Foundation

TANGLE implements computation in the **free strict ribbon category FR(T)**:
- Objects = ordered lists of strand types (boundaries)
- Morphisms = isotopy classes of tangles
- Composition = vertical stacking (`.`)
- Tensor product = horizontal juxtaposition (`|`)
- Braiding = crossings (`>`, `<`)
- Twist = framing (θ_A)
- Duality = cap/cup (evaluation/coevaluation)

Alexander's theorem guarantees: every link is the closure of some braid.
Markov's theorem gives: two braids have isotopic closures iff related by
Markov moves (conjugation + stabilization).

This is real mathematics. The implementation must respect it.
