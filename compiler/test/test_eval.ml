(* SPDX-License-Identifier: MPL-2.0 *)
(* test_eval.ml — Test suite for the TANGLE interpreter.
 *
 * Tests cover evaluation of:
 *   1.  Braid literals (identity, trefoil, figure-eight)
 *   2.  Composition and tensor
 *   3.  Close, mirror, reverse
 *   4.  Simplify (Reidemeister cancellation)
 *   5.  Pattern matching on braid words
 *   6.  Let bindings
 *   7.  Function definitions and calls
 *   8.  Pipeline operator
 *   9.  Compute invariants
 *  10.  Arithmetic and equality operators
 *  11.  Error cases
 *)

open Tangle.Ast
open Tangle.Eval

(* ================================================================== *)
(*  Test harness                                                       *)
(* ================================================================== *)

let passed = ref 0
let failed = ref 0
let total  = ref 0

(** Run a named test.  Catches exceptions and reports pass/fail. *)
let test (name : string) (f : unit -> bool) : unit =
  incr total;
  try
    if f () then begin
      incr passed;
      Printf.printf "  PASS  %s\n" name
    end else begin
      incr failed;
      Printf.printf "  FAIL  %s\n" name
    end
  with
  | Eval_error msg ->
    incr failed;
    Printf.printf "  FAIL  %s (Eval_error: %s)\n" name msg
  | exn ->
    incr failed;
    Printf.printf "  FAIL  %s (Exception: %s)\n" name (Printexc.to_string exn)

(** Helper: make a generator with index i and exponent e. *)
let gen i e = { gen_index = i; gen_exponent = e }

(** Helper: make a positive generator at index i (sigma_i). *)
let sigma i = gen i 1

(** Helper: make an inverse generator at index i (sigma_i^{-1}). *)
let sigma_inv i = gen i (-1)

(** Helper: make a runtime generator for comparison. *)
let rgen i e = { g_index = i; g_exponent = e }

(** Helper: make a simple value definition statement. *)
let def_val name body =
  Definition { def_name = name; def_params = []; def_body = body; def_line = 0 }

(** Helper: make a function definition statement. *)
let def_fun name params body =
  Definition { def_name = name; def_params = params; def_body = body; def_line = 0 }

(** Evaluate an expression in an empty environment. *)
let eval e = eval_expr_in_env [] e

(** Evaluate an expression in the given environment. *)
let _eval_in env e = eval_expr_in_env env e

(* ================================================================== *)
(*  1. Braid literals                                                  *)
(* ================================================================== *)

let test_braid_literals () =
  Printf.printf "\n=== Braid Literals ===\n";

  (* Identity: braid[] / identity keyword *)
  test "Identity keyword" (fun () ->
    eval Identity = VBraid []);

  test "Empty braid literal" (fun () ->
    eval (BraidLit []) = VBraid []);

  (* Single generator *)
  test "Single generator s1" (fun () ->
    eval (BraidLit [sigma 1]) = VBraid [rgen 1 1]);

  (* Inverse generator *)
  test "Inverse generator s1^-1" (fun () ->
    eval (BraidLit [sigma_inv 1]) = VBraid [rgen 1 (-1)]);

  (* Trefoil: s1 . s1 . s1 (as braid literal) *)
  test "Trefoil braid literal" (fun () ->
    eval (BraidLit [sigma 1; sigma 1; sigma 1])
      = VBraid [rgen 1 1; rgen 1 1; rgen 1 1]);

  (* Figure-eight: s1 s2^-1 s1 s2^-1 *)
  test "Figure-eight braid literal" (fun () ->
    let gens = [sigma 1; sigma_inv 2; sigma 1; sigma_inv 2] in
    eval (BraidLit gens)
      = VBraid [rgen 1 1; rgen 2 (-1); rgen 1 1; rgen 2 (-1)])

(* ================================================================== *)
(*  2. Composition and tensor                                          *)
(* ================================================================== *)

let test_composition () =
  Printf.printf "\n=== Composition ===\n";

  (* Compose two braid words: concatenate generators *)
  test "Compose braids" (fun () ->
    let e = BinOp (Compose, BraidLit [sigma 1], BraidLit [sigma 2]) in
    eval e = VBraid [rgen 1 1; rgen 2 1]);

  (* Compose identity with a braid *)
  test "Compose identity left" (fun () ->
    let e = BinOp (Compose, Identity, BraidLit [sigma 1]) in
    eval e = VBraid [rgen 1 1]);

  (* Compose a braid with identity *)
  test "Compose identity right" (fun () ->
    let e = BinOp (Compose, BraidLit [sigma 1], Identity) in
    eval e = VBraid [rgen 1 1]);

  (* Compose identity with identity *)
  test "Compose identity identity" (fun () ->
    let e = BinOp (Compose, Identity, Identity) in
    eval e = VBraid [])

