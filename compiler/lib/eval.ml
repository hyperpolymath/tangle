(* SPDX-License-Identifier: MPL-2.0 *)
(* eval.ml — Tree-walking interpreter for the core TANGLE language.
 *
 * Evaluates TANGLE programs by walking the AST produced by the parser.
 * Braid words are represented as lists of generators; topological
 * operations (compose, tensor, close, mirror, reverse, simplify) act
 * directly on these lists.  Invariant computation produces placeholder
 * polynomial strings — a full polynomial engine is outside the scope
 * of this interpreter.
 *
 * The interpreter assumes that the program has passed type-checking.
 * Runtime errors (division by zero, failed assertions, unbound variables)
 * are raised as [Eval_error] exceptions.
 *)

open Ast

(* ================================================================== *)
(*  Values                                                             *)
(* ================================================================== *)

(** A braid generator at runtime: index and exponent. *)
type gen = {
  g_index    : int;
  g_exponent : int;
}

(** A tangle value produced by [close]. *)
type tangle_value = {
  tv_word  : gen list;   (** The underlying braid word *)
  tv_closed : bool;      (** Whether this tangle is closed *)
}

(** Runtime values. *)
type value =
  | VInt       of int
  | VFloat     of float
  | VBool      of bool
  | VString    of string
  | VBraid     of gen list            (** Braid word as list of generators *)
  | VTangle    of tangle_value        (** Closed tangle *)
  | VFun       of string list * expr * env  (** Closure: params, body, captured env *)
  | VUnit                             (** Unit / void result *)
  | VInvariant of string * string     (** Invariant name, result string *)

(** Runtime environment: association list of name-value bindings. *)
and env = (string * value) list

(* ================================================================== *)
(*  Error reporting                                                    *)
(* ================================================================== *)

(** Runtime evaluation error. *)
exception Eval_error of string

(** Raise a formatted evaluation error. *)
let eval_error fmt =
  Printf.ksprintf (fun msg -> raise (Eval_error msg)) fmt

(* ================================================================== *)
(*  Value display                                                      *)
(* ================================================================== *)

(** Pretty-print a generator. *)
let pp_gen (g : gen) : string =
  if g.g_exponent = 1 then
    Printf.sprintf "s%d" g.g_index
  else if g.g_exponent = -1 then
    Printf.sprintf "s%d^-1" g.g_index
  else
    Printf.sprintf "s%d^%d" g.g_index g.g_exponent

(** Pretty-print a list of generators as a braid literal. *)
let pp_braid (gens : gen list) : string =
  match gens with
  | [] -> "braid[]"
  | _  -> "braid[" ^ String.concat ", " (List.map pp_gen gens) ^ "]"

(** Pretty-print a value. *)
let pp_value (v : value) : string =
  match v with
  | VInt n        -> string_of_int n
  | VFloat f      -> Printf.sprintf "%g" f
  | VBool true    -> "true"
  | VBool false   -> "false"
  | VString s     -> Printf.sprintf "%S" s
  | VBraid gens   -> pp_braid gens
  | VTangle tv    -> Printf.sprintf "close(%s)" (pp_braid tv.tv_word)
  | VFun _        -> "<function>"
  | VUnit         -> "()"
  | VInvariant (name, result) -> Printf.sprintf "%s = %s" name result

(* ================================================================== *)
(*  Environment operations                                             *)
(* ================================================================== *)

(** Look up a name in the environment. *)
let env_lookup (env : env) (name : string) : value option =
  List.assoc_opt name env

(** Extend the environment with a binding. *)
let env_bind (env : env) (name : string) (v : value) : env =
  (name, v) :: env

(* ================================================================== *)
(*  Generator / braid word helpers                                     *)
(* ================================================================== *)

(** Convert an AST generator to a runtime generator. *)
let gen_of_ast (g : generator) : gen =
  { g_index = g.gen_index; g_exponent = g.gen_exponent }

