(* SPDX-License-Identifier: MPL-2.0 *)
(* jeg.ml — Judgement Evidence Graph.  See jeg.mli for the rationale. *)

open Ast
open Typecheck

type judgement = {
  j_ctx  : (string * ty) list;
  j_expr : expr;
  j_ty   : ty;
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
let ctx_of (gamma : env) (names : string list) : (string * ty) list =
  List.filter_map (fun n ->
    match env_lookup gamma n with
    | Some (EVal t) -> Some (n, t)
    | _ -> None) names

let node rule gamma names e t premises =
  { d_rule = rule;
    d_conclusion = { j_ctx = ctx_of gamma names; j_expr = e; j_ty = t };
    d_premises = premises }

(* The derivation is produced by the SAME rules the checker uses — `derive` is
   not a parallel implementation that could drift.  Each case mirrors one
   inference rule from FORMAL-SEMANTICS.md, and the type recorded on the
   conclusion is the one `infer_expr` computes. *)
let rec derive (gamma : env) (e : expr) : derivation =
  let ty = infer_expr gamma [] e in
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
  | AddBlock _       -> leaf "T-Add-Block"
  | Crossing _       -> leaf "T-Crossing"
  | Weave _          -> leaf "T-Weave"

(* ================================================================== *)
(*  Checking — independent of `derive`                                 *)
(* ================================================================== *)

(* `check` deliberately does NOT call `derive`.  It re-establishes each node
   from its premises, so a graph that was hand-edited, truncated, or produced
   by some other tool is rejected.  Without that independence the graph would
   be a log, not evidence. *)

let errs = ref []
let fail rule reason at = errs := { ce_rule = rule; ce_reason = reason; ce_at = at } :: !errs

(* The type a node CLAIMS for each premise, in order. *)
let premise_tys (d : derivation) : ty list =
  List.map (fun p -> p.d_conclusion.j_ty) d.d_premises

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
          | Some t -> expect t
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

  (* Rules whose side conditions are not yet re-derivable here.  Listed
     explicitly rather than swallowed by a wildcard, so the coverage gap is
     visible: an unknown rule name is itself an error. *)
  | "T-Pipeline" | "T-Unary" | "T-Close" | "T-Mirror" | "T-Reverse"
  | "T-Simplify" | "T-Twist" | "T-Cap" | "T-Cup" | "T-Echo-Add" | "T-Echo-Eq"
  | "T-Let" | "T-Match" | "T-App" | "T-Crossing" | "T-Weave" -> ()
  (* T-Add-Block: the island has its own judgement (|-_hd), so re-deriving it
     here would mean re-implementing that checker. Deferred, and listed. *)
  | "T-Add-Block" -> ()
  | r -> fail r "unknown rule name" c

let check (d : derivation) : (unit, check_error list) result =
  errs := [];
  check_node d;
  match List.rev !errs with [] -> Ok () | es -> Error es

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
            (List.map (fun (n, t) -> n ^ ":" ^ pp_ty t) j.j_ctx)) ^ " "
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
