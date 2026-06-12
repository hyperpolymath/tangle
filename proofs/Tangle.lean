-- SPDX-License-Identifier: MPL-2.0
-- Tangle.lean — Mechanized type safety proofs for the TANGLE language core.
--
-- Models the core type system from docs/spec/FORMAL-SEMANTICS.md:
--   - Syntax: Expr inductive (26 constructors) with the de Bruijn Var and the
--     let binder Lett, plus Num, Str, Bool, Identity, BraidLit, Compose (.),
--     Tensor (|), Pipeline (>>), Close, Add, Eq, the echo constructors
--     EchoClose, Lower, Residue, EchoVal (structured loss), and the product
--     constructors Pair, Fst, Snd, EchoAdd, EchoEq
--   - Typing: HasType inductive relation (26 rules) covering T-Var, T-Let,
--     T-Num, T-Str, T-Bool, T-Identity, T-Braid, T-Compose-Word, T-Tensor-Word,
--     T-Pipeline, T-Close-Word, T-Add-Num, T-Eq-Word, T-Eq-Num, T-Eq-Str, the
--     echo rules T-Echo-Close, T-Lower, T-Residue, T-Echo-Val, the product
--     rules T-Pair, T-Fst, T-Snd, T-Echo-Add, and the echo-equality rules
--     T-Echo-Eq-Word, T-Echo-Eq-Num, T-Echo-Eq-Str.  Contexts are
--     `Ctx = List Ty` (de Bruijn); `Γ[i]?` (`List.getElem?`) looks up Var.
--   - Substitution: capture-avoiding de Bruijn `shift`/`subst` over all 22
--     value/operation constructors (TG-1).
--   - Semantics: Small-step Step relation (55 rules incl. echo + product +
--     the two let rules letStep / letRed)
--
-- Theorems proven:
--   1. Progress:     well-typed closed terms are values or can step
--   2. Preservation: stepping preserves types
--   3. Determinism:  if e ⟶ e₁ and e ⟶ e₂ then e₁ = e₂
--   4. Type Safety:  corollary combining progress and preservation
--   Plus the two metatheory lemmas WEAKENING (context insertion) and
--   SUBST_PRESERVES (the substitution lemma) underpinning let-reduction.
--   All cover the echo-types fragment, the product fragment, and let-binding.
--
-- Echo types (structured loss): `close : Word[n] → Word[0]` is TANGLE's
-- canonical lossy map.  The echo type former `Ty.echo ρ τ` and the
-- constructors `echoClose`/`lower`/`residue` integrate echo-types
-- (hyperpolymath/echo-types: `Echo f y := Σ (x : A), f x ≡ y`) directly into
-- the type system: closing a braid through an echo retains the residue, so the
-- otherwise-irreversible `close` becomes reversible at the type level.  The
-- product type `Ty.prod ρ σ` carries two further lossy operations, `echoAdd`
-- and `echoEq`: ordinary `add` discards which two numbers were summed, but
-- `echoAdd` keeps the summand pair as its residue (residue type `Num × Num`,
-- result `Num`); ordinary `eq` discards which two operands were compared, but
-- `echoEq` keeps the operand pair as its residue (residue type `ρ × ρ`, result
-- `Bool`), so distinct inputs that collapse to the same sum or boolean stay
-- distinguishable.  See the §ECHO-TYPES section at the foot of the file for the
-- residue-recovery and non-injectivity theorems (the `close`, `echoAdd`, and
-- `echoEq` forms).
--
-- TG-1 LANDED: variables + the `lett` binder, capture-avoiding de Bruijn
-- `shift`/`subst`, and the full substitution metatheory.  `weakening`
-- (context insertion) and `subst_preserves` (the substitution lemma) are
-- proved, and Progress / Preservation / Determinism / Type Safety + the
-- decidability layer (`infer`, `infer_sound`, `infer_complete`) all extend to
-- cover variables and let.  One honest deviation: `subst_preserves` carries
-- its substitutee `s` typed in the COMBINED context `Γ₁ ++ Γ₂` (the true
-- inductive invariant — the closed-context `HasType Γ₂ s σ` form is false for a
-- non-empty prefix); the `letRed` consumer uses `Γ₁ := []` where the two forms
-- coincide.  See the §METATHEORY comment block for the full rationale.
--
-- Developed for Lean 4. Tested against leanprover/lean4:v4.14.0.
--
-- Author: Jonathan D.A. Jewell, Claude

namespace Tangle

-- ═══════════════════════════════════════════════════════════════════════
-- SYNTAX
-- ═══════════════════════════════════════════════════════════════════════

/-- A braid generator σᵢ^{±1}: strand index i with exponent +1 or -1.
    Mirrors `generator` in compiler/lib/ast.ml. -/
structure Generator where
  idx : Nat
  exp : Int
  deriving DecidableEq, Repr

/-- Types in the core TANGLE language.
    Word[n] represents braid words on n strands (§2.1 of the spec). -/
inductive Ty where
  | num  : Ty              -- Num: integers and floats
  | str  : Ty              -- Str: strings
  | bool : Ty              -- Bool: booleans
  | word : Nat → Ty        -- Word[n]: braid word on n strands
  | echo : Ty → Ty → Ty    -- Echo[ρ, τ]: structured-loss type — a τ-result
                           --   carrying a ρ-typed residue.  The simply-typed
                           --   shadow of echo-types' `Echo f y := Σ (x : A), f x ≡ y`
                           --   (hyperpolymath/echo-types, Echo.agda): ρ is the
                           --   residue (domain witness x : A), τ is the result
                           --   (codomain point y).  See §ECHO-TYPES below.
  | prod : Ty → Ty → Ty     -- product (pair) type ρ × σ; residue carrier for lossy binary ops
  deriving DecidableEq, Repr

/-- Core expression AST. Mirrors the OCaml AST in compiler/lib/ast.ml.
    Uses de Bruijn indices (not needed for closed terms but included
    for completeness of the typing judgment). -/
inductive Expr where
  | var      : Nat → Expr                   -- de Bruijn variable
  | lett     : Expr → Expr → Expr           -- let _ = e₁ in e₂ (e₂ binds var 0)
  | num      : Int → Expr                   -- integer literal
  | str      : String → Expr                -- string literal
  | boolLit  : Bool → Expr                  -- boolean literal
  | identity : Expr                         -- identity element (Word[0])
  | braidLit : List Generator → Expr        -- braid literal [σ₁, σ₂⁻¹, ...]
  | compose  : Expr → Expr → Expr           -- vertical composition (.)
  | tensor   : Expr → Expr → Expr           -- horizontal tensor (|)
  | pipeline : Expr → Expr → Expr           -- pipeline (>>), sugar for (.)
  | close    : Expr → Expr                  -- closure
  | add      : Expr → Expr → Expr           -- numeric addition
  | eq       : Expr → Expr → Expr           -- structural equality
  -- Echo types (structured loss).  `close` is TANGLE's canonical lossy map
  -- (Word[n] ↠ Word[0]); these constructors give it a residue-retaining
  -- variant and the two projections, mirroring echo-types' fibre/residue API.
  -- A formed echo is the value `echoVal residue result`; `echoClose` is the
  -- redex that reduces into one, and `lower`/`residue` are its two projections.
  | echoClose : Expr → Expr                 -- echo-preserving closure (redex → echoVal)
  | lower     : Expr → Expr                 -- project an echo to its result (forget residue)
  | residue   : Expr → Expr                 -- project an echo to its residue (recover witness)
  | echoVal   : Expr → Expr → Expr          -- formed echo value: (residue, result)
  | pair    : Expr → Expr → Expr            -- product introduction
  | fst     : Expr → Expr                   -- first projection
  | snd     : Expr → Expr                   -- second projection
  | echoAdd : Expr → Expr → Expr            -- echo-preserving addition (residue = pair of summands)
  | echoEq : Expr → Expr → Expr          -- echo-preserving equality (residue = operand pair)
  deriving DecidableEq, Repr

/-- Value predicate: fully reduced expressions. -/
inductive IsValue : Expr → Prop where
  | num      : ∀ n, IsValue (.num n)
  | str      : ∀ s, IsValue (.str s)
  | boolLit  : ∀ b, IsValue (.boolLit b)
  | identity : IsValue .identity
  | braidLit : ∀ gs, IsValue (.braidLit gs)
  | echoVal : ∀ {r v}, IsValue r → IsValue v → IsValue (.echoVal r v)  -- a formed echo value (residue r, result v)
  | pair : ∀ {a b}, IsValue a → IsValue b → IsValue (.pair a b)

-- ═══════════════════════════════════════════════════════════════════════
-- WIDTH
-- ═══════════════════════════════════════════════════════════════════════

/-- Width of a generator list: max(index + 1) across all generators.
    Corresponds to the width function in §2.5 of the spec. -/
def generatorWidth (gs : List Generator) : Nat :=
  gs.foldl (fun acc g => max acc (g.idx + 1)) 0

/-- Shift all generator indices by n (for tensor product).
    shift(σᵢ, k) = σ_{i+k} per §4.6. -/
def shiftGenerators (gs : List Generator) (n : Nat) : List Generator :=
  gs.map fun g => { g with idx := g.idx + n }

-- ═══════════════════════════════════════════════════════════════════════
-- DE BRUIJN SUBSTITUTION MACHINERY
-- ═══════════════════════════════════════════════════════════════════════
--
-- Standard POPLmark substitution operators on de Bruijn terms.  `shift d c e`
-- lifts every free variable of `e` whose index is ≥ the cutoff `c` by `d`
-- (used to move a term under `d` extra binders).  `subst j s e` replaces the
-- variable at index `j` by `s`, decrements every free variable > `j` (the
-- binder being eliminated disappears), and shifts `s` by one under each binder
-- it crosses.  Both recurse uniformly through every `Expr` constructor.

/-- de Bruijn shift: lift free variables ≥ cutoff `c` by `d`. -/
def shift (d : Nat) (c : Nat) : Expr → Expr
  | .var k       => if k < c then .var k else .var (k + d)
  | .lett e₁ e₂  => .lett (shift d c e₁) (shift d (c+1) e₂)
  | .num n       => .num n
  | .str s       => .str s
  | .boolLit b   => .boolLit b
  | .identity    => .identity
  | .braidLit gs => .braidLit gs
  | .compose a b => .compose (shift d c a) (shift d c b)
  | .tensor a b  => .tensor (shift d c a) (shift d c b)
  | .pipeline a b => .pipeline (shift d c a) (shift d c b)
  | .close a     => .close (shift d c a)
  | .add a b     => .add (shift d c a) (shift d c b)
  | .eq a b      => .eq (shift d c a) (shift d c b)
  | .echoClose a => .echoClose (shift d c a)
  | .lower a     => .lower (shift d c a)
  | .residue a   => .residue (shift d c a)
  | .echoVal a b => .echoVal (shift d c a) (shift d c b)
  | .pair a b    => .pair (shift d c a) (shift d c b)
  | .fst a       => .fst (shift d c a)
  | .snd a       => .snd (shift d c a)
  | .echoAdd a b => .echoAdd (shift d c a) (shift d c b)
  | .echoEq a b  => .echoEq (shift d c a) (shift d c b)

/-- de Bruijn substitution: replace variable `j` by `s`, decrement vars > `j`,
    shift `s` under binders. -/
def subst (j : Nat) (s : Expr) : Expr → Expr
  | .var k       => if k < j then .var k else if k = j then s else .var (k - 1)
  | .lett e₁ e₂  => .lett (subst j s e₁) (subst (j+1) (shift 1 0 s) e₂)
  | .num n       => .num n
  | .str t       => .str t
  | .boolLit b   => .boolLit b
  | .identity    => .identity
  | .braidLit gs => .braidLit gs
  | .compose a b => .compose (subst j s a) (subst j s b)
  | .tensor a b  => .tensor (subst j s a) (subst j s b)
  | .pipeline a b => .pipeline (subst j s a) (subst j s b)
  | .close a     => .close (subst j s a)
  | .add a b     => .add (subst j s a) (subst j s b)
  | .eq a b      => .eq (subst j s a) (subst j s b)
  | .echoClose a => .echoClose (subst j s a)
  | .lower a     => .lower (subst j s a)
  | .residue a   => .residue (subst j s a)
  | .echoVal a b => .echoVal (subst j s a) (subst j s b)
  | .pair a b    => .pair (subst j s a) (subst j s b)
  | .fst a       => .fst (subst j s a)
  | .snd a       => .snd (subst j s a)
  | .echoAdd a b => .echoAdd (subst j s a) (subst j s b)
  | .echoEq a b  => .echoEq (subst j s a) (subst j s b)

