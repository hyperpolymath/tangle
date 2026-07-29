(* SPDX-License-Identifier: MPL-2.0 *)
(* jeg.mli — Judgement Evidence Graph.
 *
 * Reifies a typing DERIVATION as data.  `typecheck.ml` computes a type and
 * discards how it got there; the Lean side has the derivation as a proof term
 * but never exports it.  So the question "why does this typecheck?" had no
 * answer you could hold, compare, or transmit.
 *
 * This matters beyond explanation.  TG-3's obligations assert
 *     infer [] e = some τ
 * — the RESULT type.  Two different derivations reaching the same type are
 * indistinguishable to it.  A reified derivation is comparable.
 *
 * ── What makes it EVIDENCE rather than a log ────────────────────────────────
 * A derivation is only evidence if it can be checked WITHOUT trusting whoever
 * produced it.  So [derive] and [check] are independent: [check] re-validates
 * every node against the typing rule it names, recomputing each side condition
 * from the premises.  A hand-edited or forged graph fails.  That is the whole
 * point — see the forgery tests in test_jeg.ml.
 *
 * ── Relation to TG-11 (epistemic types) ─────────────────────────────────────
 * A checked derivation is exactly what `Epi[κ, ρ, τ]` is for: standpoint κ
 * holds evidence ρ for claim τ.  The JEG is the ρ.  And the non-factivity of
 * TG-11 is the right discipline here too: holding a derivation is not the same
 * as the judgement being true — you must CHECK it.  [check] is the
 * `SoundWarrant.sound` of this module.
 *)

(** A single judgement: Γ ⊢ e : τ.  The context records only the bindings the
    derivation actually consults, so the graph stays readable. *)
type judgement = {
  j_ctx  : (string * Typecheck.ty) list;
  j_expr : Ast.expr;
  j_ty   : Typecheck.ty;
}

(** A derivation node: the rule applied, what it concludes, and the sub-derivations
    of its premises.  Nodes plus premise-edges are the graph. *)
type derivation = {
  d_rule       : string;              (** rule name, e.g. "T-Braid", "T-Eq-Word" *)
  d_conclusion : judgement;
  d_premises   : derivation list;
}

(** Why a derivation failed to check. *)
type check_error = {
  ce_rule    : string;
  ce_reason  : string;
  ce_at      : judgement;
}

(** Build the derivation for an expression under a context.
    Raises [Typecheck.Type_error] exactly when [infer_expr] does — the graph is
    produced by the same rules, not a parallel implementation. *)
val derive : Typecheck.env -> Ast.expr -> derivation

(** Independently re-validate a derivation.  Does NOT call [derive]: it checks
    each node's rule against its premises from scratch, so a forged graph is
    rejected.  [Ok ()] iff every node is licensed by the rule it names. *)
val check : derivation -> (unit, check_error list) result

(** Number of nodes (judgements) in the graph. *)
val size : derivation -> int

(** Depth of the derivation tree. *)
val depth : derivation -> int

(** Render as an indented proof tree, conclusion first. *)
val to_string : derivation -> string

(** Render as Graphviz DOT — nodes are judgements, edges point from a
    conclusion to each premise. *)
val to_dot : derivation -> string
