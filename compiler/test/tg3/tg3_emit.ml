(* SPDX-License-Identifier: MPL-2.0 *)
(* tg3_emit.ml — TG-3 translation-validation harness.
 *
 * Discharges proof obligation TG-3 ("OCaml typecheck.ml refines the Lean
 * HasType spec") by *translation validation*.  TG-2 already proves, in Lean,
 * that the algorithmic `infer` equals the declarative `HasType`
 * (`infer_iff_hasType`).  So refinement reduces to the cross-language claim
 *
 *     OCaml `infer_expr` agrees with Lean `infer` on the shared core fragment.
 *
 * This program establishes that claim term-by-term: a deterministic corpus of
 * core-fragment terms is type-inferred by OCaml `infer_expr`, and every result
 * is emitted as a Lean obligation
 *
 *     example : infer [] <term> = <some τ | none> := by decide
 *
 * which Lean's *proven* `infer` kernel-checks (`proofs/TG3Differential.lean`,
 * built by `proofs/check-tg3-differential.sh`).  All obligations pass ⟺ OCaml
 * ≡ Lean on the corpus.
 *
 * THE CORE FRAGMENT is the sublanguage on which the OCaml type algebra stays
 * inside Lean's `Ty = {num,str,bool,word,echo,prod}` (no `Tangle`):
 *
 *   literals (int/str/bool/identity/braid with idx ≥ 0), let/var, compose,
 *   tensor, pipeline, add, eq (num/str/word-same-width), echoClose, lower,
 *   residue, pair, fst, snd, echoAdd, echoEq.
 *
 * It EXCLUDES `close` — the single boundary gateway: Lean types it `word 0`,
 * OCaml lifts it to `Tangle[I,I]`, escaping the translatable type universe —
 * together with isotopy, sub/mul/div, unary, mirror/reverse/simplify/twist/
 * cap/cup/crossing, match, call, float literals, and program-level def typing.
 * Each is recorded in proofs/TG3-REFINEMENT.md as model-later or declare-non-core.
 *
 * Two run modes:
 *   --check          self-test: OCaml-side invariants + divergence behaviours
 *                    (no Lean needed; wired into `dune runtest`).
 *   --emit <path>    regenerate the Lean obligation file at <path>.
 *)

open Tangle.Ast
open Tangle.Typecheck

(* ================================================================== *)
(*  Generator helpers                                                  *)
(* ================================================================== *)

let s i  = { gen_index = i; gen_exponent = 1 }    (* σᵢ   (idx ≥ 0)      *)
let si i = { gen_index = i; gen_exponent = -1 }   (* σᵢ⁻¹               *)

(* ================================================================== *)
(*  OCaml type → Lean Ty syntax                                        *)
(*  Total on the core image; raises on TTangle (must never occur for   *)
(*  a core term — the closure result, asserted by --check).            *)
(* ================================================================== *)

let rec lean_ty (t : ty) : string =
  match t with
  | TNum         -> ".num"
  | TStr         -> ".str"
  | TBool        -> ".bool"
  | TWord n      -> Printf.sprintf "(.word %d)" n
  | TEcho (r, v) -> Printf.sprintf "(.echo %s %s)" (lean_ty r) (lean_ty v)
  | TProd (a, b) -> Printf.sprintf "(.prod %s %s)" (lean_ty a) (lean_ty b)
  | TTangle _    ->
    failwith "TG-3: TTangle has no Lean image — a non-core term leaked into the corpus"

(** True iff the whole type tree is free of TTangle (the strengthened
    closure invariant: a Tangle must not hide inside a TProd/TEcho). *)
let rec ty_tangle_free = function
  | TTangle _              -> false
  | TEcho (a, b) | TProd (a, b) -> ty_tangle_free a && ty_tangle_free b
  | TWord _ | TNum | TStr | TBool -> true

(* ================================================================== *)
(*  OCaml expr → Lean Expr syntax (named → de Bruijn)                  *)
(* ================================================================== *)

(* Lean Int literal — negatives must be parenthesised. *)
let lean_int n = if n < 0 then Printf.sprintf "(%d)" n else string_of_int n

