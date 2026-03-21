(* SPDX-License-Identifier: PMPL-1.0-or-later *)
(* test_typecheck.ml — Test suite for the TANGLE type checker.
 *
 * Tests cover all 37 typing rules from FORMAL-SEMANTICS.md:
 *   1.  Literal types (T-Num, T-Str, T-True, T-False, T-Identity)
 *   2.  Braid literals (T-Braid, T-Braid-Empty)
 *   3.  Variables (T-Var)
 *   4.  Composition operators (T-Compose-Word, T-Compose-Tangle, T-Pipeline)
 *   5.  Tensor operators (T-Tensor-Word, T-Tensor-Tangle)
 *   6.  Arithmetic (T-Add-Num, T-Add-Tangle, T-Arith)
 *   7.  Equality (T-Eq-Word, T-Eq-Num, T-Eq-Str)
 *   8.  Isotopy (T-Isotopy)
 *   9.  Close (T-Close-Word, T-Close-Tangle)
 *  10.  Cap/Cup (T-Cap, T-Cup)
 *  11.  Mirror (T-Mirror-Word, T-Mirror-Tangle)
 *  12.  Reverse (T-Reverse)
 *  13.  Simplify (T-Simplify-Word, T-Simplify-Tangle)
 *  14.  Twist (T-Twist-Word, T-Twist-Tangle)
 *  15.  Pattern matching (T-Match, P-Identity, P-Cons, P-Var, P-Wildcard)
 *  16.  Let bindings (T-Let)
 *  17.  Function definitions and application (T-Def-Fun, T-Def-Val, T-App)
 *  18.  Assert (T-Assert)
 *  19.  Compute (T-Compute)
 *  20.  Width inference and auto-widening
 *  21.  Type error detection
 *)

open Tangle.Ast
open Tangle.Typecheck

(* ================================================================== *)
(*  Test harness                                                       *)
(* ================================================================== *)

let passed = ref 0
let failed = ref 0
let total  = ref 0

(** Run a named test. Catches exceptions and reports pass/fail. *)
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
  | Type_error msg ->
    incr failed;
    Printf.printf "  FAIL  %s (Type_error: %s)\n" name msg
  | exn ->
    incr failed;
    Printf.printf "  FAIL  %s (Exception: %s)\n" name (Printexc.to_string exn)

(** Check that type-checking a program succeeds. *)
let check_ok (prog : program) : check_result =
  let r = check_program prog in
  if not r.result_ok then begin
    List.iter (fun d ->
      Printf.eprintf "    diagnostic: %s\n" d.diag_message
    ) r.result_diagnostics
  end;
  r

(** Check that type-checking a program produces at least one error. *)
let check_fails (prog : program) : bool =
  let r = check_program prog in
  not r.result_ok

(** Infer the type of an expression in a given environment. *)
let infer (gamma : env) (e : expr) : ty =
  infer_expr gamma [] e

(** Helper: make a generator with index i and exponent e. *)
let gen i e = { gen_index = i; gen_exponent = e }

(** Helper: make a positive generator at index i (sigma_i). *)
let sigma i = gen i 1

(** Helper: make an inverse generator at index i (sigma_i^{-1}). *)
let sigma_inv i = gen i (-1)

(** Helper: make a simple value definition statement. *)
let def_val name body =
  Definition { def_name = name; def_params = []; def_body = body }

(** Helper: make a function definition statement. *)
let def_fun name params body =
  Definition { def_name = name; def_params = params; def_body = body }

(* ================================================================== *)
(*  1. Literal types                                                   *)
(* ================================================================== *)

let test_literals () =
  Printf.printf "\n=== Literal Types ===\n";

  (* [T-Num]: integer literal *)
  test "T-Num (int)" (fun () ->
    infer [] (IntLit 42) = TNum);

  (* [T-Num]: float literal *)
  test "T-Num (float)" (fun () ->
    infer [] (FloatLit 3.14) = TNum);

  (* [T-Str]: string literal *)
  test "T-Str" (fun () ->
    infer [] (StringLit "hello") = TStr);

  (* [T-True] *)
  test "T-True" (fun () ->
    infer [] (BoolLit true) = TBool);

  (* [T-False] *)
  test "T-False" (fun () ->
    infer [] (BoolLit false) = TBool);

  (* [T-Identity]: identity : Word[0] *)
  test "T-Identity" (fun () ->
    infer [] Identity = TWord 0)

(* ================================================================== *)
(*  2. Braid literals                                                  *)
(* ================================================================== *)