-- ═══════════════════════════════════════════════════════════════════════
-- TYPING JUDGMENT
-- ═══════════════════════════════════════════════════════════════════════

/-- Typing context (de Bruijn indexed). -/
abbrev Ctx := List Ty

/-- Typing judgment: Γ ⊢ e : τ.
    Encodes the rules from §3 of FORMAL-SEMANTICS.md. -/
inductive HasType : Ctx → Expr → Ty → Prop where
  | tNum (Γ : Ctx) (n : Int) :                              -- [T-Num]
      HasType Γ (.num n) .num
  | tStr (Γ : Ctx) (s : String) :                            -- [T-Str]
      HasType Γ (.str s) .str
  | tBool (Γ : Ctx) (b : Bool) :                             -- [T-Bool]
      HasType Γ (.boolLit b) .bool
  | tIdentity (Γ : Ctx) :                                    -- [T-Identity]
      HasType Γ .identity (.word 0)
  | tBraid (Γ : Ctx) (gs : List Generator) :                 -- [T-Braid]
      HasType Γ (.braidLit gs) (.word (generatorWidth gs))
  | tComposeWord (Γ : Ctx) (e₁ e₂ : Expr) (n m : Nat) :     -- [T-Compose-Word]
      HasType Γ e₁ (.word n) →
      HasType Γ e₂ (.word m) →
      HasType Γ (.compose e₁ e₂) (.word (max n m))
  | tTensorWord (Γ : Ctx) (e₁ e₂ : Expr) (n m : Nat) :      -- [T-Tensor-Word]
      HasType Γ e₁ (.word n) →
      HasType Γ e₂ (.word m) →
      HasType Γ (.tensor e₁ e₂) (.word (n + m))
  | tPipeline (Γ : Ctx) (e₁ e₂ : Expr) (τ : Ty) :           -- [T-Pipeline]
      HasType Γ (.compose e₁ e₂) τ →
      HasType Γ (.pipeline e₁ e₂) τ
  | tCloseWord (Γ : Ctx) (e : Expr) (n : Nat) :              -- [T-Close-Word]
      HasType Γ e (.word n) →
      HasType Γ (.close e) (.word 0)
  | tAddNum (Γ : Ctx) (e₁ e₂ : Expr) :                      -- [T-Add-Num]
      HasType Γ e₁ .num →
      HasType Γ e₂ .num →
      HasType Γ (.add e₁ e₂) .num
  | tEqWord (Γ : Ctx) (e₁ e₂ : Expr) (n : Nat) :            -- [T-Eq-Word]
      HasType Γ e₁ (.word n) →
      HasType Γ e₂ (.word n) →
      HasType Γ (.eq e₁ e₂) .bool
  | tEqNum (Γ : Ctx) (e₁ e₂ : Expr) :                       -- [T-Eq-Num]
      HasType Γ e₁ .num →
      HasType Γ e₂ .num →
      HasType Γ (.eq e₁ e₂) .bool
  | tEqStr (Γ : Ctx) (e₁ e₂ : Expr) :                       -- [T-Eq-Str]
      HasType Γ e₁ .str →
      HasType Γ e₂ .str →
      HasType Γ (.eq e₁ e₂) .bool
  | tEchoClose (Γ : Ctx) (e : Expr) (n : Nat) :             -- [T-Echo-Close]
      HasType Γ e (.word n) →                               --   echo-intro for `close`:
      HasType Γ (.echoClose e) (.echo (.word n) (.word 0))  --   residue Word[n], result Word[0]
  | tLower (Γ : Ctx) (e : Expr) (ρ τ : Ty) :                -- [T-Lower]  (project to result)
      HasType Γ e (.echo ρ τ) →
      HasType Γ (.lower e) τ
  | tResidue (Γ : Ctx) (e : Expr) (ρ τ : Ty) :              -- [T-Residue] (recover witness)
      HasType Γ e (.echo ρ τ) →
      HasType Γ (.residue e) ρ
  | tEchoVal (Γ : Ctx) (r v : Expr) (ρ τ : Ty) :            -- [T-Echo-Val]
      HasType Γ r ρ →
      HasType Γ v τ →
      HasType Γ (.echoVal r v) (.echo ρ τ)
  | tPair (Γ : Ctx) (a b : Expr) (α β : Ty) :               -- [T-Pair]
      HasType Γ a α → HasType Γ b β → HasType Γ (.pair a b) (.prod α β)
  | tFst (Γ : Ctx) (e : Expr) (α β : Ty) :                  -- [T-Fst]
      HasType Γ e (.prod α β) → HasType Γ (.fst e) α
  | tSnd (Γ : Ctx) (e : Expr) (α β : Ty) :                  -- [T-Snd]
      HasType Γ e (.prod α β) → HasType Γ (.snd e) β
  | tEchoAdd (Γ : Ctx) (e₁ e₂ : Expr) :                     -- [T-Echo-Add]
      HasType Γ e₁ .num → HasType Γ e₂ .num →
      HasType Γ (.echoAdd e₁ e₂) (.echo (.prod .num .num) .num)
  | tEchoEqWord (Γ : Ctx) (e₁ e₂ : Expr) (n : Nat) :       -- [T-Echo-Eq-Word]
      HasType Γ e₁ (.word n) → HasType Γ e₂ (.word n) →
      HasType Γ (.echoEq e₁ e₂) (.echo (.prod (.word n) (.word n)) .bool)
  | tEchoEqNum (Γ : Ctx) (e₁ e₂ : Expr) :                  -- [T-Echo-Eq-Num]
      HasType Γ e₁ .num → HasType Γ e₂ .num →
      HasType Γ (.echoEq e₁ e₂) (.echo (.prod .num .num) .bool)
  | tEchoEqStr (Γ : Ctx) (e₁ e₂ : Expr) :                  -- [T-Echo-Eq-Str]
      HasType Γ e₁ .str → HasType Γ e₂ .str →
      HasType Γ (.echoEq e₁ e₂) (.echo (.prod .str .str) .bool)
  | tVar (Γ : Ctx) (i : Nat) (τ : Ty) :                    -- [T-Var]
      Γ[i]? = some τ → HasType Γ (.var i) τ
  | tLet (Γ : Ctx) (e₁ e₂ : Expr) (σ τ : Ty) :             -- [T-Let]
      HasType Γ e₁ σ → HasType (σ :: Γ) e₂ τ →
      HasType Γ (.lett e₁ e₂) τ

-- ═══════════════════════════════════════════════════════════════════════
-- SMALL-STEP SEMANTICS
-- ═══════════════════════════════════════════════════════════════════════

/-- Small-step reduction relation e ⟶ e'.
    Encodes the evaluation rules from §4 of FORMAL-SEMANTICS.md. -/
inductive Step : Expr → Expr → Prop where
  -- Compose: congruence
  | composeLeft  : Step e₁ e₁' → Step (.compose e₁ e₂) (.compose e₁' e₂)
  | composeRight : IsValue e₁ → Step e₂ e₂' → Step (.compose e₁ e₂) (.compose e₁ e₂')
  -- Compose: computation (E-Compose-Word, etc.)
  | composeWords : Step (.compose (.braidLit gs₁) (.braidLit gs₂)) (.braidLit (gs₁ ++ gs₂))
  | composeIdL   : Step (.compose .identity (.braidLit gs)) (.braidLit gs)
  | composeIdR   : Step (.compose (.braidLit gs) .identity) (.braidLit gs)
  | composeIdId  : Step (.compose .identity .identity) .identity
  -- Tensor: congruence
  | tensorLeft   : Step e₁ e₁' → Step (.tensor e₁ e₂) (.tensor e₁' e₂)
  | tensorRight  : IsValue e₁ → Step e₂ e₂' → Step (.tensor e₁ e₂) (.tensor e₁ e₂')
  -- Tensor: computation (E-Tensor-Word)
  | tensorWords  : Step (.tensor (.braidLit gs₁) (.braidLit gs₂))
                        (.braidLit (gs₁ ++ shiftGenerators gs₂ (generatorWidth gs₁)))
  | tensorIdL    : Step (.tensor .identity (.braidLit gs)) (.braidLit gs)
  | tensorIdR    : Step (.tensor (.braidLit gs) .identity) (.braidLit gs)
  | tensorIdId   : Step (.tensor .identity .identity) .identity
  -- Pipeline desugaring (E-Pipeline)
  | pipeline     : Step (.pipeline e₁ e₂) (.compose e₁ e₂)
  -- Close (E-Close-Word)
  | closeStep    : Step e e' → Step (.close e) (.close e')
  | closeWord    : Step (.close (.braidLit gs)) .identity
  | closeId      : Step (.close .identity) .identity
  -- Add (E-Add-Num)
  | addLeft      : Step e₁ e₁' → Step (.add e₁ e₂) (.add e₁' e₂)
  | addRight     : IsValue e₁ → Step e₂ e₂' → Step (.add e₁ e₂) (.add e₁ e₂')
  | addNums      : Step (.add (.num n₁) (.num n₂)) (.num (n₁ + n₂))
  -- Eq (E-Eq-Word, E-Eq-Num, E-Eq-Str)
  | eqLeft       : Step e₁ e₁' → Step (.eq e₁ e₂) (.eq e₁' e₂)
  | eqRight      : IsValue e₁ → Step e₂ e₂' → Step (.eq e₁ e₂) (.eq e₁ e₂')
  | eqNums       : Step (.eq (.num n₁) (.num n₂)) (.boolLit (n₁ == n₂))
  | eqStrs       : Step (.eq (.str s₁) (.str s₂)) (.boolLit (s₁ == s₂))
  | eqBraids     : Step (.eq (.braidLit gs₁) (.braidLit gs₂)) (.boolLit (gs₁ == gs₂))
  | eqIdId       : Step (.eq .identity .identity) (.boolLit true)
  | eqIdBraid    : Step (.eq .identity (.braidLit gs)) (.boolLit (gs == []))
  | eqBraidId    : Step (.eq (.braidLit gs) .identity) (.boolLit (gs == []))
  -- Echo (structured loss): `echoClose` is a redex that reduces into a formed
  -- echo value `echoVal residue result`; `lower`/`residue` are the two generic
  -- projections off a formed echo value.  `lower` yields the result component
  -- (the codomain point identity : Word[0]); `residue` recovers the witness
  -- braid retained in the residue component — the fibre element echo-types keeps.
  | echoCloseStep : Step e e' → Step (.echoClose e) (.echoClose e')
  | echoCloseWord : Step (.echoClose (.braidLit gs)) (.echoVal (.braidLit gs) .identity)
  | echoCloseId   : Step (.echoClose .identity) (.echoVal .identity .identity)
  | echoValLeft   : Step r r' → Step (.echoVal r v) (.echoVal r' v)
  | echoValRight  : IsValue r → Step v v' → Step (.echoVal r v) (.echoVal r v')
  | lowerStep     : Step e e' → Step (.lower e) (.lower e')
  | lowerVal      : IsValue r → IsValue v → Step (.lower (.echoVal r v)) v
  | residueStep   : Step e e' → Step (.residue e) (.residue e')
  | residueVal    : IsValue r → IsValue v → Step (.residue (.echoVal r v)) r
  -- Product: congruence + projections
  | pairLeft   : Step a a' → Step (.pair a b) (.pair a' b)
  | pairRight  : IsValue a → Step b b' → Step (.pair a b) (.pair a b')
  | fstStep    : Step e e' → Step (.fst e) (.fst e')
  | fstPair    : IsValue a → IsValue b → Step (.fst (.pair a b)) a
  | sndStep    : Step e e' → Step (.snd e) (.snd e')
  | sndPair    : IsValue a → IsValue b → Step (.snd (.pair a b)) b
  -- Echo-preserving addition: residue retains the summand pair; result is the sum.
  | echoAddLeft  : Step e₁ e₁' → Step (.echoAdd e₁ e₂) (.echoAdd e₁' e₂)
  | echoAddRight : IsValue e₁ → Step e₂ e₂' → Step (.echoAdd e₁ e₂) (.echoAdd e₁ e₂')
  | echoAddNums  : Step (.echoAdd (.num n₁) (.num n₂))
                        (.echoVal (.pair (.num n₁) (.num n₂)) (.num (n₁ + n₂)))
  -- Echo-preserving equality: residue retains the operand pair; result is the
  -- boolean.  Mirrors the 8 `eq` rules; each computation produces
  -- `echoVal (pair <operands>) (boolLit <same bool as the matching eq rule>)`.
  | echoEqLeft    : Step e₁ e₁' → Step (.echoEq e₁ e₂) (.echoEq e₁' e₂)
  | echoEqRight   : IsValue e₁ → Step e₂ e₂' → Step (.echoEq e₁ e₂) (.echoEq e₁ e₂')
  | echoEqNums    : Step (.echoEq (.num n₁) (.num n₂))
                        (.echoVal (.pair (.num n₁) (.num n₂)) (.boolLit (n₁ == n₂)))
  | echoEqStrs    : Step (.echoEq (.str s₁) (.str s₂))
                        (.echoVal (.pair (.str s₁) (.str s₂)) (.boolLit (s₁ == s₂)))
  | echoEqBraids  : Step (.echoEq (.braidLit gs₁) (.braidLit gs₂))
                        (.echoVal (.pair (.braidLit gs₁) (.braidLit gs₂)) (.boolLit (gs₁ == gs₂)))
  | echoEqIdId    : Step (.echoEq .identity .identity)
                        (.echoVal (.pair .identity .identity) (.boolLit true))
  | echoEqIdBraid : Step (.echoEq .identity (.braidLit gs))
                        (.echoVal (.pair .identity (.braidLit gs)) (.boolLit (gs == [])))
  | echoEqBraidId : Step (.echoEq (.braidLit gs) .identity)
                        (.echoVal (.pair (.braidLit gs) .identity) (.boolLit (gs == [])))
  -- Let-binding: congruence on the bound expression, then β-reduction once it
  -- is a value (the bound value is substituted into the body's variable 0).
  | letStep : Step e₁ e₁' → Step (.lett e₁ e₂) (.lett e₁' e₂)
  | letRed  : IsValue v → Step (.lett v e₂) (subst 0 v e₂)

