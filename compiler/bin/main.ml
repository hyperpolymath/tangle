(* SPDX-License-Identifier: MPL-2.0 *)
(* main.ml — CLI entry point for the TANGLE compiler.
 *
 * Reads a .tangle source file, lexes and parses it, then prints the
 * resulting AST using the pretty printer.
 *
 * Usage:
 *   tanglec <file.tangle>          — parse and pretty-print AST
 *   tanglec --dump-tokens <file>   — dump lexer tokens
 *   tanglec --eval <file.tangle>   — evaluate a program
 *   tanglec --repl                 — start interactive REPL
 *)

(** A parse diagnostic with location. *)
type parse_diagnostic = {
  pd_message : string;
  pd_file    : string;
  pd_line    : int;
  pd_column  : int;
}

(** Synchronize the lexer by skipping tokens until a statement keyword is found.
    Returns [true] if EOF was reached. *)
let synchronize_tangle_lexer lexbuf =
  let rec loop () =
    try
      let tok = Tangle.Lexer.token lexbuf in
      match tok with
      | Tangle.Parser.EOF -> true
      | Tangle.Parser.DEF | Tangle.Parser.WEAVE
      | Tangle.Parser.COMPUTE | Tangle.Parser.ASSERT -> false
      | _ -> loop ()
    with
    | Tangle.Lexer.Lexer_error _ -> loop ()
  in
  loop ()

(** Parse a TANGLE source file with error recovery.
    Collects multiple diagnostics and returns a partial AST. *)
let parse_file_recovering (filename : string) : Tangle.Ast.program * parse_diagnostic list =
  let ic = open_in filename in
  let n = in_channel_length ic in
  let source = really_input_string ic n in
  close_in ic;
  let lexbuf = Lexing.from_string source in
  lexbuf.Lexing.lex_curr_p <- {
    lexbuf.Lexing.lex_curr_p with
    Lexing.pos_fname = filename;
    Lexing.pos_lnum = 1;
  };
  let diagnostics = ref [] in
  (* Accumulate SEGMENTS (each a statement list from one parser run), newest
     first, and flatten in order at the end.
     The previous code did `stmts := prog @ !stmts` and then `List.rev !stmts`.
     That reversal is correct for an accumulator built by prepending single
     items — as `diagnostics` is — but here whole segments are prepended, so
     reversing the FLATTENED list reversed the statements themselves. On the
     normal path (one successful parse) every program came out backwards:
     `def x; def y; def z` parsed to [z; y; x], so any program whose statements
     depend on order failed at evaluation with "Unbound variable".
     The test suites never caught it because they call Tangle.Parser.program
     directly; only the CLI goes through this recovering path. *)
  let segments = ref [] in
  let at_eof = ref false in
  while not !at_eof do
    (try
       let prog = Tangle.Parser.program Tangle.Lexer.token lexbuf in
       segments := prog :: !segments;
       at_eof := true
     with
     | Tangle.Lexer.Lexer_error msg ->
       let pos = lexbuf.Lexing.lex_curr_p in
       diagnostics := {
         pd_message = Printf.sprintf "Lexer error: %s" msg;
         pd_file = filename;
         pd_line = pos.Lexing.pos_lnum;
         pd_column = pos.Lexing.pos_cnum - pos.Lexing.pos_bol;
       } :: !diagnostics;
       at_eof := synchronize_tangle_lexer lexbuf
     | Tangle.Parser.Error ->
       let pos = lexbuf.Lexing.lex_curr_p in
       diagnostics := {
         pd_message = "Unexpected token";
         pd_file = filename;
         pd_line = pos.Lexing.pos_lnum;
         pd_column = pos.Lexing.pos_cnum - pos.Lexing.pos_bol;
       } :: !diagnostics;
       at_eof := synchronize_tangle_lexer lexbuf)
  done;
  (* Flatten oldest-segment-first, preserving order WITHIN each segment. *)
  (List.concat (List.rev !segments), List.rev !diagnostics)

