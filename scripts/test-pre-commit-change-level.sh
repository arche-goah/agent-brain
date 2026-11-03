#!/usr/bin/env bash
# covers: pre-commit
# Fixture for the change-level step of helpers/git-hooks/pre-commit: a staged changelog fragment whose level field
# change-level.cjs refuses blocks the commit; a valid one and a commit without fragments pass. Measured 2026-11-03 on
# the macOS instance: six fragments with "higher: none" on reader/writer reached the lint before anything said so.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/../helpers/git-hooks/pre-commit"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0; checks=0
ok()  { checks=$((checks + 1)); echo "  ok   $1"; }
bad() { checks=$((checks + 1)); fails=$((fails + 1)); echo "  FAIL $1 — $2"; }
mkdir -p "$T/nohooks"
g() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main -c core.autocrlf=false -c core.hooksPath="$T/nohooks" "$@"; }
gq() { g "$@" >/dev/null 2>&1; }
hook() { (cd "$1" && bash "$HOOK" 2>&1); }

R="$T/repo"; mkdir -p "$R/helpers" "$R/changelog.d"
cp "$HERE/../helpers/change-level.cjs" "$R/helpers/change-level.cjs"
gq init -q "$R"; echo a > "$R/a.txt"; gq -C "$R" add -A; gq -C "$R" commit -qm seed

echo "change level in the pre-commit"
echo b > "$R/a.txt"; gq -C "$R" add -A
o=$(hook "$R"); [ $? -eq 0 ] && ok "a commit without a fragment passes" || bad "no fragment" "$o"
printf '%s\n' '- **x** (test: T1) (level: reader; higher: none; debt: none). Body.' > "$R/changelog.d/bad.md"; gq -C "$R" add -A
o=$(hook "$R"); [[ $? -ne 0 && "$o" == *"change-level"* && "$o" == *"higher: none on level reader"* ]] \
  && ok "higher: none on reader is refused, the reason named" || bad "bad fragment" "$o"
printf '%s\n' '- **x** (test: T1) (level: reader; higher: writer — not needed here; debt: none). Body.' > "$R/changelog.d/bad.md"; gq -C "$R" add -A
o=$(hook "$R"); [ $? -eq 0 ] && ok "a valid fragment passes" || bad "valid fragment" "$o"

echo ""
[ "$fails" -eq 0 ] && echo "pre-commit change-level: all $checks checks pass" || echo "pre-commit change-level: $fails of $checks FAILED"
exit "$fails"
