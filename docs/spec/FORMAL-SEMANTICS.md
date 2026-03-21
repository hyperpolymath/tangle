# TANGLE & TANGLE-JTV Formal Semantics

Specification Version: 1.0.0-draft
Date: 2026-02-12
Authors: Jonathan D.A. Jewell, Claude (Opus 4.6)
License: PMPL-1.0-or-later

This document defines the formal typing rules and operational semantics for
TANGLE (Part 1) and TANGLE-JTV (Part 2). All rules reference locked decisions
in DECISIONS-LOCKED.md.

---

# Part 1: TANGLE

## 1. Abstract Syntax

### 1.1 Programs

```
prog  ::=  stmt₁ ; ... ; stmtₙ

stmt  ::=  def x = e                                              -- value definition
        |  def f(x₁, ..., xₖ) = e                                -- function definition
        |  weave strands S_in into e yield strands S_out          -- weave block
        |  compute inv(e)                                         -- invariant computation
        |  assert e                                               -- assertion (e : Bool)
```

### 1.2 Expressions

```
e  ::=  x                                    -- variable reference
     |  n                                    -- numeric literal (integer or float)
     |  "s"                                  -- string literal
     |  true  |  false                       -- boolean literals
     |  identity                             -- identity element (Word[0])
     |  braid[g₁, ..., gₖ]                  -- braid literal
     |  e₁ . e₂                             -- vertical composition / word cons
     |  e₁ | e₂                             -- horizontal tensor
     |  e₁ + e₂                             -- addition or disjoint union
     |  e₁ >> e₂                            -- pipeline (sugar for .)
     |  e₁ - e₂                             -- subtraction
     |  e₁ * e₂                             -- multiplication
     |  e₁ / e₂                             -- division
     |  e₁ == e₂                            -- structural equality
     |  e₁ ~ e₂                             -- isotopy equivalence
     |  (~e)                                 -- twist (standalone)
     |  (~a)                                 -- twist (weave, strand name a)
     |  (a > b)                              -- over-crossing (weave context)
     |  (a < b)                              -- under-crossing (weave context)
     |  close(e)                             -- closure
     |  cap                                  -- cap primitive
     |  cup                                  -- cup primitive
     |  mirror(e)                            -- mirror image
     |  reverse(e)                           -- reverse word
     |  simplify(e)                          -- Reidemeister simplification
     |  f(e₁, ..., eₖ)                      -- function application
     |  match e with arm₁ | ... | armₖ end  -- pattern matching
     |  let x = e₁ in e₂                    -- let binding
```

### 1.3 Generators

```
g  ::=  sᵢ                -- positive generator (strand i over strand i+1)
     |  sᵢ⁻¹              -- inverse generator (strand i+1 over strand i)

index(sᵢ) = i
index(sᵢ⁻¹) = i
```

### 1.4 Patterns

```
p  ::=  identity           -- matches empty word
     |  g . p              -- matches generator g followed by pattern p
     |  x                  -- variable pattern (binds x to matched value)
     |  _                  -- wildcard (matches anything, binds nothing)
```

### 1.5 Strand Declarations

```
S  ::=  a₁:T₁, ..., aₙ:Tₙ     -- named typed strand list
```

---

## 2. Types

### 2.1 Type Syntax

```
τ  ::=  Word[n]            -- braid word on n strands (n ≥ 0)
     |  Tangle[A, B]       -- tangle morphism from boundary A to boundary B
     |  Num                 -- numbers (integers and floats)
     |  Str                 -- strings
     |  Bool                -- booleans
```

### 2.2 Boundaries

```
A, B  ::=  [T₁, ..., Tₖ]   -- ordered list of strand types (k ≥ 0)
        |  I                 -- empty boundary (alias for [])

|A|  =  length of boundary A
A ++ B  =  concatenation of boundaries
```

### 2.3 Strand Types

```
T  ::=  Q | R | S | ...    -- named strand types (from weave declarations)
     |  Strand              -- default strand type (when unannoted)
```

### 2.4 Function Signatures

Functions are not first-class. Their signatures are recorded in the environment.

```
sig  ::=  (τ₁, ..., τₖ) → τ    -- k-argument function type
```

### 2.5 Width Function

```
width(identity) = 0
width(braid[g₁, ..., gₖ]) = max(index(gⱼ) + 1 for j = 1..k), or 0 if k = 0
width(e₁ . e₂) = max(width(e₁), width(e₂))
width(e₁ | e₂) = width(e₁) + width(e₂)
```

### 2.6 Permutation Function

Each braid word w : Word[n] induces a permutation πw on {1, ..., n}.

```
π_identity = id
π_{sᵢ} = transposition (i, i+1)
π_{sᵢ⁻¹} = transposition (i, i+1)
π_{w₁ · w₂} = π_{w₂} ∘ π_{w₁}
```

For boundary application: πw([T₁, ..., Tₙ]) = [T_{πw(1)}, ..., T_{πw(n)}]

---

## 3. Typing Rules

### Environments

```
Γ  ::=  ·                         -- empty environment
     |  Γ, x : τ                  -- value binding
     |  Γ, f : (τ₁,...,τₖ) → τ   -- function binding

Σ  ::=  ·                         -- empty strand context
     |  Σ, a : (i, T)             -- strand name a at position i with type T
```

Typing judgments:
- `Γ ⊢ e : τ` — expression e has type τ under environment Γ
- `Γ; Σ ⊢ e : τ` — expression e has type τ under Γ and strand context Σ

### 3.1 Literals

```
─────────────────── [T-Num]
Γ ⊢ n : Num


─────────────────── [T-Str]
Γ ⊢ "s" : Str


─────────────────── [T-True]           ─────────────────── [T-False]
Γ ⊢ true : Bool                        Γ ⊢ false : Bool


─────────────────────────── [T-Identity]           (D1.14)
Γ ⊢ identity : Word[0]
```

### 3.2 Braid Literals

```
g₁, ..., gₖ  are generators
n = max(index(gⱼ) + 1 for j = 1..k)        (n ≥ 1 when k ≥ 1)
──────────────────────────────────────────── [T-Braid]
Γ ⊢ braid[g₁, ..., gₖ] : Word[n]


──────────────────────────── [T-Braid-Empty]
Γ ⊢ braid[] : Word[0]
```

### 3.3 Variables

```
(x : τ) ∈ Γ
────────────── [T-Var]
Γ ⊢ x : τ
```

### 3.4 Composition Operators

**Vertical composition** (`.`) — sequential application (D1.8, D1.8.5):

```
Γ ⊢ e₁ : Word[n]       Γ ⊢ e₂ : Word[m]
──────────────────────────────────────────── [T-Compose-Word]
Γ ⊢ e₁ . e₂ : Word[max(n, m)]


Γ ⊢ e₁ : Tangle[A, B]       Γ ⊢ e₂ : Tangle[B, C]
──────────────────────────────────────────────────── [T-Compose-Tangle]
Γ ⊢ e₁ . e₂ : Tangle[A, C]
```

