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

(* Build a node directly, bypassing `derive` — this is how a forgery is made.
   [ctx] is given as plain (name, ty) pairs for brevity; [jf] takes function
   signatures, which T-App needs. *)
let j ctx e t =
  { j_ctx = List.map (fun (n, ty) -> (n, EVal ty)) ctx;
    j_sigma = []; j_expr = e; j_ty = t }
let jf ctx e t = { j_ctx = ctx; j_sigma = []; j_expr = e; j_ty = t }
let js sigma e t = { j_ctx = []; j_sigma = sigma; j_expr = e; j_ty = t }
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

  (* ================================================================== *)
  (*  Rules that used to be DEFERRED                                     *)
  (* ================================================================== *)
  (* Every rule below previously matched a `-> ()` arm: `check` accepted the
     node without re-deriving it, so ANY conclusion passed. Each honest/forged
     pair here is the evidence that the hole is closed — the forged half would
     have passed before. *)

  Printf.printf "\n=== Unary and structural rules (were deferred) ===\n";

  let w2 = BraidLit [sigma 1] in           (* : Word[2] *)
  let dw2 () = n "T-Braid" (j [] w2 (TWord 2)) [] in

  test "honest: T-Mirror on a word keeps the width" (fun () ->
    ok (check (n "T-Mirror" (j [] (Mirror w2) (TWord 2)) [dw2 ()])));

  test "forged: T-Mirror changing the width is rejected" (fun () ->
    rejected (check (n "T-Mirror" (j [] (Mirror w2) (TWord 9)) [dw2 ()])));

  test "forged: T-Reverse on a non-word is rejected" (fun () ->
    rejected (check (n "T-Reverse" (j [] (Reverse (IntLit 1)) TNum)
                       [n "T-Num" (j [] (IntLit 1) TNum) []])));

  test "honest: T-Close yields the closed tangle" (fun () ->
    ok (check (n "T-Close" (j [] (Close w2) (TTangle ([], []))) [dw2 ()])));

  test "forged: T-Close concluding a word is rejected" (fun () ->
    rejected (check (n "T-Close" (j [] (Close w2) (TWord 2)) [dw2 ()])));

  test "forged: T-Simplify changing the type is rejected" (fun () ->
    rejected (check (n "T-Simplify" (j [] (Simplify w2) TNum) [dw2 ()])));

  test "forged: T-Twist on a Num is rejected" (fun () ->
    rejected (check (n "T-Twist" (j [] (Twist (IntLit 1)) TNum)
                       [n "T-Num" (j [] (IntLit 1) TNum) []])));

  test "honest: T-Pipeline composes" (fun () ->
    ok (check (n "T-Pipeline" (j [] (Pipeline (w2, w2)) (TWord 2))
                 [dw2 (); dw2 ()])));

  test "forged: T-Pipeline with a bogus result width is rejected" (fun () ->
    rejected (check (n "T-Pipeline" (j [] (Pipeline (w2, w2)) (TWord 7))
                       [dw2 (); dw2 ()])));

  test "forged: T-Unary negating a Bool is rejected" (fun () ->
    rejected (check (n "T-Unary" (j [] (UnaryOp (Neg, BoolLit true)) TBool)
                       [n "T-Bool" (j [] (BoolLit true) TBool) []])));

  test "forged: T-Echo-Eq on mismatched operands is rejected" (fun () ->
    rejected (check (n "T-Echo-Eq"
                       (j [] (EchoEq (IntLit 1, StringLit "a"))
                          (TEcho (TProd (TNum, TNum), TBool)))
                       [n "T-Num" (j [] (IntLit 1) TNum) [];
                        n "T-Str" (j [] (StringLit "a") TStr) []])));

  Printf.printf "\n=== T-Let: the body must use the binding the let makes ===\n";

  let letexp = Let ("x", IntLit 1, Var "x") in

  test "honest: T-Let concludes the body type" (fun () ->
    ok (check (n "T-Let" (j [] letexp TNum)
                 [n "T-Num" (j [] (IntLit 1) TNum) [];
                  n "T-Var" (j [("x", TNum)] (Var "x") TNum) []])));

  (* The forgery that the type-only check would miss: the body claims `x` is a
     Word, which the let never bound it to. *)
  test "forged: body assumes a different type for the bound variable" (fun () ->
    rejected (check (n "T-Let" (j [] letexp (TWord 2))
                       [n "T-Num" (j [] (IntLit 1) TNum) [];
                        n "T-Var" (j [("x", TWord 2)] (Var "x") (TWord 2)) []])));

  test "forged: T-Let concluding the BOUND type not the body type" (fun () ->
    let e = Let ("x", IntLit 1, BoolLit true) in
    rejected (check (n "T-Let" (j [] e TNum)
                       [n "T-Num" (j [] (IntLit 1) TNum) [];
                        n "T-Bool" (j [] (BoolLit true) TBool) []])));

  Printf.printf "\n=== T-Match: the conclusion is the join of the arms ===\n";

  let marms = [ { arm_pattern = PatWildcard; arm_body = IntLit 1 } ] in
  let mexp  = Match (IntLit 0, marms) in

  test "honest: single-arm match concludes the arm type" (fun () ->
    ok (check (n "T-Match" (j [] mexp TNum)
                 [n "T-Num" (j [] (IntLit 0) TNum) [];
                  n "T-Num" (j [] (IntLit 1) TNum) []])));

  test "forged: match concluding a type no arm has" (fun () ->
    rejected (check (n "T-Match" (j [] mexp TBool)
                       [n "T-Num" (j [] (IntLit 0) TNum) [];
                        n "T-Num" (j [] (IntLit 1) TNum) []])));

  test "forged: match missing an arm premise" (fun () ->
    let two = [ { arm_pattern = PatWildcard; arm_body = IntLit 1 };
                { arm_pattern = PatWildcard; arm_body = IntLit 2 } ] in
    rejected (check (n "T-Match" (j [] (Match (IntLit 0, two)) TNum)
                       [n "T-Num" (j [] (IntLit 0) TNum) [];
                        n "T-Num" (j [] (IntLit 1) TNum) []])));

  Printf.printf "\n=== T-App: checked against the recorded signature ===\n";

  let fsig = EFun { fsig_params = [TNum]; fsig_return = TBool } in
  let callexp = Call ("f", [IntLit 1]) in

  test "honest: call matching the signature" (fun () ->
    ok (check (n "T-App" (jf [("f", fsig)] callexp TBool)
                 [n "T-Num" (j [] (IntLit 1) TNum) []])));

  test "forged: call concluding a type the signature does not return" (fun () ->
    rejected (check (n "T-App" (jf [("f", fsig)] callexp TNum)
                       [n "T-Num" (j [] (IntLit 1) TNum) []])));

  test "forged: argument type does not match the parameter" (fun () ->
    rejected (check (n "T-App" (jf [("f", fsig)] (Call ("f", [BoolLit true])) TBool)
                       [n "T-Bool" (j [] (BoolLit true) TBool) []])));

  test "forged: wrong number of arguments" (fun () ->
    rejected (check (n "T-App" (jf [("f", fsig)] (Call ("f", [])) TBool) [])));

  test "forged: callee absent from the recorded context" (fun () ->
    rejected (check (n "T-App" (jf [] callexp TBool)
                       [n "T-Num" (j [] (IntLit 1) TNum) []])));

  Printf.printf "\n=== T-Crossing / T-Weave: re-derived against Sigma ===\n";

  let sq p = { strand_pos = p; strand_ty = StrandNamed "Q" } in
  let sg = [ ("a", sq 1); ("b", sq 2) ] in
  let cr = Crossing ("a", Over, "b") in
  let qq = [StrandNamed "Q"; StrandNamed "Q"] in

  test "honest: crossing derived and checked in a strand context" (fun () ->
    ok (check (derive_in [] sg cr)));

  test "honest: hand-built crossing node against Sigma" (fun () ->
    ok (check (n "T-Crossing" (js sg cr (TTangle (qq, qq))) [])));

  test "forged: crossing concluding a word" (fun () ->
    rejected (check (n "T-Crossing" (js sg cr (TWord 2)) [])));

  test "forged: crossing naming a strand not in Sigma" (fun () ->
    rejected (check (n "T-Crossing"
                       (js [("a", sq 1)] cr (TTangle (qq, qq))) [])));

  let mkweave ins body outs =
    let st nm = { strand_name = nm; strand_type = Some "Q" } in
    Weave { weave_inputs = List.map st ins;
            weave_body = body;
            weave_outputs = List.map st outs } in

  test "honest: a permutation weave derives and checks" (fun () ->
    ok (check (derive [] (mkweave ["a"; "b"] cr ["b"; "a"]))));

  (* The graph cannot launder a linearity violation: T-Weave re-runs the same
     strand check the typechecker does. *)
  test "forged: weave node duplicating a strand is rejected" (fun () ->
    let bad = mkweave ["a"; "b"] cr ["a"; "b"; "a"] in
    rejected (check (n "T-Weave" (j [] bad (TTangle (qq, qq @ [StrandNamed "Q"]))) [])));

  test "forged: weave node dropping a strand is rejected" (fun () ->
    let bad = mkweave ["a"; "b"] cr ["a"] in
    rejected (check (n "T-Weave" (j [] bad (TTangle (qq, [StrandNamed "Q"]))) [])));

  Printf.printf "\n=== Coverage: the remaining hole is reported, not hidden ===\n";

  test "a fully-derived ordinary program leaves NO unchecked nodes" (fun () ->
    (* Exercises T-Let, T-Var, T-Mirror, T-Braid and T-Close in one graph —
       four of the five were deferred until now. *)
    let prog = Let ("x", w2, Close (Mirror (Var "x"))) in
    let d = derive [] prog in
    ok (check d) && unchecked d = []);

  test "T-Add-Block is reported as unchecked rather than silently accepted" (fun () ->
    let d = n "T-Add-Block" (j [] (IntLit 0) TNum) [] in
    (* it does not FAIL the check ... *)
    ok (check d)
    (* ... but it is visibly not re-derived *)
    && List.map fst (unchecked d) = ["T-Add-Block"]);

  test "an unknown rule name is still an error, not an unchecked node" (fun () ->
    rejected (check (n "T-Nonsense" (j [] (IntLit 0) TNum) [])));

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
