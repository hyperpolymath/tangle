(* SPDX-License-Identifier: MPL-2.0 *)
(* tg5_invariants.ml — TG-5 structural-invariant property test for the
 * compositional PD lowering (compiler/lib/compositional.ml).
 *
 * compositional.ml is the rewriter that lowers a braid-word `expr` to the
 * planar-diagram IR (PDv1).  It sits BELOW the Tangle type layer (it has no
 * Ty), so "the rewriter preserves types" (TG-5) is realised here as: `compile`
 * preserves the structural invariants that make a lowering well-formed, plus
 * the echo residue-recovery property (the OCaml analogue of the Lean
 * `echo_residue_recovers` capstone).  Concretely, over an enumerated corpus we
 * assert ONLY invariants the code actually guarantees (no arc-balance /
 * planarity / topology claims the lowering does not make):
 *
 *   OpenWord w        : w is unit-expanded (all |exp| = 1); |w| = unit count;
 *                       word_of_compiled = Some w.
 *   ClosedDiagram pd  : pd.closed; pd.components = []; pd.source_word = Some w
 *                       with w unit-expanded; |pd.crossings| = |w| = unit count;
 *                       word_of_compiled = pd.source_word.
 *   EchoClosed {r;d}  : d is the SAME diagram as plain `close` of the same body
 *                       (pdv1-identical → consumers unaffected); the residue r
 *                       is VERBATIM (exponents preserved, NOT unit-expanded);
 *                       unit_expand(r) = d.source_word; word_of_compiled = Some r.
 *
 * The headline TG-5/echo property: echoClose(braid[s1^3]) keeps residue s1^3
 * (length 1, exponent 3) while its diagram is the unit-expanded 3-crossing
 * closure — residue and diagram-word are deliberately different shapes, and the
 * residue is the recoverable witness.
 *
 * Modes (mirroring compiler/test/tg3):
 *   --check         self-test; exits 1 on any failure (wired into dune runtest).
 *   --emit <path>   human-readable provenance ledger of the corpus + results.
 *)

open Tangle.Compositional

(* ---- helpers ---- *)

let mk i e : generator = { index = i; exponent = e }
let s1 = mk 1 1
let s2 = mk 2 1
let s1i = mk 1 (-1)
let s2i = mk 2 (-1)

(* unit-expanded crossing count, computed INDEPENDENTLY of word_of_expr
   (sum of |exponent| over every generator; compose/tensor concatenate, close
   is transparent). *)
let rec expected_units (e : expr) : int =
  match e with
  | Identity -> 0
  | Gen g -> abs g.exponent
  | Braid gs -> List.fold_left (fun a g -> a + abs g.exponent) 0 gs
  | Compose (a, b) -> expected_units a + expected_units b
  | Tensor (a, b) -> expected_units a + expected_units b
  | Close x -> expected_units x
  | EchoClose x -> expected_units x

(* our own unit-expansion of a verbatim word, for the residue<->diagram link *)
let unit_expand (w : generator list) : generator list =
  List.concat_map (fun g ->
    let u = if g.exponent > 0 then 1 else -1 in
    List.init (abs g.exponent) (fun _ -> { index = g.index; exponent = u })) w

let contains s sub =
  let ls = String.length s and lsub = String.length sub in
  let rec go i = i + lsub <= ls && (String.sub s i lsub = sub || go (i + 1)) in
  lsub = 0 || go 0

(* ---- test harness ---- *)

let pass = ref 0
let fail = ref 0
let ok name b =
  if b then incr pass
  else begin incr fail; Printf.printf "  FAIL  %s\n" name end

(* ---- generic per-term invariants ---- *)

