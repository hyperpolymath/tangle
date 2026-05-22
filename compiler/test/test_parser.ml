(* SPDX-License-Identifier: MPL-2.0 *)
(* test_parser.ml — Test suite for the TANGLE lexer and parser.
 *
 * Tests cover:
 *   1. Simple definitions
 *   2. Weave blocks with strands
 *   3. Invariant computations
 *   4. Pattern matching
 *   5. Let bindings
 *   6. Operator precedence (all levels)
 *   7. Crossings and twists
 *   8. Assertions
 *   9. Braid literals (empty, single, multi, inverse, exponent)
 *  10. Comments (line and nested block)
 *  11. String and float literals
 *  12. Unary prefix operations
 *  13. Lexer error cases
 *)

open Tangle.Ast

(* ================================================================== *)
(*  Test harness                                                       *)
(* ================================================================== *)

(** Track pass/fail counts. *)
let passed = ref 0
let failed = ref 0
let total  = ref 0

(** Parse a source string into a program AST.
 *  Returns [None] on parse/lex errors.
 *)
let parse (source : string) : program option =
  let lexbuf = Lexing.from_string source in
  try Some (Tangle.Parser.program Tangle.Lexer.token lexbuf)
  with
  | Tangle.Lexer.Lexer_error _ -> None
  | Tangle.Parser.Error -> None
  | Assert_failure _ -> None

(** Assert that [source] parses successfully and return the AST. *)
let parse_ok (source : string) : program =
  match parse source with
  | Some prog -> prog
  | None ->
    Printf.eprintf "  UNEXPECTED PARSE FAILURE for:\n    %s\n" source;
    failwith "parse_ok"

(** Assert that [source] fails to parse. *)
let parse_fail (source : string) : unit =
  match parse source with
  | None -> ()
  | Some _ ->
    Printf.eprintf "  EXPECTED PARSE FAILURE for:\n    %s\n" source;
    failwith "parse_fail"

(** Run a named test case. *)
let test (name : string) (f : unit -> unit) : unit =
  incr total;
  try
    f ();
    incr passed;
    Printf.printf "  PASS: %s\n" name
  with exn ->
    incr failed;
    Printf.printf "  FAIL: %s (%s)\n" name (Printexc.to_string exn)

(** Assert structural equality. *)
let assert_eq (label : string) (expected : 'a) (actual : 'a) : unit =
  if expected <> actual then begin
    Printf.eprintf "  assertion failed: %s\n" label;
    failwith "assert_eq"
  end

(* ================================================================== *)
(*  1. Simple definitions                                              *)
(* ================================================================== *)

