#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# SessionStart hook — make Lean available in Claude Code on the web so the
# proofs in proofs/Tangle.lean can be built and verified (the repo's working
# rule: "every edit ends with a Lean compile").
#
# Thin wrapper over proofs/bootstrap-lean.sh (the single source of truth for
# toolchain setup). Synchronous: guarantees Lean is ready before the agent
# loop starts, so it never races a build/verify against a half-installed
# toolchain. Web/remote sessions only; local developers use their own Lean.
set -euo pipefail

[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0

REPO="${CLAUDE_PROJECT_DIR:-$(pwd)}"
BOOT="$REPO/proofs/bootstrap-lean.sh"
if [ ! -x "$BOOT" ]; then
  echo "session-start: $BOOT not found or not executable; skipping Lean bootstrap."
  exit 0
fi

# Install the pinned toolchain (idempotent; ~16s cold, instant when cached).
# A failure must not block the whole session — Lean just won't be ready, and
# the developer can run proofs/bootstrap-lean.sh by hand.
if "$BOOT"; then
  # Persist `lean` on PATH for the rest of the session.
  if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    "$BOOT" --print-path >> "$CLAUDE_ENV_FILE"
  fi
else
  echo "session-start: Lean bootstrap failed; continuing without Lean." \
       "Run proofs/bootstrap-lean.sh manually once network is available." >&2
fi
exit 0
