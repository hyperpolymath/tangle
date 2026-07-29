(* SPDX-License-Identifier: MPL-2.0 *)
(* test_quantity.ml — the {0, 1, omega} quantity semiring, and the strand
 * linearity rule built on it.
 *
 * Two halves, and the first is not decoration.  A "semiring" whose operations
 * do not actually satisfy the semiring laws is just two arbitrary tables, and
 * every soundness claim resting on it is worth nothing.  The carrier is three
 * elements, so the laws are decidable by exhaustion: we check all 27 triples
 * rather than asserting the laws in a comment.
 *
 * The second half checks the rule that consumes the semiring — that a strand
 * is used exactly once, and that the yield is a permutation of the inputs.
 *)

open Tangle.Ast
open Tangle.Typecheck

let passed = ref 0
let failed = ref 0

let test name f =
  (try
     if f () then begin incr passed; Printf.printf "  PASS  %s\n" name end
     else begin incr failed; Printf.printf "  FAIL  %s\n" name end
   with e ->
     incr failed;
     Printf.printf "  FAIL  %s (%s)\n" name (Printexc.to_string e))

(* The whole carrier.  Three elements, so "for all" is a fold, not a sample. *)
let all = Tangle.Quantity.[ Zero; One; Omega ]

let for_all1 p = List.for_all p all
let for_all2 p = List.for_all (fun a -> List.for_all (p a) all) all
let for_all3 p =
  List.for_all (fun a ->
    List.for_all (fun b -> List.for_all (p a b) all) all) all

(* ------------------------------------------------------------------ *)
(*  Semiring laws — exhaustively, over every triple                    *)
(* ------------------------------------------------------------------ *)

let () = print_endline "\n=== Semiring laws (exhaustive over all 3^3 triples) ==="

let () =
  let open Tangle.Quantity in

  test "(+) is associative" (fun () ->
    for_all3 (fun a b c -> add (add a b) c = add a (add b c)));

  test "(+) is commutative" (fun () ->
    for_all2 (fun a b -> add a b = add b a));

  test "0 is the additive identity" (fun () ->
    for_all1 (fun a -> add zero a = a && add a zero = a));

  test "( * ) is associative" (fun () ->
    for_all3 (fun a b c -> mul (mul a b) c = mul a (mul b c)));

  test "1 is the multiplicative identity" (fun () ->
    for_all1 (fun a -> mul one a = a && mul a one = a));

  test "0 annihilates under ( * )" (fun () ->
    for_all1 (fun a -> mul zero a = zero && mul a zero = zero));

  test "( * ) distributes over (+) on the left" (fun () ->
    for_all3 (fun a b c -> mul a (add b c) = add (mul a b) (mul a c)));

  test "( * ) distributes over (+) on the right" (fun () ->
    for_all3 (fun a b c -> mul (add a b) c = add (mul a c) (mul b c)))

(* ------------------------------------------------------------------ *)
(*  The intended readings of the two operations                        *)
(* ------------------------------------------------------------------ *)

let () = print_endline "\n=== Intended readings ==="

let () =
  let open Tangle.Quantity in

  (* This single equation is the whole reason `a > a` is rejected: two
     independent uses of a linear resource add to omega, and omega is not
     permitted where 1 was declared. *)
  test "1 + 1 = omega (two independent uses is unrestricted use)" (fun () ->
    add one one = Omega);

  test "omega is absorbing under (+)" (fun () ->
    for_all1 (fun a -> add Omega a = Omega));

  (* permits is the linear, not the affine, check.  The distinguishing case is
     the FIRST one: an affine discipline would accept it. *)
  test "declared 1, used 0 is REJECTED (linear, not affine)" (fun () ->
    not (permits ~declared:one ~actual:zero));

  test "declared 1, used 1 is accepted" (fun () ->
    permits ~declared:one ~actual:one);

  test "declared 1, used omega is rejected" (fun () ->
    not (permits ~declared:one ~actual:Omega));

  test "declared omega permits every usage" (fun () ->
    for_all1 (fun a -> permits ~declared:Omega ~actual:a));

  test "declared 0 permits only 0" (fun () ->
    for_all1 (fun a -> permits ~declared:zero ~actual:a = (a = Zero)));

  test "explain names the vanishing case" (fun () ->
    let s = explain ~declared:one ~actual:zero in
    (* substring search, so the wording can be improved without breaking this *)
    let re = Str.regexp_string "never used" in
    (try ignore (Str.search_forward re s 0); true with Not_found -> false))

