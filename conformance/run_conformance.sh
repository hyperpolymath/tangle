#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0-or-later
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
    PARSER_CMD=(dune exec --root "${SCRIPT_DIR}/../compiler" -- tangle --parse-only)
fi

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
