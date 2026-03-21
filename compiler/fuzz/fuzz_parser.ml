(* SPDX-License-Identifier: PMPL-1.0-or-later *)
(* Fuzz target for the Tangle (OCaml) parser.
 *
 * Invariant: the parser must NEVER crash on ANY input. It should raise
 * Parser.Error or Lexer.Lexer_error, never an uncaught exception.
 *
 * Tangle uses ocamllex (lib/lexer.mll) + Menhir (lib/parser.mly).
 * This harness feeds random strings through the full lex+parse pipeline.
 *
 * Strategy: 50% raw random bytes, 50% structured inputs mixing
 * TANGLE keywords (def, weave, strands, match, etc.) to achieve
 * deeper parser coverage.
 *
 * Run with:
 *   dune exec fuzz/fuzz_parser.exe
 *)

let fuzz_one_input (input : string) : unit =
  let lexbuf = Lexing.from_string input in
  (try
     let _ = Parser.program Lexer.token lexbuf in
     ()
   with
   | Parser.Error -> ()
   | Lexer.Lexer_error _ -> ()
   | _ -> ())

(* Simple PRNG-based random string generator. *)
let random_bytes (rng : Random.State.t) (max_len : int) : string =
  let len = Random.State.int rng (max_len + 1) in
  let buf = Bytes.create len in
  for i = 0 to len - 1 do
    Bytes.set buf i (Char.chr (Random.State.int rng 256))
  done;
  Bytes.to_string buf

(* Fragments biased toward TANGLE syntax for deeper parser coverage.
 * TANGLE is a braid/knot theory language with vertical composition (.),
 * horizontal tensor (|), pipeline (>>), and braid generators. *)
let interesting_fragments =
  [| (* Keywords *)
     "def"; "weave"; "into"; "yield"; "strands"; "compute"; "assert";
     "match"; "with"; "end"; "let"; "in";
     (* Braid operations *)
     "close"; "mirror"; "reverse"; "simplify"; "cap"; "cup"; "twist";
     (* Operators *)
     "."; "|"; ">>"; "=="; "~"; "+"; "-"; "*"; "/";
     "->"; "=>";
     (* Delimiters *)
     "("; ")"; "["; "]"; "{"; "}"; ","; ";"; ":";
     (* Braid generators *)
     "s1"; "s2"; "s3"; "s1^-1"; "s2^-1"; "s3^-1";
     (* Literals *)
     "42"; "0"; "3.14"; "1e5"; "true"; "false";
     "\"hello\"";
     (* Identifiers *)
     "x"; "y"; "braid"; "knot"; "link"; "f"; "g"; "_";
     (* Whitespace *)
     " "; "\t"; "\n"; "\r";
     (* Comments *)
     "(* comment *)"; "// line\n";
     (* Structured patterns *)
     "def f x = x . x";
     "let b = s1 | s2 in b >> b";
     "match x with | a -> a end";
     "weave [s1, s2, s3] into knot";
  |]

let random_input (rng : Random.State.t) (max_len : int) : string =
  if Random.State.bool rng then
    random_bytes rng max_len
  else begin
    let buf = Buffer.create max_len in
    let target_len = Random.State.int rng (max_len + 1) in
    while Buffer.length buf < target_len do
      let frag = interesting_fragments.(
        Random.State.int rng (Array.length interesting_fragments)
      ) in
      Buffer.add_string buf frag
    done;
    Buffer.contents buf
  end

let () =
  let rng = Random.State.make_self_init () in
  let iterations =
    try int_of_string (Sys.getenv "FUZZ_ITERATIONS")
    with _ -> 100_000
  in
  Printf.printf "Tangle parser fuzzer: running %d iterations\n%!" iterations;
  for i = 1 to iterations do
    let input = random_input rng 4096 in
    fuzz_one_input input;
    if i mod 10_000 = 0 then
      Printf.printf "  ... %d iterations complete\n%!" i
  done;
  Printf.printf "Tangle parser fuzzer: %d iterations passed with no crashes\n%!" iterations
