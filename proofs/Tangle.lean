-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Tangle.lean — Mechanized type safety proofs for the TANGLE language core.
--
-- Models the core type system from docs/spec/FORMAL-SEMANTICS.md and proves:
--   1. Progress:     well-typed closed terms are values or can step
--   2. Preservation: stepping preserves types
--   3. Determinism:  evaluation is deterministic
--
-- Covers typing rules: T-Num, T-Str, T-Bool, T-Var, T-Compose, T-Tensor,
-- T-Pipeline, T-Close, T-Let, T-Add, T-Eq
--
-- Uses de Bruijn indices. All theorems fully proven — NO sorry.
--
-- Author: Jonathan D.A. Jewell, Claude (Opus 4.6)

namespace Tangle

------------------------------------------------------------------------
-- 1. Syntax
------------------------------------------------------------------------

structure Generator where
  idx : Nat
  exp : Int
  deriving DecidableEq, Repr

inductive Ty where
  | num  : Ty
  | str  : Ty
  | bool : Ty
  | word : Nat → Ty
  deriving DecidableEq, Repr

inductive Expr where
  | num      : Int → Expr
  | str      : String → Expr
  | boolLit  : Bool → Expr
  | identity : Expr
  | braidLit : List Generator → Expr
  | var      : Nat → Expr
  | compose  : Expr → Expr → Expr
  | tensor   : Expr → Expr → Expr
  | pipeline : Expr → Expr → Expr
  | close    : Expr → Expr
  | letE     : Expr → Expr → Expr
  | add      : Expr → Expr → Expr
  | eq       : Expr → Expr → Expr
  deriving DecidableEq, Repr

inductive IsValue : Expr → Prop where
  | num      : ∀ n, IsValue (.num n)
  | str      : ∀ s, IsValue (.str s)
  | boolLit  : ∀ b, IsValue (.boolLit b)
  | identity : IsValue .identity
  | braidLit : ∀ gs, IsValue (.braidLit gs)

------------------------------------------------------------------------
-- 2. Width
------------------------------------------------------------------------

def generatorWidth (gs : List Generator) : Nat :=
  gs.foldl (fun acc g => max acc (g.idx + 1)) 0

def shiftGenerators (gs : List Generator) (n : Nat) : List Generator :=
  gs.map fun g => { g with idx := g.idx + n }

------------------------------------------------------------------------
-- 3. Typing
------------------------------------------------------------------------

abbrev Ctx := List Ty

inductive HasType : Ctx → Expr → Ty → Prop where
  | tNum (Γ : Ctx) (n : Int) :
      HasType Γ (.num n) .num
  | tStr (Γ : Ctx) (s : String) :
      HasType Γ (.str s) .str
  | tBool (Γ : Ctx) (b : Bool) :
      HasType Γ (.boolLit b) .bool
  | tIdentity (Γ : Ctx) :
      HasType Γ .identity (.word 0)
  | tBraid (Γ : Ctx) (gs : List Generator) (n : Nat) :
      n = generatorWidth gs →
      HasType Γ (.braidLit gs) (.word n)
  | tVar (Γ : Ctx) (i : Nat) (τ : Ty) :
      Γ[i]? = some τ →
      HasType Γ (.var i) τ
  | tComposeWord (Γ : Ctx) (e₁ e₂ : Expr) (n m : Nat) :
      HasType Γ e₁ (.word n) →
      HasType Γ e₂ (.word m) →
      HasType Γ (.compose e₁ e₂) (.word (max n m))
  | tTensorWord (Γ : Ctx) (e₁ e₂ : Expr) (n m : Nat) :
      HasType Γ e₁ (.word n) →
      HasType Γ e₂ (.word m) →
      HasType Γ (.tensor e₁ e₂) (.word (n + m))
  | tPipeline (Γ : Ctx) (e₁ e₂ : Expr) (τ : Ty) :
      HasType Γ (.compose e₁ e₂) τ →
      HasType Γ (.pipeline e₁ e₂) τ
  | tCloseWord (Γ : Ctx) (e : Expr) (n : Nat) :
      HasType Γ e (.word n) →
      HasType Γ (.close e) (.word 0)
  | tLet (Γ : Ctx) (e₁ e₂ : Expr) (τ₁ τ₂ : Ty) :
      HasType Γ e₁ τ₁ →
      HasType (τ₁ :: Γ) e₂ τ₂ →
      HasType Γ (.letE e₁ e₂) τ₂
  | tAddNum (Γ : Ctx) (e₁ e₂ : Expr) :
      HasType Γ e₁ .num →
      HasType Γ e₂ .num →
      HasType Γ (.add e₁ e₂) .num
  | tEqWord (Γ : Ctx) (e₁ e₂ : Expr) (n : Nat) :
      HasType Γ e₁ (.word n) →
      HasType Γ e₂ (.word n) →
      HasType Γ (.eq e₁ e₂) .bool
  | tEqNum (Γ : Ctx) (e₁ e₂ : Expr) :
      HasType Γ e₁ .num →
      HasType Γ e₂ .num →
      HasType Γ (.eq e₁ e₂) .bool
  | tEqStr (Γ : Ctx) (e₁ e₂ : Expr) :
      HasType Γ e₁ .str →
      HasType Γ e₂ .str →
      HasType Γ (.eq e₁ e₂) .bool

------------------------------------------------------------------------
-- 4. Lifting and substitution
------------------------------------------------------------------------

