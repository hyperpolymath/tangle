(* SPDX-License-Identifier: MPL-2.0 *)
(* tg7_braid_equiv.ml — tests for the out-of-band braid-group equivalence
 * checker (Braid_equiv, Dehornoy handle reduction).  TG-7 non-semantic rung.
 *
 * Correctness is established by THREE independent kinds of ground truth, so the
 * battery does not rely on handle reduction being bug-free a priori:
 *   1. the braid-group defining relations (must be equivalent);
 *   2. constructed equivalent pairs — start from a random word, apply random
 *      relation-preserving moves (free (de)cancellation, far commutation, the
 *      braid relation both ways), so v ≡ u BY CONSTRUCTION;  equiv u v must hold,
 *      and writhe/permutation (invariants) must agree (guards the generator);
 *   3. invariant-distinguished pairs — when writhe differs the braids are
 *      provably NOT equivalent, so equiv must return false.
 *)

module B = Tangle.Braid_equiv

let g i e : Tangle.Ast.generator = { gen_index = i; gen_exponent = e }
let s i = g i 1
let si i = g i (-1)

let pass = ref 0
let fail = ref 0
let ok name b = if b then incr pass else (incr fail; Printf.printf "  FAIL  %s\n" name)

(* ---- defining relations: must be equivalent ---- *)

let test_relations () =
  ok "refl s1 = s1"                 (B.equiv [s 1] [s 1]);
  ok "cancel s1 s1^-1 = e"          (B.equiv [s 1; si 1] []);
  ok "cancel s1^-1 s1 = e"          (B.equiv [si 1; s 1] []);
  ok "commute s1 s3 = s3 s1"        (B.equiv [s 1; s 3] [s 3; s 1]);
  ok "commute s1 s4 = s4 s1"        (B.equiv [s 1; s 4] [s 4; s 1]);
  ok "braid s1s2s1 = s2s1s2"        (B.equiv [s 1; s 2; s 1] [s 2; s 1; s 2]);
  ok "braid s2s3s2 = s3s2s3"        (B.equiv [s 2; s 3; s 2] [s 3; s 2; s 3]);
  ok "braid (neg) s1^-1 s2^-1 s1^-1 = s2^-1 s1^-1 s2^-1"
    (B.equiv [si 1; si 2; si 1] [si 2; si 1; si 2]);
  ok "derived s1s2s1 (s2s1s2)^-1 = e"
    (B.is_trivial [s 1; s 2; s 1; si 2; si 1; si 2]);
  ok "exponent s1^2 = s1 s1"        (B.equiv [g 1 2] [s 1; s 1]);
  ok "exponent s1^3 = s1 s1 s1"     (B.equiv [g 1 3] [s 1; s 1; s 1]);
  ok "exponent s1^-2 = s1^-1 s1^-1" (B.equiv [g 1 (-2)] [si 1; si 1]);
  (* far-commutation consequence: s1 s3 s1 s3 = s3 s1 s3 s1 *)
  ok "s1s3s1s3 = s3s1s3s1"          (B.equiv [s 1; s 3; s 1; s 3] [s 3; s 1; s 3; s 1])

(* ---- genuinely distinct braids: must NOT be equivalent ---- *)

let test_non_equiv () =
  ok "s1 <> e"            (not (B.equiv [s 1] []));
  ok "s1 <> s2"          (not (B.equiv [s 1] [s 2]));
  ok "s1 s2 <> s2 s1"    (not (B.equiv [s 1; s 2] [s 2; s 1]));
  ok "trefoil s1^3 <> e" (not (B.equiv [g 1 3] []));
  ok "s1 <> s1^-1"       (not (B.equiv [s 1] [si 1]));
  ok "s1s2s1 <> s1s2"    (not (B.equiv [s 1; s 2; s 1] [s 1; s 2]));
  ok "s1^2 <> s1"        (not (B.equiv [g 1 2] [s 1]))

(* ---- random relation-preserving moves (internal (idx,sgn) words) ---- *)

let max_idx = 5
let to_ast (w : (int * int) list) : Tangle.Ast.generator list =
  List.map (fun (i, sg) -> g i sg) w

let rand_word () : (int * int) list =
  let len = Random.int 9 in
  List.init len (fun _ -> (1 + Random.int max_idx, if Random.bool () then 1 else -1))