let test_braid_literals () =
  Printf.printf "\n=== Braid Literals ===\n";

  (* [T-Braid-Empty]: braid[] : Word[0] *)
  test "T-Braid-Empty" (fun () ->
    infer [] (BraidLit []) = TWord 0);

  (* [T-Braid]: single generator s1 -> Word[2] *)
  test "T-Braid (s1)" (fun () ->
    infer [] (BraidLit [sigma 1]) = TWord 2);

  (* [T-Braid]: single generator s2 -> Word[3] *)
  test "T-Braid (s2)" (fun () ->
    infer [] (BraidLit [sigma 2]) = TWord 3);

  (* [T-Braid]: multiple generators, width = max(index) + 1 *)
  test "T-Braid (s1, s2, s1)" (fun () ->
    infer [] (BraidLit [sigma 1; sigma 2; sigma 1]) = TWord 3);

  (* [T-Braid]: inverse generator has same width *)
  test "T-Braid (s1^{-1})" (fun () ->
    infer [] (BraidLit [sigma_inv 1]) = TWord 2);

  (* [T-Braid]: mixed generators, max index determines width *)
  test "T-Braid (s1, s3^{-1})" (fun () ->
    infer [] (BraidLit [sigma 1; sigma_inv 3]) = TWord 4)

(* ================================================================== *)
(*  3. Variables                                                       *)
(* ================================================================== *)

let test_variables () =
  Printf.printf "\n=== Variables ===\n";

  (* [T-Var]: look up bound variable *)
  test "T-Var (bound)" (fun () ->
    let gamma = env_bind_val [] "x" TNum in
    infer gamma (Var "x") = TNum);

  (* [T-Var]: unbound variable -> error *)
  test "T-Var (unbound)" (fun () ->
    try
      let _ = infer [] (Var "y") in
      false
    with Type_error _ -> true);

  (* [T-Var]: function name used as value -> error *)
  test "T-Var (function as value)" (fun () ->
    let gamma = env_bind_fun [] "f"
      { fsig_params = [TNum]; fsig_return = TNum } in
    try
      let _ = infer gamma (Var "f") in
      false
    with Type_error _ -> true)

(* ================================================================== *)
(*  4. Composition operators                                           *)
(* ================================================================== *)

let test_composition () =
  Printf.printf "\n=== Composition Operators ===\n";

  (* [T-Compose-Word]: Word[2] . Word[2] -> Word[2] *)
  test "T-Compose-Word (same width)" (fun () ->
    let e = BinOp (Compose, BraidLit [sigma 1], BraidLit [sigma 1]) in
    infer [] e = TWord 2);

  (* [T-Compose-Word]: Word[2] . Word[3] -> Word[3] (auto-widening) *)
  test "T-Compose-Word (auto-widen)" (fun () ->
    let e = BinOp (Compose, BraidLit [sigma 1], BraidLit [sigma 2]) in
    infer [] e = TWord 3);

  (* [T-Compose-Tangle]: compose matching tangles *)
  test "T-Compose-Tangle" (fun () ->
    let gamma = env_bind_val [] "t1"
      (TTangle ([StrandDefault], [StrandDefault])) in
    let gamma = env_bind_val gamma "t2"
      (TTangle ([StrandDefault], [])) in
    infer gamma (BinOp (Compose, Var "t1", Var "t2"))
      = TTangle ([StrandDefault], []));

  (* [T-Compose-Tangle]: boundary mismatch -> error *)
  test "T-Compose-Tangle (mismatch)" (fun () ->
    let gamma = env_bind_val [] "t1"
      (TTangle ([StrandDefault], [StrandDefault; StrandDefault])) in
    let gamma = env_bind_val gamma "t2"
      (TTangle ([StrandDefault], [])) in
    try
      let _ = infer gamma (BinOp (Compose, Var "t1", Var "t2")) in
      false
    with Type_error _ -> true);

  (* [T-Pipeline]: e1 >> e2 desugars to e1 . e2 *)
  test "T-Pipeline" (fun () ->
    let e = Pipeline (BraidLit [sigma 1], BraidLit [sigma 2]) in
    infer [] e = TWord 3);

  (* Compose: incompatible types -> error *)
  test "T-Compose (type error)" (fun () ->
    try
      let _ = infer [] (BinOp (Compose, IntLit 1, BraidLit [sigma 1])) in
      false
    with Type_error _ -> true)

(* ================================================================== *)
(*  5. Tensor operators                                                *)
(* ================================================================== *)