let test_simple_definitions () =
  Printf.printf "\n--- Simple definitions ---\n";

  test "def with braid literal" (fun () ->
    let prog = parse_ok "def trefoil = braid[s1, s2, s1]" in
    match prog with
    | [Definition d] ->
      assert_eq "name" "trefoil" d.def_name;
      assert_eq "no params" [] d.def_params;
      (match d.def_body with
       | BraidLit gs ->
         assert_eq "3 generators" 3 (List.length gs);
         assert_eq "g1 index" 1 (List.nth gs 0).gen_index;
         assert_eq "g1 exp" 1 (List.nth gs 0).gen_exponent;
         assert_eq "g2 index" 2 (List.nth gs 1).gen_index;
       | _ -> failwith "expected BraidLit")
    | _ -> failwith "expected single Definition");

  test "def with inverse generator" (fun () ->
    let prog = parse_ok "def inv = braid[s1, s2^-1, s1]" in
    match prog with
    | [Definition d] ->
      (match d.def_body with
       | BraidLit gs ->
         assert_eq "g2 exp" (-1) (List.nth gs 1).gen_exponent
       | _ -> failwith "expected BraidLit")
    | _ -> failwith "expected single Definition");

  test "def with exponent" (fun () ->
    let prog = parse_ok "def powered = braid[s1^3]" in
    match prog with
    | [Definition d] ->
      (match d.def_body with
       | BraidLit [g] ->
         assert_eq "index" 1 g.gen_index;
         assert_eq "exp" 3 g.gen_exponent
       | _ -> failwith "expected BraidLit with one gen")
    | _ -> failwith "expected single Definition");

  test "def with params" (fun () ->
    let prog = parse_ok "def compose(a, b) = a . b" in
    match prog with
    | [Definition d] ->
      assert_eq "name" "compose" d.def_name;
      assert_eq "params" ["a"; "b"] d.def_params;
      (match d.def_body with
       | BinOp (Compose, Var "a", Var "b") -> ()
       | _ -> failwith "expected Compose")
    | _ -> failwith "expected single Definition");

  test "def identity" (fun () ->
    let prog = parse_ok "def unit = identity" in
    match prog with
    | [Definition d] ->
      assert_eq "body" Identity d.def_body
    | _ -> failwith "expected single Definition");

  test "def empty braid" (fun () ->
    let prog = parse_ok "def empty = braid[]" in
    match prog with
    | [Definition d] ->
      assert_eq "body" (BraidLit []) d.def_body
    | _ -> failwith "expected single Definition");

  test "def with bool literal" (fun () ->
    let prog = parse_ok "def flag = true" in
    match prog with
    | [Definition d] ->
      assert_eq "body" (BoolLit true) d.def_body
    | _ -> failwith "expected single Definition")

(* ================================================================== *)
(*  2. Weave blocks                                                    *)
(* ================================================================== *)

let test_weave_blocks () =
  Printf.printf "\n--- Weave blocks ---\n";

  test "basic weave" (fun () ->
    let prog = parse_ok
      "weave strands a, b into (a > b) yield strands c" in
    match prog with
    | [WeaveBlock w] ->
      assert_eq "inputs" 2 (List.length w.weave_inputs);
      assert_eq "input1" "a" (List.nth w.weave_inputs 0).strand_name;
      assert_eq "input2" "b" (List.nth w.weave_inputs 1).strand_name;
      assert_eq "outputs" 1 (List.length w.weave_outputs);
      assert_eq "output1" "c" (List.nth w.weave_outputs 0).strand_name
    | _ -> failwith "expected single WeaveBlock");

  test "weave with types" (fun () ->
    let prog = parse_ok
      "weave strands a: Strand, b: Strand into (a > b) yield strands c: Strand" in
    match prog with
    | [WeaveBlock w] ->
      assert_eq "input1 type" (Some "Strand")
        (List.nth w.weave_inputs 0).strand_type;
      assert_eq "output1 type" (Some "Strand")
        (List.nth w.weave_outputs 0).strand_type
    | _ -> failwith "expected single WeaveBlock")

(* ================================================================== *)
(*  3. Invariant computations                                          *)
(* ================================================================== *)

let test_computations () =
  Printf.printf "\n--- Computations ---\n";

  test "compute jones" (fun () ->
    let prog = parse_ok "compute jones(trefoil)" in
    match prog with
    | [Computation c] ->
      assert_eq "invariant" "jones" c.comp_invariant;
      (match c.comp_arg with
       | Var "trefoil" -> ()
       | _ -> failwith "expected Var trefoil")
    | _ -> failwith "expected single Computation");

  test "compute alexander" (fun () ->
    let prog = parse_ok "compute alexander(braid[s1, s2^-1])" in
    match prog with
    | [Computation c] ->
      assert_eq "invariant" "alexander" c.comp_invariant
    | _ -> failwith "expected single Computation");

  test "compute custom invariant" (fun () ->
    let prog = parse_ok "compute myinvariant(x)" in
    match prog with
    | [Computation c] ->
      assert_eq "invariant" "myinvariant" c.comp_invariant
    | _ -> failwith "expected single Computation")

(* ================================================================== *)
(*  4. Pattern matching                                                *)
(* ================================================================== *)