(** Parse a TANGLE source file into a program AST. *)
let parse_file (filename : string) : Tangle.Ast.program =
  let (program, diagnostics) = parse_file_recovering filename in
  if diagnostics <> [] then begin
    List.iter (fun d ->
      Printf.eprintf "Parse error in %s at %d:%d: %s\n"
        d.pd_file d.pd_line d.pd_column d.pd_message
    ) diagnostics;
    exit 1
  end;
  program

(** Dump all tokens from a source file (for debugging the lexer). *)
let dump_tokens (filename : string) : unit =
  let ic = open_in filename in
  let n = in_channel_length ic in
  let source = really_input_string ic n in
  close_in ic;
  let lexbuf = Lexing.from_string source in
  lexbuf.Lexing.lex_curr_p <- {
    lexbuf.Lexing.lex_curr_p with
    Lexing.pos_fname = filename;
    Lexing.pos_lnum = 1;
  };
  let open Tangle.Parser in
  let rec loop () =
    let tok = Tangle.Lexer.token lexbuf in
    let pos = lexbuf.Lexing.lex_curr_p in
    Printf.printf "%d:%d  "
      pos.Lexing.pos_lnum
      (pos.Lexing.pos_cnum - pos.Lexing.pos_bol);
    (match tok with
     | DEF         -> print_string "DEF"
     | WEAVE       -> print_string "WEAVE"
     | INTO        -> print_string "INTO"
     | YIELD       -> print_string "YIELD"
     | STRANDS     -> print_string "STRANDS"
     | COMPUTE     -> print_string "COMPUTE"
     | ASSERT      -> print_string "ASSERT"
     | MATCH       -> print_string "MATCH"
     | WITH        -> print_string "WITH"
     | END         -> print_string "END"
     | LET         -> print_string "LET"
     | IN          -> print_string "IN"
     | IDENTITY    -> print_string "IDENTITY"
     | TRUE        -> print_string "TRUE"
     | FALSE       -> print_string "FALSE"
     | CLOSE       -> print_string "CLOSE"
     | MIRROR      -> print_string "MIRROR"
     | REVERSE     -> print_string "REVERSE"
     | SIMPLIFY    -> print_string "SIMPLIFY"
     | CAP         -> print_string "CAP"
     | CUP         -> print_string "CUP"
     | BRAID       -> print_string "BRAID"
     | JONES       -> print_string "JONES"
     | ALEXANDER   -> print_string "ALEXANDER"
     | HOMFLY      -> print_string "HOMFLY"
     | KAUFFMAN    -> print_string "KAUFFMAN"
     | WRITHE      -> print_string "WRITHE"
     | LINKING     -> print_string "LINKING"
     | DOT         -> print_string "DOT"
     | PIPE        -> print_string "PIPE"
     | PLUS        -> print_string "PLUS"
     | MINUS       -> print_string "MINUS"
     | STAR        -> print_string "STAR"
     | SLASH       -> print_string "SLASH"
     | EQEQ        -> print_string "EQEQ"
     | TILDE       -> print_string "TILDE"
     | GTGT        -> print_string "GTGT"
     | GT          -> print_string "GT"
     | LT          -> print_string "LT"
     | LPAREN      -> print_string "LPAREN"
     | RPAREN      -> print_string "RPAREN"
     | LBRACKET    -> print_string "LBRACKET"
     | RBRACKET    -> print_string "RBRACKET"
     | LBRACE      -> print_string "LBRACE"
     | RBRACE      -> print_string "RBRACE"
     | COMMA       -> print_string "COMMA"
     | COLON       -> print_string "COLON"
     | EQ          -> print_string "EQ"
     | ARROW       -> print_string "ARROW"
     | SEMI        -> print_string "SEMI"
     | CARET       -> print_string "CARET"
     | UNDERSCORE  -> print_string "UNDERSCORE"
     | INT n       -> Printf.printf "INT(%d)" n
     | FLOAT f     -> Printf.printf "FLOAT(%g)" f
     | STRING s    -> Printf.printf "STRING(%S)" s
     | IDENT s     -> Printf.printf "IDENT(%s)" s
     | GENERATOR n -> Printf.printf "GENERATOR(%d)" n
     | EOF         -> print_string "EOF"
     | ECHOCLOSE   -> print_string "ECHOCLOSE"
     | LOWER       -> print_string "LOWER"
     | RESIDUE     -> print_string "RESIDUE"
     | PAIR        -> print_string "PAIR"
     | FST         -> print_string "FST"
     | SND         -> print_string "SND"
     | ECHOADD     -> print_string "ECHOADD"
     | ECHOEQ      -> print_string "ECHOEQ"
     | WARRANT     -> print_string "WARRANT"
     | EVIDENCE    -> print_string "EVIDENCE"
     | ADDBRACE    -> print_string "ADDBRACE"
     | IF          -> print_string "IF"
     | THEN        -> print_string "THEN"
     | ELSE        -> print_string "ELSE"
     | AMPAMP      -> print_string "AMPAMP"
     | BARBAR      -> print_string "BARBAR"
     | BANGEQ      -> print_string "BANGEQ"
     | LE          -> print_string "LE"
     | GE          -> print_string "GE"
     | PERCENT     -> print_string "PERCENT"
     | BANG        -> print_string "BANG");
    print_newline ();
    if tok <> EOF then loop ()
  in
  try loop ()
  with Tangle.Lexer.Lexer_error msg ->
    Printf.eprintf "Lexer error in %s: %s\n" filename msg;
    exit 1

