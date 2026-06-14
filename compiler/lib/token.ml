(* SPDX-License-Identifier: MPL-2.0 *)
(* token.ml — Token type definitions for the TANGLE lexer.
 *
 * Each constructor corresponds to a terminal symbol in the TANGLE EBNF
 * grammar.  The lexer (lexer.mll) produces values of type [token] and
 * the parser (parser.mly) consumes them via the [%token] declarations
 * that mirror this type.
 *)

(** Source location for error messages. *)
type pos = {
  pos_line : int;   (** 1-based line number *)
  pos_col  : int;   (** 0-based column *)
}

(** A located token carries its source position for diagnostics. *)
type located_token = {
  tok : token;
  pos : pos;
}

(** All token kinds produced by the TANGLE lexer.
 *
 *  Groups:
 *    - Keywords        : language-level reserved words
 *    - Invariant names : built-in knot/link invariants
 *    - Operators        : symbolic punctuation
 *    - Literals         : values embedded in source text
 *    - Special          : end-of-file sentinel
 *)
and token =
  (* ---- Keywords ---- *)
  | DEF
  | WEAVE
  | INTO
  | YIELD
  | STRANDS
  | COMPUTE
  | ASSERT
  | MATCH
  | WITH
  | END
  | LET
  | IN
  | IDENTITY
  | TRUE
  | FALSE
  | CLOSE
  | MIRROR
  | REVERSE
  | SIMPLIFY
  | CAP
  | CUP
  | BRAID
  (* Echo / product forms *)
  | ECHOCLOSE
  | LOWER
  | RESIDUE
  | PAIR
  | FST
  | SND
  | ECHOADD
  | ECHOEQ

  (* ---- Invariant names ---- *)
  | JONES
  | ALEXANDER
  | HOMFLY
  | KAUFFMAN
  | WRITHE
  | LINKING

  (* ---- Operators / punctuation ---- *)
  | DOT           (* .  — vertical compose / cons *)
  | PIPE          (* |  — horizontal tensor *)
  | PLUS          (* +  — addition / connect sum *)
  | MINUS         (* -  — subtraction *)
  | STAR          (* *  — multiplication *)
  | SLASH         (* /  — division *)
  | EQEQ          (* == — structural equality *)
  | TILDE         (* ~  — isotopy equivalence *)
  | GTGT          (* >> — pipeline *)
  | GT            (* >  — over-crossing operator *)
  | LT            (* <  — under-crossing operator *)
  | LPAREN        (* (  *)
  | RPAREN        (* )  *)
  | LBRACKET      (* [  *)
  | RBRACKET      (* ]  *)
  | LBRACE        (* {  *)
  | RBRACE        (* }  *)
  | COMMA         (* ,  *)
  | COLON         (* :  *)
  | EQ            (* =  — binding / definition *)
  | ARROW         (* => — match arm arrow *)
  | SEMI          (* ;  *)
  | CARET         (* ^  — exponentiation *)
  | UNDERSCORE    (* _  — wildcard pattern *)

  (* ---- Literals ---- *)
  | INT of int          (** Integer literal *)
  | FLOAT of float      (** Floating-point literal *)
  | STRING of string    (** String literal (contents, no quotes) *)
  | IDENT of string     (** Identifier *)
  | GENERATOR of int    (** Braid generator index: s1 -> 1, s2 -> 2, etc. *)

  (* ---- Special ---- *)
  | EOF