(* Lean Generator ⟨idx : Nat, exp : Int⟩.  idx ≥ 0 is required for a faithful
   image (Lean's idx is Nat); the corpus only ever uses non-negative indices. *)
let lean_gen (g : generator) : string =
  if g.gen_index < 0 then
    failwith "TG-3: negative generator index has no Lean (Nat) image";
  Printf.sprintf "\xe2\x9f\xa8%d, %s\xe2\x9f\xa9" g.gen_index (lean_int g.gen_exponent)

let lean_str s =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  String.iter (fun c -> match c with
    | '"'  -> Buffer.add_string b "\\\""
    | '\\' -> Buffer.add_string b "\\\\"
    | c    -> Buffer.add_char b c) s;
  Buffer.add_char b '"';
  Buffer.contents b

(* index of the nearest enclosing binder named [name] (0 = innermost). *)
let index_of scope name =
  let rec go i = function
    | [] -> None
    | x :: r -> if String.equal x name then Some i else go (i + 1) r
  in go 0 scope

let rec lean_expr (scope : string list) (e : expr) : string =
  match e with
  | IntLit n    -> Printf.sprintf "(.num %s)" (lean_int n)
  | StringLit s -> Printf.sprintf "(.str %s)" (lean_str s)
  | BoolLit b   -> Printf.sprintf "(.boolLit %b)" b
  | Identity    -> ".identity"
  | BraidLit gs -> Printf.sprintf "(.braidLit [%s])"
                     (String.concat ", " (List.map lean_gen gs))
  | Var name ->
    (match index_of scope name with
     | Some i -> Printf.sprintf "(.var %d)" i
     | None   -> failwith ("TG-3: free variable '" ^ name ^ "' in corpus term"))
  | Let (x, e1, e2) ->
    Printf.sprintf "(.lett %s %s)"
      (lean_expr scope e1) (lean_expr (x :: scope) e2)
  | BinOp (Compose, a, b) -> Printf.sprintf "(.compose %s %s)" (lean_expr scope a) (lean_expr scope b)
  | BinOp (Tensor,  a, b) -> Printf.sprintf "(.tensor %s %s)"  (lean_expr scope a) (lean_expr scope b)
  | BinOp (Add,     a, b) -> Printf.sprintf "(.add %s %s)"     (lean_expr scope a) (lean_expr scope b)
  | BinOp (Eq,      a, b) -> Printf.sprintf "(.eq %s %s)"      (lean_expr scope a) (lean_expr scope b)
  | Pipeline (a, b)       -> Printf.sprintf "(.pipeline %s %s)" (lean_expr scope a) (lean_expr scope b)
  | EchoClose e1 -> Printf.sprintf "(.echoClose %s)" (lean_expr scope e1)
  | Lower e1     -> Printf.sprintf "(.lower %s)"     (lean_expr scope e1)
  | Residue e1   -> Printf.sprintf "(.residue %s)"   (lean_expr scope e1)
  | Pair (a, b)  -> Printf.sprintf "(.pair %s %s)"   (lean_expr scope a) (lean_expr scope b)
  | Fst e1       -> Printf.sprintf "(.fst %s)"       (lean_expr scope e1)
  | Snd e1       -> Printf.sprintf "(.snd %s)"       (lean_expr scope e1)
  | EchoAdd (a, b) -> Printf.sprintf "(.echoAdd %s %s)" (lean_expr scope a) (lean_expr scope b)
  | EchoEq  (a, b) -> Printf.sprintf "(.echoEq %s %s)"  (lean_expr scope a) (lean_expr scope b)
  (* Non-core: must never appear in the corpus (close is the boundary gateway). *)
  | FloatLit _ | BinOp ((Sub | Mul | Div | Isotopy), _, _) | UnaryOp _
  | Close _ | Mirror _ | Reverse _ | Simplify _ | Cap _ | Cup _ | Twist _
  | Match _ | Call _ | Crossing _ ->
    failwith "TG-3: non-core constructor in corpus term"

(* ================================================================== *)
(*  Corpus                                                             *)
(* ================================================================== *)

let nums  = [IntLit 0; IntLit 1; IntLit 7; IntLit (-3)]
let strs  = [StringLit ""; StringLit "ab"; StringLit "knot"]
let bools = [BoolLit true; BoolLit false]
let words = [
  Identity;                    (* word 0 *)
  BraidLit [];                 (* word 0 *)
  BraidLit [s 0];              (* word 1 *)
  BraidLit [s 1];              (* word 2 *)
  BraidLit [si 1];             (* word 2 *)
  BraidLit [s 0; s 1];         (* word 2 *)
  BraidLit [s 2];              (* word 3 *)
  BraidLit [s 1; si 2; s 0];   (* word 3 *)
]

let x = "x"
let y = "y"

(** Every corpus term is closed and built only from core constructors.
    Terms that OCaml rejects (Type_error) are kept too — they exercise
    reject-agreement (both sides return none). *)
let corpus : expr list =
  let acc = ref [] in
  let a e = acc := e :: !acc in
  let cross f xs ys = List.iter (fun u -> List.iter (fun v -> f u v) ys) xs in

  (* leaves *)
  List.iter a (nums @ strs @ bools @ words);

  (* word algebra: compose / tensor / pipeline over all word pairs *)
  cross (fun u v -> a (BinOp (Compose, u, v)); a (BinOp (Tensor, u, v)); a (Pipeline (u, v)))
    words words;

  (* arithmetic + equality (never bool == bool: that is divergence D2) *)
  cross (fun u v -> a (BinOp (Add, u, v))) nums nums;
  cross (fun u v -> a (BinOp (Eq, u, v))) nums nums;
  cross (fun u v -> a (BinOp (Eq, u, v))) strs strs;
  cross (fun u v -> a (BinOp (Eq, u, v))) words words;   (* same-width accept, else reject *)

  (* echo intro / elimination *)
  List.iter (fun w -> a (EchoClose w); a (Lower (EchoClose w)); a (Residue (EchoClose w))) words;
  cross (fun u v -> a (EchoAdd (u, v))) nums nums;
  cross (fun u v -> a (EchoEq (u, v))) nums nums;
  cross (fun u v -> a (EchoEq (u, v))) strs strs;
  cross (fun u v -> a (EchoEq (u, v))) words words;
  a (Lower   (EchoAdd (IntLit 1, IntLit 2)));
  a (Residue (EchoAdd (IntLit 1, IntLit 2)));
  a (Fst (Residue (EchoAdd (IntLit 1, IntLit 2))));
  a (Snd (Residue (EchoEq (StringLit "a", StringLit "b"))));
  a (Residue (EchoEq (BraidLit [s 1], BraidLit [si 1])));

  (* products + nested projections *)
  List.iter (fun t -> a (Pair (t, IntLit 0))) (nums @ strs @ bools @ words);
  a (Fst (Pair (BraidLit [s 1], IntLit 0)));
  a (Snd (Pair (BraidLit [s 1], StringLit "x")));
  a (Pair (Pair (IntLit 1, StringLit "a"), BoolLit true));
  a (Fst (Fst (Pair (Pair (IntLit 1, StringLit "a"), BoolLit true))));
  a (Snd (Fst (Pair (Pair (IntLit 1, StringLit "a"), BoolLit true))));

  (* let-binding, including shadowing (the de Bruijn hazard) *)
  a (Let (x, IntLit 5, Var x));
  a (Let (x, BraidLit [s 1], Var x));
  a (Let (x, IntLit 5, BinOp (Add, Var x, IntLit 1)));
  a (Let (x, BraidLit [s 1], BinOp (Compose, Var x, Var x)));
  a (Let (x, IntLit 1, Let (y, StringLit "a", Snd (Pair (Var x, Var y)))));
  a (Let (x, IntLit 1, Let (y, BraidLit [s 2], Fst (Pair (Var y, Var x)))));
  (* shadowing: the inner x must translate to (.var 0), the outer to (.var 1) *)
  a (Let (x, IntLit 1, Let (x, Identity, Var x)));
  a (Let (x, IntLit 1, Let (x, BraidLit [s 2], BinOp (Compose, Var x, Var x))));
  a (Let (x, EchoClose (BraidLit [s 1]), Residue (Var x)));
  a (Let (x, IntLit 1, BinOp (Add, Var x, Let (y, IntLit 2, Var y))));

  (* explicit reject witnesses (both OCaml and Lean return none) *)
  a (BinOp (Add, BraidLit [], IntLit 1));
  a (BinOp (Compose, IntLit 1, IntLit 2));
  a (BinOp (Tensor, StringLit "a", Identity));
  a (Lower (IntLit 1));
  a (Residue (BoolLit true));
  a (Fst (IntLit 1));
  a (Snd Identity);
  a (EchoAdd (StringLit "a", IntLit 1));
  a (EchoClose (IntLit 1));
  a (BinOp (Eq, IntLit 1, StringLit "a"));

  List.rev !acc

(* result of OCaml inference: Some τ (accept) or None (Type_error/reject). *)
let infer_opt e = try Some (infer_expr [] [] e) with Type_error _ -> None

(* ================================================================== *)
(*  Divergence witnesses (D-family).                                   *)
(*  These contain `close` (boundary gateway) or `bool == bool`, so they *)
(*  are outside the core translator.  Each pins the LEAN side as a      *)
(*  hand-written obligation; the OCaml side is pinned by --check.       *)
(* ================================================================== *)

type divergence = {
  d_id      : string;
  d_desc    : string;
  d_lean    : string;            (* Lean obligation body: "<expr> = <rhs>" *)
  d_ocaml   : unit -> string;    (* OCaml behaviour, rendered for --check  *)
}

(* render OCaml behaviour for a term as a type string or "REJECT" *)
let ocaml_render e = match infer_opt e with Some t -> pp_ty t | None -> "REJECT"

let divergences : divergence list = [
  { d_id = "D1"; d_desc = "close(braid[s0]): OCaml Tangle[I,I] vs Lean Word[0]";
    d_lean = "infer [] (.close (.braidLit [\xe2\x9f\xa80, 1\xe2\x9f\xa9])) = some (.word 0)";
    d_ocaml = (fun () -> ocaml_render (Close (BraidLit [s 0]))) };
  { d_id = "D1b"; d_desc = "pipeline(close,close): OCaml Tangle[I,I] vs Lean Word[0]";
    d_lean = "infer [] (.pipeline (.close (.braidLit [\xe2\x9f\xa80, 1\xe2\x9f\xa9])) (.close (.braidLit [\xe2\x9f\xa80, 1\xe2\x9f\xa9]))) = some (.word 0)";
    d_ocaml = (fun () -> ocaml_render (Pipeline (Close (BraidLit [s 0]), Close (BraidLit [s 0])))) };
  { d_id = "D1c"; d_desc = "compose(braid[s0],close): OCaml REJECT vs Lean Word[1]";
    d_lean = "infer [] (.compose (.braidLit [\xe2\x9f\xa80, 1\xe2\x9f\xa9]) (.close (.braidLit [\xe2\x9f\xa80, 1\xe2\x9f\xa9]))) = some (.word 1)";
    d_ocaml = (fun () -> ocaml_render (BinOp (Compose, BraidLit [s 0], Close (BraidLit [s 0])))) };
  { d_id = "D1c'"; d_desc = "compose(close,braid[s0]): OCaml REJECT vs Lean Word[1]";
    d_lean = "infer [] (.compose (.close (.braidLit [\xe2\x9f\xa80, 1\xe2\x9f\xa9])) (.braidLit [\xe2\x9f\xa80, 1\xe2\x9f\xa9])) = some (.word 1)";
    d_ocaml = (fun () -> ocaml_render (BinOp (Compose, Close (BraidLit [s 0]), BraidLit [s 0]))) };
  { d_id = "D1d"; d_desc = "add(close,close): OCaml Tangle[I,I] vs Lean none (close⇒word 0, not num)";
    d_lean = "infer [] (.add (.close (.braidLit [\xe2\x9f\xa80, 1\xe2\x9f\xa9])) (.close (.braidLit [\xe2\x9f\xa80, 1\xe2\x9f\xa9]))) = none";
    d_ocaml = (fun () -> ocaml_render (BinOp (Add, Close (BraidLit [s 0]), Close (BraidLit [s 0])))) };
  { d_id = "D2"; d_desc = "true == false: OCaml Bool vs Lean none (no bool-eq rule)";
    d_lean = "infer [] (.eq (.boolLit true) (.boolLit false)) = none";
    d_ocaml = (fun () -> ocaml_render (BinOp (Eq, BoolLit true, BoolLit false))) };
]

(* expected OCaml behaviours for the divergence witnesses (checked by --check) *)
let divergence_expected = [
  ("D1",   "Tangle[I, I]");
  ("D1b",  "Tangle[I, I]");
  ("D1c",  "REJECT");
  ("D1c'", "REJECT");
  ("D1d",  "Tangle[I, I]");
  ("D2",   "Bool");
]

(* ================================================================== *)
(*  Emit mode                                                          *)
(* ================================================================== *)

let obligation_of_term e =
  let lhs = Printf.sprintf "infer [] %s" (lean_expr [] e) in
  match infer_opt e with
  | Some t -> Printf.sprintf "%s = some %s" lhs (lean_ty t)
  | None   -> Printf.sprintf "%s = none" lhs

let emit path =
  let oc = open_out path in
  let p fmt = Printf.fprintf oc fmt in
  p "-- SPDX-License-Identifier: MPL-2.0\n";
  p "-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>\n";
  p "--\n";
  p "-- TG3Differential.lean — GENERATED by compiler/test/tg3/tg3_emit.ml.  DO NOT EDIT BY HAND.\n";
  p "-- Regenerate: (cd compiler && dune exec ./test/tg3/tg3_emit.exe -- --emit <abs>/proofs/TG3Differential.lean)\n";
  p "--\n";
  p "-- Each `example` certifies that OCaml `infer_expr` agrees with Lean's *proven*\n";
  p "-- `infer` (TG-2: infer ≡ HasType) on one term of the shared core fragment.\n";
  p "-- `by decide` kernel-checks each.  Build via proofs/check-tg3-differential.sh.\n";
  p "-- This is the machine-checked half of TG-3; see proofs/TG3-REFINEMENT.md.\n";
  p "import Tangle\n";
  p "open Tangle\n\n";
  p "section CoreAgreement\n";
  p "-- OCaml infer_expr result == Lean infer result, for every core-fragment term.\n";
  let n = List.length corpus in
  List.iteri (fun i e ->
    p "example : %s := by decide  -- %d/%d\n" (obligation_of_term e) (i + 1) n) corpus;
  p "end CoreAgreement\n\n";
  p "section Divergences\n";
  p "-- The complete divergence catalogue.  Each pins the LEAN side; the OCaml\n";
  p "-- side (shown) is pinned by compiler/test/tg3 --check.  `close` is the sole\n";
  p "-- core boundary gateway (OCaml lifts Word→Tangle[I,I]); D2 is bool-eq.\n";
  List.iter (fun d ->
    p "-- %s  %s  [OCaml: %s]\n" d.d_id d.d_desc (d.d_ocaml ());
    p "example : %s := by decide\n" d.d_lean) divergences;
  p "end Divergences\n";
  close_out oc;
  Printf.printf "TG-3: emitted %d core-agreement obligations + %d divergence witnesses to %s\n"
    n (List.length divergences) path

(* ================================================================== *)
(*  Check mode (dune runtest; no Lean required)                        *)
(* ================================================================== *)

let check () =
  let pass = ref 0 and fail = ref 0 in
  let ok name b =
    if b then incr pass
    else begin incr fail; Printf.printf "  FAIL  %s\n" name end
  in

  (* 1. Closure invariant: every accepted core term has a Tangle-free type,
     and every term is renderable into Lean syntax (no leaked non-core node). *)
  List.iteri (fun i e ->
    (match infer_opt e with
     | Some t -> ok (Printf.sprintf "closure[%d]: tangle-free" i) (ty_tangle_free t)
     | None   -> incr pass);                       (* reject is fine *)
    (try let _ = obligation_of_term e in incr pass
     with e -> incr fail;
       Printf.printf "  FAIL  render[%d]: %s\n" i (Printexc.to_string e))) corpus;

  (* 2. Curated agreement pins — pin OCaml's result directly. *)
  let pin name e expected = ok name (infer_opt e = Some expected) in
  pin "compose width = max"  (BinOp (Compose, BraidLit [s 0], BraidLit [s 2])) (TWord 3);
  pin "tensor width = sum"   (BinOp (Tensor,  BraidLit [s 0], BraidLit [s 1])) (TWord 3);
  pin "pipeline = compose"   (Pipeline (BraidLit [s 1], BraidLit [s 2]))       (TWord 3);
  pin "add num"              (BinOp (Add, IntLit 1, IntLit 2))                 TNum;
  pin "eq same-width word"   (BinOp (Eq, BraidLit [s 1], BraidLit [si 1]))     TBool;
  pin "echoClose shape"      (EchoClose (BraidLit [s 1]))         (TEcho (TWord 2, TWord 0));
  pin "lower echoClose"      (Lower (EchoClose (BraidLit [s 1])))  (TWord 0);
  pin "residue echoClose"    (Residue (EchoClose (BraidLit [s 1]))) (TWord 2);
  pin "echoAdd shape"        (EchoAdd (IntLit 1, IntLit 2))  (TEcho (TProd (TNum, TNum), TNum));
  pin "echoEq word shape"    (EchoEq (BraidLit [s 1], BraidLit [si 1]))
    (TEcho (TProd (TWord 2, TWord 2), TBool));
  pin "let identity bind"    (Let (x, BraidLit [s 1], Var x))                  (TWord 2);
  pin "let shadowing inner"  (Let (x, IntLit 1, Let (x, BraidLit [s 2], BinOp (Compose, Var x, Var x))))
    (TWord 3);
  pin "nested pair fst.fst"  (Fst (Fst (Pair (Pair (IntLit 1, StringLit "a"), BoolLit true)))) TNum;

  (* 3. Reject pins — these must raise Type_error. *)
  let rejects name e = ok name (infer_opt e = None) in
  rejects "add word+num"        (BinOp (Add, BraidLit [], IntLit 1));
  rejects "eq diff-width word"  (BinOp (Eq, BraidLit [s 1], Identity));
  rejects "eq num vs str"       (BinOp (Eq, IntLit 1, StringLit "a"));
  rejects "lower non-echo"      (Lower (IntLit 1));
  rejects "fst non-prod"        (Fst (IntLit 1));
  rejects "echoClose non-word"  (EchoClose (IntLit 1));

  (* 4. Divergence OCaml-behaviour pins — the contrast with the Lean side. *)
  List.iter (fun d ->
    match List.assoc_opt d.d_id divergence_expected with
    | Some exp -> ok (Printf.sprintf "divergence %s OCaml=%s" d.d_id exp) (d.d_ocaml () = exp)
    | None -> incr fail; Printf.printf "  FAIL  divergence %s: no expected value\n" d.d_id)
    divergences;

  (* 5. de Bruijn translation pins — the HIGH-severity hazard. *)
  let dbn name e expected = ok name (String.equal (lean_expr [] e) expected) in
  dbn "deBruijn: outer var" (Let (x, IntLit 1, Var x)) "(.lett (.num 1) (.var 0))";
  dbn "deBruijn: shadowing"
    (Let (x, IntLit 1, Let (x, Identity, Var x)))
    "(.lett (.num 1) (.lett .identity (.var 0)))";
  dbn "deBruijn: outer through binder"
    (Let (x, IntLit 1, Let (y, IntLit 2, BinOp (Add, Var x, Var y))))
    "(.lett (.num 1) (.lett (.num 2) (.add (.var 1) (.var 0))))";

  Printf.printf "TG-3 self-check: %d passed, %d failed (corpus = %d terms, %d divergences)\n"
    !pass !fail (List.length corpus) (List.length divergences);
  if !fail > 0 then exit 1

(* ================================================================== *)

let () =
  match Array.to_list Sys.argv with
  | _ :: "--emit" :: path :: _ -> emit path
  | _ :: "--check" :: _ | [_] -> check ()
  | _ -> prerr_endline "usage: tg3_emit (--check | --emit <path>)"; exit 2
