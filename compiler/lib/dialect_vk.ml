(* SPDX-License-Identifier: MPL-2.0 *)
(* dialect_vk.ml — the virtual-knot dialect as a CONSERVATIVE EXTENSION of the
 * core braid language.  TG-8 template (OCaml conservativity rung).
 *
 * The virtual braid monoid VBₙ extends the braid group Bₙ with *virtual*
 * crossings vᵢ: involutions (vᵢ vᵢ = ε) with no over/under information and no
 * writhe.  The classical embedding Bₙ ↪ VBₙ is known to be faithful, so VBₙ is a
 * conservative extension of Bₙ.
 *
 * This module realises that extension so that conservativity holds BY
 * CONSTRUCTION at the implementation level: the core (real) braid language
 * embeds via [embed], and every decision on the real fragment is DELEGATED to
 * the core decision procedure [Braid_equiv] (TG-7).  The dialect therefore
 * cannot change core typing/semantics; virtual crossings are handled by new
 * rules (involution, virtual permutation) that fire only on virtual syntax.
 * `compiler/test/tg8` verifies this (delegation, faithful embedding, invariant
 * agreement, proper extension, virtual involution).
 *
 * SCOPE (honest).  This is the dialect's semantic core + conservativity bridge,
 * NOT a surface-syntax parser integration, and equivalence is a SOUND, PARTIAL
 * decision procedure for VBₙ: real Dehornoy handle reduction (via Braid_equiv) +
 * virtual involution + free reduction.  Words with irreducible mixed virtual
 * content are reported UNDECIDED (`None`) rather than guessed.  A complete VBₙ
 * word problem and a mechanised Lean conservativity proof are the next rungs.
 *)

module BE = Braid_equiv

(* A virtual braid generator: a real crossing σᵢ^{±k} or a virtual crossing vᵢ. *)
type vgen =
  | Real of Ast.generator      (* real crossing (carries index + exponent) *)
  | Virt of int                (* virtual crossing vᵢ at index i (involution) *)

type vword = vgen list

(* ---- embedding / projection (faithfulness) ---- *)

(** Embed a core braid word into the dialect (all crossings real). *)
let embed (gs : Ast.generator list) : vword = List.map (fun g -> Real g) gs

(** Recover the core braid word iff the vword has no virtual crossings. *)
let project (w : vword) : Ast.generator list option =
  let rec go acc = function
    | [] -> Some (List.rev acc)
    | Real g :: r -> go (g :: acc) r
    | Virt _ :: _ -> None
  in
  go [] w

let is_real (w : vword) : bool = project w <> None
let has_virtual (w : vword) : bool = List.exists (function Virt _ -> true | _ -> false) w

(* ---- invariants ---- *)

(** Underlying permutation on [1..strands]: BOTH real and virtual crossings
    transpose adjacent strands (σᵢ^k acts as the transposition (i,i+1) repeated
    |k| times; vᵢ once). *)
let permutation ~(strands : int) (w : vword) : int array =
  let p = Array.init strands (fun k -> k + 1) in
  let swap i = if i >= 1 && i < strands then (let t = p.(i-1) in p.(i-1) <- p.(i); p.(i) <- t) in
  List.iter (function
    | Real g -> for _ = 1 to abs g.gen_exponent do swap g.gen_index done
    | Virt i -> swap i) w;
  p

(** Writhe counts REAL crossings only (virtual crossings carry no sign). *)
let writhe (w : vword) : int =
  List.fold_left (fun a -> function Real g -> a + g.gen_exponent | Virt _ -> a) 0 w

(* ---- reduction ---- *)

let vinverse (w : vword) : vword =
  List.rev_map (function
    | Real g -> Real { g with gen_exponent = - g.gen_exponent }
    | Virt i -> Virt i) w

(* one pass of free + involution cancellation: σᵢ^a σᵢ^{-a} and vᵢ vᵢ. *)
let cancel (a : vgen) (b : vgen) : bool =
  match a, b with
  | Virt i, Virt j -> i = j
  | Real g, Real h -> g.gen_index = h.gen_index && g.gen_exponent = - h.gen_exponent
  | _ -> false

let free_reduce (w : vword) : vword =
  List.fold_right (fun x acc ->
    match acc with y :: rest when cancel x y -> rest | _ -> x :: acc) w []

(** Decide whether a vword is the trivial braid.
    [Some true]/[Some false] when decided; [None] when the word still has
    irreducible mixed virtual content (the partial-decision frontier — honest,
    never guessed).  On the REAL fragment this is the core decision procedure. *)
let decide_trivial (w : vword) : bool option =
  let r = free_reduce w in
  if r = [] then Some true
  else match project r with
    | Some real -> Some (BE.is_trivial real)   (* real fragment → core decides (complete) *)
    | None -> None                              (* mixed virtual residue → research-grade *)

(** Equivalence in the dialect: [decide_trivial (u · v⁻¹)]. *)
let equiv (u : vword) (v : vword) : bool option =
  decide_trivial (u @ vinverse v)