let test_pattern_matching () =
  Printf.printf "\n--- Pattern matching ---\n";

  test "match with identity" (fun () ->
    let prog = parse_ok
      "def f(x) = match x with | identity => true | _ => false end" in
    match prog with
    | [Definition d] ->
      (match d.def_body with
       | Match (Var "x", [arm1; arm2]) ->
         assert_eq "pat1" PatIdentity arm1.arm_pattern;
         assert_eq "body1" (BoolLit true) arm1.arm_body;
         assert_eq "pat2" PatWildcard arm2.arm_pattern;
         assert_eq "body2" (BoolLit false) arm2.arm_body
       | _ -> failwith "expected Match")
    | _ -> failwith "expected single Definition");

  test "match with cons pattern" (fun () ->
    let prog = parse_ok
      "def len(x) = match x with \
       | identity => 0 \
       | s1 . rest => 1 \
       end" in
    match prog with
    | [Definition d] ->
      (match d.def_body with
       | Match (_, [_; arm2]) ->
         (match arm2.arm_pattern with
          | PatCons (g, PatVar "rest") ->
            assert_eq "gen index" 1 g.gpat_index;
            assert_eq "gen exp" 1 g.gpat_exponent
          | _ -> failwith "expected PatCons")
       | _ -> failwith "expected Match")
    | _ -> failwith "expected single Definition");

  test "match with inverse cons" (fun () ->
    let prog = parse_ok
      "def f(x) = match x with | s2^-1 . rest => rest | _ => x end" in
    match prog with
    | [Definition d] ->
      (match d.def_body with
       | Match (_, [arm1; _]) ->
         (match arm1.arm_pattern with
          | PatCons (g, PatVar "rest") ->
            assert_eq "gen index" 2 g.gpat_index;
            assert_eq "gen exp" (-1) g.gpat_exponent
          | _ -> failwith "expected PatCons with inverse")
       | _ -> failwith "expected Match")
    | _ -> failwith "expected single Definition")

(* ================================================================== *)
(*  5. Let bindings                                                    *)
(* ================================================================== *)

let test_let_bindings () =
  Printf.printf "\n--- Let bindings ---\n";

  test "simple let" (fun () ->
    let prog = parse_ok "def f = let x = 42 in x" in
    match prog with
    | [Definition d] ->
      (match d.def_body with
       | Let ("x", IntLit 42, Var "x") -> ()
       | _ -> failwith "expected Let")
    | _ -> failwith "expected single Definition");

  test "nested let" (fun () ->
    let prog = parse_ok "def f = let x = 1 in let y = 2 in x + y" in
    match prog with
    | [Definition d] ->
      (match d.def_body with
       | Let ("x", IntLit 1, Let ("y", IntLit 2, BinOp (Add, Var "x", Var "y"))) -> ()
       | _ -> failwith "expected nested Let")
    | _ -> failwith "expected single Definition")

(* ================================================================== *)
(*  6. Operator precedence                                             *)
(* ================================================================== *)

