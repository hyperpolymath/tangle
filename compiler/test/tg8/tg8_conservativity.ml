(* SPDX-License-Identifier: MPL-2.0 *)
(* tg8_conservativity.ml — TG-8 template: the virtual-knot dialect is a
 * CONSERVATIVE EXTENSION of the core braid language (Dialect_vk).
 *
 * "Conservative extension" = adding the dialect does not change the core
 * sub-theory.  We verify, with random ground truth:
 *   (1) faithful embedding: project (embed w) = Some w;
 *   (2) the dialect DECIDES core (real) terms exactly as the core procedure
 *       Braid_equiv (TG-7) — decide_trivial (embed w) = Some (BE.is_trivial w),
 *       equiv (embed u) (embed v) = Some (BE.equiv u v);
 *   (3) the dialect's invariants agree with the core on real words;
 *   (4) the extension is PROPER: virtual crossings give genuinely-new,
 *       non-real elements, and virtual involution holds;
 *   (5) honest frontier: irreducible mixed virtual content is reported
 *       UNDECIDED (None), never guessed.
 *)

module VK = Tangle.Dialect_vk
module BE = Tangle.Braid_equiv

let g i e : Tangle.Ast.generator = { gen_index = i; gen_exponent = e }

let pass = ref 0
let fail = ref 0
let ok name b = if b then incr pass else (incr fail; Printf.printf "  FAIL  %s\n" name)

let max_idx = 5
let rand_real () : Tangle.Ast.generator list =
  let len = Random.int 9 in
  List.init len (fun _ -> g (1 + Random.int max_idx) (if Random.bool () then 1 else -1))

(* ---- (1) faithful embedding + (2,3) conservativity on the real fragment ---- *)

let test_conservativity () =
  for _ = 1 to 400 do
    let w = rand_real () in
    ok "faithful: project (embed w) = Some w" (VK.project (VK.embed w) = Some w);
    ok "real terms always decided" (VK.decide_trivial (VK.embed w) <> None);
    ok "decide_trivial (embed w) = core is_trivial"
      (VK.decide_trivial (VK.embed w) = Some (BE.is_trivial w));
    ok "perm (embed w) = core perm"
      (VK.permutation ~strands:(max_idx + 2) (VK.embed w)
       = BE.permutation ~strands:(max_idx + 2) w);
    ok "writhe (embed w) = core writhe" (VK.writhe (VK.embed w) = BE.writhe w)
  done;
  for _ = 1 to 300 do
    let u = rand_real () and v = rand_real () in
    ok "equiv (embed u) (embed v) = core equiv"
      (VK.equiv (VK.embed u) (VK.embed v) = Some (BE.equiv u v))
  done

(* ---- (4) proper extension + virtual involution ---- *)

let test_proper_extension () =
  let v1 = [ VK.Virt 1 ] in
  ok "v1 has virtual content" (VK.has_virtual v1);
  ok "v1 is not a real braid" (not (VK.is_real v1));
  ok "v1 does not project to core" (VK.project v1 = None);
  (* v1 induces the transposition (1 2) -> not the identity braid *)
  ok "v1 permutation /= identity"
    (VK.permutation ~strands:3 v1 <> [| 1; 2; 3 |]);
  (* virtual involution: v_i v_i = e *)
  ok "involution v1 v1 = e" (VK.decide_trivial [ VK.Virt 1; VK.Virt 1 ] = Some true);
  ok "involution v3 v3 = e" (VK.decide_trivial [ VK.Virt 3; VK.Virt 3 ] = Some true);
  (* mixed word whose virtuals cancel reduces to a (trivial) real word *)
  ok "mixed cancels: s1 v1 v1 s1^-1 = e"
    (VK.decide_trivial [ VK.Real (g 1 1); VK.Virt 1; VK.Virt 1; VK.Real (g 1 (-1)) ] = Some true);
  (* writhe ignores virtual crossings *)
  ok "writhe ignores virtual" (VK.writhe [ VK.Real (g 1 1); VK.Virt 1; VK.Virt 2 ] = 1)

(* ---- (5) honest partial-decision frontier ---- *)

let test_frontier () =
  (* irreducible mixed virtual content -> undecided, never guessed *)
  ok "mixed residue undecided: v1 s1" (VK.decide_trivial [ VK.Virt 1; VK.Real (g 1 1) ] = None);
  ok "mixed residue undecided: s1 v2" (VK.decide_trivial [ VK.Real (g 1 1); VK.Virt 2 ] = None);
  (* a lone virtual crossing: not reducible by involution/free rules -> undecided
     (it is in fact non-trivial, witnessed by its permutation above) *)
  ok "lone v1 undecided by reducer" (VK.decide_trivial [ VK.Virt 1 ] = None)

let () =
  Random.init 20260614;
  (match Array.to_list Sys.argv with
   | _ :: "--check" :: _ | [_] ->
     test_conservativity ();
     test_proper_extension ();
     test_frontier ();
     Printf.printf "TG-8 conservativity: %d passed, %d failed\n" !pass !fail;
     if !fail > 0 then exit 1
   | _ -> prerr_endline "usage: tg8_conservativity [--check]"; exit 2)
