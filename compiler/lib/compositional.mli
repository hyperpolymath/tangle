(* SPDX-License-Identifier: PMPL-1.0-or-later *)

type generator = {
  index : int;
  exponent : int;
}

type expr =
  | Identity
  | Gen of generator
  | Braid of generator list
  | Compose of expr * expr
  | Tensor of expr * expr
  | Close of expr

type compile_error = string

val identity : expr
val gen : ?exponent:int -> int -> expr
val braid : generator list -> expr
val compose : expr -> expr -> expr
val tensor : expr -> expr -> expr
val close : expr -> expr

type crossing = {
  under_in : int;
  over_out : int;
  under_out : int;
  over_in : int;
  sign : int;
}

type planar_diagram = {
  crossings : crossing list;
  components : int list list;
  closed : bool;
  source_word : generator list option;
}

type compiled =
  | OpenWord of generator list
  | ClosedDiagram of planar_diagram

val word_of_expr : expr -> (generator list, compile_error) result
val expr_of_word : generator list -> expr

val of_ast_expr : Ast.expr -> (expr, compile_error) result
val to_ast_expr : expr -> Ast.expr
val parse_expr : string -> (expr, compile_error) result

val compile : expr -> (compiled, compile_error) result
val compile_source_expr : string -> (compiled, compile_error) result
val word_of_compiled : compiled -> generator list option

val entries_of_pd : planar_diagram -> (int * int * int * int * int) list
val canonicalize_pd : planar_diagram -> planar_diagram
val pdv1_blob_of_pd : planar_diagram -> string
val pd_of_closed_word : generator list -> (planar_diagram, compile_error) result

type skein_payload = {
  name : string;
  pd_blob : string;
  pd_entries : (int * int * int * int * int) list;
  crossing_number : int;
}

type skein_sink = skein_payload -> unit

val skein_payload_of_pd : name:string -> planar_diagram -> skein_payload
val send_to_skein : skein_sink -> skein_payload -> unit
val compile_and_send_to_skein :
  skein_sink -> name:string -> expr -> (skein_payload, compile_error) result