let test_operator_precedence () =
  Printf.printf "\n--- Operator precedence ---\n";

  test "tensor binds tighter than compose" (fun () ->
    (* a . b | c should parse as a . (b | c) *)
    let prog = parse_ok "def f = a . b | c" in
    match prog with
    | [Definition d] ->
      (match d.def_body with
       | BinOp (Compose, Var "a", BinOp (Tensor, Var "b", Var "c")) -> ()
       | _ -> failwith "expected Compose(a, Tensor(b, c))")
    | _ -> failwith "expected single Definition");

  test "compose binds tighter than product" (fun () ->
    (* a * b . c should parse as a * (b . c) *)
    let prog = parse_ok "def f = a * b . c" in
    match prog with
    | [Definition d] ->
      (match d.def_body with
       | BinOp (Mul, Var "a", BinOp (Compose, Var "b", Var "c")) -> ()
       | _ -> failwith "expected Mul(a, Compose(b, c))")
    | _ -> failwith "expected single Definition");

  test "product binds tighter than sum" (fun () ->
    (* a + b * c should parse as a + (b * c) *)
    let prog = parse_ok "def f = a + b * c" in
    match prog with
    | [Definition d] ->
      (match d.def_body with
       | BinOp (Add, Var "a", BinOp (Mul, Var "b", Var "c")) -> ()
       | _ -> failwith "expected Add(a, Mul(b, c))")
    | _ -> failwith "expected single Definition");

  test "sum binds tighter than equality" (fun () ->
    (* a == b + c should parse as a == (b + c) *)
    let prog = parse_ok "def f = a == b + c" in
    match prog with
    | [Definition d] ->
      (match d.def_body with
       | BinOp (Eq, Var "a", BinOp (Add, Var "b", Var "c")) -> ()
       | _ -> failwith "expected Eq(a, Add(b, c))")
    | _ -> failwith "expected single Definition");

  test "equality binds tighter than pipeline" (fun () ->
    (* a >> b == c should parse as a >> (b == c) *)
    let prog = parse_ok "def f = a >> b == c" in
    match prog with
    | [Definition d] ->
      (match d.def_body with
       | Pipeline (Var "a", BinOp (Eq, Var "b", Var "c")) -> ()
       | _ -> failwith "expected Pipeline(a, Eq(b, c))")
    | _ -> failwith "expected single Definition");

  test "isotopy at same level as equality" (fun () ->
    let prog = parse_ok "def f = a ~ b" in
    match prog with
    | [Definition d] ->
      (match d.def_body with
       | BinOp (Isotopy, Var "a", Var "b") -> ()
       | _ -> failwith "expected Isotopy")
    | _ -> failwith "expected single Definition");

  test "left associativity of addition" (fun () ->
    (* a + b + c should parse as (a + b) + c *)
    let prog = parse_ok "def f = a + b + c" in
    match prog with
    | [Definition d] ->
      (match d.def_body with
       | BinOp (Add, BinOp (Add, Var "a", Var "b"), Var "c") -> ()
       | _ -> failwith "expected left-assoc Add")
    | _ -> failwith "expected single Definition");

  test "left associativity of pipeline" (fun () ->
    let prog = parse_ok "def f = a >> b >> c" in
    match prog with
    | [Definition d] ->
      (match d.def_body with
       | Pipeline (Pipeline (Var "a", Var "b"), Var "c") -> ()
       | _ -> failwith "expected left-assoc Pipeline")
    | _ -> failwith "expected single Definition");

  test "parenthesised override" (fun () ->
    let prog = parse_ok "def f = (a + b) * c" in
    match prog with
    | [Definition d] ->
      (match d.def_body with
       | BinOp (Mul, BinOp (Add, Var "a", Var "b"), Var "c") -> ()
       | _ -> failwith "expected Mul(Add(a, b), c)")
    | _ -> failwith "expected single Definition");

  test "division and subtraction" (fun () ->
    let prog = parse_ok "def f = a - b / c" in
    match prog with
    | [Definition d] ->
      (match d.def_body with
       | BinOp (Sub, Var "a", BinOp (Div, Var "b", Var "c")) -> ()
       | _ -> failwith "expected Sub(a, Div(b, c))")
    | _ -> failwith "expected single Definition")

(* ================================================================== *)
(*  7. Crossings and twists                                            *)
(* ================================================================== *)

