(* SPDX-License-Identifier: MPL-2.0 *)
(* compositional.ml — Compositional tangle-expression AST and PD compiler.
 *
 * This module is intentionally narrow:
 * - It models only compositional syntax (generators, composition, tensor, closure).
 * - It compiles to a PlanarDiagram-equivalent IR.
 * - It exposes pure hook payloads for Skein ingestion.
 *
 * It does NOT implement invariants or persistence.
 *)

open Ast

(* ================================================================== *)
(*  Core compositional AST                                             *)
(* ================================================================== *)

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

(* ================================================================== *)
(*  Builder API                                                       *)
(* ================================================================== *)

let identity = Identity
let gen ?(exponent = 1) index = Gen { index; exponent }
let braid gens = Braid gens
let compose a b = Compose (a, b)
let tensor a b = Tensor (a, b)
let close e = Close e

(* ================================================================== *)
(*  Planar diagram IR                                                  *)
(* ================================================================== *)

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

(* ================================================================== *)
(*  Skein hook payload                                                 *)
(* ================================================================== *)

type skein_payload = {
  name : string;
  pd_blob : string;
  pd_entries : (int * int * int * int * int) list;
  crossing_number : int;
}

type skein_sink = skein_payload -> unit

(* ================================================================== *)
(*  Result helpers                                                     *)
(* ================================================================== *)

let ( let* ) r f =
  match r with
  | Ok x -> f x
  | Error _ as e -> e

let ok x = Ok x
let err msg = Error msg

(* ================================================================== *)
(*  Word utilities                                                     *)
(* ================================================================== *)

let validate_generator (g : generator) : (unit, compile_error) result =
  if g.index < 1 then
    err (Printf.sprintf "invalid generator index s%d (expected >= 1)" g.index)
  else if g.exponent = 0 then
    err (Printf.sprintf "invalid zero exponent for s%d" g.index)
  else
    ok ()

let expand_generator (g : generator) : generator list =
  let unit_exp = if g.exponent > 0 then 1 else -1 in
  let count = abs g.exponent in
  List.init count (fun _ -> { index = g.index; exponent = unit_exp })

let width_of_word (word : generator list) : int =
  List.fold_left (fun acc g -> max acc (g.index + 1)) 0 word

let shift_word (offset : int) (word : generator list) : generator list =
  List.map (fun g -> { g with index = g.index + offset }) word

let tensor_word (left : generator list) (right : generator list) : generator list =
  let w = width_of_word left in
  left @ shift_word w right

let rec word_of_expr (e : expr) : (generator list, compile_error) result =
  match e with
  | Identity -> ok []
  | Gen g ->
    let* () = validate_generator g in
    ok (expand_generator g)
  | Braid gens ->
    let rec loop acc = function
      | [] -> ok (List.rev acc)
      | g :: rest ->
        let* () = validate_generator g in
        let units = expand_generator g in
        loop (List.rev_append units acc) rest
    in
    loop [] gens
  | Compose (a, b) ->
    let* wa = word_of_expr a in
    let* wb = word_of_expr b in
    ok (wa @ wb)
  | Tensor (a, b) ->
    let* wa = word_of_expr a in
    let* wb = word_of_expr b in
    ok (tensor_word wa wb)
  | Close _ ->
    err "nested close is not compositional in open-word context"

let expr_of_word (word : generator list) : expr =
  if word = [] then Identity else Braid word

(* ================================================================== *)
(*  Compiler: braid word -> PD IR                                      *)
(* ================================================================== *)

let crossing_to_entry (c : crossing) : int * int * int * int * int =
  (c.under_in, c.over_out, c.under_out, c.over_in, c.sign)

let entries_of_pd (pd : planar_diagram) : (int * int * int * int * int) list =
  List.map crossing_to_entry pd.crossings

let compare_entry (a1, b1, c1, d1, s1) (a2, b2, c2, d2, s2) =
  match Int.compare a1 a2 with
  | 0 ->
    begin match Int.compare b1 b2 with
    | 0 ->
      begin match Int.compare c1 c2 with
      | 0 ->
        begin match Int.compare d1 d2 with
        | 0 -> Int.compare s1 s2
        | x -> x
        end
      | x -> x
      end
    | x -> x
    end
  | x -> x

