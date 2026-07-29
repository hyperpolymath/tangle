(* SPDX-License-Identifier: MPL-2.0 *)
(* quantity.ml — the QTT quantity semiring {0, 1, omega}.
 *
 * Quantitative Type Theory (Atkey 2018) annotates each binding with a quantity
 * drawn from a semiring.  With {0, 1, omega} that single mechanism subsumes
 * three disciplines rather than forcing a choice between them:
 *
 *     0      erased      present for typing, absent at runtime
 *     1      linear      used exactly once
 *     omega  unrestricted  used freely
 *
 * ── Why TANGLE needs the semiring and not one discipline ────────────────────
 * The requirement is genuinely mixed, which is why "make the language linear"
 * or "make it affine" are both wrong answers:
 *
 *   * BRAID WORDS are unrestricted (omega).  `x . x` is sigma_1^2 — composing
 *     a braid with itself is a legitimate braid, not resource duplication.
 *     Linearity would forbid a valid program.
 *
 *   * STRANDS inside a `weave` are LINEAR (1).  A strand is a physical thread:
 *     it is used exactly once, and it must come out the other side.  Braids are
 *     permutations of n strands and strand count is a conservation law, so
 *     AFFINE is specifically wrong here — affine permits discarding, and a
 *     strand cannot vanish.
 *
 *   * The CLAIM in `Epi[k, rho, tau]` (TG-11) is erased (0): it fixes the type
 *     and is never observable.  Assumption A-TG-11.1 records that the current
 *     encoding carries it instead, because erasing it without quantities would
 *     break uniqueness of typing.  This module is the missing half.
 *
 * ── Scope ───────────────────────────────────────────────────────────────────
 * This provides the semiring and applies it to STRAND usage, which is where
 * the discipline actually bites and where a real soundness gap exists.  It is
 * NOT a QTT conversion of the whole core: TANGLE's judgement is still
 * `Gamma |- e : tau` without quantities on ordinary bindings.  Doing that means
 * changing the judgement shape and re-proving the metatheory, and is tracked
 * separately.
 *)

(** A quantity from the {0, 1, omega} semiring. *)
type t =
  | Zero    (** erased: present for typing, absent at runtime *)
  | One     (** linear: used exactly once *)
  | Omega   (** unrestricted *)

let to_string = function
  | Zero -> "0" | One -> "1" | Omega -> "omega"

(** Semiring addition.  Combines the quantities of two INDEPENDENT uses —
    e.g. the two operands of a crossing.  Using something once in each of two
    places is using it twice, which is unrestricted usage, so 1 + 1 = omega
    rather than an error: the error is raised later by [check_linear], when the
    binding's declared quantity is compared against its total use. *)
let add a b =
  match a, b with
  | Zero, x | x, Zero -> x
  | One, One          -> Omega
  | Omega, _ | _, Omega -> Omega

(** Semiring multiplication.  Scales a usage by the context it sits in — a
    binding used once inside something used twice is used twice.  Zero
    annihilates: nothing inside an erased position is used at all. *)
let mul a b =
  match a, b with
  | Zero, _ | _, Zero -> Zero
  | One, x | x, One   -> x
  | Omega, Omega      -> Omega

(** Additive identity. *)
let zero = Zero

(** Multiplicative identity. *)
let one = One

(** Is [actual] usage permitted where [declared] was promised?

    * [Zero]  demands NO use at runtime.
    * [One]   demands EXACTLY one — neither zero (the resource vanishes) nor
              more (it is duplicated).  This is what makes it linear rather
              than affine: [Zero] actual is a violation.
    * [Omega] permits anything. *)
let permits ~declared ~actual =
  match declared, actual with
  | Zero,  Zero  -> true
  | Zero,  _     -> false
  | One,   One   -> true
  | One,   _     -> false
  | Omega, _     -> true

(** Why a usage was rejected, in words a programmer can act on. *)
let explain ~declared ~actual =
  match declared, actual with
  | One, Zero ->
    "declared linear (used exactly once) but never used — a strand cannot \
     vanish; braids conserve strand count"
  | One, Omega ->
    "declared linear (used exactly once) but used more than once — a strand \
     cannot be duplicated"
  | Zero, _ ->
    "declared erased (quantity 0) but used at runtime"
  | _ ->
    Printf.sprintf "declared %s but used %s" (to_string declared) (to_string actual)
