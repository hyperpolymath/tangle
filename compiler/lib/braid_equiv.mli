(* SPDX-License-Identifier: MPL-2.0 *)
(* braid_equiv.mli — braid-GROUP equivalence (TG-7; the semantics of `==`).
 *
 * Decides braid-group equality via Dehornoy handle reduction.  As of the
 * owner ruling tangle#50 (2026-07-29) this IS the language's `==` on braids
 * (eval.ml `Eq`, Lean `Step.eqBraids` via `braidEquiv`), and `~` too. *)

(** A braid word as unit letters (index >= 1, sign +/-1). *)
type letter = { idx : int; sgn : int }

(** Expand a braid literal (with arbitrary nonzero exponents) to unit letters. *)
val units_of : Ast.generator list -> letter list

(** Inverse braid word: reverse order, negate signs. *)
val inverse : letter list -> letter list

(** Dehornoy handle reduction to a handle-free, freely-reduced word.
    [max_steps] is a safety bound (default 1_000_000). *)
val reduce : ?max_steps:int -> letter list -> letter list

(** A unit word represents the trivial braid iff it reduces to the empty word. *)
val is_trivial_word : letter list -> bool

(** A braid literal represents the trivial (identity) braid. *)
val is_trivial : Ast.generator list -> bool

(** [equiv u v] is true iff [u] and [v] denote the same braid-group element. *)
val equiv : Ast.generator list -> Ast.generator list -> bool

(** Writhe (exponent sum); a braid-relation invariant. *)
val writhe : Ast.generator list -> int

(** Underlying permutation on [1..strands]; a braid-relation invariant. *)
val permutation : strands:int -> Ast.generator list -> int array