**Horizontal tensor** (`|`) — parallel juxtaposition:

```
Γ ⊢ e₁ : Word[n]       Γ ⊢ e₂ : Word[m]
──────────────────────────────────────────── [T-Tensor-Word]
Γ ⊢ e₁ | e₂ : Word[n + m]


Γ ⊢ e₁ : Tangle[A₁, B₁]       Γ ⊢ e₂ : Tangle[A₂, B₂]
──────────────────────────────────────────────────────── [T-Tensor-Tangle]
Γ ⊢ e₁ | e₂ : Tangle[A₁ ++ A₂, B₁ ++ B₂]
```

**Pipeline** (`>>`) — sugar for vertical composition (D1.20):

```
Γ ⊢ e₁ . e₂ : τ
─────────────────── [T-Pipeline]
Γ ⊢ e₁ >> e₂ : τ
```

### 3.5 Arithmetic Operators

**Addition** — overloaded by sort (D1.6):

```
Γ ⊢ e₁ : Num       Γ ⊢ e₂ : Num
──────────────────────────────────── [T-Add-Num]
Γ ⊢ e₁ + e₂ : Num


Γ ⊢ e₁ : Tangle[I, I]       Γ ⊢ e₂ : Tangle[I, I]
──────────────────────────────────────────────────── [T-Add-Tangle]       (D1.7)
Γ ⊢ e₁ + e₂ : Tangle[I, I]
```

If operand types don't match either rule: TYPE ERROR.

**Other arithmetic** (D1.6):

```
Γ ⊢ e₁ : Num       Γ ⊢ e₂ : Num       op ∈ {-, *, /}
───────────────────────────────────────────────────────── [T-Arith]
Γ ⊢ e₁ op e₂ : Num
```

### 3.6 Equality Operators

**Structural equality** (`==`) — defined for Word, Num, Str (D1.2):

```
Γ ⊢ e₁ : Word[n]       Γ ⊢ e₂ : Word[n]
──────────────────────────────────────────── [T-Eq-Word]
Γ ⊢ e₁ == e₂ : Bool


Γ ⊢ e₁ : Num       Γ ⊢ e₂ : Num
──────────────────────────────────── [T-Eq-Num]
Γ ⊢ e₁ == e₂ : Bool


Γ ⊢ e₁ : Str       Γ ⊢ e₂ : Str
──────────────────────────────────── [T-Eq-Str]
Γ ⊢ e₁ == e₂ : Bool
```

**Isotopy equivalence** (`~`) — defined for Tangles (D1.2):

```
Γ ⊢ e₁ : Tangle[A, B]       Γ ⊢ e₂ : Tangle[A, B]
──────────────────────────────────────────────────── [T-Isotopy]
Γ ⊢ e₁ ~ e₂ : Bool
```

`~` also works on Words via implicit coercion (see §3.12).

### 3.7 Tier 1 Primitives

**Close** (D1.17):

```
Γ ⊢ e : Tangle[A, B]       |A| = |B|
───────────────────────────────────────── [T-Close-Tangle]
Γ ⊢ close(e) : Tangle[I, I]


Γ ⊢ e : Word[n]
────────────────────────────── [T-Close-Word]
Γ ⊢ close(e) : Tangle[I, I]
```

No permutation check. Closing a non-identity permutation produces a link.

**Cap and Cup**:

```
──────────────────────────────────── [T-Cap]
Γ ⊢ cap : Tangle[[T, T], I]


──────────────────────────────────── [T-Cup]
Γ ⊢ cup : Tangle[I, [T, T]]
```

With explicit strand types (in weave context):

```
──────────────────────────────────────────── [T-Cap-Typed]
Γ ⊢ cap(T₁, T₂) : Tangle[[T₁, T₂], I]


──────────────────────────────────────────── [T-Cup-Typed]
Γ ⊢ cup(T₁, T₂) : Tangle[I, [T₁, T₂]]
```

**Mirror** — reverses morphism direction:

```
Γ ⊢ e : Tangle[A, B]
──────────────────────────── [T-Mirror-Tangle]
Γ ⊢ mirror(e) : Tangle[B, A]


Γ ⊢ e : Word[n]
────────────────────────── [T-Mirror-Word]
Γ ⊢ mirror(e) : Word[n]
```

**Reverse** — inverts all generators in a word:

```
Γ ⊢ e : Word[n]
──────────────────────── [T-Reverse]
Γ ⊢ reverse(e) : Word[n]
```

**Simplify** — applies Reidemeister moves:

```
Γ ⊢ e : Word[n]
────────────────────────── [T-Simplify-Word]
Γ ⊢ simplify(e) : Word[n]


Γ ⊢ e : Tangle[A, B]
──────────────────────────────── [T-Simplify-Tangle]
Γ ⊢ simplify(e) : Tangle[A, B]
```

### 3.8 Twist Operator (D1.18)

**Standalone twist** — composes with all-strand twist tangle (θ_A):

```
Γ ⊢ e : Word[n]
──────────────────── [T-Twist-Word]
Γ ⊢ (~e) : Word[n]


Γ ⊢ e : Tangle[A, B]
──────────────────────────── [T-Twist-Tangle]
Γ ⊢ (~e) : Tangle[A, B]
```

Desugaring: `(~e) ≡ e . twist_n` where `twist_n` is the n-strand full twist.

**Weave twist** — single strand (see §3.10).

### 3.9 Pattern Matching (D1.3, D1.4)

```
Γ ⊢ e : τ_scrutinee
∀i.  Γ ⊢ pᵢ ◁ τ_scrutinee ⊣ Γᵢ       -- pattern pᵢ checks against τ, binds Γᵢ
∀i.  Γ, Γᵢ ⊢ eᵢ : τ_result            -- each arm body has same result type
──────────────────────────────────────── [T-Match]
Γ ⊢ match e with p₁ => e₁ | ... | pₖ => eₖ end : τ_result
```

**Pattern typing** — `Γ ⊢ p ◁ τ ⊣ Γ'` means pattern p checks against type τ,
producing bindings Γ':

```
──────────────────────────────── [P-Identity]
Γ ⊢ identity ◁ Word[n] ⊣ ·


index(g) + 1 ≤ n       Γ ⊢ p ◁ Word[n] ⊣ Γ'
──────────────────────────────────────────────── [P-Cons]
Γ ⊢ g . p ◁ Word[n] ⊣ Γ'


──────────────────────────────── [P-Var]
Γ ⊢ x ◁ τ ⊣ (x : τ)


──────────────────────────────── [P-Wildcard]
Γ ⊢ _ ◁ τ ⊣ ·
```

**Exhaustiveness**: Width-aware warning (D1.4). When scrutinee type is Word[n],
the compiler warns if not all generators s₁ through s_{n-1} are covered.
Warning only; does not affect well-typedness.

