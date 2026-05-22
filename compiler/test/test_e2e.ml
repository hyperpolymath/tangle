(* SPDX-License-Identifier: MPL-2.0 *)
(* test_e2e.ml — End-to-end test suite for the TANGLE pipeline.
 *
 * Each test case runs the full chain:
 *   source string → parse → typecheck → evaluate → inspect result
 *
 * This verifies that the three compiler passes (parser, typechecker, evaluator)
 * interoperate correctly and that representative TANGLE programs produce the
 * expected runtime values.
 *
 * Tests cover:
 *   1.  Simple value definitions
 *   2.  Braid literal evaluation
 *   3.  Braid composition (concat)
 *   4.  Braid simplification
 *   5.  Mirror and reverse
 *   6.  Close (braid → tangle)
 *   7.  Pattern matching on braid words
 *   8.  Let bindings
 *   9.  Function definition and application
 *  10.  Arithmetic operators
 *  11.  Equality and isotopy comparisons
 *  12.  Compute invariant statements (writhe)
 *  13.  Assertion statements
 *  14.  Multi-statement programs
 *  15.  Pipeline operator
 *)

open Tangle.Ast
open Tangle.Eval

(* ================================================================== *)
(*  Test harness (mirrors test_parser.ml style)                       *)
(* ================================================================== *)

let passed = ref 0
let failed = ref 0
let total  = ref 0

(** Run a named test and report pass/fail. *)
let test (name : string) (f : unit -> unit) : unit =
  incr total;
  try
    f ();
    incr passed;
    Printf.printf "  PASS: %s\n" name
  with exn ->
    incr failed;
    Printf.printf "  FAIL: %s (%s)\n" name (Printexc.to_string exn)

(** Assert structural equality, raising on mismatch. *)
let assert_eq (label : string) (expected : 'a) (actual : 'a) : unit =
  if expected <> actual then begin
    Printf.eprintf "  assertion failed [%s]: expected <> actual\n" label;
    failwith ("assert_eq: " ^ label)
  end

(** Assert that a boolean is true. *)
let assert_true (label : string) (b : bool) : unit =
  if not b then begin
    Printf.eprintf "  assert_true failed: %s\n" label;
    failwith ("assert_true: " ^ label)
  end

(* ================================================================== *)
(*  Pipeline helpers                                                   *)
(* ================================================================== *)

(** Parse a source string.  Raises [Failure "parse"] on error. *)
let parse_source (source : string) : program =
  let lexbuf = Lexing.from_string source in
  try Tangle.Parser.program Tangle.Lexer.token lexbuf
  with
  | Tangle.Lexer.Lexer_error msg ->
    failwith ("lex error: " ^ msg)
  | Tangle.Parser.Error ->
    failwith ("parse error in: " ^ source)

(** Typecheck a program.  Raises [Tangle.Typecheck.Type_error _] on failure. *)
let typecheck (prog : program) : unit =
  let _ = Tangle.Typecheck.check_program prog in ()

(** Evaluate a program and return the evaluation result. *)
let evaluate (prog : program) : eval_result =
  eval_program prog

(** Full pipeline: parse → typecheck → evaluate. *)
let run_pipeline (source : string) : eval_result =
  let prog = parse_source source in
  typecheck prog;
  evaluate prog

(** Convenience: run pipeline and look up a named binding. *)
let run_and_lookup (source : string) (name : string) : value option =
  let result = run_pipeline source in
  env_lookup result.eval_env name

(* ================================================================== *)
(*  1. Simple value definitions                                        *)
(* ================================================================== *)

let test_simple_defs () =
  Printf.printf "\n--- 1. Simple value definitions ---\n";

  test "integer binding" (fun () ->
    let v = run_and_lookup "def answer = 42" "answer" in
    assert_eq "value" (Some (VInt 42)) v);

  test "boolean binding true" (fun () ->
    let v = run_and_lookup "def flag = true" "flag" in
    assert_eq "value" (Some (VBool true)) v);

  test "boolean binding false" (fun () ->
    let v = run_and_lookup "def flag = false" "flag" in
    assert_eq "value" (Some (VBool false)) v);

  test "string binding" (fun () ->
    let v = run_and_lookup {|def greeting = "hello"|} "greeting" in
    assert_eq "value" (Some (VString "hello")) v);

  test "identity binding" (fun () ->
    let v = run_and_lookup "def unit = identity" "unit" in
    assert_eq "value" (Some (VBraid [])) v)

(* ================================================================== *)
(*  2. Braid literal evaluation                                        *)
(* ================================================================== *)