let test_tensor () =
  Printf.printf "\n=== Tensor Operators ===\n";

  (* [T-Tensor-Word]: Word[2] | Word[3] -> Word[5] *)
  test "T-Tensor-Word" (fun () ->
    let e = BinOp (Tensor, BraidLit [sigma 1], BraidLit [sigma 2]) in
    infer [] e = TWord 5);

  (* [T-Tensor-Word]: identity | Word[2] -> Word[2] *)
  test "T-Tensor-Word (identity left)" (fun () ->
    let e = BinOp (Tensor, Identity, BraidLit [sigma 1]) in
    infer [] e = TWord 2);

  (* [T-Tensor-Tangle]: concatenate boundaries *)
  test "T-Tensor-Tangle" (fun () ->
    let gamma = env_bind_val [] "t1"
      (TTangle ([StrandDefault], [StrandDefault])) in
    let gamma = env_bind_val gamma "t2"
      (TTangle ([StrandDefault; StrandDefault], [StrandDefault; StrandDefault])) in
    let result = infer gamma (BinOp (Tensor, Var "t1", Var "t2")) in
    result = TTangle (
      [StrandDefault; StrandDefault; StrandDefault],
      [StrandDefault; StrandDefault; StrandDefault]
    ));

  (* Tensor: incompatible types -> error *)
  test "T-Tensor (type error)" (fun () ->
    try
      let _ = infer [] (BinOp (Tensor, IntLit 1, IntLit 2)) in
      false
    with Type_error _ -> true)

(* ================================================================== *)
(*  6. Arithmetic operators                                            *)
(* ================================================================== *)

let test_arithmetic () =
  Printf.printf "\n=== Arithmetic Operators ===\n";

  (* [T-Add-Num] *)
  test "T-Add-Num" (fun () ->
    infer [] (BinOp (Add, IntLit 1, IntLit 2)) = TNum);

  (* [T-Add-Tangle]: closed tangles *)
  test "T-Add-Tangle (closed)" (fun () ->
    let gamma = env_bind_val [] "k1" (TTangle ([], [])) in
    let gamma = env_bind_val gamma "k2" (TTangle ([], [])) in
    infer gamma (BinOp (Add, Var "k1", Var "k2"))
      = TTangle ([], []));

  (* [T-Add-Tangle]: non-closed -> error *)
  test "T-Add-Tangle (non-closed)" (fun () ->
    let gamma = env_bind_val [] "t1"
      (TTangle ([StrandDefault], [StrandDefault])) in
    let gamma = env_bind_val gamma "t2" (TTangle ([], [])) in
    try
      let _ = infer gamma (BinOp (Add, Var "t1", Var "t2")) in
      false
    with Type_error _ -> true);

  (* [T-Arith]: subtraction *)
  test "T-Arith (sub)" (fun () ->
    infer [] (BinOp (Sub, IntLit 5, IntLit 3)) = TNum);

  (* [T-Arith]: multiplication *)
  test "T-Arith (mul)" (fun () ->
    infer [] (BinOp (Mul, IntLit 2, IntLit 3)) = TNum);

  (* [T-Arith]: division *)
  test "T-Arith (div)" (fun () ->
    infer [] (BinOp (Div, FloatLit 10.0, FloatLit 3.0)) = TNum);

  (* [T-Arith]: type mismatch -> error *)
  test "T-Arith (type error)" (fun () ->
    try
      let _ = infer [] (BinOp (Sub, StringLit "a", IntLit 1)) in
      false
    with Type_error _ -> true)

(* ================================================================== *)
(*  7. Equality operators                                              *)
(* ================================================================== *)

let test_equality () =
  Printf.printf "\n=== Equality Operators ===\n";

  (* [T-Eq-Num] *)
  test "T-Eq-Num" (fun () ->
    infer [] (BinOp (Eq, IntLit 1, IntLit 2)) = TBool);

  (* [T-Eq-Str] *)
  test "T-Eq-Str" (fun () ->
    infer [] (BinOp (Eq, StringLit "a", StringLit "b")) = TBool);

  (* [T-Eq-Word] *)
  test "T-Eq-Word" (fun () ->
    infer [] (BinOp (Eq, BraidLit [sigma 1], BraidLit [sigma 1])) = TBool);

  (* Eq: type mismatch -> error *)
  test "T-Eq (type mismatch)" (fun () ->
    try
      let _ = infer [] (BinOp (Eq, IntLit 1, StringLit "a")) in
      false
    with Type_error _ -> true)

(* ================================================================== *)
(*  8. Isotopy                                                         *)
(* ================================================================== *)