(* ------------------------------------------------------------------ *)
(*  Strand linearity, through the typechecker                          *)
(* ------------------------------------------------------------------ *)

let () = print_endline "\n=== Strand linearity (weave) ==="

let strand n = { strand_name = n; strand_type = Some "Q" }

let weave ins body outs =
  Weave { weave_inputs = List.map strand ins;
          weave_body = body;
          weave_outputs = List.map strand outs }

let cross a b = Crossing (a, Over, b)

let accepts e =
  try ignore (infer_expr [] [] e); true with _ -> false

let rejects e = not (accepts e)

let () =
  test "permutation weave is accepted" (fun () ->
    accepts (weave ["a"; "b"] (cross "a" "b") ["b"; "a"]));

  test "identity-order yield is accepted" (fun () ->
    accepts (weave ["a"; "b"] (cross "a" "b") ["a"; "b"]));

  test "single strand under a twist is accepted" (fun () ->
    accepts (weave ["a"] (Twist (Var "a")) ["a"]));

  (* The three soundness gaps this work closes. *)
  test "REJECTED: strand crossed with itself (a > a)" (fun () ->
    rejects (weave ["a"; "b"] (cross "a" "a") ["a"; "b"]));

  test "REJECTED: strand yielded twice (contraction)" (fun () ->
    rejects (weave ["a"; "b"] (cross "a" "b") ["a"; "b"; "a"]));

  test "REJECTED: strand dropped from the yield (weakening)" (fun () ->
    rejects (weave ["a"; "b"] (cross "a" "b") ["a"]));

  test "REJECTED: yielding a strand that was never an input" (fun () ->
    rejects (weave ["a"; "b"] (cross "a" "b") ["a"; "c"]));

  (* An input that the body never mentions is a violation too: it is declared
     linear and used zero times.  Distinct from the yield check — this one
     fires even when the yield is a perfect permutation. *)
  test "REJECTED: input strand never used in the body" (fun () ->
    rejects (weave ["a"; "b"; "c"] (cross "a" "b") ["a"; "b"; "c"]))

(* ------------------------------------------------------------------ *)
(*  Braid WORDS are unrestricted — linearity must not leak into them   *)
(* ------------------------------------------------------------------ *)

let () = print_endline "\n=== Words stay unrestricted (omega) ==="

let () =
  (* `x . x` is sigma_1^2 — a legitimate braid.  If the linear discipline
     leaked out of `weave` and onto ordinary bindings, this would break, and
     the language would reject valid programs.  That is exactly why the answer
     is a SEMIRING and not "make the language linear". *)
  let gamma = [ ("x", EVal (TWord 2)) ] in
  test "x . x typechecks (a word composed with itself)" (fun () ->
    try ignore (infer_expr gamma [] (BinOp (Compose, Var "x", Var "x"))); true
    with _ -> false);

  test "x . x . x typechecks (three uses)" (fun () ->
    try
      ignore (infer_expr gamma []
                (BinOp (Compose, Var "x", BinOp (Compose, Var "x", Var "x"))));
      true
    with _ -> false)

(* ------------------------------------------------------------------ *)

let () =
  Printf.printf "\n=====================================\n";
  Printf.printf "Results: %d/%d passed\n" !passed (!passed + !failed);
  if !failed > 0 then exit 1
