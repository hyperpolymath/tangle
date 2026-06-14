(* SPDX-License-Identifier: MPL-2.0 *)
(* check.ml — Single source of truth for Tangle diagnostics.
 *
 * Combines parsing (with error recovery) and type-checking into one diagnostic
 * list.  Both the CLI (`tanglec --check`) and the LSP server consume THIS, so
 * that LSP diagnostics are *by construction* a subset of the compiler's parse /
 * `HasType` failures — discharging proof obligation TG-9 ("LSP diagnostics are
 * a subset of HasType failures; no LSP-only diagnostics"). *)

type level = Error | Warning

type diag = {
  level   : level;
  line    : int;   (* 1-based source line; 1 with col 0 when unlocated *)
  col     : int;   (* 0-based byte offset within the line *)
  message : string;
}

(* Skip to the next statement keyword after a parse error, so a single bad
   statement does not suppress diagnostics for the rest of the file.  Mirrors the
   recovery loop in bin/main.ml. *)
let synchronize lexbuf =
  let rec loop () =
    try
      match Lexer.token lexbuf with
      | Parser.EOF -> true
      | Parser.DEF | Parser.WEAVE | Parser.COMPUTE | Parser.ASSERT -> false
      | _ -> loop ()
    with Lexer.Lexer_error _ -> loop ()
  in
  loop ()

let parse_with_recovery (source : string) : Ast.program * diag list =
  let lexbuf = Lexing.from_string source in
  lexbuf.Lexing.lex_curr_p <-
    { lexbuf.Lexing.lex_curr_p with Lexing.pos_lnum = 1 };
  let diags = ref [] in
  let stmts = ref [] in
  let at_eof = ref false in
  while not !at_eof do
    (try
       let prog = Parser.program Lexer.token lexbuf in
       stmts := prog @ !stmts;
       at_eof := true
     with
     | Lexer.Lexer_error msg ->
       let pos = lexbuf.Lexing.lex_curr_p in
       diags := { level = Error; line = pos.Lexing.pos_lnum;
                  col = pos.Lexing.pos_cnum - pos.Lexing.pos_bol;
                  message = Printf.sprintf "Lexer error: %s" msg } :: !diags;
       at_eof := synchronize lexbuf
     | Parser.Error ->
       let pos = lexbuf.Lexing.lex_curr_p in
       diags := { level = Error; line = pos.Lexing.pos_lnum;
                  col = pos.Lexing.pos_cnum - pos.Lexing.pos_bol;
                  message = "Parse error: unexpected token" } :: !diags;
       at_eof := synchronize lexbuf)
  done;
  (List.rev !stmts, List.rev !diags)

(* The full diagnostic set for a source string: parse diagnostics followed by
   type-checker diagnostics.  This is exactly the set of failures that would
   make `tanglec --eval` reject the program, so the LSP showing precisely these
   diagnostics cannot invent an LSP-only one. *)
let check_source (source : string) : diag list =
  let (prog, parse_diags) = parse_with_recovery source in
  let type_diags =
    if prog = [] then []
    else
      let r = Typecheck.check_program prog in
      List.map (fun (d : Typecheck.diagnostic) ->
        { level   = (match d.Typecheck.diag_level with
                     | `Error -> Error | `Warning -> Warning);
          (* Typecheck diagnostics carry no source span yet — surface them at the
             top of the file.  Coarse location does not affect the subset
             property TG-9 asserts (which programs are flagged, not where). *)
          line    = 1;
          col     = 0;
          message = d.Typecheck.diag_message }
      ) r.Typecheck.result_diagnostics
  in
  parse_diags @ type_diags

let level_tag = function Error -> "ERROR" | Warning -> "WARNING"

(* Machine-readable line the LSP parses: "SEVERITY<TAB>LINE<TAB>COL<TAB>MESSAGE".
   LINE is 1-based; consumers convert to their own indexing. *)
let format_diag (d : diag) : string =
  Printf.sprintf "%s\t%d\t%d\t%s" (level_tag d.level) d.line d.col d.message

let has_error (ds : diag list) : bool =
  List.exists (fun d -> d.level = Error) ds