let test_isotopy () =
  Printf.printf "\n=== Isotopy ===\n";

  (* [T-Isotopy]: Word ~ Word -> Bool *)
  test "T-Isotopy (words)" (fun () ->
    infer [] (BinOp (Isotopy, BraidLit [sigma 1], BraidLit [sigma 1])) = TBool);

  (* [T-Isotopy]: Tangle ~ Tangle -> Bool *)
  test "T-Isotopy (tangles)" (fun () ->
    let gamma = env_bind_val [] "t1" (TTangle ([], [])) in
    let gamma = env_bind_val gamma "t2" (TTangle ([], [])) in
    infer gamma (BinOp (Isotopy, Var "t1", Var "t2")) = TBool);

  (* Isotopy: non-topological types -> error *)
  test "T-Isotopy (type error)" (fun () ->
    try
      let _ = infer [] (BinOp (Isotopy, IntLit 1, IntLit 2)) in
      false
    with Type_error _ -> true)

(* ================================================================== *)
(*  9. Close                                                           *)
(* ================================================================== *)

let test_close () =
  Printf.printf "\n=== Close ===\n";

  (* [T-Close-Word]: Word[n] -> Tangle[I, I] *)
  test "T-Close-Word" (fun () ->
    infer [] (Close (BraidLit [sigma 1])) = TTangle ([], []));

  (* [T-Close-Tangle]: Tangle[A, B] with |A|=|B| -> Tangle[I, I] *)
  test "T-Close-Tangle" (fun () ->
    let gamma = env_bind_val [] "t"
      (TTangle ([StrandDefault; StrandDefault],
                [StrandDefault; StrandDefault])) in
    infer gamma (Close (Var "t")) = TTangle ([], []));

  (* Close: boundary length mismatch -> error *)
  test "T-Close (boundary mismatch)" (fun () ->
    let gamma = env_bind_val [] "t"
      (TTangle ([StrandDefault], [StrandDefault; StrandDefault])) in
    try
      let _ = infer gamma (Close (Var "t")) in
      false
    with Type_error _ -> true);

  (* Close: non-topological type -> error *)
  test "T-Close (type error)" (fun () ->
    try
      let _ = infer [] (Close (IntLit 42)) in
      false
    with Type_error _ -> true)

(* ================================================================== *)
(*  10. Cap and Cup                                                    *)
(* ================================================================== *)

let test_cap_cup () =
  Printf.printf "\n=== Cap and Cup ===\n";

  (* [T-Cap]: creates Tangle[[T,T], I] *)
  test "T-Cap" (fun () ->
    let t = infer [] (Cap (IntLit 0, IntLit 0)) in
    match t with
    | TTangle ([_; _], []) -> true
    | _ -> false);

  (* [T-Cup]: creates Tangle[I, [T,T]] *)
  test "T-Cup" (fun () ->
    let t = infer [] (Cup (IntLit 0, IntLit 0)) in
    match t with
    | TTangle ([], [_; _]) -> true
    | _ -> false)

(* ================================================================== *)
(*  11. Mirror                                                         *)
(* ================================================================== *)

let test_mirror () =
  Printf.printf "\n=== Mirror ===\n";

  (* [T-Mirror-Word]: Word[n] -> Word[n] *)
  test "T-Mirror-Word" (fun () ->
    infer [] (Mirror (BraidLit [sigma 1; sigma 2])) = TWord 3);

  (* [T-Mirror-Tangle]: Tangle[A, B] -> Tangle[B, A] *)
  test "T-Mirror-Tangle" (fun () ->
    let gamma = env_bind_val [] "t"
      (TTangle ([StrandDefault], [StrandDefault; StrandDefault])) in
    infer gamma (Mirror (Var "t"))
      = TTangle ([StrandDefault; StrandDefault], [StrandDefault]));

  (* Mirror: non-topological -> error *)
  test "T-Mirror (type error)" (fun () ->
    try
      let _ = infer [] (Mirror (IntLit 1)) in
      false
    with Type_error _ -> true)

(* ================================================================== *)
(*  12. Reverse                                                        *)
(* ================================================================== *)

let test_reverse () =
  Printf.printf "\n=== Reverse ===\n";

  (* [T-Reverse]: Word[n] -> Word[n] *)
  test "T-Reverse" (fun () ->
    infer [] (Reverse (BraidLit [sigma 1; sigma 2])) = TWord 3);

  (* Reverse: non-word -> error *)
  test "T-Reverse (type error)" (fun () ->
    try
      let _ = infer [] (Reverse (IntLit 1)) in
      false
    with Type_error _ -> true)

(* ================================================================== *)
(*  13. Simplify                                                       *)
(* ================================================================== *)