let test_braid_literals () =
  Printf.printf "\n--- 2. Braid literal evaluation ---\n";

  test "empty braid" (fun () ->
    let v = run_and_lookup "def e = braid[]" "e" in
    assert_eq "value" (Some (VBraid [])) v);

  test "single generator s1" (fun () ->
    let v = run_and_lookup "def g = braid[s1]" "g" in
    assert_eq "value" (Some (VBraid [{ g_index = 1; g_exponent = 1 }])) v);

  test "trefoil literal" (fun () ->
    let v = run_and_lookup "def t = braid[s1, s1, s1]" "t" in
    let expected = VBraid [
      { g_index = 1; g_exponent = 1 };
      { g_index = 1; g_exponent = 1 };
      { g_index = 1; g_exponent = 1 };
    ] in
    assert_eq "value" (Some expected) v);

  test "inverse generator s2^-1" (fun () ->
    let v = run_and_lookup "def g = braid[s2^-1]" "g" in
    assert_eq "value" (Some (VBraid [{ g_index = 2; g_exponent = -1 }])) v)

(* ================================================================== *)
(*  3. Braid composition                                               *)
(* ================================================================== *)

let test_composition () =
  Printf.printf "\n--- 3. Braid composition ---\n";

  test "compose two braids" (fun () ->
    let v = run_and_lookup
      "def c = braid[s1] . braid[s2]" "c" in
    let expected = VBraid [
      { g_index = 1; g_exponent = 1 };
      { g_index = 2; g_exponent = 1 };
    ] in
    assert_eq "value" (Some expected) v);

  test "compose with identity left" (fun () ->
    let v = run_and_lookup
      "def c = identity . braid[s1]" "c" in
    assert_eq "value" (Some (VBraid [{ g_index = 1; g_exponent = 1 }])) v);

  test "compose with identity right" (fun () ->
    let v = run_and_lookup
      "def c = braid[s1] . identity" "c" in
    assert_eq "value" (Some (VBraid [{ g_index = 1; g_exponent = 1 }])) v)

(* ================================================================== *)
(*  4. Simplify                                                        *)
(* ================================================================== *)

let test_simplify () =
  Printf.printf "\n--- 4. Simplify ---\n";

  test "s1.s1^-1 simplifies to identity" (fun () ->
    let v = run_and_lookup
      "def s = simplify(braid[s1, s1^-1])" "s" in
    assert_eq "value" (Some (VBraid [])) v);

  test "s1^-1.s1 simplifies to identity" (fun () ->
    let v = run_and_lookup
      "def s = simplify(braid[s1^-1, s1])" "s" in
    assert_eq "value" (Some (VBraid [])) v);

  test "distinct generators not cancelled" (fun () ->
    let v = run_and_lookup
      "def s = simplify(braid[s1, s2])" "s" in
    let expected = VBraid [
      { g_index = 1; g_exponent = 1 };
      { g_index = 2; g_exponent = 1 };
    ] in
    assert_eq "value" (Some expected) v)

(* ================================================================== *)
(*  5. Mirror and reverse                                              *)
(* ================================================================== *)

let test_mirror_reverse () =
  Printf.printf "\n--- 5. Mirror and reverse ---\n";

  test "mirror negates exponents" (fun () ->
    let v = run_and_lookup
      "def m = mirror(braid[s1])" "m" in
    assert_eq "value" (Some (VBraid [{ g_index = 1; g_exponent = -1 }])) v);

  test "mirror of identity is identity" (fun () ->
    let v = run_and_lookup
      "def m = mirror(identity)" "m" in
    assert_eq "value" (Some (VBraid [])) v);

  test "reverse reverses and negates" (fun () ->
    let v = run_and_lookup
      "def r = reverse(braid[s1, s2])" "r" in
    let expected = VBraid [
      { g_index = 2; g_exponent = -1 };
      { g_index = 1; g_exponent = -1 };
    ] in
    assert_eq "value" (Some expected) v)

(* ================================================================== *)
(*  6. Close                                                           *)
(* ================================================================== *)

let test_close () =
  Printf.printf "\n--- 6. Close ---\n";

  test "close produces a tangle" (fun () ->
    let result = run_pipeline "def k = close(braid[s1])" in
    match env_lookup result.eval_env "k" with
    | Some (VTangle t) ->
      assert_true "closed flag" t.tv_closed;
      assert_eq "word" [{ g_index = 1; g_exponent = 1 }] t.tv_word
    | _ -> failwith "expected VTangle");

  test "close identity produces empty tangle" (fun () ->
    let result = run_pipeline "def k = close(identity)" in
    match env_lookup result.eval_env "k" with
    | Some (VTangle t) ->
      assert_true "closed flag" t.tv_closed;
      assert_eq "empty word" [] t.tv_word
    | _ -> failwith "expected VTangle")

