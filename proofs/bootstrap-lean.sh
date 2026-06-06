#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# bootstrap-lean.sh — install the pinned Lean 4 toolchain so the proofs in
# this directory can be built and verified.
#
# WHY THIS EXISTS
#   proofs/Tangle.lean is the repo's build oracle (.github/workflows/
#   lean-proofs.yml) and the working rule is "every edit ends with a Lean
#   compile". GitHub Actions runners have open network and install Lean fine,
#   but sandboxed/allowlisted environments (e.g. Claude Code on the web)
#   cannot reach elan's default dist server release.lean-lang.org. GitHub
#   release assets ARE reachable, so when the normal install path is blocked
#   this script fetches the pinned toolchain directly from github.com.
#
#   The version is read from proofs/lean-toolchain, so this stays correct
#   when the pin is bumped. Idempotent and non-interactive.
#
# USAGE
#   ./proofs/bootstrap-lean.sh        # install the toolchain
#   eval "$(./proofs/bootstrap-lean.sh --print-path)"   # and put lean on PATH
#   # then:
#   cd proofs && lean Tangle.lean     # 0 errors == proofs verified
set -euo pipefail

PRINT_PATH=0
[ "${1:-}" = "--print-path" ] && PRINT_PATH=1

# Resolve repo paths relative to this script.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIN_FILE="$SCRIPT_DIR/lean-toolchain"

log() { [ "$PRINT_PATH" -eq 1 ] || echo "bootstrap-lean: $*"; }

if [ ! -f "$PIN_FILE" ]; then
  echo "bootstrap-lean: no $PIN_FILE found" >&2
  exit 1
fi

PIN="$(tr -d '[:space:]' < "$PIN_FILE")"             # e.g. leanprover/lean4:v4.14.0
VER="${PIN##*:}"                                      # v4.14.0
VNUM="${VER#v}"                                       # 4.14.0
ELAN_DIR="${ELAN_HOME:-$HOME/.elan}"
TC_NAME="$(printf '%s' "$PIN" | sed 's|/|--|; s|:|---|')"  # leanprover--lean4---v4.14.0
TC_PATH="$ELAN_DIR/toolchains/$TC_NAME"

# --print-path mode: just emit the PATH export (for eval), do no work.
if [ "$PRINT_PATH" -eq 1 ]; then
  # $PATH is intentionally literal — it must expand when this line is later
  # eval'd / sourced, not now. Only %s (= $ELAN_DIR) expands here.
  # shellcheck disable=SC2016
  printf 'export PATH="%s/bin:$PATH"\n' "$ELAN_DIR"
  exit 0
fi

export PATH="$ELAN_DIR/bin:$PATH"

# Already bootstrapped — fast idempotent exit.
if [ -x "$TC_PATH/bin/lean" ]; then
  log "Lean toolchain $PIN already present at $TC_PATH"
  log "Run: eval \"\$($0 --print-path)\"  then  (cd $SCRIPT_DIR && lean Tangle.lean)"
  exit 0
fi

# 1. elan (toolchain manager). raw.githubusercontent.com is reachable.
if [ ! -x "$ELAN_DIR/bin/elan" ]; then
  log "installing elan…"
  curl -sSf https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh \
    | sh -s -- -y --default-toolchain none >/dev/null
fi

# 2. Try the normal toolchain install; fall back to the GitHub release asset
#    if the elan dist server is unreachable (the allowlist case).
if "$ELAN_DIR/bin/elan" toolchain install "$PIN" >/dev/null 2>&1 \
   && [ -x "$TC_PATH/bin/lean" ]; then
  log "installed $PIN via elan."
else
  log "elan dist server unreachable — using GitHub release asset."
  arch="$(uname -m)"
  case "$arch" in
    x86_64)  asset="lean-${VNUM}-linux.tar.zst" ;;
    aarch64) asset="lean-${VNUM}-linux_aarch64.tar.zst" ;;
    *) echo "bootstrap-lean: unsupported arch '$arch'" >&2; exit 1 ;;
  esac
  url="https://github.com/leanprover/lean4/releases/download/${VER}/${asset}"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  log "downloading $url"
  curl -sSfL -o "$tmp/lean.tar.zst" "$url"

  # zstd is needed to unpack .tar.zst.
  if ! command -v unzstd >/dev/null 2>&1 && ! command -v zstd >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get install -y zstd >/dev/null 2>&1 \
        || apt-get install -y zstd >/dev/null 2>&1 || true
    fi
  fi

  mkdir -p "$ELAN_DIR/toolchains"
  tar --use-compress-program=unzstd -xf "$tmp/lean.tar.zst" -C "$tmp"
  extracted="$(find "$tmp" -maxdepth 1 -type d -name 'lean-*' | head -1)"
  if [ -z "$extracted" ]; then
    echo "bootstrap-lean: extraction produced no lean-* directory" >&2
    exit 1
  fi
  rm -rf "$TC_PATH"
  mv "$extracted" "$TC_PATH"
  log "installed $PIN from GitHub release."
fi

# 3. Sanity check.
if [ -x "$TC_PATH/bin/lean" ]; then
  log "ready — $("$TC_PATH/bin/lean" --version 2>/dev/null || echo '(version unavailable)')"
  log "next: eval \"\$($0 --print-path)\"  then  (cd $SCRIPT_DIR && lean Tangle.lean)"
else
  echo "bootstrap-lean: toolchain bootstrap FAILED" >&2
  exit 1
fi