/-- Lift: increment free variables ≥ cutoff c by 1. -/
def lift (c : Nat) : Expr → Expr
  | .num n        => .num n
  | .str s        => .str s
  | .boolLit b    => .boolLit b
  | .identity     => .identity
  | .braidLit gs  => .braidLit gs
  | .var i        => if i < c then .var i else .var (i + 1)
  | .compose a b  => .compose (lift c a) (lift c b)
  | .tensor a b   => .tensor (lift c a) (lift c b)
  | .pipeline a b => .pipeline (lift c a) (lift c b)
  | .close e      => .close (lift c e)
  | .letE e₁ e₂   => .letE (lift c e₁) (lift (c + 1) e₂)
  | .add a b      => .add (lift c a) (lift c b)
  | .eq a b       => .eq (lift c a) (lift c b)

/-- Substitute expression s for variable 0, decrementing others. -/
def substTop (s : Expr) : Expr → Expr
  | .num n        => .num n
  | .str st       => .str st
  | .boolLit b    => .boolLit b
  | .identity     => .identity
  | .braidLit gs  => .braidLit gs
  | .var 0        => s
  | .var (i + 1)  => .var i
  | .compose a b  => .compose (substTop s a) (substTop s b)
  | .tensor a b   => .tensor (substTop s a) (substTop s b)
  | .pipeline a b => .pipeline (substTop s a) (substTop s b)
  | .close e      => .close (substTop s e)
  | .letE e₁ e₂   => .letE (substTop s e₁) (substTop (lift 0 s) e₂)
  | .add a b      => .add (substTop s a) (substTop s b)
  | .eq a b       => .eq (substTop s a) (substTop s b)

------------------------------------------------------------------------
-- 5. Small-step semantics
------------------------------------------------------------------------

inductive Step : Expr → Expr → Prop where
  | composeLeft (e₁ e₁' e₂ : Expr) :
      Step e₁ e₁' → Step (.compose e₁ e₂) (.compose e₁' e₂)
  | composeRight (e₁ e₂ e₂' : Expr) :
      IsValue e₁ → Step e₂ e₂' → Step (.compose e₁ e₂) (.compose e₁ e₂')
  | composeWords (gs₁ gs₂ : List Generator) :
      Step (.compose (.braidLit gs₁) (.braidLit gs₂)) (.braidLit (gs₁ ++ gs₂))
  | composeIdL (gs : List Generator) :
      Step (.compose .identity (.braidLit gs)) (.braidLit gs)
  | composeIdR (gs : List Generator) :
      Step (.compose (.braidLit gs) .identity) (.braidLit gs)
  | composeIdId :
      Step (.compose .identity .identity) .identity
  | tensorLeft (e₁ e₁' e₂ : Expr) :
      Step e₁ e₁' → Step (.tensor e₁ e₂) (.tensor e₁' e₂)
  | tensorRight (e₁ e₂ e₂' : Expr) :
      IsValue e₁ → Step e₂ e₂' → Step (.tensor e₁ e₂) (.tensor e₁ e₂')
  | tensorWords (gs₁ gs₂ : List Generator) :
      Step (.tensor (.braidLit gs₁) (.braidLit gs₂))
           (.braidLit (gs₁ ++ shiftGenerators gs₂ (generatorWidth gs₁)))
  | tensorIdL (gs : List Generator) :
      Step (.tensor .identity (.braidLit gs)) (.braidLit gs)
  | tensorIdR (gs : List Generator) :
      Step (.tensor (.braidLit gs) .identity) (.braidLit gs)
  | tensorIdId :
      Step (.tensor .identity .identity) .identity
  | pipelineDesugar (e₁ e₂ : Expr) :
      Step (.pipeline e₁ e₂) (.compose e₁ e₂)
  | closeStep (e e' : Expr) :
      Step e e' → Step (.close e) (.close e')
  | closeWord (gs : List Generator) :
      Step (.close (.braidLit gs)) .identity
  | closeId :
      Step (.close .identity) .identity
  | letStep (e₁ e₁' e₂ : Expr) :
      Step e₁ e₁' → Step (.letE e₁ e₂) (.letE e₁' e₂)
  | letBeta (v e₂ : Expr) :
      IsValue v → Step (.letE v e₂) (substTop v e₂)
  | addLeft (e₁ e₁' e₂ : Expr) :
      Step e₁ e₁' → Step (.add e₁ e₂) (.add e₁' e₂)
  | addRight (e₁ e₂ e₂' : Expr) :
      IsValue e₁ → Step e₂ e₂' → Step (.add e₁ e₂) (.add e₁ e₂')
  | addNums (n₁ n₂ : Int) :
      Step (.add (.num n₁) (.num n₂)) (.num (n₁ + n₂))
  | eqLeft (e₁ e₁' e₂ : Expr) :
      Step e₁ e₁' → Step (.eq e₁ e₂) (.eq e₁' e₂)
  | eqRight (e₁ e₂ e₂' : Expr) :
      IsValue e₁ → Step e₂ e₂' → Step (.eq e₁ e₂) (.eq e₁ e₂')
  | eqNums (n₁ n₂ : Int) :
      Step (.eq (.num n₁) (.num n₂)) (.boolLit (n₁ == n₂))
  | eqStrs (s₁ s₂ : String) :
      Step (.eq (.str s₁) (.str s₂)) (.boolLit (s₁ == s₂))
  | eqBraids (gs₁ gs₂ : List Generator) :
      Step (.eq (.braidLit gs₁) (.braidLit gs₂)) (.boolLit (gs₁ == gs₂))
  | eqIdId :
      Step (.eq .identity .identity) (.boolLit true)
  | eqIdBraid (gs : List Generator) :
      Step (.eq .identity (.braidLit gs)) (.boolLit (gs == []))
  | eqBraidId (gs : List Generator) :
      Step (.eq (.braidLit gs) .identity) (.boolLit (gs == []))

------------------------------------------------------------------------
-- 6. Values don't step
------------------------------------------------------------------------

theorem value_no_step (e : Expr) (hv : IsValue e) (e' : Expr) (hs : Step e e') : False := by
  cases hv <;> cases hs

