(* SPDX-License-Identifier: MPL-2.0 *)
(* test_check.ml — Tests for the shared diagnostic source (Tangle.Check).
 *
 * This is the OCaml half of the TG-9 evidence: `check_source` is exactly the
 * set of parse + HasType failures the LSP forwards.  (The Rust half — that the
 * LSP shows precisely this output — lives in tangle-lsp's unit tests.) *)

open Tangle.Check

let passed = ref 0
let failed = ref 0
let total  = ref 0

let test name f =
  incr total;
  try
    if f () then begin incr passed; Printf.printf "  PASS  %s\n" name end
    else begin incr failed; Printf.printf "  FAIL  %s\n" name end
  with exn ->
    incr failed;
    Printf.printf "  FAIL  %s (exn: %s)\n" name (Printexc.to_string exn)

(* Does any diagnostic message contain the needle? *)
let mentions needle ds =
  List.exists (fun d ->
    let m = d.message and n = String.length needle in
    let h = String.length m in
    let rec scan i = i + n <= h && (String.sub m i n = needle || scan (i + 1)) in
    n = 0 || scan 0) ds

let () =
  Printf.printf "TANGLE Check (diagnostic source) Tests\n";
  Printf.printf "======================================\n";

  Printf.printf "\n=== Valid programs produce no errors ===\n";
  test "valid braid program is clean" (fun () ->
    not (has_error (check_source "def trefoil = close(braid[s1, s1, s1])\n")));
  test "same-width word equality is clean" (fun () ->
    not (has_error (check_source "def ok = braid[s1] == braid[s1]\n")));
  test "echo program is clean" (fun () ->
    not (has_error (check_source "def e = echoClose(braid[s1])\n")));
  test "bool equality is clean (extra-core)" (fun () ->
    not (has_error (check_source "def b = true == false\n")));

  Printf.printf "\n=== Type errors are reported ===\n";
  test "unequal-width word eq is rejected" (fun () ->
    let ds = check_source "def bad = braid[s1] == braid[s1, s2]\n" in
    has_error ds && mentions "width" ds);
  test "add of word and num is rejected" (fun () ->
    has_error (check_source "def bad = braid[s1] + 3\n"));

  Printf.printf "\n=== Parse errors are reported ===\n";
  test "empty body is a parse error" (fun () ->
    has_error (check_source "def x = \n"));
  test "unbalanced bracket is a parse error" (fun () ->
    has_error (check_source "def x = braid[s1\n"));

  Printf.printf "\n=== Diagnostics carry locations / format ===\n";
  test "parse error has a source line" (fun () ->
    let ds = check_source "def a = braid[s1]\ndef x = \n" in
    List.exists (fun d -> d.level = Error && d.line >= 1) ds);
  test "format_diag is tab-separated with 4 fields" (fun () ->
    let line = format_diag { level = Error; line = 3; col = 5; message = "boom" } in
    String.split_on_char '\t' line = ["ERROR"; "3"; "5"; "boom"]);

  Printf.printf "\n======================================\n";
  Printf.printf "Results: %d/%d passed" !passed !total;
  if !failed > 0 then Printf.printf " (%d FAILED)" !failed;
  Printf.printf "\n";
  if !failed > 0 then exit 1
