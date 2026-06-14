(* @taxonomy: compiler/lexer *)
{
(* SPDX-License-Identifier: MPL-2.0 *)
(* lexer.mll -- ocamllex specification for the TANGLE language.
 *
 * Handles:
 *   - All keywords and operators from the EBNF grammar
 *   - Braid generators: s followed by digits becomes a GENERATOR token
 *   - Line comments: hash to end of line
 *   - Block comments: nestable delimiters
 *   - String literals with escape sequences
 *   - Integer and floating-point literals including scientific notation
 *)
  open Parser

  (** Raise a lexer error with location info. *)
  exception Lexer_error of string

  (** Update the lexbuf position at each newline. *)
  let newline lexbuf =
    Lexing.new_line lexbuf

  (** Convert a keyword string to its token, or return [IDENT s]. *)
  let keyword_or_ident s =
    match s with
    | "def"       -> DEF
    | "weave"     -> WEAVE
    | "into"      -> INTO
    | "yield"     -> YIELD
    | "strands"   -> STRANDS
    | "compute"   -> COMPUTE
    | "assert"    -> ASSERT
    | "match"     -> MATCH
    | "with"      -> WITH
    | "end"       -> END
    | "let"       -> LET
    | "in"        -> IN
    | "identity"  -> IDENTITY
    | "true"      -> TRUE
    | "false"     -> FALSE
    | "close"     -> CLOSE
    | "mirror"    -> MIRROR
    | "reverse"   -> REVERSE
    | "simplify"  -> SIMPLIFY
    | "cap"       -> CAP
    | "cup"       -> CUP
    | "braid"     -> BRAID
    (* Echo / product forms — surface syntax mirrors pretty.ml output. *)
    | "echoClose" -> ECHOCLOSE
    | "lower"     -> LOWER
    | "residue"   -> RESIDUE
    | "pair"      -> PAIR
    | "fst"       -> FST
    | "snd"       -> SND
    | "echoAdd"   -> ECHOADD
    | "echoEq"    -> ECHOEQ
    | "jones"     -> JONES
    | "alexander" -> ALEXANDER
    | "homfly"    -> HOMFLY
    | "kauffman"  -> KAUFFMAN
    | "writhe"    -> WRITHE
    | "linking"   -> LINKING
    | _           -> IDENT s
}

(* ---- Character classes ---- *)

let digit      = ['0'-'9']
let nonzero    = ['1'-'9']
let letter     = ['a'-'z' 'A'-'Z']
let ident_char = letter | digit | '_'
let whitespace = [' ' '\t' '\r']

(* ---- Numeric patterns ---- *)

let nat        = '0' | nonzero digit*
let integer    = '-'? nat
let frac       = '.' digit+
let exponent   = ['e' 'E'] ['+' '-']? digit+
let float_lit  = nat frac exponent?
               | nat exponent
               | nat frac

(* ---- Main lexer rule ---- *)

rule token = parse
  (* Whitespace *)
  | whitespace+      { token lexbuf }
  | '\n'             { newline lexbuf; token lexbuf }

  (* Comments *)
  | '#'              { line_comment lexbuf; token lexbuf }
  | "(*"             { block_comment 1 lexbuf; token lexbuf }

  (* Multi-character operators (must come before single-char) *)
  | "=>"             { ARROW }
  | "=="             { EQEQ }
  | ">>"             { GTGT }

  (* Single-character operators and punctuation *)
  | '.'              { DOT }
  | '|'              { PIPE }
  | '+'              { PLUS }
  | '-'              { MINUS }
  | '*'              { STAR }
  | '/'              { SLASH }
  | '~'              { TILDE }
  | '>'              { GT }
  | '<'              { LT }
  | '('              { LPAREN }
  | ')'              { RPAREN }
  | '['              { LBRACKET }
  | ']'              { RBRACKET }
  | '{'              { LBRACE }
  | '}'              { RBRACE }
  | ','              { COMMA }
  | ':'              { COLON }
  | '='              { EQ }
  | ';'              { SEMI }
  | '^'              { CARET }
  | '_'              { UNDERSCORE }

  (* Braid generators: s followed by digits -> GENERATOR *)
  | 's' (nonzero digit* as n)
                     { GENERATOR (int_of_string n) }

  (* Floating-point literals (must come before integer to avoid
     consuming the integer prefix of "3.14") *)
  | float_lit as f   { FLOAT (float_of_string f) }

  (* Integer literals *)
  | nat as n         { INT (int_of_string n) }

  (* String literals *)
  | '"'              { let buf = Buffer.create 64 in
                       string_body buf lexbuf;
                       STRING (Buffer.contents buf) }

  (* Identifiers and keywords *)
  | (letter ident_char*) as s
                     { keyword_or_ident s }

  (* End of file *)
  | eof              { EOF }

  (* Catch-all error *)
  | _ as c           { let pos = lexbuf.Lexing.lex_curr_p in
                       raise (Lexer_error
                         (Printf.sprintf "unexpected character '%c' at %d:%d"
                            c pos.pos_lnum
                            (pos.pos_cnum - pos.pos_bol))) }

(* ---- Line comment: skip to end of line ---- *)

and line_comment = parse
  | '\n'             { newline lexbuf }
  | eof              { () }
  | _                { line_comment lexbuf }

(* ---- Block comment: (* ... *) with nesting ---- *)

and block_comment depth = parse
  | "(*"             { block_comment (depth + 1) lexbuf }
  | "*)"             { if depth > 1 then block_comment (depth - 1) lexbuf }
  | '\n'             { newline lexbuf; block_comment depth lexbuf }
  | eof              { raise (Lexer_error "unterminated block comment") }
  | _                { block_comment depth lexbuf }

(* ---- String literal body: handles escape sequences ---- *)

and string_body buf = parse
  | '"'              { () }
  | '\\' 'n'        { Buffer.add_char buf '\n'; string_body buf lexbuf }
  | '\\' 't'        { Buffer.add_char buf '\t'; string_body buf lexbuf }
  | '\\' '\\'       { Buffer.add_char buf '\\'; string_body buf lexbuf }
  | '\\' '"'        { Buffer.add_char buf '"';  string_body buf lexbuf }
  | '\\' 'r'        { Buffer.add_char buf '\r'; string_body buf lexbuf }
  | '\\' (_ as c)   { raise (Lexer_error
                         (Printf.sprintf "invalid escape sequence '\\%c'" c)) }
  | '\n'             { newline lexbuf;
                       Buffer.add_char buf '\n';
                       string_body buf lexbuf }
  | eof              { raise (Lexer_error "unterminated string literal") }
  | _ as c           { Buffer.add_char buf c; string_body buf lexbuf }