(** Convert a list of AST generators to runtime generators. *)
let gens_of_ast (gs : generator list) : gen list =
  List.map gen_of_ast gs

(** Compute the width (number of strands) of a braid word.
 *  width = max(index + 1) over all generators, or 0 if empty.
 *)
let width_of_gens (gens : gen list) : int =
  List.fold_left (fun acc g -> max acc (g.g_index + 1)) 0 gens

(** Mirror a braid word: negate all exponents, preserving order.
 *  This produces the mirror image of the braid.
 *)
let mirror_gens (gens : gen list) : gen list =
  List.map (fun g -> { g with g_exponent = -g.g_exponent }) gens

(** Reverse a braid word: reverse the list and negate exponents.
 *  This produces the inverse braid word.
 *)
let reverse_gens (gens : gen list) : gen list =
  List.rev_map (fun g -> { g with g_exponent = -g.g_exponent }) gens

(** Tensor two braid words: offset the indices of the right word
 *  by the width of the left word, then concatenate.
 *)
let tensor_gens (left : gen list) (right : gen list) : gen list =
  let w = width_of_gens left in
  let shifted = List.map (fun g -> { g with g_index = g.g_index + w }) right in
  left @ shifted

(** Simplify a braid word by applying Reidemeister move II cancellation:
 *  Adjacent generators with the same index but opposite exponents cancel.
 *  Repeats until no more cancellations are possible.
 *)