### 3.10 Weave Blocks (D1.9, D1.10, D1.11, D2.8)

```
Σ = {a₁ : (1, T₁), ..., aₙ : (n, Tₙ)}
A = [T₁, ..., Tₙ]
B = [U₁, ..., Uₘ]
Γ; Σ ⊢ body : Tangle[A, B]
yield declarations match B
────────────────────────────────────────────────────────────── [T-Weave]
Γ ⊢ weave strands a₁:T₁,...,aₙ:Tₙ into body
    yield strands b₁:U₁,...,bₘ:Uₘ : Tangle[A, B]
```

Weave blocks can reference all definitions in Γ (D2.8).

**Crossing in weave context**:

```
Σ(a) = (i, Tₐ)       Σ(b) = (j, Tᵦ)       i ≠ j
A = current input boundary
B = swap(A, i, j)
─────────────────────────────────────────────────── [T-Cross-Over]
Γ; Σ ⊢ (a > b) : Tangle[A, B]
```

```
Σ(a) = (i, Tₐ)       Σ(b) = (j, Tᵦ)       i ≠ j
A = current input boundary
B = swap(A, i, j)
─────────────────────────────────────────────────── [T-Cross-Under]
Γ; Σ ⊢ (a < b) : Tangle[A, B]
```

Where `swap(A, i, j)` exchanges elements at positions i and j in A.

**Twist in weave context** (D1.18):

```
Σ(a) = (i, T)
─────────────────────────────────── [T-Twist-Strand]
Γ; Σ ⊢ (~a) : Tangle[[T], [T]]
```

**Self-crossing** (D1.19):

```
Σ(a) = (i, T)
───────────────────────────────────── [T-Self-Cross]
Γ; Σ ⊢ (a > a) : Tangle[[T], [T]]
```

Desugars to `(~a)`. Compiler emits warning.

### 3.11 Let Bindings (D1.4.5)

```
Γ ⊢ e₁ : τ₁       Γ, x : τ₁ ⊢ e₂ : τ₂
──────────────────────────────────────────── [T-Let]
Γ ⊢ let x = e₁ in e₂ : τ₂
```

Shadowing: if x already exists in Γ, the inner binding shadows it.
Compiler emits warning (D1.15.3).

### 3.12 Implicit Coercion: Word → Tangle (D1.1)

```
Γ ⊢ e : Word[n]
context expects Tangle[A, B]
|A| = n'       n' ≥ n
B = πₑ(A)     (permutation applied to A, identity on widened strands)
──────────────────────────────────────────── [T-Realize]
Γ ⊢ e : Tangle[A, B]
```

Coercion inserts `realize_A(e)`:
- Embeds Word[n] into an n'-strand tangle (n' ≥ n)
- Extra strands (beyond n) act as identity
- Result boundary B = πₑ(A) where πₑ is the permutation of e, extended with identity on extra strands

With homogeneous default boundaries (all strands have type Strand):

```
Γ ⊢ e : Word[n]
A = [Strand, ..., Strand]  (n copies)
──────────────────────────────────────── [T-Realize-Default]
Γ ⊢ e : Tangle[A, A]
```

Note: With homogeneous boundaries, πₑ(A) = A always, since all strand types are identical.

### 3.13 Function Definitions and Application

**Definition** (collected in pass 1 per D1.13):

```
Γ, f : (τ₁,...,τₖ) → τ, x₁ : τ₁, ..., xₖ : τₖ ⊢ body : τ
──────────────────────────────────────────────────────────────── [T-Def-Fun]
Γ ⊢ def f(x₁, ..., xₖ) = body  ⊣  Γ, f : (τ₁,...,τₖ) → τ


Γ ⊢ e : τ
──────────────────────────── [T-Def-Val]
Γ ⊢ def x = e  ⊣  Γ, x : τ
```

Note: f appears in its own environment (recursive definitions allowed, D1.3).

**Application**:

```
Γ(f) = (τ₁, ..., τₖ) → τ       Γ ⊢ eᵢ : τᵢ  for each i
──────────────────────────────────────────────────────────── [T-App]
Γ ⊢ f(e₁, ..., eₖ) : τ
```

### 3.14 Width Inference (D1.21)

Types for function arguments are inferred from usage when not annotated.
The inference algorithm tracks the maximum generator index through expressions:

```
infer_width(identity) = 0
infer_width(braid[g₁,...,gₖ]) = max(index(gⱼ) + 1)
infer_width(e₁ . e₂) = max(infer_width(e₁), infer_width(e₂))
infer_width(e₁ | e₂) = infer_width(e₁) + infer_width(e₂)
infer_width(f(e₁,...,eₖ)) = width from f's return type
infer_width(x) = width from Γ(x) if Word[n], else unknown
```

If width cannot be inferred, compiler requests annotation.

### 3.15 Statements

**Assert** (D1.15, D1.15.1):

The grammar has `assertion = "assert", expr`. The expression must evaluate
to Bool. Common patterns: `assert e₁ ~ e₂`, `assert e₁ == e₂`, `assert f(x)`.

```
Γ ⊢ e : Bool
────────────────────── [T-Assert]
Γ ⊢ assert e  :  ok
```

This subsumes isotopy and equality assertions because `~` and `==` return Bool
(see §3.6). For example, `assert e₁ ~ e₂` typechecks because T-Isotopy gives
`e₁ ~ e₂ : Bool`, and T-Assert accepts any `Bool`.

**Compute** (D1.12):

```
inv ∈ {jones, alexander, homfly, kauffman, writhe, linking}
Γ ⊢ e : Tangle[I, I]       (or coercible to Tangle[I, I])
──────────────────────────────────────────────────────────── [T-Compute]
Γ ⊢ compute inv(e)  :  ok
```

**Invariant Result Types**:

Each built-in invariant produces a specific type:

```
result_type(jones)     = Num     -- Laurent polynomial in t^(1/2), evaluated numerically
result_type(alexander) = Num     -- Laurent polynomial in t, evaluated numerically
result_type(homfly)    = Num     -- two-variable polynomial P(a,z), evaluated numerically
result_type(kauffman)  = Num     -- Kauffman bracket polynomial, evaluated numerically
result_type(writhe)    = Num     -- integer (sum of crossing signs)
result_type(linking)   = Num     -- integer or half-integer (linking number)
```

MVP note: Polynomials are evaluated at fixed values, returning Num. Future versions
may return a Polynomial type for symbolic manipulation.

### 3.16 Program Typing (D1.13)

A program is well-typed if all statements typecheck under the accumulated Γ.

**Pass 1**: Collect all `def` names and their types into Γ.

```
Γ₀ = ·
For each def in prog (in source order):
  Γᵢ₊₁ = Γᵢ, name : inferred_type
Γ_complete = Γₙ
```

**Pass 2**: Typecheck all statements against Γ_complete.

```
∀ stmt ∈ prog:  Γ_complete ⊢ stmt : ok
──────────────────────────────────────── [T-Program]
⊢ prog : ok
```

