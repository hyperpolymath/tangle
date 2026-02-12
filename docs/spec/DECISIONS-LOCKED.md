# TANGLE & TANGLE-JTV Design Decisions (LOCKED 2026-02-12)

This document records all locked design decisions for:
1. **TANGLE** - The base topological programming language
2. **TANGLE-JTV** - TANGLE extended with Julia-the-Viper injection blocks

---

# PART 1: TANGLE (Base Language)

## Core Type System

### D1.1: Word vs Tangle Split
**Decision**: Braid literals construct `Word[n]` (data), tangles are morphisms.

**Type Rules**:
```
braid[σ₁,...,σₖ] : Word[n]   where n = max strand index + 1

Coercion (implicit):
  If w : Word[n] appears where Tangle[𝐀,𝐁] expected,
  insert realize_𝐀(w) : Tangle[𝐀, π_w(𝐀)]
```

**Rationale**:
- Pattern matching requires data values (Words)
- Equational reasoning requires morphisms (Tangles)
- Separation prevents matching breaking extensional equality

**Example**:
```tangle
def w = braid[s1, s2, s1]         # w : Word[2]

match w with                       # Pattern match on Word (intensional)
  | s1 . rest => ...
end

weave strands a, b into w yield a, b  # w coerced to Tangle (extensional)
```

---

### D1.2: Two Equality Operators
**Decision**: `~` for isotopy, `==` for definitional equality.

**Semantics**:
```
~ : Tangle[𝐀,𝐁] × Tangle[𝐀,𝐁] → Bool    (isotopy in FR(T))
== : Word[n] × Word[n] → Bool            (structural)
== : Num × Num → Bool                     (numeric)
== : Str × Str → Bool                     (string)
```

**Critical**: `~` has **fixed mathematical meaning** (equality in strict ribbon category FR(T)).
- Backends provide checking procedures (strict/lax)
- MVP may only support syntactic equality
- Do NOT redefine `~` as AST equality

**Example**:
```tangle
assert trefoil ~ mirror(trefoil)    # Isotopy check (mathematical truth)
assert braid[s1] == braid[s1]       # Definitional equality (structural)
```

---

### D1.3: Recursion on Words
**Decision**: TANGLE definitions CAN recurse via pattern matching on Words.

**Semantics**: Call-by-value for non-Tangle values.

**Example**:
```tangle
def length(w) = match w with
  | identity => 0
  | s1 . rest => 1 + length(rest)    # Recursive - legal
end
```

**Rationale**: This enables Turing-completeness. Words behave like lists (identity/cons), match provides branching, recursion gives unbounded iteration.

---

### D1.3.5: Pattern Variable Scoping (NEW)
**Decision**: Pattern variables are lexically scoped to their match arm.

**Scoping Rules**:
```
Scope: Pattern variables visible ONLY in the arm body (RHS of =>)
Shadowing: YES - pattern variables shadow outer definitions
Namespace: Unified with global definitions (per D1.15.3)
```

**Example**:
```tangle
def rest = braid[s2]           # Global definition

def f(w) = match w with
  | s1 . rest => rest . rest   # Pattern 'rest' shadows global (warning emitted)
                                # Uses matched tail, not global braid[s2]
end
```

**Rationale**: Lexical scoping prevents accidental capture. Shadowing is natural for pattern matching (matches functional language conventions).

---

### D1.4: Match Exhaustiveness
**Decision**: Runtime error if no arm matches (MVP). Width-aware warnings.

**Semantics**:
- Match evaluates arms in order
- If no pattern matches, halt with `MatchFailure(span)` (per D1.15)
- **Width-aware warning**: When width is statically known, compiler warns about missing generator arms
- Wildcard `_` or variable pattern silences the warning

**Example**:
```tangle
def process(w : Word[3]) = match w with
  | identity => 0
  | s1 . rest => 1
  | s2 . rest => 2
  # Warning: match on Word[3] missing arm for s3
end

def safe(w : Word[3]) = match w with
  | identity => 0
  | s1 . rest => 1
  | _ => 2              # No warning - wildcard catches s2, s3
end
```

**Rules**:
- Known-width types: warn about missing generators up to width
- Unknown-width types: no warning (programmer takes responsibility)
- Warning only, not error — compilation proceeds

---

### D1.4.5: Let Binding Scoping (NEW)
**Decision**: Let bindings are lexically scoped to the `in` clause.

**Syntax**: `let identifier = expr in expr`

**Scoping Rules**:
```
Scope: Binding visible ONLY in the 'in' clause
Shadowing: YES - let bindings can shadow outer definitions
Nesting: Nested lets allowed (inner shadows outer)
```

**Type Rule**:
```
Γ ⊢ e₁ : S₁
Γ, x : S₁ ⊢ e₂ : S₂
────────────────────────
Γ ⊢ let x = e₁ in e₂ : S₂
```

**Example**:
```tangle
def x = braid[s1]              # Global

def f(y) =
  let x = braid[s2] in         # Shadows global
  let z = x . y in             # x refers to braid[s2]
  z . z                         # Result uses shadowed x

# After f completes, global x still braid[s1]
```