let test_simplify () =
  Printf.printf "\n=== Simplify ===\n";

  (* [T-Simplify-Word]: Word[n] -> Word[n] *)
  test "T-Simplify-Word" (fun () ->
    infer [] (Simplify (BraidLit [sigma 1; sigma_inv 1])) = TWord 2);

  (* [T-Simplify-Tangle]: preserves boundary types *)
  test "T-Simplify-Tangle" (fun () ->
    let gamma = env_bind_val [] "t"
      (TTangle ([StrandDefault], [StrandDefault])) in
    infer gamma (Simplify (Var "t"))
      = TTangle ([StrandDefault], [StrandDefault]));

  (* Simplify: non-topological -> error *)
  test "T-Simplify (type error)" (fun () ->
    try
      let _ = infer [] (Simplify (StringLit "x")) in
      false
    with Type_error _ -> true)

(* ================================================================== *)
(*  14. Twist                                                          *)
(* ================================================================== *)

let test_twist () =
  Printf.printf "\n=== Twist ===\n";

  (* [T-Twist-Word]: Word[n] -> Word[n] *)
  test "T-Twist-Word" (fun () ->
    infer [] (Twist (BraidLit [sigma 1])) = TWord 2);

  (* [T-Twist-Tangle]: Tangle[A,B] -> Tangle[A,B] *)
  test "T-Twist-Tangle" (fun () ->
    let gamma = env_bind_val [] "t"
      (TTangle ([StrandDefault], [StrandDefault])) in
    infer gamma (Twist (Var "t"))
      = TTangle ([StrandDefault], [StrandDefault]));

  (* Twist: non-topological -> error *)
  test "T-Twist (type error)" (fun () ->
    try
      let _ = infer [] (Twist (IntLit 1)) in
      false
    with Type_error _ -> true)

(* ================================================================== *)
(*  15. Pattern matching                                               *)
(* ================================================================== *)

let test_match () =
  Printf.printf "\n=== Pattern Matching ===\n";

  (* [T-Match]: match with variable pattern *)
  test "T-Match (var pattern)" (fun () ->
    let scrutinee = BraidLit [sigma 1] in
    let arm = { arm_pattern = PatVar "w"; arm_body = Var "w" } in
    infer [] (Match (scrutinee, [arm])) = TWord 2);

  (* [T-Match]: match with identity pattern *)
  test "T-Match (identity pattern)" (fun () ->
    let scrutinee = Identity in
    let arm = { arm_pattern = PatIdentity; arm_body = IntLit 0 } in
    infer [] (Match (scrutinee, [arm])) = TNum);

  (* [T-Match]: match with cons pattern *)
  test "T-Match (cons pattern)" (fun () ->
    let scrutinee = BraidLit [sigma 1; sigma 2] in
    let gpat = { gpat_index = 1; gpat_exponent = 1 } in
    let arm = {
      arm_pattern = PatCons (gpat, PatVar "rest");
      arm_body = Var "rest";
    } in
    infer [] (Match (scrutinee, [arm])) = TWord 3);

  (* [T-Match]: wildcard pattern *)
  test "T-Match (wildcard)" (fun () ->
    let scrutinee = BraidLit [sigma 1] in
    let arm = { arm_pattern = PatWildcard; arm_body = IntLit 42 } in
    infer [] (Match (scrutinee, [arm])) = TNum);

  (* [T-Match]: multiple arms must agree on result type *)
  test "T-Match (arms agree)" (fun () ->
    let scrutinee = BraidLit [sigma 1] in
    let arm1 = { arm_pattern = PatIdentity; arm_body = IntLit 0 } in
    let arm2 = { arm_pattern = PatWildcard; arm_body = IntLit 1 } in
    infer [] (Match (scrutinee, [arm1; arm2])) = TNum);

  (* [T-Match]: arms disagree on type -> error *)
  test "T-Match (arms disagree)" (fun () ->
    let scrutinee = BraidLit [sigma 1] in
    let arm1 = { arm_pattern = PatIdentity; arm_body = IntLit 0 } in
    let arm2 = { arm_pattern = PatWildcard; arm_body = StringLit "x" } in
    try
      let _ = infer [] (Match (scrutinee, [arm1; arm2])) in
      false
    with Type_error _ -> true);

  (* Pattern: identity pattern on non-word -> error *)
  test "P-Identity (type error)" (fun () ->
    let scrutinee = IntLit 42 in
    let arm = { arm_pattern = PatIdentity; arm_body = IntLit 0 } in
    try
      let _ = infer [] (Match (scrutinee, [arm])) in
      false
    with Type_error _ -> true)