-- ═══════════════════════════════════════════════════════════════════════
-- LEMMAS
-- ═══════════════════════════════════════════════════════════════════════

/-- Values are in normal form.  Recursive on the value structure because a
    formed echo value `echoVal r v` is a value exactly when both components are. -/
theorem value_no_step {e e' : Expr} (hv : IsValue e) (hs : Step e e') : False := by
  induction hv generalizing e' with
  | echoVal _ _ ihr ihv => cases hs with
    | echoValLeft h => exact ihr h
    | echoValRight _ h => exact ihv h
  | pair _ _ iha ihb => cases hs with
    | pairLeft h => exact iha h
    | pairRight _ h => exact ihb h
  | _ => cases hs

/-- Canonical forms for Num. -/
theorem canonical_num : IsValue e → HasType [] e .num → ∃ n, e = .num n := by
  intro hv ht; cases hv <;> cases ht; exact ⟨_, rfl⟩

/-- Canonical forms for Str. -/
theorem canonical_str : IsValue e → HasType [] e .str → ∃ s, e = .str s := by
  intro hv ht; cases hv <;> cases ht; exact ⟨_, rfl⟩

/-- Canonical forms for Word[n]. -/
theorem canonical_word : IsValue e → HasType [] e (.word n) →
    (e = .identity ∧ n = 0) ∨ (∃ gs, e = .braidLit gs ∧ n = generatorWidth gs) := by
  intro hv ht
  cases hv with
  | num => cases ht
  | str => cases ht
  | boolLit => cases ht
  | identity => left; cases ht with | tIdentity => exact ⟨rfl, rfl⟩
  | braidLit gs => right; cases ht with | tBraid => exact ⟨gs, rfl, rfl⟩
  | echoVal _ _ => cases ht
  | pair _ _ => cases ht

/-- Canonical forms for Echo[ρ, τ]: a value of echo type is a formed echo value
    `echoVal r v` whose residue `r` and result `v` are themselves values.  This
    is the canonical form that lets `lower`/`residue` make progress. -/
theorem canonical_echo : IsValue e → HasType [] e (.echo ρ τ) →
    ∃ r v, e = .echoVal r v ∧ IsValue r ∧ IsValue v := by
  intro hv ht
  cases hv with
  | num => cases ht
  | str => cases ht
  | boolLit => cases ht
  | identity => cases ht
  | braidLit => cases ht
  | echoVal hr hv => exact ⟨_, _, rfl, hr, hv⟩
  | pair _ _ => cases ht

/-- Canonical forms for products: a value of product type is a `pair a b` whose
    components `a` and `b` are themselves values.  This is the canonical form
    that lets `fst`/`snd` make progress. -/
theorem canonical_prod : IsValue e → HasType [] e (.prod α β) →
    ∃ a b, e = .pair a b ∧ IsValue a ∧ IsValue b := by
  intro hv ht
  cases hv with
  | num => cases ht
  | str => cases ht
  | boolLit => cases ht
  | identity => cases ht
  | braidLit => cases ht
  | echoVal _ _ => cases ht
  | pair ha hb => exact ⟨_, _, rfl, ha, hb⟩

-- Width distribution lemmas
private theorem foldl_max_init (gs : List Generator) (a : Nat) :
    gs.foldl (fun acc g => max acc (g.idx + 1)) a =
    max a (gs.foldl (fun acc g => max acc (g.idx + 1)) 0) := by
  induction gs generalizing a with
  | nil => simp [List.foldl]
  | cons g rest ih =>
    simp only [List.foldl]
    rw [ih (max a (g.idx + 1)), ih (max 0 (g.idx + 1))]
    omega

theorem generatorWidth_append (gs₁ gs₂ : List Generator) :
    generatorWidth (gs₁ ++ gs₂) = max (generatorWidth gs₁) (generatorWidth gs₂) := by
  simp only [generatorWidth, List.foldl_append]; rw [foldl_max_init]

private theorem foldl_shift_init (gs : List Generator) (n a : Nat) :
    (gs.map fun g => { idx := g.idx + n, exp := g.exp : Generator}).foldl
      (fun acc g => max acc (g.idx + 1)) a =
    if gs = [] then a
    else max a (gs.foldl (fun acc g => max acc (g.idx + 1)) 0 + n) := by
  induction gs generalizing a with
  | nil => simp
  | cons g rest ih =>
    simp only [List.map, List.foldl, List.cons_ne_nil, if_false]
    rw [ih]
    rw [foldl_max_init rest (max 0 (g.idx + 1))]
    by_cases hrest : rest = []
    · subst hrest; simp [List.foldl]; omega
    · simp [hrest]; omega

theorem generatorWidth_shift (gs : List Generator) (n : Nat) :
    generatorWidth (shiftGenerators gs n) =
    if gs = [] then 0 else generatorWidth gs + n := by
  simp only [generatorWidth, shiftGenerators]; rw [foldl_shift_init]
  split <;> simp_all

-- ═══════════════════════════════════════════════════════════════════════
-- METATHEORY: WEAKENING + SUBSTITUTION (TG-1)
-- ═══════════════════════════════════════════════════════════════════════
--
-- The two structural lemmas underpinning `let`-binding.  `weakening` inserts a
-- fresh hypothesis `σ` at position `Γ₁.length` (shifting the term to skip the
-- new binder); `subst_preserves` is the substitution lemma — typing is closed
-- under replacing the variable at `Γ₁.length` by a term `s` of its type.
--
-- Implementation notes (deviations from the naive POPLmark recipe):
--   * Variable lookup uses `Γ[i]?` (`List.getElem?`), not the deprecated
--     `List.get?`, so the append splits go through `List.getElem?_append_left`
--     / `List.getElem?_append_right`.
--   * Each derivation is taken apart with a bare `cases h` followed by
--     `rename_i`, rather than `cases h with | tCtor …`.  Under
--     `induction e`, the binder/index arguments of `tVar`/`tLet` are unified
--     with the surrounding context, so the positional `with`-arm naming does
--     not line up; `rename_i` names exactly the residual hypotheses.
--   * `subst_preserves` carries the hypothesis `s` typed in the COMBINED
--     context `Γ₁ ++ Γ₂` (not merely `Γ₂`).  This is the genuine inductive
--     invariant: the naive `HasType Γ₂ s σ` form is *false* for a non-empty
--     prefix (e.g. `Γ₁ = [α]`, `s = .var 0` pointing into `Γ₂`).  The `letRed`
--     consumer instantiates `Γ₁ := []`, where `Γ₁ ++ Γ₂ = Γ₂`, so it still
--     accepts a closed-context premise directly.  Because `s` is already in
--     the combined context, the `var = Γ₁.length` case closes by `exact hs`
--     and no separate `front_weakening` / shift-composition lemma is needed.

/-- **Weakening (insertion)**: inserting a fresh hypothesis `σ` at de Bruijn
    position `Γ₁.length` preserves typing, provided the term is shifted to
    skip the new binder. -/
theorem weakening {Γ₁ Γ₂ : Ctx} {e : Expr} {τ σ : Ty} :
    HasType (Γ₁ ++ Γ₂) e τ → HasType (Γ₁ ++ σ :: Γ₂) (shift 1 Γ₁.length e) τ := by
  intro h
  induction e generalizing Γ₁ τ with
  | var k =>
    cases h; rename_i hi; simp only [shift]
    by_cases hk : k < Γ₁.length
    · simp only [hk, if_true]
      rw [List.getElem?_append_left hk] at hi
      exact .tVar _ _ _ (by rw [List.getElem?_append_left hk]; exact hi)
    · simp only [hk, if_false]
      rw [List.getElem?_append_right (by omega)] at hi
      refine .tVar _ _ _ ?_
      rw [List.getElem?_append_right (by omega)]
      have hrw : k + 1 - Γ₁.length = (k - Γ₁.length) + 1 := by omega
      rw [hrw]; simpa using hi
  | lett e₁ e₂ ih₁ ih₂ =>
    cases h; rename_i a h₁ h₂; simp only [shift]
    refine .tLet _ _ _ a _ (ih₁ h₁) ?_
    have hr := ih₂ (Γ₁ := a :: Γ₁) h₂
    simpa using hr
  | num _ => cases h; exact .tNum _ _
  | str _ => cases h; exact .tStr _ _
  | boolLit _ => cases h; exact .tBool _ _
  | identity => cases h; exact .tIdentity _
  | braidLit _ => cases h; exact .tBraid _ _
  | compose a b iha ihb =>
    cases h; rename_i n m h₁ h₂; simp only [shift]; exact .tComposeWord _ _ _ n m (iha h₁) (ihb h₂)
  | tensor a b iha ihb =>
    cases h; rename_i n m h₁ h₂; simp only [shift]; exact .tTensorWord _ _ _ n m (iha h₁) (ihb h₂)
  | pipeline a b iha ihb =>
    cases h; rename_i hc; simp only [shift]
    cases hc; rename_i n m h₁ h₂
    exact .tPipeline _ _ _ _ (.tComposeWord _ _ _ n m (iha h₁) (ihb h₂))
  | close a iha =>
    cases h; rename_i n h₁; simp only [shift]; exact .tCloseWord _ _ n (iha h₁)
  | add a b iha ihb =>
    cases h; rename_i h₁ h₂; simp only [shift]; exact .tAddNum _ _ _ (iha h₁) (ihb h₂)
  | eq a b iha ihb =>
    cases h <;> simp only [shift]
    · rename_i n h₁ h₂; exact .tEqWord _ _ _ n (iha h₁) (ihb h₂)
    · rename_i h₁ h₂; exact .tEqNum _ _ _ (iha h₁) (ihb h₂)
    · rename_i h₁ h₂; exact .tEqStr _ _ _ (iha h₁) (ihb h₂)
  | echoClose a iha =>
    cases h; rename_i n h₁; simp only [shift]; exact .tEchoClose _ _ n (iha h₁)
  | lower a iha =>
    cases h; rename_i ρ h₁; simp only [shift]; exact .tLower _ _ ρ _ (iha h₁)
  | residue a iha =>
    cases h; rename_i τ' h₁; simp only [shift]; exact .tResidue _ _ _ τ' (iha h₁)
  | echoVal a b iha ihb =>
    cases h; rename_i ρ τ' h₁ h₂; simp only [shift]; exact .tEchoVal _ _ _ ρ τ' (iha h₁) (ihb h₂)
  | pair a b iha ihb =>
    cases h; rename_i α β h₁ h₂; simp only [shift]; exact .tPair _ _ _ α β (iha h₁) (ihb h₂)
  | fst a iha =>
    cases h; rename_i β h₁; simp only [shift]; exact .tFst _ _ _ β (iha h₁)
  | snd a iha =>
    cases h; rename_i α h₁; simp only [shift]; exact .tSnd _ _ α _ (iha h₁)
  | echoAdd a b iha ihb =>
    cases h; rename_i h₁ h₂; simp only [shift]; exact .tEchoAdd _ _ _ (iha h₁) (ihb h₂)
  | echoEq a b iha ihb =>
    cases h <;> simp only [shift]
    · rename_i n h₁ h₂; exact .tEchoEqWord _ _ _ n (iha h₁) (ihb h₂)
    · rename_i h₁ h₂; exact .tEchoEqNum _ _ _ (iha h₁) (ihb h₂)
    · rename_i h₁ h₂; exact .tEchoEqStr _ _ _ (iha h₁) (ihb h₂)

