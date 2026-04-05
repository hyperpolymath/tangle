(* @taxonomy: compiler/parser *)
(* SPDX-License-Identifier: PMPL-1.0-or-later *)
(* parser.mly — Menhir grammar for the core TANGLE language.
 *
 * Translates the EBNF from src/tangle.ebnf into an LR(1) grammar.
 * Operator precedence (lowest to highest):
 *
 *   >>       pipeline           left-associative
 *   == ~     equality/isotopy   non-associative
 *   + -      sum                left-associative
 *   * /      product            left-associative
 *   .        vertical compose   left-associative
 *   |        horizontal tensor  left-associative
 *
 * Match and let expressions sit below pipeline (lowest precedence).
 *
 * PIPE is overloaded: it serves as both the horizontal tensor operator
 * and the match-arm delimiter.  To avoid ambiguity, match arm bodies
 * use a restricted expression level (arm_expr) that excludes bare PIPE.
 * Parenthesised expressions may still contain PIPE.
 *)

%{
  open Ast
%}

(* ---- Token declarations ---- *)

(* Keywords *)
%token DEF WEAVE INTO YIELD STRANDS COMPUTE ASSERT
%token MATCH WITH END LET IN
%token IDENTITY TRUE FALSE
%token CLOSE MIRROR REVERSE SIMPLIFY CAP CUP BRAID

(* Invariant names *)
%token JONES ALEXANDER HOMFLY KAUFFMAN WRITHE LINKING

(* Operators and punctuation *)
%token DOT PIPE PLUS MINUS STAR SLASH
%token EQEQ TILDE GTGT
%token GT LT
%token LPAREN RPAREN LBRACKET RBRACKET LBRACE RBRACE
%token COMMA COLON EQ ARROW SEMI CARET UNDERSCORE

(* Literals *)
%token <int>    INT
%token <float>  FLOAT
%token <string> STRING
%token <string> IDENT
%token <int>    GENERATOR

(* Special *)
%token EOF

(* ---- Start symbol ---- *)

%start <Ast.program> program

%%

(* ================================================================== *)
(*  Top-level structure                                                *)
(* ================================================================== *)

program:
  | ss = list(statement_item) EOF { ss }
  ;

statement_item:
  | s = statement SEMI { s }
  | s = statement      { s }
  ;

statement:
  | d = definition   { Definition d }
  | w = weave_block  { WeaveBlock w }
  | c = computation  { Computation c }
  | a = assertion    { Assertion a }
  ;

(* ================================================================== *)
(*  Definitions                                                        *)
(* ================================================================== *)

definition:
  | DEF name = IDENT LPAREN ps = param_list RPAREN EQ body = expr
    { { def_name = name; def_params = ps; def_body = body } }
  | DEF name = IDENT EQ body = expr
    { { def_name = name; def_params = []; def_body = body } }
  ;

param_list:
  | p = separated_nonempty_list(COMMA, IDENT) { p }
  ;

(* ================================================================== *)
(*  Weave block                                                        *)
(* ================================================================== *)

weave_block:
  | WEAVE inp = input_decl INTO body = expr YIELD out = output_decl
    { { weave_inputs = inp; weave_body = body; weave_outputs = out } }
  ;

input_decl:
  | STRANDS sl = strand_list { sl }
  ;

output_decl:
  | STRANDS sl = strand_list { sl }
  ;

strand_list:
  | ss = separated_nonempty_list(COMMA, typed_strand) { ss }
  ;

typed_strand:
  | name = IDENT COLON typ = IDENT
    { { strand_name = name; strand_type = Some typ } }
  | name = IDENT
    { { strand_name = name; strand_type = None } }
  ;

(* ================================================================== *)
(*  Invariant computation                                              *)
(* ================================================================== *)

computation:
  | COMPUTE inv = invariant LPAREN arg = expr RPAREN
    { { comp_invariant = inv; comp_arg = arg } }
  ;

