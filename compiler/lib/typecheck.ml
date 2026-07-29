(* SPDX-License-Identifier: MPL-2.0 *)
(* typecheck.ml — Type checker for the core TANGLE language.
 *
 * Implements all 37 typing rules from docs/spec/FORMAL-SEMANTICS.md (Part 1).
 * The checker performs two passes over a program:
 *   Pass 1: Collect all [def] names and infer their types into Gamma.
 *   Pass 2: Type-check every statement against the complete Gamma.
 *
 * Key types from the formal semantics:
 *   - Word[n]        — braid word on n strands
 *   - Tangle[A, B]   — morphism from boundary A to boundary B
 *   - Num            — numbers (integers and floats)
 *   - Bool           — booleans
 *   - Str            — strings
 *
 * Width inference: width(braid[g1,...,gk]) = max(index(gj) + 1).
 * Auto-widening: composing Word[n] . Word[m] yields Word[max(n,m)].
 *)

open Ast

(* ================================================================== *)
(*  Types                                                              *)
(* ================================================================== *)

(** Strand type within a boundary. *)
type strand_type =
  | StrandDefault       (** Default homogeneous strand type *)
  | StrandNamed of string  (** Named strand type from weave declaration *)

(** Boundary: an ordered list of strand types. *)
type boundary = strand_type list

(** The empty boundary (I). *)
let empty_boundary : boundary = []

(** TANGLE types as defined in FORMAL-SEMANTICS.md section 2.1. *)
type ty =
  | TWord   of int                  (** Word[n] — braid word on n strands *)
  | TTangle of boundary * boundary  (** Tangle[A, B] — morphism *)
  | TNum                            (** Num — integers and floats *)
  | TBool                           (** Bool — booleans *)
  | TStr                            (** Str — strings *)
  | TProd   of ty * ty              (** ρ × σ — product / residue carrier for lossy ops *)
  | TEcho   of ty * ty              (** Echo[ρ, τ] — structured loss: residue ρ, result τ.
                                        Mirrors Ty.echo in proofs/Tangle.lean. *)
  | TEpi    of int * ty * ty        (** Epi[κ, ρ, τ] — at standpoint κ, evidence ρ
                                        purporting to support claim τ.  Mirrors
                                        Ty.epi in proofs/Tangle.lean.  τ appears
                                        in the type but NO rule eliminates to it:
                                        a warrant is not knowledge. *)

(** Function signature: (param_types) -> return_type. *)
type fun_sig = {
  fsig_params : ty list;
  fsig_return : ty;
}

(** Entry in the type environment. *)
type env_entry =
  | EVal of ty         (** Value binding *)
  | EFun of fun_sig    (** Function binding *)

(** Strand context entry for weave blocks (section 3.10). *)
type strand_entry = {
  strand_pos  : int;         (** Position index (1-based) *)
  strand_ty   : strand_type; (** Strand type *)
}

(** Type environment Gamma: maps names to types or function signatures. *)
type env = (string * env_entry) list

(** Strand context Sigma: maps strand names to positions and types. *)
type strand_ctx = (string * strand_entry) list

(* ================================================================== *)
(*  Error reporting                                                    *)
(* ================================================================== *)

(** A type error with a human-readable message. *)
exception Type_error of string

(** Raise a type error with a formatted message. *)
let type_error fmt =
  Printf.ksprintf (fun msg -> raise (Type_error msg)) fmt

(** Pretty-print a strand type. *)
let pp_strand_type = function
  | StrandDefault  -> "Strand"
  | StrandNamed s  -> s

(** Pretty-print a boundary. *)
let pp_boundary (b : boundary) : string =
  match b with
  | [] -> "I"
  | _  ->
    "[" ^ String.concat ", " (List.map pp_strand_type b) ^ "]"

(** Pretty-print a type. *)
let rec pp_ty = function
  | TWord n        -> Printf.sprintf "Word[%d]" n
  | TTangle (a, b) -> Printf.sprintf "Tangle[%s, %s]" (pp_boundary a) (pp_boundary b)
  | TNum           -> "Num"
  | TBool          -> "Bool"
  | TStr           -> "Str"
  | TProd (a, b)   -> Printf.sprintf "(%s * %s)" (pp_ty a) (pp_ty b)
  | TEcho (r, t)   -> Printf.sprintf "Echo[%s, %s]" (pp_ty r) (pp_ty t)
  | TEpi (k, r, t) -> Printf.sprintf "Epi[%d, %s, %s]" k (pp_ty r) (pp_ty t)

(* ================================================================== *)
(*  Environment operations                                             *)
(* ================================================================== *)

(** Look up a name in the environment. *)
let env_lookup (gamma : env) (name : string) : env_entry option =
  List.assoc_opt name gamma

(** Extend the environment with a value binding. *)
let env_bind_val (gamma : env) (name : string) (ty : ty) : env =
  (name, EVal ty) :: gamma

(** Extend the environment with a function binding. *)
let env_bind_fun (gamma : env) (name : string) (sig_ : fun_sig) : env =
  (name, EFun sig_) :: gamma

(** Look up a strand name in the strand context. *)
let strand_lookup (sigma : strand_ctx) (name : string) : strand_entry option =
  List.assoc_opt name sigma

(* ================================================================== *)
(*  Width inference (section 2.5 / 3.14)                               *)
(* ================================================================== *)

