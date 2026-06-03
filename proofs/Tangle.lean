-- SPDX-License-Identifier: MPL-2.0
-- Tangle.lean — Mechanized type safety proofs for the TANGLE language core.
--
-- Models the core type system from docs/spec/FORMAL-SEMANTICS.md:
--   - Syntax: Expr inductive with Num, Str, Bool, Identity, BraidLit,
--     Compose (.), Tensor (|), Pipeline (>>), Close, Add, Eq, and the echo
--     constructors EchoClose, Lower, Residue (structured loss)
--   - Typing: HasType inductive relation covering T-Num, T-Str, T-Bool,
--     T-Identity, T-Braid, T-Compose-Word, T-Tensor-Word, T-Pipeline,
--     T-Close-Word, T-Add-Num, T-Eq-Word, T-Eq-Num, T-Eq-Str, and the echo
--     rules T-Echo-Close, T-Lower, T-Residue
--   - Semantics: Small-step Step relation (31 rules incl. echo)
--
-- Theorems proven:
--   1. Progress:     well-typed closed terms are values or can step
--   2. Preservation: stepping preserves types
--   3. Determinism:  if e ⟶ e₁ and e ⟶ e₂ then e₁ = e₂
--   4. Type Safety:  corollary combining progress and preservation
--   All four cover the echo-types fragment as well as the let-free base.
--
-- Echo types (structured loss): `close : Word[n] → Word[0]` is TANGLE's
-- canonical lossy map.  The echo type former `Ty.echo ρ τ` and the
-- constructors `echoClose`/`lower`/`residue` integrate echo-types
-- (hyperpolymath/echo-types: `Echo f y := Σ (x : A), f x ≡ y`) directly into
-- the type system: closing a braid through an echo retains the residue, so the
-- otherwise-irreversible `close` becomes reversible at the type level.  See the
-- §ECHO-TYPES section at the foot of the file for the residue-recovery and
-- non-injectivity theorems.
--
-- Note on T-Let: the let binding requires a generalized de Bruijn substitution
-- lemma (standard POPLmark machinery); tracked as TG-1.  The fragment here
-- already covers the knot-theoretic operations (compose, tensor, close) and the
-- echo-types layer that are central to TANGLE.
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
  deriving DecidableEq, Repr

/-- Core expression AST. Mirrors the OCaml AST in compiler/lib/ast.ml.
    Uses de Bruijn indices (not needed for closed terms but included
    for completeness of the typing judgment). -/
inductive Expr where
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
  | echoClose : Expr → Expr                 -- echo-preserving closure (echo-intro for `close`)
  | lower     : Expr → Expr                 -- project an echo to its result (forget residue)
  | residue   : Expr → Expr                 -- project an echo to its residue (recover witness)
  deriving DecidableEq, Repr

/-- Value predicate: fully reduced expressions. -/
inductive IsValue : Expr → Prop where
  | num      : ∀ n, IsValue (.num n)
  | str      : ∀ s, IsValue (.str s)
  | boolLit  : ∀ b, IsValue (.boolLit b)
  | identity : IsValue .identity
  | braidLit : ∀ gs, IsValue (.braidLit gs)
  | echoClose : ∀ {v}, IsValue v → IsValue (.echoClose v)  -- a formed echo (residue v retained)

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
  -- Echo (structured loss): closure that retains its residue, and the two
  -- projections.  `lower` collapses to the codomain point (identity : Word[0]);
  -- `residue` recovers the witness braid — the fibre element echo-types keeps.
  | echoCloseStep : Step e e' → Step (.echoClose e) (.echoClose e')
  | lowerStep     : Step e e' → Step (.lower e) (.lower e')
  | lowerEcho     : IsValue v → Step (.lower (.echoClose v)) .identity
  | residueStep   : Step e e' → Step (.residue e) (.residue e')
  | residueEcho   : IsValue v → Step (.residue (.echoClose v)) v

-- ═══════════════════════════════════════════════════════════════════════
-- LEMMAS
-- ═══════════════════════════════════════════════════════════════════════

/-- Values are in normal form.  Recursive on the value structure because a
    formed echo `echoClose v` is a value exactly when its residue `v` is. -/
