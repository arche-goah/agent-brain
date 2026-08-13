#!/usr/bin/env bash
# lint-placeholders.sh — fail if template placeholders leak into skills, rules, or docs.
#
# Guards against the Windows-starter-pack heritage: {DEIN_*}, {User}/{Users},
# {deine-domain}, {DATUM} in auto-firing SKILL.md descriptions were shipped to the
# model on every semantic match (repo audit 2026-07-06, P1.2).
#
# Usage:  scripts/lint-placeholders.sh          # scan default paths
#         scripts/lint-placeholders.sh <paths>  # scan specific files (pre-commit)
# Exit 0 = clean, 1 = placeholders found.

set -eu

PATTERN='\{DEIN_[A-Z_]*\}|\{Users?\}|\{deine-domain\}|\{DATUM\}|\{DEINE_[A-Z_]*\}'

# Files that may legitimately mention the placeholder patterns (this linter, the audit report).
EXCLUDE_RE='scripts/lint-placeholders\.sh|docs/research/repo-audit-'

if [ "$#" -gt 0 ]; then
  TARGETS=("$@")
else
  TARGETS=(.claude/skills .claude/rules CLAUDE.md README.md)
fi

hits=$(grep -rInE "$PATTERN" "${TARGETS[@]}" 2>/dev/null | grep -vE "$EXCLUDE_RE" || true)

if [ -n "$hits" ]; then
  echo "FAIL: template placeholders found:"
  echo "$hits"
  echo ""
  echo "Replace {DEIN_NAME}/{User} with the real value or neutral wording."
  exit 1
fi

echo "OK: no template placeholders in ${TARGETS[*]}"