invariant:
  | JONES      { "jones" }
  | ALEXANDER  { "alexander" }
  | HOMFLY     { "homfly" }
  | KAUFFMAN   { "kauffman" }
  | WRITHE     { "writhe" }
  | LINKING    { "linking" }
  | name = IDENT { name }
  ;

(* ================================================================== *)
(*  Assertion                                                          *)
(* ================================================================== *)

assertion:
  | ASSERT e = expr { e }
  ;

(* ================================================================== *)
(*  Expressions                                                        *)
(*                                                                     *)
(*  Full expressions allow all operators including PIPE (tensor).      *)
(*  Match arm bodies use arm_expr which excludes bare PIPE to avoid    *)
(*  ambiguity with the match-arm delimiter.                            *)
(* ================================================================== *)

expr:
  | MATCH scrut = pipe_free_expr WITH arms = nonempty_list(match_arm) END
    { Match (scrut, arms) }
  | LET name = IDENT EQ value = expr IN body = expr
    { Let (name, value, body) }
  | e = pipeline_expr
    { e }
  ;

match_arm:
  | PIPE p = pattern ARROW body = arm_expr
    { { arm_pattern = p; arm_body = body } }
  ;

(* arm_expr: expressions allowed in match arm bodies.
 * Excludes bare PIPE to avoid conflict with match-arm delimiter.
 * To use the tensor operator inside a match arm, parenthesise it.
 *)
arm_expr:
  | MATCH scrut = pipe_free_expr WITH arms = nonempty_list(match_arm) END
    { Match (scrut, arms) }
  | LET name = IDENT EQ value = arm_expr IN body = arm_expr
    { Let (name, value, body) }
  | e = pipe_free_expr
    { e }
  ;

(* ---- Full expression with PIPE (tensor) ---- *)

pipeline_expr:
  | l = pipeline_expr GTGT r = equality_expr   { Pipeline (l, r) }
  | e = equality_expr                           { e }
  ;

equality_expr:
  | l = sum_expr EQEQ r = sum_expr   { BinOp (Eq, l, r) }
  | l = sum_expr TILDE r = sum_expr  { BinOp (Isotopy, l, r) }
  | e = sum_expr                      { e }
  ;

sum_expr:
  | l = sum_expr PLUS r = product_expr    { BinOp (Add, l, r) }
  | l = sum_expr MINUS r = product_expr   { BinOp (Sub, l, r) }
  | e = product_expr                       { e }
  ;

product_expr:
  | l = product_expr STAR r = vertical_expr    { BinOp (Mul, l, r) }
  | l = product_expr SLASH r = vertical_expr   { BinOp (Div, l, r) }
  | e = vertical_expr                           { e }
  ;

vertical_expr:
  | l = vertical_expr DOT r = horizontal_expr   { BinOp (Compose, l, r) }
  | e = horizontal_expr                          { e }
  ;

horizontal_expr:
  | l = horizontal_expr PIPE r = unary_expr   { BinOp (Tensor, l, r) }
  | e = unary_expr                             { e }
  ;

(* ---- Pipe-free expression chain (for match arm bodies) ---- *)
(* Same precedence hierarchy but stops before PIPE.             *)

pipe_free_expr:
  | l = pipe_free_expr GTGT r = pf_equality_expr   { Pipeline (l, r) }
  | e = pf_equality_expr                             { e }
  ;

pf_equality_expr:
  | l = pf_sum_expr EQEQ r = pf_sum_expr   { BinOp (Eq, l, r) }
  | l = pf_sum_expr TILDE r = pf_sum_expr  { BinOp (Isotopy, l, r) }
  | e = pf_sum_expr                          { e }
  ;

pf_sum_expr:
  | l = pf_sum_expr PLUS r = pf_product_expr    { BinOp (Add, l, r) }
  | l = pf_sum_expr MINUS r = pf_product_expr   { BinOp (Sub, l, r) }
  | e = pf_product_expr                           { e }
  ;