Forward references are allowed because Γ_complete contains all definitions.

---

## 4. Operational Semantics

Big-step natural semantics. Call-by-value evaluation (D1.13.5).

### 4.1 Values

```
v  ::=  num(n)                          -- numeric value
     |  str(s)                          -- string value
     |  bool(b)                         -- boolean value (b ∈ {true, false})
     |  word(g₁, ..., gₖ)              -- braid word value (sequence of generators)
     |  tangle(t)                       -- tangle value (opaque internal representation)
     |  halt(msg, span)                 -- error value (program halts)
```

`word()` (empty sequence) represents identity.

### 4.2 Runtime Environments

```
ρ  ::=  ·                               -- empty environment
     |  ρ, x ↦ v                        -- value binding
     |  ρ, f ↦ closure(x₁,...,xₖ, body) -- function binding
```

### 4.3 Judgment Form

```
ρ ⊢ e ⇓ v        -- under environment ρ, expression e evaluates to value v
ρ ⊢ e ⇓ halt(m)  -- under environment ρ, expression e halts with error message m
```

Non-termination: if no derivation exists, the evaluation diverges (D1.13.5).

### 4.4 Evaluation Rules — Literals

```
─────────────────── [E-Num]
ρ ⊢ n ⇓ num(n)


─────────────────── [E-Str]
ρ ⊢ "s" ⇓ str(s)


───────────────────────── [E-True]         ──────────────────────── [E-False]
ρ ⊢ true ⇓ bool(true)                     ρ ⊢ false ⇓ bool(false)


──────────────────────── [E-Identity]
ρ ⊢ identity ⇓ word()


─────────────────────────────────────── [E-Braid]
ρ ⊢ braid[g₁,...,gₖ] ⇓ word(g₁,...,gₖ)
```

### 4.5 Evaluation Rules — Variables

```
ρ(x) = v
────────────── [E-Var]
ρ ⊢ x ⇓ v
```

### 4.6 Evaluation Rules — Composition

**Word composition** — concatenation with implicit widening (D1.8.5):

```
ρ ⊢ e₁ ⇓ word(g₁, ..., gⱼ)       ρ ⊢ e₂ ⇓ word(h₁, ..., hₖ)
──────────────────────────────────────────────────────────────── [E-Compose-Word]
ρ ⊢ e₁ . e₂ ⇓ word(g₁, ..., gⱼ, h₁, ..., hₖ)
```

Widening is implicit: generators from both words coexist in the wider braid group.

**Tangle composition** — sequential application:

```
ρ ⊢ e₁ ⇓ tangle(t₁)       ρ ⊢ e₂ ⇓ tangle(t₂)
output boundary of t₁ = input boundary of t₂
──────────────────────────────────────────────── [E-Compose-Tangle]
ρ ⊢ e₁ . e₂ ⇓ tangle(compose(t₁, t₂))
```

**Tensor** — parallel juxtaposition:

```
ρ ⊢ e₁ ⇓ word(g₁, ..., gⱼ)       ρ ⊢ e₂ ⇓ word(h₁, ..., hₖ)
n₁ = width(word(g₁,...,gⱼ))
h'ᵢ = shift(hᵢ, n₁)       for each i     -- shift indices by n₁
──────────────────────────────────────────────────────────────── [E-Tensor-Word]
ρ ⊢ e₁ | e₂ ⇓ word(g₁, ..., gⱼ, h'₁, ..., h'ₖ)
```

Where `shift(sᵢ, k) = s_{i+k}` and `shift(sᵢ⁻¹, k) = s_{i+k}⁻¹`.

**Pipeline** — desugars to composition:

```
ρ ⊢ e₁ . e₂ ⇓ v
─────────────────── [E-Pipeline]
ρ ⊢ e₁ >> e₂ ⇓ v
```

### 4.7 Evaluation Rules — Arithmetic

```
ρ ⊢ e₁ ⇓ num(n₁)       ρ ⊢ e₂ ⇓ num(n₂)
─────────────────────────────────────────── [E-Add-Num]
ρ ⊢ e₁ + e₂ ⇓ num(n₁ + n₂)


ρ ⊢ e₁ ⇓ tangle(t₁)       ρ ⊢ e₂ ⇓ tangle(t₂)
t₁, t₂ both closed (boundary = I)
──────────────────────────────────────────────── [E-Add-Tangle]
ρ ⊢ e₁ + e₂ ⇓ tangle(disjoint_union(t₁, t₂))


ρ ⊢ e₁ ⇓ num(n₁)       ρ ⊢ e₂ ⇓ num(n₂)       op ∈ {-, *, /}
────────────────────────────────────────────────────────────────── [E-Arith]
ρ ⊢ e₁ op e₂ ⇓ num(n₁ op n₂)
```

Division by zero:

```
ρ ⊢ e₁ ⇓ num(n₁)       ρ ⊢ e₂ ⇓ num(0)
──────────────────────────────────────────── [E-Div-Zero]
ρ ⊢ e₁ / e₂ ⇓ halt("division by zero")
```

### 4.8 Evaluation Rules — Equality

```
ρ ⊢ e₁ ⇓ word(w₁)       ρ ⊢ e₂ ⇓ word(w₂)
──────────────────────────────────────────── [E-Eq-Word]
ρ ⊢ e₁ == e₂ ⇓ bool(w₁ = w₂)
```

Where `w₁ = w₂` iff the generator sequences are identical (structural equality).

```
ρ ⊢ e₁ ⇓ num(n₁)       ρ ⊢ e₂ ⇓ num(n₂)
──────────────────────────────────────────── [E-Eq-Num]
ρ ⊢ e₁ == e₂ ⇓ bool(n₁ = n₂)


ρ ⊢ e₁ ⇓ str(s₁)       ρ ⊢ e₂ ⇓ str(s₂)
──────────────────────────────────────────── [E-Eq-Str]
ρ ⊢ e₁ == e₂ ⇓ bool(s₁ = s₂)
```

**Isotopy** (D1.2):

```
ρ ⊢ e₁ ⇓ v₁       ρ ⊢ e₂ ⇓ v₂
──────────────────────────────────── [E-Isotopy]
ρ ⊢ e₁ ~ e₂ ⇓ bool(isotopy(v₁, v₂))
```

Where `isotopy(v₁, v₂)` checks equality in the free ribbon category FR(T).
This is a semantic function provided by the backend (D1.12).
MVP: may only support syntactic equality after simplification.

### 4.9 Evaluation Rules — Primitives

**Close**:

```
ρ ⊢ e ⇓ word(g₁, ..., gₖ)
────────────────────────────────────────── [E-Close-Word]
ρ ⊢ close(e) ⇓ tangle(close(word(g₁,...,gₖ)))


ρ ⊢ e ⇓ tangle(t)
──────────────────────────── [E-Close-Tangle]
ρ ⊢ close(e) ⇓ tangle(close(t))
```

