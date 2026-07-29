#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# check-corpus.sh — gate the RUNNABLE corpus: examples/ and conformance/.
#
# ── Why this exists ────────────────────────────────────────────────────────
# Neither examples/ nor conformance/ was executed by anything — not CI, not the
# Justfile. The cost of that was concrete: `examples/isotopy.tangle`, the file
# whose entire purpose is to demonstrate the language's central claim ("two
# braids can be structurally different but topologically equivalent"), FAILED
# with "Assertion failed" and had done for as long as `~` used free reduction.
# It only began passing when TG-7 (#50/#87) made `~` decide real braid-group
# equivalence. A showcase example can sit broken indefinitely if nothing runs it.
#
# ── Why a RATCHET rather than a pass/fail ──────────────────────────────────
# Five example programs do not typecheck and five conformance `valid/` programs
# do not parse. Those are real gaps (see below), not things to paper over — but
# they also cannot be fixed in the change that introduces the gate. So each
# known failure is recorded EXPLICITLY here with its cause. The gate then
# enforces, in both directions:
#
#   * nothing currently working may break  (regression)
#   * nothing may join the known-bad lists  (new debt)
#   * anything that starts working MUST be removed from the list (the ratchet
#     tightens — a stale entry is itself a failure)
#
# That last rule is what stops an "expected failures" list decaying into a
# permanent excuse.
#
# USAGE:  scripts/check-corpus.sh [path-to-tangle-binary]
# EXIT:   0 = corpus matches the manifest exactly; 1 = drift in either direction

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${1:-${ROOT}/compiler/_build/default/bin/main.exe}"

if [[ ! -x "${BIN}" ]]; then
  echo "::error::tangle binary not found or not executable: ${BIN}"
  echo "Build it first:  (cd compiler && dune build)"
  exit 1
fi

# ── MANIFEST ───────────────────────────────────────────────────────────────
# Examples that must fully TYPECHECK and EVALUATE (all their asserts hold).
EXAMPLES_MUST_RUN=(
  braids_as_data.tangle
  epistemic.tangle        # TG-11 — warranted claims, non-factive
  compositional_pd.tangle
  echo_pd.tangle
  isotopy.tangle          # the TG-7 witness — see header
  tensor_product.tangle
  trefoil.tangle
  turing_complete.tangle
)

# Examples that parse but do not yet typecheck. EMPTY as of #92 + the
# statement-order fix: all seven examples now typecheck AND evaluate, so they
# are all in EXAMPLES_MUST_RUN above. Keep this list empty — an entry here is
# debt, and the ratchet fails the build if a listed file starts working.
EXAMPLES_KNOWN_UNTYPED=(
)

# conformance/valid programs the parser does not yet accept.
# EMPTY as of #94 (the JTV add{} island). All 19 valid programs parse.
CONFORMANCE_KNOWN_UNPARSED=(
)

# conformance/valid programs that PARSE but do not yet TYPECHECK+EVALUATE.
# EMPTY as of #94. All 19 valid programs run. Keep it empty: an entry here is
# debt, and the ratchet fails the build if a listed file starts working.
CONFORMANCE_KNOWN_UNRUNNABLE=(
)

fail=0
note() { printf '  %-34s %s\n' "$1" "$2"; }

in_list() { local n="$1"; shift; local x; for x in "$@"; do [[ "$x" == "$n" ]] && return 0; done; return 1; }