theorem value_no_step {e e' : Expr} (hv : IsValue e) (hs : Step e e') : False := by
  induction hv generalizing e' with
  | echoClose _ ih => cases hs with | echoCloseStep h => exact ih h
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
  | echoClose _ => cases ht

/-- Canonical forms for Echo[ρ, τ]: a value of echo type is a formed echo
    `echoClose v` whose residue `v` is itself a value.  This is the canonical
    form that lets `lower`/`residue` make progress. -/
theorem canonical_echo : IsValue e → HasType [] e (.echo ρ τ) →
    ∃ v, e = .echoClose v ∧ IsValue v := by
  intro hv ht
  cases hv with
  | num => cases ht
  | str => cases ht
  | boolLit => cases ht
  | identity => cases ht
  | braidLit => cases ht
  | echoClose hv => exact ⟨_, rfl, hv⟩

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
-- THEOREM 1: PROGRESS
-- ═══════════════════════════════════════════════════════════════════════

/-- **Progress**: Every well-typed closed term is either a value or can
    take a step. This is the standard progress theorem from TAPL §8. -/
theorem progress : HasType [] e τ → IsValue e ∨ ∃ e', Step e e' := by
  intro ht
  cases ht with
  | tNum => left; exact .num _
  | tStr => left; exact .str _
  | tBool => left; exact .boolLit _
  | tIdentity => left; exact .identity
  | tBraid => left; exact .braidLit _
  | tComposeWord _ _ n m h₁ h₂ =>
    right
    rcases progress h₁ with hv₁ | ⟨e₁', hs₁⟩
    · rcases progress h₂ with hv₂ | ⟨e₂', hs₂⟩
      · rcases canonical_word hv₁ h₁ with ⟨rfl, _⟩ | ⟨gs₁, rfl, _⟩ <;>
        rcases canonical_word hv₂ h₂ with ⟨rfl, _⟩ | ⟨gs₂, rfl, _⟩
        · exact ⟨_, .composeIdId⟩
        · exact ⟨_, .composeIdL⟩
        · exact ⟨_, .composeIdR⟩
        · exact ⟨_, .composeWords⟩
      · exact ⟨_, .composeRight hv₁ hs₂⟩
    · exact ⟨_, .composeLeft hs₁⟩
  | tTensorWord _ _ n m h₁ h₂ =>
    right
    rcases progress h₁ with hv₁ | ⟨e₁', hs₁⟩
    · rcases progress h₂ with hv₂ | ⟨e₂', hs₂⟩
      · rcases canonical_word hv₁ h₁ with ⟨rfl, _⟩ | ⟨gs₁, rfl, _⟩ <;>
        rcases canonical_word hv₂ h₂ with ⟨rfl, _⟩ | ⟨gs₂, rfl, _⟩
        · exact ⟨_, .tensorIdId⟩
        · exact ⟨_, .tensorIdL⟩
        · exact ⟨_, .tensorIdR⟩
        · exact ⟨_, .tensorWords⟩
      · exact ⟨_, .tensorRight hv₁ hs₂⟩
    · exact ⟨_, .tensorLeft hs₁⟩
  | tPipeline _ _ _ _ => exact .inr ⟨_, .pipeline⟩
  | tCloseWord _ n h =>
    right
    rcases progress h with hv | ⟨e', hs⟩
    · rcases canonical_word hv h with ⟨rfl, _⟩ | ⟨gs, rfl, _⟩
      · exact ⟨_, .closeId⟩
      · exact ⟨_, .closeWord⟩
    · exact ⟨_, .closeStep hs⟩
  | tAddNum _ _ h₁ h₂ =>
    right
    rcases progress h₁ with hv₁ | ⟨e₁', hs₁⟩
    · rcases progress h₂ with hv₂ | ⟨e₂', hs₂⟩
      · obtain ⟨n₁, rfl⟩ := canonical_num hv₁ h₁
        obtain ⟨n₂, rfl⟩ := canonical_num hv₂ h₂
        exact ⟨_, .addNums⟩
      · exact ⟨_, .addRight hv₁ hs₂⟩
    · exact ⟨_, .addLeft hs₁⟩
  | tEqWord _ _ n h₁ h₂ =>
    right
    rcases progress h₁ with hv₁ | ⟨e₁', hs₁⟩
    · rcases progress h₂ with hv₂ | ⟨e₂', hs₂⟩
      · rcases canonical_word hv₁ h₁ with ⟨rfl, _⟩ | ⟨gs₁, rfl, _⟩ <;>
        rcases canonical_word hv₂ h₂ with ⟨rfl, _⟩ | ⟨gs₂, rfl, _⟩
        · exact ⟨_, .eqIdId⟩
        · exact ⟨_, .eqIdBraid⟩
        · exact ⟨_, .eqBraidId⟩
        · exact ⟨_, .eqBraids⟩
      · exact ⟨_, .eqRight hv₁ hs₂⟩
    · exact ⟨_, .eqLeft hs₁⟩
  | tEqNum _ _ h₁ h₂ =>
    right
    rcases progress h₁ with hv₁ | ⟨e₁', hs₁⟩
    · rcases progress h₂ with hv₂ | ⟨e₂', hs₂⟩
      · obtain ⟨n₁, rfl⟩ := canonical_num hv₁ h₁
        obtain ⟨n₂, rfl⟩ := canonical_num hv₂ h₂
        exact ⟨_, .eqNums⟩
      · exact ⟨_, .eqRight hv₁ hs₂⟩
    · exact ⟨_, .eqLeft hs₁⟩
  | tEqStr _ _ h₁ h₂ =>
    right
    rcases progress h₁ with hv₁ | ⟨e₁', hs₁⟩
    · rcases progress h₂ with hv₂ | ⟨e₂', hs₂⟩
      · obtain ⟨s₁, rfl⟩ := canonical_str hv₁ h₁
        obtain ⟨s₂, rfl⟩ := canonical_str hv₂ h₂
        exact ⟨_, .eqStrs⟩
      · exact ⟨_, .eqRight hv₁ hs₂⟩
    · exact ⟨_, .eqLeft hs₁⟩
  | tEchoClose _ n h =>
    -- `echoClose e` is a value once `e` is (the residue is retained); else it steps.
    rcases progress h with hv | ⟨e', hs⟩
    · exact .inl (.echoClose hv)
    · exact .inr ⟨_, .echoCloseStep hs⟩
  | tLower _ ρ τ h =>
    right
    rcases progress h with hv | ⟨e', hs⟩
    · obtain ⟨v, rfl, hv'⟩ := canonical_echo hv h
      exact ⟨_, .lowerEcho hv'⟩
    · exact ⟨_, .lowerStep hs⟩
  | tResidue _ ρ τ h =>
    right
    rcases progress h with hv | ⟨e', hs⟩
    · obtain ⟨v, rfl, hv'⟩ := canonical_echo hv h
      exact ⟨_, .residueEcho hv'⟩
    · exact ⟨_, .residueStep hs⟩

