#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Conformance test runner for Tangle
#
# Three tiers, because "rejected" is not one property:
#
#   valid/      MUST parse AND MUST typecheck
#   invalid/    MUST FAIL TO PARSE          (grammar-level rejection)
#   ill-typed/  MUST PARSE but MUST FAIL to typecheck
#
# The third tier carries a DOUBLE assertion on purpose.  Asserting only "the
# compiler rejects it" is the failure this suite already suffered once: an
# invalid case scores a point whenever the command fails, including when it
# fails for an unrelated reason.  Requiring the file to parse FIRST proves the
# rejection came from the typechecker and not from a typo in the test.
#
# Usage: ./run_conformance.sh [path-to-tangle-binary]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Build PARSER_CMD as an array so we never need `eval`. If the caller
# passes a parser command as $1, split it on whitespace; otherwise use
# the default command directly.
if [[ -n "${1:-}" ]]; then
    # shellcheck disable=SC2206 # deliberate word-splitting of caller's string
    PARSER_CMD=(${1})
else
    # The default used to be `dune exec -- tangle --parse-only`. BOTH halves were
    # wrong: the executable is named `main` (compiler/bin/dune), not `tangle`, and
    # there has never been a `--parse-only` flag — bare `<file>` is parse +
    # pretty-print. So every invocation failed, which made this suite REPORT
    # 3/19 while proving nothing: the three "passes" were invalid/ cases, and an
    # invalid case "passes" precisely when the command fails. It failed for the
    # wrong reason and scored a point for it.
    #
    # Prefer a pre-built binary (CI builds once); fall back to `dune exec`.
    BIN="${SCRIPT_DIR}/../compiler/_build/default/bin/main.exe"
    if [[ -x "${BIN}" ]]; then
        PARSER_CMD=("${BIN}")
    else
        PARSER_CMD=(dune exec --root "${SCRIPT_DIR}/../compiler" -- ./bin/main.exe)
    fi
fi

# The typechecker is the same binary with --check.  Built as a separate array
# so a caller-supplied PARSER_CMD still gets the flag appended correctly.
CHECK_CMD=("${PARSER_CMD[@]}" --check)

echo "parser:      ${PARSER_CMD[*]}"
echo "typechecker: ${CHECK_CMD[*]}"

PASS=0
FAIL=0
TOTAL=0

# --- Valid programs: MUST parse AND MUST typecheck ---
for f in "${SCRIPT_DIR}"/valid/*.tangle; do
    TOTAL=$((TOTAL + 1))
    name="$(basename "$f")"
    if ! "${PARSER_CMD[@]}" "$f" >/dev/null 2>&1; then
        echo "  FAIL  valid/${name}  (expected to parse, got a parse error)"
        FAIL=$((FAIL + 1))
    elif ! "${CHECK_CMD[@]}" "$f" >/dev/null 2>&1; then
        echo "  FAIL  valid/${name}  (parses, but does not typecheck)"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS  valid/${name}"
        PASS=$((PASS + 1))
    fi
done

# --- Invalid programs: parser MUST fail ---
for f in "${SCRIPT_DIR}"/invalid/*.tangle; do
    TOTAL=$((TOTAL + 1))
    name="$(basename "$f")"
    if "${PARSER_CMD[@]}" "$f" >/dev/null 2>&1; then
        echo "  FAIL  invalid/${name}  (expected failure, got success)"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS  invalid/${name}"
        PASS=$((PASS + 1))
    fi
done

# --- Ill-typed programs: MUST parse, MUST NOT typecheck ---
for f in "${SCRIPT_DIR}"/ill-typed/*.tangle; do
    TOTAL=$((TOTAL + 1))
    name="$(basename "$f")"
    if ! "${PARSER_CMD[@]}" "$f" >/dev/null 2>&1; then
        # Not a pass. The file was supposed to reach the typechecker; if it
        # cannot even parse, the test is broken and proves nothing.
        echo "  FAIL  ill-typed/${name}  (must PARSE first — got a parse error)"
        FAIL=$((FAIL + 1))
    elif "${CHECK_CMD[@]}" "$f" >/dev/null 2>&1; then
        echo "  FAIL  ill-typed/${name}  (typechecker accepted an ill-typed program)"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS  ill-typed/${name}"
        PASS=$((PASS + 1))
    fi
done

echo ""
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"

if [ "${FAIL}" -gt 0 ]; then
    exit 1
fi