(** Emit the judgement evidence graph for each definition in a file.
    Every graph is CHECKED before being printed: an unchecked derivation is a
    log, not evidence.  See jeg.mli. *)
let derive_file ?(dot = false) (filename : string) : unit =
  let prog = parse_file filename in
  let gamma = ref [] in
  let failures = ref 0 in
  List.iter (fun stmt ->
    match stmt with
    | Tangle.Ast.Definition d when d.Tangle.Ast.def_params = [] ->
      begin try
        let dv = Tangle.Jeg.derive !gamma d.Tangle.Ast.def_body in
        (* Re-validate independently before showing it. *)
        begin match Tangle.Jeg.check dv with
        | Ok () -> ()
        | Error es ->
          incr failures;
          List.iter (fun (e : Tangle.Jeg.check_error) ->
            Printf.eprintf "JEG CHECK FAILED [%s]: %s\n" e.Tangle.Jeg.ce_rule e.Tangle.Jeg.ce_reason) es
        end;
        if dot then print_string (Tangle.Jeg.to_dot dv)
        else begin
          Printf.printf "== %s ==  (%d nodes, depth %d)\n"
            d.Tangle.Ast.def_name (Tangle.Jeg.size dv) (Tangle.Jeg.depth dv);
          print_string (Tangle.Jeg.to_string dv);
          print_newline ()
        end;
        let ty = Tangle.Typecheck.infer_expr !gamma [] d.Tangle.Ast.def_body in
        gamma := Tangle.Typecheck.env_bind_val !gamma d.Tangle.Ast.def_name ty
      with Tangle.Typecheck.Type_error msg ->
        Printf.eprintf "Type error in '%s': %s\n" d.Tangle.Ast.def_name msg
      end
    | _ -> ()
  ) prog;
  if !failures > 0 then exit 1

(** Type-check and evaluate a TANGLE source file, printing results. *)
let eval_file (filename : string) : unit =
  let prog = parse_file filename in
  (* Type-check first *)
  let tc_result = Tangle.Typecheck.check_program prog in
  if not tc_result.result_ok then begin
    List.iter (fun d ->
      Printf.eprintf "Type error: %s\n" d.Tangle.Typecheck.diag_message
    ) tc_result.result_diagnostics;
    exit 1
  end;
  (* Evaluate *)
  begin try
    let result = Tangle.Eval.eval_program prog in
    List.iter (fun output ->
      Printf.printf "%s\n" output
    ) result.eval_outputs
  with Tangle.Eval.Eval_error msg ->
    Printf.eprintf "Runtime error: %s\n" msg;
    exit 1
  end

(** Compile a TANGLE source file's compositional definitions to planar-diagram
    payloads (the Skein / TangleIR ingestion path).  Each `def name = <expr>`
    whose body is a closed or echo-closed compositional expression is lowered to
    its canonical PDv1 blob; `echoClose` definitions additionally emit the
    retained residue braid (the pre-closure word threaded for QuandleDB
    provenance — see docs/spec/ECHO-TANGLEIR-THREADING.md). *)