(* all relation-preserving rewrites applicable to w, as new words *)
let moves (w : (int * int) list) : (int * int) list list =
  let arr = Array.of_list w in
  let n = Array.length arr in
  let acc = ref [] in
  let add m = acc := m :: !acc in
  (* free insertion of a cancelling pair at every gap *)
  for p = 0 to n do
    let i = 1 + Random.int max_idx and sg = if Random.bool () then 1 else -1 in
    let pre = Array.to_list (Array.sub arr 0 p) in
    let post = Array.to_list (Array.sub arr p (n - p)) in
    add (pre @ [ (i, sg); (i, -sg) ] @ post)
  done;
  (* adjacent free cancellation *)
  for k = 0 to n - 2 do
    let (i, a) = arr.(k) and (j, b) = arr.(k + 1) in
    if i = j && a = -b then
      add (Array.to_list (Array.sub arr 0 k) @ Array.to_list (Array.sub arr (k + 2) (n - k - 2)))
  done;
  (* far commutation: swap adjacent σ with |i-j| >= 2 *)
  for k = 0 to n - 2 do
    let (i, _) = arr.(k) and (j, _) = arr.(k + 1) in
    if abs (i - j) >= 2 then begin
      let cp = Array.copy arr in
      let t = cp.(k) in cp.(k) <- cp.(k + 1); cp.(k + 1) <- t;
      add (Array.to_list cp)
    end
  done;
  (* braid relation both ways for a consistent sign: σi σ(i+1) σi <-> σ(i+1) σi σ(i+1) *)
  for k = 0 to n - 3 do
    let (a, sa) = arr.(k) and (b, sb) = arr.(k + 1) and (c, sc) = arr.(k + 2) in
    let pre = Array.to_list (Array.sub arr 0 k) in
    let post = Array.to_list (Array.sub arr (k + 3) (n - k - 3)) in
    if sa = sb && sb = sc then begin
      if b = a + 1 && c = a then
        add (pre @ [ (a + 1, sa); (a, sa); (a + 1, sa) ] @ post)   (* σiσ(i+1)σi -> σ(i+1)σiσ(i+1) *)
      else if b = a - 1 && c = a then
        add (pre @ [ (a - 1, sa); (a, sa); (a - 1, sa) ] @ post)   (* σ(i+1)σiσ(i+1) -> σiσ(i+1)σi (a=i+1) *)
    end
  done;
  !acc

let apply_random_moves (w0 : (int * int) list) (steps : int) : (int * int) list =
  let rec loop w k =
    if k <= 0 then w
    else
      match moves w with
      | [] -> w
      | ms -> loop (List.nth ms (Random.int (List.length ms))) (k - 1)
  in
  loop w0 steps

let test_constructed () =
  for _ = 1 to 400 do
    let u = rand_word () in
    let v = apply_random_moves u (3 + Random.int 12) in
    let ua = to_ast u and va = to_ast v in
    (* v ≡ u by construction → equiv must hold, both directions *)
    ok "constructed equiv u v" (B.equiv ua va);
    ok "constructed equiv v u" (B.equiv va ua);
    ok "constructed u v^-1 trivial" (B.is_trivial_word (B.units_of ua @ B.inverse (B.units_of va)));
    (* the move generator must preserve the invariants (guards the ground truth) *)
    ok "constructed writhe preserved" (B.writhe ua = B.writhe va);
    ok "constructed perm preserved"
      (B.permutation ~strands:(max_idx + 2) ua = B.permutation ~strands:(max_idx + 2) va)
  done

let test_invariant_negatives () =
  for _ = 1 to 200 do
    let u = rand_word () in
    (* append one generator → writhe changes by ±1 → provably NOT equivalent *)
    let extra = (1 + Random.int max_idx, if Random.bool () then 1 else -1) in
    let v = u @ [ extra ] in
    let ua = to_ast u and va = to_ast v in
    if B.writhe ua <> B.writhe va then
      ok "writhe-distinct => not equiv" (not (B.equiv ua va))
    else incr pass
  done

let () =
  Random.init 20260614;
  (match Array.to_list Sys.argv with
   | _ :: "--check" :: _ | [_] ->
     test_relations ();
     test_non_equiv ();
     test_constructed ();
     test_invariant_negatives ();
     Printf.printf "TG-7 braid_equiv: %d passed, %d failed\n" !pass !fail;
     if !fail > 0 then exit 1
   | _ -> prerr_endline "usage: tg7_braid_equiv [--check]"; exit 2)