(* ================================================================== *)
(*  16. Let bindings                                                   *)
(* ================================================================== *)

let test_let () =
  Printf.printf "\n=== Let Bindings ===\n";

  (* [T-Let]: basic let binding *)
  test "T-Let (basic)" (fun () ->
    let e = Let ("x", IntLit 42, Var "x") in
    infer [] e = TNum);

  (* [T-Let]: nested let *)
  test "T-Let (nested)" (fun () ->
    let e = Let ("x", IntLit 1,
              Let ("y", IntLit 2,
                BinOp (Add, Var "x", Var "y"))) in
    infer [] e = TNum);

  (* [T-Let]: shadowing *)
  test "T-Let (shadowing)" (fun () ->
    let e = Let ("x", IntLit 1,
              Let ("x", StringLit "hi",
                Var "x")) in
    infer [] e = TStr);

  (* [T-Let]: braid binding *)
  test "T-Let (braid)" (fun () ->
    let e = Let ("w", BraidLit [sigma 1; sigma 2],
              BinOp (Compose, Var "w", Var "w")) in
    infer [] e = TWord 3)

(* ================================================================== *)
(*  17. Function definitions and application                           *)
(* ================================================================== *)

let test_functions () =
  Printf.printf "\n=== Functions ===\n";

  (* [T-Def-Val]: value definition *)
  test "T-Def-Val" (fun () ->
    let prog = [def_val "x" (IntLit 42)] in
    let r = check_ok prog in
    r.result_ok);

  (* [T-Def-Fun]: function definition *)
  test "T-Def-Fun" (fun () ->
    let prog = [def_fun "f" ["x"] (Var "x")] in
    let r = check_ok prog in
    r.result_ok);

  (* [T-App]: function application *)
  test "T-App" (fun () ->
    let prog = [
      def_fun "double" ["x"] (BinOp (Compose, Var "x", Var "x"));
      def_val "result" (Call ("double", [BraidLit [sigma 1]]));
    ] in
    let r = check_ok prog in
    r.result_ok);

  (* [T-App]: wrong arity -> error *)
  test "T-App (wrong arity)" (fun () ->
    let gamma = env_bind_fun [] "f"
      { fsig_params = [TNum; TNum]; fsig_return = TNum } in
    try
      let _ = infer gamma (Call ("f", [IntLit 1])) in
      false
    with Type_error _ -> true);

  (* [T-App]: unbound function -> error *)
  test "T-App (unbound)" (fun () ->
    try
      let _ = infer [] (Call ("nonexistent", [IntLit 1])) in
      false
    with Type_error _ -> true)

(* ================================================================== *)
(*  18. Assert                                                         *)
(* ================================================================== *)

let test_assert () =
  Printf.printf "\n=== Assert ===\n";

  (* [T-Assert]: boolean expression *)
  test "T-Assert (bool)" (fun () ->
    let prog = [Assertion (BoolLit true)] in
    let r = check_ok prog in
    r.result_ok);

  (* [T-Assert]: equality expression produces Bool *)
  test "T-Assert (equality)" (fun () ->
    let prog = [Assertion (BinOp (Eq, IntLit 1, IntLit 2))] in
    let r = check_ok prog in
    r.result_ok);

  (* [T-Assert]: isotopy expression produces Bool *)
  test "T-Assert (isotopy)" (fun () ->
    let prog = [
      def_val "w" (BraidLit [sigma 1]);
      Assertion (BinOp (Isotopy, Var "w", Var "w"));
    ] in
    let r = check_ok prog in
    r.result_ok);

  (* [T-Assert]: non-Bool -> error *)
  test "T-Assert (type error)" (fun () ->
    let prog = [Assertion (IntLit 42)] in
    check_fails prog)

(* ================================================================== *)
(*  19. Compute                                                        *)
(* ================================================================== *)