/-- **Substitution**: typing is preserved by substituting the variable at de
    Bruijn position `Γ₁.length` by a term `s` of its type, with `s` taken in
    the combined context `Γ₁ ++ Γ₂` (the inductive invariant; see note above). -/
theorem subst_preserves {Γ₁ Γ₂ : Ctx} {e s : Expr} {τ σ : Ty} :
    HasType (Γ₁ ++ σ :: Γ₂) e τ → HasType (Γ₁ ++ Γ₂) s σ →
    HasType (Γ₁ ++ Γ₂) (subst Γ₁.length s e) τ := by
  intro h hs
  induction e generalizing Γ₁ s τ with
  | var k =>
    cases h; rename_i hi; simp only [subst]
    by_cases hlt : k < Γ₁.length
    · simp only [hlt, if_true]
      rw [List.getElem?_append_left hlt] at hi
      exact .tVar _ _ _ (by rw [List.getElem?_append_left hlt]; exact hi)
    · by_cases heq : k = Γ₁.length
      · subst heq
        simp only [Nat.lt_irrefl, if_false]
        rw [List.getElem?_append_right (by omega)] at hi
        simp only [Nat.sub_self, List.getElem?_cons_zero, Option.some.injEq] at hi
        subst hi; exact hs
      · simp only [hlt, if_false, heq, if_false]
        rw [List.getElem?_append_right (by omega)] at hi
        refine .tVar _ _ _ ?_
        rw [List.getElem?_append_right (by omega)]
        have e1 : k - Γ₁.length = (k - 1 - Γ₁.length) + 1 := by omega
        rw [e1] at hi; simpa using hi
  | lett e₁ e₂ ih₁ ih₂ =>
    cases h; rename_i a h₁ h₂; simp only [subst]
    refine .tLet _ _ _ a _ (ih₁ h₁ hs) ?_
    have hws : HasType ((a :: Γ₁) ++ Γ₂) (shift 1 0 s) σ := by
      have hw := weakening (Γ₁ := []) (σ := a) hs
      simpa using hw
    have hr := ih₂ (Γ₁ := a :: Γ₁) (s := shift 1 0 s) h₂ hws
    simpa using hr
  | num _ => cases h; exact .tNum _ _
  | str _ => cases h; exact .tStr _ _
  | boolLit _ => cases h; exact .tBool _ _
  | identity => cases h; exact .tIdentity _
  | braidLit _ => cases h; exact .tBraid _ _
  | compose a b iha ihb =>
    cases h; rename_i n m h₁ h₂; simp only [subst]; exact .tComposeWord _ _ _ n m (iha h₁ hs) (ihb h₂ hs)
  | tensor a b iha ihb =>
    cases h; rename_i n m h₁ h₂; simp only [subst]; exact .tTensorWord _ _ _ n m (iha h₁ hs) (ihb h₂ hs)
  | pipeline a b iha ihb =>
    cases h; rename_i hc; simp only [subst]
    cases hc; rename_i n m h₁ h₂
    exact .tPipeline _ _ _ _ (.tComposeWord _ _ _ n m (iha h₁ hs) (ihb h₂ hs))
  | close a iha =>
    cases h; rename_i n h₁; simp only [subst]; exact .tCloseWord _ _ n (iha h₁ hs)
  | add a b iha ihb =>
    cases h; rename_i h₁ h₂; simp only [subst]; exact .tAddNum _ _ _ (iha h₁ hs) (ihb h₂ hs)
  | eq a b iha ihb =>
    cases h <;> simp only [subst]
    · rename_i n h₁ h₂; exact .tEqWord _ _ _ n (iha h₁ hs) (ihb h₂ hs)
    · rename_i h₁ h₂; exact .tEqNum _ _ _ (iha h₁ hs) (ihb h₂ hs)
    · rename_i h₁ h₂; exact .tEqStr _ _ _ (iha h₁ hs) (ihb h₂ hs)
  | echoClose a iha =>
    cases h; rename_i n h₁; simp only [subst]; exact .tEchoClose _ _ n (iha h₁ hs)
  | lower a iha =>
    cases h; rename_i ρ h₁; simp only [subst]; exact .tLower _ _ ρ _ (iha h₁ hs)
  | residue a iha =>
    cases h; rename_i τ' h₁; simp only [subst]; exact .tResidue _ _ _ τ' (iha h₁ hs)
  | echoVal a b iha ihb =>
    cases h; rename_i ρ τ' h₁ h₂; simp only [subst]; exact .tEchoVal _ _ _ ρ τ' (iha h₁ hs) (ihb h₂ hs)
  | pair a b iha ihb =>
    cases h; rename_i α β h₁ h₂; simp only [subst]; exact .tPair _ _ _ α β (iha h₁ hs) (ihb h₂ hs)
  | fst a iha =>
    cases h; rename_i β h₁; simp only [subst]; exact .tFst _ _ _ β (iha h₁ hs)
  | snd a iha =>
    cases h; rename_i α h₁; simp only [subst]; exact .tSnd _ _ α _ (iha h₁ hs)
  | echoAdd a b iha ihb =>
    cases h; rename_i h₁ h₂; simp only [subst]; exact .tEchoAdd _ _ _ (iha h₁ hs) (ihb h₂ hs)
  | echoEq a b iha ihb =>
    cases h <;> simp only [subst]
    · rename_i n h₁ h₂; exact .tEchoEqWord _ _ _ n (iha h₁ hs) (ihb h₂ hs)
    · rename_i h₁ h₂; exact .tEchoEqNum _ _ _ (iha h₁ hs) (ihb h₂ hs)
    · rename_i h₁ h₂; exact .tEchoEqStr _ _ _ (iha h₁ hs) (ihb h₂ hs)

-- ═══════════════════════════════════════════════════════════════════════
-- THEOREM 1: PROGRESS
-- ═══════════════════════════════════════════════════════════════════════

/-- **Progress**: Every well-typed closed term is either a value or can
    take a step. This is the standard progress theorem from TAPL §8. -/
theorem progress : HasType [] e τ → IsValue e ∨ ∃ e', Step e e' := by
  -- Recurse structurally on the expression (the typing derivation cannot drive
  -- structural recursion once `tLet` is present, since its body premise lives
  -- in an extended context).  Each constructor inverts the typing hypothesis;
  -- the recursive `progress` calls become the Expr induction hypotheses.
  intro ht
  induction e generalizing τ with
  | var k => cases ht; rename_i hi; simp at hi  -- vacuous: `[][i]? = some τ`
  | lett e₁ e₂ ih₁ _ =>
    cases ht; rename_i h₁ h₂
    right
    rcases ih₁ h₁ with hv | ⟨e₁', hs⟩
    · exact ⟨_, .letRed hv⟩
    · exact ⟨_, .letStep hs⟩
  | num _ => cases ht; left; exact .num _
  | str _ => cases ht; left; exact .str _
  | boolLit _ => cases ht; left; exact .boolLit _
  | identity => cases ht; left; exact .identity
  | braidLit _ => cases ht; left; exact .braidLit _
  | compose a b iha ihb =>
    cases ht; rename_i h₁ h₂
    right
    rcases iha h₁ with hv₁ | ⟨e₁', hs₁⟩
    · rcases ihb h₂ with hv₂ | ⟨e₂', hs₂⟩
      · rcases canonical_word hv₁ h₁ with ⟨rfl, _⟩ | ⟨gs₁, rfl, _⟩ <;>
        rcases canonical_word hv₂ h₂ with ⟨rfl, _⟩ | ⟨gs₂, rfl, _⟩
        · exact ⟨_, .composeIdId⟩
        · exact ⟨_, .composeIdL⟩
        · exact ⟨_, .composeIdR⟩
        · exact ⟨_, .composeWords⟩
      · exact ⟨_, .composeRight hv₁ hs₂⟩
    · exact ⟨_, .composeLeft hs₁⟩
  | tensor a b iha ihb =>
    cases ht; rename_i h₁ h₂
    right
    rcases iha h₁ with hv₁ | ⟨e₁', hs₁⟩
    · rcases ihb h₂ with hv₂ | ⟨e₂', hs₂⟩
      · rcases canonical_word hv₁ h₁ with ⟨rfl, _⟩ | ⟨gs₁, rfl, _⟩ <;>
        rcases canonical_word hv₂ h₂ with ⟨rfl, _⟩ | ⟨gs₂, rfl, _⟩
        · exact ⟨_, .tensorIdId⟩
        · exact ⟨_, .tensorIdL⟩
        · exact ⟨_, .tensorIdR⟩
        · exact ⟨_, .tensorWords⟩
      · exact ⟨_, .tensorRight hv₁ hs₂⟩
    · exact ⟨_, .tensorLeft hs₁⟩
  | pipeline a b _ _ => cases ht; exact .inr ⟨_, .pipeline⟩
  | close a iha =>
    cases ht; rename_i h
    right
    rcases iha h with hv | ⟨e', hs⟩
    · rcases canonical_word hv h with ⟨rfl, _⟩ | ⟨gs, rfl, _⟩
      · exact ⟨_, .closeId⟩
      · exact ⟨_, .closeWord⟩
    · exact ⟨_, .closeStep hs⟩
  | add a b iha ihb =>
    cases ht; rename_i h₁ h₂
    right
    rcases iha h₁ with hv₁ | ⟨e₁', hs₁⟩
    · rcases ihb h₂ with hv₂ | ⟨e₂', hs₂⟩
      · obtain ⟨n₁, rfl⟩ := canonical_num hv₁ h₁
        obtain ⟨n₂, rfl⟩ := canonical_num hv₂ h₂
        exact ⟨_, .addNums⟩
      · exact ⟨_, .addRight hv₁ hs₂⟩
    · exact ⟨_, .addLeft hs₁⟩
  | eq a b iha ihb =>
    right
    cases ht with
    | tEqWord =>
      rename_i n h₁ h₂
      rcases iha h₁ with hv₁ | ⟨e₁', hs₁⟩
      · rcases ihb h₂ with hv₂ | ⟨e₂', hs₂⟩
        · rcases canonical_word hv₁ h₁ with ⟨rfl, _⟩ | ⟨gs₁, rfl, _⟩ <;>
          rcases canonical_word hv₂ h₂ with ⟨rfl, _⟩ | ⟨gs₂, rfl, _⟩
          · exact ⟨_, .eqIdId⟩
          · exact ⟨_, .eqIdBraid⟩
          · exact ⟨_, .eqBraidId⟩
          · exact ⟨_, .eqBraids⟩
        · exact ⟨_, .eqRight hv₁ hs₂⟩
      · exact ⟨_, .eqLeft hs₁⟩
    | tEqNum =>
      rename_i h₁ h₂
      rcases iha h₁ with hv₁ | ⟨e₁', hs₁⟩
      · rcases ihb h₂ with hv₂ | ⟨e₂', hs₂⟩
        · obtain ⟨n₁, rfl⟩ := canonical_num hv₁ h₁
          obtain ⟨n₂, rfl⟩ := canonical_num hv₂ h₂
          exact ⟨_, .eqNums⟩
        · exact ⟨_, .eqRight hv₁ hs₂⟩
      · exact ⟨_, .eqLeft hs₁⟩
    | tEqStr =>
      rename_i h₁ h₂
      rcases iha h₁ with hv₁ | ⟨e₁', hs₁⟩
      · rcases ihb h₂ with hv₂ | ⟨e₂', hs₂⟩
        · obtain ⟨s₁, rfl⟩ := canonical_str hv₁ h₁
          obtain ⟨s₂, rfl⟩ := canonical_str hv₂ h₂
          exact ⟨_, .eqStrs⟩
        · exact ⟨_, .eqRight hv₁ hs₂⟩
      · exact ⟨_, .eqLeft hs₁⟩
  | echoClose a iha =>
    -- `echoClose e` is always a redex: it reduces into a formed echo value.
    cases ht; rename_i h
    right
    rcases iha h with hv | ⟨e', hs⟩
    · rcases canonical_word hv h with ⟨rfl, _⟩ | ⟨gs, rfl, _⟩
      · exact ⟨_, .echoCloseId⟩
      · exact ⟨_, .echoCloseWord⟩
    · exact ⟨_, .echoCloseStep hs⟩
  | lower a iha =>
    cases ht; rename_i h
    right
    rcases iha h with hv | ⟨e', hs⟩
    · obtain ⟨r, v, rfl, hr, hvv⟩ := canonical_echo hv h
      exact ⟨_, .lowerVal hr hvv⟩
    · exact ⟨_, .lowerStep hs⟩
  | residue a iha =>
    cases ht; rename_i h
    right
    rcases iha h with hv | ⟨e', hs⟩
    · obtain ⟨r, v, rfl, hr, hvv⟩ := canonical_echo hv h
      exact ⟨_, .residueVal hr hvv⟩
    · exact ⟨_, .residueStep hs⟩
  | echoVal r w ihr ihw =>
    -- `echoVal r v` is a value iff both r and v are; otherwise the relevant
    -- component steps under `echoValLeft` / `echoValRight`.
    cases ht; rename_i hr hv
    rcases ihr hr with hvr | ⟨r', hsr⟩
    · rcases ihw hv with hvv | ⟨v', hsv⟩
      · exact .inl (.echoVal hvr hvv)
      · exact .inr ⟨_, .echoValRight hvr hsv⟩
    · exact .inr ⟨_, .echoValLeft hsr⟩
  | pair a b iha ihb =>
    cases ht; rename_i ha hb
    rcases iha ha with hva | ⟨a', hsa⟩
    · rcases ihb hb with hvb | ⟨b', hsb⟩
      · exact .inl (.pair hva hvb)
      · exact .inr ⟨_, .pairRight hva hsb⟩
    · exact .inr ⟨_, .pairLeft hsa⟩
  | fst a iha =>
    cases ht; rename_i h
    right
    rcases iha h with hv | ⟨e', hs⟩
    · obtain ⟨a, b, rfl, ha, hb⟩ := canonical_prod hv h
      exact ⟨_, .fstPair ha hb⟩
    · exact ⟨_, .fstStep hs⟩
  | snd a iha =>
    cases ht; rename_i h
    right
    rcases iha h with hv | ⟨e', hs⟩
    · obtain ⟨a, b, rfl, ha, hb⟩ := canonical_prod hv h
      exact ⟨_, .sndPair ha hb⟩
    · exact ⟨_, .sndStep hs⟩
  | echoAdd a b iha ihb =>
    cases ht; rename_i h₁ h₂
    right
    rcases iha h₁ with hv₁ | ⟨e₁', hs₁⟩
    · rcases ihb h₂ with hv₂ | ⟨e₂', hs₂⟩
      · obtain ⟨n₁, rfl⟩ := canonical_num hv₁ h₁
        obtain ⟨n₂, rfl⟩ := canonical_num hv₂ h₂
        exact ⟨_, .echoAddNums⟩
      · exact ⟨_, .echoAddRight hv₁ hs₂⟩
    · exact ⟨_, .echoAddLeft hs₁⟩
  | echoEq a b iha ihb =>
    right
    cases ht with
    | tEchoEqWord =>
      rename_i n h₁ h₂
      rcases iha h₁ with hv₁ | ⟨e₁', hs₁⟩
      · rcases ihb h₂ with hv₂ | ⟨e₂', hs₂⟩
        · rcases canonical_word hv₁ h₁ with ⟨rfl, _⟩ | ⟨gs₁, rfl, _⟩ <;>
          rcases canonical_word hv₂ h₂ with ⟨rfl, _⟩ | ⟨gs₂, rfl, _⟩
          · exact ⟨_, .echoEqIdId⟩
          · exact ⟨_, .echoEqIdBraid⟩
          · exact ⟨_, .echoEqBraidId⟩
          · exact ⟨_, .echoEqBraids⟩
        · exact ⟨_, .echoEqRight hv₁ hs₂⟩
      · exact ⟨_, .echoEqLeft hs₁⟩
    | tEchoEqNum =>
      rename_i h₁ h₂
      rcases iha h₁ with hv₁ | ⟨e₁', hs₁⟩
      · rcases ihb h₂ with hv₂ | ⟨e₂', hs₂⟩
        · obtain ⟨n₁, rfl⟩ := canonical_num hv₁ h₁
          obtain ⟨n₂, rfl⟩ := canonical_num hv₂ h₂
          exact ⟨_, .echoEqNums⟩
        · exact ⟨_, .echoEqRight hv₁ hs₂⟩
      · exact ⟨_, .echoEqLeft hs₁⟩
    | tEchoEqStr =>
      rename_i h₁ h₂
      rcases iha h₁ with hv₁ | ⟨e₁', hs₁⟩
      · rcases ihb h₂ with hv₂ | ⟨e₂', hs₂⟩
        · obtain ⟨s₁, rfl⟩ := canonical_str hv₁ h₁
          obtain ⟨s₂, rfl⟩ := canonical_str hv₂ h₂
          exact ⟨_, .echoEqStrs⟩
        · exact ⟨_, .echoEqRight hv₁ hs₂⟩
      · exact ⟨_, .echoEqLeft hs₁⟩

