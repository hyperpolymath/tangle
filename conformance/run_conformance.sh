#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Conformance test runner for Tangle
#
# Invokes the Tangle compiler (OCaml/Menhir) on every file in valid/
# and invalid/, asserting success for valid files and failure for invalid files.
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

echo "parser: ${PARSER_CMD[*]}"

PASS=0
FAIL=0
TOTAL=0

# --- Valid programs: parser MUST succeed ---
for f in "${SCRIPT_DIR}"/valid/*.tangle; do
    TOTAL=$((TOTAL + 1))
    name="$(basename "$f")"
    if "${PARSER_CMD[@]}" "$f" >/dev/null 2>&1; then
        echo "  PASS  valid/${name}"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  valid/${name}  (expected success, got failure)"
        FAIL=$((FAIL + 1))
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

echo ""
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"

if [ "${FAIL}" -gt 0 ]; then
    exit 1
fi
