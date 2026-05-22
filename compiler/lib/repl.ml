(* SPDX-License-Identifier: MPL-2.0 *)
(* repl.ml — Interactive Read-Eval-Print Loop for the TANGLE language.
 *
 * Reads a line of input, lexes, parses, type-checks, and evaluates it,
 * then prints the result value and its type.  Definitions persist across
 * lines so that the user can incrementally build up an environment.
 *
 * Commands:
 *   :quit / :q   — exit the REPL
 *   :type <expr> — show the type of an expression without evaluating it
 *   :env         — show all bindings in the current environment
 *   :help        — show help text
 *
 * Multi-line input is detected by tracking unmatched delimiters (parentheses,
 * brackets, and the match..end construct).
 *)

(* ================================================================== *)
(*  Multi-line detection                                               *)
(* ================================================================== *)

(** Check whether a line of input appears to be incomplete.
 *  Returns [true] if we should prompt for more input.
 *
 *  Heuristic: count unmatched delimiters and keywords.
 *)
let is_incomplete (input : string) : bool =
  let parens = ref 0 in
  let brackets = ref 0 in
  let match_depth = ref 0 in
  let let_depth = ref 0 in
  (* Simple token scan — we do not run the full lexer here because
     the input may be syntactically invalid mid-line. *)
  let words = String.split_on_char ' ' input in
  List.iter (fun w ->
    let w = String.trim w in
    if w = "(" then incr parens
    else if w = ")" then decr parens
    else if w = "[" then incr brackets
    else if w = "]" then decr brackets
    else if w = "match" then incr match_depth
    else if w = "end" then decr match_depth
    else if w = "let" then incr let_depth
    else if w = "in" then decr let_depth
  ) words;
  (* Also check for individual characters in non-whitespace-separated tokens *)
  String.iter (fun c ->
    match c with
    | '(' -> incr parens
    | ')' -> decr parens
    | '[' -> incr brackets
    | ']' -> decr brackets
    | _ -> ()
  ) input;
  (* Reset parens/brackets since we double-counted with the word scan.
     Use a simpler character-only count. *)
  parens := 0;
  brackets := 0;
  String.iter (fun c ->
    match c with
    | '(' -> incr parens
    | ')' -> decr parens
    | '[' -> incr brackets
    | ']' -> decr brackets
    | _ -> ()
  ) input;
  !parens > 0 || !brackets > 0 || !match_depth > 0

(* ================================================================== *)
(*  REPL state                                                         *)
(* ================================================================== *)

(** REPL state: type environment and value environment. *)
type repl_state = {
  mutable type_env : Typecheck.env;
  mutable val_env  : Eval.env;
}

(** Create a fresh REPL state. *)
let make_state () : repl_state =
  { type_env = []; val_env = [] }

(* ================================================================== *)
(*  Input parsing                                                      *)
(* ================================================================== *)

(** Try to parse input as a TANGLE program (one or more statements). *)
let parse_input (input : string) : Ast.program =
  let lexbuf = Lexing.from_string input in
  lexbuf.Lexing.lex_curr_p <- {
    lexbuf.Lexing.lex_curr_p with
    Lexing.pos_fname = "<repl>";
    Lexing.pos_lnum = 1;
  };
  Parser.program Lexer.token lexbuf

(* ================================================================== *)
(*  Command handling                                                   *)
(* ================================================================== *)

(** Process a REPL command (lines starting with ':'). *)
let handle_command (state : repl_state) (cmd : string) : bool =
  let parts = String.split_on_char ' ' (String.trim cmd) in
  match parts with
  | [":quit"] | [":q"] ->
    false  (* Signal to exit *)

  | ":type" :: rest ->
    let expr_str = String.concat " " rest in
    begin try
      let prog = parse_input expr_str in
      (* For :type, we just type-check the first statement/expression *)
      let _ = List.fold_left (fun gamma stmt ->
        let gamma' = Typecheck.check_statement gamma stmt in
        begin match stmt with
        | Ast.Definition def ->
          begin match Typecheck.env_lookup gamma' def.def_name with
          | Some (Typecheck.EVal ty) ->
            Printf.printf ": %s\n" (Typecheck.pp_ty ty)
          | Some (Typecheck.EFun fsig) ->
            let params_str = String.concat ", "
              (List.map Typecheck.pp_ty fsig.fsig_params) in
            Printf.printf ": (%s) -> %s\n" params_str
              (Typecheck.pp_ty fsig.fsig_return)
          | None ->
            Printf.printf ": <unknown>\n"
          end
        | _ ->
          Printf.printf ": <statement>\n"
        end;
        gamma'
      ) state.type_env prog in
      ()
    with
    | Lexer.Lexer_error msg ->
      Printf.eprintf "Lexer error: %s\n" msg
    | Parser.Error ->
      Printf.eprintf "Parse error in expression\n"
    | Typecheck.Type_error msg ->
      Printf.eprintf "Type error: %s\n" msg
    end;
    true

  | [":env"] ->
    if state.val_env = [] then
      Printf.printf "(empty environment)\n"
    else
      List.iter (fun (name, v) ->
        if not (String.length name > 0 && name.[0] = '_') then
          Printf.printf "  %s = %s\n" name (Eval.pp_value v)
      ) (List.rev state.val_env);
    true

  | [":help"] | [":h"] | [":?"] ->
    Printf.printf "TANGLE REPL Commands:\n";
    Printf.printf "  :type <expr>  — show the type of an expression\n";
    Printf.printf "  :env          — show all bindings\n";
    Printf.printf "  :quit / :q    — exit the REPL\n";
    Printf.printf "  :help / :h    — show this help\n";
    Printf.printf "\n";
    Printf.printf "Enter TANGLE statements (def, compute, assert, weave)\n";
    Printf.printf "or expressions to evaluate them.\n";
    true

  | _ ->
    Printf.eprintf "Unknown command: %s\n" (List.hd parts);
    Printf.eprintf "Type :help for available commands.\n";
    true

