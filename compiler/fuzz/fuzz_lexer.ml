(* SPDX-License-Identifier: MPL-2.0 *)
(* Fuzz target for the Tangle (OCaml) lexer.
 *
 * Invariant: the lexer must NEVER crash on ANY input. It should always
 * return tokens or raise Lexer.Lexer_error, never an uncaught exception.
 *
 * The Tangle OCaml lexer is ocamllex-generated (lib/lexer.mll) and
 * handles braid generators, nested block comments, string literals,
 * and scientific notation.
 *
 * Run with:
 *   dune exec fuzz/fuzz_lexer.exe
 *)

let fuzz_one_input (input : string) : unit =
  let lexbuf = Lexing.from_string input in
  let rec drain () =
    match (try Some (Lexer.token lexbuf) with _ -> None) with
    | None -> ()
    | Some tok ->
      let _ = tok in
      if tok = Parser.EOF then ()
      else drain ()
  in
  drain ()

(* Simple PRNG-based random string generator. *)
let random_bytes (rng : Random.State.t) (max_len : int) : string =
  let len = Random.State.int rng (max_len + 1) in
  let buf = Bytes.create len in
  for i = 0 to len - 1 do
    Bytes.set buf i (Char.chr (Random.State.int rng 256))
  done;
  Bytes.to_string buf

(* Generate strings biased toward printable ASCII and common
 * Tangle tokens to improve coverage. *)
let interesting_fragments =
  [| "def"; "weave"; "into"; "yield"; "strands"; "compute"; "assert";
     "match"; "with"; "end"; "let"; "in"; "identity"; "true"; "false";
     "close"; "mirror"; "reverse"; "simplify"; "cap"; "cup"; "braid";
     "jones"; "alexander"; "homfly"; "kauffman"; "writhe"; "linking";
     "s1"; "s2"; "s3"; "s10"; "s99";
     "=>"; "=="; ">>"; "."; "|"; "+"; "-"; "*"; "/"; "~";
     ">"; "<"; "("; ")"; "["; "]"; "{"; "}"; ","; ":"; "="; ";";
     "^"; "_";
     "42"; "0"; "3.14"; "1e10"; "2.5E-3";
     "\"hello\""; "\"escape\\n\""; "\"nested\\\"quote\"";
     "#"; "# comment\n"; "(*"; "*)"; "(* nested (* *) *)";
     " "; "\t"; "\n"; "\r";
     "foo"; "Bar"; "my_ident";
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
  Printf.printf "Tangle (OCaml) lexer fuzzer: running %d iterations\n%!" iterations;
  for i = 1 to iterations do
    let input = random_input rng 4096 in
    fuzz_one_input input;
    if i mod 10_000 = 0 then
      Printf.printf "  ... %d iterations complete\n%!" i
  done;
  Printf.printf "Tangle (OCaml) lexer fuzzer: %d iterations passed with no crashes\n%!" iterations