# ── 1. Every example must PARSE. No exceptions: a file that cannot even parse
#       is not documentation, it is a syntax error with a licence header.
echo "== examples: parse =="
for f in "${ROOT}"/examples/*.tangle; do
  n="$(basename "$f")"
  if "${BIN}" "$f" >/dev/null 2>&1; then note "$n" "parse ok"; else
    note "$n" "PARSE FAILED"; echo "::error::${n} does not parse"; fail=1; fi
done

# ── 2. The working examples must keep typechecking AND evaluating.
echo "== examples: typecheck + evaluate (must-run set) =="
for n in "${EXAMPLES_MUST_RUN[@]}"; do
  f="${ROOT}/examples/${n}"
  if [[ ! -f "$f" ]]; then
    echo "::error::manifest lists ${n} but the file is gone"; fail=1; continue; fi
  if "${BIN}" --eval "$f" >/dev/null 2>&1; then note "$n" "eval ok"; else
    note "$n" "EVAL FAILED"
    echo "::error::${n} must evaluate cleanly (all asserts holding) and does not:"
    "${BIN}" --eval "$f" 2>&1 | head -5
    fail=1
  fi
done

# ── 3. The known-untyped examples: still parse, still fail to typecheck.
#       If one starts typechecking, the manifest is STALE and must be updated.
echo "== examples: known-untyped (ratchet) =="
for n in "${EXAMPLES_KNOWN_UNTYPED[@]}"; do
  f="${ROOT}/examples/${n}"
  if [[ ! -f "$f" ]]; then
    echo "::error::manifest lists ${n} but the file is gone"; fail=1; continue; fi
  if "${BIN}" --eval "$f" >/dev/null 2>&1; then
    note "$n" "NOW WORKS"
    echo "::error::${n} now evaluates — good! Move it to EXAMPLES_MUST_RUN and drop it from EXAMPLES_KNOWN_UNTYPED."
    fail=1
  else
    note "$n" "still untyped (expected)"
  fi
done

# ── 4. Any example NOT in either list is unaccounted for.
echo "== examples: manifest covers every file =="
for f in "${ROOT}"/examples/*.tangle; do
  n="$(basename "$f")"
  if ! in_list "$n" "${EXAMPLES_MUST_RUN[@]}" && ! in_list "$n" "${EXAMPLES_KNOWN_UNTYPED[@]}"; then
    note "$n" "UNLISTED"
    echo "::error::${n} is in examples/ but not in the manifest. Add it to EXAMPLES_MUST_RUN (preferred) or, with a recorded cause, EXAMPLES_KNOWN_UNTYPED."
    fail=1
  fi
done

# ── 5. Conformance: valid must parse (except the recorded set); invalid must NOT.
echo "== conformance =="
for f in "${ROOT}"/conformance/valid/*.tangle; do
  n="$(basename "$f")"
  if "${BIN}" "$f" >/dev/null 2>&1; then
    if in_list "$n" "${CONFORMANCE_KNOWN_UNPARSED[@]}"; then
      note "valid/$n" "NOW PARSES"
      echo "::error::conformance/valid/${n} now parses — drop it from CONFORMANCE_KNOWN_UNPARSED."
      fail=1
    else
      note "valid/$n" "parse ok"
    fi
  else
    if in_list "$n" "${CONFORMANCE_KNOWN_UNPARSED[@]}"; then
      note "valid/$n" "still unparsed (expected)"
    else
      note "valid/$n" "PARSE FAILED"
      echo "::error::conformance/valid/${n} must parse and does not"; fail=1
    fi
  fi
done
# conformance/valid must also RUN, not merely parse.
# Parsing alone was never enough: `examples/trefoil.tangle` and
# `conformance/valid/v16_close_mirror_reverse.tangle` BOTH asserted
# `reverse(w) == <w with order reversed>`, forgetting that `reverse` also
# negates exponents and so yields the inverse braid. Both were mathematically
# false — disproved by writhe, which is invariant under the braid relations —
# and both sat undetected because the gate only checked that they parsed.
echo "== conformance: valid programs must EVALUATE =="
for f in "${ROOT}"/conformance/valid/*.tangle; do
  n="$(basename "$f")"
  if "${BIN}" --eval "$f" >/dev/null 2>&1; then
    if in_list "$n" "${CONFORMANCE_KNOWN_UNRUNNABLE[@]}"; then
      note "valid/$n" "NOW RUNS"
      echo "::error::conformance/valid/${n} now evaluates — drop it from CONFORMANCE_KNOWN_UNRUNNABLE."
      fail=1
    else
      note "valid/$n" "evaluates ok"
    fi
  else
    if in_list "$n" "${CONFORMANCE_KNOWN_UNRUNNABLE[@]}"; then
      note "valid/$n" "still not runnable (expected)"
    else
      note "valid/$n" "EVAL FAILED"
      echo "::error::conformance/valid/${n} parses but does not evaluate:"
      "${BIN}" --eval "$f" 2>&1 | head -3
      fail=1
    fi
  fi
done

for f in "${ROOT}"/conformance/invalid/*.tangle; do
  n="$(basename "$f")"
  if "${BIN}" "$f" >/dev/null 2>&1; then
    note "invalid/$n" "PARSED (should not)"
    echo "::error::conformance/invalid/${n} parsed successfully but is meant to be rejected"; fail=1
  else
    note "invalid/$n" "rejected ok"
  fi
done

# ── 6. Conformance: ill-typed programs must PARSE and then be REJECTED.
#
# A third tier, separate from invalid/, because "the compiler rejects it" is
# two different properties and conflating them produces a gate that passes for
# the wrong reason. invalid/ is grammar-level: the file must not parse.
# ill-typed/ is type-level: the file MUST parse — reaching the typechecker is
# the whole point of the test — and the typechecker must then reject it.
#
# Asserting only the rejection is precisely the failure this suite already had
# once, when three invalid/ cases "passed" because the command was wrong and
# failed on every input. A typo in an ill-typed/ fixture would score the same
# false point here, so the parse step is asserted first.
echo
echo "== conformance: ill-typed programs must parse, then be rejected =="
for f in "${ROOT}"/conformance/ill-typed/*.tangle; do
  [[ -e "$f" ]] || continue
  n="$(basename "$f")"
  if ! "${BIN}" "$f" >/dev/null 2>&1; then
    note "ill-typed/$n" "PARSE FAILED (must parse first)"
    echo "::error::conformance/ill-typed/${n} does not parse — it must reach the typechecker to prove anything"; fail=1
  elif "${BIN}" --check "$f" >/dev/null 2>&1; then
    note "ill-typed/$n" "TYPECHECKED (should not)"
    echo "::error::conformance/ill-typed/${n} was accepted by the typechecker but is meant to be rejected"; fail=1
  else
    note "ill-typed/$n" "parsed, then rejected ok"
  fi
done

echo
if [[ "$fail" -ne 0 ]]; then
  echo "::error::corpus drifted from the manifest — see the errors above."
  exit 1
fi
echo "Corpus matches the manifest: examples parse, the must-run set evaluates,"
echo "known gaps are unchanged, invalid programs are still rejected, and"
echo "ill-typed programs still parse but still fail to typecheck."
