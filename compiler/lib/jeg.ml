(* SPDX-License-Identifier: MPL-2.0 *)
(* jeg.ml — Judgement Evidence Graph.  See jeg.mli for the rationale. *)

open Ast
open Typecheck

type judgement = {
  j_ctx   : (string * env_entry) list;
  j_sigma : (string * strand_entry) list;
  j_expr  : expr;
  j_ty    : ty;
}

type derivation = {
  d_rule       : string;
  d_conclusion : judgement;
  d_premises   : derivation list;
}

type check_error = {
  ce_rule   : string;
  ce_reason : string;
  ce_at     : judgement;
}

(* ================================================================== *)
(*  Deriving                                                           *)
(* ================================================================== *)

(* Only the bindings a node actually consults are recorded, so the graph stays
   readable: a 40-binding environment would otherwise be repeated at every
   node. *)
(* Function signatures are recorded, not just value types: without the callee's
   signature a T-App node cannot be re-derived at all, and an unre-derivable
   node is a hole a forger can put anything through. *)
let ctx_of (gamma : env) (names : string list) : (string * env_entry) list =
  List.filter_map (fun n ->
    match env_lookup gamma n with
    | Some entry -> Some (n, entry)
    | None -> None) names

let node ?(sigma = []) rule gamma names e t premises =
  { d_rule = rule;
    d_conclusion =
      { j_ctx = ctx_of gamma names; j_sigma = sigma; j_expr = e; j_ty = t };
    d_premises = premises }

(* Record only the strand entries a node consults, mirroring [ctx_of]. *)
let strands_of (sigma : strand_ctx) (names : string list) :
      (string * strand_entry) list =
  List.filter_map (fun n ->
    match strand_lookup sigma n with
    | Some se -> Some (n, se)
    | None -> None) names

(* The strand context a weave block introduces — the same construction
   [infer_expr] performs for [T-Weave]. *)
let sigma_of_weave (wb : weave_block) : strand_ctx =
  List.mapi (fun i ts ->
    let sty = match ts.strand_type with
      | Some name -> StrandNamed name
      | None      -> StrandDefault
    in
    (ts.strand_name, { strand_pos = i + 1; strand_ty = sty })) wb.weave_inputs

(* The derivation is produced by the SAME rules the checker uses — `derive` is
   not a parallel implementation that could drift.  Each case mirrors one
   inference rule from FORMAL-SEMANTICS.md, and the type recorded on the
   conclusion is the one `infer_expr` computes. *)