let test_tensor () =
  Printf.printf "\n=== Tensor ===\n";

  (* Tensor two braids: offset right indices by left width *)
  test "Tensor braids" (fun () ->
    (* s1 | s1 -> s1, s3  (width of left = 2, so right s1 becomes s3) *)
    let e = BinOp (Tensor, BraidLit [sigma 1], BraidLit [sigma 1]) in
    eval e = VBraid [rgen 1 1; rgen 3 1]);

  (* Tensor identity with braid *)
  test "Tensor identity left" (fun () ->
    let e = BinOp (Tensor, Identity, BraidLit [sigma 1]) in
    eval e = VBraid [rgen 1 1]);

  (* Tensor braid with identity *)
  test "Tensor braid with identity" (fun () ->
    let e = BinOp (Tensor, BraidLit [sigma 1], Identity) in
    eval e = VBraid [rgen 1 1]);

  (* Tensor with different widths *)
  test "Tensor different widths" (fun () ->
    (* s2 | s1 -> s2, s4  (width of left = 3, so right s1 becomes s4) *)
    let e = BinOp (Tensor, BraidLit [sigma 2], BraidLit [sigma 1]) in
    eval e = VBraid [rgen 2 1; rgen 4 1])

(* ================================================================== *)
(*  3. Close, mirror, reverse                                          *)
(* ================================================================== *)

let test_close () =
  Printf.printf "\n=== Close ===\n";

  (* Close a braid word produces a tangle *)
  test "Close braid" (fun () ->
    let v = eval (Close (BraidLit [sigma 1])) in
    match v with
    | VTangle { tv_word = [g]; tv_closed = true } ->
      g = rgen 1 1
    | _ -> false);

  (* Close identity produces empty tangle *)
  test "Close identity" (fun () ->
    let v = eval (Close Identity) in
    match v with
    | VTangle { tv_word = []; tv_closed = true } -> true
    | _ -> false)

let test_mirror () =
  Printf.printf "\n=== Mirror ===\n";

  (* Mirror negates exponents *)
  test "Mirror braid" (fun () ->
    eval (Mirror (BraidLit [sigma 1; sigma_inv 2]))
      = VBraid [rgen 1 (-1); rgen 2 1]);

  (* Mirror of identity is identity *)
  test "Mirror identity" (fun () ->
    eval (Mirror Identity) = VBraid []);

  (* Mirror of a tangle *)
  test "Mirror tangle" (fun () ->
    let v = eval (Mirror (Close (BraidLit [sigma 1]))) in
    match v with
    | VTangle { tv_word = [g]; _ } -> g = rgen 1 (-1)
    | _ -> false)

let test_reverse () =
  Printf.printf "\n=== Reverse ===\n";

  (* Reverse reverses list and negates exponents (produces inverse) *)
  test "Reverse braid" (fun () ->
    eval (Reverse (BraidLit [sigma 1; sigma 2]))
      = VBraid [rgen 2 (-1); rgen 1 (-1)]);

  (* Reverse identity is identity *)
  test "Reverse identity" (fun () ->
    eval (Reverse Identity) = VBraid []);

  (* Reverse single generator *)
  test "Reverse single" (fun () ->
    eval (Reverse (BraidLit [sigma 1]))
      = VBraid [rgen 1 (-1)])

(* ================================================================== *)
(*  4. Simplify (Reidemeister cancellation)                            *)
(* ================================================================== *)