(* ================================================================== *)
(*  7. Pattern matching                                                *)
(* ================================================================== *)

let test_pattern_match () =
  Printf.printf "\n--- 7. Pattern matching ---\n";

  test "match identity pattern" (fun () ->
    let src =
      "def f(w) = match w with \
       | identity => 0 \
       | _ => 1 end\n\
       def r = f(identity)" in
    let v = run_and_lookup src "r" in
    assert_eq "value" (Some (VInt 0)) v);

  test "match non-empty falls to wildcard" (fun () ->
    let src =
      "def f(w) = match w with \
       | identity => 0 \
       | _ => 1 end\n\
       def r = f(braid[s1])" in
    let v = run_and_lookup src "r" in
    assert_eq "value" (Some (VInt 1)) v);

  test "match cons deconstructs braid" (fun () ->
    let src =
      "def head_exp(w) = match w with \
       | s1 . rest => 1 \
       | _ => 0 end\n\
       def r = head_exp(braid[s1, s2])" in
    let v = run_and_lookup src "r" in
    assert_eq "value" (Some (VInt 1)) v)

(* ================================================================== *)
(*  8. Let bindings                                                    *)
(* ================================================================== *)

let test_let_bindings () =
  Printf.printf "\n--- 8. Let bindings ---\n";

  test "simple let" (fun () ->
    let v = run_and_lookup "def r = let x = 10 in x" "r" in
    assert_eq "value" (Some (VInt 10)) v);

  test "nested let addition" (fun () ->
    let v = run_and_lookup
      "def r = let a = 3 in let b = 4 in a + b" "r" in
    assert_eq "value" (Some (VInt 7)) v);

  test "let with braid" (fun () ->
    let v = run_and_lookup
      "def r = let w = braid[s1] in w . w" "r" in
    let expected = VBraid [
      { g_index = 1; g_exponent = 1 };
      { g_index = 1; g_exponent = 1 };
    ] in
    assert_eq "value" (Some expected) v)

(* ================================================================== *)
(*  9. Function definition and application                            *)
(* ================================================================== *)

let test_functions () =
  Printf.printf "\n--- 9. Function definition and application ---\n";

  test "identity function" (fun () ->
    let v = run_and_lookup
      "def id(x) = x\ndef r = id(42)" "r" in
    assert_eq "value" (Some (VInt 42)) v);

  test "double compose function" (fun () ->
    let v = run_and_lookup
      "def dup(w) = w . w\ndef r = dup(braid[s1])" "r" in
    let expected = VBraid [
      { g_index = 1; g_exponent = 1 };
      { g_index = 1; g_exponent = 1 };
    ] in
    assert_eq "value" (Some expected) v);

  test "add function" (fun () ->
    let v = run_and_lookup
      "def add(a, b) = a + b\ndef r = add(10, 32)" "r" in
    assert_eq "value" (Some (VInt 42)) v)

(* ================================================================== *)
(*  10. Arithmetic operators                                           *)
(* ================================================================== *)

let test_arithmetic () =
  Printf.printf "\n--- 10. Arithmetic ---\n";

  test "addition" (fun () ->
    let v = run_and_lookup "def r = 3 + 4" "r" in
    assert_eq "value" (Some (VInt 7)) v);

  test "subtraction" (fun () ->
    let v = run_and_lookup "def r = 10 - 3" "r" in
    assert_eq "value" (Some (VInt 7)) v);

  test "multiplication" (fun () ->
    let v = run_and_lookup "def r = 6 * 7" "r" in
    assert_eq "value" (Some (VInt 42)) v);

  test "integer division" (fun () ->
    let v = run_and_lookup "def r = 10 / 3" "r" in
    assert_eq "value" (Some (VInt 3)) v);

  test "unary negation" (fun () ->
    let v = run_and_lookup "def r = -5" "r" in
    assert_eq "value" (Some (VInt (-5))) v)

(* ================================================================== *)
(*  11. Equality and isotopy                                           *)
(* ================================================================== *)

let test_equality () =
  Printf.printf "\n--- 11. Equality and isotopy ---\n";

  test "integer equality true" (fun () ->
    let v = run_and_lookup "def r = 42 == 42" "r" in
    assert_eq "value" (Some (VBool true)) v);

  test "integer equality false" (fun () ->
    let v = run_and_lookup "def r = 1 == 2" "r" in
    assert_eq "value" (Some (VBool false)) v);

  test "braid equality true" (fun () ->
    let v = run_and_lookup
      "def r = braid[s1] == braid[s1]" "r" in
    assert_eq "value" (Some (VBool true)) v);

  test "isotopy after cancellation" (fun () ->
    let v = run_and_lookup
      "def r = braid[s1, s1^-1] ~ identity" "r" in
    assert_eq "value" (Some (VBool true)) v)