**Rationale**: Lexical scoping prevents variable leakage. Shadowing allows temporary rebinding without name conflicts.

---

### D1.5: TANGLE Literals
**Decision**: Direct `Num` and `Str` literals (no wrapping needed).

**Grammar**: `literal = number | string`

**Types**: `Num`, `Str` are first-class TANGLE sorts (alongside `Word[n]`, `Tangle[𝐀,𝐁]`).

**Example**:
```tangle
def copies = 5              # Num literal
def name = "trefoil"        # Str literal
```

---

### D1.6: Numeric Arithmetic in TANGLE
**Decision**: TANGLE has `+`, `-`, `*`, `/` for `Num`, with **`+` overloaded by sort**.

**Overloading Rule**:
```
+ : Num × Num → Num                              (numeric addition)
+ : Tangle[I,I] × Tangle[I,I] → Tangle[I,I]    (disjoint union)
(mixed types) → TYPE ERROR
```

**Examples**:
```tangle
def length(w) = match w with
  | identity => 0
  | s1 . rest => 1 + length(rest)    # + is Num addition
end

def knots = close(trefoil) + close(unknot)  # + is tangle union
def bad = 5 + close(trefoil)                # TYPE ERROR
```

**Rationale**: Makes Word recursion practical while preserving mathematical `+` on closed tangles.

---

### D1.6.5: Numeric Encoding of Braids (NEW)
**Decision**: Braids do NOT represent numbers; `Num` is a separate type.

**Turing Completeness**:
- **Achieved via**: Recursion + pattern matching + Num arithmetic (D1.3, D1.6)
- **NOT via**: Encoding naturals as braid words

**Three Distinct Equalities**:
```
Word equality (==):        braid[s1, s1] == braid[s1, s1]  ✓
                           braid[s1, s1] == braid[s2, s2]  ✗  (different generators)

Topological equality (~):  braid[s1, s1^-1] ~ identity    ✓  (isotopy)

Numeric equality (==):     5 == 5  ✓  (separate Num type)
```

**No Automatic Encoding**:
```tangle
# These are DIFFERENT types:
def word = braid[s1, s1]   # Word[2]
def num = 2                 # Num

# NO automatic conversion:
assert word == num          # TYPE ERROR

# To count generators, use explicit length function:
def length(w) = match w with
  | identity => 0
  | s1 . rest => 1 + length(rest)
end

assert length(braid[s1, s1]) == 2  ✓  (Word → Num via function)
```

**Rationale**:
- Avoids three-way ambiguity (word/topological/numeric equality)
- Braids retain topological meaning (not numeric encoding)
- Turing-completeness via Num + recursion (cleaner proof)

---

### D1.7: Tangle `+` Type Restriction
**Decision**: Hard error - `+` on tangles ONLY for `Tangle[I,I]`.

**Rule**:
```tangle
def valid = close(t1) + close(t2)  ✓ Both Tangle[I,I]
def invalid = tangle1 + tangle2    ✗ ERROR if not closed
```

**Rationale**: Mathematical correctness (disjoint union defined only for closed diagrams).

---

### D1.8: Operator Disambiguation

**`.` operator**: Context-sensitive parsing.
```
Pattern:    s1 . rest     (cons operator)
Expression: f . g         (vertical composition)
```

**`identity`**: Type-directed disambiguation.
```
As pattern:    identity         (matches empty Word)
As expression: identity : Word[n]         (polymorphic empty word)
As expression: identity : Tangle[𝐀,𝐀]    (identity morphism)
```

---

### D1.8.5: Word/Tangle Composition with Different Indices (NEW)
**Decision**: Auto-widen Words to maximum index on composition (MVP).

**Index Inference**:
```
braid[s1]     : Word[2]   (strands 1,2 needed)
braid[s3]     : Word[4]   (strands 1,2,3,4 needed)
braid[s1, s5] : Word[6]   (strands 1,2,3,4,5,6 needed)
```

**Composition Rule**:
```
Word[n] . Word[m] : Word[max(n,m)]   (auto-widen to larger width)

Example:
  braid[s1] . braid[s3] : Word[max(2,4)] = Word[4]
```

**Coercion to Tangle**:
```
realize_𝐀(w : Word[n]) : Tangle[𝐀, π_w(𝐀)]
  where |𝐀| = n (boundary length must match word width)

If |𝐀| > n, implicit widening:
  realize_𝐀(w) treats w as if w | identity^(|𝐀|-n)
  (word w on first n strands, identity on remaining strands)
```

**Example**:
```tangle
def a = braid[s1]       # Word[2]
def b = braid[s3]       # Word[4]
def c = a . b           # Word[4] (auto-widen a to 4 strands)

weave strands p:Q, q:Q, r:Q, s:Q into
  a                     # realize_[Q,Q,Q,Q](braid[s1])
                        # Treats as: (s1 crossing) | (identity on r,s)
yield strands p, q, r, s
```