-- ═══════════════════════════════════════════════════════════════════════
-- THEOREM 2: PRESERVATION
-- ═══════════════════════════════════════════════════════════════════════

/-- **Preservation**: If [] ⊢ e : τ and e ⟶ e', then [] ⊢ e' : τ.
    Stepping preserves the type. -/
theorem preservation : HasType [] e τ → Step e e' → HasType [] e' τ := by
  intro ht hs
  induction hs generalizing τ with
  | composeLeft hs ih =>
    cases ht with | tComposeWord _ _ n m h₁ h₂ => exact .tComposeWord _ _ _ n m (ih h₁) h₂
  | composeRight _ hs ih =>
    cases ht with | tComposeWord _ _ n m h₁ h₂ => exact .tComposeWord _ _ _ n m h₁ (ih h₂)
  | composeWords =>
    cases ht with | tComposeWord _ _ n m h₁ h₂ =>
    cases h₁; cases h₂
    rw [← generatorWidth_append]
    exact .tBraid _ _
  | composeIdL =>
    cases ht with | tComposeWord _ _ n m h₁ h₂ =>
    cases h₁ with | tIdentity => simp at *; exact h₂
  | composeIdR =>
    cases ht with | tComposeWord _ _ n m h₁ h₂ =>
    cases h₂ with | tIdentity => simp at *; exact h₁
  | composeIdId =>
    cases ht with | tComposeWord _ _ n m h₁ h₂ =>
    cases h₁; cases h₂; exact .tIdentity _
  | tensorLeft hs ih =>
    cases ht with | tTensorWord _ _ n m h₁ h₂ => exact .tTensorWord _ _ _ n m (ih h₁) h₂
  | tensorRight _ hs ih =>
    cases ht with | tTensorWord _ _ n m h₁ h₂ => exact .tTensorWord _ _ _ n m h₁ (ih h₂)
  | tensorWords =>
    cases ht with | tTensorWord _ _ n m h₁ h₂ =>
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
    cases ht with | tTensorWord _ _ n m h₁ h₂ =>
    cases h₁ with | tIdentity => simp at *; exact h₂
  | tensorIdR =>
    cases ht with | tTensorWord _ _ n m h₁ h₂ =>
    cases h₂ with | tIdentity => simp at *; exact h₁
  | tensorIdId =>
    cases ht with | tTensorWord _ _ n m h₁ h₂ =>
    cases h₁; cases h₂; exact .tIdentity _
  | pipeline => cases ht with | tPipeline _ _ _ h => exact h
  | closeStep hs ih => cases ht with | tCloseWord _ n h => exact .tCloseWord _ _ n (ih h)
  | closeWord => cases ht with | tCloseWord => exact .tIdentity _
  | closeId => cases ht with | tCloseWord => exact .tIdentity _
  | addLeft hs ih => cases ht with | tAddNum _ _ h₁ h₂ => exact .tAddNum _ _ _ (ih h₁) h₂
  | addRight _ hs ih => cases ht with | tAddNum _ _ h₁ h₂ => exact .tAddNum _ _ _ h₁ (ih h₂)
  | addNums => cases ht with | tAddNum => exact .tNum _ _
  | eqLeft hs ih =>
    cases ht with
    | tEqWord _ _ n h₁ h₂ => exact .tEqWord _ _ _ n (ih h₁) h₂
    | tEqNum _ _ h₁ h₂ => exact .tEqNum _ _ _ (ih h₁) h₂
    | tEqStr _ _ h₁ h₂ => exact .tEqStr _ _ _ (ih h₁) h₂
  | eqRight _ hs ih =>
    cases ht with
    | tEqWord _ _ n h₁ h₂ => exact .tEqWord _ _ _ n h₁ (ih h₂)
    | tEqNum _ _ h₁ h₂ => exact .tEqNum _ _ _ h₁ (ih h₂)
    | tEqStr _ _ h₁ h₂ => exact .tEqStr _ _ _ h₁ (ih h₂)
  | eqNums => cases ht with
    | tEqNum => exact .tBool _ _
    | tEqWord _ _ _ _ h₁ => cases h₁
    | tEqStr _ _ _ h₁ => cases h₁
  | eqStrs => cases ht with
    | tEqStr => exact .tBool _ _
    | tEqWord _ _ _ _ h₁ => cases h₁
    | tEqNum _ _ _ h₁ => cases h₁
  | eqBraids => cases ht with
    | tEqWord => exact .tBool _ _
    | tEqNum _ _ _ h₁ => cases h₁
    | tEqStr _ _ _ h₁ => cases h₁
  | eqIdId => cases ht with
    | tEqWord => exact .tBool _ _
    | tEqNum _ _ _ h₁ => cases h₁
    | tEqStr _ _ _ h₁ => cases h₁
  | eqIdBraid => cases ht with
    | tEqWord => exact .tBool _ _
    | tEqNum _ _ _ h₁ => cases h₁
    | tEqStr _ _ _ h₁ => cases h₁
  | eqBraidId => cases ht with
    | tEqWord => exact .tBool _ _
    | tEqNum _ _ _ h₁ => cases h₁
    | tEqStr _ _ _ h₁ => cases h₁
  -- Echo congruence preserves the (residue Word[n], result Word[0]) echo type.
  | echoCloseStep hs ih =>
    cases ht with | tEchoClose _ n h => exact .tEchoClose _ _ n (ih h)
  | lowerStep hs ih =>
    cases ht with | tLower _ _ _ h => exact .tLower _ _ _ _ (ih h)
  | residueStep hs ih =>
    cases ht with | tResidue _ _ _ h => exact .tResidue _ _ _ _ (ih h)
  -- `lower` yields the codomain point identity : Word[0]; the echo type forces τ = Word[0].
  | lowerEcho hv =>
    cases ht with | tLower _ _ _ h =>
    cases h with | tEchoClose _ n _ => exact .tIdentity _
  -- `residue` recovers the witness, whose type is exactly the echo's residue type.
  | residueEcho hv =>
    cases ht with | tResidue _ _ _ h =>
    cases h with | tEchoClose _ n h' => exact h'

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
  -- on a formed echo (a value), so they never race with their congruence rule.
  | echoCloseStep hs ih => cases hs₂ with
    | echoCloseStep h => exact congrArg Expr.echoClose (ih h)
  | lowerStep hs ih => cases hs₂ with
    | lowerStep h => exact congrArg Expr.lower (ih h)
    | lowerEcho hv => exact absurd hs (value_no_step (.echoClose hv))
  | residueStep hs ih => cases hs₂ with
    | residueStep h => exact congrArg Expr.residue (ih h)
    | residueEcho hv => exact absurd hs (value_no_step (.echoClose hv))
  | lowerEcho hv => cases hs₂ with
    | lowerStep h => exact absurd h (value_no_step (.echoClose hv))
    | lowerEcho _ => rfl
  | residueEcho hv => cases hs₂ with
    | residueStep h => exact absurd h (value_no_step (.echoClose hv))
    | residueEcho _ => rfl

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
-- constructors above (`echoClose`/`lower`/`residue`, type former `Ty.echo`)
-- make that loss *recoverable in the type system*: the residue `Word[n]` is
-- retained and projected back out.  Progress, Preservation, Determinism, and
-- Type Safety (proved above) all cover these constructors — echo types are not
-- a bolt-on, they are part of the metatheory.
--
-- The three theorems below are the TANGLE instantiation of the echo-types
-- `no-section` / `sigma-distinguishes` results: `lower` collapses, `residue`
-- distinguishes.