(** Compute the width of a list of generators.
 *  width(braid[g1,...,gk]) = max(index(gj) + 1 for j = 1..k), or 0 if empty.
 *)
let width_of_generators (gens : generator list) : int =
  List.fold_left (fun acc g -> max acc (g.gen_index + 1)) 0 gens

(* ================================================================== *)
(*  Permutation tracking (section 2.6)                                 *)
(* ================================================================== *)

(** Apply a single transposition (i, i+1) to a boundary.
 *  Indices are 1-based as specified.
 *)
let swap_boundary (b : boundary) (i : int) : boundary =
  let arr = Array.of_list b in
  let n = Array.length arr in
  if i >= 1 && i < n then begin
    let tmp = arr.(i - 1) in
    arr.(i - 1) <- arr.(i);
    arr.(i) <- tmp
  end;
  Array.to_list arr

(** Compute the permutation induced by a sequence of generators on a boundary.
 *  Each generator sigma_i swaps positions i and i+1.
 *)
let apply_perm (b : boundary) (gens : generator list) : boundary =
  List.fold_left (fun acc g -> swap_boundary acc g.gen_index) b gens

(* ================================================================== *)
(*  Type inference for expressions                                     *)
(* ================================================================== *)

(** Infer the type of an expression under environment Gamma.
 *  Optionally takes a strand context Sigma for weave block bodies.
 *
 *  This implements all expression typing rules from section 3 of the
 *  formal semantics.
 *)