let rec derive_in (gamma : env) (sigma : strand_ctx) (e : expr) : derivation =
  let derive gamma e = derive_in gamma sigma e in
  let node ?(sigma = sigma) = node ~sigma in
  let ty = infer_expr gamma sigma e in
  let leaf rule = node rule gamma [] e ty [] in
  match e with
  | IntLit _ | FloatLit _ -> leaf "T-Num"
  | StringLit _           -> leaf "T-Str"
  | BoolLit _             -> leaf "T-Bool"
  | Identity              -> leaf "T-Identity"
  | BraidLit _            -> leaf "T-Braid"
  | Var n                 -> node "T-Var" gamma [n] e ty []

  | BinOp (op, a, b) ->
    let rule = match op with
      | Compose -> "T-Compose" | Tensor -> "T-Tensor"
      | Add -> "T-Add" | Sub | Mul | Div -> "T-Arith"
      | Eq -> "T-Eq" | Isotopy -> "T-Isotopy"
    in
    node rule gamma [] e ty [derive gamma a; derive gamma b]

  | Pipeline (a, b) -> node "T-Pipeline" gamma [] e ty [derive gamma a; derive gamma b]
  | UnaryOp (_, a)  -> node "T-Unary"    gamma [] e ty [derive gamma a]
  | Close a         -> node "T-Close"    gamma [] e ty [derive gamma a]
  | Mirror a        -> node "T-Mirror"   gamma [] e ty [derive gamma a]
  | Reverse a       -> node "T-Reverse"  gamma [] e ty [derive gamma a]
  | Simplify a      -> node "T-Simplify" gamma [] e ty [derive gamma a]
  | Twist a         -> node "T-Twist"    gamma [] e ty [derive gamma a]
  | Cap (a, b)      -> node "T-Cap"      gamma [] e ty [derive gamma a; derive gamma b]
  | Cup (a, b)      -> node "T-Cup"      gamma [] e ty [derive gamma a; derive gamma b]

  | EchoClose a     -> node "T-Echo-Close" gamma [] e ty [derive gamma a]
  | Lower a         -> node "T-Lower"      gamma [] e ty [derive gamma a]
  | Residue a       -> node "T-Residue"    gamma [] e ty [derive gamma a]
  | Fst a           -> node "T-Fst"        gamma [] e ty [derive gamma a]
  | Snd a           -> node "T-Snd"        gamma [] e ty [derive gamma a]
  | Pair (a, b)     -> node "T-Pair"    gamma [] e ty [derive gamma a; derive gamma b]
  | EchoAdd (a, b)  -> node "T-Echo-Add" gamma [] e ty [derive gamma a; derive gamma b]
  | EchoEq (a, b)   -> node "T-Echo-Eq"  gamma [] e ty [derive gamma a; derive gamma b]

  (* TG-11.  Note the shape: T-Warrant has BOTH premises, and T-Evidence has
     one whose type is an Epi.  There is no rule here concluding the claim's
     type — non-factivity is visible in the graph itself. *)
  | Warrant (_, c, ev) -> node "T-Warrant"  gamma [] e ty [derive gamma c; derive gamma ev]
  | EpiVal (_, c, ev)  -> node "T-Epi-Val"  gamma [] e ty [derive gamma c; derive gamma ev]
  | Evidence a         -> node "T-Evidence" gamma [] e ty [derive gamma a]

  | Let (x, e1, e2) ->
    let d1 = derive gamma e1 in
    let gamma' = env_bind_val gamma x (infer_expr gamma [] e1) in
    node "T-Let" gamma [x] e ty [d1; derive gamma' e2]

  | Match (scrut, arms) ->
    node "T-Match" gamma [] e ty
      (derive gamma scrut :: List.map (fun a -> derive gamma a.arm_body) arms)

  | Call (f, args)   -> node "T-App" gamma [f] e ty (List.map (derive gamma) args)

  (* An add{} island has its own judgement (|-_hd), so there is no TANGLE-rule
     premise structure to record.  It is the one rule `check` cannot re-derive,
     and [unchecked] reports it rather than passing it off as verified. *)
  | AddBlock _       -> leaf "T-Add-Block"

  (* Crossings and weaves read the STRAND context, not premise types.  Recording
     Sigma on the judgement is what lets `check` re-derive them — previously
     they were bare leaves, i.e. nodes that asserted a type with nothing
     licensing it. *)
  | Crossing (a, _, b) ->
    { d_rule = "T-Crossing";
      d_conclusion =
        { j_ctx = []; j_sigma = strands_of sigma [a; b]; j_expr = e; j_ty = ty };
      d_premises = [] }

  | Weave wb ->
    (* The body is derived in the weave's OWN strand context, which is where
       strand names mean anything. *)
    let sigma' = sigma_of_weave wb in
    node ~sigma "T-Weave" gamma [] e ty [derive_in gamma sigma' wb.weave_body]

and derive (gamma : env) (e : expr) : derivation = derive_in gamma [] e

(* ================================================================== *)
(*  Checking — independent of `derive`                                 *)
(* ================================================================== *)

(* `check` deliberately does NOT call `derive`.  It re-establishes each node
   from its premises, so a graph that was hand-edited, truncated, or produced
   by some other tool is rejected.  Without that independence the graph would
   be a log, not evidence. *)

let errs = ref []
let fail rule reason at = errs := { ce_rule = rule; ce_reason = reason; ce_at = at } :: !errs

(* Nodes accepted WITHOUT re-derivation.  A rule that cannot be re-derived is a
   hole — a forger can put any conclusion through it — so the holes are counted
   and reportable rather than hidden behind a silent `-> ()`.  `check` returning
   Ok while [unchecked] is non-empty is a meaningful, and different, result. *)
let unchecked_nodes = ref []
let defer rule at = unchecked_nodes := (rule, at) :: !unchecked_nodes

(* The type a node CLAIMS for each premise, in order. *)
let premise_tys (d : derivation) : ty list =
  List.map (fun p -> p.d_conclusion.j_ty) d.d_premises

(* Every T-Var node inside a derivation that names [x], with the type it
   assumed.  Used by T-Let to verify the body was checked under the binding the
   let actually introduces. *)
let rec var_uses_in (x : string) (d : derivation) : (string * ty) list =
  let here =
    if d.d_rule = "T-Var" && d.d_conclusion.j_expr = Var x
    then [ (x, d.d_conclusion.j_ty) ] else []
  in
  here @ List.concat_map (var_uses_in x) d.d_premises

let rec check_node (d : derivation) : unit =
  List.iter check_node d.d_premises;
  let c = d.d_conclusion in
  let pts = premise_tys d in
  let arity n =
    if List.length d.d_premises <> n then begin
      fail d.d_rule
        (Printf.sprintf "expected %d premise(s), found %d" n (List.length d.d_premises)) c;
      false
    end else true
  in
  let expect want =
    if c.j_ty <> want then
      fail d.d_rule
        (Printf.sprintf "concludes %s but the rule gives %s" (pp_ty c.j_ty) (pp_ty want)) c
  in
  (* Run a rule function and compare.  A Type_error means the premises do not
     license the conclusion at all, which is a failure, not an exception to
     propagate: `check` reports, it does not throw. *)
  let guard rule at f =
    match (try Ok (f ()) with Type_error m -> Error m) with
    | Ok want ->
      if at.j_ty <> want then
        fail rule
          (Printf.sprintf "concludes %s but the rule gives %s"
             (pp_ty at.j_ty) (pp_ty want)) at
    | Error m -> fail rule ("premises do not license it: " ^ m) at
  in
  let unary_rule d c pts f =
    if arity 1 then
      (match pts with [t] -> guard d.d_rule c (fun () -> f t) | _ -> ())
  in
  let binary_rule d c pts f =
    if arity 2 then
      (match pts with [a; b] -> guard d.d_rule c (fun () -> f a b) | _ -> ())
  in
  match d.d_rule with
  (* Axioms: the conclusion must match the literal, and there are no premises. *)
  | "T-Num"   -> if arity 0 then expect TNum
  | "T-Str"   -> if arity 0 then expect TStr
  | "T-Bool"  -> if arity 0 then expect TBool
  | "T-Identity" -> if arity 0 then expect (TWord 0)
  | "T-Braid" ->
    if arity 0 then
      (match c.j_expr with
       | BraidLit gs -> expect (TWord (width_of_generators gs))
       | _ -> fail d.d_rule "conclusion is not a braid literal" c)
  | "T-Var" ->
    if arity 0 then
      (match c.j_expr with
       | Var n ->
         (match List.assoc_opt n c.j_ctx with
          | Some (EVal t) -> expect t
          | Some (EFun _) ->
            fail d.d_rule
              (Printf.sprintf "'%s' is a function; it has no value type" n) c
          | None -> fail d.d_rule (Printf.sprintf "'%s' not in the recorded context" n) c)
       | _ -> fail d.d_rule "conclusion is not a variable" c)

  (* Structural rules: re-run the operator's typing on the PREMISE types. *)
  | "T-Compose" | "T-Tensor" | "T-Add" | "T-Arith" | "T-Eq" | "T-Isotopy" ->
    if arity 2 then begin
      match c.j_expr, pts with
      | BinOp (op, _, _), [t1; t2] ->
        (try expect (infer_binop op t1 t2)
         with Type_error m -> fail d.d_rule ("premises do not license it: " ^ m) c)
      | _ -> fail d.d_rule "conclusion is not a binary operation" c
    end

  | "T-Echo-Close" ->
    if arity 1 then
      (match pts with
       | [TWord n] -> expect (TEcho (TWord n, TWord 0))
       | [t] -> fail d.d_rule ("premise must be a Word, got " ^ pp_ty t) c
       | _ -> ())
  | "T-Lower" ->
    if arity 1 then
      (match pts with
       | [TEcho (_, t)] -> expect t
       | [t] -> fail d.d_rule ("premise must be an Echo, got " ^ pp_ty t) c
       | _ -> ())
  | "T-Residue" ->
    if arity 1 then
      (match pts with
       | [TEcho (r, _)] -> expect r
       | [t] -> fail d.d_rule ("premise must be an Echo, got " ^ pp_ty t) c
       | _ -> ())
  | "T-Fst" ->
    if arity 1 then
      (match pts with
       | [TProd (a, _)] -> expect a
       | [t] -> fail d.d_rule ("premise must be a product, got " ^ pp_ty t) c
       | _ -> ())
  | "T-Snd" ->
    if arity 1 then
      (match pts with
       | [TProd (_, b)] -> expect b
       | [t] -> fail d.d_rule ("premise must be a product, got " ^ pp_ty t) c
       | _ -> ())
  | "T-Pair" ->
    if arity 2 then (match pts with [a; b] -> expect (TProd (a, b)) | _ -> ())

  (* TG-11.  T-Evidence is the load-bearing one: it must conclude the EVIDENCE
     component.  A graph claiming it concludes the CLAIM component is exactly
     the forgery this catches — it would assert factivity, which no rule
     licenses (epi_only_yields_evidence). *)
  | "T-Warrant" | "T-Epi-Val" ->
    if arity 2 then
      (match c.j_expr, pts with
       | (Warrant (k, _, _) | EpiVal (k, _, _)), [tc; tev] -> expect (TEpi (k, tev, tc))
       | _ -> fail d.d_rule "conclusion is not a warrant" c)
  | "T-Evidence" ->
    if arity 1 then
      (match pts with
       | [TEpi (_, rho, tau)] ->
         if c.j_ty = rho then ()
         else if c.j_ty = tau && rho <> tau then
           fail d.d_rule
             "concludes the CLAIM type — no rule extracts a claim from a warrant \
              (non-factivity, see epi_only_yields_evidence)" c
         else expect rho
       | [t] -> fail d.d_rule ("premise must be an Epi, got " ^ pp_ty t) c
       | _ -> ())

  (* ---- Unary and pipeline: re-run the rule on the premise type. ---- *)

  | "T-Pipeline" ->
    if arity 2 then
      (match pts with
       | [t1; t2] -> guard d.d_rule c (fun () -> infer_binop Compose t1 t2)
       | _ -> ())

  | "T-Unary" ->
    if arity 1 then
      (match c.j_expr, pts with
       | UnaryOp (op, _), [t] -> guard d.d_rule c (fun () -> infer_unop op t)
       | _ -> fail d.d_rule "conclusion is not a unary operation" c)

  | "T-Close"    -> unary_rule d c pts infer_close
  | "T-Mirror"   -> unary_rule d c pts infer_mirror
  | "T-Reverse"  -> unary_rule d c pts infer_reverse
  | "T-Simplify" -> unary_rule d c pts infer_simplify
  | "T-Twist"    -> unary_rule d c pts infer_twist

  | "T-Cap"      -> binary_rule d c pts infer_cap
  | "T-Cup"      -> binary_rule d c pts infer_cup
  | "T-Echo-Add" -> binary_rule d c pts infer_echo_add
  | "T-Echo-Eq"  -> binary_rule d c pts infer_echo_eq

  (* ---- T-Let ----
     Two obligations.  The conclusion is the BODY's type (the bound expression's
     type does not escape), and — the substantive half — the body must have been
     checked under the binding the let actually introduces.  Checking only the
     first would accept a derivation whose body silently assumed `x` had some
     more convenient type. *)
  | "T-Let" ->
    if arity 2 then
      (match c.j_expr, d.d_premises, pts with
       | Let (x, _, _), [_; body], [t1; t2] ->
         expect t2;
         List.iter (fun (nm, t) ->
           if nm = x && t <> t1 then
             fail d.d_rule
               (Printf.sprintf
                  "body assumes '%s' : %s, but the let binds it at %s"
                  x (pp_ty t) (pp_ty t1)) c)
           (var_uses_in x body)
       | _ -> fail d.d_rule "conclusion is not a let" c)

  (* ---- T-Match ----
     Premises are the scrutinee followed by one per arm.  The conclusion is the
     join of the arm types (words agree up to width, #92). *)
  | "T-Match" ->
    (match c.j_expr, pts with
     | Match (_, arms), _ :: arm_tys when List.length arms = List.length arm_tys
                                       && arm_tys <> [] ->
       let joined =
         List.fold_left (fun acc t ->
           match acc with None -> None | Some a -> join_arm_ty a t)
           (Some (List.hd arm_tys)) arm_tys
       in
       (match joined with
        | Some t -> expect t
        | None -> fail d.d_rule "arms have no common type" c)
     | Match (arms_e, _), _ ->
       ignore arms_e;
       fail d.d_rule
         "premises must be the scrutinee followed by exactly one per arm" c
     | _ -> fail d.d_rule "conclusion is not a match" c)

  (* ---- T-App ----
     Re-derivable now that the callee's SIGNATURE is recorded on the judgement.
     Both halves matter: the argument types must match the parameters, and the
     conclusion must be the declared return type. *)
  | "T-App" ->
    (match c.j_expr with
     | Call (f, _) ->
       (match List.assoc_opt f c.j_ctx with
        | Some (EFun fs) ->
          let np = List.length fs.fsig_params in
          if List.length pts <> np then
            fail d.d_rule
              (Printf.sprintf "'%s' takes %d argument(s), the graph supplies %d"
                 f np (List.length pts)) c
          else
            List.iteri (fun i (want, got) ->
              if want <> got then
                fail d.d_rule
                  (Printf.sprintf "argument %d of '%s' is %s but the signature \
                                   declares %s" (i + 1) f (pp_ty got) (pp_ty want)) c)
              (List.combine fs.fsig_params pts);
          expect fs.fsig_return
        | Some (EVal _) ->
          fail d.d_rule (Printf.sprintf "'%s' is a value, not a function" f) c
        | None ->
          fail d.d_rule
            (Printf.sprintf "'%s' is not in the recorded context — the callee's \
                             signature is required to re-derive the call" f) c)
     | _ -> fail d.d_rule "conclusion is not a call" c)

  (* ---- T-Crossing / T-Weave ----
     These read the STRAND context rather than premise types, so they are
     re-derived against the Sigma recorded on the judgement.  That is still
     independent of `derive`: it recomputes the rule from the graph's own data.
     For T-Weave it also re-checks strand LINEARITY, so a graph asserting a
     weave that duplicates or drops a strand is rejected here too. *)
  | "T-Crossing" ->
    if arity 0 then
      (match c.j_expr with
       | Crossing _ -> guard d.d_rule c (fun () -> infer_expr [] c.j_sigma c.j_expr)
       | _ -> fail d.d_rule "conclusion is not a crossing" c)

  | "T-Weave" ->
    (match c.j_expr with
     | Weave wb ->
       guard d.d_rule c (fun () ->
         (* linearity + boundary, exactly as the typechecker computes them *)
         check_strand_linearity (sigma_of_weave wb) wb;
         let inb = List.map (fun (_, se) -> se.strand_ty) (sigma_of_weave wb) in
         let outb = List.map (fun ts ->
           match ts.strand_type with
           | Some n -> StrandNamed n
           | None   -> StrandDefault) wb.weave_outputs in
         TTangle (inb, outb))
     | _ -> fail d.d_rule "conclusion is not a weave" c)

  (* T-Add-Block: the island has its own judgement (|-_hd), so re-deriving it
     here would mean re-implementing that checker.  Recorded as UNCHECKED — the
     one remaining hole, and reported as such rather than silently accepted. *)
  | "T-Add-Block" -> defer d.d_rule c

  | r -> fail r "unknown rule name" c

let check (d : derivation) : (unit, check_error list) result =
  errs := [];
  unchecked_nodes := [];
  check_node d;
  match List.rev !errs with [] -> Ok () | es -> Error es

(** Which nodes `check` accepted without re-deriving.  Empty means every node
    in the graph was licensed by a rule the checker recomputed. *)
let unchecked (d : derivation) : (string * judgement) list =
  errs := [];
  unchecked_nodes := [];
  check_node d;
  List.rev !unchecked_nodes

(* ================================================================== *)
(*  Presentation                                                       *)
(* ================================================================== *)

let rec size (d : derivation) : int =
  1 + List.fold_left (fun a p -> a + size p) 0 d.d_premises

let rec depth (d : derivation) : int =
  1 + List.fold_left (fun a p -> max a (depth p)) 0 d.d_premises

let judgement_to_string (j : judgement) : string =
  let ctx =
    if j.j_ctx = [] then ""
    else (String.concat ", "
            (List.map (fun (n, entry) ->
               match entry with
               | EVal t -> n ^ ":" ^ pp_ty t
               | EFun fs ->
                 Printf.sprintf "%s:(%s)->%s" n
                   (String.concat ", " (List.map pp_ty fs.fsig_params))
                   (pp_ty fs.fsig_return)) j.j_ctx)) ^ " "
  in
  Printf.sprintf "%s|- %s : %s" ctx (Pretty.expr_to_string j.j_expr) (pp_ty j.j_ty)

let to_string (d : derivation) : string =
  let buf = Buffer.create 256 in
  let rec go indent d =
    Buffer.add_string buf (String.make indent ' ');
    Buffer.add_string buf ("[" ^ d.d_rule ^ "] ");
    Buffer.add_string buf (judgement_to_string d.d_conclusion);
    Buffer.add_char buf '\n';
    List.iter (go (indent + 2)) d.d_premises
  in
  go 0 d;
  Buffer.contents buf

let to_dot (d : derivation) : string =
  let buf = Buffer.create 256 in
  Buffer.add_string buf "digraph JEG {\n  rankdir=BT;\n  node [shape=box, fontname=\"monospace\"];\n";
  let n = ref 0 in
  let rec go d =
    let id = !n in incr n;
    Buffer.add_string buf
      (Printf.sprintf "  n%d [label=\"%s\\n%s\"];\n" id d.d_rule
         (String.concat "\\'" (String.split_on_char '"' (judgement_to_string d.d_conclusion))));
    List.iter (fun p -> let pid = go p in
                Buffer.add_string buf (Printf.sprintf "  n%d -> n%d;\n" pid id)) d.d_premises;
    id
  in
  ignore (go d);
  Buffer.add_string buf "}\n";
  Buffer.contents buf