let compile_pd_file (filename : string) : unit =
  let prog = parse_file filename in
  List.iter (fun stmt ->
    match stmt with
    | Tangle.Ast.Definition d ->
      begin match Tangle.Compositional.of_ast_expr d.Tangle.Ast.def_body with
      | Error _ ->
        Printf.printf "%s: (outside compositional subset — skipped)\n" d.Tangle.Ast.def_name
      | Ok cexpr ->
        begin match Tangle.Compositional.compile cexpr with
        | Ok (Tangle.Compositional.ClosedDiagram pd) ->
          let p = Tangle.Compositional.skein_payload_of_pd ~name:d.Tangle.Ast.def_name pd in
          Printf.printf "%s: %s (crossings=%d)\n"
            d.Tangle.Ast.def_name p.Tangle.Compositional.pd_blob p.Tangle.Compositional.crossing_number
        | Ok (Tangle.Compositional.EchoClosed { residue; diagram }) ->
          let p =
            Tangle.Compositional.echo_payload_of_residue_and_pd
              ~name:d.Tangle.Ast.def_name residue diagram
          in
          Printf.printf "%s: %s (crossings=%d) residue=%s\n"
            d.Tangle.Ast.def_name p.Tangle.Compositional.pd_blob
            p.Tangle.Compositional.crossing_number p.Tangle.Compositional.residue_blob
        | Ok (Tangle.Compositional.OpenWord _) ->
          Printf.printf "%s: (open word — not closed; no planar diagram)\n" d.Tangle.Ast.def_name
        | Error msg ->
          Printf.eprintf "%s: compile error: %s\n" d.Tangle.Ast.def_name msg
        end
      end
    | _ -> ()
  ) prog

(** Emit the combined parse + type-check diagnostics for a file, one per line in
    the machine-readable form the LSP consumes ("SEVERITY<TAB>LINE<TAB>COL<TAB>MESSAGE").
    Exit 1 if any error diagnostic is present, 0 otherwise.  This is the single
    diagnostic source the LSP delegates to (TG-9). *)
let check_file (filename : string) : unit =
  let ic = open_in filename in
  let n = in_channel_length ic in
  let source = really_input_string ic n in
  close_in ic;
  let diags = Tangle.Check.check_source source in
  List.iter (fun d -> print_string (Tangle.Check.format_diag d); print_newline ()) diags;
  if Tangle.Check.has_error diags then exit 1

(** Print usage information. *)
let usage () =
  Printf.eprintf "Usage: tanglec [OPTIONS] [file.tangle]\n";
  Printf.eprintf "\n";
  Printf.eprintf "Options:\n";
  Printf.eprintf "  --dump-tokens <file>   Dump lexer tokens\n";
  Printf.eprintf "  --eval <file>          Evaluate a program\n";
  Printf.eprintf "  --check <file>         Emit parse + type diagnostics (LSP backend)\n";
  Printf.eprintf "  --compile-pd <file>    Compile compositional defs to PD/Skein payloads\n";
  Printf.eprintf "  --derive <file>        Emit the judgement evidence graph (proof tree)\n";
  Printf.eprintf "  --derive-dot <file>    Emit the judgement evidence graph as Graphviz DOT\n";
  Printf.eprintf "  --repl                 Start interactive REPL\n";
  Printf.eprintf "  <file>                 Parse and pretty-print AST\n";
  exit 1

let () =
  match Array.to_list Sys.argv with
  | [_; "--dump-tokens"; filename] ->
    dump_tokens filename
  | [_; "--eval"; filename] ->
    eval_file filename
  | [_; "--check"; filename] ->
    check_file filename
  | [_; "--compile-pd"; filename] ->
    compile_pd_file filename
  | [_; "--derive"; filename] ->
    derive_file filename
  | [_; "--derive-dot"; filename] ->
    derive_file ~dot:true filename
  | [_; "--repl"] ->
    Tangle.Repl.run ()
  | [_; filename] ->
    let prog = parse_file filename in
    print_string (Tangle.Pretty.program_to_string prog)
  | _ ->
    usage ()