/-- `lower ∘ echoClose` is the collapsing map: every closed braid lowers to the
    identity (the single `Word[0]` value).  This is `close` re-derived through the
    echo — the step that loses information. -/
theorem echo_lower_collapses (gs : List Generator) :
    Step (.lower (.echoClose (.braidLit gs))) .identity :=
  .lowerEcho (.braidLit gs)

/-- `residue ∘ echoClose` recovers the witness: the original braid is retained in
    the residue.  This is echo-types' `proj₁`/`echo-intro` round-trip — the lossy
    `close` becomes reversible once its echo is carried. -/
theorem echo_residue_recovers (gs : List Generator) :
    Step (.residue (.echoClose (.braidLit gs))) (.braidLit gs) :=
  .residueEcho (.braidLit gs)

/-- **Echo distinguishes what `close` collapses.**  Two distinct braids close to
    the *same* identity (the residue forgotten by `lower`), yet their echoes carry
    distinct residues (recovered by `residue`).  This is the TANGLE form of
    echo-types' non-injectivity barrier (`collapse-residue-same` paired with
    `echo-true≢echo-false` / `no-section-collapse-to-residue`). -/
theorem echo_distinguishes_collapsed {gs₁ gs₂ : List Generator} (h : gs₁ ≠ gs₂) :
    (Step (.lower (.echoClose (.braidLit gs₁))) .identity ∧
     Step (.lower (.echoClose (.braidLit gs₂))) .identity) ∧
    (Expr.braidLit gs₁ ≠ Expr.braidLit gs₂) :=
  ⟨⟨.lowerEcho (.braidLit gs₁), .lowerEcho (.braidLit gs₂)⟩,
   fun heq => h (Expr.braidLit.inj heq)⟩

/-- The echo round-trip is type-safe: from `e : Word[n]`, `residue` recovers a
    `Word[n]` and `lower` yields the `Word[0]` codomain point.  The type system
    tracks both the recovered witness type and the collapsed result type. -/
theorem echo_roundtrip_typed (e : Expr) (n : Nat) (h : HasType [] e (.word n)) :
    HasType [] (.residue (.echoClose e)) (.word n) ∧
    HasType [] (.lower (.echoClose e)) (.word 0) :=
  ⟨.tResidue _ _ _ _ (.tEchoClose _ _ n h), .tLower _ _ _ _ (.tEchoClose _ _ n h)⟩

end Tangle