(* ================================================================== *)
(*  Main REPL loop                                                     *)
(* ================================================================== *)

(** Print the REPL banner. *)
let print_banner () =
  Printf.printf "TANGLE REPL v0.1.0\n";
  Printf.printf "Type :help for commands, :quit to exit.\n";
  Printf.printf "\n"

(** Read a potentially multi-line input from stdin.
 *  Returns [None] on EOF.
 *)
let read_input () : string option =
  Printf.printf "tangle> %!";
  match input_line stdin with
  | exception End_of_file -> None
  | line ->
    let buf = Buffer.create 256 in
    Buffer.add_string buf line;
    (* Check for multi-line input *)
    let rec continue () =
      let current = Buffer.contents buf in
      if is_incomplete current then begin
        Printf.printf "   ...> %!";
        match input_line stdin with
        | exception End_of_file -> ()
        | more ->
          Buffer.add_char buf '\n';
          Buffer.add_string buf more;
          continue ()
      end
    in
    continue ();
    Some (Buffer.contents buf)

(** Process a single line of input, updating state.
 *  Returns [false] if the REPL should exit.
 *)
let process_input (state : repl_state) (input : string) : bool =
  let input = String.trim input in
  if input = "" then true
  else if String.length input > 0 && input.[0] = ':' then
    handle_command state input
  else begin
    begin try
      (* Parse *)
      let prog = parse_input input in

      (* Type-check *)
      let type_result = List.fold_left (fun gamma stmt ->
        try Typecheck.check_statement gamma stmt
        with Typecheck.Type_error msg ->
          Printf.eprintf "Type error: %s\n" msg;
          gamma
      ) state.type_env prog in

      (* Evaluate *)
      List.iter (fun stmt ->
        try
          let (env', output) = Eval.eval_statement state.val_env stmt in
          state.val_env <- env';
          begin match output with
          | Some s -> Printf.printf "%s\n" s
          | None ->
            (* For definitions, show the bound value *)
            begin match stmt with
            | Ast.Definition def ->
              begin match Eval.env_lookup env' def.def_name with
              | Some v ->
                let ty_str = match Typecheck.env_lookup type_result def.def_name with
                  | Some (Typecheck.EVal ty) -> Typecheck.pp_ty ty
                  | Some (Typecheck.EFun fsig) ->
                    let params = String.concat ", "
                      (List.map Typecheck.pp_ty fsig.fsig_params) in
                    Printf.sprintf "(%s) -> %s" params
                      (Typecheck.pp_ty fsig.fsig_return)
                  | None -> "?"
                in
                Printf.printf "%s : %s = %s\n"
                  def.def_name ty_str (Eval.pp_value v)
              | None -> ()
              end
            | _ -> ()
            end
          end
        with Eval.Eval_error msg ->
          Printf.eprintf "Runtime error: %s\n" msg
      ) prog;

      (* Update type environment *)
      state.type_env <- type_result

    with
    | Lexer.Lexer_error msg ->
      Printf.eprintf "Lexer error: %s\n" msg
    | Parser.Error ->
      Printf.eprintf "Parse error\n"
    end;
    true
  end

(** Run the interactive REPL. *)
let run () : unit =
  print_banner ();
  let state = make_state () in
  let running = ref true in
  while !running do
    match read_input () with
    | None ->
      Printf.printf "\nBye.\n";
      running := false
    | Some input ->
      running := process_input state input
  done
