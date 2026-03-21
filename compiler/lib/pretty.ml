(* SPDX-License-Identifier: PMPL-1.0-or-later *)
(* pretty.ml — AST pretty printer for TANGLE.
 *
 * Produces a human-readable, indented representation of a parsed
 * TANGLE program for debugging and test verification.
 *)

open Ast

(** Buffer-based pretty printer state. *)
type ctx = {
  buf    : Buffer.t;
  mutable indent : int;
}

(** Create a fresh printer context. *)
let mk_ctx () = { buf = Buffer.create 1024; indent = 0 }

(** Emit a string to the buffer. *)
let emit ctx s = Buffer.add_string ctx.buf s

(** Emit a newline followed by indentation. *)
let nl ctx =
  Buffer.add_char ctx.buf '\n';
  for _ = 1 to ctx.indent * 2 do
    Buffer.add_char ctx.buf ' '
  done

(** Run [f] at one deeper indentation level. *)
let indented ctx f =
  ctx.indent <- ctx.indent + 1;
  f ();
  ctx.indent <- ctx.indent - 1

(* ------------------------------------------------------------------ *)
(*  Operator names                                                     *)
(* ------------------------------------------------------------------ *)

let string_of_binop = function
  | Add     -> "+"
  | Sub     -> "-"
  | Mul     -> "*"
  | Div     -> "/"
  | Eq      -> "=="
  | Isotopy -> "~"
  | Compose -> "."
  | Tensor  -> "|"

let string_of_unaryop = function
  | Neg -> "-"
  | Not -> "!"

let string_of_crossing_op = function
  | Over  -> ">"
  | Under -> "<"

(* ------------------------------------------------------------------ *)
(*  Generator                                                          *)
(* ------------------------------------------------------------------ *)

let pp_generator ctx g =
  emit ctx (Printf.sprintf "s%d" g.gen_index);
  if g.gen_exponent <> 1 then
    emit ctx (Printf.sprintf "^%d" g.gen_exponent)

let pp_gen_pattern ctx g =
  emit ctx (Printf.sprintf "s%d" g.gpat_index);
  if g.gpat_exponent <> 1 then
    emit ctx (Printf.sprintf "^%d" g.gpat_exponent)

(* ------------------------------------------------------------------ *)
(*  Patterns                                                           *)
(* ------------------------------------------------------------------ *)

let rec pp_pattern ctx = function
  | PatIdentity ->
    emit ctx "identity"
  | PatCons (g, rest) ->
    pp_gen_pattern ctx g;
    emit ctx " . ";
    pp_pattern ctx rest
  | PatVar name ->
    emit ctx name
  | PatWildcard ->
    emit ctx "_"

(* ------------------------------------------------------------------ *)
(*  Expressions                                                        *)
(* ------------------------------------------------------------------ *)