-- ═══════════════════════════════════════════════════════════════════════
-- THEOREM 2: PRESERVATION
-- ═══════════════════════════════════════════════════════════════════════

/-- **Preservation**: If [] ⊢ e : τ and e ⟶ e', then [] ⊢ e' : τ.
    Stepping preserves the type. -/
theorem preservation : HasType [] e τ → Step e e' → HasType [] e' τ := by
  intro ht hs
  induction hs generalizing τ with
  | composeLeft hs ih =>
    cases ht with | tComposeWord _ _ _ n m h₁ h₂ => exact .tComposeWord _ _ _ n m (ih h₁) h₂
  | composeRight _ hs ih =>
    cases ht with | tComposeWord _ _ _ n m h₁ h₂ => exact .tComposeWord _ _ _ n m h₁ (ih h₂)
  | composeWords =>
    cases ht with | tComposeWord _ _ _ n m h₁ h₂ =>
    cases h₁; cases h₂
    rw [← generatorWidth_append]
    exact .tBraid _ _
  | composeIdL =>
    cases ht with | tComposeWord _ _ _ n m h₁ h₂ =>
    cases h₁ with | tIdentity => simp at *; exact h₂
  | composeIdR =>
    cases ht with | tComposeWord _ _ _ n m h₁ h₂ =>
    cases h₂ with | tIdentity => simp at *; exact h₁
  | composeIdId =>
    cases ht with | tComposeWord _ _ _ n m h₁ h₂ =>
    cases h₁; cases h₂; exact .tIdentity _
  | tensorLeft hs ih =>
    cases ht with | tTensorWord _ _ _ n m h₁ h₂ => exact .tTensorWord _ _ _ n m (ih h₁) h₂
  | tensorRight _ hs ih =>
    cases ht with | tTensorWord _ _ _ n m h₁ h₂ => exact .tTensorWord _ _ _ n m h₁ (ih h₂)
  | tensorWords =>
    cases ht with | tTensorWord _ _ _ n m h₁ h₂ =>
    cases h₁; cases h₂
    rename_i gs₁ gs₂
    have hgoal :
        generatorWidth (gs₁ ++ shiftGenerators gs₂ (generatorWidth gs₁))
          = generatorWidth gs₁ + generatorWidth gs₂ := by
      rw [generatorWidth_append, generatorWidth_shift]
      by_cases hempty : gs₂ = []
      · subst hempty; simp [generatorWidth, List.foldl]
      · simp [hempty]; omega
    rw [← hgoal]
    exact .tBraid _ _
  | tensorIdL =>
    cases ht with | tTensorWord _ _ _ n m h₁ h₂ =>
    cases h₁ with | tIdentity => simp at *; exact h₂
  | tensorIdR =>
    cases ht with | tTensorWord _ _ _ n m h₁ h₂ =>
    cases h₂ with | tIdentity => simp at *; exact h₁
  | tensorIdId =>
    cases ht with | tTensorWord _ _ _ n m h₁ h₂ =>
    cases h₁; cases h₂; exact .tIdentity _
  | pipeline => cases ht with | tPipeline _ _ _ _ h => exact h
  | closeStep hs ih => cases ht with | tCloseWord _ _ n h => exact .tCloseWord _ _ n (ih h)
  | closeWord => cases ht with | tCloseWord => exact .tIdentity _
  | closeId => cases ht with | tCloseWord => exact .tIdentity _
  | addLeft hs ih => cases ht with | tAddNum _ _ _ h₁ h₂ => exact .tAddNum _ _ _ (ih h₁) h₂
  | addRight _ hs ih => cases ht with | tAddNum _ _ _ h₁ h₂ => exact .tAddNum _ _ _ h₁ (ih h₂)
  | addNums => cases ht with | tAddNum => exact .tNum _ _
  | eqLeft hs ih =>
    cases ht with
    | tEqWord _ _ _ n h₁ h₂ => exact .tEqWord _ _ _ n (ih h₁) h₂
    | tEqNum _ _ _ h₁ h₂ => exact .tEqNum _ _ _ (ih h₁) h₂
    | tEqStr _ _ _ h₁ h₂ => exact .tEqStr _ _ _ (ih h₁) h₂
  | eqRight _ hs ih =>
    cases ht with
    | tEqWord _ _ _ n h₁ h₂ => exact .tEqWord _ _ _ n h₁ (ih h₂)
    | tEqNum _ _ _ h₁ h₂ => exact .tEqNum _ _ _ h₁ (ih h₂)
    | tEqStr _ _ _ h₁ h₂ => exact .tEqStr _ _ _ h₁ (ih h₂)
  | eqNums => cases ht with
    | tEqNum => exact .tBool _ _
    | tEqWord _ _ _ _ _ h₁ => cases h₁
    | tEqStr _ _ _ _ h₁ => cases h₁
  | eqStrs => cases ht with
    | tEqStr => exact .tBool _ _
    | tEqWord _ _ _ _ _ h₁ => cases h₁
    | tEqNum _ _ _ _ h₁ => cases h₁
  | eqBraids => cases ht with
    | tEqWord => exact .tBool _ _
    | tEqNum _ _ _ _ h₁ => cases h₁
    | tEqStr _ _ _ _ h₁ => cases h₁
  | eqIdId => cases ht with
    | tEqWord => exact .tBool _ _
    | tEqNum _ _ _ _ h₁ => cases h₁
    | tEqStr _ _ _ _ h₁ => cases h₁
  | eqIdBraid => cases ht with
    | tEqWord => exact .tBool _ _
    | tEqNum _ _ _ _ h₁ => cases h₁
    | tEqStr _ _ _ _ h₁ => cases h₁
  | eqBraidId => cases ht with
    | tEqWord => exact .tBool _ _
    | tEqNum _ _ _ _ h₁ => cases h₁
    | tEqStr _ _ _ _ h₁ => cases h₁
  -- Echo congruence preserves types; `echoClose` reduces into a formed echo
  -- value `echoVal residue result`; `lower`/`residue` project off it.
  | echoCloseStep hs ih =>
    cases ht with | tEchoClose _ _ n h => exact .tEchoClose _ _ n (ih h)
  | echoCloseWord =>
    cases ht with | tEchoClose _ _ n h =>
    cases h with | tBraid => exact .tEchoVal _ _ _ _ _ (.tBraid _ _) (.tIdentity _)
  | echoCloseId =>
    cases ht with | tEchoClose _ _ n h =>
    cases h with | tIdentity => exact .tEchoVal _ _ _ _ _ (.tIdentity _) (.tIdentity _)
  | echoValLeft hs ih =>
    cases ht with | tEchoVal _ _ _ _ _ hr hv => exact .tEchoVal _ _ _ _ _ (ih hr) hv
  | echoValRight _ hs ih =>
    cases ht with | tEchoVal _ _ _ _ _ hr hv => exact .tEchoVal _ _ _ _ _ hr (ih hv)
  | lowerStep hs ih =>
    cases ht with | tLower _ _ _ _ h => exact .tLower _ _ _ _ (ih h)
  | lowerVal _ _ =>
    cases ht with | tLower _ _ _ _ h =>
    cases h with | tEchoVal _ _ _ _ _ hr hv => exact hv
  | residueStep hs ih =>
    cases ht with | tResidue _ _ _ _ h => exact .tResidue _ _ _ _ (ih h)
  | residueVal _ _ =>
    cases ht with | tResidue _ _ _ _ h =>
    cases h with | tEchoVal _ _ _ _ _ hr hv => exact hr
  -- Product: congruence preserves the product type; projections recover the
  -- component types.  `echoAdd` reduces into a formed echo value whose residue
  -- is the (num, num) summand pair and whose result is the num sum.
  | pairLeft hs ih => cases ht with | tPair _ _ _ α β ha hb => exact .tPair _ _ _ _ _ (ih ha) hb
  | pairRight _ hs ih => cases ht with | tPair _ _ _ α β ha hb => exact .tPair _ _ _ _ _ ha (ih hb)
  | fstStep hs ih => cases ht with | tFst _ _ α β h => exact .tFst _ _ _ _ (ih h)
  | fstPair _ _ => cases ht with | tFst _ _ α β h => cases h with | tPair _ _ _ _ _ ha hb => exact ha
  | sndStep hs ih => cases ht with | tSnd _ _ α β h => exact .tSnd _ _ _ _ (ih h)
  | sndPair _ _ => cases ht with | tSnd _ _ α β h => cases h with | tPair _ _ _ _ _ ha hb => exact hb
  | echoAddLeft hs ih => cases ht with | tEchoAdd _ _ _ h₁ h₂ => exact .tEchoAdd _ _ _ (ih h₁) h₂
  | echoAddRight _ hs ih => cases ht with | tEchoAdd _ _ _ h₁ h₂ => exact .tEchoAdd _ _ _ h₁ (ih h₂)
  | echoAddNums =>
    cases ht with | tEchoAdd _ _ _ h₁ h₂ =>
    exact .tEchoVal _ _ _ _ _ (.tPair _ _ _ _ _ (.tNum _ _) (.tNum _ _)) (.tNum _ _)
  -- Echo-preserving equality: congruence rebuilds via `tEchoEq*` + `ih` (the
  -- inner type is ambiguous, so case-split on all three `tEchoEq*`); the 6
  -- computation rules invert the matching `tEchoEq*` and build the formed echo
  -- value `echoVal (pair <ops>) (boolLit …)`, residue typed via `tPair`.
  | echoEqLeft hs ih =>
    cases ht with
    | tEchoEqWord _ _ _ n h₁ h₂ => exact .tEchoEqWord _ _ _ n (ih h₁) h₂
    | tEchoEqNum _ _ _ h₁ h₂ => exact .tEchoEqNum _ _ _ (ih h₁) h₂
    | tEchoEqStr _ _ _ h₁ h₂ => exact .tEchoEqStr _ _ _ (ih h₁) h₂
  | echoEqRight _ hs ih =>
    cases ht with
    | tEchoEqWord _ _ _ n h₁ h₂ => exact .tEchoEqWord _ _ _ n h₁ (ih h₂)
    | tEchoEqNum _ _ _ h₁ h₂ => exact .tEchoEqNum _ _ _ h₁ (ih h₂)
    | tEchoEqStr _ _ _ h₁ h₂ => exact .tEchoEqStr _ _ _ h₁ (ih h₂)
  | echoEqNums => cases ht with
    | tEchoEqNum =>
      exact .tEchoVal _ _ _ _ _ (.tPair _ _ _ _ _ (.tNum _ _) (.tNum _ _)) (.tBool _ _)
    | tEchoEqWord _ _ _ _ _ h₁ => cases h₁
    | tEchoEqStr _ _ _ _ h₁ => cases h₁
  | echoEqStrs => cases ht with
    | tEchoEqStr =>
      exact .tEchoVal _ _ _ _ _ (.tPair _ _ _ _ _ (.tStr _ _) (.tStr _ _)) (.tBool _ _)
    | tEchoEqWord _ _ _ _ _ h₁ => cases h₁
    | tEchoEqNum _ _ _ _ h₁ => cases h₁
  | echoEqBraids => cases ht with
    | tEchoEqWord _ _ _ n h₁ h₂ =>
      exact .tEchoVal _ _ _ _ _ (.tPair _ _ _ _ _ h₁ h₂) (.tBool _ _)
    | tEchoEqNum _ _ _ _ h₁ => cases h₁
    | tEchoEqStr _ _ _ _ h₁ => cases h₁
  | echoEqIdId => cases ht with
    | tEchoEqWord _ _ _ n h₁ h₂ =>
      exact .tEchoVal _ _ _ _ _ (.tPair _ _ _ _ _ h₁ h₂) (.tBool _ _)
    | tEchoEqNum _ _ _ _ h₁ => cases h₁
    | tEchoEqStr _ _ _ _ h₁ => cases h₁
  | echoEqIdBraid => cases ht with
    | tEchoEqWord _ _ _ n h₁ h₂ =>
      exact .tEchoVal _ _ _ _ _ (.tPair _ _ _ _ _ h₁ h₂) (.tBool _ _)
    | tEchoEqNum _ _ _ _ h₁ => cases h₁
    | tEchoEqStr _ _ _ _ h₁ => cases h₁
  | echoEqBraidId => cases ht with
    | tEchoEqWord _ _ _ n h₁ h₂ =>
      exact .tEchoVal _ _ _ _ _ (.tPair _ _ _ _ _ h₁ h₂) (.tBool _ _)
    | tEchoEqNum _ _ _ _ h₁ => cases h₁
    | tEchoEqStr _ _ _ _ h₁ => cases h₁
  -- Let: congruence rebuilds `tLet` via the IH on the bound expression; the
  -- β-redex closes by the substitution lemma at the empty prefix (`Γ₁ := []`,
  -- where `[] ++ [] = []`, so the closed-context premise `h₁` is accepted).
  | letStep hs ih =>
    cases ht with | tLet _ _ _ σ τ h₁ h₂ => exact .tLet _ _ _ σ τ (ih h₁) h₂
  | letRed hv =>
    cases ht with | tLet _ _ _ σ τ h₁ h₂ => exact subst_preserves (Γ₁ := []) h₂ h₁