let simplify_gens (gens : gen list) : gen list =
  let rec pass (gs : gen list) (changed : bool) : gen list * bool =
    match gs with
    | [] -> (List.rev [], changed)
    | [g] -> ([g], changed)
    | g1 :: g2 :: rest ->
      if g1.g_index = g2.g_index && g1.g_exponent + g2.g_exponent = 0 then
        (* Cancel adjacent inverses (Reidemeister II) *)
        pass rest true
      else
        let (result, c) = pass (g2 :: rest) changed in
        (g1 :: result, c)
  in
  let rec fixpoint gs =
    let (gs', changed) = pass gs false in
    if changed then fixpoint gs'
    else gs'
  in
  fixpoint gens

(* ================================================================== *)
(*  Invariant computation (placeholder polynomial strings)             *)
(* ================================================================== *)

(** Compute the writhe of a braid word: sum of all exponents. *)
let writhe (gens : gen list) : int =
  List.fold_left (fun acc g -> acc + g.g_exponent) 0 gens

(** Compute a placeholder Jones polynomial string.
 *  For an actual implementation, this would use the Kauffman bracket
 *  or Temperley-Lieb algebra.  Here we return a symbolic string.
 *)
let jones_polynomial (gens : gen list) : string =
  let w = writhe gens in
  let n = List.length gens in
  if n = 0 then "1"
  else Printf.sprintf "J(w=%d, n=%d)" w n

(** Compute a placeholder Alexander polynomial string. *)
let alexander_polynomial (gens : gen list) : string =
  let n = List.length gens in
  if n = 0 then "1"
  else Printf.sprintf "A(n=%d)" n

(** Compute a placeholder HOMFLY-PT polynomial string. *)
let homfly_polynomial (gens : gen list) : string =
  let w = writhe gens in
  let n = List.length gens in
  if n = 0 then "1"
  else Printf.sprintf "P(w=%d, n=%d)" w n

(** Compute a placeholder Kauffman polynomial string. *)
let kauffman_polynomial (gens : gen list) : string =
  let n = List.length gens in
  if n = 0 then "1"
  else Printf.sprintf "F(n=%d)" n

(** Compute the linking number for a two-component link.
 *  This is a simplification: the real computation requires component
 *  identification.  Here we return half the writhe as an approximation.
 *)
let linking_number (gens : gen list) : string =
  let w = writhe gens in
  Printf.sprintf "%d" (w / 2)

(** Dispatch invariant computation by name. *)
let compute_invariant (name : string) (gens : gen list) : string =
  match name with
  | "jones"     -> jones_polynomial gens
  | "alexander" -> alexander_polynomial gens
  | "homfly"    -> homfly_polynomial gens
  | "kauffman"  -> kauffman_polynomial gens
  | "writhe"    -> string_of_int (writhe gens)
  | "linking"   -> linking_number gens
  | _           -> eval_error "Unknown invariant '%s'" name

(* ================================================================== *)
(*  Pattern matching                                                   *)
(* ================================================================== *)

(** Try to match a value against a pattern, returning bindings on success. *)
let rec match_pattern (pat : pattern) (v : value) : (string * value) list option =
  match pat, v with

  (* PatIdentity matches an empty braid word *)
  | PatIdentity, VBraid [] -> Some []
  | PatIdentity, _ -> None

  (* PatCons matches a generator consed onto a braid word *)
  | PatCons (gpat, rest_pat), VBraid (g :: gs) ->
    if g.g_index = gpat.gpat_index && g.g_exponent = gpat.gpat_exponent then
      match_pattern rest_pat (VBraid gs)
    else
      None
  | PatCons _, _ -> None

  (* PatVar binds the entire value to a name *)
  | PatVar name, _ -> Some [(name, v)]

  (* PatWildcard matches anything without binding *)
  | PatWildcard, _ -> Some []

(* ================================================================== *)
(*  Expression evaluation                                              *)
(* ================================================================== *)

(** Extract the braid word from a value, coercing tangles. *)
let gens_of_value (v : value) : gen list =
  match v with
  | VBraid gens    -> gens
  | VTangle tv     -> tv.tv_word
  | _ -> eval_error "Expected a braid or tangle value, got %s" (pp_value v)

(** Evaluate an expression in the given environment. *)
let rec eval_expr (env : env) (e : expr) : value =
  match e with

  (* ---- Literals ---- *)

  | IntLit n    -> VInt n
  | FloatLit f  -> VFloat f
  | BoolLit b   -> VBool b
  | StringLit s -> VString s
  | Identity    -> VBraid []

  | BraidLit gens ->
    VBraid (gens_of_ast gens)

  (* ---- Variables ---- *)

  | Var name ->
    begin match env_lookup env name with
    | Some v -> v
    | None   -> eval_error "Unbound variable '%s'" name
    end

  (* ---- Let binding ---- *)

  | Let (x, e1, e2) ->
    let v1 = eval_expr env e1 in
    let env' = env_bind env x v1 in
    eval_expr env' e2

  (* ---- Function call ---- *)

  | Call (fname, args) ->
    begin match env_lookup env fname with
    | Some (VFun (params, body, closure_env)) ->
      let arg_vals = List.map (eval_expr env) args in
      if List.length params <> List.length arg_vals then
        eval_error "Function '%s' expects %d argument(s) but got %d"
          fname (List.length params) (List.length arg_vals);
      (* Bind parameters and the function itself (for recursion) *)
      let call_env = List.fold_left2 (fun e p v ->
        env_bind e p v
      ) closure_env params arg_vals in
      let call_env = env_bind call_env fname (VFun (params, body, closure_env)) in
      eval_expr call_env body
    | Some _ ->
      eval_error "'%s' is not a function" fname
    | None ->
      eval_error "Unbound function '%s'" fname
    end

  (* ---- Binary operators ---- *)

  | BinOp (op, e1, e2) ->
    let v1 = eval_expr env e1 in
    let v2 = eval_expr env e2 in
    eval_binop op v1 v2

  (* ---- Pipeline: evaluate left, pipe result as compose ---- *)

  | Pipeline (e1, e2) ->
    let v1 = eval_expr env e1 in
    let v2 = eval_expr env e2 in
    eval_binop Compose v1 v2

  (* ---- Unary operators ---- *)

  | UnaryOp (Neg, e1) ->
    begin match eval_expr env e1 with
    | VInt n   -> VInt (-n)
    | VFloat f -> VFloat (-.f)
    | v -> eval_error "Cannot negate %s" (pp_value v)
    end

  | UnaryOp (Not, e1) ->
    begin match eval_expr env e1 with
    | VBool b -> VBool (not b)
    | v -> eval_error "Cannot negate (not) %s" (pp_value v)
    end

  (* ---- Tier 1 primitives ---- *)

  | Close e1 ->
    let gens = gens_of_value (eval_expr env e1) in
    VTangle { tv_word = gens; tv_closed = true }

  | Mirror e1 ->
    let v = eval_expr env e1 in
    begin match v with
    | VBraid gens -> VBraid (mirror_gens gens)
    | VTangle tv  -> VTangle { tv with tv_word = mirror_gens tv.tv_word }
    | _ -> eval_error "Cannot mirror %s" (pp_value v)
    end

  | Reverse e1 ->
    let v = eval_expr env e1 in
    begin match v with
    | VBraid gens -> VBraid (reverse_gens gens)
    | _ -> eval_error "Cannot reverse %s" (pp_value v)
    end

  | Simplify e1 ->
    let v = eval_expr env e1 in
    begin match v with
    | VBraid gens -> VBraid (simplify_gens gens)
    | VTangle tv  -> VTangle { tv with tv_word = simplify_gens tv.tv_word }
    | _ -> eval_error "Cannot simplify %s" (pp_value v)
    end

  | Cap (_e1, _e2) ->
    (* Cap creates a tangle that absorbs two strands — a single-crossing
       cup/cap pair.  Represented as an empty closed tangle. *)
    VTangle { tv_word = []; tv_closed = true }

  | Cup (_e1, _e2) ->
    (* Cup creates a tangle that emits two strands — a single-crossing
       cup/cap pair.  Represented as an empty closed tangle. *)
    VTangle { tv_word = []; tv_closed = true }

  | Twist e1 ->
    let v = eval_expr env e1 in
    begin match v with
    | VBraid gens ->
      (* Twist adds a full twist: compose with all pairwise generators *)
      let w = width_of_gens gens in
      if w <= 1 then VBraid gens
      else begin
        let twist_gens = List.init (w - 1) (fun i ->
          { g_index = i + 1; g_exponent = 1 }
        ) in
        VBraid (gens @ twist_gens)
      end
    | VTangle tv ->
      let w = width_of_gens tv.tv_word in
      if w <= 1 then v
      else begin
        let twist_gens = List.init (w - 1) (fun i ->
          { g_index = i + 1; g_exponent = 1 }
        ) in
        VTangle { tv with tv_word = tv.tv_word @ twist_gens }
      end
    | _ -> eval_error "Cannot twist %s" (pp_value v)
    end

  (* ---- Crossings (weave context) ---- *)

  | Crossing (a, _op, b) ->
    (* In the interpreter, crossings are evaluated as a single generator
       between the two strand positions.  Without a full strand context
       at runtime, we treat them as identity (weave blocks are structural). *)
    ignore (a, b);
    VBraid []

  (* ---- Pattern matching ---- *)

  | Match (scrutinee, arms) ->
    let v = eval_expr env scrutinee in
    let rec try_arms = function
      | [] -> eval_error "No pattern matched value %s" (pp_value v)
      | arm :: rest ->
        begin match match_pattern arm.arm_pattern v with
        | Some bindings ->
          let env' = List.fold_left (fun e (name, v) ->
            env_bind e name v
          ) env bindings in
          eval_expr env' arm.arm_body
        | None ->
          try_arms rest
        end
    in
    try_arms arms

  (* ---- Echo types (structured loss) ----
   * These are typed by typecheck.ml (mirroring proofs/Tangle.lean).  Runtime
   * evaluation needs echo/product value forms and is a deliberate follow-on;
   * the typechecker is the scoped deliverable. *)
  | EchoClose _ | Lower _ | Residue _ | Pair _ | Fst _ | Snd _ | EchoAdd _ | EchoEq _ ->
    eval_error "echo-type evaluation is not yet implemented (typecheck-only); \
                see proofs/Tangle.lean for the intended small-step semantics"

