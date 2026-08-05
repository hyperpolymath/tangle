#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# check-rsr-instantiation.sh — enforce that this repo is INSTANTIATED, not a
# copy of the RSR template wearing tangle's name.
#
# ── Why this exists ────────────────────────────────────────────────────────
# `.machine_readable/bot_directives/methodology.a2ml` already declares:
#
#     reject-if-contains = ["{{PLACEHOLDER}}", "TANGLE", "rsr-template-repo"]
#
# ...and NOTHING enforced it, so the repository violated its own stated rule
# indefinitely: four contractiles still named `rsr-template-repo` as their
# SUBJECT (`Intentfile` asserted "This repository is the canonical template for
# Rhodium Standard Repository compliance"), and the citation guide credited
# "Polymath, Hyper" for "RSR-template-repo". Fixed under #56; this makes the
# rule real so it cannot come back.
#
# ── Two checks, because two different things went wrong ────────────────────
# 1. TEMPLATE RESIDUE — unfilled `{{...}}` placeholders and files whose subject
#    is still the template.
# 2. PHANTOM COMMANDS — the QUICKSTARTs documented `just build`, `just test`,
#    `just lint`, `just panic-scan`, `just setup-dev`, `just build-release`,
#    `just install`, `just run`, `just stapeln-export`. None were recipes.
#    Documentation that fails when followed is worse than none, so every
#    `just <recipe>` named in the docs is checked against `just --list`.
#
# ── Why an ALLOWLIST rather than a bare grep ───────────────────────────────
# A naive search-and-replace would have corrupted working code. In particular
# `src/rust/src/eval.rs` contains `"...add{{}} block"`, which is a Rust
# `format!` ESCAPE (`{{}}` renders as a literal `{}`) describing the `add{}`
# language construct — not a placeholder. Files that legitimately *mention*
# the forbidden tokens (this script, the rule that forbids them, and the
# errata recording the debt) are listed explicitly below.
#
# USAGE:  scripts/check-rsr-instantiation.sh
# EXIT:   0 = instantiated; 1 = template residue or phantom commands found

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}" || exit 1

fail=0

# Paths permitted to contain the forbidden tokens, with the reason.
#   AFFIRMATION.adoc                 — dated errata recording the debt
#   docs/identity-fabric/            — the task description
#   methodology.a2ml                 — the reject-if-contains rule itself
#   contractiles/Adjustfile.a2ml     — the corrective-action text
#   contractiles/dust/Dustfile.a2ml  — note about generic templates
#   scripts/check-rsr-instantiation.sh — this file
#   src/rust/src/eval.rs             — Rust format! escape, NOT a placeholder
#   .github/workflows/dogfood-gate.yml, .githooks/, self-validating/ — links to
#     the upstream template as an external resource, which is legitimate
ALLOW_RE='^(AFFIRMATION\.adoc|docs/identity-fabric/|docs/CHANGELOG|\.machine_readable/bot_directives/methodology\.a2ml|\.machine_readable/contractiles/Adjustfile\.a2ml|\.machine_readable/contractiles/dust/Dustfile\.a2ml|\.machine_readable/self-validating/|scripts/check-rsr-instantiation\.sh|src/rust/src/eval\.rs|\.github/workflows/dogfood-gate\.yml|\.githooks/)'

echo "== template residue =="
# Unfilled placeholders: {{UPPER_SNAKE}}. Deliberately does NOT match `{{}}`.
residue="$(grep -rn --binary-files=without-match \
             --exclude-dir=.git --exclude-dir=_build --exclude-dir=target \
             --exclude-dir=.claude --exclude-dir=node_modules \
             -E '\{\{[A-Z][A-Z_]*\}\}' . 2>/dev/null \
           | sed 's|^\./||' | grep -vE "${ALLOW_RE}" || true)"
if [[ -n "${residue}" ]]; then
  echo "::error::Unfilled template placeholders:"; printf '%s\n' "${residue}"; fail=1
else
  echo "  no unfilled {{PLACEHOLDER}} tokens"
fi

# Files whose SUBJECT is still the template.
subject="$(grep -rn --binary-files=without-match \
             --exclude-dir=.git --exclude-dir=_build --exclude-dir=target \
             --exclude-dir=.claude --exclude-dir=node_modules \
             -F 'rsr-template-repo' . 2>/dev/null \
           | sed 's|^\./||' | grep -vE "${ALLOW_RE}" \
           | grep -viE 'https?://' || true)"
if [[ -n "${subject}" ]]; then
  echo "::error::Files still describing rsr-template-repo as their subject:"
  printf '%s\n' "${subject}"
  echo "  (A bare URL to the upstream template is fine; naming it as THIS repo is not.)"
  fail=1
else
  echo "  no file claims to be rsr-template-repo"
fi

echo "== documented commands exist =="
if ! command -v just >/dev/null 2>&1; then
  echo "::warning::\`just\` not installed — skipping the phantom-command check."
  echo "  (Not a pass: the check did not run.)"
else
  recipes="$(just --list 2>/dev/null | tail -n +2 | awk '{print $1}')"
  missing=0
  while IFS= read -r doc; do
    [[ -f "$doc" ]] || continue
    while IFS= read -r r; do
      [[ -z "$r" || "$r" == --* ]] && continue
      if ! printf '%s\n' "${recipes}" | grep -qx -- "$r"; then
        echo "::error::${doc} documents \`just ${r}\`, which is not a recipe"
        missing=1
      fi
    done < <(grep -oE '^just [a-z][a-z-]*' "$doc" | awk '{print $2}' | sort -u)
  done < <(printf '%s\n' QUICKSTART-DEV.adoc QUICKSTART-MAINTAINER.adoc QUICKSTART-USER.adoc README.adoc)
  if [[ "$missing" -eq 0 ]]; then echo "  every documented \`just\` recipe exists"; else fail=1; fi
fi

echo
if [[ "$fail" -ne 0 ]]; then
  echo "::error::repo is not fully instantiated — see above."
  exit 1
fi
echo "RSR instantiation OK: no template residue, and the docs only name commands that exist."