-- ═══════════════════════════════════════════════════════════════════════
-- THEOREM 3: DETERMINISM
-- ═══════════════════════════════════════════════════════════════════════

/-- **Determinism**: The step relation is deterministic. -/
theorem determinism : Step e e₁ → Step e e₂ → e₁ = e₂ := by
  intro hs₁ hs₂
  induction hs₁ generalizing e₂ with
  | composeLeft hs ih => cases hs₂ with
    | composeLeft h => rw [ih h]
    | composeRight hv _ => exact absurd hs (value_no_step hv)
    | composeWords => exact absurd hs (value_no_step (.braidLit _))
    | composeIdL => exact absurd hs (value_no_step .identity)
    | composeIdR => exact absurd hs (value_no_step (.braidLit _))
    | composeIdId => exact absurd hs (value_no_step .identity)
  | composeRight hv hs ih => cases hs₂ with
    | composeLeft h => exact absurd h (value_no_step hv)
    | composeRight _ h => exact congrArg (Expr.compose _ ·) (ih h)
    | composeWords => exact absurd hs (value_no_step (.braidLit _))
    | composeIdL => exact absurd hs (value_no_step (.braidLit _))
    | composeIdR => exact absurd hs (value_no_step .identity)
    | composeIdId => cases hv with | identity => exact absurd hs (value_no_step .identity)
  | composeWords => cases hs₂ with
    | composeLeft h => exact absurd h (value_no_step (.braidLit _))
    | composeRight _ h => exact absurd h (value_no_step (.braidLit _))
    | composeWords => rfl
  | composeIdL => cases hs₂ with
    | composeLeft h => exact absurd h (value_no_step .identity)
    | composeRight _ h => exact absurd h (value_no_step (.braidLit _))
    | composeIdL => rfl
  | composeIdR => cases hs₂ with
    | composeLeft h => exact absurd h (value_no_step (.braidLit _))
    | composeRight _ h => exact absurd h (value_no_step .identity)
    | composeIdR => rfl
  | composeIdId => cases hs₂ with
    | composeLeft h => exact absurd h (value_no_step .identity)
    | composeRight _ h => exact absurd h (value_no_step .identity)
    | composeIdId => rfl
  | tensorLeft hs ih => cases hs₂ with
    | tensorLeft h => rw [ih h]
    | tensorRight hv _ => exact absurd hs (value_no_step hv)
    | tensorWords => exact absurd hs (value_no_step (.braidLit _))
    | tensorIdL => exact absurd hs (value_no_step .identity)
    | tensorIdR => exact absurd hs (value_no_step (.braidLit _))
    | tensorIdId => exact absurd hs (value_no_step .identity)
  | tensorRight hv hs ih => cases hs₂ with
    | tensorLeft h => exact absurd h (value_no_step hv)
    | tensorRight _ h => exact congrArg (Expr.tensor _ ·) (ih h)
    | tensorWords => exact absurd hs (value_no_step (.braidLit _))
    | tensorIdL => exact absurd hs (value_no_step (.braidLit _))
    | tensorIdR => exact absurd hs (value_no_step .identity)
    | tensorIdId => cases hv with | identity => exact absurd hs (value_no_step .identity)
  | tensorWords => cases hs₂ with
    | tensorLeft h => exact absurd h (value_no_step (.braidLit _))
    | tensorRight _ h => exact absurd h (value_no_step (.braidLit _))
    | tensorWords => rfl
  | tensorIdL => cases hs₂ with
    | tensorLeft h => exact absurd h (value_no_step .identity)
    | tensorRight _ h => exact absurd h (value_no_step (.braidLit _))
    | tensorIdL => rfl
  | tensorIdR => cases hs₂ with
    | tensorLeft h => exact absurd h (value_no_step (.braidLit _))
    | tensorRight _ h => exact absurd h (value_no_step .identity)
    | tensorIdR => rfl
  | tensorIdId => cases hs₂ with
    | tensorLeft h => exact absurd h (value_no_step .identity)
    | tensorRight _ h => exact absurd h (value_no_step .identity)
    | tensorIdId => rfl
  | pipeline => cases hs₂ with | pipeline => rfl
  | closeStep hs ih => cases hs₂ with
    | closeStep h => exact congrArg Expr.close (ih h)
    | closeWord => exact absurd hs (value_no_step (.braidLit _))
    | closeId => exact absurd hs (value_no_step .identity)
  | closeWord => cases hs₂ with
    | closeStep h => exact absurd h (value_no_step (.braidLit _))
    | closeWord => rfl
  | closeId => cases hs₂ with
    | closeStep h => exact absurd h (value_no_step .identity)
    | closeId => rfl
  | addLeft hs ih => cases hs₂ with
    | addLeft h => rw [ih h]
    | addRight hv _ => exact absurd hs (value_no_step hv)
    | addNums => exact absurd hs (value_no_step (.num _))
  | addRight hv hs ih => cases hs₂ with
    | addLeft h => exact absurd h (value_no_step hv)
    | addRight _ h => exact congrArg (Expr.add _ ·) (ih h)
    | addNums => exact absurd hs (value_no_step (.num _))
  | addNums => cases hs₂ with
    | addLeft h => exact absurd h (value_no_step (.num _))
    | addRight _ h => exact absurd h (value_no_step (.num _))
    | addNums => rfl
  | eqLeft hs ih => cases hs₂ with
    | eqLeft h => rw [ih h]
    | eqRight hv _ => exact absurd hs (value_no_step hv)
    | eqNums => exact absurd hs (value_no_step (.num _))
    | eqStrs => exact absurd hs (value_no_step (.str _))
    | eqBraids => exact absurd hs (value_no_step (.braidLit _))
    | eqIdId => exact absurd hs (value_no_step .identity)
    | eqIdBraid => exact absurd hs (value_no_step .identity)
    | eqBraidId => exact absurd hs (value_no_step (.braidLit _))
  | eqRight hv hs ih => cases hs₂ with
    | eqLeft h => exact absurd h (value_no_step hv)
    | eqRight _ h => exact congrArg (Expr.eq _ ·) (ih h)
    | eqNums => exact absurd hs (value_no_step (.num _))
    | eqStrs => exact absurd hs (value_no_step (.str _))
    | eqBraids => exact absurd hs (value_no_step (.braidLit _))
    | eqIdId => cases hv with | identity => exact absurd hs (value_no_step .identity)
    | eqIdBraid => cases hv with | identity => exact absurd hs (value_no_step (.braidLit _))
    | eqBraidId => cases hv with | braidLit => exact absurd hs (value_no_step .identity)
  | eqNums => cases hs₂ with
    | eqLeft h => exact absurd h (value_no_step (.num _))
    | eqRight _ h => exact absurd h (value_no_step (.num _))
    | eqNums => rfl
  | eqStrs => cases hs₂ with
    | eqLeft h => exact absurd h (value_no_step (.str _))
    | eqRight _ h => exact absurd h (value_no_step (.str _))
    | eqStrs => rfl
  | eqBraids => cases hs₂ with
    | eqLeft h => exact absurd h (value_no_step (.braidLit _))
    | eqRight _ h => exact absurd h (value_no_step (.braidLit _))
    | eqBraids => rfl
  | eqIdId => cases hs₂ with
    | eqLeft h => exact absurd h (value_no_step .identity)
    | eqRight _ h => exact absurd h (value_no_step .identity)
    | eqIdId => rfl
  | eqIdBraid => cases hs₂ with
    | eqLeft h => exact absurd h (value_no_step .identity)
    | eqRight _ h => exact absurd h (value_no_step (.braidLit _))
    | eqIdBraid => rfl
  | eqBraidId => cases hs₂ with
    | eqLeft h => exact absurd h (value_no_step (.braidLit _))
    | eqRight _ h => exact absurd h (value_no_step .identity)
    | eqBraidId => rfl
  -- Echo: congruence is deterministic by IH; the computation rules fire only
  -- on a formed echo value's component, so they never race their congruence.
  | echoCloseStep hs ih => cases hs₂ with
    | echoCloseStep h => exact congrArg Expr.echoClose (ih h)
    | echoCloseWord => exact absurd hs (value_no_step (.braidLit _))
    | echoCloseId => exact absurd hs (value_no_step .identity)
  | echoCloseWord => cases hs₂ with
    | echoCloseStep h => exact absurd h (value_no_step (.braidLit _))
    | echoCloseWord => rfl
  | echoCloseId => cases hs₂ with
    | echoCloseStep h => exact absurd h (value_no_step .identity)
    | echoCloseId => rfl
  | echoValLeft hs ih => cases hs₂ with
    | echoValLeft h => exact congrArg (Expr.echoVal · _) (ih h)
    | echoValRight hr _ => exact absurd hs (value_no_step hr)
  | echoValRight hr hs ih => cases hs₂ with
    | echoValLeft h => exact absurd h (value_no_step hr)
    | echoValRight _ h => exact congrArg (Expr.echoVal _ ·) (ih h)
  | lowerStep hs ih => cases hs₂ with
    | lowerStep h => exact congrArg Expr.lower (ih h)
    | lowerVal hr hv => exact absurd hs (value_no_step (.echoVal hr hv))
  | lowerVal hr hv => cases hs₂ with
    | lowerStep h => exact absurd h (value_no_step (.echoVal hr hv))
    | lowerVal _ _ => rfl
  | residueStep hs ih => cases hs₂ with
    | residueStep h => exact congrArg Expr.residue (ih h)
    | residueVal hr hv => exact absurd hs (value_no_step (.echoVal hr hv))
  | residueVal hr hv => cases hs₂ with
    | residueStep h => exact absurd h (value_no_step (.echoVal hr hv))
    | residueVal _ _ => rfl
  -- Product: congruence is deterministic by IH; projections fire only on a
  -- formed pair value, so they never race their congruence rule.  `echoAdd`
  -- computes only on two `num` values.
  | pairLeft hs ih => cases hs₂ with
    | pairLeft h => exact congrArg (Expr.pair · _) (ih h)
    | pairRight hva _ => exact absurd hs (value_no_step hva)
  | pairRight hva hs ih => cases hs₂ with
    | pairLeft h => exact absurd h (value_no_step hva)
    | pairRight _ h => exact congrArg (Expr.pair _ ·) (ih h)
  | fstStep hs ih => cases hs₂ with
    | fstStep h => exact congrArg Expr.fst (ih h)
    | fstPair ha hb => exact absurd hs (value_no_step (.pair ha hb))
  | fstPair ha hb => cases hs₂ with
    | fstStep h => exact absurd h (value_no_step (.pair ha hb))
    | fstPair _ _ => rfl
  | sndStep hs ih => cases hs₂ with
    | sndStep h => exact congrArg Expr.snd (ih h)
    | sndPair ha hb => exact absurd hs (value_no_step (.pair ha hb))
  | sndPair ha hb => cases hs₂ with
    | sndStep h => exact absurd h (value_no_step (.pair ha hb))
    | sndPair _ _ => rfl
  | echoAddLeft hs ih => cases hs₂ with
    | echoAddLeft h => exact congrArg (Expr.echoAdd · _) (ih h)
    | echoAddRight hv₁ _ => exact absurd hs (value_no_step hv₁)
    | echoAddNums => exact absurd hs (value_no_step (.num _))
  | echoAddRight hv₁ hs ih => cases hs₂ with
    | echoAddLeft h => exact absurd h (value_no_step hv₁)
    | echoAddRight _ h => exact congrArg (Expr.echoAdd _ ·) (ih h)
    | echoAddNums => exact absurd hs (value_no_step (.num _))
  | echoAddNums => cases hs₂ with
    | echoAddLeft h => exact absurd h (value_no_step (.num _))
    | echoAddRight _ h => exact absurd h (value_no_step (.num _))
    | echoAddNums => rfl
  -- Echo-preserving equality: same shape as `eq` determinism — congruence is
  -- deterministic by IH; computations discharge congruence races via
  -- `value_no_step` on the atomic operand values; same-rule → `rfl`.
  | echoEqLeft hs ih => cases hs₂ with
    | echoEqLeft h => rw [ih h]
    | echoEqRight hv _ => exact absurd hs (value_no_step hv)
    | echoEqNums => exact absurd hs (value_no_step (.num _))
    | echoEqStrs => exact absurd hs (value_no_step (.str _))
    | echoEqBraids => exact absurd hs (value_no_step (.braidLit _))
    | echoEqIdId => exact absurd hs (value_no_step .identity)
    | echoEqIdBraid => exact absurd hs (value_no_step .identity)
    | echoEqBraidId => exact absurd hs (value_no_step (.braidLit _))
  | echoEqRight hv hs ih => cases hs₂ with
    | echoEqLeft h => exact absurd h (value_no_step hv)
    | echoEqRight _ h => exact congrArg (Expr.echoEq _ ·) (ih h)
    | echoEqNums => exact absurd hs (value_no_step (.num _))
    | echoEqStrs => exact absurd hs (value_no_step (.str _))
    | echoEqBraids => exact absurd hs (value_no_step (.braidLit _))
    | echoEqIdId => cases hv with | identity => exact absurd hs (value_no_step .identity)
    | echoEqIdBraid => cases hv with | identity => exact absurd hs (value_no_step (.braidLit _))
    | echoEqBraidId => cases hv with | braidLit => exact absurd hs (value_no_step .identity)
  | echoEqNums => cases hs₂ with
    | echoEqLeft h => exact absurd h (value_no_step (.num _))
    | echoEqRight _ h => exact absurd h (value_no_step (.num _))
    | echoEqNums => rfl
  | echoEqStrs => cases hs₂ with
    | echoEqLeft h => exact absurd h (value_no_step (.str _))
    | echoEqRight _ h => exact absurd h (value_no_step (.str _))
    | echoEqStrs => rfl
  | echoEqBraids => cases hs₂ with
    | echoEqLeft h => exact absurd h (value_no_step (.braidLit _))
    | echoEqRight _ h => exact absurd h (value_no_step (.braidLit _))
    | echoEqBraids => rfl
  | echoEqIdId => cases hs₂ with
    | echoEqLeft h => exact absurd h (value_no_step .identity)
    | echoEqRight _ h => exact absurd h (value_no_step .identity)
    | echoEqIdId => rfl
  | echoEqIdBraid => cases hs₂ with
    | echoEqLeft h => exact absurd h (value_no_step .identity)
    | echoEqRight _ h => exact absurd h (value_no_step (.braidLit _))
    | echoEqIdBraid => rfl
  | echoEqBraidId => cases hs₂ with
    | echoEqLeft h => exact absurd h (value_no_step (.braidLit _))
    | echoEqRight _ h => exact absurd h (value_no_step .identity)
    | echoEqBraidId => rfl
  -- Let: congruence is deterministic by the IH; the β-redex fires only on a
  -- value (which cannot step), so it never races its congruence rule.
  | letStep hs ih => cases hs₂ with
    | letStep h => exact congrArg (Expr.lett · _) (ih h)
    | letRed hv => exact absurd hs (value_no_step hv)
  | letRed hv => cases hs₂ with
    | letStep h => exact absurd h (value_no_step hv)
    | letRed _ => rfl