(** Evaluate a binary operation on two values. *)
and eval_binop (op : binop) (v1 : value) (v2 : value) : value =
  match op with

  (* Compose: concatenate braid words *)
  | Compose ->
    begin match v1, v2 with
    | VBraid g1, VBraid g2     -> VBraid (g1 @ g2)
    | VTangle t1, VTangle t2   -> VTangle { tv_word = t1.tv_word @ t2.tv_word;
                                             tv_closed = t1.tv_closed && t2.tv_closed }
    | VBraid g1, VTangle t2    -> VTangle { tv_word = g1 @ t2.tv_word;
                                             tv_closed = t2.tv_closed }
    | VTangle t1, VBraid g2    -> VTangle { tv_word = t1.tv_word @ g2;
                                             tv_closed = t1.tv_closed }
    | _ -> eval_error "Cannot compose %s with %s" (pp_value v1) (pp_value v2)
    end

  (* Tensor: interleave with width offset *)
  | Tensor ->
    begin match v1, v2 with
    | VBraid g1, VBraid g2     -> VBraid (tensor_gens g1 g2)
    | VTangle t1, VTangle t2   -> VTangle { tv_word = tensor_gens t1.tv_word t2.tv_word;
                                             tv_closed = t1.tv_closed && t2.tv_closed }
    | VBraid g1, VTangle t2    -> VTangle { tv_word = tensor_gens g1 t2.tv_word;
                                             tv_closed = t2.tv_closed }
    | VTangle t1, VBraid g2    -> VTangle { tv_word = tensor_gens t1.tv_word g2;
                                             tv_closed = t1.tv_closed }
    | _ -> eval_error "Cannot tensor %s with %s" (pp_value v1) (pp_value v2)
    end

  (* Arithmetic *)
  | Add ->
    begin match v1, v2 with
    | VInt a, VInt b       -> VInt (a + b)
    | VFloat a, VFloat b   -> VFloat (a +. b)
    | VInt a, VFloat b     -> VFloat (float_of_int a +. b)
    | VFloat a, VInt b     -> VFloat (a +. float_of_int b)
    | VTangle t1, VTangle t2 ->
      (* Disjoint union of closed tangles *)
      VTangle { tv_word = t1.tv_word @ t2.tv_word;
                tv_closed = t1.tv_closed && t2.tv_closed }
    | _ -> eval_error "Cannot add %s and %s" (pp_value v1) (pp_value v2)
    end

  | Sub ->
    begin match v1, v2 with
    | VInt a, VInt b       -> VInt (a - b)
    | VFloat a, VFloat b   -> VFloat (a -. b)
    | VInt a, VFloat b     -> VFloat (float_of_int a -. b)
    | VFloat a, VInt b     -> VFloat (a -. float_of_int b)
    | _ -> eval_error "Cannot subtract %s from %s" (pp_value v2) (pp_value v1)
    end

  | Mul ->
    begin match v1, v2 with
    | VInt a, VInt b       -> VInt (a * b)
    | VFloat a, VFloat b   -> VFloat (a *. b)
    | VInt a, VFloat b     -> VFloat (float_of_int a *. b)
    | VFloat a, VInt b     -> VFloat (a *. float_of_int b)
    | _ -> eval_error "Cannot multiply %s and %s" (pp_value v1) (pp_value v2)
    end

  | Div ->
    begin match v1, v2 with
    | VInt _, VInt 0       -> eval_error "Division by zero"
    | VInt a, VInt b       -> VInt (a / b)
    | VFloat _, VFloat 0.0 -> eval_error "Division by zero"
    | VFloat a, VFloat b   -> VFloat (a /. b)
    | VInt a, VFloat b     ->
      if b = 0.0 then eval_error "Division by zero";
      VFloat (float_of_int a /. b)
    | VFloat a, VInt b     ->
      if b = 0 then eval_error "Division by zero";
      VFloat (a /. float_of_int b)
    | _ -> eval_error "Cannot divide %s by %s" (pp_value v1) (pp_value v2)
    end

  (* Equality: structural comparison *)
  | Eq ->
    begin match v1, v2 with
    | VInt a, VInt b       -> VBool (a = b)
    | VFloat a, VFloat b   -> VBool (a = b)
    | VBool a, VBool b     -> VBool (a = b)
    | VString a, VString b -> VBool (a = b)
    | VBraid g1, VBraid g2 -> VBool (g1 = g2)
    | _ -> eval_error "Cannot compare %s == %s" (pp_value v1) (pp_value v2)
    end

  (* Isotopy: compare simplified braid words *)
  | Isotopy ->
    begin match v1, v2 with
    | VBraid g1, VBraid g2 ->
      VBool (simplify_gens g1 = simplify_gens g2)
    | VTangle t1, VTangle t2 ->
      VBool (simplify_gens t1.tv_word = simplify_gens t2.tv_word)
    | VBraid g1, VTangle t2 ->
      VBool (simplify_gens g1 = simplify_gens t2.tv_word)
    | VTangle t1, VBraid g2 ->
      VBool (simplify_gens t1.tv_word = simplify_gens g2)
    | _ -> eval_error "Cannot test isotopy of %s ~ %s" (pp_value v1) (pp_value v2)
    end