(* ================================================================== *)
(*  12. Compute statements                                             *)
(* ================================================================== *)

let test_compute () =
  Printf.printf "\n--- 12. Compute statements ---\n";

  test "writhe of trefoil is 3" (fun () ->
    let result = run_pipeline
      "def trefoil = braid[s1, s1, s1]\ncompute writhe(trefoil)" in
    assert_true "writhe output"
      (List.exists (fun s -> s = "writhe = 3") result.eval_outputs));

  test "writhe of identity is 0" (fun () ->
    let result = run_pipeline "compute writhe(identity)" in
    assert_true "writhe 0 output"
      (List.exists (fun s -> s = "writhe = 0") result.eval_outputs));

  test "jones computation produces output" (fun () ->
    let result = run_pipeline "compute jones(identity)" in
    assert_true "jones produces output"
      (List.length result.eval_outputs > 0))

(* ================================================================== *)
(*  13. Assertions                                                     *)
(* ================================================================== *)

let test_assertions () =
  Printf.printf "\n--- 13. Assertions ---\n";

  test "assert true succeeds" (fun () ->
    let result = run_pipeline "assert true" in
    assert_true "assertion passed output"
      (List.exists (fun s -> s = "assertion passed") result.eval_outputs));

  test "assert equality succeeds" (fun () ->
    let result = run_pipeline
      "def x = 42\nassert x == 42" in
    assert_true "assertion passed"
      (List.exists (fun s -> s = "assertion passed") result.eval_outputs));

  test "assert false raises eval error" (fun () ->
    try
      let _ = run_pipeline "assert false" in
      failwith "expected Eval_error"
    with Eval_error _ -> ())

(* ================================================================== *)
(*  14. Multi-statement programs                                       *)
(* ================================================================== *)

let test_multi_statement () =
  Printf.printf "\n--- 14. Multi-statement programs ---\n";

  test "two definitions both accessible" (fun () ->
    let src = "def a = 10\ndef b = 20" in
    let result = run_pipeline src in
    assert_eq "a" (Some (VInt 10)) (env_lookup result.eval_env "a");
    assert_eq "b" (Some (VInt 20)) (env_lookup result.eval_env "b"));

  test "definition references earlier definition" (fun () ->
    let src = "def x = 5\ndef y = x + 1" in
    let v = run_and_lookup src "y" in
    assert_eq "y" (Some (VInt 6)) v);

  test "full braid program" (fun () ->
    let src =
      "def trefoil = braid[s1, s1, s1]\n\
       def mirror_trefoil = mirror(trefoil)\n\
       assert trefoil ~ trefoil\n\
       compute writhe(trefoil)" in
    let result = run_pipeline src in
    assert_true "outputs not empty" (List.length result.eval_outputs > 0))

(* ================================================================== *)
(*  15. Pipeline operator                                              *)
(* ================================================================== *)

let test_pipeline_op () =
  Printf.printf "\n--- 15. Pipeline operator ---\n";

  test "pipeline composes braids" (fun () ->
    let v = run_and_lookup
      "def r = braid[s1] >> braid[s2]" "r" in
    let expected = VBraid [
      { g_index = 1; g_exponent = 1 };
      { g_index = 2; g_exponent = 1 };
    ] in
    assert_eq "value" (Some expected) v);

  test "pipeline chain three stages" (fun () ->
    let v = run_and_lookup
      "def r = braid[s1] >> braid[s2] >> braid[s1]" "r" in
    let expected = VBraid [
      { g_index = 1; g_exponent = 1 };
      { g_index = 2; g_exponent = 1 };
      { g_index = 1; g_exponent = 1 };
    ] in
    assert_eq "value" (Some expected) v)

(* ================================================================== *)
(*  Entry point                                                        *)
(* ================================================================== *)

let () =
  Printf.printf "=== TANGLE E2E Test Suite ===\n";
  test_simple_defs ();
  test_braid_literals ();
  test_composition ();
  test_simplify ();
  test_mirror_reverse ();
  test_close ();
  test_pattern_match ();
  test_let_bindings ();
  test_functions ();
  test_arithmetic ();
  test_equality ();
  test_compute ();
  test_assertions ();
  test_multi_statement ();
  test_pipeline_op ();
  Printf.printf "\n=== Results: %d/%d passed" !passed !total;
  if !failed > 0 then
    Printf.printf ", %d FAILED" !failed;
  Printf.printf " ===\n";
  if !failed > 0 then exit 1