-- ═══════════════════════════════════════════════════════════════════════
-- COROLLARY: TYPE SAFETY
-- ═══════════════════════════════════════════════════════════════════════

/-- **Type Safety**: Well-typed closed terms never get stuck. -/
theorem type_safety (ht : HasType [] e τ) (hs : Step e e') :
    HasType [] e' τ ∧ (IsValue e' ∨ ∃ e'', Step e' e'') :=
  ⟨preservation ht hs, progress (preservation ht hs)⟩

-- ═══════════════════════════════════════════════════════════════════════
-- ECHO-TYPES: STRUCTURED LOSS AS A FEATURE OF THE TYPE SYSTEM
-- ═══════════════════════════════════════════════════════════════════════
--
-- `close : Word[n] → Word[0]` is TANGLE's canonical lossy map: it collapses
-- every braid to the identity, discarding the word.  This mirrors echo-types'
-- `collapse : Bool → ⊤` (hyperpolymath/echo-types, EchoResidue.agda).  The echo
-- constructors above (`echoClose`/`lower`/`residue`/`echoVal`, type former
-- `Ty.echo`) make that loss *recoverable in the type system*: `echoClose`
-- reduces into a formed echo value `echoVal residue result` from which the
-- residue `Word[n]` is projected back out.  Progress, Preservation,
-- Determinism, and Type Safety (proved above) all cover these constructors —
-- echo types are not a bolt-on, they are part of the metatheory.
--
-- The three theorems below are the TANGLE instantiation of the echo-types
-- `no-section` / `sigma-distinguishes` results: `lower` collapses, `residue`
-- distinguishes.  They are stated over `StepStar` (multi-step reduction) since
-- `echoClose` now takes two steps to project: reduce to `echoVal`, then project.

/-- Reflexive-transitive closure of `Step` (multi-step reduction). -/
inductive StepStar : Expr → Expr → Prop where
  | refl  : StepStar e e
  | head  : Step e e' → StepStar e' e'' → StepStar e e''

/-- `lower ∘ echoClose` is the collapsing map: every closed braid lowers to the
    identity (the single `Word[0]` value).  `echoClose` first reduces into a
    formed echo value `echoVal (braidLit gs) identity`, then `lower` projects out
    the result component `identity` — `close` re-derived through the echo, the
    step that loses information. -/
theorem echo_lower_collapses (gs : List Generator) :
    StepStar (.lower (.echoClose (.braidLit gs))) .identity :=
  .head (.lowerStep .echoCloseWord) (.head (.lowerVal (.braidLit gs) .identity) .refl)

/-- `residue ∘ echoClose` recovers the witness: the original braid is retained in
    the residue.  `echoClose` reduces into `echoVal (braidLit gs) identity`, then
    `residue` projects out the residue component `braidLit gs`.  This is
    echo-types' `proj₁`/`echo-intro` round-trip — the lossy `close` becomes
    reversible once its echo is carried. -/
theorem echo_residue_recovers (gs : List Generator) :
    StepStar (.residue (.echoClose (.braidLit gs))) (.braidLit gs) :=
  .head (.residueStep .echoCloseWord) (.head (.residueVal (.braidLit gs) .identity) .refl)

/-- **Echo distinguishes what `close` collapses.**  Two distinct braids close to
    the *same* identity (the residue forgotten by `lower`), yet their echoes carry
    distinct residues (recovered by `residue`).  This is the TANGLE form of
    echo-types' non-injectivity barrier (`collapse-residue-same` paired with
    `echo-true≢echo-false` / `no-section-collapse-to-residue`). -/
theorem echo_distinguishes_collapsed {gs₁ gs₂ : List Generator} (h : gs₁ ≠ gs₂) :
    (StepStar (.lower (.echoClose (.braidLit gs₁))) .identity ∧
     StepStar (.lower (.echoClose (.braidLit gs₂))) .identity) ∧
    (Expr.braidLit gs₁ ≠ Expr.braidLit gs₂) :=
  ⟨⟨echo_lower_collapses gs₁, echo_lower_collapses gs₂⟩,
   fun heq => h (Expr.braidLit.inj heq)⟩

/-- The echo round-trip is type-safe: from `e : Word[n]`, `residue` recovers a
    `Word[n]` and `lower` yields the `Word[0]` codomain point.  The type system
    tracks both the recovered witness type and the collapsed result type. -/
theorem echo_roundtrip_typed (e : Expr) (n : Nat) (h : HasType [] e (.word n)) :
    HasType [] (.residue (.echoClose e)) (.word n) ∧
    HasType [] (.lower (.echoClose e)) (.word 0) :=
  ⟨.tResidue _ _ _ _ (.tEchoClose _ _ n h), .tLower _ _ _ _ (.tEchoClose _ _ n h)⟩