**Mirror**:

```
ρ ⊢ e ⇓ word(g₁, ..., gₖ)
mirror_gen(sᵢ) = sᵢ⁻¹       mirror_gen(sᵢ⁻¹) = sᵢ
───────────────────────────────────────────────────── [E-Mirror-Word]
ρ ⊢ mirror(e) ⇓ word(mirror_gen(g₁), ..., mirror_gen(gₖ))
```

**Reverse**:

```
ρ ⊢ e ⇓ word(g₁, ..., gₖ)
inv(sᵢ) = sᵢ⁻¹       inv(sᵢ⁻¹) = sᵢ
──────────────────────────────────────────────── [E-Reverse]
ρ ⊢ reverse(e) ⇓ word(inv(gₖ), ..., inv(g₁))
```

**Simplify**:

```
ρ ⊢ e ⇓ word(w)
w' = reidemeister_reduce(w)
───────────────────────────── [E-Simplify]
ρ ⊢ simplify(e) ⇓ word(w')
```

Where `reidemeister_reduce` applies Reidemeister moves to normal form:
- R1: `sᵢ . sᵢ⁻¹ → ε` and `sᵢ⁻¹ . sᵢ → ε`  (cancellation)
- R2: `sᵢ . sⱼ → sⱼ . sᵢ` when `|i - j| ≥ 2`  (far commutativity)
- R3: `sᵢ . s_{i+1} . sᵢ → s_{i+1} . sᵢ . s_{i+1}`  (braid relation)

Implementation may use any terminating strategy that produces a canonical representative.

**Twist** (standalone, D1.18):

```
ρ ⊢ e ⇓ word(w)
n = width(word(w))
tw = twist_generators(n)       -- full twist on n strands
──────────────────────────────── [E-Twist-Standalone]
ρ ⊢ (~e) ⇓ word(w · tw)
```

Where `twist_generators(n)` produces the canonical full twist braid word
Δ² = (s₁ s₂ ... s_{n-1})ⁿ (the Garside element squared).

### 4.10 Evaluation Rules — Pattern Matching

**Successful match** (D1.4):

```
ρ ⊢ e ⇓ v
match(v, p₁) = fail       ...       match(v, p_{i-1}) = fail
match(v, pᵢ) = θ                    -- first matching arm
ρ ⊕ θ ⊢ eᵢ ⇓ v'
─────────────────────────────────────────────────────────────── [E-Match-Hit]
ρ ⊢ match e with p₁ => e₁ | ... | pₖ => eₖ end ⇓ v'
```

**Match failure** (D1.15):

```
ρ ⊢ e ⇓ v
∀i.  match(v, pᵢ) = fail
──────────────────────────────────────────────────────────── [E-Match-Fail]
ρ ⊢ match e with p₁ => e₁ | ... | pₖ => eₖ end ⇓ halt("MatchFailure at <span>")
```

**Pattern matching function** `match(v, p) = θ | fail`:

```
match(word(), identity)        = {}                                    -- [M-Identity]
match(word(g, g₂,...,gₖ), g . p) = match(word(g₂,...,gₖ), p)         -- [M-Cons-Match]
match(word(g, g₂,...,gₖ), g' . p) = fail      when g ≠ g'            -- [M-Cons-Fail]
match(word(), g . p)           = fail                                  -- [M-Cons-Empty]
match(v, x)                    = {x ↦ v}                              -- [M-Var]
match(v, _)                    = {}                                    -- [M-Wildcard]
```

### 4.11 Evaluation Rules — Let Bindings

```
ρ ⊢ e₁ ⇓ v₁       ρ, x ↦ v₁ ⊢ e₂ ⇓ v₂
──────────────────────────────────────────── [E-Let]
ρ ⊢ let x = e₁ in e₂ ⇓ v₂
```

### 4.12 Evaluation Rules — Function Application

```
ρ(f) = closure(x₁, ..., xₖ, body)
ρ ⊢ eᵢ ⇓ vᵢ       for each i = 1..k       -- call-by-value
ρ, x₁ ↦ v₁, ..., xₖ ↦ vₖ ⊢ body ⇓ v
──────────────────────────────────────────── [E-App]
ρ ⊢ f(e₁, ..., eₖ) ⇓ v
```

Note: f is in ρ (recursive calls resolve to the same closure), enabling recursion (D1.3).

### 4.13 Evaluation Rules — Assertions

Assertions evaluate the expression and check for truth:

```
ρ ⊢ e ⇓ bool(true)
────────────────────── [E-Assert-Pass]
ρ ⊢ assert e ⇓ ok


ρ ⊢ e ⇓ bool(false)
──────────────────────────────────────────────── [E-Assert-Fail]
ρ ⊢ assert e ⇓ halt("assertion failed: <e> at <span>")
```

For `assert e₁ ~ e₂`, evaluation first reduces `e₁ ~ e₂` via [E-Isotopy]
to `bool(b)`, then [E-Assert-Pass] or [E-Assert-Fail] applies.
Similarly for `assert e₁ == e₂` via [E-Eq-*].

### 4.14 Evaluation Rules — Invariant Computation

```
ρ ⊢ e ⇓ v       v is closed tangle or word
result = compute_invariant(inv, v)
──────────────────────────────────────── [E-Compute]
ρ ⊢ compute inv(e) ⇓ result
```

`compute_invariant` dispatches to the backend/plugin for the named invariant (D1.12).

### 4.15 Error Propagation

Errors propagate strictly (halt short-circuits evaluation):

```
ρ ⊢ e₁ ⇓ halt(m)
──────────────────────── [E-Halt-Left]
ρ ⊢ e₁ op e₂ ⇓ halt(m)


ρ ⊢ e₁ ⇓ v₁       ρ ⊢ e₂ ⇓ halt(m)
──────────────────────────────────────── [E-Halt-Right]
ρ ⊢ e₁ op e₂ ⇓ halt(m)
```

This applies uniformly to all binary operators and function arguments.

### 4.16 Program Evaluation (D1.13)

```
ρ₀ = ·

-- Pass 1: Collect definitions
For each  def x = e  in prog:
  ρ ⊢ e ⇓ v
  ρ := ρ, x ↦ v

For each  def f(x₁,...,xₖ) = body  in prog:
  ρ := ρ, f ↦ closure(x₁,...,xₖ, body)

-- Pass 2: Execute statements in source order
For each non-def stmt in prog (in source order):
  ρ ⊢ stmt ⇓ result
  if result = halt(m): terminate program with error message m
```

---

## 5. Weave Block Semantics (Detailed)

Weave blocks have richer structure than simple expressions. This section
specifies their evaluation in detail.

### 5.1 Weave Body Expressions

The body of a weave block is an expression in strand context. Strand names
resolve in Σ. Other names resolve in ρ (D2.8).

**Crossing evaluation**:

