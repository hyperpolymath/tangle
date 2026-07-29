(* SPDX-License-Identifier: MPL-2.0 *)
(* ast.ml — Abstract syntax tree for the core TANGLE language.
 *
 * Mirrors the EBNF grammar in src/tangle.ebnf and the formal semantics
 * in docs/spec/FORMAL-SEMANTICS.md.  JTV extensions are NOT included
 * here; this module covers the base topological braid language only.
 *)

(** A complete TANGLE program is a list of top-level statements. *)
type program = statement list

(** Top-level statement forms. *)
and statement =
  | Definition  of definition
  | WeaveBlock  of weave_block
  | Computation of computation
  | Assertion   of expr
  | StmtError   (** Placeholder for a statement that failed to parse *)

(** Named definition: [def name(params) = body].
 *  When [params] is empty the definition is a simple binding.
 *  The body may reference [name] for recursion.
 *)
and definition = {
  def_name   : string;
  def_params : string list;
  def_body   : expr;
  def_line   : int;          (** 1-based source line of the `def` keyword; 0 if synthesised *)
}

(** Weave block: [weave strands <inputs> into <body> yield strands <outputs>].
 *  Declares named strands, composes them through an expression, and
 *  yields the resulting output strands.
 *)
and weave_block = {
  weave_inputs  : typed_strand list;
  weave_body    : expr;
  weave_outputs : typed_strand list;
}

(** A strand declaration with an optional type annotation. *)
and typed_strand = {
  strand_name : string;
  strand_type : string option;
}

(** Invariant computation: [compute <invariant>(<expr>)]. *)
and computation = {
  comp_invariant : string;
  comp_arg       : expr;
}

(** Expression AST.
 *
 *  Precedence (lowest to highest):
 *    match / let       — control flow
 *    >>                — pipeline (left-assoc)
 *    == ~              — equality / isotopy (non-assoc)
 *    + -               — addition / subtraction (left-assoc)
 *    * /               — multiplication / division (left-assoc)
 *    .                 — vertical compose / cons (left-assoc)
 *    |                 — horizontal tensor (left-assoc)
 *    unary / primary   — atoms and prefix operations
 *)
and expr =
  (* ---- Control flow ---- *)
  | Match     of expr * match_arm list
  | Let       of string * expr * expr

  (* ---- Binary operators (by precedence) ---- *)
  | Pipeline  of expr * expr          (* >> *)
  | BinOp     of binop * expr * expr

  (* ---- Unary / prefix operations ---- *)
  | UnaryOp   of unaryop * expr
  | Close     of expr
  | Mirror    of expr
  | Reverse   of expr
  | Simplify  of expr
  | Cap       of expr * expr
  | Cup       of expr * expr
  | Twist     of expr

  (* ---- Echo types (structured loss) — mirror the Lean spec in
   *      proofs/Tangle.lean (Ty.echo / Ty.prod and the echo operations).
   *      Typed by typecheck.ml; surface parser syntax is a follow-on. ---- *)
  | EchoClose of expr                 (* echo-preserving closure (residue-retaining close) *)
  | Lower     of expr                 (* project an echo to its result *)
  | Residue   of expr                 (* project an echo to its residue (recover witness) *)
  | Pair      of expr * expr          (* product introduction *)
  | Fst       of expr                 (* first projection *)
  | Snd       of expr                 (* second projection *)
  | EchoAdd   of expr * expr          (* echo-preserving addition (residue = summand pair) *)
  | EchoEq    of expr * expr          (* echo-preserving equality (residue = operand pair) *)

  (* ---- Epistemic (warranted claim) — mirrors §EPISTEMIC in
   *      proofs/Tangle.lean and epistemic-types' Warrant.agda.
   *      NON-FACTIVE: `Evidence` is the only elimination.  There is no
   *      operation taking a warrant to the thing warranted. ---- *)
  (* ---- JTV injection island (D2.1) ----
   * `add{ he }` embeds a Harvard DATA expression into TANGLE.
   *
   * Deliberately a SEPARATE grammar, not more TANGLE expressions: the whole
   * point of the island is semantic separation.  `+` in TANGLE is connect-sum
   * on tangles; `+` inside add{} is arithmetic.  Sharing one `expr` type would
   * lose exactly the distinction the design exists to make (README-jtv.adoc,
   * "Semantic Separation").
   *
   * The block is total and pure by construction: no side effects, no loops, no
   * assignment, guaranteed terminating (D2.1). *)
  | AddBlock  of hv_expr             (* add{ he } *)

  | Warrant   of int * expr * expr    (* warrant κ claim evidence (redex) *)
  | EpiVal    of int * expr * expr    (* formed warrant: standpoint, claim, token *)
  | Evidence  of expr                 (* project the evidence token (ONLY elimination) *)

  (* ---- Literals ---- *)
  | BraidLit  of generator list
  | Identity
  | BoolLit   of bool
  | IntLit    of int
  | FloatLit  of float
  | StringLit of string

  (* ---- References / application ---- *)
  | Var       of string
  | Call      of string * expr list

  (* ---- Crossings (weave context) ---- *)
  | Crossing  of string * crossing_op * string

  (* ---- Weave as an EXPRESSION ----
   * `weave ... into ... yield ...` was a statement only, per spec/grammar.ebnf.
   * As a statement it is inert: eval returns (env, None) and the typechecker
   * discards the Tangle[A,B] it computes, so the construct could be written
   * but never bound or used.  Allowing it in expression position is what makes
   * it reachable — and is how conformance/valid/v02, v08, v09 and v12 have
   * always been written (`def x = weave ...`).  The statement form is kept, so
   * this is purely additive.  Weave is outside the mechanised Lean core (0
   * occurrences in proofs/Tangle.lean) and outside the TG-3 corpus, so this
   * touches no proof obligation. *)
  | Weave     of weave_block