**Rationale**:
- Matches mathematical convention (n-strand braid embeds in m-strand for m≥n)
- Flexible (no explicit widening annotations needed)
- Sound (topologically correct widening)

**Alternative (rejected for MVP)**: Explicit index type error (require manual widening)

---

## Weave Blocks

### D1.9: Weave Expression Restrictions
**Decision**: Any TANGLE expression that typechecks to `Tangle[𝐀,𝐁]`.

**Rules**:
```tangle
weave strands a:A, b:B, c:C into
  <any TANGLE expr : Tangle[𝐀,𝐁]>    # ✓ Allowed
yield strands ...
```

**Allowed**:
- Crossings, compositions, tensors
- Calls to TANGLE functions
- Pattern matching (if yields Tangle)
- Let bindings
- Any combinators

**Not allowed** (type error):
- Harvard blocks (statement-level, not expressions)
- add{...} if it returns Num/Str (not Tangle)

**Rationale**: Maximizes expressiveness, allows factoring and combinators.

---

### D1.10: Heterogeneous Typed Boundaries
**Decision**: Boundaries can have **different types** (NO "all strands same type" restriction).

**Rules**:
```tangle
weave strands a:A, b:B, c:C into    # 𝐀 = [A,B,C]
  (a > b)                            # Tangle[[A,B,C], [B,A,C]]
yield strands b:B, a:A, c:C
```

**Crossing Typing**:
- `(x > y)` where x:Tx, y:Ty denotes β_{Tx,Ty}
- Swaps positions in boundary: `[A,B]` → `[B,A]`
- Types are reordered, not changed

**Missing Type Annotations**: Default to `Strand` or `Any` (MVP).

---

### D1.11: Yield Boundary Matching
**Decision**: Yield must **exactly match** final boundary order (MVP).

**Rule**:
```tangle
weave strands a:A, b:B into
  (a > b)                    # Final boundary: [B,A]
yield strands b:B, a:A       # ✓ Exact match required

yield strands a:A, b:B       # ✗ ERROR - order mismatch
```

**Future v2**: Allow arbitrary yield order, insert permutation braid.

---

## Computation

### D1.12: Invariant Computation
**Decision**: Built-in reserved names + FFI/plugin registry.

**Reserved Invariants**: `jones`, `alexander`, `homfly`, `kauffman`, `writhe`, `linking`

**Semantics**:
```tangle
compute jones(trefoil)    # Statement with effect (print/return value)
```

**Type Requirement**: Expression must typecheck to invariant's domain (usually `Tangle[I,I]`).

**Extensibility**: User can register custom invariants via FFI/plugin system.

---

## Program Structure

### D1.13: Top-Level Definition Order
**Decision**: Two-pass for TANGLE definitions (forward references allowed).

**Pass 1**: Collect all `def` names into Γ
**Pass 2**: Execute `compute`, `assert` in source order

**Example**:
```tangle
compute jones(trefoil)        # ✓ OK - trefoil in Γ from pass 1
def trefoil = braid[s1,s1,s1]
assert trefoil ~ trefoil      # ✓ OK - forward refs allowed
```

**Rationale**: Good UX, matches functional language conventions.

---

### D1.13.5: Termination and Evaluation Strategy (NEW)
**Decision**: Non-termination allowed (Turing-complete); call-by-value evaluation.

**Non-Termination**:
```tangle
def loop(x) = loop(x)      # Legal (non-terminating)

def collatz(n) = match n with
  | identity => identity
  | s1 . rest => collatz(computed_value(rest))  # Non-structural recursion allowed
end
```

**Allowed**: Recursion on **computed values** (not just sub-terms).

**Consequence for Assertions**:
```tangle
assert simplify(some_program) ~ identity
```

- If `some_program` doesn't terminate, assertion checking **may diverge**
- `assert` is **undecidable in general** (halting problem)
- MVP: Runtime check only (no static verification)

**Evaluation Strategy**: **Call-by-value** (strict evaluation)
```
Arguments evaluated before function call
Matches are evaluated strictly (no lazy patterns)
Let bindings are strict: let x = e in ... evaluates e before binding
```

**Rationale**:
- **Turing-completeness**: Requires unrestricted recursion (D1.3)
- **Simplicity**: Call-by-value is simpler to reason about and implement
- **Trade-off**: Accept undecidable assertions for computational power

**Note**: This creates a deliberate tension with decidable topological verification. The language prioritizes expressiveness over complete static checking.

---

## Error Handling

### D1.14: Identity Width
**Decision**: `identity` is `Word[0]` (the empty braid word, equivalent to `braid[]`).

**Semantics**:
- `identity` alone has type `Word[0]`
- Auto-widening (D1.8.5) handles composition: `identity . braid[s3]` → `Word[4]`
- The empty braid word IS the identity element in every braid group B_n after stabilization
- Pattern matching: `identity` pattern matches the empty word

**Type Rule**:
```
identity : Word[0]
identity . w : Word[max(0, n)] = Word[n]    (via D1.8.5)
```

