(* SPDX-License-Identifier: PMPL-1.0-or-later *)
(* bench_lexer.ml -- Lexer performance benchmark for TANGLE (OCaml frontend)
 *
 * Measures:
 *   - Tokens per second on synthetic source (10K+ tokens)
 *   - Time to lex an empty file vs a large file
 *   - Average allocation per token (via Gc stats)
 *
 * Run:
 *   dune exec bench/bench_lexer.exe
 *)

(** Generate a realistic TANGLE source string with braid operations. *)
let generate_source ~num_statements =
  let buf = Buffer.create (num_statements * 80) in
  let keywords = [|
    "def"; "weave"; "into"; "yield"; "strands"; "compute"; "assert";
    "match"; "with"; "end"; "let"; "in"; "identity"; "true"; "false";
    "close"; "mirror"; "reverse"; "simplify"; "cap"; "cup"; "braid";
    "jones"; "alexander"; "homfly"; "kauffman"; "writhe"; "linking"
  |] in
  let operators = [|
    "=>"; "=="; ">>"; "."; "|"; "+"; "-"; "*"; "/"; "~";
    ">"; "<"; "^"; "="; ":"
  |] in
  for i = 0 to num_statements - 1 do
    let kw = keywords.(i mod Array.length keywords) in
    let op = operators.(i mod Array.length operators) in
    Buffer.add_string buf
      (Printf.sprintf "%s knot_%d %s %d;\n" kw i op (i * 5));
    if i mod 8 = 0 then begin
      Buffer.add_string buf "# line comment\n";
      Buffer.add_string buf (Printf.sprintf "s%d " (i mod 9 + 1));
      Buffer.add_string buf (Printf.sprintf "\"braid_%d\" " i);
      Buffer.add_string buf "{ [ ( ) ] } , : _ \n"
    end
  done;
  Buffer.contents buf

(** Count tokens produced by the TANGLE ocamllex lexer. *)
let count_tokens source =
  let lexbuf = Lexing.from_string source in
  let count = ref 0 in
  let continue_ = ref true in
  while !continue_ do
    let tok = Lexer.token lexbuf in
    incr count;
    if tok = Parser.EOF then continue_ := false
  done;
  !count

(** Time a function, returning (result, elapsed_seconds). *)
let time_it f =
  let t0 = Unix.gettimeofday () in
  let result = f () in
  let t1 = Unix.gettimeofday () in
  (result, t1 -. t0)

(** Measure GC allocations around a function call. *)
let measure_alloc f =
  Gc.compact ();
  let stat0 = Gc.stat () in
  let result = f () in
  let stat1 = Gc.stat () in
  let minor_words = stat1.Gc.minor_words -. stat0.Gc.minor_words in
  let major_words = stat1.Gc.major_words -. stat0.Gc.major_words in
  (result, minor_words +. major_words)

let () =
  let iterations = 100 in

  (* --- Benchmark 1: Empty file --- *)
  let (_, empty_time) = time_it (fun () ->
    for _ = 1 to iterations do
      ignore (count_tokens "")
    done
  ) in
  Printf.printf "=== TANGLE (OCaml) Lexer Benchmark ===\n\n";
  Printf.printf "Empty file:\n";
  Printf.printf "  %d iterations in %.4f s (%.2f us/iter)\n"
    iterations empty_time (empty_time /. float_of_int iterations *. 1e6);

  (* --- Generate large source --- *)
  let source = generate_source ~num_statements:2000 in
  let source_bytes = String.length source in
  let token_count = count_tokens source in
  Printf.printf "\nLarge file (%d bytes, %d tokens):\n" source_bytes token_count;

  (* --- Benchmark 2: Tokens/sec on large file --- *)
  let (_, large_time) = time_it (fun () ->
    for _ = 1 to iterations do
      ignore (count_tokens source)
    done
  ) in
  let total_tokens = float_of_int (token_count * iterations) in
  let tokens_per_sec = total_tokens /. large_time in
  Printf.printf "  %d iterations in %.4f s\n" iterations large_time;
  Printf.printf "  %.2f tokens/sec\n" tokens_per_sec;
  Printf.printf "  %.2f us/token\n" (large_time /. total_tokens *. 1e6);
  Printf.printf "  %.2f MB/sec\n"
    (float_of_int (source_bytes * iterations) /. large_time /. 1e6);

  (* --- Benchmark 3: Memory allocation per token --- *)
  let (_, words_allocated) = measure_alloc (fun () ->
    ignore (count_tokens source)
  ) in
  let words_per_token = words_allocated /. float_of_int token_count in
  let bytes_per_token = words_per_token *. float_of_int Sys.word_size /. 8.0 in
  Printf.printf "\nMemory allocation:\n";
  Printf.printf "  %.1f words allocated for %d tokens\n" words_allocated token_count;
  Printf.printf "  %.1f words/token (%.1f bytes/token)\n" words_per_token bytes_per_token;

  Printf.printf "\nDone.\n"