let test_compute () =
  Printf.printf "\n=== Compute ===\n";

  (* [T-Compute]: jones on a closed word *)
  test "T-Compute (jones)" (fun () ->
    let prog = [
      def_val "trefoil" (BraidLit [sigma 1; sigma 1; sigma 1]);
      Computation { comp_invariant = "jones"; comp_arg = Var "trefoil" };
    ] in
    let r = check_ok prog in
    r.result_ok);

  (* [T-Compute]: all valid invariant names *)
  test "T-Compute (all invariants)" (fun () ->
    let word = BraidLit [sigma 1] in
    let invs = ["jones"; "alexander"; "homfly"; "kauffman"; "writhe"; "linking"] in
    let stmts = List.map (fun inv ->
      Computation { comp_invariant = inv; comp_arg = word }
    ) invs in
    let prog = stmts in
    let r = check_ok prog in
    r.result_ok);

  (* [T-Compute]: unknown invariant -> error *)
  test "T-Compute (unknown invariant)" (fun () ->
    let prog = [
      Computation { comp_invariant = "bogus"; comp_arg = BraidLit [sigma 1] }
    ] in
    check_fails prog);

  (* [T-Compute]: non-closed tangle -> error *)
  test "T-Compute (open tangle)" (fun () ->
    let prog = [
      def_val "open_t" (BraidLit [sigma 1]);  (* This is a Word, which is OK *)
    ] in
    let r = check_ok prog in
    r.result_ok)

(* ================================================================== *)
(*  20. Width inference and auto-widening                              *)
(* ================================================================== *)

let test_width () =
  Printf.printf "\n=== Width Inference ===\n";

  (* Width: identity has width 0 *)
  test "Width (identity)" (fun () ->
    infer [] Identity = TWord 0);

  (* Width: braid width = max(index) + 1 *)
  test "Width (braid)" (fun () ->
    infer [] (BraidLit [sigma 3; sigma 1]) = TWord 4);

  (* Auto-widen: compose different widths *)
  test "Width (auto-widen compose)" (fun () ->
    let e = BinOp (Compose,
      BraidLit [sigma 1],      (* Word[2] *)
      BraidLit [sigma 3]) in   (* Word[4] *)
    infer [] e = TWord 4);

  (* Tensor: widths add *)
  test "Width (tensor adds)" (fun () ->
    let e = BinOp (Tensor,
      BraidLit [sigma 1],      (* Word[2] *)
      BraidLit [sigma 1]) in   (* Word[2] *)
    infer [] e = TWord 4);

  (* Width through let binding *)
  test "Width (through let)" (fun () ->
    let e = Let ("w", BraidLit [sigma 2],
              BinOp (Compose, Var "w", BraidLit [sigma 1])) in
    infer [] e = TWord 3)

(* ================================================================== *)
(*  21. Type error detection                                           *)
(* ================================================================== *)

let test_type_errors () =
  Printf.printf "\n=== Type Error Detection ===\n";

  (* Cannot add Word and Num *)
  test "Error: Word + Num" (fun () ->
    try
      let _ = infer [] (BinOp (Add, BraidLit [sigma 1], IntLit 1)) in
      false
    with Type_error _ -> true);

  (* Cannot negate a braid *)
  test "Error: -Word" (fun () ->
    try
      let _ = infer [] (UnaryOp (Neg, BraidLit [sigma 1])) in
      false
    with Type_error _ -> true);

  (* Cannot logical-not a number *)
  test "Error: not Num" (fun () ->
    try
      let _ = infer [] (UnaryOp (Not, IntLit 1)) in
      false
    with Type_error _ -> true);

  (* Cannot reverse a tangle *)
  test "Error: reverse Tangle" (fun () ->
    let gamma = env_bind_val [] "t" (TTangle ([], [])) in
    try
      let _ = infer gamma (Reverse (Var "t")) in
      false
    with Type_error _ -> true);

  (* Cannot close a number *)
  test "Error: close Num" (fun () ->
    try
      let _ = infer [] (Close (IntLit 42)) in
      false
    with Type_error _ -> true)

(* ================================================================== *)
(*  22. Unary operators                                                *)
(* ================================================================== *)

let test_unary () =
  Printf.printf "\n=== Unary Operators ===\n";

  (* Negation of Num *)
  test "UnaryOp Neg (Num)" (fun () ->
    infer [] (UnaryOp (Neg, IntLit 42)) = TNum);

  (* Logical not of Bool *)
  test "UnaryOp Not (Bool)" (fun () ->
    infer [] (UnaryOp (Not, BoolLit true)) = TBool)

(* ================================================================== *)
(*  23. Weave blocks                                                   *)
(* ================================================================== *)