**Implication**: No polymorphism needed in the type system for MVP. Width inference suffices.

---

### D1.15: Error Handling Philosophy
**Decision**: Halt/panic for MVP. Future review for richer error model.

**Error Classification**:
```
Parse errors        → Compile time (never reach runtime)
Type errors         → Compile time (never reach runtime)
MatchFailure        → Runtime halt with diagnostic
Assertion failure   → Runtime halt with diagnostic
Non-termination     → Programmer's responsibility (no timeout/detection)
```

**Runtime Error Format**:
```
MatchFailure at line N: no pattern matched value <repr>
Assertion failed at line N: <lhs> ~ <rhs>
```

**Rationale**: Keeps TANGLE pure and simple. Error recovery belongs in `harvard{...}` blocks where `if/else` can guard calls. Fail-fast is correct for quantum circuit verification.

**Future review**: Exceptions, Result types, or `try/catch` may be considered post-MVP.

---

### D1.15.1: Assertion Decidability
**Decision**: Assertions are runtime-only expressions (MVP).

**Semantics**:
- `assert P` evaluates `P`; if true, continues; if false, halts (per D1.15)
- If `P` diverges (calls non-terminating function), assertion check diverges
- No static verification, no theorem prover for MVP

**Consistency**: Follows from D1.13.5 (non-termination allowed) and D1.15 (halt on error).

**Future review**: Split into `assert` (runtime) vs `prove` (static verification). `prove` would require a static verifier — significant implementation effort but valuable for quantum circuit verification.

---

### D1.15.2: Error Messages — Name-Based
**Decision**: Error messages reference strand names with positional hints.

**Format**:
```
Error at line 3: yield boundary mismatch
  Expected: strands a:Q, b:R
  Got:      strands b:R, a:Q
  (strand 'a' is in position 2, expected position 1)
```

**Rationale**: Users write strand names, not type lists. Messages should speak the user's language. Compiler tracks strand names through weave body.

---

### D1.15.3: Name Conflict Resolution
**Decision**: Unified namespace, innermost binding wins, shadowing emits warning.

**Binding Priority** (innermost wins):
```
pattern variable > strand name > let binding > global def
```

**Warning**:
```
Warning: strand name 'a' shadows global definition 'a' at line N
```

**Consistency**: Same rule as D1.3.5 (pattern variables) and D1.4.5 (let bindings). All three binding forms follow standard lexical scoping.

---

## Operations

### D1.16: Primitives and Library Tiering
**Decision**: Three-tier split for TANGLE operations.

**Tier 1 — Language Primitives** (in compiler, have typing rules):
- `identity` — Word[0], type-directed (D1.14)
- `braid[...]` literals — fundamental data constructor
- `(a > b)`, `(a < b)` crossings — strand interaction
- `(~x)` twist — topological operation (D1.18)
- `.` `|` `+` `>>` — composition operators
- `close` — Tangle[A,A] → Tangle[I,I] (D1.17)
- `cap`, `cup` — create/destroy strand pairs
- `mirror`, `reverse` — structural transforms
- `simplify` — applies Reidemeister moves (needs internal representation access)

**Tier 2 — Built-in Invariants** (compiler knows names, delegates to backends):
- `jones`, `alexander`, `homfly`, `kauffman`, `writhe`, `linking`
- Reserved names (D1.12) with FFI/plugin backends
- Compiler type-checks, runtime dispatches to invariant engine

**Tier 3 — Standard Library** (pure TANGLE definitions, shipped with language):
- `length`, `concat`, `braid_repeat`, and similar utilities
- Defined via pattern matching + recursion
- Shipped as `.tangle` files alongside the compiler

---

### D1.17: Close Operation Validation
**Decision**: `close` works on any matching-boundary tangle. No permutation check.

**Type Rule**:
```
close : Tangle[A,A] → Tangle[I,I]
```

**Semantics**: Connects output strand i to input strand i regardless of permutation. Closing a braid that permutes strands gives a **link** (possibly multi-component), not necessarily a knot.

**Example**:
```tangle
def c = braid[s1] . braid[s3]   # Permutation (1 2)(3 4), NOT identity
def link = close(c)               # ✓ Legal — produces a 2-component link
```