(** Harvard DATA expressions — the `add{...}` island (spec section 6.2).
    Separate from [expr] on purpose; see [AddBlock].

    Implemented here: the scalar-literal fragment with the full operator
    hierarchy and the conditional.  NOT implemented, and NOT pretended:
    rationals, complex numbers, lists and tuples (spec section 7.1); variables
    resolving in the Pi environment and function calls (sections 8.2, 9.5); and
    the `harvard{...}` CONTROL block (section 6.3) entirely. *)
and hv_expr =
  | HvInt   of int
  | HvFloat of float
  | HvStr   of string
  | HvBool  of bool
  | HvUn    of hv_unop * hv_expr
  | HvBin   of hv_binop * hv_expr * hv_expr
  | HvIf    of hv_expr * hv_expr * hv_expr   (* total: both branches required *)

and hv_unop =
  | HvNeg      (* - *)
  | HvNot      (* ! *)

and hv_binop =
  | HvAdd | HvSub | HvMul | HvDiv | HvMod
  | HvEq  | HvNe  | HvLt  | HvLe  | HvGt | HvGe
  | HvAnd | HvOr

(** Binary operator tag. *)
and binop =
  | Add       (** + *)
  | Sub       (** - *)
  | Mul       (** * *)
  | Div       (** / *)
  | Eq        (** == *)
  | Isotopy   (** ~ *)
  | Compose   (** .  — vertical stack *)
  | Tensor    (** |  — horizontal lay *)

(** Unary operator tag. *)
and unaryop =
  | Neg       (** arithmetic negation *)
  | Not       (** logical negation *)

(** Crossing direction within a weave block. *)
and crossing_op =
  | Over      (** > — strand a passes over strand b *)
  | Under     (** < — strand a passes under strand b *)

(** A braid generator with its index and exponent.
 *
 *  [{ gen_index = 1; gen_exponent = 1 }]  represents sigma_1
 *  [{ gen_index = 2; gen_exponent = -1 }] represents sigma_2 inverse
 *)
and generator = {
  gen_index    : int;
  gen_exponent : int;
}

(** A match arm: [| pattern => body]. *)
and match_arm = {
  arm_pattern : pattern;
  arm_body    : expr;
}

(** Structural patterns over braid words.
 *
 *  - [PatIdentity]       matches the empty braid word (identity element)
 *  - [PatCons (g, rest)] matches generator [g] consed onto [rest]
 *  - [PatVar name]       binds the matched value to [name]
 *  - [PatWildcard]       matches anything without binding
 *)
and pattern =
  | PatIdentity
  | PatCons     of gen_pattern * pattern
  | PatVar      of string
  | PatWildcard

(** Generator pattern used in [PatCons]. *)
and gen_pattern = {
  gpat_index    : int;
  gpat_exponent : int;
}
