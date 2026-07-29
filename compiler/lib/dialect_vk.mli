(* SPDX-License-Identifier: MPL-2.0 *)
(* dialect_vk.mli — virtual-knot dialect as a conservative extension of core
 * braids (TG-8 template).  See dialect_vk.ml for scope and method. *)

(** A virtual braid generator: a real crossing or a virtual crossing vᵢ. *)
type vgen =
  | Real of Ast.generator
  | Virt of int

type vword = vgen list

(** Embed a core braid word (all crossings real).  [project (embed w) = Some w]. *)
val embed : Ast.generator list -> vword

(** Recover the core braid word iff there are no virtual crossings. *)
val project : vword -> Ast.generator list option

val is_real : vword -> bool
val has_virtual : vword -> bool

(** Underlying permutation on [1..strands] (real and virtual both transpose). *)
val permutation : strands:int -> vword -> int array

(** Writhe (real crossings only). *)
val writhe : vword -> int

(** Inverse virtual braid word. *)
val vinverse : vword -> vword

(** Free + involution reduction (σσ⁻¹ and vᵢvᵢ cancellation). *)
val free_reduce : vword -> vword

(** Decide triviality.  [Some _] when decided; on the real fragment this is the
    core decision procedure (complete).  [None] iff irreducible mixed virtual
    content remains (the honest partial-decision frontier). *)
val decide_trivial : vword -> bool option

(** Dialect equivalence = [decide_trivial (u · v⁻¹)]. *)
val equiv : vword -> vword -> bool option