**Rationale**: Standard knot theory (Alexander's theorem). Any braid closure is a well-defined link. `close` always succeeds on any `Word[n]` since input and output both have n strands.

---

### D1.18: Twist Operator Types
**Decision**: Context-dependent granularity.

**Standalone** `(~t)` — all-strand twist (categorical θ_A):
```
(~t) ≜ t . twist_n     where n = width of t
Type: Word[n] → Word[n]   or   Tangle[A,B] → Tangle[A,B]
```
Composes expression with the all-strand twist tangle. No new semantics — just sugar for composition with a Tier 1 primitive.

**Weave context** `(~a)` — single named strand:
```
Γ; strands ⊢ a : T
────────────────────
Γ; strands ⊢ (~a) : Tangle[[T], [T]]
```
Twists only the named strand.

**Resolution**: Compiler checks "am I inside a weave block with a strand named `x`?" If yes, single-strand twist. If no, treat `x` as expression and apply all-strand twist.

---

### D1.19: Self-Crossings in Weave
**Decision**: Allow but warn, desugar to `(~a)`.

**Semantics**:
```tangle
weave strands a:Q into
  (a > a)              # ✓ Legal — equivalent to (~a)
                        # Warning: self-crossing (a > a) is equivalent to (~a)
yield strands a:Q
```

**Compiler**: Desugars `(a > a)` to `(~a)` during lowering. Warning suggests canonical form.

---

### D1.20: Pipeline `>>` Precedence
**Decision**: `>>` is sugar for `.` semantically, but has LOWER precedence.

**Precedence** (lowest to highest):
```
>>    pipeline (lowest)
+     addition / disjoint union
.     vertical composition
|     horizontal tensor (highest)
```

**Example**:
```tangle
# Without >>: parentheses needed
(braid[s1] . braid[s2]) . (braid[s3] . braid[s1])

# With >>: pipeline stages visually clear
braid[s1] . braid[s2] >> braid[s3] . braid[s1]
```

Both evaluate identically — `.` is associative. Different precedence is purely for **human readability**.

**Status**: Grammar already implements this correctly.

---

## Polymorphism and Width

### D1.21: No Full Polymorphism (MVP)
**Decision**: Width inference instead of Hindley-Milner polymorphism.

**Rules**:
- `identity` is concretely `Word[0]` with auto-widening (D1.14)
- User-defined function widths inferred from usage
- If ambiguous, compiler asks for annotation

**Example**:
```tangle
def f(x) = x . braid[s1]   # x must be at least Word[2], result is Word[2]
```

**No** `∀` quantifiers. Width inference is simpler than full polymorphism — just track maximum generator index through expressions.

**Future**: Full polymorphic boundaries (∀A. Tangle[A,A]) can be added post-MVP.

---

## Module System

### D1.22: TANGLE Module System
**Decision**: Flat namespace for MVP (no in-language modules).

**Rules**:
- All `def`s go into one global Γ
- Multiple `.tangle` files loaded in order
- Harvard modules (already in grammar) available for namespacing via JTV

**Rationale**: TANGLE programs are mathematical objects. Mathematical papers have definitions, not modules. Module system can be added post-MVP if name collisions become a problem.

---

## Standard Library

### D1.23: Standard Library Functions
**Decision**: Utility functions shipped as pure TANGLE definitions (Tier 3).

**Included**:
```tangle
# length : Word[n] → Num
def length(w) = match w with
  | identity => 0
  | _ . rest => add{ 1 + length(rest) }
end

# Also: concat, braid_repeat, reverse_word, etc.
```

**Rationale**: These are trivially definable with pattern matching + recursion. No reason to bake into the compiler. Also serve as idiomatic TANGLE code examples.

---

## Theoretical Foundations

### D1.24: Turing Completeness Proof Strategy
**Decision**: Via pattern matching + recursion on Word structure.

**Proof Sketch**:
- `identity` = nil
- `s_i . rest` = cons(s_i, rest)
- Pattern matching = list destructuring
- Recursion = general recursion

Pattern matching + recursion on an inductively-defined structure with infinitely many constructors (s1, s2, s3, ...) is Turing complete (standard result).

**Implication**: Pure TANGLE (without JTV) is Turing complete on its own. Num is a convenience, not a necessity. No braid-as-number encoding needed (D1.6.5).

---

### D1.25: Data Encoding Philosophy
**Decision**: Pure TANGLE handles topology only. Complex data structures live in JTV.

**Scope**:
- TANGLE: `Word[n]`, `Tangle[A,B]`, `Num`, `Str` — that's it
- Pairs, lists, trees → require `add{...}` / `harvard{...}` blocks
- No braid encoding of data structures (Coherence Problem #5 resolved by design)

**Rationale**: "Everything topological is a braid, everything else is Harvard." Encoding lists as braids would overload topological meaning with data semantics. The two-world design exists precisely so TANGLE doesn't have to solve this.

**Implication**: Generator index partitioning (using high indices as type tags) is unnecessary.

---

# PART 2: TANGLE-JTV (Julia-the-Viper Extension)

## Overview

TANGLE-JTV extends TANGLE with two delimited syntactic islands:
1. **`add{...}`** - Data-only computations (total, guaranteed terminating)
2. **`harvard{...}`** - Full imperative programs (control + data)

---

## The Three Worlds

### D2.1: Semantic Stratification

**TANGLE World** (from Part 1):
- Values: `Word[n]`, `Tangle[𝐀,𝐁]`, `Num`, `Str`, `Bool`
- Control: Pattern matching on Words only
- Environment: Γ (TANGLE definitions)

**Harvard DATA World** (`add{...}`):
- Values: Total data expressions (numbers, bools, strings)
- Grammar: `hv_data_expr` only (NO if/while/for/assignments)
- Calls: Only @pure/@total functions from Π
- **Guarantee**: Always terminates

**Harvard CONTROL World** (`harvard{...}`):
- Full imperative language: if/while/for/return/assignments
- Functions with purity markers (@pure/@total)
- Modules, imports
- Environment: Δ (full Harvard), Π ⊆ Δ (pure subset)

---

## Visibility & Environments

### D2.2: Three Environments
**Decision**: Separate namespaces with one-way bridge.

```
Γ : TangleEnv      - TANGLE definitions (def, weave)
Δ : HarvardEnv     - All Harvard functions, modules
Π ⊆ Δ : PureEnv    - Pure/total Harvard functions only
```

**Visibility Rules**:
```
Inside TANGLE expr:   calls resolve in Γ only
Inside harvard{...}:  calls resolve in Δ
Inside add{...}:      calls resolve in Π only
```

**Bridge Flow**:
```
harvard{...} defines functions
    ↓
@pure/@total functions → Π
    ↓
add{...} calls Π functions
    ↓
Results embed via Embed(τ)
    ↓
TANGLE uses embedded values
```

**Rationale**: Clean separation prevents effect leakage, maintains totality guarantees.

---

### D2.3: Π Visibility Model (Sequential)
**Decision**: Sequential visibility (MVP).

**Meaning**: @pure/@total function visible in `add{...}` ONLY AFTER its `harvard{...}` block.

**Example**:
```tangle
add{ bar() }                      ✗ ERROR - bar not in Π yet

harvard{ fn bar() @pure { ... } }

add{ bar() }                      ✓ OK - bar now in Π
```

**Two-Pass Reconciliation**:
- TANGLE defs collected in pass 1 (forward refs OK)
- Harvard blocks processed sequentially in pass 2 (Π grows)
- add{...} sees current Π at point of use

**Future**: Two-pass Π in v2 (non-breaking, accepts more programs).

---

## Embedding Bridge

### D2.4: Embed(τ) Type Bridge
**Decision**: Minimal scalar embedding only (MVP).

```
Embed : HarvardType → TangleType

Embed(Int)       = Num
Embed(Float)     = Num
Embed(Rational)  = Num
Embed(Hex)       = Num          (convert to numeric)
Embed(Binary)    = Num          (convert to numeric)
Embed(Bool)      = Bool
Embed(String)    = Str
Embed(Symbolic)  = Str          (serialized)

Embed(Complex)   = ERROR        ("Complex not yet supported")
Embed(List<T>)   = ERROR        ("Lists not embeddable")
Embed(Tuple<T>)  = ERROR        ("Tuples not embeddable")
Embed(Fn ...)    = ERROR        ("Functions not embeddable")
```

**Example**:
```tangle
harvard{
  fn factorial(n: Int) @pure { ... }
}

def copies = add{ factorial(5) }    # Embed(Int) = Num
```

**Future Extensions**:
- Phase 2: Complex, structured data (List, Tuple)
- Phase 3: Semantic mappings (List<Int> ≈ Word[n]?)

---

## Harvard Semantics

### D2.5: Harvard Store Persistence
**Decision**: Module-scoped (explicit imports).

**Semantics**:
```tangle
harvard{ module Math { let x = 5 } }

harvard{
  import Math
  print(Math.x)    # ✓ OK - explicit import
}

harvard{
  print(x)         # ✗ ERROR - x not in scope
}
```

**Rationale**: Modularity, no accidental global state.

---

### D2.6: Harvard Module Imports
**Decision**: Explicit imports with sequential visibility.

**Rules**:
- `module M { ... }` registers M in Δ
- `import M` or `import M as Alias` brings M into scope
- **Sequential constraint**: Can only import modules from earlier `harvard{...}` blocks

**Example**:
```tangle
harvard{
  module Math {
    fn sqrt(x: Float) @pure { ... }
  }
}

harvard{
  import Math
  fn hypotenuse(a, b) @pure {
    Math.sqrt(a*a + b*b)
  }
}
```

**Rationale**: Consistent with sequential Π visibility (D2.3).

---

## Future Extensions

### D2.7: Reverse Blocks
**Decision**: Document interface, defer implementation.

**Status**:
- Parse `reverse{...}` syntax
- Typecheck reversible statements
- Full Bennett semantics: post-MVP

---

## Cross-World Interaction

### D2.8: Weave Block Visibility
**Decision**: Weave blocks can reference all definitions in Γ (outer scope).

**Rules**:
```tangle
def helper = braid[s1, s2]

weave strands a:Q, b:Q into
  helper              # ✓ Can reference global def
yield strands b:Q, a:Q
```

**Rationale**: Weave blocks are TANGLE expressions. They naturally see all of Γ, consistent with D1.9 (any TANGLE expression that typechecks).

---

### D2.9: Harvard Calling TANGLE
**Decision**: Harvard CAN call TANGLE functions, with purity restriction.

**Rules**:
```
Unmarked Harvard functions → can call ANY TANGLE function
@pure/@total Harvard functions → can ONLY call non-recursive TANGLE functions
```

**Recursion Check**: Syntactic (conservative) — if a TANGLE function's body contains self-reference, it's marked as potentially non-terminating. @pure/@total Harvard code cannot call it.

**Example**:
```tangle
def simplify_once(w) = ...        # Non-recursive — @pure can call ✓
def loop(w) = loop(w)             # Recursive — @pure CANNOT call ✗

harvard{
  fn verify(w) @pure {
    simplify_once(w)               # ✓ OK
    # loop(w)                      # ✗ ERROR: @pure cannot call recursive TANGLE
  }
  fn debug(w) {
    loop(w)                        # ✓ OK (no purity marker)
  }
}
```

**Rationale**: Sound (conservative check, never wrong), simple (syntactic), practical (Tier 1 primitives like `simplify`, `jones`, `close` are non-recursive, so @pure Harvard code can call them freely).

---

### D2.10: Reverse Embedding (Unembed)
**Decision**: Implicit scalar Unembed — TANGLE scalars convert to Harvard types automatically.

**Unembed Rules**:
```
Unembed(Num)           = Int or Float   (context-dependent)
Unembed(Str)           = String
Unembed(Word[n])       = ERROR          ("braids don't cross into Harvard")
Unembed(Tangle[A,B])   = ERROR          ("tangles don't cross into Harvard")
```

**Bidirectional Scalar Bridge**:
```
Harvard → TANGLE:  Embed(Int) = Num,  Embed(String) = Str
TANGLE → Harvard:  Unembed(Num) = Int, Unembed(Str) = String
```

**Example**:
```tangle
def copies = 5                         # TANGLE Num

harvard{
  fn process(n: Int) @pure { n * 2 }
}

add{ process(copies) }                 # ✓ copies (Num) → Int automatically
add{ process(braid[s1]) }             # ✗ TYPE ERROR: Word can't cross
```

**Rationale**: Symmetric with D2.4 (Embed). Scalars cross both ways, topological types stay in TANGLE.

---

### D2.11: Harvard Module Re-exports
**Decision**: Imports are private to the module (MVP).

**Rules**:
```tangle
harvard{
  module Utils {
    import Math                        # Private — Utils uses Math internally
    fn helper() @pure { Math.sqrt(2) }
  }
}

harvard{
  import Utils
  # Utils.helper()  ✓ OK
  # Math.sqrt(2)    ✗ ERROR — must import Math directly
}
```

**Rationale**: Keeps dependency chains explicit — you always know where a function comes from.

**Future review**: Re-exports (like Rust `pub use`) may be added post-MVP if module hierarchies get deep.

---

## Decision Cross-Reference

### TANGLE-Only Decisions (Part 1):
- D1.1–D1.8.5: Core type system (Word/Tangle split, equality, recursion, scoping, literals, arithmetic, encoding, operators, widening)
- D1.9–D1.11: Weave blocks (expression restrictions, heterogeneous boundaries, yield matching)
- D1.12: Computation (invariants)
- D1.13–D1.13.5: Program structure (definition order, termination, evaluation)
- D1.14–D1.15.3: Error handling (identity width, halt/panic, assertions, error messages, name conflicts)
- D1.16–D1.20: Operations (tiering, close, twist, self-crossings, pipeline)
- D1.21: Polymorphism (width inference, no HM for MVP)
- D1.22: Module system (flat for MVP)
- D1.23: Standard library (Tier 3 definitions)
- D1.24–D1.25: Theoretical foundations (Turing completeness, data encoding)

### TANGLE-JTV Decisions (Part 2):
- D2.1–D2.3: Three worlds, environments, Π visibility
- D2.4: Embed(τ) type bridge
- D2.5–D2.6: Harvard store persistence, module imports
- D2.7: Reverse blocks (deferred)
- D2.8: Weave block visibility (sees all Γ)
- D2.9: Harvard calling TANGLE (@pure restriction)
- D2.10: Reverse embedding (scalar Unembed)
- D2.11: Module re-exports (private for MVP)

### Decisions Affecting Both:
- D1.3 (Recursion) — affects D2.9 (Harvard purity check)
- D1.6 (Arithmetic) — add{...} can call Π functions that use arithmetic
- D1.13 (Order) — two-pass for TANGLE, sequential for harvard{...}
- D1.15 (Errors) — Harvard blocks provide error recovery TANGLE lacks
- D1.25 (Data encoding) — TANGLE topology only, complex data via JTV

---

## Implementation Priorities

**MVP (Minimum Viable Product)**:
- All TANGLE decisions (D1.1–D1.25)
- add{...} blocks with Embed(τ) and Unembed (D2.4, D2.10)
- harvard{...} blocks with @pure functions (D2.2, D2.3, D2.9)
- Sequential Π visibility (D2.3)
- Halt/panic error model (D1.15)
- Width inference (D1.21)
- Flat namespace (D1.22)
- Standard library (D1.23)
- Three-tier operations (D1.16)

**v2 (Enhanced)**:
- Two-pass Π visibility
- Exhaustiveness checking promoted from warning to error
- Rich Embed(τ) (Complex, List, Tuple)
- Module re-exports (D2.11 future)
- Richer error model (D1.15 future review)
- `assert` vs `prove` split (D1.15.1 future review)

**v3 (Advanced)**:
- Reverse blocks (Bennett semantics, D2.7)
- Arbitrary yield order permutations
- Full polymorphic boundaries (∀A. Tangle[A,A])
- Advanced isotopy checkers (Reidemeister, model-based)
- TANGLE module system

---

## Future Review Items

Items explicitly noted for post-MVP review:
1. **Error handling model** (D1.15) — exceptions, Result types, try/catch
2. **Assert vs Prove split** (D1.15.1) — static verification for quantum circuit proofs
3. **Module re-exports** (D2.11) — Rust-style `pub use` for facade modules

---

## Meta

- **Specification Version**: 1.0.0-draft
- **Decisions Locked**: 2026-02-12
- **Total Decisions**: 37 (25 TANGLE + 11 TANGLE-JTV + 1 deferred)
- **Authors**: Jonathan D.A. Jewell, Claude (Sonnet 4.5, Opus 4.6)
- **License**: PMPL-1.0-or-later
- **Status**: Ready for formal specification writing

---

## Change Policy

These decisions are **locked** for the MVP specification. Changes require:
1. Documented rationale
2. Impact analysis (which decisions are affected?)
3. Version bump:
   - **Major**: Breaking changes to TANGLE or TANGLE-JTV semantics
   - **Minor**: Additive features (e.g., two-pass Π)
   - **Patch**: Clarifications, typo fixes

---

## Quick Reference

**TANGLE** = Part 1 (D1.1–D1.25)
**TANGLE-JTV** = Part 1 + Part 2 (D1.1–D1.25 + D2.1–D2.11)

**Can I use TANGLE without JTV?** Yes! Part 1 is self-contained.
**Can I use JTV without TANGLE?** No — JTV extends TANGLE.

### Decision Index

| ID | Topic | Section |
|----|-------|---------|
| D1.1 | Word vs Tangle split | Core Type System |
| D1.2 | Two equality operators (~ and ==) | Core Type System |
| D1.3 | Recursion on Words | Core Type System |
| D1.3.5 | Pattern variable scoping | Core Type System |
| D1.4 | Match exhaustiveness (runtime + warning) | Core Type System |
| D1.4.5 | Let binding scoping | Core Type System |
| D1.5 | TANGLE literals (Num, Str) | Core Type System |
| D1.6 | Numeric arithmetic (+ overloaded) | Core Type System |
| D1.6.5 | Numeric encoding (Num ≠ Word) | Core Type System |
| D1.7 | Tangle + restriction (closed only) | Core Type System |
| D1.8 | Operator disambiguation (. and identity) | Core Type System |
| D1.8.5 | Auto-widening on composition | Core Type System |
| D1.9 | Weave expression restrictions | Weave Blocks |
| D1.10 | Heterogeneous typed boundaries | Weave Blocks |
| D1.11 | Yield boundary matching (exact) | Weave Blocks |
| D1.12 | Invariant computation (built-in + FFI) | Computation |
| D1.13 | Top-level definition order (two-pass) | Program Structure |
| D1.13.5 | Termination and evaluation (CBV) | Program Structure |
| D1.14 | Identity width (Word[0]) | Error Handling |
| D1.15 | Error handling (halt/panic) | Error Handling |
| D1.15.1 | Assertion decidability (runtime only) | Error Handling |
| D1.15.2 | Error messages (name-based) | Error Handling |
| D1.15.3 | Name conflict resolution (unified, warn) | Error Handling |
| D1.16 | Primitives tiering (3 tiers) | Operations |
| D1.17 | Close operation (no permutation check) | Operations |
| D1.18 | Twist operator (context-dependent) | Operations |
| D1.19 | Self-crossings (allow, warn, desugar) | Operations |
| D1.20 | Pipeline >> precedence | Operations |
| D1.21 | No full polymorphism (width inference) | Polymorphism |
| D1.22 | Flat module system | Module System |
| D1.23 | Standard library (Tier 3) | Standard Library |
| D1.24 | Turing completeness proof | Theoretical |
| D1.25 | Data encoding (topology only) | Theoretical |
| D2.1 | Semantic stratification (3 worlds) | Three Worlds |
| D2.2 | Three environments (Γ, Δ, Π) | Visibility |
| D2.3 | Π sequential visibility | Visibility |
| D2.4 | Embed(τ) scalar bridge | Embedding |
| D2.5 | Harvard store persistence | Harvard Semantics |
| D2.6 | Harvard module imports | Harvard Semantics |
| D2.7 | Reverse blocks (deferred) | Future |
| D2.8 | Weave block visibility (all Γ) | Cross-World |
| D2.9 | Harvard calling TANGLE (@pure restriction) | Cross-World |
| D2.10 | Reverse embedding (scalar Unembed) | Cross-World |
| D2.11 | Module re-exports (private MVP) | Cross-World |
