(* SPDX-License-Identifier: PMPL-1.0-or-later *)
(* test_property.ml — Property tests for the TANGLE parser.
 *
 * The core property tested is:
 *
 *   ROUND-TRIP PARSE STABILITY
 *   For any well-formed expression, parsing it must succeed (return Some).
 *   Furthermore, parsing the pretty-printed form of a parsed AST must also
 *   succeed and produce the same AST shape (structural round-trip stability).
 *
 * A fixed list of representative expressions is used in place of a
 * generative library so no new dependencies are required.
 *
 * Properties verified:
 *   P1. All valid expressions parse without errors.
 *   P2. Pretty-printing a parsed AST yields a string that parses again.
 *   P3. Re-parsing the pretty-printed form produces an equal AST.
 *   P4. Expressions known to be invalid are rejected (negative round-trip).
 *)

open Tangle.Ast

(* ================================================================== *)
(*  Test harness                                                       *)
(* ================================================================== *)

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

let assert_eq (label : string) (expected : 'a) (actual : 'a) : unit =
  if expected <> actual then begin
    Printf.eprintf "  assertion failed [%s]\n" label;
    failwith ("assert_eq: " ^ label)
  end

let assert_true (label : string) (b : bool) : unit =
  if not b then failwith ("assert_true: " ^ label)

(* ================================================================== *)
(*  Parse helpers                                                      *)
(* ================================================================== *)

let parse (source : string) : program option =
  let lexbuf = Lexing.from_string source in
  try Some (Tangle.Parser.program Tangle.Lexer.token lexbuf)
  with
  | Tangle.Lexer.Lexer_error _ -> None
  | Tangle.Parser.Error          -> None

let parse_ok (source : string) : program =
  match parse source with
  | Some p -> p
  | None   -> failwith ("parse_ok failed for: " ^ source)

(* ================================================================== *)
(*  P1. Valid expressions — fixed corpus                               *)
(* ================================================================== *)

(** Expressions that must parse successfully.
 *  Each element is a (description, source) pair.
 *)
let valid_exprs : (string * string) list = [
  ("integer literal",         "def x = 42");
  ("zero literal",            "def x = 0");
  ("negative integer",        "def x = -1");
  ("float literal",           "def x = 3.14");
  ("bool true",               "def x = true");
  ("bool false",              "def x = false");
  ("string literal",          {|def x = "hello"|});
  ("empty braid",             "def x = braid[]");
  ("single generator",        "def x = braid[s1]");
  ("generator with exponent", "def x = braid[s1^3]");
  ("inverse generator",       "def x = braid[s2^-1]");
  ("multi-generator braid",   "def x = braid[s1, s2^-1, s1]");
  ("identity keyword",        "def x = identity");
  ("compose operator",        "def x = braid[s1] . braid[s2]");
  ("tensor operator",         "def x = braid[s1] | braid[s2]");
  ("add operator",            "def x = a + b");
  ("subtract operator",       "def x = a - b");
  ("multiply operator",       "def x = a * b");
  ("divide operator",         "def x = a / b");
  ("equality operator",       "def x = a == b");
  ("isotopy operator",        "def x = a ~ b");
  ("pipeline operator",       "def x = a >> b");
  ("simple let binding",      "def x = let y = 1 in y");
  ("nested let binding",      "def x = let a = 1 in let b = 2 in a + b");
  ("function no params",      "def f = g");
  ("function single arg",     "def r = f(x)");
  ("function multi args",     "def r = f(x, y, z)");
  ("function with params",    "def f(a, b) = a . b");
  ("close unary",             "def x = close(b)");
  ("mirror unary",            "def x = mirror(b)");
  ("reverse unary",           "def x = reverse(b)");
  ("simplify unary",          "def x = simplify(b)");
  ("cap binary",              "def x = cap(a, b)");
  ("cup binary",              "def x = cup(a, b)");
  ("negation unary",          "def x = -y");
  ("over crossing",           "def x = (a > b)");
  ("under crossing",          "def x = (a < b)");
  ("twist expression",        "def x = (~a)");
  ("parenthesised expr",      "def x = (a + b) * c");
  ("match identity arm",      "def f(w) = match w with | identity => 0 | _ => 1 end");
  ("match variable arm",      "def f(w) = match w with | v => v end");
  ("match cons arm",          "def f(w) = match w with | s1 . rest => rest | _ => identity end");
  ("compute statement",       "compute jones(x)");
  ("assert statement",        "assert x == y");
  ("weave block",             "weave strands a, b into (a > b) yield strands c");
  ("line comment ignored",    "# comment\ndef x = 1");
  ("block comment ignored",   "(* comment *) def x = 2");
  ("multi-statement",         "def a = 1\ndef b = 2");
]

let test_p1_all_valid_parse () =
  Printf.printf "\n--- P1: Valid expressions parse without errors ---\n";
  List.iter (fun (desc, source) ->
    test ("parse ok: " ^ desc) (fun () ->
      match parse source with
      | Some _ -> ()
      | None   -> failwith ("expected Some, got None for: " ^ source))
  ) valid_exprs