pf_product_expr:
  | l = pf_product_expr STAR r = pf_vertical_expr    { BinOp (Mul, l, r) }
  | l = pf_product_expr SLASH r = pf_vertical_expr   { BinOp (Div, l, r) }
  | e = pf_vertical_expr                               { e }
  ;

pf_vertical_expr:
  | l = pf_vertical_expr DOT r = unary_expr   { BinOp (Compose, l, r) }
  | e = unary_expr                              { e }
  ;

(* Note: pipe-free chain shares unary_expr and below with the full chain,
 * because parenthesised sub-expressions re-enter the full expr rule. *)

(* ---- Unary / prefix operations ---- *)

unary_expr:
  | CLOSE    LPAREN e = expr RPAREN   { Close e }
  | MIRROR   LPAREN e = expr RPAREN   { Mirror e }
  | REVERSE  LPAREN e = expr RPAREN   { Reverse e }
  | SIMPLIFY LPAREN e = expr RPAREN   { Simplify e }
  | CAP LPAREN e1 = expr COMMA e2 = expr RPAREN
    { Cap (e1, e2) }
  | CUP LPAREN e1 = expr COMMA e2 = expr RPAREN
    { Cup (e1, e2) }
  | t = twist_expr                     { t }
  | MINUS e = primary_expr             { UnaryOp (Neg, e) }
  | e = primary_expr                   { e }
  ;

(* ---- Twist: (~ident) or (~(expr)) ---- *)

twist_expr:
  | LPAREN TILDE name = IDENT RPAREN
    { Twist (Var name) }
  | LPAREN TILDE LPAREN e = expr RPAREN RPAREN
    { Twist e }
  ;

(* ---- Primary / atomic expressions ---- *)

primary_expr:
  | BRAID LBRACKET gs = generator_list RBRACKET
    { BraidLit gs }
  | BRAID LBRACKET RBRACKET
    { BraidLit [] }
  | IDENTITY
    { Identity }
  | TRUE
    { BoolLit true }
  | FALSE
    { BoolLit false }
  | c = crossing
    { c }
  | name = IDENT LPAREN args = arg_list RPAREN
    { Call (name, args) }
  | name = IDENT
    { Var name }
  | n = INT
    { IntLit n }
  | f = FLOAT
    { FloatLit f }
  | s = STRING
    { StringLit s }
  | LPAREN e = expr RPAREN
    { e }
  | LBRACE e = expr RBRACE
    { e }
  ;

(* ---- Crossings: (a > b) or (a < b) ---- *)

crossing:
  | LPAREN a = IDENT GT b = IDENT RPAREN
    { Crossing (a, Over, b) }
  | LPAREN a = IDENT LT b = IDENT RPAREN
    { Crossing (a, Under, b) }
  ;

(* ---- Braid generator lists ---- *)

generator_list:
  | gs = separated_nonempty_list(COMMA, generator) { gs }
  ;

generator:
  | idx = GENERATOR CARET MINUS n = INT
    { { gen_index = idx; gen_exponent = (- n) } }
  | idx = GENERATOR CARET n = INT
    { { gen_index = idx; gen_exponent = n } }
  | idx = GENERATOR
    { { gen_index = idx; gen_exponent = 1 } }
  ;

(* ---- Function argument lists ---- *)

arg_list:
  | args = separated_nonempty_list(COMMA, expr) { args }
  ;

(* ================================================================== *)
(*  Patterns                                                           *)
(* ================================================================== *)

pattern:
  | IDENTITY
    { PatIdentity }
  | g = gen_pattern DOT rest = pattern
    { PatCons (g, rest) }
  | name = IDENT
    { PatVar name }
  | UNDERSCORE
    { PatWildcard }
  | LPAREN p = pattern RPAREN
    { p }
  ;

gen_pattern:
  | idx = GENERATOR CARET MINUS n = INT
    { { gpat_index = idx; gpat_exponent = (- n) } }
  | idx = GENERATOR CARET n = INT
    { { gpat_index = idx; gpat_exponent = n } }
  | idx = GENERATOR
    { { gpat_index = idx; gpat_exponent = 1 } }
  ;