let compare_int_list (a : int list) (b : int list) =
  let rec loop x y =
    match x, y with
    | [], [] -> 0
    | [], _ -> -1
    | _, [] -> 1
    | hx :: tx, hy :: ty ->
      begin match Int.compare hx hy with
      | 0 -> loop tx ty
      | c -> c
      end
  in
  loop a b

let canonicalize_pd (pd : planar_diagram) : planar_diagram =
  let all_arcs = Hashtbl.create 64 in
  List.iter (fun c ->
    Hashtbl.replace all_arcs c.under_in ();
    Hashtbl.replace all_arcs c.over_out ();
    Hashtbl.replace all_arcs c.under_out ();
    Hashtbl.replace all_arcs c.over_in ()
  ) pd.crossings;
  List.iter (fun comp ->
    List.iter (fun a -> Hashtbl.replace all_arcs a ()) comp
  ) pd.components;

  let arcs =
    Hashtbl.to_seq_keys all_arcs |> List.of_seq |> List.sort Int.compare
  in
  let arc_map = Hashtbl.create (List.length arcs) in
  List.iteri (fun i a -> Hashtbl.replace arc_map a (i + 1)) arcs;
  let remap a = match Hashtbl.find_opt arc_map a with Some x -> x | None -> a in

  let remapped_entries =
    entries_of_pd pd
    |> List.map (fun (a, b, c, d, s) -> (remap a, remap b, remap c, remap d, s))
    |> List.sort compare_entry
  in
  let remapped_crossings =
    List.map (fun (a, b, c, d, s) ->
      { under_in = a; over_out = b; under_out = c; over_in = d; sign = s }
    ) remapped_entries
  in

  let remapped_components =
    pd.components
    |> List.map (fun comp -> List.map remap comp |> List.sort Int.compare)
    |> List.sort compare_int_list
  in
  { pd with crossings = remapped_crossings; components = remapped_components }

let pdv1_blob_of_pd (pd : planar_diagram) : string =
  let canonical = canonicalize_pd pd in
  let crossing_chunks =
    entries_of_pd canonical
    |> List.map (fun (a, b, c, d, s) ->
      Printf.sprintf "%d,%d,%d,%d,%d" a b c d s
    )
  in
  let component_chunks =
    List.map (fun comp ->
      String.concat "," (List.map string_of_int comp)
    ) canonical.components
  in
  Printf.sprintf "pdv1|x=%s|c=%s"
    (String.concat ";" crossing_chunks)
    (String.concat ";" component_chunks)

let pd_of_closed_word (word : generator list) : (planar_diagram, compile_error) result =
  let width = width_of_word word in
  if word = [] then
    ok { crossings = []; components = []; closed = true; source_word = Some word }
  else if width < 2 then
    err "cannot close braid word with fewer than 2 strands"
  else begin
    let current_arc = Array.init width (fun i -> i + 1) in
    let next_arc = ref (width + 1) in
    let crossings_rev = ref [] in

    let step (g : generator) : (unit, compile_error) result =
      if g.exponent <> 1 && g.exponent <> -1 then
        err "internal error: expected unit exponents before PD lowering"
      else if g.index < 1 || g.index >= width then
        err (Printf.sprintf "generator s%d out of range for width %d" g.index width)
      else begin
        let i = g.index in
        let arc_in_i = current_arc.(i - 1) in
        let arc_in_i1 = current_arc.(i) in

        let arc_out_i = !next_arc in
        let arc_out_i1 = !next_arc + 1 in
        next_arc := !next_arc + 2;

        let crossing =
          if g.exponent > 0 then
            (* Positive generator: strand i crosses over i+1 *)
            { under_in = arc_in_i1; over_out = arc_out_i;
              under_out = arc_out_i1; over_in = arc_in_i; sign = 1 }
          else
            (* Negative generator: strand i+1 crosses over i *)
            { under_in = arc_in_i; over_out = arc_out_i1;
              under_out = arc_out_i; over_in = arc_in_i1; sign = -1 }
        in
        crossings_rev := crossing :: !crossings_rev;
        current_arc.(i - 1) <- arc_out_i;
        current_arc.(i) <- arc_out_i1;
        ok ()
      end
    in

    let rec run = function
      | [] -> ok ()
      | g :: rest ->
        let* () = step g in
        run rest
    in
    let* () = run word in

    let rename = Hashtbl.create width in
    for k = 1 to width do
      let bottom = current_arc.(k - 1) in
      if bottom <> k then Hashtbl.replace rename bottom k
    done;
    let remap a = match Hashtbl.find_opt rename a with Some x -> x | None -> a in
    let remapped =
      List.rev !crossings_rev
      |> List.map (fun c ->
        { c with
          under_in = remap c.under_in;
          over_out = remap c.over_out;
          under_out = remap c.under_out;
          over_in = remap c.over_in;
        })
    in
    ok { crossings = remapped; components = []; closed = true; source_word = Some word }
  end