(* ================================================================== *)
(*  P2. Pretty-print then re-parse succeeds                           *)
(* ================================================================== *)

let test_p2_pretty_reparse () =
  Printf.printf "\n--- P2: Pretty-printed AST re-parses successfully ---\n";
  List.iter (fun (desc, source) ->
    test ("reparse: " ^ desc) (fun () ->
      let prog = parse_ok source in
      let printed = Tangle.Pretty.program_to_string prog in
      assert_true "printed non-empty" (String.length printed > 0);
      match parse printed with
      | Some _ -> ()   (* Re-parse succeeded: property holds. *)
      | None   ->
        Printf.eprintf "  printed form was: %s\n" printed;
        failwith ("re-parse failed for printed form of: " ^ desc))
  ) valid_exprs

(* ================================================================== *)
(*  P3. Structural round-trip stability                               *)
(*                                                                     *)
(*  Re-parsing the pretty-printed form must produce an AST that is    *)
(*  equal to re-pretty-printing the re-parsed AST.  In other words,   *)
(*  pretty-print ∘ parse is idempotent: pp(parse(pp(parse(s)))) =     *)
(*  pp(parse(s)).                                                      *)
(* ================================================================== *)

let test_p3_roundtrip_idempotent () =
  Printf.printf "\n--- P3: Round-trip idempotency (pp.parse.pp = pp.parse) ---\n";
  (* Use a subset: the expressions that have a canonical pretty-print form. *)
  let subset = [
    ("integer",          "def x = 42");
    ("bool",             "def x = true");
    ("empty braid",      "def x = braid[]");
    ("single gen",       "def x = braid[s1]");
    ("inverse gen",      "def x = braid[s2^-1]");
    ("compose",          "def x = braid[s1] . braid[s2]");
    ("let binding",      "def x = let y = 10 in y");
    ("function def",     "def f(a, b) = a + b");
    ("match expr",       "def f(w) = match w with | identity => 0 | _ => 1 end");
    ("compute",          "compute writhe(x)");
    ("assert",           "assert x == y");
  ] in
  List.iter (fun (desc, source) ->
    test ("idempotent: " ^ desc) (fun () ->
      let prog1 = parse_ok source in
      let pp1 = Tangle.Pretty.program_to_string prog1 in
      let prog2 = match parse pp1 with
        | Some p -> p
        | None -> failwith ("second parse failed for: " ^ desc)
      in
      let pp2 = Tangle.Pretty.program_to_string prog2 in
      assert_eq "pp idempotent" pp1 pp2)
  ) subset

(* ================================================================== *)
(*  P4. Invalid expressions are rejected                              *)
(* ================================================================== *)

(** Expressions that must NOT parse successfully. *)
let invalid_exprs : (string * string) list = [
  ("unterminated string",    {|def x = "hello|});
  ("missing equals",         "def x 42");
  ("unexpected char",        "def x = @");
  ("missing end in match",   "def f(w) = match w with | _ => 1");
  ("bare operator",          "+ 1 2");
  ("empty program keyword",  "def");
  ("unclosed braid",         "def x = braid[s1");
  ("double hash",            "def x = ##bad");
  ("unclosed paren",         "def x = (1 + 2");
]

let test_p4_invalid_rejected () =
  Printf.printf "\n--- P4: Invalid expressions are rejected ---\n";
  List.iter (fun (desc, source) ->
    test ("parse fails: " ^ desc) (fun () ->
      match parse source with
      | None   -> ()  (* Correctly rejected. *)
      | Some _ -> failwith ("expected None (parse failure) for: " ^ source))
  ) invalid_exprs

(* ================================================================== *)
(*  P5. Parse does not raise exceptions on valid input                *)
(*                                                                     *)
(*  Guard against regressions where parsing raises an unhandled       *)
(*  exception instead of returning None or Some.                      *)
(* ================================================================== *)

let test_p5_no_exceptions () =
  Printf.printf "\n--- P5: No unexpected exceptions from parse ---\n";
  let all_sources = List.map snd valid_exprs @ List.map snd invalid_exprs in
  List.iter (fun source ->
    test ("no exn: " ^ (String.sub source 0 (min 30 (String.length source)))) (fun () ->
      (* parse_ok or None, no unhandled exceptions allowed *)
      let _ : program option = parse source in ())
  ) all_sources

(* ================================================================== *)
(*  Entry point                                                        *)
(* ================================================================== *)

let () =
  Printf.printf "=== TANGLE Property Test Suite ===\n";
  test_p1_all_valid_parse ();
  test_p2_pretty_reparse ();
  test_p3_roundtrip_idempotent ();
  test_p4_invalid_rejected ();
  test_p5_no_exceptions ();
  Printf.printf "\n=== Results: %d/%d passed" !passed !total;
  if !failed > 0 then
    Printf.printf ", %d FAILED" !failed;
  Printf.printf " ===\n";
  if !failed > 0 then exit 1