```
Σ(a) = (i, Tₐ)       Σ(b) = (j, Tᵦ)
──────────────────────────────────────────── [E-Cross]
ρ; Σ ⊢ (a > b) ⇓ tangle(crossing(i, j, over))


ρ; Σ ⊢ (a < b) ⇓ tangle(crossing(i, j, under))
```

**Composition in weave** — body expressions compose sequentially:

If the body contains multiple operations (e.g., `(a > b) . (b > c)`),
they compose via [E-Compose-Tangle].

### 5.2 Yield Validation (D1.11)

At runtime, the computed tangle's output boundary must exactly match the
yield declaration. Error messages are name-based (D1.15.2):

```
computed output boundary ≠ declared yield boundary
─────────────────────────────────────────────────── [E-Yield-Mismatch]
result = halt("yield boundary mismatch at <span>
  Expected: strands <yield_names>
  Got: strands <actual_names>
  (strand '<name>' is in position <n>, expected position <m>)")
```

---

# Part 2: TANGLE-JTV Extensions

## 6. Extended Syntax

### 6.1 Additional Expressions

```
e  ::=  ...                                  -- all TANGLE expressions from §1
     |  add{ he }                            -- Harvard data block
     |  harvard{ hp }                        -- Harvard control block (statement-level)
```

### 6.2 Harvard Data Expressions (add{...})

```
he  ::=  n | "s" | true | false              -- literals
      |  x                                   -- variable (resolves in Π)
      |  he₁ op he₂                          -- arithmetic (op ∈ {+,-,*,/})
      |  he₁ == he₂                          -- equality
      |  he₁ && he₂  |  he₁ || he₂          -- boolean operators
      |  !he                                 -- boolean negation
      |  f(he₁, ..., heₖ)                   -- function call (f must be in Π)
      |  if he₁ then he₂ else he₃           -- conditional (total: both branches required)
```

Note: NO side effects, NO loops, NO assignments. Guaranteed terminating (D2.1).

### 6.3 Harvard Control Programs (harvard{...})

```
hp  ::=  hs₁ ; ... ; hsₙ                   -- statement sequence

hs  ::=  let x = he                          -- variable binding
      |  x = he                              -- assignment
      |  if he { hp } else { hp }            -- conditional
      |  while he { hp }                     -- loop
      |  for x in he { hp }                  -- iteration
      |  return he                           -- return from function
      |  fn f(x₁:τ₁,...,xₖ:τₖ) purity { hp }  -- function definition
      |  module M { hp }                     -- module definition
      |  import M                            -- module import
      |  import M as Alias                   -- aliased import

purity  ::=  @pure                           -- total and side-effect free
          |  @total                          -- always terminates, may have effects
          |  ε                               -- no purity guarantee
```

---

## 7. Extended Types

### 7.1 Harvard Types

```
hτ  ::=  Int | Float | Rational              -- numeric types
      |  Bool                                -- boolean
      |  String                              -- strings
      |  Hex | Binary                        -- numeric encodings
      |  Symbolic                            -- symbolic expressions
      |  Complex                             -- complex numbers (future)
      |  List<hτ>                            -- lists (future)
      |  Tuple<hτ₁,...,hτₖ>                 -- tuples (future)
      |  (hτ₁,...,hτₖ) → hτ                 -- function types
```

### 7.2 Embed and Unembed (D2.4, D2.10)

**Embed**: Harvard type → TANGLE type (for `add{...}` results entering TANGLE):

```
Embed(Int)       = Num
Embed(Float)     = Num
Embed(Rational)  = Num
Embed(Hex)       = Num
Embed(Binary)    = Num
Embed(Bool)      = Bool
Embed(String)    = Str
Embed(Symbolic)  = Str

Embed(Complex)   = ERROR("Complex not yet supported")
Embed(List<T>)   = ERROR("Lists not embeddable")
Embed(Tuple<T>)  = ERROR("Tuples not embeddable")
Embed(T → U)     = ERROR("Functions not embeddable")
```

**Unembed**: TANGLE type → Harvard type (for TANGLE values entering Harvard):

```
Unembed(Num)          = Int or Float (context-dependent)
Unembed(Str)          = String
Unembed(Bool)         = Bool
Unembed(Word[n])      = ERROR("braids cannot cross into Harvard")
Unembed(Tangle[A,B])  = ERROR("tangles cannot cross into Harvard")
```

---

## 8. Extended Environments (D2.2)

```
Γ  :  TangleEnv       -- TANGLE definitions (def, weave)
Δ  :  HarvardEnv      -- ALL Harvard definitions (functions, modules, variables)
Π  ⊆ Δ  :  PureEnv    -- @pure/@total Harvard functions only
```

### 8.1 Visibility Rules

```
Inside TANGLE expression:  names resolve in Γ only
Inside add{...}:           names resolve in Π only
Inside harvard{...}:       names resolve in Δ
```

### 8.2 Π Construction (D2.3)

Π grows sequentially as harvard{...} blocks are processed:

```
Π₀ = ·

For each  harvard{ ... fn f(args) @pure { body } ... }  in source order:
  Πᵢ₊₁ = Πᵢ, f : sig

For each  harvard{ ... fn f(args) @total { body } ... }  in source order:
  Πᵢ₊₁ = Πᵢ, f : sig
```

An `add{...}` block at position j in the source sees Π = Πⱼ (all @pure/@total
functions defined in harvard{...} blocks that precede position j).

---

## 9. Extended Typing Rules

### 9.1 Harvard Data Blocks (add{...})

```
Π ⊢_hd he : hτ       Embed(hτ) = τ       Embed(hτ) ≠ ERROR
──────────────────────────────────────────────────────────── [T-Add]
Γ ⊢ add{ he } : τ
```

Where `⊢_hd` is the Harvard data typing judgment (see §9.3).

### 9.2 Harvard Control Blocks (harvard{...})

```
Δ ⊢_hc hp ⊣ Δ'       -- hp typechecks, extending Δ to Δ'
extract_pure(Δ' \ Δ) = Π'           -- new @pure/@total bindings
──────────────────────────────────── [T-Harvard]
Γ; Δ; Π ⊢ harvard{ hp } ⊣ Γ; Δ'; Π ∪ Π'
```

Harvard blocks are statement-level: they don't produce TANGLE values.
They extend Δ and Π for subsequent blocks.

### 9.3 Harvard Data Typing (⊢_hd)

Typing judgment for expressions inside `add{...}`:

```
─────────────────── [HD-Num]
Π ⊢_hd n : Int


─────────────────── [HD-Str]
Π ⊢_hd "s" : String


─────────────────────────── [HD-Bool]
Π ⊢_hd true : Bool
Π ⊢_hd false : Bool


(f : (hτ₁,...,hτₖ) → hτ) ∈ Π       Π ⊢_hd heᵢ : hτᵢ  for each i
──────────────────────────────────────────────────────────────────── [HD-App]
Π ⊢_hd f(he₁, ..., heₖ) : hτ


Π ⊢_hd he₁ : hτ₁       Π ⊢_hd he₂ : hτ₂       hτ₁ = hτ₂ = numeric
──────────────────────────────────────────────────────────────────── [HD-Arith]
Π ⊢_hd he₁ op he₂ : hτ₁       (op ∈ {+, -, *, /})


Π ⊢_hd he₁ : Bool       Π ⊢_hd he₂ : hτ       Π ⊢_hd he₃ : hτ
──────────────────────────────────────────────────────────────────── [HD-If]
Π ⊢_hd if he₁ then he₂ else he₃ : hτ


(x : hτ) ∈ Π
────────────── [HD-Var]
Π ⊢_hd x : hτ


─────────────────── [HD-Str]
Π ⊢_hd "s" : String


Π ⊢_hd he₁ : hτ₁       Π ⊢_hd he₂ : hτ₂       hτ₁, hτ₂ comparable
op ∈ {==, !=, <, <=, >, >=}
──────────────────────────────────────────────────────────────────── [HD-Compare]
Π ⊢_hd he₁ op he₂ : Bool


Π ⊢_hd he₁ : Bool       Π ⊢_hd he₂ : Bool
──────────────────────────────────────────── [HD-And]
Π ⊢_hd he₁ && he₂ : Bool


Π ⊢_hd he₁ : Bool       Π ⊢_hd he₂ : Bool
──────────────────────────────────────────── [HD-Or]
Π ⊢_hd he₁ || he₂ : Bool


Π ⊢_hd he : Bool
──────────────────── [HD-Not]
Π ⊢_hd !he : Bool


Π ⊢_hd he : numeric
──────────────────── [HD-Neg]
Π ⊢_hd -he : numeric
```

### 9.4 TANGLE Value Passing to Harvard (Unembed)

When a TANGLE value is passed as argument to a Harvard function:

```
Γ ⊢ e : τ       Unembed(τ) = hτ       Unembed(τ) ≠ ERROR
──────────────────────────────────────────────────────────── [T-Unembed]
Π ⊢_hd e : hτ       (TANGLE expression in Harvard data context)
```

### 9.5 Harvard Calling TANGLE (D2.9)

Harvard functions can call TANGLE functions with purity restriction:

```
(f : (τ₁,...,τₖ) → τ) ∈ Γ
f is non-recursive (syntactic check)
Δ ⊢_hc eᵢ : τᵢ  for each i  (with Unembed)
────────────────────────────────────────────── [HC-Call-Tangle-Pure]
Δ ⊢_hc f(e₁,...,eₖ) : τ       (legal in @pure/@total context)


(f : (τ₁,...,τₖ) → τ) ∈ Γ
f may be recursive
Δ ⊢_hc eᵢ : τᵢ  for each i  (with Unembed)
────────────────────────────────────────────── [HC-Call-Tangle-Impure]
Δ ⊢_hc f(e₁,...,eₖ) : τ       (legal ONLY in unmarked context, NOT in @pure/@total)
```

**Recursion check** (syntactic, conservative):

```
is_recursive(def f(x₁,...,xₖ) = body) = f ∈ reachable_names(body, Γ)
```

Where `reachable_names(body, Γ)` is the transitive closure of free names:

```
reachable_names(body, Γ) =
  let direct = free_names(body)
  let indirect = ∪ { free_names(Γ(g).body) | g ∈ direct, g is a function in Γ }
  direct ∪ reachable_names(indirect \ direct, Γ)    -- fixed-point iteration
```

This detects both direct recursion (`f` calls `f`) and mutual recursion
(`f` calls `g` which calls `f`). The check is conservative: if the call
graph cannot be statically determined, the function is marked recursive.

### 9.6 Module Imports (D2.6, D2.11)

```
M ∈ Δ       M defined in earlier harvard{...} block
──────────────────────────────────────────────────── [HC-Import]
Δ ⊢_hc import M  ⊣  Δ, (all bindings from M)


M ∈ Δ       M defined in earlier harvard{...} block
──────────────────────────────────────────────────── [HC-Import-Alias]
Δ ⊢_hc import M as A  ⊣  Δ, (all bindings from M under prefix A)
```

Imports are private: importing M in module N does not make M's bindings
available to consumers of N (D2.11).

---

## 10. Extended Operational Semantics

### 10.1 Harvard Data Block Evaluation

```
ρ_Π = extract_pure_values(ρ)       -- runtime values for Π functions
ρ_Π ⊢_hd he ⇓ hv                  -- evaluate Harvard data expression
v = embed_value(hv)                 -- convert Harvard value to TANGLE value
────────────────────────────────── [E-Add]
ρ ⊢ add{ he } ⇓ v
```

Where `embed_value`:

```
embed_value(int(n))    = num(n)
embed_value(float(f))  = num(f)
embed_value(bool(b))   = bool(b)
embed_value(string(s)) = str(s)
```

### 10.2 Harvard Data Expression Evaluation (⊢_hd)

```
────────────────────── [EHD-Num]
ρ_Π ⊢_hd n ⇓ int(n)


ρ_Π(f) = closure_pure(x₁,...,xₖ, body)
ρ_Π ⊢_hd heᵢ ⇓ hvᵢ       for each i
ρ_Π, x₁ ↦ hv₁, ..., xₖ ↦ hvₖ ⊢_hd body ⇓ hv
──────────────────────────────────────────────── [EHD-App]
ρ_Π ⊢_hd f(he₁,...,heₖ) ⇓ hv


ρ_Π ⊢_hd he₁ ⇓ bool(true)       ρ_Π ⊢_hd he₂ ⇓ hv
──────────────────────────────────────────────────── [EHD-If-True]
ρ_Π ⊢_hd if he₁ then he₂ else he₃ ⇓ hv


ρ_Π ⊢_hd he₁ ⇓ bool(false)       ρ_Π ⊢_hd he₃ ⇓ hv
──────────────────────────────────────────────────── [EHD-If-False]
ρ_Π ⊢_hd if he₁ then he₂ else he₃ ⇓ hv
```

### 10.3 TANGLE Value in Harvard Context (Unembed)

```
ρ ⊢ e ⇓ num(n)
──────────────────────── [E-Unembed-Num]
ρ_Π ⊢_hd e ⇓ int(n)


ρ ⊢ e ⇓ str(s)
──────────────────────── [E-Unembed-Str]
ρ_Π ⊢_hd e ⇓ string(s)


ρ ⊢ e ⇓ bool(b)
──────────────────────── [E-Unembed-Bool]
ρ_Π ⊢_hd e ⇓ bool(b)
```

### 10.4 Harvard Control Block Evaluation

Harvard control blocks are evaluated for their side effects (defining functions,
modules). They do not produce TANGLE values.

```
ρ_Δ = current Harvard runtime environment
ρ_Δ ⊢_hc hp ⇓ ρ_Δ'                -- execute Harvard program, get new environment
ρ' = ρ ∪ extract_pure(ρ_Δ' \ ρ_Δ)  -- add new @pure functions to TANGLE env
──────────────────────────────────── [E-Harvard]
ρ ⊢ harvard{ hp } ⇓ ok, ρ'
```

