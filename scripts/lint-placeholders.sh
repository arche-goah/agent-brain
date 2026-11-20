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
# The example value of a copied templates/rules-instance file, left as a JSON key or value (2026-11-20, Windows
# instance: .claude/rules/os-proof.json still held "example-owner/example-repo" from the copy, so no repo counted
# its green CI as the OS proof and shared-memory-post.py / merge-request-gate never fired there).
PATTERN="$PATTERN"'|"example-[a-z0-9.-]+(/example-[a-z0-9.-]+)?"'

# Files that may legitimately mention the placeholder patterns (this linter, the audit report).
EXCLUDE_RE='scripts/lint-placeholders\.sh|docs/research/repo-audit-'

if [ "$#" -gt 0 ]; then
  TARGETS=("$@")
else
  TARGETS=(.claude/skills .claude/rules CLAUDE.md README.md)
fi

hits=$(grep -rInE "$PATTERN" "${TARGETS[@]}" 2>/dev/null | grep -vE "$EXCLUDE_RE" || true)
# A <placeholder> left as a whole JSON string of a copied template ("<owner>/<core-repo>", "<operator>-<machine-1>";
# macOS instance's review of #624: collab-watch.json carries 14 of them in live data). JSON only and a string with
# no space, so prose ("kill <pid>", Markdown usage lines) and "_..." comment lines stay out.
JSON_PH='(^|[^\\])"[^" ]*<[a-z][a-z0-9._-]*>[^" ]*"'
ph=$(grep -rInE --include='*.json' "$JSON_PH" "${TARGETS[@]}" 2>/dev/null | grep -avE '^[^:]+:[0-9]+:[[:space:]]*"_' \
  | grep -avE "$EXCLUDE_RE" || true)
hits=$(printf '%s\n%s' "$hits" "$ph" | sed '/^$/d')

if [ -n "$hits" ]; then
  echo "FAIL: template placeholders found:"
  echo "$hits"
  echo ""
  echo "Replace {DEIN_NAME}/{User} with the real value or neutral wording; an \"example-...\" entry of a copied"
  echo "template, or a \"<...>\" string in a copied JSON file, with the instance's own value, or delete the entry."
  exit 1
fi

echo "OK: no template placeholders in ${TARGETS[*]}"
