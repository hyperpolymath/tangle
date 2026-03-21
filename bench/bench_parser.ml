(* SPDX-License-Identifier: PMPL-1.0-or-later *)
(* bench_parser.ml — Parser benchmark harness for Tangle (OCaml/Menhir)
 *
 * Generates a large synthetic Tangle program and measures
 * parse throughput: LOC/sec, total parse time.
 *
 * Tangle syntax: topological/knot-theoretic DSL with def, weave,
 * braid literals, compute invariants, match/with/end, let/in.
 *
 * Usage:  dune exec bench/bench_parser.ml
 *)

open Tangle

(** Generate a synthetic Tangle program. *)
let generate_program num_defs =
  let buf = Buffer.create (num_defs * 300) in
  (* Definition blocks *)
  for i = 0 to num_defs - 1 do
    Buffer.add_string buf (Printf.sprintf "def knot_%d(a, b) = a . b + b . a\n\n" i);
    Buffer.add_string buf (Printf.sprintf "def compose_%d(x, y) = x . y | y . x\n\n" i);
    if i mod 5 = 0 then begin
      (* Weave blocks *)
      Buffer.add_string buf
        (Printf.sprintf "weave strands s%d : wire into\n  s%d . s%d\nyield strands out%d\n\n"
           i i i i)
    end;
    if i mod 8 = 0 then begin
      (* Compute invariant *)
      Buffer.add_string buf (Printf.sprintf "compute jones(knot_%d(1, 2))\n\n" i)
    end;
    if i mod 7 = 0 then begin
      (* Match expression *)
      Buffer.add_string buf (Printf.sprintf "def classify_%d(x) =\n" i);
      Buffer.add_string buf "  match x with\n";
      Buffer.add_string buf "  | identity -> 0\n";
      Buffer.add_string buf (Printf.sprintf "  | y -> %d\n" (i + 1));
      Buffer.add_string buf "  end\n\n"
    end;
    if i mod 6 = 0 then begin
      (* Let expression *)
      Buffer.add_string buf (Printf.sprintf "def bind_%d = let t = %d + %d in t * 2\n\n"
                               i i (i + 1))
    end;
    (* Assert *)
    if i mod 10 = 0 then
      Buffer.add_string buf (Printf.sprintf "assert knot_%d(1, 2) == knot_%d(1, 2)\n\n" i i)
  done;
  Buffer.contents buf

let count_lines s =
  let n = ref 1 in
  String.iter (fun c -> if c = '\n' then incr n) s;
  !n

let () =
  let num_defs = 40 in
  let iterations = 100 in
  let source = generate_program num_defs in
  let loc = count_lines source in

  Printf.printf "=== Tangle (OCaml) Parser Benchmark ===\n";
  Printf.printf "Source: %d LOC, %d bytes\n" loc (String.length source);
  Printf.printf "Iterations: %d\n\n" iterations;

  let parse src =
    let lexbuf = Lexing.from_string src in
    Parser.program Lexer.token lexbuf
  in
  (* Warm up *)
  let _ = parse source in

  let t_start = Unix.gettimeofday () in
  for _ = 1 to iterations do
    let result = parse source in
    ignore (Sys.opaque_identity result)
  done;
  let t_end = Unix.gettimeofday () in

  let total_sec = t_end -. t_start in
  let per_iter = total_sec /. Float.of_int iterations in
  let loc_per_sec = Float.of_int (loc * iterations) /. total_sec in

  Printf.printf "Total parse time : %.4f s\n" total_sec;
  Printf.printf "Time per parse   : %.6f s\n" per_iter;
  Printf.printf "LOC/sec          : %.0f\n" loc_per_sec;
  Printf.printf "Bytes/sec        : %.0f\n"
    (Float.of_int (String.length source * iterations) /. total_sec)