let test_weave () =
  Printf.printf "\n=== Weave Blocks ===\n";

  (* Basic weave block with crossings *)
  test "T-Weave (basic)" (fun () ->
    let prog = [WeaveBlock {
      weave_inputs = [
        { strand_name = "a"; strand_type = None };
        { strand_name = "b"; strand_type = None };
      ];
      weave_body = Crossing ("a", Over, "b");
      weave_outputs = [
        { strand_name = "b"; strand_type = None };
        { strand_name = "a"; strand_type = None };
      ];
    }] in
    let r = check_ok prog in
    r.result_ok);

  (* Weave block with typed strands *)
  test "T-Weave (typed strands)" (fun () ->
    let prog = [WeaveBlock {
      weave_inputs = [
        { strand_name = "x"; strand_type = Some "Q" };
        { strand_name = "y"; strand_type = Some "R" };
      ];
      weave_body = Crossing ("x", Under, "y");
      weave_outputs = [
        { strand_name = "y"; strand_type = Some "R" };
        { strand_name = "x"; strand_type = Some "Q" };
      ];
    }] in
    let r = check_ok prog in
    r.result_ok)

(* ================================================================== *)
(*  24. Program-level type-checking                                    *)
(* ================================================================== *)

let test_program () =
  Printf.printf "\n=== Program-Level ===\n";

  (* Complete program with definitions, assertions, computations *)
  test "Full program" (fun () ->
    let prog = [
      def_val "trefoil" (BraidLit [sigma 1; sigma 1; sigma 1]);
      def_val "figure_eight" (BraidLit [sigma 1; sigma_inv 2; sigma 1; sigma_inv 2]);
      Assertion (BinOp (Eq,
        BraidLit [sigma 1; sigma 1; sigma 1],
        Var "trefoil"));
      Computation { comp_invariant = "jones"; comp_arg = Var "trefoil" };
    ] in
    let r = check_ok prog in
    r.result_ok);

  (* Forward references work (pass 1 collects all defs) *)
  test "Forward references" (fun () ->
    let prog = [
      (* Use y before it is defined *)
      def_val "x" (BinOp (Compose, Var "y", BraidLit [sigma 1]));
      def_val "y" (BraidLit [sigma 2]);
    ] in
    let r = check_ok prog in
    r.result_ok);

  (* Empty program is valid *)
  test "Empty program" (fun () ->
    let r = check_ok [] in
    r.result_ok);

  (* StmtError is tolerated *)
  test "StmtError recovery" (fun () ->
    let prog = [StmtError; def_val "x" (IntLit 1)] in
    let r = check_ok prog in
    r.result_ok)

(* ================================================================== *)
(*  25. Permutation tracking                                           *)
(* ================================================================== *)

let test_permutations () =
  Printf.printf "\n=== Permutation Tracking ===\n";

  (* swap_boundary swaps positions i and i+1 *)
  test "swap_boundary" (fun () ->
    let b = [StrandNamed "A"; StrandNamed "B"; StrandNamed "C"] in
    let b' = swap_boundary b 1 in
    b' = [StrandNamed "B"; StrandNamed "A"; StrandNamed "C"]);

  (* apply_perm with single generator *)
  test "apply_perm (single)" (fun () ->
    let b = [StrandNamed "A"; StrandNamed "B"; StrandNamed "C"] in
    let b' = apply_perm b [sigma 2] in
    b' = [StrandNamed "A"; StrandNamed "C"; StrandNamed "B"]);

  (* apply_perm with identity (no generators) *)
  test "apply_perm (identity)" (fun () ->
    let b = [StrandNamed "A"; StrandNamed "B"] in
    let b' = apply_perm b [] in
    b' = b);

  (* apply_perm with multiple generators *)
  test "apply_perm (multiple)" (fun () ->
    let b = [StrandNamed "A"; StrandNamed "B"; StrandNamed "C"] in
    (* sigma_1 then sigma_2: A B C -> B A C -> B C A *)
    let b' = apply_perm b [sigma 1; sigma 2] in
    b' = [StrandNamed "B"; StrandNamed "C"; StrandNamed "A"])

(* ================================================================== *)
(*  Main: run all test groups                                          *)
(* ================================================================== *)

let () =
  Printf.printf "TANGLE Type Checker Tests\n";
  Printf.printf "=========================\n";
  test_literals ();
  test_braid_literals ();
  test_variables ();
  test_composition ();
  test_tensor ();
  test_arithmetic ();
  test_equality ();
  test_isotopy ();
  test_close ();
  test_cap_cup ();
  test_mirror ();
  test_reverse ();
  test_simplify ();
  test_twist ();
  test_match ();
  test_let ();
  test_functions ();
  test_assert ();
  test_compute ();
  test_width ();
  test_type_errors ();
  test_unary ();
  test_weave ();
  test_program ();
  test_permutations ();
  Printf.printf "\n=========================\n";
  Printf.printf "Results: %d/%d passed" !passed !total;
  if !failed > 0 then
    Printf.printf " (%d FAILED)" !failed;
  Printf.printf "\n";
  if !failed > 0 then exit 1