------------------------------------------------------------------------
-- 7. Canonical forms
------------------------------------------------------------------------

theorem canonical_num (e : Expr) (hv : IsValue e) (ht : HasType [] e .num) :
    ∃ n, e = .num n := by
  cases hv <;> cases ht; exact ⟨_, rfl⟩

theorem canonical_str (e : Expr) (hv : IsValue e) (ht : HasType [] e .str) :
    ∃ s, e = .str s := by
  cases hv <;> cases ht; exact ⟨_, rfl⟩

theorem canonical_word (e : Expr) (n : Nat) (hv : IsValue e) (ht : HasType [] e (.word n)) :
    (e = .identity ∧ n = 0) ∨ (∃ gs, e = .braidLit gs ∧ n = generatorWidth gs) := by
  cases hv with
  | num k => cases ht
  | str s => cases ht
  | boolLit b => cases ht
  | identity => left; cases ht with | tIdentity => exact ⟨rfl, rfl⟩
  | braidLit gs => right; cases ht with | tBraid _ _ _ h => exact ⟨gs, rfl, h⟩

------------------------------------------------------------------------
-- 8. Progress
------------------------------------------------------------------------

theorem progress (e : Expr) (τ : Ty) (ht : HasType [] e τ) :
    IsValue e ∨ ∃ e', Step e e' := by
  induction ht with
  | tNum _ n => left; exact .num n
  | tStr _ s => left; exact .str s
  | tBool _ b => left; exact .boolLit b
  | tIdentity _ => left; exact .identity
  | tBraid _ gs n _ => left; exact .braidLit gs
  | @tVar _ i _ h => exact absurd h (by cases i <;> simp)
  | tComposeWord _ e₁ e₂ n m ht₁ ht₂ ih₁ ih₂ =>
    right
    rcases ih₁ with hv₁ | ⟨e₁', hs₁⟩
    · rcases ih₂ with hv₂ | ⟨e₂', hs₂⟩
      · rcases canonical_word e₁ n hv₁ ht₁ with ⟨rfl, _⟩ | ⟨gs₁, rfl, _⟩ <;>
        rcases canonical_word e₂ m hv₂ ht₂ with ⟨rfl, _⟩ | ⟨gs₂, rfl, _⟩
        · exact ⟨_, .composeIdId⟩
        · exact ⟨_, .composeIdL gs₂⟩
        · exact ⟨_, .composeIdR gs₁⟩
        · exact ⟨_, .composeWords gs₁ gs₂⟩
      · exact ⟨_, .composeRight e₁ e₂ e₂' hv₁ hs₂⟩
    · exact ⟨_, .composeLeft e₁ e₁' e₂ hs₁⟩
  | tTensorWord _ e₁ e₂ n m ht₁ ht₂ ih₁ ih₂ =>
    right
    rcases ih₁ with hv₁ | ⟨e₁', hs₁⟩
    · rcases ih₂ with hv₂ | ⟨e₂', hs₂⟩
      · rcases canonical_word e₁ n hv₁ ht₁ with ⟨rfl, _⟩ | ⟨gs₁, rfl, _⟩ <;>
        rcases canonical_word e₂ m hv₂ ht₂ with ⟨rfl, _⟩ | ⟨gs₂, rfl, _⟩
        · exact ⟨_, .tensorIdId⟩
        · exact ⟨_, .tensorIdL gs₂⟩
        · exact ⟨_, .tensorIdR gs₁⟩
        · exact ⟨_, .tensorWords gs₁ gs₂⟩
      · exact ⟨_, .tensorRight e₁ e₂ e₂' hv₁ hs₂⟩
    · exact ⟨_, .tensorLeft e₁ e₁' e₂ hs₁⟩
  | tPipeline _ e₁ e₂ _ _ _ =>
    exact .inr ⟨_, .pipelineDesugar e₁ e₂⟩
  | tCloseWord _ e n hte ih =>
    right
    rcases ih with hv | ⟨e', hs⟩
    · rcases canonical_word e n hv hte with ⟨rfl, _⟩ | ⟨gs, rfl, _⟩
      · exact ⟨_, .closeId⟩
      · exact ⟨_, .closeWord gs⟩
    · exact ⟨_, .closeStep e e' hs⟩
  | tLet _ e₁ e₂ τ₁ τ₂ _ _ ih₁ _ =>
    right
    rcases ih₁ with hv₁ | ⟨e₁', hs₁⟩
    · exact ⟨_, .letBeta e₁ e₂ hv₁⟩
    · exact ⟨_, .letStep e₁ e₁' e₂ hs₁⟩
  | tAddNum _ e₁ e₂ ht₁ ht₂ ih₁ ih₂ =>
    right
    rcases ih₁ with hv₁ | ⟨e₁', hs₁⟩
    · rcases ih₂ with hv₂ | ⟨e₂', hs₂⟩
      · obtain ⟨n₁, rfl⟩ := canonical_num e₁ hv₁ ht₁
        obtain ⟨n₂, rfl⟩ := canonical_num e₂ hv₂ ht₂
        exact ⟨_, .addNums n₁ n₂⟩
      · exact ⟨_, .addRight e₁ e₂ e₂' hv₁ hs₂⟩
    · exact ⟨_, .addLeft e₁ e₁' e₂ hs₁⟩
  | tEqWord _ e₁ e₂ n ht₁ ht₂ ih₁ ih₂ =>
    right
    rcases ih₁ with hv₁ | ⟨e₁', hs₁⟩
    · rcases ih₂ with hv₂ | ⟨e₂', hs₂⟩
      · rcases canonical_word e₁ n hv₁ ht₁ with ⟨rfl, _⟩ | ⟨gs₁, rfl, _⟩ <;>
        rcases canonical_word e₂ n hv₂ ht₂ with ⟨rfl, _⟩ | ⟨gs₂, rfl, _⟩
        · exact ⟨_, .eqIdId⟩
        · exact ⟨_, .eqIdBraid gs₂⟩
        · exact ⟨_, .eqBraidId gs₁⟩
        · exact ⟨_, .eqBraids gs₁ gs₂⟩
      · exact ⟨_, .eqRight e₁ e₂ e₂' hv₁ hs₂⟩
    · exact ⟨_, .eqLeft e₁ e₁' e₂ hs₁⟩
  | tEqNum _ e₁ e₂ ht₁ ht₂ ih₁ ih₂ =>
    right
    rcases ih₁ with hv₁ | ⟨e₁', hs₁⟩
    · rcases ih₂ with hv₂ | ⟨e₂', hs₂⟩
      · obtain ⟨n₁, rfl⟩ := canonical_num e₁ hv₁ ht₁
        obtain ⟨n₂, rfl⟩ := canonical_num e₂ hv₂ ht₂
        exact ⟨_, .eqNums n₁ n₂⟩
      · exact ⟨_, .eqRight e₁ e₂ e₂' hv₁ hs₂⟩
    · exact ⟨_, .eqLeft e₁ e₁' e₂ hs₁⟩
  | tEqStr _ e₁ e₂ ht₁ ht₂ ih₁ ih₂ =>
    right
    rcases ih₁ with hv₁ | ⟨e₁', hs₁⟩
    · rcases ih₂ with hv₂ | ⟨e₂', hs₂⟩
      · obtain ⟨s₁, rfl⟩ := canonical_str e₁ hv₁ ht₁
        obtain ⟨s₂, rfl⟩ := canonical_str e₂ hv₂ ht₂
        exact ⟨_, .eqStrs s₁ s₂⟩
      · exact ⟨_, .eqRight e₁ e₂ e₂' hv₁ hs₂⟩
    · exact ⟨_, .eqLeft e₁ e₁' e₂ hs₁⟩