(* ================================================================== *)
(*  Statement evaluation                                               *)
(* ================================================================== *)

(** Evaluate a single statement, returning the (possibly extended) environment
 *  and an optional output string (for compute/assert results).
 *)
let eval_statement (env : env) (stmt : statement) : env * string option =
  match stmt with

  | Definition def ->
    if def.def_params = [] then begin
      (* Value definition: def x = e *)
      let v = eval_expr env def.def_body in
      (env_bind env def.def_name v, None)
    end else begin
      (* Function definition: def f(x1, ..., xk) = body *)
      let closure = VFun (def.def_params, def.def_body, env) in
      (env_bind env def.def_name closure, None)
    end

  | WeaveBlock _wb ->
    (* Weave blocks are structural — no runtime evaluation needed.
       They define tangle morphisms checked at the type level. *)
    (env, None)

  | Computation comp ->
    let v = eval_expr env comp.comp_arg in
    let gens = gens_of_value v in
    let result = compute_invariant comp.comp_invariant gens in
    let output = Printf.sprintf "%s = %s" comp.comp_invariant result in
    let inv_val = VInvariant (comp.comp_invariant, result) in
    let env' = env_bind env ("_last_" ^ comp.comp_invariant) inv_val in
    (env', Some output)

  | Assertion e ->
    let v = eval_expr env e in
    begin match v with
    | VBool true  -> (env, Some "assertion passed")
    | VBool false -> eval_error "Assertion failed"
    | _ -> eval_error "assert requires a boolean, got %s" (pp_value v)
    end

  | StmtError ->
    (env, None)

(* ================================================================== *)
(*  Program evaluation                                                 *)
(* ================================================================== *)

(** Result of evaluating a program. *)
type eval_result = {
  eval_env     : env;
  eval_outputs : string list;
}

(** Evaluate a complete program.
 *  Returns the final environment and collected output strings.
 *)
let eval_program (prog : program) : eval_result =
  let (final_env, outputs) = List.fold_left (fun (env, outs) stmt ->
    let (env', out) = eval_statement env stmt in
    let outs' = match out with
      | Some s -> outs @ [s]
      | None   -> outs
    in
    (env', outs')
  ) ([], []) prog in
  { eval_env = final_env; eval_outputs = outputs }

(** Evaluate a single expression in the given environment.
 *  Convenience wrapper for REPL use.
 *)
let eval_expr_in_env (env : env) (e : expr) : value =
  eval_expr env e
