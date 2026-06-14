(* SPDX-License-Identifier: MPL-2.0 *)
(* Owner: Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk> *)
(*
 * test_roundtrip.ml — TG-4 pretty-print/parse round-trip property test.
 *
 * Obligation (PROOF-NARRATIVE.md §3 TG-4):
 *
 *   For every closed value e in the core Tangle language,
 *   parse(pretty(e)) = e
 *
 * Strategy:
 *   1. Build a fixed corpus of source strings exercising each AST node.
 *   2. Parse each source into a program AST.
 *   3. Pretty-print the AST back to a string.
 *   4. Re-parse the pretty-printed string.
 *   5. Compare the two ASTs for structural equality.
 *
 * Discharges:
 *   - PROOF-NARRATIVE.md §3 TG-4 (round-trip).
 *   - ASSUMPTIONS.md A-TG-4.1 (pretty printer is unambiguous w.r.t. parser).
 *   - ASSUMPTIONS.md A-TG-4.2 (lexer doesn't strip required information).
 *)

(* --------------------------------------------------------------------- *)
(*  Test harness — mirrors test_parser.ml/test_property.ml style         *)
(* --------------------------------------------------------------------- *)

let passed = ref 0
let failed = ref 0
let total  = ref 0

let test (name : string) (f : unit -> unit) : unit =
  incr total;
  try
    f ();
    incr passed;
    Printf.printf "  PASS: %s\n" name
  with exn ->
    incr failed;
    Printf.printf "  FAIL: %s (%s)\n" name (Printexc.to_string exn)

(* --------------------------------------------------------------------- *)
(*  Parser + pretty wrappers                                              *)
(* --------------------------------------------------------------------- *)

let parse (source : string) : Tangle.Ast.program option =
  let lexbuf = Lexing.from_string source in
  try Some (Tangle.Parser.program Tangle.Lexer.token lexbuf)
  with
  | _ -> None

let parse_ok (source : string) : Tangle.Ast.program =
  match parse source with
  | Some p -> p
  | None -> failwith ("parse failed for: " ^ source)

(* --------------------------------------------------------------------- *)
(*  AST equality — uses OCaml structural equality, but documented        *)
(* --------------------------------------------------------------------- *)

(* The Ast.program type is a list of statements built from algebraic
 * datatypes. OCaml's structural equality (=) correctly compares them
 * field-by-field.
 *
 * Known caveats:
 *   - Float literals: OCaml = compares floats by IEEE 754, which means
 *     NaN != NaN. The current corpus has no NaN/Inf literals so this
 *     is moot. If float literals are added, switch to a tolerant eq.
 *   - Position info: Ast.ml does not carry source positions, so they
 *     can't contaminate equality.
 *)
let program_equal (p1 : Tangle.Ast.program) (p2 : Tangle.Ast.program) : bool =
  p1 = p2

(* --------------------------------------------------------------------- *)
(*  Corpus: one source line per AST constructor (or as close as          *)
(*  practical given the v0.1.0 grammar).                                 *)
(* --------------------------------------------------------------------- *)

let basic_corpus : (string * string) list = [
  (* Literals + identity *)
  ("integer literal",    "def x = 42");
  ("string literal",     {|def x = "hello"|});
  ("bool true",          "def x = true");
  ("bool false",         "def x = false");
  ("identity",           "def x = identity");
  (* Braid generators *)
  ("empty braid",        "def x = braid[]");
  ("single sigma",       "def x = braid[s1]");
  ("trefoil-shaped",     "def x = braid[s1, s1, s1]");
  ("inverse generator",  "def x = braid[s2^-1]");
  ("mixed-sign braid",   "def x = braid[s1, s2^-1, s1]");
  (* Algebraic operations *)
  ("addition",           "def x = a + b");
  ("composition",        "def x = braid[s1] . braid[s2]");
  ("tensor product",     "def x = braid[s1] | braid[s2]");
  ("close call",         "def x = close(braid[s1])");
  ("equality",           "def x = a == b");
  (* Function definitions *)
  ("nullary def",        "def x = identity");
  ("unary def",          "def f(a) = a");
  ("binary def",         "def f(a, b) = a + b");
  (* Echo / structured-loss forms (PR #45) *)
  ("echoClose",          "def x = echoClose(a)");
  ("lower",              "def x = lower(a)");
  ("residue",            "def x = residue(a)");
  ("pair",               "def x = pair(a, b)");
  ("fst",                "def x = fst(a)");
  ("snd",                "def x = snd(a)");
  ("echoAdd",            "def x = echoAdd(a, b)");
  ("echoEq",             "def x = echoEq(a, b)");
]

(* --------------------------------------------------------------------- *)
(*  Test bodies                                                          *)
(* --------------------------------------------------------------------- *)

let test_roundtrip_basic () =
  Printf.printf "\n--- TG-4: Basic round-trip on per-constructor corpus ---\n";
  List.iter (fun (label, source) ->
    test ("roundtrip: " ^ label) (fun () ->
      let prog1 = parse_ok source in
      let pp_text = Tangle.Pretty.program_to_string prog1 in
      match parse pp_text with
      | None ->
        Printf.eprintf "  re-parse failed for pretty output:\n    %s\n" pp_text;
        failwith ("re-parse failed: " ^ label)
      | Some prog2 ->
        if not (program_equal prog1 prog2) then begin
          Printf.eprintf "  AST mismatch on %s\n" label;
          Printf.eprintf "    source: %s\n" source;
          Printf.eprintf "    pretty: %s\n" pp_text;
          failwith ("ast mismatch: " ^ label)
        end)
  ) basic_corpus

let test_roundtrip_idempotent () =
  Printf.printf "\n--- TG-4: pretty(parse(pretty(parse(s)))) = pretty(parse(s)) ---\n";
  (* If parse and pretty are inverse on the AST level, then they're also
   * inverse on the pretty-form level after one normalisation pass.
   * This catches cases where the pretty printer is right-inverse but
   * not left-inverse (e.g. drops sugar). *)
  List.iter (fun (label, source) ->
    test ("idempotent: " ^ label) (fun () ->
      let prog1 = parse_ok source in
      let pp1 = Tangle.Pretty.program_to_string prog1 in
      let prog2 = parse_ok pp1 in
      let pp2 = Tangle.Pretty.program_to_string prog2 in
      if pp1 <> pp2 then begin
        Printf.eprintf "  Pretty-form drift on %s\n" label;
        Printf.eprintf "    first  pretty: %s\n" pp1;
        Printf.eprintf "    second pretty: %s\n" pp2;
        failwith ("pretty drift: " ^ label)
      end)
  ) basic_corpus

(* --------------------------------------------------------------------- *)
(*  Entry point                                                          *)
(* --------------------------------------------------------------------- *)

let () =
  Printf.printf "=== TG-4 round-trip property tests ===\n";
  Printf.printf "Obligation: parse(pretty(e)) = e for closed e in core Tangle.\n";
  test_roundtrip_basic ();
  test_roundtrip_idempotent ();
  Printf.printf "\n=== Results: %d/%d passed" !passed !total;
  if !failed > 0 then
    Printf.printf ", %d FAILED" !failed;
  Printf.printf " ===\n";
  if !failed > 0 then exit 1