let check_compiled name (e : expr) =
  match compile e with
  | Error msg -> ok (name ^ ": unexpected compile error: " ^ msg) false
  | Ok (OpenWord w) ->
    ok (name ^ " [open] len = units") (List.length w = expected_units e);
    ok (name ^ " [open] all unit exponents") (List.for_all (fun g -> abs g.exponent = 1) w);
    ok (name ^ " [open] word_of_compiled") (word_of_compiled (OpenWord w) = Some w)
  | Ok (ClosedDiagram pd) ->
    ok (name ^ " [closed] closed flag") pd.closed;
    ok (name ^ " [closed] components empty") (pd.components = []);
    ok (name ^ " [closed] crossings = units") (List.length pd.crossings = expected_units e);
    (match pd.source_word with
     | Some w ->
       ok (name ^ " [closed] source unit-expanded") (List.for_all (fun g -> abs g.exponent = 1) w);
       ok (name ^ " [closed] crossings = |source|") (List.length pd.crossings = List.length w)
     | None -> ok (name ^ " [closed] has source_word") false);
    ok (name ^ " [closed] word_of_compiled = source")
      (word_of_compiled (ClosedDiagram pd) = pd.source_word)
  | Ok (EchoClosed { residue; diagram }) ->
    ok (name ^ " [echo] diagram closed") diagram.closed;
    ok (name ^ " [echo] diagram components empty") (diagram.components = []);
    ok (name ^ " [echo] crossings = units") (List.length diagram.crossings = expected_units e);
    ok (name ^ " [echo] word_of_compiled = residue")
      (word_of_compiled (EchoClosed { residue; diagram }) = Some residue);
    (match diagram.source_word with
     | Some w ->
       (* the residue, unit-expanded, reconstructs the diagram's unit word *)
       ok (name ^ " [echo] expand(residue) = diagram word") (unit_expand residue = w)
     | None -> ok (name ^ " [echo] diagram has source_word") false)

(* ---- corpus ---- *)

let words = [
  "empty",        ([] : generator list);
  "s1",           [s1];
  "s1inv",        [s1i];
  "s2",           [s2];
  "s1.s2",        [s1; s2];
  "s1.s2.s1",     [s1; s2; s1];
  "s1^2",         [mk 1 2];
  "s1^3",         [mk 1 3];
  "s1^-2",        [mk 1 (-2)];
  "s1.s2^-1.s1",  [s1; s2i; s1];
  "s2^2.s1",      [mk 2 2; s1];
]

let corpus () =
  (* OpenWord terms: braid of each word + a few compose/tensor combinations *)
  List.iter (fun (n, gs) -> check_compiled ("open braid[" ^ n ^ "]") (braid gs)) words;
  check_compiled "open compose(s1,s2)" (compose (braid [s1]) (braid [s2]));
  check_compiled "open tensor(s1,s1)"  (tensor  (braid [s1]) (braid [s1]));
  check_compiled "open compose(gen1,gen1^2)" (compose (gen 1) (gen ~exponent:2 1));
  check_compiled "open tensor(s1.s2, s1)" (tensor (braid [s1; s2]) (braid [s1]));
  (* ClosedDiagram terms: close of each word (empty -> empty closed diagram) *)
  List.iter (fun (n, gs) -> check_compiled ("close braid[" ^ n ^ "]") (close (braid gs))) words;
  check_compiled "close compose(s1,s2)" (close (compose (braid [s1]) (braid [s2])));
  (* EchoClosed terms: echo_close of each word *)
  List.iter (fun (n, gs) -> check_compiled ("echo braid[" ^ n ^ "]") (echo_close (braid gs))) words

(* ---- headline echo residue-recovery property ---- *)

let test_verbatim_residue () =
  let inner = braid [mk 1 3] in
  (match compile (echo_close inner) with
   | Ok (EchoClosed { residue; diagram }) ->
     ok "verbatim: residue = [s1^3] (exponents preserved)" (residue = [mk 1 3]);
     ok "verbatim: residue length 1 (NOT unit-expanded)" (List.length residue = 1);
     ok "verbatim: diagram word unit-expanded (length 3)"
       (match diagram.source_word with Some w -> List.length w = 3 | None -> false);
     ok "verbatim: diagram has 3 crossings" (List.length diagram.crossings = 3);
     ok "verbatim: expand(residue) = diagram word"
       (match diagram.source_word with Some w -> unit_expand residue = w | None -> false);
     (match compile (close inner) with
      | Ok (ClosedDiagram pd) ->
        ok "verbatim: echo diagram = plain close diagram (pdv1-identical)"
          (pdv1_blob_of_pd diagram = pdv1_blob_of_pd pd)
      | _ -> ok "verbatim: close(s1^3) compiles to ClosedDiagram" false)
   | _ -> ok "verbatim: echoClose(s1^3) is EchoClosed" false);
  (* a mixed-exponent residue is also verbatim *)
  (match compile (echo_close (braid [s1; mk 2 2; s1i])) with
   | Ok (EchoClosed { residue; diagram }) ->
     ok "verbatim: mixed residue preserved" (residue = [s1; mk 2 2; s1i]);
     ok "verbatim: mixed expand(residue) = diagram word"
       (match diagram.source_word with Some w -> unit_expand residue = w | None -> false)
   | _ -> ok "verbatim: mixed echoClose is EchoClosed" false)

(* ---- error paths (message-pinned to the intended branch) ---- *)

let test_errors () =
  let is_err name pat e =
    match compile e with
    | Error m -> ok ("error " ^ name) (contains m pat)
    | Ok _ -> ok ("error " ^ name ^ " (expected failure)") false
  in
  is_err "zero exponent"   "zero exponent" (gen ~exponent:0 1);
  is_err "index < 1"       "index"         (gen 0);
  is_err "nested close"    "nested"        (close (close (braid [s1; s2])));
  is_err "nested echo"     "nested"        (close (echo_close (braid [s1; s2])))

(* ---- concrete count pins ---- *)

let crossings_of e = match compile e with Ok (ClosedDiagram pd) -> List.length pd.crossings | _ -> -1

let test_count_pins () =
  ok "count: close(identity) = 0"      (crossings_of (close identity) = 0);
  ok "count: close(s1^3) = 3"          (crossings_of (close (braid [mk 1 3])) = 3);
  ok "count: close(s1.s2.s1) = 3"      (crossings_of (close (braid [s1; s2; s1])) = 3);
  ok "count: close(s1^2) = 2"          (crossings_of (close (braid [mk 1 2])) = 2);
  ok "count: open braid[s1^3] = [s1;s1;s1]"
    (word_of_compiled (Result.get_ok (compile (braid [mk 1 3]))) = Some [s1; s1; s1])

(* ---- emit (provenance ledger) ---- *)

let render_compiled e =
  match compile e with
  | Error m -> "ERROR " ^ m
  | Ok (OpenWord w) -> Printf.sprintf "OpenWord(len=%d)" (List.length w)
  | Ok (ClosedDiagram pd) -> Printf.sprintf "ClosedDiagram(crossings=%d)" (List.length pd.crossings)
  | Ok (EchoClosed { residue; diagram }) ->
    Printf.sprintf "EchoClosed(residue_len=%d, crossings=%d)"
      (List.length residue) (List.length diagram.crossings)

let emit path =
  let oc = open_out path in
  Printf.fprintf oc "# TG-5 compositional PD lowering — provenance ledger\n";
  Printf.fprintf oc "# GENERATED by compiler/test/tg5/tg5_invariants.ml --emit. Not a Lean file.\n\n";
  List.iter (fun (n, gs) ->
    Printf.fprintf oc "braid[%s]      -> %s\n" n (render_compiled (braid gs));
    Printf.fprintf oc "close[%s]      -> %s\n" n (render_compiled (close (braid gs)));
    Printf.fprintf oc "echoClose[%s]  -> %s\n" n (render_compiled (echo_close (braid gs)))) words;
  close_out oc;
  Printf.printf "TG-5: wrote provenance ledger to %s\n" path

(* ---- entry ---- *)

let check () =
  corpus ();
  test_verbatim_residue ();
  test_errors ();
  test_count_pins ();
  Printf.printf "TG-5 self-check: %d passed, %d failed\n" !pass !fail;
  if !fail > 0 then exit 1

let () =
  match Array.to_list Sys.argv with
  | _ :: "--emit" :: path :: _ -> emit path
  | _ :: "--check" :: _ | [_] -> check ()
  | _ -> prerr_endline "usage: tg5_invariants (--check | --emit <path>)"; exit 2