let rec infer_expr (gamma : env) (sigma : strand_ctx) (e : expr) : ty =
  match e with

  (* ---- Literals ---- *)

  (* [T-Num] *)
  | IntLit _   -> TNum
  | FloatLit _ -> TNum

  (* [T-Str] *)
  | StringLit _ -> TStr

  (* [T-True], [T-False] *)
  | BoolLit _ -> TBool

  (* [T-Identity] (D1.14): identity : Word[0] *)
  | Identity -> TWord 0

  (* [T-Braid], [T-Braid-Empty]:
   *   braid[g1,...,gk] : Word[max(index(gj) + 1)]
   *)
  | BraidLit gens ->
    let n = width_of_generators gens in
    TWord n

  (* [T-Weave] in expression position.
     The statement form computed this same Tangle[A,B] and then DISCARDED it
     (`let _weave_ty = ... in gamma`), which is why weave was inert.  Here the
     type is the expression's type, so the result can be bound and used. *)
  | Weave wb ->
    let sigma' = List.mapi (fun i ts ->
      let sty = match ts.strand_type with
        | Some name -> StrandNamed name
        | None      -> StrandDefault
      in
      (ts.strand_name, { strand_pos = i + 1; strand_ty = sty })
    ) wb.weave_inputs in
    let input_boundary = List.map (fun (_, se) -> se.strand_ty) sigma' in
    (* The body is checked in the strand context, exactly as the statement
       form does — strand names are only meaningful there. *)
    let body_ty = infer_expr gamma sigma' wb.weave_body in
    begin match body_ty with
    | TTangle (_, _) | TWord _ -> ()   (* words coerce to tangles *)
    | _ ->
      type_error "Weave body must produce a Word or Tangle type, got %s"
        (pp_ty body_ty)
    end;
    let output_boundary = List.map (fun ts ->
      match ts.strand_type with
      | Some name -> StrandNamed name
      | None      -> StrandDefault
    ) wb.weave_outputs in
    TTangle (input_boundary, output_boundary)

  (* [T-Warrant] / [T-Epi-Val] / [T-Evidence] — epistemic.
     Note the absence: no case here produces τ from an Epi.  `Evidence` yields
     the token type ρ, and that is the only elimination.  Contrast `Lower`,
     which DOES deliver an echo's result. *)
  | Warrant (k, claim, ev) ->
    let t_claim = infer_expr gamma sigma claim in
    let t_ev    = infer_expr gamma sigma ev in
    TEpi (k, t_ev, t_claim)

  | EpiVal (k, claim, ev) ->
    let t_claim = infer_expr gamma sigma claim in
    let t_ev    = infer_expr gamma sigma ev in
    TEpi (k, t_ev, t_claim)

  | Evidence e ->
    begin match infer_expr gamma sigma e with
    | TEpi (_, rho, _) -> rho
    | t -> type_error "evidence requires an Epi[k, rho, tau], got %s" (pp_ty t)
    end

  (* ---- Variables [T-Var] ---- *)

  | Var name ->
    begin match env_lookup gamma name with
    | Some (EVal ty) -> ty
    | Some (EFun _)  -> type_error "Cannot use function '%s' as a value" name
    | None ->
      (* Check strand context for weave block references *)
      begin match strand_lookup sigma name with
      | Some _entry ->
        type_error "Strand name '%s' cannot be used as a standalone expression \
                    (use crossing syntax: a > b or a < b)" name
      | None ->
        type_error "Unbound variable '%s'" name
      end
    end

  (* ---- Function application [T-App] ---- *)

  | Call (fname, args) ->
    begin match env_lookup gamma fname with
    | Some (EFun fsig) ->
      let n_expected = List.length fsig.fsig_params in
      let n_actual = List.length args in
      if n_expected <> n_actual then
        type_error "Function '%s' expects %d argument(s) but got %d"
          fname n_expected n_actual;
      List.iter2 (fun param_ty arg_expr ->
        let arg_ty = infer_expr gamma sigma arg_expr in
        check_compatible param_ty arg_ty fname
      ) fsig.fsig_params args;
      fsig.fsig_return
    | Some (EVal _) ->
      type_error "'%s' is not a function" fname
    | None ->
      type_error "Unbound function '%s'" fname
    end

  (* ---- Binary operators ---- *)

  | BinOp (op, e1, e2) ->
    let t1 = infer_expr gamma sigma e1 in
    let t2 = infer_expr gamma sigma e2 in
    infer_binop op t1 t2

  (* [T-Compose-Word], [T-Compose-Tangle] via Pipeline desugaring [T-Pipeline] *)
  | Pipeline (e1, e2) ->
    let t1 = infer_expr gamma sigma e1 in
    let t2 = infer_expr gamma sigma e2 in
    infer_binop Compose t1 t2

  (* ---- Unary operators ---- *)

  | UnaryOp (Neg, e1) ->
    let t = infer_expr gamma sigma e1 in
    begin match t with
    | TNum -> TNum
    | _    -> type_error "Negation requires Num, got %s" (pp_ty t)
    end

  | UnaryOp (Not, e1) ->
    let t = infer_expr gamma sigma e1 in
    begin match t with
    | TBool -> TBool
    | _     -> type_error "Logical not requires Bool, got %s" (pp_ty t)
    end

  (* ---- Tier 1 primitives ---- *)

  (* [T-Close-Word], [T-Close-Tangle] *)
  | Close e1 ->
    let t = infer_expr gamma sigma e1 in
    begin match t with
    | TWord _        -> TTangle (empty_boundary, empty_boundary)
    | TTangle (a, b) ->
      if List.length a <> List.length b then
        type_error "close requires |A| = |B|, got |%s| = %d and |%s| = %d"
          (pp_boundary a) (List.length a)
          (pp_boundary b) (List.length b);
      TTangle (empty_boundary, empty_boundary)
    | _ -> type_error "close requires Word[n] or Tangle[A,B], got %s" (pp_ty t)
    end

  (* [T-Mirror-Word], [T-Mirror-Tangle] *)
  | Mirror e1 ->
    let t = infer_expr gamma sigma e1 in
    begin match t with
    | TWord n        -> TWord n
    | TTangle (a, b) -> TTangle (b, a)
    | _ -> type_error "mirror requires Word[n] or Tangle[A,B], got %s" (pp_ty t)
    end

  (* [T-Reverse] *)
  | Reverse e1 ->
    let t = infer_expr gamma sigma e1 in
    begin match t with
    | TWord n -> TWord n
    | _       -> type_error "reverse requires Word[n], got %s" (pp_ty t)
    end

  (* [T-Simplify-Word], [T-Simplify-Tangle] *)
  | Simplify e1 ->
    let t = infer_expr gamma sigma e1 in
    begin match t with
    | TWord n        -> TWord n
    | TTangle (a, b) -> TTangle (a, b)
    | _ -> type_error "simplify requires Word[n] or Tangle[A,B], got %s" (pp_ty t)
    end

  (* [T-Cap], [T-Cap-Typed] *)
  | Cap (e1, e2) ->
    let t1 = infer_expr gamma sigma e1 in
    let t2 = infer_expr gamma sigma e2 in
    (* Cap creates a tangle that absorbs two strands from above *)
    let s1 = strand_type_of_ty t1 in
    let s2 = strand_type_of_ty t2 in
    TTangle ([s1; s2], empty_boundary)

  (* [T-Cup], [T-Cup-Typed] *)
  | Cup (e1, e2) ->
    let t1 = infer_expr gamma sigma e1 in
    let t2 = infer_expr gamma sigma e2 in
    (* Cup creates a tangle that emits two strands below *)
    let s1 = strand_type_of_ty t1 in
    let s2 = strand_type_of_ty t2 in
    TTangle (empty_boundary, [s1; s2])

  (* [T-Twist-Word], [T-Twist-Tangle] (D1.18) *)
  | Twist e1 ->
    let t = infer_expr gamma sigma e1 in
    begin match t with
    | TWord n        -> TWord n
    | TTangle (a, b) -> TTangle (a, b)
    | _ -> type_error "twist requires Word[n] or Tangle[A,B], got %s" (pp_ty t)
    end

  (* ---- Crossings in weave context [T-Cross-Over], [T-Cross-Under] ---- *)

  | Crossing (a, op, b) ->
    begin match strand_lookup sigma a, strand_lookup sigma b with
    | Some ea, Some eb ->
      if ea.strand_pos = eb.strand_pos && a <> b then
        type_error "Strands '%s' and '%s' have the same position %d"
          a b ea.strand_pos;
      (* Self-crossing [T-Self-Cross] desugars to twist *)
      if a = b then begin
        let _ = op in  (* direction is ignored for self-crossing *)
        TTangle ([strand_to_type ea.strand_ty], [strand_to_type ea.strand_ty])
      end else begin
        (* Build the boundary from strand context and compute swap *)
        let all_strands = List.sort (fun (_, e1) (_, e2) ->
          compare e1.strand_pos e2.strand_pos) sigma in
        let input_boundary = List.map (fun (_, e) -> e.strand_ty) all_strands in
        let output_boundary =
          swap_boundary input_boundary (min ea.strand_pos eb.strand_pos) in
        TTangle (input_boundary, output_boundary)
      end
    | None, _ -> type_error "Unknown strand '%s' in crossing" a
    | _, None -> type_error "Unknown strand '%s' in crossing" b
    end

  (* ---- Let binding [T-Let] ---- *)

  | Let (x, e1, e2) ->
    let t1 = infer_expr gamma sigma e1 in
    let gamma' = env_bind_val gamma x t1 in
    infer_expr gamma' sigma e2

  (* ---- Pattern matching [T-Match] ---- *)

  | Match (scrutinee, arms) ->
    let t_scrutinee = infer_expr gamma sigma scrutinee in
    if arms = [] then
      type_error "Match expression has no arms";
    (* Type-check each arm body; all must produce the same type *)
    let arm_types = List.map (fun arm ->
      let bindings = check_pattern gamma t_scrutinee arm.arm_pattern in
      let gamma' = List.fold_left (fun g (name, ty) ->
        env_bind_val g name ty) gamma bindings in
      infer_expr gamma' sigma arm.arm_body
    ) arms in
    (* Arms must agree — but for WORDS, "agree" means agree up to width (#92),
       consistent with `.` (compose) widening to max and with `==` no longer
       requiring equal widths.  Arms at Word[0] and Word[2] describe the same
       kind of thing at different strand counts; the join is the wider.
       Everything else must still match exactly. *)
    let join_ty a b =
      match a, b with
      | TWord n, TWord m -> Some (TWord (max n m))
      | x, y when x = y  -> Some x
      | _                -> None
    in
    let result_ty =
      List.fold_left (fun acc ty ->
        match acc with
        | None -> None
        | Some a -> join_ty a ty
      ) (Some (List.hd arm_types)) arm_types
    in
    begin match result_ty with
    | Some t -> t
    | None ->
      (* Report against arm 0, as before, so the message stays familiar. *)
      let t0 = List.hd arm_types in
      let i, bad =
        let rec find i = function
          | [] -> (0, t0)
          | ty :: rest -> if join_ty t0 ty = None then (i, ty) else find (i+1) rest
        in find 0 arm_types
      in
      type_error "Match arm %d has type %s but arm 0 has type %s"
        i (pp_ty bad) (pp_ty t0)
    end

  (* ---- Echo types (structured loss) ----
   * Mirror the HasType rules in proofs/Tangle.lean:
   *   [T-Echo-Close] echoClose e : Echo[Word[n], Word[0]]   when e : Word[n]
   *   [T-Lower]      lower e      : τ                        when e : Echo[ρ, τ]
   *   [T-Residue]    residue e    : ρ                        when e : Echo[ρ, τ]
   *   [T-Pair]/[T-Fst]/[T-Snd]    product intro + projections
   *   [T-Echo-Add]   echoAdd a b  : Echo[Num × Num, Num]
   *   [T-Echo-Eq]    echoEq a b   : Echo[ρ × ρ, Bool]        for ρ ∈ {Num, Str, Word[n]}
   *)
  | EchoClose e1 ->
    begin match infer_expr gamma sigma e1 with
    | TWord n -> TEcho (TWord n, TWord 0)
    | t -> type_error "echoClose requires Word[n], got %s" (pp_ty t)
    end

  | Lower e1 ->
    begin match infer_expr gamma sigma e1 with
    | TEcho (_, t) -> t
    | t -> type_error "lower requires Echo[_, _], got %s" (pp_ty t)
    end

  | Residue e1 ->
    begin match infer_expr gamma sigma e1 with
    | TEcho (r, _) -> r
    | t -> type_error "residue requires Echo[_, _], got %s" (pp_ty t)
    end

  | Pair (e1, e2) ->
    let t1 = infer_expr gamma sigma e1 in
    let t2 = infer_expr gamma sigma e2 in
    TProd (t1, t2)

  | Fst e1 ->
    begin match infer_expr gamma sigma e1 with
    | TProd (a, _) -> a
    | t -> type_error "fst requires a product, got %s" (pp_ty t)
    end

  | Snd e1 ->
    begin match infer_expr gamma sigma e1 with
    | TProd (_, b) -> b
    | t -> type_error "snd requires a product, got %s" (pp_ty t)
    end

  | EchoAdd (e1, e2) ->
    begin match infer_expr gamma sigma e1, infer_expr gamma sigma e2 with
    | TNum, TNum -> TEcho (TProd (TNum, TNum), TNum)
    | t1, t2 -> type_error "echoAdd requires Num, Num, got %s, %s" (pp_ty t1) (pp_ty t2)
    end

  | EchoEq (e1, e2) ->
    begin match infer_expr gamma sigma e1, infer_expr gamma sigma e2 with
    | TNum, TNum -> TEcho (TProd (TNum, TNum), TBool)
    | TStr, TStr -> TEcho (TProd (TStr, TStr), TBool)
    | TWord n, TWord m when n = m -> TEcho (TProd (TWord n, TWord n), TBool)
    | t1, t2 ->
      type_error "echoEq requires matching Num/Str/Word[n] operands, got %s, %s"
        (pp_ty t1) (pp_ty t2)
    end

(** Infer the type of a binary operation given operand types.
 *  Implements rules from sections 3.4, 3.5, 3.6.
 *)
and infer_binop (op : binop) (t1 : ty) (t2 : ty) : ty =
  match op with

  (* [T-Compose-Word]: Word[n] . Word[m] -> Word[max(n,m)]
   * [T-Compose-Tangle]: Tangle[A,B] . Tangle[B,C] -> Tangle[A,C]
   *)
  | Compose ->
    begin match t1, t2 with
    | TWord n, TWord m ->
      TWord (max n m)
    | TTangle (a, b), TTangle (b', c) ->
      if b <> b' then
        type_error "Cannot compose Tangle[%s, %s] with Tangle[%s, %s]: \
                    output boundary %s does not match input boundary %s"
          (pp_boundary a) (pp_boundary b)
          (pp_boundary b') (pp_boundary c)
          (pp_boundary b) (pp_boundary b');
      TTangle (a, c)
    (* Implicit coercion Word -> Tangle [T-Realize] when mixing *)
    | TWord n, TTangle (a, c) ->
      if List.length a < n then
        type_error "Cannot compose Word[%d] with Tangle[%s, %s]: \
                    word is wider than tangle input boundary"
          n (pp_boundary a) (pp_boundary c);
      (* Widen word to match tangle boundary, check output = permuted input *)
      let b = apply_perm_default n a in
      if b <> a then
        (* With default strand types, permutation preserves boundary *)
        TTangle (a, c)
      else
        TTangle (a, c)
    | TTangle (a, b), TWord m ->
      if List.length b < m then
        type_error "Cannot compose Tangle[%s, %s] with Word[%d]: \
                    word is wider than tangle output boundary"
          (pp_boundary a) (pp_boundary b) m;
      let c = apply_perm_default m b in
      TTangle (a, c)
    | _ ->
      type_error "Cannot compose %s with %s" (pp_ty t1) (pp_ty t2)
    end

  (* [T-Tensor-Word]: Word[n] | Word[m] -> Word[n+m]
   * [T-Tensor-Tangle]: Tangle[A1,B1] | Tangle[A2,B2] -> Tangle[A1++A2, B1++B2]
   *)
  | Tensor ->
    begin match t1, t2 with
    | TWord n, TWord m ->
      TWord (n + m)
    | TTangle (a1, b1), TTangle (a2, b2) ->
      TTangle (a1 @ a2, b1 @ b2)
    (* Implicit coercion: Word | Tangle *)
    | TWord n, TTangle (a2, b2) ->
      let a1 = List.init n (fun _ -> StrandDefault) in
      TTangle (a1 @ a2, a1 @ b2)
    | TTangle (a1, b1), TWord m ->
      let a2 = List.init m (fun _ -> StrandDefault) in
      TTangle (a1 @ a2, b1 @ a2)
    | _ ->
      type_error "Cannot tensor %s with %s" (pp_ty t1) (pp_ty t2)
    end

  (* [T-Add-Num], [T-Add-Tangle] *)
  | Add ->
    begin match t1, t2 with
    | TNum, TNum -> TNum
    | TTangle ([], []), TTangle ([], []) ->
      TTangle (empty_boundary, empty_boundary)
    | TTangle _, TTangle _ ->
      type_error "Addition of tangles requires closed tangles (Tangle[I, I]), \
                  got %s + %s" (pp_ty t1) (pp_ty t2)
    | _ ->
      type_error "Cannot add %s and %s" (pp_ty t1) (pp_ty t2)
    end

  (* [T-Arith]: sub, mul, div require Num *)
  | Sub ->
    begin match t1, t2 with
    | TNum, TNum -> TNum
    | _ -> type_error "Subtraction requires Num, got %s - %s" (pp_ty t1) (pp_ty t2)
    end
  | Mul ->
    begin match t1, t2 with
    | TNum, TNum -> TNum
    | _ -> type_error "Multiplication requires Num, got %s * %s" (pp_ty t1) (pp_ty t2)
    end
  | Div ->
    begin match t1, t2 with
    | TNum, TNum -> TNum
    | _ -> type_error "Division requires Num, got %s / %s" (pp_ty t1) (pp_ty t2)
    end

  (* [T-Eq-Word] (same width), [T-Eq-Num], [T-Eq-Str].
   * Word equality requires equal width (n = m), matching the mechanised
   * Lean rule `tEqWord` (proofs/Tangle.lean:248) which binds one width to
   * both operands. `Bool == Bool` is an extra-core convenience (used by
   * examples/braids_as_data.tangle) that lives outside the 26-rule Lean
   * fragment, like `match`/`weave`/`mirror`/etc.; recorded under TG-3 in
   * PROOF-NEEDS.md. *)
  | Eq ->
    begin match t1, t2 with
    (* Widths need not agree (#92).  Braid groups embed Bn -> Bn+1 by adding a
       strand nothing touches, so a Word[n] IS a Word[max n m]; the comparison
       is decided in the larger group.  That is already what
       [Braid_equiv.equiv] computes — it takes two generator lists and has no
       width parameter — and it is what `~` has always accepted.  Mirrors the
       widened [tEqWord] in proofs/Tangle.lean. *)
    | TWord _, TWord _ -> TBool
    | TNum, TNum        -> TBool
    | TStr, TStr        -> TBool
    | TBool, TBool      -> TBool
    | _ -> type_error "Cannot compare %s == %s" (pp_ty t1) (pp_ty t2)
    end

  (* [T-Isotopy]: Tangle[A,B] ~ Tangle[A,B] -> Bool
   * Also works on Words via implicit coercion.
   *)
  | Isotopy ->
    begin match t1, t2 with
    | TTangle (a1, b1), TTangle (a2, b2) ->
      if a1 <> a2 || b1 <> b2 then
        type_error "Isotopy requires matching boundaries: %s ~ %s"
          (pp_ty t1) (pp_ty t2);
      TBool
    | TWord _, TWord _ ->
      (* Words coerce to tangles for isotopy comparison *)
      TBool
    | TWord _, TTangle _ | TTangle _, TWord _ ->
      (* Mixed: word coerces to tangle *)
      TBool
    | _ ->
      type_error "Isotopy requires Tangle or Word types, got %s ~ %s"
        (pp_ty t1) (pp_ty t2)
    end

(** Check that an argument type is compatible with a parameter type. *)
and check_compatible (expected : ty) (actual : ty) (fname : string) : unit =
  match expected, actual with
  | TWord _, TWord _ -> ()   (* Words auto-widen *)
  | TTangle _, TWord _ -> () (* Word coerces to Tangle *)
  | _ when expected = actual -> ()
  | _ ->
    type_error "Function '%s': expected %s but got %s"
      fname (pp_ty expected) (pp_ty actual)

(** Extract a strand_type from a type expression for cap/cup.
 *  Numbers/strings produce default strands; this is a simplified model.
 *)
and strand_type_of_ty (t : ty) : strand_type =
  match t with
  | TStr  -> StrandNamed "Str"
  | TNum  -> StrandNamed "Num"
  | TBool -> StrandNamed "Bool"
  | TWord _ -> StrandDefault
  | TTangle _ -> StrandDefault
  | TProd _ -> StrandDefault
  | TEcho _ -> StrandDefault
  | TEpi _ -> StrandDefault

(** Convert a strand_type to a boundary element for self-crossing. *)
and strand_to_type (st : strand_type) : strand_type = st

(** Apply the permutation induced by a Word[n] to a boundary with
 *  default strand types. With homogeneous boundaries, the result
 *  is always the same as the input [T-Realize-Default].
 *)
and apply_perm_default (_n : int) (b : boundary) : boundary = b

(* ================================================================== *)
(*  Pattern type-checking (section 3.9)                                *)
(* ================================================================== *)

(** Check a pattern against a scrutinee type, returning new bindings.
 *  Implements [P-Identity], [P-Cons], [P-Var], [P-Wildcard].
 *)
and check_pattern (gamma : env) (scrutinee_ty : ty) (pat : pattern)
    : (string * ty) list =
  ignore gamma;
  match pat with

  (* [P-Identity]: matches empty word *)
  | PatIdentity ->
    begin match scrutinee_ty with
    | TWord _ -> []
    | _ -> type_error "Pattern 'identity' can only match Word[n], got %s"
             (pp_ty scrutinee_ty)
    end

  (* [P-Cons]: g . p matches generator g followed by pattern p *)
  | PatCons (gpat, rest) ->
    begin match scrutinee_ty with
    | TWord n ->
      if gpat.gpat_index + 1 > n && n > 0 then
        type_error "Generator s%d in pattern exceeds width %d of scrutinee"
          gpat.gpat_index n;
      check_pattern gamma scrutinee_ty rest
    | _ ->
      type_error "Cons pattern can only match Word[n], got %s"
        (pp_ty scrutinee_ty)
    end

  (* [P-Var]: binds the matched value *)
  | PatVar name ->
    [(name, scrutinee_ty)]

  (* [P-Wildcard]: matches anything, binds nothing *)
  | PatWildcard -> []

(* ================================================================== *)
(*  Statement type-checking (section 3.15)                             *)
(* ================================================================== *)

(** Valid built-in invariant names for [compute] statements. *)
let valid_invariants =
  ["jones"; "alexander"; "homfly"; "kauffman"; "writhe"; "linking"]

(** Does [e] contain a call to [f]?  Used to detect self-recursion in a
    function definition, so that only recursive definitions pay the cost of the
    return-type search below. *)
let rec expr_calls (f : string) (e : expr) : bool =
  let go = expr_calls f in
  match e with
  | Call (g, args) -> g = f || List.exists go args
  | Match (scrut, arms) ->
    go scrut || List.exists (fun a -> go a.arm_body) arms
  | Let (_, e1, e2)      -> go e1 || go e2
  | Pipeline (e1, e2)    -> go e1 || go e2
  | BinOp (_, e1, e2)    -> go e1 || go e2
  | Cap (e1, e2) | Cup (e1, e2) | Pair (e1, e2)
  | EchoAdd (e1, e2) | EchoEq (e1, e2) -> go e1 || go e2
  | UnaryOp (_, e1) | Close e1 | Mirror e1 | Reverse e1 | Simplify e1
  | Twist e1 | EchoClose e1 | Lower e1 | Residue e1 | Fst e1 | Snd e1
  | Evidence e1 -> go e1
  | Warrant (_, c, ev) | EpiVal (_, c, ev) -> go c || go ev
  | Weave wb -> go wb.weave_body
  | BraidLit _ | Identity | BoolLit _ | IntLit _ | FloatLit _
  | StringLit _ | Var _ | Crossing _ -> false

(** Candidate return types for a recursive function, in the order they are
    tried.  Seeds drawn from the body come first (a match's non-recursive arms
    are the usual source), then the scalar types, then the original [TWord 0]
    placeholder so the previous behaviour remains reachable. *)
let recursive_return_candidates (gamma : env) (f : string) (body : expr) : ty list =
  (* Types of the arms that do NOT mention [f] — those can be inferred before
     anything is known about the function's return type.  For
       def length(w) = match w with
         | identity  => 0                  <- typeable now: Num
         | s1 . rest => 1 + length(rest)   <- not yet
         | _         => 0                  <- typeable now: Num
     this yields [TNum], which is the fixpoint. *)
  let seeds_from_body =
    match body with
    | Match (_, arms) ->
      List.filter_map (fun a ->
        if expr_calls f a.arm_body then None
        else (try Some (infer_expr gamma [] a.arm_body) with _ -> None)
      ) arms
    | _ -> []
  in
  let dedup l =
    List.fold_left (fun acc x -> if List.mem x acc then acc else acc @ [x]) [] l
  in
  dedup (seeds_from_body @ [TNum; TBool; TStr; TWord 0])

(** Infer the return type of a function definition and bind it in [gamma].
    [T-Def-Fun].

    This is the single implementation of function-definition typing.  It used
    to exist twice — once here and once inlined in [check_program]'s pass 1b —
    and only the copy in [check_program] was ever reached for whole programs.
    A fix applied to one had no effect on the other, so they are now one
    function called from both. *)
let bind_function_def (gamma : env) (def : definition) : env =
  let param_tys = List.map (fun _p -> TWord 0) def.def_params in
  (* Bind the params, and the function itself so recursive calls resolve.
     [seed] is the return type assumed for those recursive calls. *)
  let with_seed (seed : ty) : env =
    let fsig = { fsig_params = param_tys; fsig_return = seed } in
    let g = env_bind_fun gamma def.def_name fsig in
    List.fold_left2 (fun g pname pty -> env_bind_val g pname pty)
      g def.def_params param_tys
  in
  let body_ty =
    if not (expr_calls def.def_name def.def_body) then
      (* Non-recursive: the seed is never consulted, so one pass suffices.
         Unchanged from the original behaviour. *)
      infer_expr (with_seed (TWord 0)) [] def.def_body
    else begin
      (* Recursive.  The return type occurs in its own derivation, so it must
         be a FIXPOINT: assume a return type, check the body under that
         assumption, and accept only if the body then has exactly the assumed
         type.  Anything weaker is a guess that merely failed to crash.

         Previously the seed was hard-coded to [TWord 0] and marked
         "placeholder", with nothing checking the result against it.  So

             def length(w) = match w with
               | identity  => 0
               | s1 . rest => 1 + length(rest)
               | _         => 0

         failed with "Cannot add Num and Word[0]" — the recursive call was
         typed at the placeholder rather than at Num, which made every
         recursive function returning a scalar unwritable.

         The candidate list is finite and ordered, so this terminates.  If no
         candidate is a fixpoint we fall back to the original single pass,
         which re-raises its original error: a definition that did not
         typecheck before still does not, with the same message. *)
      let rec first_fixpoint = function
        | [] -> infer_expr (with_seed (TWord 0)) [] def.def_body
        | seed :: rest ->
          (match infer_expr (with_seed seed) [] def.def_body with
           | t when t = seed -> t            (* consistent: a real fixpoint *)
           | _               -> first_fixpoint rest
           | exception _     -> first_fixpoint rest)
      in
      first_fixpoint (recursive_return_candidates gamma def.def_name def.def_body)
    end
  in
  env_bind_fun gamma def.def_name { fsig_params = param_tys; fsig_return = body_ty }

(** Type-check a single statement, returning the (possibly extended) environment.
 *  Implements [T-Def-Val], [T-Def-Fun], [T-Assert], [T-Compute], [T-Weave].
 *)
let check_statement (gamma : env) (stmt : statement) : env =
  match stmt with

  (* [T-Def-Val], [T-Def-Fun] *)
  | Definition def ->
    if def.def_params = [] then begin
      (* Value definition: def x = e *)
      let ty = infer_expr gamma [] def.def_body in
      env_bind_val gamma def.def_name ty
    end else begin
      (* Function definition: def f(x1, ..., xk) = body
       * We first infer parameter types from body usage.
       * For now, parameters are typed as Word[0] (will be widened).
       * A more sophisticated implementation would use constraint-based
       * inference; here we use a simple forward analysis.
       *)
      bind_function_def gamma def
    end

  (* [T-Weave] (section 3.10) *)
  | WeaveBlock wb ->
    (* Build the strand context Sigma from input strand declarations *)
    let sigma = List.mapi (fun i ts ->
      let sty = match ts.strand_type with
        | Some name -> StrandNamed name
        | None      -> StrandDefault
      in
      (ts.strand_name, { strand_pos = i + 1; strand_ty = sty })
    ) wb.weave_inputs in
    (* Build input boundary A *)
    let input_boundary = List.map (fun (_, se) -> se.strand_ty) sigma in
    (* Type-check the body in the strand context *)
    let body_ty = infer_expr gamma sigma wb.weave_body in
    (* Validate the body produces a Tangle type *)
    begin match body_ty with
    | TTangle (_, _) -> ()
    | TWord _ -> ()  (* Words are implicitly coerced to Tangles *)
    | _ ->
      type_error "Weave body must produce a Word or Tangle type, got %s"
        (pp_ty body_ty)
    end;
    (* Build output boundary B from yield declarations *)
    let output_boundary = List.map (fun ts ->
      match ts.strand_type with
      | Some name -> StrandNamed name
      | None      -> StrandDefault
    ) wb.weave_outputs in
    (* The weave block itself has type Tangle[A, B] *)
    let _weave_ty = TTangle (input_boundary, output_boundary) in
    gamma

  (* [T-Compute] (D1.12): compute inv(e) where e : Tangle[I, I] *)
  | Computation comp ->
    if not (List.mem comp.comp_invariant valid_invariants) then
      type_error "Unknown invariant '%s'; valid invariants are: %s"
        comp.comp_invariant (String.concat ", " valid_invariants);
    let t = infer_expr gamma [] comp.comp_arg in
    begin match t with
    | TTangle ([], []) -> ()   (* Already closed tangle *)
    | TWord _ -> ()            (* Word coerces via close *)
    | TTangle (a, b) ->
      type_error "compute %s requires a closed tangle (Tangle[I, I]), \
                  got Tangle[%s, %s]"
        comp.comp_invariant (pp_boundary a) (pp_boundary b)
    | _ ->
      type_error "compute %s requires a Tangle or Word, got %s"
        comp.comp_invariant (pp_ty t)
    end;
    gamma

  (* [T-Assert] (D1.15): assert e where e : Bool *)
  | Assertion e ->
    let t = infer_expr gamma [] e in
    begin match t with
    | TBool -> ()
    | _ -> type_error "assert requires Bool, got %s" (pp_ty t)
    end;
    gamma

  (* Error recovery: skip malformed statements *)
  | StmtError ->
    gamma

(* ================================================================== *)
(*  Program type-checking (section 3.16)                               *)
(* ================================================================== *)

(** Collected diagnostics. *)
type diagnostic = {
  diag_message : string;
  diag_level   : [`Error | `Warning];
  diag_line    : int option;   (** 1-based source line, when known *)
}

(** Result of type-checking a program. *)
type check_result = {
  result_env         : env;
  result_diagnostics : diagnostic list;
  result_ok          : bool;
}

(** Type-check a complete program.
 *
 *  Pass 1: Collect all [def] names and their types into Gamma.
 *  Pass 2: Type-check all statements against the complete Gamma.
 *
 *  Forward references are allowed because Pass 1 builds the full Gamma
 *  before Pass 2 validates statement bodies.
 *)
let check_program (prog : program) : check_result =
  let errors = ref [] in
  let add_error_at line msg =
    let diag_line = if line > 0 then Some line else None in
    errors := { diag_message = msg; diag_level = `Error; diag_line } :: !errors
  in
  let add_error msg = add_error_at 0 msg in

  (* Pass 1a: collect all def names with placeholder types (forward refs).
   * This gives every name a preliminary entry so later defs can reference
   * earlier ones and vice versa.
   *)
  let gamma_placeholders = List.fold_left (fun gamma stmt ->
    match stmt with
    | Definition def ->
      if def.def_params = [] then
        (* Value: placeholder as Word[0]; will be refined in pass 1b *)
        env_bind_val gamma def.def_name (TWord 0)
      else begin
        let param_tys = List.map (fun _p -> TWord 0) def.def_params in
        let fsig = { fsig_params = param_tys; fsig_return = TWord 0 } in
        env_bind_fun gamma def.def_name fsig
      end
    | _ -> gamma
  ) [] prog in

  (* Pass 1b: re-infer all def types against the full placeholder env.
   * This resolves forward references because every name is visible.
   *)
  let gamma_pass1 = List.fold_left (fun gamma stmt ->
    match stmt with
    | Definition def ->
      begin try
        if def.def_params = [] then begin
          let ty = infer_expr gamma [] def.def_body in
          env_bind_val gamma def.def_name ty
        end else begin
          bind_function_def gamma def
        end
      with Type_error msg ->
        add_error_at def.def_line
          (Printf.sprintf "In definition '%s': %s" def.def_name msg);
        gamma
      end
    | _ -> gamma
  ) gamma_placeholders prog in

  (* Pass 2: type-check the non-definition statements (assertions, computations,
   * weave blocks).  Definitions are fully checked in pass 1b; re-checking them
   * here would only duplicate their diagnostics. *)
  let _gamma_final = List.fold_left (fun gamma stmt ->
    match stmt with
    | Definition _ -> gamma
    | _ ->
      try check_statement gamma stmt
      with Type_error msg ->
        add_error msg;
        gamma
  ) gamma_pass1 prog in

  let diagnostics = List.rev !errors in
  {
    result_env         = gamma_pass1;
    result_diagnostics = diagnostics;
    result_ok          = diagnostics = [];
  }

(** Convenience: type-check a program and raise on the first error. *)
let check_program_exn (prog : program) : env =
  let result = check_program prog in
  match result.result_diagnostics with
  | [] -> result.result_env
  | d :: _ -> raise (Type_error d.diag_message)