------------------------------------------------------------------------
-- 9. Weakening (lifting) lemma
------------------------------------------------------------------------

/-- Weakening: inserting a type at position c preserves typing for lifted terms. -/
theorem weakening (Γ : Ctx) (e : Expr) (τ τ' : Ty) (c : Nat) (hc : c ≤ Γ.length)
    (ht : HasType Γ e τ) : HasType (Γ.insertIdx c τ') (lift c e) τ := by
  induction ht generalizing c with
  | tNum _ n => simp [lift]; exact .tNum _ n
  | tStr _ s => simp [lift]; exact .tStr _ s
  | tBool _ b => simp [lift]; exact .tBool _ b
  | tIdentity _ => simp [lift]; exact .tIdentity _
  | tBraid _ gs n h => simp [lift]; exact .tBraid _ gs n h
  | tVar Γ₀ i τ'' hlook =>
    simp [lift]
    split
    · rename_i hlt
      apply HasType.tVar
      rw [List.getElem?_insertIdx]
      simp [show i < c from hlt, hlook]
    · rename_i hge
      apply HasType.tVar
      rw [List.getElem?_insertIdx]
      simp [show ¬(i + 1 < c) by omega, show ¬(i + 1 = c) by omega]
      simpa using hlook
  | tComposeWord _ e₁ e₂ n m _ _ ih₁ ih₂ =>
    simp [lift]; exact .tComposeWord _ _ _ n m (ih₁ c hc) (ih₂ c hc)
  | tTensorWord _ e₁ e₂ n m _ _ ih₁ ih₂ =>
    simp [lift]; exact .tTensorWord _ _ _ n m (ih₁ c hc) (ih₂ c hc)
  | tPipeline _ e₁ e₂ τ'' _ ih =>
    simp [lift]; exact .tPipeline _ _ _ τ'' (ih c hc)
  | tCloseWord _ e n _ ih =>
    simp [lift]; exact .tCloseWord _ _ n (ih c hc)
  | tLet Γ₀ e₁ e₂ τ₁ τ₂ _ _ ih₁ ih₂ =>
    simp [lift]
    apply HasType.tLet _ _ _ τ₁ τ₂ (ih₁ c hc)
    have : (τ₁ :: Γ₀).insertIdx (c + 1) τ' = τ₁ :: (Γ₀.insertIdx c τ') :=
      List.insertIdx_succ_cons
    rw [← this]
    exact ih₂ (c + 1) (by simp; omega)
  | tAddNum _ e₁ e₂ _ _ ih₁ ih₂ =>
    simp [lift]; exact .tAddNum _ _ _ (ih₁ c hc) (ih₂ c hc)
  | tEqWord _ e₁ e₂ n _ _ ih₁ ih₂ =>
    simp [lift]; exact .tEqWord _ _ _ n (ih₁ c hc) (ih₂ c hc)
  | tEqNum _ e₁ e₂ _ _ ih₁ ih₂ =>
    simp [lift]; exact .tEqNum _ _ _ (ih₁ c hc) (ih₂ c hc)
  | tEqStr _ e₁ e₂ _ _ ih₁ ih₂ =>
    simp [lift]; exact .tEqStr _ _ _ (ih₁ c hc) (ih₂ c hc)

/-- Corollary: weakening at position 0. -/
theorem weakening_zero (Γ : Ctx) (e : Expr) (τ τ' : Ty)
    (ht : HasType Γ e τ) : HasType (τ' :: Γ) (lift 0 e) τ := by
  have : τ' :: Γ = Γ.insertIdx 0 τ' := by simp [List.insertIdx]
  rw [this]
  exact weakening Γ e τ τ' 0 (Nat.zero_le _) ht

------------------------------------------------------------------------
-- 10. Substitution lemma
------------------------------------------------------------------------

theorem subst_preserves_typing (Γ : Ctx) (e v : Expr) (τ₁ τ₂ : Ty)
    (hte : HasType (τ₁ :: Γ) e τ₂) (htv : HasType Γ v τ₁) :
    HasType Γ (substTop v e) τ₂ := by
  induction hte generalizing v with
  | tNum _ n => exact .tNum _ n
  | tStr _ s => exact .tStr _ s
  | tBool _ b => exact .tBool _ b
  | tIdentity _ => exact .tIdentity _
  | tBraid _ gs n h => exact .tBraid _ gs n h
  | tVar Γ' i τ' hlook =>
    cases i with
    | zero =>
      simp [substTop]
      simp at hlook; subst hlook; exact htv
    | succ j =>
      simp [substTop]
      apply HasType.tVar
      simpa using hlook
  | tComposeWord _ e₁ e₂ n m _ _ ih₁ ih₂ =>
    simp [substTop]; exact .tComposeWord _ _ _ n m (ih₁ htv) (ih₂ htv)
  | tTensorWord _ e₁ e₂ n m _ _ ih₁ ih₂ =>
    simp [substTop]; exact .tTensorWord _ _ _ n m (ih₁ htv) (ih₂ htv)
  | tPipeline _ e₁ e₂ τ' _ ih =>
    simp [substTop]; exact .tPipeline _ _ _ τ' (ih htv)
  | tCloseWord _ e n _ ih =>
    simp [substTop]; exact .tCloseWord _ _ n (ih htv)
  | tLet _ e₁ e₂ τ₁' τ₂' _ _ ih₁ ih₂ =>
    simp [substTop]
    apply HasType.tLet _ _ _ τ₁' τ₂' (ih₁ htv)
    exact ih₂ (weakening_zero Γ v τ₁ τ₁' htv)
  | tAddNum _ e₁ e₂ _ _ ih₁ ih₂ =>
    simp [substTop]; exact .tAddNum _ _ _ (ih₁ htv) (ih₂ htv)
  | tEqWord _ e₁ e₂ n _ _ ih₁ ih₂ =>
    simp [substTop]; exact .tEqWord _ _ _ n (ih₁ htv) (ih₂ htv)
  | tEqNum _ e₁ e₂ _ _ ih₁ ih₂ =>
    simp [substTop]; exact .tEqNum _ _ _ (ih₁ htv) (ih₂ htv)
  | tEqStr _ e₁ e₂ _ _ ih₁ ih₂ =>
    simp [substTop]; exact .tEqStr _ _ _ (ih₁ htv) (ih₂ htv)

------------------------------------------------------------------------
-- 11. Preservation
------------------------------------------------------------------------

private theorem foldl_max_init (gs : List Generator) (a : Nat) :
    gs.foldl (fun acc g => max acc (g.idx + 1)) a =
    max a (gs.foldl (fun acc g => max acc (g.idx + 1)) 0) := by
  induction gs generalizing a with
  | nil => simp [List.foldl]
  | cons g rest ih =>
    simp only [List.foldl]
    rw [ih (max a (g.idx + 1))]
    rw [ih (max 0 (g.idx + 1))]
    omega

theorem generatorWidth_append (gs₁ gs₂ : List Generator) :
    generatorWidth (gs₁ ++ gs₂) = max (generatorWidth gs₁) (generatorWidth gs₂) := by
  simp only [generatorWidth, List.foldl_append]
  rw [foldl_max_init]

private theorem foldl_shift_init (gs : List Generator) (n a : Nat) :
    (gs.map fun g => { idx := g.idx + n, exp := g.exp : Generator}).foldl
      (fun acc g => max acc (g.idx + 1)) a =
    if gs = [] then a
    else max a (gs.foldl (fun acc g => max acc (g.idx + 1)) 0 + n) := by
  induction gs generalizing a with
  | nil => simp [List.foldl, List.map]
  | cons g rest ih =>
    simp only [List.map, List.foldl, List.cons_ne_nil, ↓reduceIte]
    rw [ih]
    rw [foldl_max_init rest (max 0 (g.idx + 1))]
    split
    · rename_i heq; subst heq; simp [List.foldl]; omega
    · omega

theorem generatorWidth_shift (gs : List Generator) (n : Nat) :
    generatorWidth (shiftGenerators gs n) =
    if gs = [] then 0 else generatorWidth gs + n := by
  simp only [generatorWidth, shiftGenerators]
  rw [foldl_shift_init]
  split
  · rename_i h; subst h; simp [List.foldl]
  · simp

theorem preservation (e e' : Expr) (τ : Ty) (ht : HasType [] e τ) (hs : Step e e') :
    HasType [] e' τ := by
  induction hs generalizing τ with
  | composeLeft e₁ e₁' e₂ _ ih =>
    cases ht with | tComposeWord _ _ _ n m h₁ h₂ => exact .tComposeWord _ _ _ n m (ih _ h₁) h₂
  | composeRight e₁ e₂ e₂' _ _ ih =>
    cases ht with | tComposeWord _ _ _ n m h₁ h₂ => exact .tComposeWord _ _ _ n m h₁ (ih _ h₂)
  | composeWords gs₁ gs₂ =>
    cases ht with | tComposeWord _ _ _ n m h₁ h₂ =>
    cases h₁ with | tBraid _ _ _ hn =>
    cases h₂ with | tBraid _ _ _ hm =>
    subst hn; subst hm
    exact .tBraid _ _ _ (generatorWidth_append gs₁ gs₂).symm
  | composeIdL gs =>
    cases ht with | tComposeWord _ _ _ n m h₁ h₂ =>
    cases h₁ with | tIdentity => simp at *; exact h₂
  | composeIdR gs =>
    cases ht with | tComposeWord _ _ _ n m h₁ h₂ =>
    cases h₂ with | tIdentity => simp at *; exact h₁
  | composeIdId =>
    cases ht with | tComposeWord _ _ _ n m h₁ h₂ =>
    cases h₁ with | tIdentity => cases h₂ with | tIdentity => exact .tIdentity _
  | tensorLeft e₁ e₁' e₂ _ ih =>
    cases ht with | tTensorWord _ _ _ n m h₁ h₂ => exact .tTensorWord _ _ _ n m (ih _ h₁) h₂
  | tensorRight e₁ e₂ e₂' _ _ ih =>
    cases ht with | tTensorWord _ _ _ n m h₁ h₂ => exact .tTensorWord _ _ _ n m h₁ (ih _ h₂)
  | tensorWords gs₁ gs₂ =>
    cases ht with | tTensorWord _ _ _ n m h₁ h₂ =>
    cases h₁ with | tBraid _ _ _ hn =>
    cases h₂ with | tBraid _ _ _ hm =>
    subst hn; subst hm
    apply HasType.tBraid _ _ _ _
    rw [generatorWidth_append, generatorWidth_shift]
    split
    · rename_i hempty; subst hempty; simp [generatorWidth, List.foldl]
    · omega
  | tensorIdL gs =>
    cases ht with | tTensorWord _ _ _ n m h₁ h₂ =>
    cases h₁ with | tIdentity => simp at *; exact h₂
  | tensorIdR gs =>
    cases ht with | tTensorWord _ _ _ n m h₁ h₂ =>
    cases h₂ with | tIdentity => simp at *; exact h₁
  | tensorIdId =>
    cases ht with | tTensorWord _ _ _ n m h₁ h₂ =>
    cases h₁ with | tIdentity => cases h₂ with | tIdentity => exact .tIdentity _
  | pipelineDesugar e₁ e₂ =>
    cases ht with | tPipeline _ _ _ _ h => exact h
  | closeStep e e' _ ih =>
    cases ht with | tCloseWord _ _ n h => exact .tCloseWord _ _ n (ih _ h)
  | closeWord gs =>
    cases ht with | tCloseWord => exact .tIdentity _
  | closeId =>
    cases ht with | tCloseWord => exact .tIdentity _
  | letStep e₁ e₁' e₂ _ ih =>
    cases ht with | tLet _ _ _ τ₁ τ₂' h₁ h₂ => exact .tLet _ _ _ τ₁ τ₂' (ih _ h₁) h₂
  | letBeta v e₂ _ =>
    cases ht with | tLet _ _ _ τ₁ τ₂' h₁ h₂ =>
    exact subst_preserves_typing [] e₂ v τ₁ τ₂' h₂ h₁
  | addLeft e₁ e₁' e₂ _ ih =>
    cases ht with | tAddNum _ _ _ h₁ h₂ => exact .tAddNum _ _ _ (ih _ h₁) h₂
  | addRight e₁ e₂ e₂' _ _ ih =>
    cases ht with | tAddNum _ _ _ h₁ h₂ => exact .tAddNum _ _ _ h₁ (ih _ h₂)
  | addNums n₁ n₂ =>
    cases ht with | tAddNum => exact .tNum _ _
  | eqLeft e₁ e₁' e₂ _ ih =>
    cases ht with
    | tEqWord _ _ _ n h₁ h₂ => exact .tEqWord _ _ _ n (ih _ h₁) h₂
    | tEqNum _ _ _ h₁ h₂ => exact .tEqNum _ _ _ (ih _ h₁) h₂
    | tEqStr _ _ _ h₁ h₂ => exact .tEqStr _ _ _ (ih _ h₁) h₂
  | eqRight e₁ e₂ e₂' _ _ ih =>
    cases ht with
    | tEqWord _ _ _ n h₁ h₂ => exact .tEqWord _ _ _ n h₁ (ih _ h₂)
    | tEqNum _ _ _ h₁ h₂ => exact .tEqNum _ _ _ h₁ (ih _ h₂)
    | tEqStr _ _ _ h₁ h₂ => exact .tEqStr _ _ _ h₁ (ih _ h₂)
  | eqNums _ _ =>
    cases ht with
    | tEqNum => exact .tBool _ _
    | tEqWord _ _ _ _ h₁ _ => cases h₁
    | tEqStr _ _ _ h₁ _ => cases h₁
  | eqStrs _ _ =>
    cases ht with
    | tEqStr => exact .tBool _ _
    | tEqWord _ _ _ _ h₁ _ => cases h₁
    | tEqNum _ _ _ h₁ _ => cases h₁
  | eqBraids _ _ =>
    cases ht with
    | tEqWord => exact .tBool _ _
    | tEqNum _ _ _ h₁ _ => cases h₁
    | tEqStr _ _ _ h₁ _ => cases h₁
  | eqIdId =>
    cases ht with
    | tEqWord => exact .tBool _ _
    | tEqNum _ _ _ h₁ _ => cases h₁
    | tEqStr _ _ _ h₁ _ => cases h₁
  | eqIdBraid _ =>
    cases ht with
    | tEqWord => exact .tBool _ _
    | tEqNum _ _ _ h₁ _ => cases h₁
    | tEqStr _ _ _ h₁ _ => cases h₁
  | eqBraidId _ =>
    cases ht with
    | tEqWord => exact .tBool _ _
    | tEqNum _ _ _ h₁ _ => cases h₁
    | tEqStr _ _ _ h₁ _ => cases h₁

------------------------------------------------------------------------
-- 12. Determinism
------------------------------------------------------------------------

theorem determinism (e e₁ e₂ : Expr) (hs₁ : Step e e₁) (hs₂ : Step e e₂) : e₁ = e₂ := by
  induction hs₁ generalizing e₂ with
  | composeLeft a a' b _ ih =>
    cases hs₂ with
    | composeLeft _ a'' _ h => exact congrArg (·.compose b) (ih a'' h)
    | composeRight _ _ _ hv _ => exact absurd ‹Step a a'› (value_no_step a hv a')
    | composeWords gs₁ _ => exact absurd ‹Step a a'› (value_no_step _ (.braidLit gs₁) _)
    | composeIdL _ => exact absurd ‹Step a a'› (value_no_step _ .identity _)
    | composeIdR _ => exact absurd ‹Step a a'› (value_no_step _ (.braidLit _) _)
    | composeIdId => exact absurd ‹Step a a'› (value_no_step _ .identity _)
  | composeRight a b b' hv _ ih =>
    cases hs₂ with
    | composeLeft _ a' _ h => exact absurd h (value_no_step a hv a')
    | composeRight _ _ b'' _ h => exact congrArg (a.compose ·) (ih b'' h)
    | composeWords _ gs₂ => exact absurd ‹Step b b'› (value_no_step _ (.braidLit gs₂) _)
    | composeIdL _ => exact absurd ‹Step b b'› (value_no_step _ (.braidLit _) _)
    | composeIdR _ => exact absurd ‹Step b b'› (value_no_step _ .identity _)
    | composeIdId =>
      cases hv with | identity => exact absurd ‹Step b b'› (value_no_step _ .identity _)
  | composeWords gs₁ gs₂ =>
    cases hs₂ with
    | composeLeft _ _ _ h => exact absurd h (value_no_step _ (.braidLit gs₁) _)
    | composeRight _ _ _ _ h => exact absurd h (value_no_step _ (.braidLit gs₂) _)
    | composeWords _ _ => rfl
  | composeIdL gs =>
    cases hs₂ with
    | composeLeft _ _ _ h => exact absurd h (value_no_step _ .identity _)
    | composeRight _ _ _ _ h => exact absurd h (value_no_step _ (.braidLit gs) _)
    | composeIdL _ => rfl
  | composeIdR gs =>
    cases hs₂ with
    | composeLeft _ _ _ h => exact absurd h (value_no_step _ (.braidLit gs) _)
    | composeRight _ _ _ _ h => exact absurd h (value_no_step _ .identity _)
    | composeIdR _ => rfl
  | composeIdId =>
    cases hs₂ with
    | composeLeft _ _ _ h => exact absurd h (value_no_step _ .identity _)
    | composeRight _ _ _ _ h => exact absurd h (value_no_step _ .identity _)
    | composeIdId => rfl
  | tensorLeft a a' b _ ih =>
    cases hs₂ with
    | tensorLeft _ a'' _ h => exact congrArg (·.tensor b) (ih a'' h)
    | tensorRight _ _ _ hv _ => exact absurd ‹Step a a'› (value_no_step a hv a')
    | tensorWords gs₁ _ => exact absurd ‹Step a a'› (value_no_step _ (.braidLit gs₁) _)
    | tensorIdL _ => exact absurd ‹Step a a'› (value_no_step _ .identity _)
    | tensorIdR _ => exact absurd ‹Step a a'› (value_no_step _ (.braidLit _) _)
    | tensorIdId => exact absurd ‹Step a a'› (value_no_step _ .identity _)
  | tensorRight a b b' hv _ ih =>
    cases hs₂ with
    | tensorLeft _ a' _ h => exact absurd h (value_no_step a hv a')
    | tensorRight _ _ b'' _ h => exact congrArg (a.tensor ·) (ih b'' h)
    | tensorWords _ gs₂ => exact absurd ‹Step b b'› (value_no_step _ (.braidLit gs₂) _)
    | tensorIdL _ => exact absurd ‹Step b b'› (value_no_step _ (.braidLit _) _)
    | tensorIdR _ => exact absurd ‹Step b b'› (value_no_step _ .identity _)
    | tensorIdId =>
      cases hv with | identity => exact absurd ‹Step b b'› (value_no_step _ .identity _)
  | tensorWords gs₁ gs₂ =>
    cases hs₂ with
    | tensorLeft _ _ _ h => exact absurd h (value_no_step _ (.braidLit gs₁) _)
    | tensorRight _ _ _ _ h => exact absurd h (value_no_step _ (.braidLit gs₂) _)
    | tensorWords _ _ => rfl
  | tensorIdL gs =>
    cases hs₂ with
    | tensorLeft _ _ _ h => exact absurd h (value_no_step _ .identity _)
    | tensorRight _ _ _ _ h => exact absurd h (value_no_step _ (.braidLit gs) _)
    | tensorIdL _ => rfl
  | tensorIdR gs =>
    cases hs₂ with
    | tensorLeft _ _ _ h => exact absurd h (value_no_step _ (.braidLit gs) _)
    | tensorRight _ _ _ _ h => exact absurd h (value_no_step _ .identity _)
    | tensorIdR _ => rfl
  | tensorIdId =>
    cases hs₂ with
    | tensorLeft _ _ _ h => exact absurd h (value_no_step _ .identity _)
    | tensorRight _ _ _ _ h => exact absurd h (value_no_step _ .identity _)
    | tensorIdId => rfl
  | pipelineDesugar e₁ e₂ => cases hs₂ with | pipelineDesugar => rfl
  | closeStep e e' _ ih =>
    cases hs₂ with
    | closeStep _ e'' h => exact congrArg Expr.close (ih e'' h)
    | closeWord gs => exact absurd ‹Step e e'› (value_no_step _ (.braidLit gs) _)
    | closeId => exact absurd ‹Step e e'› (value_no_step _ .identity _)
  | closeWord gs =>
    cases hs₂ with
    | closeStep _ _ h => exact absurd h (value_no_step _ (.braidLit gs) _)
    | closeWord _ => rfl
  | closeId =>
    cases hs₂ with
    | closeStep _ _ h => exact absurd h (value_no_step _ .identity _)
    | closeId => rfl
  | letStep e₁ e₁' e₂ _ ih =>
    cases hs₂ with
    | letStep _ e₁'' _ h => exact congrArg (·.letE e₂) (ih e₁'' h)
    | letBeta _ _ hv => exact absurd ‹Step e₁ e₁'› (value_no_step _ hv _)
  | letBeta v e₂ hv =>
    cases hs₂ with
    | letStep _ e₁' _ h => exact absurd h (value_no_step _ hv _)
    | letBeta _ _ _ => rfl
  | addLeft a a' b _ ih =>
    cases hs₂ with
    | addLeft _ a'' _ h => exact congrArg (·.add b) (ih a'' h)
    | addRight _ _ _ hv _ => exact absurd ‹Step a a'› (value_no_step _ hv _)
    | addNums n₁ _ => exact absurd ‹Step a a'› (value_no_step _ (.num n₁) _)
  | addRight a b b' hv _ ih =>
    cases hs₂ with
    | addLeft _ a' _ h => exact absurd h (value_no_step _ hv _)
    | addRight _ _ b'' _ h => exact congrArg (a.add ·) (ih b'' h)
    | addNums _ n₂ => exact absurd ‹Step b b'› (value_no_step _ (.num n₂) _)
  | addNums n₁ n₂ =>
    cases hs₂ with
    | addLeft _ _ _ h => exact absurd h (value_no_step _ (.num n₁) _)
    | addRight _ _ _ _ h => exact absurd h (value_no_step _ (.num n₂) _)
    | addNums _ _ => rfl
  | eqLeft a a' b _ ih =>
    cases hs₂ with
    | eqLeft _ a'' _ h => exact congrArg (·.eq b) (ih a'' h)
    | eqRight _ _ _ hv _ => exact absurd ‹Step a a'› (value_no_step _ hv _)
    | eqNums n₁ _ => exact absurd ‹Step a a'› (value_no_step _ (.num n₁) _)
    | eqStrs s₁ _ => exact absurd ‹Step a a'› (value_no_step _ (.str s₁) _)
    | eqBraids gs₁ _ => exact absurd ‹Step a a'› (value_no_step _ (.braidLit gs₁) _)
    | eqIdId => exact absurd ‹Step a a'› (value_no_step _ .identity _)
    | eqIdBraid _ => exact absurd ‹Step a a'› (value_no_step _ .identity _)
    | eqBraidId gs => exact absurd ‹Step a a'› (value_no_step _ (.braidLit gs) _)
  | eqRight a b b' hv _ ih =>
    cases hs₂ with
    | eqLeft _ a' _ h => exact absurd h (value_no_step _ hv _)
    | eqRight _ _ b'' _ h => exact congrArg (a.eq ·) (ih b'' h)
    | eqNums _ n₂ => exact absurd ‹Step b b'› (value_no_step _ (.num n₂) _)
    | eqStrs _ s₂ => exact absurd ‹Step b b'› (value_no_step _ (.str s₂) _)
    | eqBraids _ gs₂ => exact absurd ‹Step b b'› (value_no_step _ (.braidLit gs₂) _)
    | eqIdId =>
      cases hv with | identity => exact absurd ‹Step b b'› (value_no_step _ .identity _)
    | eqIdBraid gs =>
      cases hv with | identity => exact absurd ‹Step b b'› (value_no_step _ (.braidLit gs) _)
    | eqBraidId _ =>
      cases hv with | braidLit gs => exact absurd ‹Step b b'› (value_no_step _ .identity _)
  | eqNums n₁ n₂ =>
    cases hs₂ with
    | eqLeft _ _ _ h => exact absurd h (value_no_step _ (.num n₁) _)
    | eqRight _ _ _ _ h => exact absurd h (value_no_step _ (.num n₂) _)
    | eqNums _ _ => rfl
  | eqStrs s₁ s₂ =>
    cases hs₂ with
    | eqLeft _ _ _ h => exact absurd h (value_no_step _ (.str s₁) _)
    | eqRight _ _ _ _ h => exact absurd h (value_no_step _ (.str s₂) _)
    | eqStrs _ _ => rfl
  | eqBraids gs₁ gs₂ =>
    cases hs₂ with
    | eqLeft _ _ _ h => exact absurd h (value_no_step _ (.braidLit gs₁) _)
    | eqRight _ _ _ _ h => exact absurd h (value_no_step _ (.braidLit gs₂) _)
    | eqBraids _ _ => rfl
  | eqIdId =>
    cases hs₂ with
    | eqLeft _ _ _ h => exact absurd h (value_no_step _ .identity _)
    | eqRight _ _ _ _ h => exact absurd h (value_no_step _ .identity _)
    | eqIdId => rfl
  | eqIdBraid gs =>
    cases hs₂ with
    | eqLeft _ _ _ h => exact absurd h (value_no_step _ .identity _)
    | eqRight _ _ _ _ h => exact absurd h (value_no_step _ (.braidLit gs) _)
    | eqIdBraid _ => rfl
  | eqBraidId gs =>
    cases hs₂ with
    | eqLeft _ _ _ h => exact absurd h (value_no_step _ (.braidLit gs) _)
    | eqRight _ _ _ _ h => exact absurd h (value_no_step _ .identity _)
    | eqBraidId _ => rfl

------------------------------------------------------------------------
-- 13. Type safety corollary
------------------------------------------------------------------------

theorem type_safety (e e' : Expr) (τ : Ty)
    (ht : HasType [] e τ) (hs : Step e e') :
    HasType [] e' τ ∧ (IsValue e' ∨ ∃ e'', Step e' e'') :=
  ⟨preservation e e' τ ht hs, progress e' τ (preservation e e' τ ht hs)⟩

end Tangle