let test_crossings_and_twists () =
  Printf.printf "\n--- Crossings and twists ---\n";

  test "over crossing" (fun () ->
    let prog = parse_ok "def f = (a > b)" in
    match prog with
    | [Definition d] ->
      (match d.def_body with
       | Crossing ("a", Over, "b") -> ()
       | _ -> failwith "expected Crossing Over")
    | _ -> failwith "expected single Definition");

  test "under crossing" (fun () ->
    let prog = parse_ok "def f = (a < b)" in
    match prog with
    | [Definition d] ->
      (match d.def_body with
       | Crossing ("a", Under, "b") -> ()
       | _ -> failwith "expected Crossing Under")
    | _ -> failwith "expected single Definition");

  test "twist with identifier" (fun () ->
    let prog = parse_ok "def f = (~a)" in
    match prog with
    | [Definition d] ->
      (match d.def_body with
       | Twist (Var "a") -> ()
       | _ -> failwith "expected Twist Var")
    | _ -> failwith "expected single Definition");

  test "twist with expression" (fun () ->
    let prog = parse_ok "def f = (~(braid[s1, s2]))" in
    match prog with
    | [Definition d] ->
      (match d.def_body with
       | Twist (BraidLit _) -> ()
       | _ -> failwith "expected Twist BraidLit")
    | _ -> failwith "expected single Definition")

(* ================================================================== *)
(*  8. Assertions                                                      *)
(* ================================================================== *)

let test_assertions () =
  Printf.printf "\n--- Assertions ---\n";

  test "assert equality" (fun () ->
    let prog = parse_ok "assert a == b" in
    match prog with
    | [Assertion (BinOp (Eq, Var "a", Var "b"))] -> ()
    | _ -> failwith "expected Assertion Eq");

  test "assert isotopy" (fun () ->
    let prog = parse_ok "assert trefoil ~ braid[s1, s2, s1]" in
    match prog with
    | [Assertion (BinOp (Isotopy, Var "trefoil", BraidLit _))] -> ()
    | _ -> failwith "expected Assertion Isotopy");

  test "assert bool" (fun () ->
    let prog = parse_ok "assert true" in
    match prog with
    | [Assertion (BoolLit true)] -> ()
    | _ -> failwith "expected Assertion true")

(* ================================================================== *)
(*  9. Braid literal edge cases                                        *)
(* ================================================================== *)

let test_braid_literals () =
  Printf.printf "\n--- Braid literals ---\n";

  test "empty braid" (fun () ->
    let prog = parse_ok "def e = braid[]" in
    match prog with
    | [Definition { def_body = BraidLit []; _ }] -> ()
    | _ -> failwith "expected empty BraidLit");

  test "single generator" (fun () ->
    let prog = parse_ok "def g = braid[s3]" in
    match prog with
    | [Definition { def_body = BraidLit [{gen_index=3; gen_exponent=1}]; _ }] -> ()
    | _ -> failwith "expected single gen BraidLit");

  test "generator with high index" (fun () ->
    let prog = parse_ok "def g = braid[s42]" in
    match prog with
    | [Definition { def_body = BraidLit [{gen_index=42; gen_exponent=1}]; _ }] -> ()
    | _ -> failwith "expected BraidLit with s42")

(* ================================================================== *)
(*  10. Comments                                                       *)
(* ================================================================== *)

let test_comments () =
  Printf.printf "\n--- Comments ---\n";

  test "line comment" (fun () ->
    let prog = parse_ok "# this is a comment\ndef x = 1" in
    match prog with
    | [Definition { def_body = IntLit 1; _ }] -> ()
    | _ -> failwith "expected Definition through comment");

  test "block comment" (fun () ->
    let prog = parse_ok "(* block comment *) def x = 2" in
    match prog with
    | [Definition { def_body = IntLit 2; _ }] -> ()
    | _ -> failwith "expected Definition through block comment");

  test "nested block comment" (fun () ->
    let prog = parse_ok "(* outer (* inner *) still outer *) def x = 3" in
    match prog with
    | [Definition { def_body = IntLit 3; _ }] -> ()
    | _ -> failwith "expected Definition through nested comment");

  test "comment at end of line" (fun () ->
    let prog = parse_ok "def x = 4 # trailing comment" in
    match prog with
    | [Definition { def_body = IntLit 4; _ }] -> ()
    | _ -> failwith "expected Definition with trailing comment")

(* ================================================================== *)
(*  11. Literals                                                       *)
(* ================================================================== *)

