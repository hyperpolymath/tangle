(* SPDX-License-Identifier: MPL-2.0 *)
(* braid_equiv.ml — decide braid-GROUP equivalence of braid words via Dehornoy
 * handle reduction.
 *
 * TG-7, NON-SEMANTIC rung.  The language's `==` on braids (eval.ml `VBraid`
 * equality and the Lean `Step.eqBraids` rule) is LIST equality and is left
 * UNCHANGED by this module — `braid_equiv` is an out-of-band decision procedure
 * for callers who want true braid-group equivalence (e.g. tooling, future
 * `compute`-style checks).  Changing `==` itself to use this is a separate
 * language-design decision (see PROOF-NEEDS.md TG-7).
 *
 * Algorithm (Dehornoy 1997, "A fast method for comparing braids").  A braid
 * word on σ₁,σ₂,…  A σᵢ-handle is a factor
 *     σᵢ^e · w₀ · σ_{i+1}^d · w₁ · σ_{i+1}^d · ⋯ · σ_{i+1}^d · w_m · σᵢ^{-e}
 * with e,d ∈ {±1}, where every wₖ uses only generators σⱼ with j ≥ i+2 (so the
 * interior contains no σᵢ, no σ_{<i}, and the σ_{i+1} all share the sign d).  It
 * reduces to
 *     w₀ · (σ_{i+1}^{-e} σᵢ^d σ_{i+1}^e) · w₁ · ⋯ · (σ_{i+1}^{-e} σᵢ^d σ_{i+1}^e) · w_m
 * (the m = 0 case is plain free cancellation σᵢ^e wₐ σᵢ^{-e} → wₐ).  Handle
 * reduction terminates and a reduced word is empty iff the braid is trivial, so
 *     equiv u v  ⇔  reduce (u · v⁻¹) = ε.
 *
 * Correctness here is established BY TESTING (compiler/test/tg7): the defining
 * relations, randomly-constructed equivalent pairs (ground truth from the group
 * relations), and the writhe/permutation invariants.  A mechanised Garside/
 * Dehornoy correctness proof in Lean is the research-grade rung and is NOT
 * claimed.  A safety step-bound guards against any non-termination surprise.
 *)

(* A braid word as a list of UNIT letters (index ≥ 1, sign ±1). *)
type letter = { idx : int; sgn : int }

let units_of (gs : Ast.generator list) : letter list =
  List.concat_map (fun (g : Ast.generator) ->
    let s = if g.gen_exponent >= 0 then 1 else -1 in
    List.init (abs g.gen_exponent) (fun _ -> { idx = g.gen_index; sgn = s })) gs

(* inverse braid: reverse order, negate each sign.  (ab)⁻¹ = b⁻¹a⁻¹. *)
let inverse (w : letter list) : letter list =
  List.rev_map (fun l -> { l with sgn = - l.sgn }) w

(* free reduction: cancel adjacent σ·σ⁻¹.  Sound (group inverses); keeps words
   short.  (Adjacent cancellation is itself the empty-interior handle case, but
   doing it eagerly speeds convergence.) *)
let free_reduce (w : letter list) : letter list =
  List.fold_right (fun x acc ->
    match acc with
    | y :: rest when x.idx = y.idx && x.sgn = - y.sgn -> rest
    | _ -> x :: acc) w []

(* Find and reduce the leftmost handle.  Returns None if the word is handle-free. *)
let reduce_one (w : letter list) : letter list option =
  let arr = Array.of_list w in
  let n = Array.length arr in
  (* Does position [a] open a handle?  If so return its closing index [b]. *)
  let handle_at a =
    let i = arr.(a).idx and e = arr.(a).sgn in
    let rec scan k d_opt =
      if k >= n then None                              (* no close → not a handle *)
      else
        let j = arr.(k).idx and s = arr.(k).sgn in
        if j = i then (if s = -e then Some k else None)  (* close, or same-sign σᵢ → blocked *)
        else if j < i then None                          (* σ_{<i} inside → blocked *)
        else if j = i + 1 then
          (match d_opt with
           | None -> scan (k + 1) (Some s)
           | Some d -> if d = s then scan (k + 1) d_opt else None) (* mixed σ_{i+1} signs *)
        else scan (k + 1) d_opt                          (* j ≥ i+2 → interior wₖ, ok *)
    in
    scan (a + 1) None
  in
  let rec find a =
    if a >= n then None
    else match handle_at a with Some b -> Some (a, b) | None -> find (a + 1)
  in
  match find 0 with
  | None -> None
  | Some (a, b) ->
    let i = arr.(a).idx and e = arr.(a).sgn in
    let interior = Array.to_list (Array.sub arr (a + 1) (b - a - 1)) in
    let rewritten =
      List.concat_map (fun l ->
        if l.idx = i + 1 then
          (* σ_{i+1}^d → σ_{i+1}^{-e} σᵢ^d σ_{i+1}^e *)
          [ { idx = i + 1; sgn = -e }; { idx = i; sgn = l.sgn }; { idx = i + 1; sgn = e } ]
        else [ l ]) interior
    in
    let prefix = Array.to_list (Array.sub arr 0 a) in
    let suffix = Array.to_list (Array.sub arr (b + 1) (n - b - 1)) in
    Some (prefix @ rewritten @ suffix)

let default_max_steps = 1_000_000

(* Reduce to a handle-free (and freely-reduced) word. *)
let reduce ?(max_steps = default_max_steps) (w0 : letter list) : letter list =
  let rec loop steps w =
    if steps <= 0 then w                      (* safety net; never hit in tests *)
    else match reduce_one w with
      | None -> w
      | Some w' -> loop (steps - 1) (free_reduce w')
  in
  loop max_steps (free_reduce w0)

(* A braid word is trivial (= identity) iff it reduces to the empty word. *)
let is_trivial_word (w : letter list) : bool = reduce w = []

let is_trivial (gs : Ast.generator list) : bool = is_trivial_word (units_of gs)

(* u ≡ v in the braid group  ⇔  u·v⁻¹ is trivial. *)
let equiv (u : Ast.generator list) (v : Ast.generator list) : bool =
  is_trivial_word (units_of u @ inverse (units_of v))

(* ---- invariants (necessary conditions; exposed for callers/tests) ---- *)

(* writhe = exponent sum (abelianisation); invariant under braid relations. *)
let writhe (gs : Ast.generator list) : int =
  List.fold_left (fun a (g : Ast.generator) -> a + g.gen_exponent) 0 gs

(* underlying permutation on 1..n as an array p where p.(k-1) = image of strand k;
   each σᵢ (any sign) transposes strands i,i+1. *)
let permutation ~(strands : int) (gs : Ast.generator list) : int array =
  let p = Array.init strands (fun k -> k + 1) in
  List.iter (fun (g : Ast.generator) ->
    let i = g.gen_index in
    if i >= 1 && i < strands then begin
      let t = p.(i - 1) in p.(i - 1) <- p.(i); p.(i) <- t
    end) gs;
  p
