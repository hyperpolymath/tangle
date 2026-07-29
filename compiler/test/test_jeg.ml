(* SPDX-License-Identifier: MPL-2.0 *)
(* test_jeg.ml — Judgement Evidence Graph.
 *
 * The tests that matter here are the FORGERY ones.  A derivation that is only
 * ever produced by `derive` and then trusted is a log; it becomes evidence
 * only if `check` rejects graphs that `derive` would never have produced.  So
 * each forgery test hand-builds an ill-founded derivation and asserts it is
 * caught.
 *)

open Tangle.Ast
open Tangle.Typecheck
open Tangle.Jeg

let passed = ref 0
let failed = ref 0

let test name f =
  (try
     if f () then begin incr passed; Printf.printf "  PASS  %s\n" name end
     else begin incr failed; Printf.printf "  FAIL  %s\n" name end
   with e ->
     incr failed;
     Printf.printf "  FAIL  %s (%s)\n" name (Printexc.to_string e))

let gen i e = { gen_index = i; gen_exponent = e }
let sigma i = gen i 1

let ok = function Ok () -> true | Error _ -> false
let rejected = function Ok () -> false | Error _ -> true

(* Build a node directly, bypassing `derive` — this is how a forgery is made. *)
let j ctx e t = { j_ctx = ctx; j_expr = e; j_ty = t }
let n rule concl prems = { d_rule = rule; d_conclusion = concl; d_premises = prems }

(* ================================================================== *)

let () =
  Printf.printf "TANGLE Judgement Evidence Graph Tests\n";
  Printf.printf "=====================================\n";

  Printf.printf "\n=== Derivations are produced and self-check ===\n";

  test "literal derivation checks" (fun () ->
    ok (check (derive [] (IntLit 42))));

  test "braid literal records the right width" (fun () ->
    let d = derive [] (BraidLit [sigma 1; sigma 2]) in
    d.d_conclusion.j_ty = TWord 3 && ok (check d));

  test "compound derivation checks" (fun () ->
    ok (check (derive [] (BinOp (Compose, BraidLit [sigma 1], BraidLit [sigma 2])))));

  test "echo derivation checks" (fun () ->
    ok (check (derive [] (Residue (EchoClose (BraidLit [sigma 1]))))));

  test "epistemic derivation checks" (fun () ->
    ok (check (derive [] (Evidence (Warrant (0, IntLit 42, BraidLit [sigma 1]))))));

  test "premises are recorded, not flattened" (fun () ->
    let d = derive [] (BinOp (Compose, BraidLit [sigma 1], BraidLit [sigma 2])) in
    List.length d.d_premises = 2 && size d = 3 && depth d = 2);

  Printf.printf "\n=== Forgeries are REJECTED (this is what makes it evidence) ===\n";

  test "forged: literal claiming the wrong type" (fun () ->
    (* `42 : Str` under T-Num. *)
    rejected (check (n "T-Num" (j [] (IntLit 42) TStr) [])));

  test "forged: braid claiming the wrong width" (fun () ->
    (* braid[s1] is Word[2]; claim Word[9]. *)
    rejected (check (n "T-Braid" (j [] (BraidLit [sigma 1]) (TWord 9)) [])));

  test "forged: axiom given premises it should not have" (fun () ->
    rejected (check (n "T-Num" (j [] (IntLit 1) TNum)
                       [n "T-Num" (j [] (IntLit 2) TNum) []])));

  test "forged: variable not in the recorded context" (fun () ->
    rejected (check (n "T-Var" (j [] (Var "nope") TNum) [])));

  test "forged: compose whose premises do not license it" (fun () ->
    (* Word[2] . Word[3] is Word[3]; claim Num. *)
    rejected (check (n "T-Compose"
                       (j [] (BinOp (Compose, BraidLit [sigma 1], BraidLit [sigma 2])) TNum)
                       [n "T-Braid" (j [] (BraidLit [sigma 1]) (TWord 2)) [];
                        n "T-Braid" (j [] (BraidLit [sigma 2]) (TWord 3)) []])));

  test "forged: residue projecting a non-echo" (fun () ->
    rejected (check (n "T-Residue" (j [] (Residue (IntLit 1)) TNum)
                       [n "T-Num" (j [] (IntLit 1) TNum) []])));

  test "forged: unknown rule name" (fun () ->
    rejected (check (n "T-Nonsense" (j [] (IntLit 1) TNum) [])));

  test "forged: truncated derivation (premise removed)" (fun () ->
    rejected (check (n "T-Compose"
                       (j [] (BinOp (Compose, BraidLit [sigma 1], BraidLit [sigma 2])) (TWord 3))
                       [n "T-Braid" (j [] (BraidLit [sigma 1]) (TWord 2)) []])));

  Printf.printf "\n=== TG-11: the graph refuses to assert factivity ===\n";

  test "forged: T-Evidence concluding the CLAIM type is rejected" (fun () ->
    (* THE test. A warrant with evidence Word[2] for a claim Num. A forger
       wants `evidence(w) : Num` — the claim — which would make the warrant
       factive. No rule licenses it, so the graph must refuse. *)
    let w = Warrant (0, IntLit 42, BraidLit [sigma 1]) in
    let epi = TEpi (0, TWord 2, TNum) in
    rejected (check (n "T-Evidence" (j [] (Evidence w) TNum)
                       [n "T-Warrant" (j [] w epi)
                          [n "T-Num" (j [] (IntLit 42) TNum) [];
                           n "T-Braid" (j [] (BraidLit [sigma 1]) (TWord 2)) []]])));

  test "honest: T-Evidence concluding the EVIDENCE type is accepted" (fun () ->
    let w = Warrant (0, IntLit 42, BraidLit [sigma 1]) in
    let epi = TEpi (0, TWord 2, TNum) in
    ok (check (n "T-Evidence" (j [] (Evidence w) (TWord 2))
                 [n "T-Warrant" (j [] w epi)
                    [n "T-Num" (j [] (IntLit 42) TNum) [];
                     n "T-Braid" (j [] (BraidLit [sigma 1]) (TWord 2)) []]])));

  test "forged: warrant claiming the wrong standpoint" (fun () ->
    let w = Warrant (0, IntLit 42, BraidLit [sigma 1]) in
    rejected (check (n "T-Warrant" (j [] w (TEpi (7, TWord 2, TNum)))
                       [n "T-Num" (j [] (IntLit 42) TNum) [];
                        n "T-Braid" (j [] (BraidLit [sigma 1]) (TWord 2)) []])));

  Printf.printf "\n=== Rendering ===\n";

  test "to_string shows rule names and judgements" (fun () ->
    let s = to_string (derive [] (BinOp (Compose, BraidLit [sigma 1], Identity))) in
    let has sub =
      let n = String.length sub in
      let rec go i = i + n <= String.length s && (String.sub s i n = sub || go (i+1)) in
      go 0
    in
    has "T-Compose" && has "T-Identity" && has "|-");

  test "to_dot emits a graph" (fun () ->
    let s = to_dot (derive [] (BinOp (Compose, BraidLit [sigma 1], Identity))) in
    String.length s > 40
    && String.sub s 0 7 = "digraph");

  Printf.printf "\n=====================================\n";
  Printf.printf "Results: %d/%d passed" !passed (!passed + !failed);
  if !failed > 0 then Printf.printf " (%d FAILED)" !failed;
  print_newline ();
  if !failed > 0 then exit 1