let test_literals () =
  Printf.printf "\n--- Literals ---\n";

  test "integer literal" (fun () ->
    let prog = parse_ok "def x = 42" in
    match prog with
    | [Definition { def_body = IntLit 42; _ }] -> ()
    | _ -> failwith "expected IntLit 42");

  test "zero literal" (fun () ->
    let prog = parse_ok "def x = 0" in
    match prog with
    | [Definition { def_body = IntLit 0; _ }] -> ()
    | _ -> failwith "expected IntLit 0");

  test "float literal" (fun () ->
    let prog = parse_ok "def x = 3.14" in
    match prog with
    | [Definition { def_body = FloatLit f; _ }] ->
      if abs_float (f -. 3.14) > 0.001 then failwith "wrong float value"
    | _ -> failwith "expected FloatLit");

  test "float with exponent" (fun () ->
    let prog = parse_ok "def x = 1e10" in
    match prog with
    | [Definition { def_body = FloatLit f; _ }] ->
      if abs_float (f -. 1e10) > 1.0 then failwith "wrong float value"
    | _ -> failwith "expected FloatLit");

  test "float with fraction and exponent" (fun () ->
    let prog = parse_ok "def x = 2.5e3" in
    match prog with
    | [Definition { def_body = FloatLit f; _ }] ->
      if abs_float (f -. 2500.0) > 0.1 then failwith "wrong float value"
    | _ -> failwith "expected FloatLit");

  test "string literal" (fun () ->
    let prog = parse_ok {|def x = "hello world"|} in
    match prog with
    | [Definition { def_body = StringLit "hello world"; _ }] -> ()
    | _ -> failwith "expected StringLit");

  test "string with escapes" (fun () ->
    let prog = parse_ok {|def x = "line1\nline2"|} in
    match prog with
    | [Definition { def_body = StringLit s; _ }] ->
      assert_eq "string content" "line1\nline2" s
    | _ -> failwith "expected StringLit with escape")

(* ================================================================== *)
(*  12. Unary prefix operations                                        *)
(* ================================================================== *)

let test_unary_ops () =
  Printf.printf "\n--- Unary prefix operations ---\n";

  test "close" (fun () ->
    let prog = parse_ok "def f = close(x)" in
    match prog with
    | [Definition { def_body = Close (Var "x"); _ }] -> ()
    | _ -> failwith "expected Close");

  test "mirror" (fun () ->
    let prog = parse_ok "def f = mirror(x)" in
    match prog with
    | [Definition { def_body = Mirror (Var "x"); _ }] -> ()
    | _ -> failwith "expected Mirror");

  test "reverse" (fun () ->
    let prog = parse_ok "def f = reverse(x)" in
    match prog with
    | [Definition { def_body = Reverse (Var "x"); _ }] -> ()
    | _ -> failwith "expected Reverse");

  test "simplify" (fun () ->
    let prog = parse_ok "def f = simplify(x)" in
    match prog with
    | [Definition { def_body = Simplify (Var "x"); _ }] -> ()
    | _ -> failwith "expected Simplify");

  test "cap" (fun () ->
    let prog = parse_ok "def f = cap(a, b)" in
    match prog with
    | [Definition { def_body = Cap (Var "a", Var "b"); _ }] -> ()
    | _ -> failwith "expected Cap");

  test "cup" (fun () ->
    let prog = parse_ok "def f = cup(a, b)" in
    match prog with
    | [Definition { def_body = Cup (Var "a", Var "b"); _ }] -> ()
    | _ -> failwith "expected Cup");

  test "negation" (fun () ->
    let prog = parse_ok "def f = -x" in
    match prog with
    | [Definition { def_body = UnaryOp (Neg, Var "x"); _ }] -> ()
    | _ -> failwith "expected UnaryOp Neg")

(* ================================================================== *)
(*  13. Function calls                                                 *)
(* ================================================================== *)

