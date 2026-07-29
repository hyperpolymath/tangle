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
 * ── Coverage ────────────────────────────────────────────────────────────────
 * Every rule the graph can name is re-derived by [check], with one exception:
 * [T-Add-Block], whose island is typed by a separate judgement (⊢_hd).  That
 * exception is REPORTED by [unchecked] rather than hidden behind a silent
 * accept, because a rule the checker waves through is a hole — any conclusion
 * passes it, and "the graph checks" then means less than it appears to.
 *
 * ── Relation to TG-11 (epistemic types) ─────────────────────────────────────
 * A checked derivation is exactly what `Epi[κ, ρ, τ]` is for: standpoint κ
 * holds evidence ρ for claim τ.  The JEG is the ρ.  And the non-factivity of
 * TG-11 is the right discipline here too: holding a derivation is not the same
 * as the judgement being true — you must CHECK it.  [check] is the
 * `SoundWarrant.sound` of this module.
 *)

(** A single judgement: Γ; Σ ⊢ e : τ.  The contexts record only the bindings the
    derivation actually consults, so the graph stays readable.

    [j_ctx] carries full environment entries, not just value types, because a
    T-App node cannot be re-derived without the callee's SIGNATURE — and a node
    that cannot be re-derived is a hole a forger can put anything through.

    [j_sigma] is the strand context, for the same reason: [T-Crossing] and
    [T-Weave] read Σ rather than premise types, so without it they were bare
    leaves asserting a type with nothing licensing it. *)
type judgement = {
  j_ctx   : (string * Typecheck.env_entry) list;
  j_sigma : (string * Typecheck.strand_entry) list;
  j_expr  : Ast.expr;
  j_ty    : Typecheck.ty;
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

(** As [derive], but starting inside a given strand context — the form needed
    to derive an expression that mentions strand names. *)
val derive_in : Typecheck.env -> Typecheck.strand_ctx -> Ast.expr -> derivation

(** Independently re-validate a derivation.  Does NOT call [derive]: it checks
    each node's rule against its premises from scratch, so a forged graph is
    rejected.  [Ok ()] iff every node is licensed by the rule it names. *)
val check : derivation -> (unit, check_error list) result

(** The nodes [check] accepted WITHOUT re-deriving them, with the rule name.

    A rule the checker cannot recompute is a hole: any conclusion passes through
    it. Rather than hide those behind a silent accept, they are counted, so
    "check succeeded" and "check succeeded and re-derived every node" are
    distinguishable results. Currently the only such rule is [T-Add-Block],
    whose island has its own judgement (⊢_hd). *)
val unchecked : derivation -> (string * judgement) list

(** Number of nodes (judgements) in the graph. *)
val size : derivation -> int

(** Depth of the derivation tree. *)
val depth : derivation -> int

(** Render as an indented proof tree, conclusion first. *)
val to_string : derivation -> string

(** Render as Graphviz DOT — nodes are judgements, edges point from a
    conclusion to each premise. *)
val to_dot : derivation -> string