/-- `echoAdd` recovers the summands: `add` discards which numbers were added,
    but the residue retains the pair. -/
theorem echoAdd_residue_recovers (n₁ n₂ : Int) :
    StepStar (.residue (.echoAdd (.num n₁) (.num n₂))) (.pair (.num n₁) (.num n₂)) :=
  .head (.residueStep .echoAddNums) (.head (.residueVal (.pair (.num _) (.num _)) (.num _)) .refl)

/-- `lower ∘ echoAdd` is ordinary addition (the lossy result). -/
theorem echoAdd_lower_sums (n₁ n₂ : Int) :
    StepStar (.lower (.echoAdd (.num n₁) (.num n₂))) (.num (n₁ + n₂)) :=
  .head (.lowerStep .echoAddNums) (.head (.lowerVal (.pair (.num _) (.num _)) (.num _)) .refl)

/-- **Echo distinguishes what `add` collapses.** 1+3 and 2+2 both lower to 4,
    but their residues (the summand pairs) stay distinct. -/
theorem echoAdd_distinguishes :
    (StepStar (.lower (.echoAdd (.num 1) (.num 3))) (.num 4) ∧
     StepStar (.lower (.echoAdd (.num 2) (.num 2))) (.num 4)) ∧
    (Expr.pair (.num 1) (.num 3) ≠ Expr.pair (.num 2) (.num 2)) :=
  ⟨⟨echoAdd_lower_sums 1 3, echoAdd_lower_sums 2 2⟩, by decide⟩

/-- **Echo distinguishes what `eq` collapses.** 1≟2 and 3≟4 both lower to
    `false`, but their residues (the operand pairs) stay distinct. -/
theorem echoEq_distinguishes :
    (StepStar (.lower (.echoEq (.num 1) (.num 2))) (.boolLit (1 == 2)) ∧
     StepStar (.lower (.echoEq (.num 3) (.num 4))) (.boolLit (3 == 4))) ∧
    (Expr.pair (.num 1) (.num 2) ≠ Expr.pair (.num 3) (.num 4)) :=
  ⟨⟨.head (.lowerStep .echoEqNums) (.head (.lowerVal (.pair (.num _) (.num _)) (.boolLit _)) .refl),
    .head (.lowerStep .echoEqNums) (.head (.lowerVal (.pair (.num _) (.num _)) (.boolLit _)) .refl)⟩,
   by decide⟩

-- ═══════════════════════════════════════════════════════════════════════
-- TG-2: DECIDABILITY OF TYPE CHECKING
-- ═══════════════════════════════════════════════════════════════════════
--
-- `infer Γ e` computes the unique type of `e` in context `Γ`, or `none` if `e`
-- is ill-typed.  It is the algorithmic counterpart of the `HasType` relation:
-- `infer_sound` + `infer_complete` prove the two equivalent, hence `HasType`
-- is decidable (`decidableHasType`) and types are unique (`type_unique`).
-- This is the specification `compiler/lib/typecheck.ml` is meant to refine
-- (TG-3).

/-- Algorithmic type inference: total, structurally recursive on the AST. -/
def infer (Γ : Ctx) : Expr → Option Ty
  | .var k       => Γ[k]?
  | .lett e₁ e₂  =>
      match infer Γ e₁ with
      | some σ => infer (σ :: Γ) e₂
      | none   => none
  | .num _       => some .num
  | .str _       => some .str
  | .boolLit _   => some .bool
  | .identity    => some (.word 0)
  | .braidLit gs => some (.word (generatorWidth gs))
  | .compose e₁ e₂ =>
      match infer Γ e₁, infer Γ e₂ with
      | some (.word n), some (.word m) => some (.word (max n m))
      | _, _ => none
  | .tensor e₁ e₂ =>
      match infer Γ e₁, infer Γ e₂ with
      | some (.word n), some (.word m) => some (.word (n + m))
      | _, _ => none
  | .pipeline e₁ e₂ =>
      match infer Γ e₁, infer Γ e₂ with
      | some (.word n), some (.word m) => some (.word (max n m))
      | _, _ => none
  | .close e =>
      match infer Γ e with
      | some (.word _) => some (.word 0)
      | _ => none
  | .add e₁ e₂ =>
      match infer Γ e₁, infer Γ e₂ with
      | some .num, some .num => some .num
      | _, _ => none
  | .eq e₁ e₂ =>
      match infer Γ e₁, infer Γ e₂ with
      | some (.word n), some (.word m) => if n = m then some .bool else none
      | some .num, some .num => some .bool
      | some .str, some .str => some .bool
      | _, _ => none
  | .echoClose e =>
      match infer Γ e with
      | some (.word n) => some (.echo (.word n) (.word 0))
      | _ => none
  | .lower e =>
      match infer Γ e with
      | some (.echo _ τ) => some τ
      | _ => none
  | .residue e =>
      match infer Γ e with
      | some (.echo ρ _) => some ρ
      | _ => none
  | .echoVal r v =>
      match infer Γ r, infer Γ v with
      | some ρ, some τ => some (.echo ρ τ)
      | _, _ => none
  | .pair a b =>
      match infer Γ a, infer Γ b with
      | some α, some β => some (.prod α β)
      | _, _ => none
  | .fst e =>
      match infer Γ e with
      | some (.prod α _) => some α
      | _ => none
  | .snd e =>
      match infer Γ e with
      | some (.prod _ β) => some β
      | _ => none
  | .echoAdd e₁ e₂ =>
      match infer Γ e₁, infer Γ e₂ with
      | some .num, some .num => some (.echo (.prod .num .num) .num)
      | _, _ => none
  | .echoEq e₁ e₂ =>
      match infer Γ e₁, infer Γ e₂ with
      | some (.word n), some (.word m) => if n = m then some (.echo (.prod (.word n) (.word n)) .bool) else none
      | some .num, some .num => some (.echo (.prod .num .num) .bool)
      | some .str, some .str => some (.echo (.prod .str .str) .bool)
      | _, _ => none

/-- **Completeness**: every typing derivation is computed by `infer`. -/
theorem infer_complete {Γ : Ctx} {e : Expr} {τ : Ty} :
    HasType Γ e τ → infer Γ e = some τ := by
  intro h
  induction h <;> simp_all [infer]

/-- **Soundness**: every successful inference is a valid typing derivation. -/
theorem infer_sound {Γ : Ctx} {e : Expr} {τ : Ty} :
    infer Γ e = some τ → HasType Γ e τ := by
  induction e generalizing Γ τ with
  | var k => intro h; simp only [infer] at h; exact .tVar _ _ _ h
  | lett e₁ e₂ ih₁ ih₂ =>
      intro h; simp only [infer] at h; split at h
      next σ he₁ => exact .tLet _ _ _ σ _ (ih₁ he₁) (ih₂ h)
      next => simp at h
  | num _ => intro h; simp only [infer, Option.some.injEq] at h; subst h; exact .tNum _ _
  | str _ => intro h; simp only [infer, Option.some.injEq] at h; subst h; exact .tStr _ _
  | boolLit _ => intro h; simp only [infer, Option.some.injEq] at h; subst h; exact .tBool _ _
  | identity => intro h; simp only [infer, Option.some.injEq] at h; subst h; exact .tIdentity _
  | braidLit _ => intro h; simp only [infer, Option.some.injEq] at h; subst h; exact .tBraid _ _
  | compose e₁ e₂ ih₁ ih₂ =>
      intro h; simp only [infer] at h; split at h
      next n m he₁ he₂ =>
        injection h with h; subst h; exact .tComposeWord _ _ _ n m (ih₁ he₁) (ih₂ he₂)
      all_goals simp at h
  | tensor e₁ e₂ ih₁ ih₂ =>
      intro h; simp only [infer] at h; split at h
      next n m he₁ he₂ =>
        injection h with h; subst h; exact .tTensorWord _ _ _ n m (ih₁ he₁) (ih₂ he₂)
      all_goals simp at h
  | pipeline e₁ e₂ ih₁ ih₂ =>
      intro h; simp only [infer] at h; split at h
      next n m he₁ he₂ =>
        injection h with h; subst h
        exact .tPipeline _ _ _ _ (.tComposeWord _ _ _ n m (ih₁ he₁) (ih₂ he₂))
      all_goals simp at h
  | close e ih =>
      intro h; simp only [infer] at h; split at h
      next k he => injection h with h; subst h; exact .tCloseWord _ _ k (ih he)
      all_goals simp at h
  | add e₁ e₂ ih₁ ih₂ =>
      intro h; simp only [infer] at h; split at h
      next he₁ he₂ => injection h with h; subst h; exact .tAddNum _ _ _ (ih₁ he₁) (ih₂ he₂)
      all_goals simp at h
  | eq e₁ e₂ ih₁ ih₂ =>
      intro h; simp only [infer] at h; split at h
      next n m he₁ he₂ =>
        split at h
        next hnm =>
          injection h with h; subst h; subst hnm
          exact .tEqWord _ _ _ _ (ih₁ he₁) (ih₂ he₂)
        next => simp at h
      next he₁ he₂ => injection h with h; subst h; exact .tEqNum _ _ _ (ih₁ he₁) (ih₂ he₂)
      next he₁ he₂ => injection h with h; subst h; exact .tEqStr _ _ _ (ih₁ he₁) (ih₂ he₂)
      all_goals simp at h
  | echoClose e ih =>
      intro h; simp only [infer] at h; split at h
      next k he => injection h with h; subst h; exact .tEchoClose _ _ k (ih he)
      all_goals simp at h
  | lower e ih =>
      intro h; simp only [infer] at h; split at h
      next ρ τ' he => injection h with h; subst h; exact .tLower _ _ ρ τ' (ih he)
      all_goals simp at h
  | residue e ih =>
      intro h; simp only [infer] at h; split at h
      next ρ τ' he => injection h with h; subst h; exact .tResidue _ _ ρ τ' (ih he)
      all_goals simp at h
  | echoVal r v ihr ihv =>
      intro h; simp only [infer] at h; split at h
      next ρ τ' he_r he_v =>
        injection h with h; subst h; exact .tEchoVal _ _ _ ρ τ' (ihr he_r) (ihv he_v)
      all_goals simp at h
  | pair a b iha ihb =>
      intro h; simp only [infer] at h; split at h
      next α β he_a he_b =>
        injection h with h; subst h; exact .tPair _ _ _ α β (iha he_a) (ihb he_b)
      all_goals simp at h
  | fst e ih =>
      intro h; simp only [infer] at h; split at h
      next α β he => injection h with h; subst h; exact .tFst _ _ α β (ih he)
      all_goals simp at h
  | snd e ih =>
      intro h; simp only [infer] at h; split at h
      next α β he => injection h with h; subst h; exact .tSnd _ _ α β (ih he)
      all_goals simp at h
  | echoAdd e₁ e₂ ih₁ ih₂ =>
      intro h; simp only [infer] at h; split at h
      next he₁ he₂ => injection h with h; subst h; exact .tEchoAdd _ _ _ (ih₁ he₁) (ih₂ he₂)
      all_goals simp at h
  | echoEq e₁ e₂ ih₁ ih₂ =>
      intro h; simp only [infer] at h; split at h
      next n m he₁ he₂ =>
        split at h
        next hnm =>
          injection h with h; subst h; subst hnm
          exact .tEchoEqWord _ _ _ _ (ih₁ he₁) (ih₂ he₂)
        next => simp at h
      next he₁ he₂ => injection h with h; subst h; exact .tEchoEqNum _ _ _ (ih₁ he₁) (ih₂ he₂)
      next he₁ he₂ => injection h with h; subst h; exact .tEchoEqStr _ _ _ (ih₁ he₁) (ih₂ he₂)
      all_goals simp at h

/-- **Decidability of type checking** (TG-2): `infer` decides `HasType`. -/
theorem infer_iff_hasType {Γ : Ctx} {e : Expr} {τ : Ty} :
    infer Γ e = some τ ↔ HasType Γ e τ :=
  ⟨infer_sound, infer_complete⟩

/-- Types are unique: `HasType` assigns at most one type per (context, term). -/
theorem type_unique {Γ : Ctx} {e : Expr} {τ₁ τ₂ : Ty}
    (h₁ : HasType Γ e τ₁) (h₂ : HasType Γ e τ₂) : τ₁ = τ₂ := by
  have p₁ := infer_complete h₁
  have p₂ := infer_complete h₂
  rw [p₁] at p₂
  exact Option.some.inj p₂

/-- Type checking in the empty context is decidable. -/
instance decidableHasType (e : Expr) (τ : Ty) : Decidable (HasType [] e τ) :=
  decidable_of_iff (infer [] e = some τ) infer_iff_hasType

end Tangle