let test_function_calls () =
  Printf.printf "\n--- Function calls ---\n";

  test "no-arg call" (fun () ->
    (* A bare identifier without parens is a Var, not a Call *)
    let prog = parse_ok "def f = g" in
    match prog with
    | [Definition { def_body = Var "g"; _ }] -> ()
    | _ -> failwith "expected Var");

  test "single-arg call" (fun () ->
    let prog = parse_ok "def f = g(x)" in
    match prog with
    | [Definition { def_body = Call ("g", [Var "x"]); _ }] -> ()
    | _ -> failwith "expected Call with one arg");

  test "multi-arg call" (fun () ->
    let prog = parse_ok "def f = g(x, y, z)" in
    match prog with
    | [Definition { def_body = Call ("g", [Var "x"; Var "y"; Var "z"]); _ }] -> ()
    | _ -> failwith "expected Call with three args")

(* ================================================================== *)
(*  14. Pretty printer round-trip sanity                               *)
(* ================================================================== *)

let test_pretty_printer () =
  Printf.printf "\n--- Pretty printer ---\n";

  test "definition pretty prints" (fun () ->
    let prog = parse_ok "def trefoil = braid[s1, s2^-1, s1]" in
    let s = Tangle.Pretty.program_to_string prog in
    (* Just check it produces non-empty output without crashing *)
    if String.length s = 0 then failwith "empty pretty output");

  test "weave pretty prints" (fun () ->
    let prog = parse_ok
      "weave strands a, b into (a > b) yield strands c" in
    let s = Tangle.Pretty.program_to_string prog in
    if String.length s = 0 then failwith "empty pretty output");

  test "match pretty prints" (fun () ->
    let prog = parse_ok
      "def f(x) = match x with | identity => 0 | _ => 1 end" in
    let s = Tangle.Pretty.program_to_string prog in
    if String.length s = 0 then failwith "empty pretty output")

(* ================================================================== *)
(*  15. Error cases                                                    *)
(* ================================================================== *)

let test_error_cases () =
  Printf.printf "\n--- Error cases ---\n";

  test "unterminated string" (fun () ->
    parse_fail {|def x = "unterminated|});

  test "unexpected character" (fun () ->
    parse_fail "def x = @");

  test "missing equals in def" (fun () ->
    parse_fail "def x 42");

  test "missing end in match" (fun () ->
    parse_fail "def f = match x with | _ => 1")

(* ================================================================== *)
(*  16. Multi-statement programs                                       *)
(* ================================================================== *)

let test_multi_statement () =
  Printf.printf "\n--- Multi-statement programs ---\n";

  test "two definitions" (fun () ->
    let prog = parse_ok "def a = 1\ndef b = 2" in
    assert_eq "count" 2 (List.length prog));

  test "def then compute" (fun () ->
    let prog = parse_ok "def k = braid[s1, s2, s1]\ncompute jones(k)" in
    assert_eq "count" 2 (List.length prog);
    (match prog with
     | [Definition _; Computation _] -> ()
     | _ -> failwith "expected Definition then Computation"));

  test "full program" (fun () ->
    let prog = parse_ok
      "def trefoil = braid[s1, s2^-1, s1]\n\
       compute jones(trefoil)\n\
       assert trefoil ~ braid[s1, s2^-1, s1]" in
    assert_eq "count" 3 (List.length prog))

(* ================================================================== *)
(*  Entry point                                                        *)
(* ================================================================== *)

let () =
  Printf.printf "=== TANGLE Parser Test Suite ===\n";
  test_simple_definitions ();
  test_weave_blocks ();
  test_computations ();
  test_pattern_matching ();
  test_let_bindings ();
  test_operator_precedence ();
  test_crossings_and_twists ();
  test_assertions ();
  test_braid_literals ();
  test_comments ();
  test_literals ();
  test_unary_ops ();
  test_function_calls ();
  test_pretty_printer ();
  test_error_cases ();
  test_multi_statement ();
  Printf.printf "\n=== Results: %d/%d passed" !passed !total;
  if !failed > 0 then
    Printf.printf ", %d FAILED" !failed;
  Printf.printf " ===\n";
  if !failed > 0 then exit 1