let rec pp_expr ctx = function
  | Match (scrut, arms) ->
    emit ctx "match ";
    pp_expr ctx scrut;
    emit ctx " with";
    indented ctx (fun () ->
      List.iter (fun arm ->
        nl ctx;
        emit ctx "| ";
        pp_pattern ctx arm.arm_pattern;
        emit ctx " => ";
        pp_expr ctx arm.arm_body
      ) arms);
    nl ctx;
    emit ctx "end"

  | Let (name, value, body) ->
    emit ctx "let ";
    emit ctx name;
    emit ctx " = ";
    pp_expr ctx value;
    emit ctx " in ";
    pp_expr ctx body

  | Pipeline (l, r) ->
    emit ctx "(";
    pp_expr ctx l;
    emit ctx " >> ";
    pp_expr ctx r;
    emit ctx ")"

  | BinOp (op, l, r) ->
    emit ctx "(";
    pp_expr ctx l;
    emit ctx " ";
    emit ctx (string_of_binop op);
    emit ctx " ";
    pp_expr ctx r;
    emit ctx ")"

  | UnaryOp (op, e) ->
    emit ctx (string_of_unaryop op);
    pp_expr ctx e

  | Close e ->
    emit ctx "close(";
    pp_expr ctx e;
    emit ctx ")"

  | Mirror e ->
    emit ctx "mirror(";
    pp_expr ctx e;
    emit ctx ")"

  | Reverse e ->
    emit ctx "reverse(";
    pp_expr ctx e;
    emit ctx ")"

  | Simplify e ->
    emit ctx "simplify(";
    pp_expr ctx e;
    emit ctx ")"

  | Cap (e1, e2) ->
    emit ctx "cap(";
    pp_expr ctx e1;
    emit ctx ", ";
    pp_expr ctx e2;
    emit ctx ")"

  | Cup (e1, e2) ->
    emit ctx "cup(";
    pp_expr ctx e1;
    emit ctx ", ";
    pp_expr ctx e2;
    emit ctx ")"

  | Twist e ->
    emit ctx "(~";
    pp_expr ctx e;
    emit ctx ")"

  | BraidLit gens ->
    emit ctx "braid[";
    List.iteri (fun i g ->
      if i > 0 then emit ctx ", ";
      pp_generator ctx g
    ) gens;
    emit ctx "]"

  | Identity ->
    emit ctx "identity"

  | BoolLit b ->
    emit ctx (if b then "true" else "false")

  | IntLit n ->
    emit ctx (string_of_int n)

  | FloatLit f ->
    emit ctx (Printf.sprintf "%g" f)

  | StringLit s ->
    emit ctx "\"";
    emit ctx (String.escaped s);
    emit ctx "\""

  | Var name ->
    emit ctx name

  | Call (name, args) ->
    emit ctx name;
    emit ctx "(";
    List.iteri (fun i a ->
      if i > 0 then emit ctx ", ";
      pp_expr ctx a
    ) args;
    emit ctx ")"

  | Crossing (a, op, b) ->
    emit ctx "(";
    emit ctx a;
    emit ctx " ";
    emit ctx (string_of_crossing_op op);
    emit ctx " ";
    emit ctx b;
    emit ctx ")"

(* ------------------------------------------------------------------ *)
(*  Typed strands                                                      *)
(* ------------------------------------------------------------------ *)

let pp_typed_strand ctx ts =
  emit ctx ts.strand_name;
  match ts.strand_type with
  | Some t -> emit ctx ": "; emit ctx t
  | None -> ()

let pp_strand_list ctx strands =
  List.iteri (fun i s ->
    if i > 0 then emit ctx ", ";
    pp_typed_strand ctx s
  ) strands

(* ------------------------------------------------------------------ *)
(*  Statements                                                         *)
(* ------------------------------------------------------------------ *)

let pp_statement ctx = function
  | Definition d ->
    emit ctx "def ";
    emit ctx d.def_name;
    if d.def_params <> [] then begin
      emit ctx "(";
      List.iteri (fun i p ->
        if i > 0 then emit ctx ", ";
        emit ctx p
      ) d.def_params;
      emit ctx ")"
    end;
    emit ctx " = ";
    pp_expr ctx d.def_body;
    nl ctx

  | WeaveBlock w ->
    emit ctx "weave strands ";
    pp_strand_list ctx w.weave_inputs;
    emit ctx " into";
    indented ctx (fun () ->
      nl ctx;
      pp_expr ctx w.weave_body);
    nl ctx;
    emit ctx "yield strands ";
    pp_strand_list ctx w.weave_outputs;
    nl ctx

  | Computation c ->
    emit ctx "compute ";
    emit ctx c.comp_invariant;
    emit ctx "(";
    pp_expr ctx c.comp_arg;
    emit ctx ")";
    nl ctx

  | Assertion e ->
    emit ctx "assert ";
    pp_expr ctx e;
    nl ctx

  | StmtError ->
    emit ctx "(* parse error *)";
    nl ctx

(* ------------------------------------------------------------------ *)
(*  Program                                                            *)
(* ------------------------------------------------------------------ *)

let pp_program ctx stmts =
  List.iter (fun s ->
    pp_statement ctx s;
    nl ctx
  ) stmts

(* ------------------------------------------------------------------ *)
(*  Public API                                                         *)
(* ------------------------------------------------------------------ *)

(** Pretty-print a program to a string. *)
let program_to_string (prog : program) : string =
  let ctx = mk_ctx () in
  pp_program ctx prog;
  Buffer.contents ctx.buf

(** Pretty-print a single expression to a string. *)
let expr_to_string (e : expr) : string =
  let ctx = mk_ctx () in
  pp_expr ctx e;
  Buffer.contents ctx.buf

(** Pretty-print a single statement to a string. *)
let statement_to_string (s : statement) : string =
  let ctx = mk_ctx () in
  pp_statement ctx s;
  Buffer.contents ctx.buf