(* ================================================================== *)
(*  AST adapter: compiler AST <-> compositional AST                    *)
(* ================================================================== *)

let generator_of_ast (g : Ast.generator) : generator =
  { index = g.gen_index; exponent = g.gen_exponent }

let ast_generator_of_generator (g : generator) : Ast.generator =
  { gen_index = g.index; gen_exponent = g.exponent }

let rec of_ast_expr (e : Ast.expr) : (expr, compile_error) result =
  match e with
  | Ast.Identity -> ok Identity
  | Ast.BraidLit gs ->
    ok (Braid (List.map generator_of_ast gs))
  | Ast.BinOp (Ast.Compose, a, b) ->
    let* ca = of_ast_expr a in
    let* cb = of_ast_expr b in
    ok (Compose (ca, cb))
  | Ast.BinOp (Ast.Tensor, a, b) ->
    let* ca = of_ast_expr a in
    let* cb = of_ast_expr b in
    ok (Tensor (ca, cb))
  | Ast.Pipeline (a, b) ->
    let* ca = of_ast_expr a in
    let* cb = of_ast_expr b in
    ok (Compose (ca, cb))
  | Ast.Close inner ->
    let* ci = of_ast_expr inner in
    ok (Close ci)
  | _ ->
    err "expression is outside compositional subset (expected generators/compose/tensor/close)"

let rec to_ast_expr (e : expr) : Ast.expr =
  match e with
  | Identity -> Ast.Identity
  | Gen g -> Ast.BraidLit [ast_generator_of_generator g]
  | Braid gs -> Ast.BraidLit (List.map ast_generator_of_generator gs)
  | Compose (a, b) -> Ast.BinOp (Ast.Compose, to_ast_expr a, to_ast_expr b)
  | Tensor (a, b) -> Ast.BinOp (Ast.Tensor, to_ast_expr a, to_ast_expr b)
  | Close x -> Ast.Close (to_ast_expr x)

let parse_expr (source : string) : (expr, compile_error) result =
  let wrapped = "def expr_tmp = " ^ source in
  let lexbuf = Lexing.from_string wrapped in
  try
    match Parser.program Lexer.token lexbuf with
    | [Ast.Definition d] when d.def_name = "expr_tmp" ->
      of_ast_expr d.def_body
    | _ ->
      err "could not isolate a single compositional expression"
  with
  | Lexer.Lexer_error msg -> err ("lexer error: " ^ msg)
  | Parser.Error -> err "parse error"

(* ================================================================== *)
(*  Compilation entrypoints                                            *)
(* ================================================================== *)

let compile (e : expr) : (compiled, compile_error) result =
  match e with
  | Close inner ->
    let* word = word_of_expr inner in
    let* pd = pd_of_closed_word word in
    ok (ClosedDiagram pd)
  | _ ->
    let* word = word_of_expr e in
    ok (OpenWord word)

let compile_source_expr (source : string) : (compiled, compile_error) result =
  let* e = parse_expr source in
  compile e

let word_of_compiled (c : compiled) : generator list option =
  match c with
  | OpenWord w -> Some w
  | ClosedDiagram pd -> pd.source_word

(* ================================================================== *)
(*  Skein hook helpers (pure data)                                     *)
(* ================================================================== *)

let skein_payload_of_pd ~name (pd : planar_diagram) : skein_payload =
  let canonical = canonicalize_pd pd in
  {
    name;
    pd_blob = pdv1_blob_of_pd canonical;
    pd_entries = entries_of_pd canonical;
    crossing_number = List.length canonical.crossings;
  }

let send_to_skein (sink : skein_sink) (payload : skein_payload) : unit =
  sink payload

let compile_and_send_to_skein
    (sink : skein_sink)
    ~(name : string)
    (e : expr)
  : (skein_payload, compile_error) result =
  let* c = compile e in
  match c with
  | OpenWord _ ->
    err "Skein hook expects a closed tangle expression"
  | ClosedDiagram pd ->
    let payload = skein_payload_of_pd ~name pd in
    send_to_skein sink payload;
    ok payload