let test_simplify () =
  Printf.printf "\n=== Simplify ===\n";

  (* s1 . s1^-1 cancels to identity *)
  test "Simplify s1.s1^-1 -> identity" (fun () ->
    eval (Simplify (BraidLit [sigma 1; sigma_inv 1]))
      = VBraid []);

  (* s1^-1 . s1 also cancels *)
  test "Simplify s1^-1.s1 -> identity" (fun () ->
    eval (Simplify (BraidLit [sigma_inv 1; sigma 1]))
      = VBraid []);

  (* Non-adjacent same-index generators don't cancel *)
  test "Simplify s1.s2.s1^-1 (no cancel)" (fun () ->
    eval (Simplify (BraidLit [sigma 1; sigma 2; sigma_inv 1]))
      = VBraid [rgen 1 1; rgen 2 1; rgen 1 (-1)]);

  (* Different indices don't cancel *)
  test "Simplify s1.s2^-1 (no cancel)" (fun () ->
    eval (Simplify (BraidLit [sigma 1; sigma_inv 2]))
      = VBraid [rgen 1 1; rgen 2 (-1)]);

  (* Chain cancellation: s1 . s2 . s2^-1 . s1^-1 -> identity *)
  test "Simplify chain cancellation" (fun () ->
    let gens = [sigma 1; sigma 2; sigma_inv 2; sigma_inv 1] in
    eval (Simplify (BraidLit gens)) = VBraid []);

  (* Already simplified stays the same *)
  test "Simplify already simplified" (fun () ->
    eval (Simplify (BraidLit [sigma 1; sigma 2]))
      = VBraid [rgen 1 1; rgen 2 1]);

  (* Simplify identity *)
  test "Simplify identity" (fun () ->
    eval (Simplify Identity) = VBraid []);

  (* Simplify tangle *)
  test "Simplify tangle" (fun () ->
    let v = eval (Simplify (Close (BraidLit [sigma 1; sigma_inv 1]))) in
    match v with
    | VTangle { tv_word = []; _ } -> true
    | _ -> false)

(* ================================================================== *)
(*  5. Pattern matching on braid words                                 *)
(* ================================================================== *)

let test_pattern_matching () =
  Printf.printf "\n=== Pattern Matching ===\n";

  (* Match identity pattern against empty braid *)
  test "Match identity pattern" (fun () ->
    let arm = { arm_pattern = PatIdentity; arm_body = IntLit 42 } in
    eval (Match (Identity, [arm])) = VInt 42);

  (* Match variable pattern captures the value *)
  test "Match variable pattern" (fun () ->
    let arm = { arm_pattern = PatVar "w"; arm_body = Var "w" } in
    eval (Match (BraidLit [sigma 1], [arm]))
      = VBraid [rgen 1 1]);

  (* Match wildcard pattern *)
  test "Match wildcard pattern" (fun () ->
    let arm = { arm_pattern = PatWildcard; arm_body = IntLit 99 } in
    eval (Match (BraidLit [sigma 1; sigma 2], [arm])) = VInt 99);

  (* Match cons pattern: decompose braid word *)
  test "Match cons pattern" (fun () ->
    let gpat = { gpat_index = 1; gpat_exponent = 1 } in
    let arm = {
      arm_pattern = PatCons (gpat, PatVar "rest");
      arm_body = Var "rest";
    } in
    eval (Match (BraidLit [sigma 1; sigma 2], [arm]))
      = VBraid [rgen 2 1]);

  (* Match cons + identity: decompose to single generator *)
  test "Match cons then identity" (fun () ->
    let gpat = { gpat_index = 1; gpat_exponent = 1 } in
    let arm = {
      arm_pattern = PatCons (gpat, PatIdentity);
      arm_body = IntLit 1;
    } in
    let fallback = { arm_pattern = PatWildcard; arm_body = IntLit 0 } in
    (* braid[s1] matches: s1 . identity *)
    eval (Match (BraidLit [sigma 1], [arm; fallback])) = VInt 1);

  (* Multiple arms: first match wins *)
  test "Match first arm wins" (fun () ->
    let arm1 = { arm_pattern = PatIdentity; arm_body = IntLit 0 } in
    let arm2 = { arm_pattern = PatWildcard; arm_body = IntLit 1 } in
    (* identity matches first arm *)
    eval (Match (Identity, [arm1; arm2])) = VInt 0);

  (* Multiple arms: fallback to second *)
  test "Match fallback to second arm" (fun () ->
    let arm1 = { arm_pattern = PatIdentity; arm_body = IntLit 0 } in
    let arm2 = { arm_pattern = PatWildcard; arm_body = IntLit 1 } in
    (* non-empty braid doesn't match identity, falls through to wildcard *)
    eval (Match (BraidLit [sigma 1], [arm1; arm2])) = VInt 1);

  (* No pattern matches -> error *)
  test "Match no pattern matches" (fun () ->
    let arm = { arm_pattern = PatIdentity; arm_body = IntLit 0 } in
    try
      let _ = eval (Match (BraidLit [sigma 1], [arm])) in
      false
    with Eval_error _ -> true)

(* ================================================================== *)
(*  6. Let bindings                                                    *)
(* ================================================================== *)

let test_let_bindings () =
  Printf.printf "\n=== Let Bindings ===\n";

  (* Basic let binding *)
  test "Let basic" (fun () ->
    eval (Let ("x", IntLit 42, Var "x")) = VInt 42);

  (* Let with braid value *)
  test "Let braid" (fun () ->
    eval (Let ("w", BraidLit [sigma 1], Var "w"))
      = VBraid [rgen 1 1]);

  (* Nested let *)
  test "Let nested" (fun () ->
    eval (Let ("x", IntLit 1,
            Let ("y", IntLit 2,
              BinOp (Add, Var "x", Var "y"))))
      = VInt 3);

  (* Let shadowing *)
  test "Let shadowing" (fun () ->
    eval (Let ("x", IntLit 1,
            Let ("x", IntLit 2,
              Var "x")))
      = VInt 2);

  (* Let with expression body *)
  test "Let expression body" (fun () ->
    eval (Let ("w", BraidLit [sigma 1],
            BinOp (Compose, Var "w", Var "w")))
      = VBraid [rgen 1 1; rgen 1 1])

(* ================================================================== *)
(*  7. Function definitions and calls                                  *)
(* ================================================================== *)

let test_functions () =
  Printf.printf "\n=== Functions ===\n";

  (* Define and call a simple function *)
  test "Function define and call" (fun () ->
    let prog = [
      def_fun "double" ["x"] (BinOp (Compose, Var "x", Var "x"));
      def_val "result" (Call ("double", [BraidLit [sigma 1]]));
    ] in
    let r = eval_program prog in
    match env_lookup r.eval_env "result" with
    | Some (VBraid gs) -> gs = [rgen 1 1; rgen 1 1]
    | _ -> false);

  (* Function with multiple parameters *)
  test "Function multiple params" (fun () ->
    let prog = [
      def_fun "add" ["a"; "b"] (BinOp (Add, Var "a", Var "b"));
      def_val "result" (Call ("add", [IntLit 3; IntLit 4]));
    ] in
    let r = eval_program prog in
    match env_lookup r.eval_env "result" with
    | Some (VInt 7) -> true
    | _ -> false);

  (* Recursive function: count generators *)
  test "Recursive function" (fun () ->
    let prog = [
      def_fun "length" ["w"]
        (Match (Var "w", [
          { arm_pattern = PatIdentity; arm_body = IntLit 0 };
          { arm_pattern = PatCons (
              { gpat_index = 1; gpat_exponent = 1 },
              PatVar "rest");
            arm_body = BinOp (Add, IntLit 1, Call ("length", [Var "rest"])) };
          { arm_pattern = PatWildcard; arm_body = IntLit 0 };
        ]));
      def_val "result" (Call ("length", [BraidLit [sigma 1; sigma 1; sigma 1]]));
    ] in
    let r = eval_program prog in
    match env_lookup r.eval_env "result" with
    | Some (VInt 3) -> true
    | _ -> false);

  (* Wrong arity -> error *)
  test "Function wrong arity" (fun () ->
    let prog = [
      def_fun "f" ["x"] (Var "x");
      def_val "result" (Call ("f", [IntLit 1; IntLit 2]));
    ] in
    try
      let _ = eval_program prog in
      false
    with Eval_error _ -> true);

  (* Unbound function -> error *)
  test "Unbound function" (fun () ->
    try
      let _ = eval (Call ("nonexistent", [IntLit 1])) in
      false
    with Eval_error _ -> true)

(* ================================================================== *)
(*  8. Pipeline operator                                               *)
(* ================================================================== *)

let test_pipeline () =
  Printf.printf "\n=== Pipeline ===\n";

  (* Pipeline is composition *)
  test "Pipeline composes" (fun () ->
    let e = Pipeline (BraidLit [sigma 1], BraidLit [sigma 2]) in
    eval e = VBraid [rgen 1 1; rgen 2 1]);

  (* Pipeline chain *)
  test "Pipeline chain" (fun () ->
    let e = Pipeline (
      Pipeline (BraidLit [sigma 1], BraidLit [sigma 2]),
      BraidLit [sigma 1]) in
    eval e = VBraid [rgen 1 1; rgen 2 1; rgen 1 1])

(* ================================================================== *)
(*  9. Compute invariants                                              *)
(* ================================================================== *)

let test_compute () =
  Printf.printf "\n=== Compute Invariants ===\n";

  (* Compute writhe of trefoil (writhe = 3) *)
  test "Compute writhe" (fun () ->
    let prog = [
      def_val "trefoil" (BraidLit [sigma 1; sigma 1; sigma 1]);
      Computation { comp_invariant = "writhe"; comp_arg = Var "trefoil" };
    ] in
    let r = eval_program prog in
    List.exists (fun s -> s = "writhe = 3") r.eval_outputs);

  (* Compute writhe of identity (writhe = 0) *)
  test "Compute writhe identity" (fun () ->
    let prog = [
      Computation { comp_invariant = "writhe"; comp_arg = Identity };
    ] in
    let r = eval_program prog in
    List.exists (fun s -> s = "writhe = 0") r.eval_outputs);

  (* Compute jones placeholder *)
  test "Compute jones" (fun () ->
    let prog = [
      def_val "trefoil" (BraidLit [sigma 1; sigma 1; sigma 1]);
      Computation { comp_invariant = "jones"; comp_arg = Var "trefoil" };
    ] in
    let r = eval_program prog in
    List.length r.eval_outputs > 0 &&
    let output = List.nth r.eval_outputs 0 in
    String.length output > 0);

  (* Compute alexander placeholder *)
  test "Compute alexander" (fun () ->
    let prog = [
      Computation { comp_invariant = "alexander"; comp_arg = BraidLit [sigma 1] };
    ] in
    let r = eval_program prog in
    List.length r.eval_outputs > 0);

  (* Compute homfly placeholder *)
  test "Compute homfly" (fun () ->
    let prog = [
      Computation { comp_invariant = "homfly"; comp_arg = BraidLit [sigma 1] };
    ] in
    let r = eval_program prog in
    List.length r.eval_outputs > 0);

  (* Compute kauffman placeholder *)
  test "Compute kauffman" (fun () ->
    let prog = [
      Computation { comp_invariant = "kauffman"; comp_arg = BraidLit [sigma 1] };
    ] in
    let r = eval_program prog in
    List.length r.eval_outputs > 0);

  (* Compute linking *)
  test "Compute linking" (fun () ->
    let prog = [
      Computation { comp_invariant = "linking"; comp_arg = BraidLit [sigma 1] };
    ] in
    let r = eval_program prog in
    List.length r.eval_outputs > 0);

  (* Jones polynomial of identity = 1 *)
  test "Jones of identity" (fun () ->
    let prog = [
      Computation { comp_invariant = "jones"; comp_arg = Identity };
    ] in
    let r = eval_program prog in
    List.exists (fun s -> s = "jones = 1") r.eval_outputs)

(* ================================================================== *)
(*  10. Arithmetic and equality operators                              *)
(* ================================================================== *)

let test_arithmetic () =
  Printf.printf "\n=== Arithmetic ===\n";

  test "Add integers" (fun () ->
    eval (BinOp (Add, IntLit 3, IntLit 4)) = VInt 7);

  test "Sub integers" (fun () ->
    eval (BinOp (Sub, IntLit 10, IntLit 3)) = VInt 7);

  test "Mul integers" (fun () ->
    eval (BinOp (Mul, IntLit 3, IntLit 4)) = VInt 12);

  test "Div integers" (fun () ->
    eval (BinOp (Div, IntLit 10, IntLit 3)) = VInt 3);

  test "Add floats" (fun () ->
    eval (BinOp (Add, FloatLit 1.5, FloatLit 2.5)) = VFloat 4.0);

  test "Negate integer" (fun () ->
    eval (UnaryOp (Neg, IntLit 42)) = VInt (-42));

  test "Negate float" (fun () ->
    eval (UnaryOp (Neg, FloatLit 3.14)) = VFloat (-3.14));

  test "Logical not" (fun () ->
    eval (UnaryOp (Not, BoolLit true)) = VBool false);

  test "Division by zero" (fun () ->
    try
      let _ = eval (BinOp (Div, IntLit 1, IntLit 0)) in
      false
    with Eval_error _ -> true)

let test_equality () =
  Printf.printf "\n=== Equality ===\n";

  test "Int equality true" (fun () ->
    eval (BinOp (Eq, IntLit 42, IntLit 42)) = VBool true);

  test "Int equality false" (fun () ->
    eval (BinOp (Eq, IntLit 1, IntLit 2)) = VBool false);

  test "String equality" (fun () ->
    eval (BinOp (Eq, StringLit "hello", StringLit "hello")) = VBool true);

  test "Bool equality" (fun () ->
    eval (BinOp (Eq, BoolLit true, BoolLit true)) = VBool true);

  test "Braid equality true" (fun () ->
    eval (BinOp (Eq, BraidLit [sigma 1], BraidLit [sigma 1])) = VBool true);

  test "Braid equality false" (fun () ->
    eval (BinOp (Eq, BraidLit [sigma 1], BraidLit [sigma 2])) = VBool false);

  (* Isotopy: simplified comparison *)
  test "Isotopy true (cancel)" (fun () ->
    (* s1 . s1^-1 ~ identity *)
    eval (BinOp (Isotopy,
      BraidLit [sigma 1; sigma_inv 1],
      Identity))
      = VBool true);

  test "Isotopy false" (fun () ->
    eval (BinOp (Isotopy,
      BraidLit [sigma 1],
      BraidLit [sigma 2]))
      = VBool false)

(* ================================================================== *)
(*  11. Error cases                                                    *)
(* ================================================================== *)

let test_errors () =
  Printf.printf "\n=== Error Cases ===\n";

  test "Unbound variable" (fun () ->
    try
      let _ = eval (Var "nonexistent") in
      false
    with Eval_error _ -> true);

  test "Assertion failure" (fun () ->
    let prog = [Assertion (BoolLit false)] in
    try
      let _ = eval_program prog in
      false
    with Eval_error _ -> true);

  test "Assertion success" (fun () ->
    let prog = [Assertion (BoolLit true)] in
    let r = eval_program prog in
    List.exists (fun s -> s = "assertion passed") r.eval_outputs);

  test "Cannot compose num with braid" (fun () ->
    try
      let _ = eval (BinOp (Compose, IntLit 1, BraidLit [sigma 1])) in
      false
    with Eval_error _ -> true);

  test "Cannot negate braid" (fun () ->
    try
      let _ = eval (UnaryOp (Neg, BraidLit [sigma 1])) in
      false
    with Eval_error _ -> true);

  test "Cannot reverse non-braid" (fun () ->
    try
      let _ = eval (Reverse (IntLit 42)) in
      false
    with Eval_error _ -> true)

(* ================================================================== *)
(*  12. Statement evaluation (program level)                           *)
(* ================================================================== *)

let test_program () =
  Printf.printf "\n=== Program Evaluation ===\n";

  (* Full program with definitions, assertions, computations *)
  test "Full program" (fun () ->
    let prog = [
      def_val "trefoil" (BraidLit [sigma 1; sigma 1; sigma 1]);
      def_val "figure_eight"
        (BraidLit [sigma 1; sigma_inv 2; sigma 1; sigma_inv 2]);
      Assertion (BinOp (Eq,
        BraidLit [sigma 1; sigma 1; sigma 1],
        Var "trefoil"));
      Computation { comp_invariant = "writhe"; comp_arg = Var "trefoil" };
    ] in
    let r = eval_program prog in
    List.length r.eval_outputs = 2);  (* assertion passed + writhe *)

  (* Value definition persists in environment *)
  test "Def persists" (fun () ->
    let prog = [
      def_val "x" (IntLit 42);
      def_val "y" (BinOp (Add, Var "x", IntLit 1));
    ] in
    let r = eval_program prog in
    match env_lookup r.eval_env "y" with
    | Some (VInt 43) -> true
    | _ -> false);

  (* Function definition persists *)
  test "Fun def persists" (fun () ->
    let prog = [
      def_fun "id" ["x"] (Var "x");
      def_val "result" (Call ("id", [IntLit 99]));
    ] in
    let r = eval_program prog in
    match env_lookup r.eval_env "result" with
    | Some (VInt 99) -> true
    | _ -> false);

  (* StmtError is tolerated *)
  test "StmtError tolerated" (fun () ->
    let prog = [StmtError; def_val "x" (IntLit 1)] in
    let r = eval_program prog in
    match env_lookup r.eval_env "x" with
    | Some (VInt 1) -> true
    | _ -> false)

(* ================================================================== *)
(*  13. Value display                                                  *)
(* ================================================================== *)

let test_pp_value () =
  Printf.printf "\n=== Value Display ===\n";

  test "pp_value int" (fun () ->
    pp_value (VInt 42) = "42");

  test "pp_value float" (fun () ->
    pp_value (VFloat 3.14) = "3.14");

  test "pp_value bool true" (fun () ->
    pp_value (VBool true) = "true");

  test "pp_value bool false" (fun () ->
    pp_value (VBool false) = "false");

  test "pp_value string" (fun () ->
    pp_value (VString "hello") = "\"hello\"");

  test "pp_value empty braid" (fun () ->
    pp_value (VBraid []) = "braid[]");

  test "pp_value braid" (fun () ->
    pp_value (VBraid [rgen 1 1; rgen 2 (-1)]) = "braid[s1, s2^-1]");

  test "pp_value function" (fun () ->
    pp_value (VFun (["x"], Identity, [])) = "<function>");

  test "pp_value unit" (fun () ->
    pp_value VUnit = "()")

(* ================================================================== *)
(*  Echo / product types (structured loss)                             *)
(* ================================================================== *)

(* Pins the eval-level semantics against the Lean Step relation
   (proofs/Tangle.lean:345-382): lower = result, residue = residue/operand-pair,
   echoClose residue = braid + result = identity, echoAdd/echoEq residue = the
   operand pair.  Catches residue/result swaps that the parse/pretty round-trip
   corpus cannot. *)
let test_echo_types () =
  Printf.printf "\n=== Echo / product types ===\n";

  (* lower projects to the RESULT (second component) — echoAddNums result is the sum *)
  test "lower (echoAdd 3 4) = 7" (fun () ->
    eval (Lower (EchoAdd (IntLit 3, IntLit 4))) = VInt 7);

  (* residue projects to the RESIDUE (first component) — the retained operand pair.
     This is the arm a residue/result swap would break. *)
  test "residue (echoAdd 3 4) = (3, 4)" (fun () ->
    eval (Residue (EchoAdd (IntLit 3, IntLit 4))) = VPair (VInt 3, VInt 4));

  test "fst (pair 1 \"a\") = 1" (fun () ->
    eval (Fst (Pair (IntLit 1, StringLit "a"))) = VInt 1);

  test "snd (pair 1 \"a\") = \"a\"" (fun () ->
    eval (Snd (Pair (IntLit 1, StringLit "a"))) = VString "a");

  (* echoClose: residue = the braid, result = the identity value (Word[0]) *)
  test "echoClose(braid[s1]) = echoVal (braid[s1]) identity" (fun () ->
    eval (EchoClose (BraidLit [sigma 1])) = VEcho (VBraid [rgen 1 1], VBraid []));

  test "lower (echoClose b) = identity" (fun () ->
    eval (Lower (EchoClose (BraidLit [sigma 1]))) = VBraid []);

  test "residue (echoClose b) = b" (fun () ->
    eval (Residue (EchoClose (BraidLit [sigma 1]))) = VBraid [rgen 1 1]);

  (* echoEq: residue = operand pair, result = the boolean *)
  test "residue (echoEq 1 1) = (1, 1)" (fun () ->
    eval (Residue (EchoEq (IntLit 1, IntLit 1))) = VPair (VInt 1, VInt 1));

  test "lower (echoEq 1 1) = true" (fun () ->
    eval (Lower (EchoEq (IntLit 1, IntLit 1))) = VBool true);

  test "lower (echoEq 1 2) = false" (fun () ->
    eval (Lower (EchoEq (IntLit 1, IntLit 2))) = VBool false)

(* ================================================================== *)
(*  Main: run all test groups                                          *)
(* ================================================================== *)

let () =
  Printf.printf "TANGLE Interpreter Tests\n";
  Printf.printf "========================\n";
  test_braid_literals ();
  test_composition ();
  test_tensor ();
  test_close ();
  test_mirror ();
  test_reverse ();
  test_simplify ();
  test_pattern_matching ();
  test_let_bindings ();
  test_functions ();
  test_pipeline ();
  test_compute ();
  test_arithmetic ();
  test_equality ();
  test_echo_types ();
  test_errors ();
  test_program ();
  test_pp_value ();
  Printf.printf "\n========================\n";
  Printf.printf "Results: %d/%d passed" !passed !total;
  if !failed > 0 then
    Printf.printf " (%d FAILED)" !failed;
  Printf.printf "\n";
  if !failed > 0 then exit 1