Detailed Harvard control evaluation rules (while loops, assignments, etc.)
follow standard imperative semantics and are not specified here. The key
constraint is the purity discipline: @pure functions must not access mutable
state or perform I/O.

---

## 11. Metatheory

### 11.1 Type Safety (Conjecture)

**Progress**: If `Γ ⊢ e : τ` and e is not a value, then either:
- e can take a step (ρ ⊢ e ⇓ v for some v), or
- e halts with an error (ρ ⊢ e ⇓ halt(m)), or
- e diverges

**Preservation**: If `Γ ⊢ e : τ` and `ρ ⊢ e ⇓ v`, then v has type τ.

Note: These are conjectures for the MVP. Formal proofs are future work.

### 11.2 Turing Completeness (D1.24)

TANGLE is Turing complete via:
1. **Data**: Word values = inductively defined sequences (identity = nil, g . w = cons)
2. **Branching**: Pattern matching on Word structure
3. **Iteration**: General recursion on definitions (D1.3)

**Proof sketch**: Encode a Turing machine as:
- Tape alphabet → generator indices (s₁ = symbol 1, s₂ = symbol 2, ...)
- Tape = Word value (generator sequence)
- Head position = Num value
- Transition function = pattern match + recursion
- Halting state = base case in match

### 11.3 Totality of add{...} (D2.1)

Harvard data expressions (inside `add{...}`) are total:
- No loops (while/for excluded from grammar)
- No recursion (functions in Π are checked by the @pure/@total discipline)
- Conditional requires both branches
- All operations on finite data

Informal argument: The `⊢_hd` typing rules exclude all sources of non-termination.
A formal proof would show that `ρ_Π ⊢_hd he ⇓ hv` always holds (no divergence).

### 11.4 Soundness of Purity Restriction (D2.9)

If a Harvard function marked @pure calls only non-recursive TANGLE functions
(per HC-Call-Tangle-Pure), and the @pure function itself terminates, then:
- The combined call always terminates
- No side effects occur

This follows from:
1. Non-recursive TANGLE functions terminate on all inputs (no recursive calls)
2. @pure Harvard functions have no side effects by construction
3. Composition of terminating, effect-free computations terminates without effects

### 11.5 Coherence of Auto-Widening (D1.8.5)

Auto-widening preserves braid group semantics:

If w₁ ∈ B_n and w₂ ∈ B_m, then w₁ . w₂ is computed in B_{max(n,m)} via
the standard stabilization embedding ι : B_n → B_{n+1} which adds an
identity strand. This embedding is a group homomorphism:

```
ι(sᵢ) = sᵢ       (generators preserved)
ι(w₁ · w₂) = ι(w₁) · ι(w₂)       (homomorphism)
```

Therefore, auto-widening is sound: the isotopy class of the widened word
is the canonical image of the original word under stabilization.

---

## 12. Precedence Table (Complete)

Operator precedence from lowest to highest binding:

```
Precedence    Operator       Associativity    Domain
──────────    ────────       ─────────────    ──────
1 (lowest)    >>             left             Word, Tangle (sugar for .)
2             ==  ~          none             see §3.6
3             +  -           left             Num; + also Tangle[I,I]
4             *  /           left             Num
5             .              left             Word, Tangle (vertical composition)
6 (highest)   |              left             Word, Tangle (horizontal tensor)

Unary:        ~e             prefix           Word, Tangle (twist)
              -e             prefix           Num (negation)
```

In weave context, crossings `(a > b)` and `(a < b)` are atomic expressions
(fully parenthesized by syntax).

---

## Appendix A: Summary of Semantic Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `width(e)` | Expr → Nat | Maximum strand index + 1 |
| `πw` | Word → Permutation | Permutation induced by braid word |
| `isotopy(v₁, v₂)` | Value × Value → Bool | Equality in FR(T) |
| `reidemeister_reduce(w)` | Word → Word | Canonical form via Reidemeister moves |
| `match(v, p)` | Value × Pattern → Subst ∪ {fail} | Pattern matching |
| `Embed(hτ)` | HarvardType → TangleType | Type bridge Harvard → TANGLE |
| `Unembed(τ)` | TangleType → HarvardType | Type bridge TANGLE → Harvard |
| `embed_value(hv)` | HarvardValue → TangleValue | Value bridge Harvard → TANGLE |
| `is_recursive(def)` | Definition → Bool | Syntactic recursion check |
| `shift(g, k)` | Generator × Nat → Generator | Index shift for tensor |
| `swap(A, i, j)` | Boundary × Nat × Nat → Boundary | Position swap in boundary |
| `twist_generators(n)` | Nat → Word | Full twist braid on n strands |
| `close(t)` | Tangle → Tangle | Trace operation (close all strands) |
| `disjoint_union(t₁, t₂)` | Tangle × Tangle → Tangle | Disjoint union of closed tangles |

---

## Appendix B: Decision Traceability

Every rule in this document traces to a locked decision:

| Rule(s) | Decision |
|---------|----------|
| T-Identity, E-Identity | D1.14 (identity = Word[0]) |
| T-Braid, E-Braid | D1.1 (braid literals = Word[n]) |
| T-Compose-Word | D1.8.5 (auto-widening) |
| T-Add-Num, T-Add-Tangle | D1.6, D1.7 (+ overloaded, closed only) |
| T-Eq-*, T-Isotopy | D1.2 (two equalities) |
| T-Close-* | D1.17 (no permutation check) |
| T-Twist-* | D1.18 (context-dependent twist) |
| T-Match, P-*, E-Match-* | D1.3, D1.4 (recursion, exhaustiveness) |
| T-Let, E-Let | D1.4.5 (let scoping) |
| T-Weave | D1.9, D1.10, D1.11 (weave rules) |
| T-Add, E-Add | D2.1, D2.4 (three worlds, Embed) |
| HC-Call-Tangle-* | D2.9 (Harvard calling TANGLE) |
| T-Unembed, E-Unembed-* | D2.10 (reverse embedding) |
| T-Assert, E-Assert-* | D1.15, D1.15.1 (halt/panic, assert) |
| E-Simplify | D1.16 Tier 1 (simplify is primitive) |
| E-Pipeline | D1.20 (>> sugar for .) |
| T-Self-Cross | D1.19 (self-crossing = twist) |
| T-Program | D1.13 (two-pass) |
| E-App | D1.13.5 (call-by-value) |
| HD-*, EHD-* | D2.1, D2.3 (Harvard data, sequential Π) |
| HD-Compare, HD-And, HD-Or, HD-Not | D2.1 (total data grammar) |
| HD-Var, HD-Str, HD-Neg | D2.1 (data expression completeness) |
| T-Compute + result_type | D1.12, D1.16 (invariant computation) |

---

*End of formal semantics.*
