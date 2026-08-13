#!/usr/bin/env bash
# workflow-parse-check.sh — loads every workflow the same way the workflow tool does.
#
# WHY (incident 2026-08-04): `workflows/brain-scan.js` had been syntactically broken since
# v1.0.0 — a prompt contained unescaped backticks in the middle of a template literal ("with
# state `configured`/`verified`"), which ended the literal and turned the rest into
# nonsense. The scan was thus unstartable on EVERY platform, and nobody noticed: CI checks
# `helpers/*.cjs` with `node --check`, but never the workflows. Worse: `node --check` alone
# would NOT have found it — parsed as CommonJS it reports exit 0, the error only shows up
# at the module parse.
#
# So this script checks the same way the caller does:
#   1. `export const meta` -> `const meta` (the tool extracts the meta itself)
#   2. wrap everything in an async IIFE (workflow scripts are allowed top-level `return`
#      and `await` — without the wrapper the parser falsely reports
#      "Illegal return statement")
#   3. `node --check` on the result
#
# Usage: scripts/workflow-parse-check.sh [workflow-dir]   (default: workflows/)
# Exit 0 = all loadable, 1 = at least one is not.
set -u

DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/workflows}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0
found=0
for f in "$DIR"/*.js; do
  [ -e "$f" ] || continue
  found=$((found + 1))
  name="$(basename "$f")"
  {
    printf '(async () => {\n'
    sed 's/^export const meta/const meta/' "$f"
    printf '\n})()\n'
  } > "$TMP/wrapped.js"

  if err=$(node --check "$TMP/wrapped.js" 2>&1); then
    printf 'OK    %s\n' "$name"
  else
    printf '!!    %s\n' "$name"
    printf '%s\n' "$err" | sed -n '1,6p' | sed 's/^/        /'
    fail=1
  fi
done

if [ "$found" -eq 0 ]; then
  echo "workflow-parse-check: no *.js in $DIR — nothing checked"
  exit 1
fi

[ "$fail" -eq 0 ] && echo "workflow-parse-check: $found workflow(s) loadable"
exit "$fail"
