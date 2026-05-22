(* SPDX-License-Identifier: MPL-2.0 *)
(* test_compositional.ml — Tests for compositional TANGLE -> PD compiler. *)

open Tangle.Compositional

let passed = ref 0
let failed = ref 0
let total = ref 0

let test name f =
  incr total;
  try
    f ();
    incr passed;
    Printf.printf "  PASS: %s\n" name
  with exn ->
    incr failed;
    Printf.printf "  FAIL: %s (%s)\n" name (Printexc.to_string exn)

let assert_true label b =
  if not b then failwith ("assert_true failed: " ^ label)

let assert_eq label expected actual =
  if expected <> actual then
    failwith ("assert_eq failed: " ^ label)

let unwrap = function
  | Ok x -> x
  | Error msg -> failwith ("unexpected error: " ^ msg)

let unwrap_error = function
  | Ok _ -> failwith "expected error"
  | Error msg -> msg

let test_builder_and_compile () =
  Printf.printf "\n--- Builder + compile ---\n";
  test "trefoil close compiles to 3-crossing PD" (fun () ->
    let e =
      close
        (compose
           (gen 1)
           (compose (gen 1) (gen 1)))
    in
    match unwrap (compile e) with
    | ClosedDiagram pd ->
      assert_eq "crossing count" 3 (List.length pd.crossings);
      assert_true "closed" pd.closed
    | OpenWord _ ->
      failwith "expected ClosedDiagram");

  test "figure-eight close compiles to 4-crossing PD" (fun () ->
    let e =
      close
        (braid [
           { index = 1; exponent = 1 };
           { index = 2; exponent = -1 };
           { index = 1; exponent = 1 };
           { index = 2; exponent = -1 };
         ])
    in
    match unwrap (compile e) with
    | ClosedDiagram pd ->
      assert_eq "crossing count" 4 (List.length pd.crossings)
    | OpenWord _ ->
      failwith "expected ClosedDiagram")

let test_compositional_semantics () =
  Printf.printf "\n--- Composition + tensor semantics ---\n";
  test "compose concatenates braid words" (fun () ->
    let e = compose (braid [{ index = 1; exponent = 1 }]) (braid [{ index = 2; exponent = 1 }]) in
    match unwrap (compile e) with
    | OpenWord w ->
      assert_eq "word length" 2 (List.length w);
      assert_eq "g1 index" 1 (List.nth w 0).index;
      assert_eq "g2 index" 2 (List.nth w 1).index
    | ClosedDiagram _ ->
      failwith "expected OpenWord");

  test "tensor offsets right word by left width" (fun () ->
    let e = tensor (braid [{ index = 1; exponent = 1 }]) (braid [{ index = 1; exponent = 1 }]) in
    match unwrap (compile e) with
    | OpenWord w ->
      assert_eq "word length" 2 (List.length w);
      assert_eq "left index" 1 (List.nth w 0).index;
      assert_eq "shifted right index" 3 (List.nth w 1).index
    | ClosedDiagram _ ->
      failwith "expected OpenWord")

let test_parser_adapter () =
  Printf.printf "\n--- Parser adapter ---\n";
  test "parse + compile trefoil expression" (fun () ->
    match unwrap (compile_source_expr "close(braid[s1, s1, s1])") with
    | ClosedDiagram pd ->
      assert_eq "crossing count" 3 (List.length pd.crossings)
    | OpenWord _ ->
      failwith "expected ClosedDiagram");

  test "parse rejects non-compositional expression" (fun () ->
    let msg = unwrap_error (parse_expr "let x = braid[s1] in x") in
    assert_true "error mentions subset"
      (String.length msg > 0))

let test_reversibility () =
  Printf.printf "\n--- Reversibility where possible ---\n";
  test "open expression round-trips via word canonical form" (fun () ->
    let c = unwrap (compile_source_expr "braid[s1] | braid[s1] . braid[s2]") in
    let w = match word_of_compiled c with
      | Some x -> x
      | None -> failwith "missing word"
    in
    let e2 = expr_of_word w in
    match unwrap (compile e2) with
    | OpenWord w2 -> assert_eq "round-trip word" w w2
    | ClosedDiagram _ -> failwith "expected OpenWord");

  test "closed expression retains source word for recovery" (fun () ->
    let c = unwrap (compile_source_expr "close(braid[s1, s2^-1, s1])") in
    let w = match word_of_compiled c with
      | Some x -> x
      | None -> failwith "missing source word"
    in
    assert_eq "source word size" 3 (List.length w))

let test_skein_hooks () =
  Printf.printf "\n--- Skein hooks (pure payload) ---\n";
  test "compile_and_send_to_skein emits canonical pdv1 payload" (fun () ->
    let captured = ref None in
    let sink payload = captured := Some payload in
    let _payload =
      unwrap
        (compile_and_send_to_skein sink
           ~name:"trefoil"
           (close (braid [
                { index = 1; exponent = 1 };
                { index = 1; exponent = 1 };
                { index = 1; exponent = 1 };
              ])))
    in
    match !captured with
    | None -> failwith "sink not called"
    | Some payload ->
      assert_eq "name" "trefoil" payload.name;
      assert_eq "crossings" 3 payload.crossing_number;
      assert_true "pdv1 prefix"
        (String.length payload.pd_blob >= 5 &&
         String.sub payload.pd_blob 0 5 = "pdv1|");
      assert_eq "entry count" 3 (List.length payload.pd_entries));

  test "Skein hook rejects open word" (fun () ->
    let sink _ = () in
    let msg =
      unwrap_error
        (compile_and_send_to_skein sink
           ~name:"open_word"
           (braid [{ index = 1; exponent = 1 }]))
    in
    assert_true "reject open"
      (String.length msg > 0))

let () =
  Printf.printf "=== test_compositional.ml ===\n";
  test_builder_and_compile ();
  test_compositional_semantics ();
  test_parser_adapter ();
  test_reversibility ();
  test_skein_hooks ();

  Printf.printf "\n=== Summary ===\n";
  Printf.printf "Total:  %d\n" !total;
  Printf.printf "Passed: %d\n" !passed;
  Printf.printf "Failed: %d\n" !failed;

  if !failed > 0 then exit 1 else exit 0

