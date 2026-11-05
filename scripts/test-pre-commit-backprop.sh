#!/usr/bin/env bash
# covers: pre-commit
# Fixture for step 4c of helpers/git-hooks/pre-commit: a staged rule file with a new dated rule prints the
# older places that name its terms (backprop-report.py) and never blocks; a commit without a rule file
# prints nothing. Sandbox repos only, the real backprop-report.py, no network. Exit 0 = all pass.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/../helpers/git-hooks/pre-commit"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0; checks=0
ok()  { checks=$((checks + 1)); echo "  ok   $1"; }
bad() { checks=$((checks + 1)); fails=$((fails + 1)); echo "  FAIL $1 — $2"; }
mkdir -p "$T/nohooks"
g() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main -c core.autocrlf=false \
        -c core.hooksPath="$T/nohooks" "$@"; }
gq() { g "$@" >/dev/null 2>&1; }
hook() { (cd "$1" && bash "$HOOK" 2>&1); }

R="$T/brain"
mkdir -p "$R/.claude/rules"
printf '%s\n' '# Brain' '' 'Old rule: `fixture-term` may run every hour.' > "$R/CLAUDE.md"
printf '%s\n' '# Feedback' '' '- seed line' > "$R/.claude/rules/feedback.md"
gq init -q "$R"; gq -C "$R" add -A; gq -C "$R" commit -qm seed

echo "backprop report in the pre-commit"
echo "unrelated" > "$R/notes.txt"; gq -C "$R" add notes.txt
o=$(hook "$R"); rc=$?
[[ $rc -eq 0 && "$o" != *"does not block"* ]] && ok "no rule file staged: no report" || bad "no rule file staged" "rc=$rc out: $o"

printf '%s\n' '- 2026-11-02 `fixture-term` runs only on the operator'"'"'s word' >> "$R/.claude/rules/feedback.md"
gq -C "$R" add .claude/rules/feedback.md
o=$(hook "$R"); rc=$?
[[ $rc -eq 0 ]] && ok "a new dated rule never blocks the commit" || bad "a new dated rule blocked" "rc=$rc out: $o"
[[ "$o" == *"does not block"* && "$o" == *"CLAUDE.md:3"* ]] && ok "  ... and the older place naming its term is reported" \
  || bad "older place not reported" "$o"

echo ""
[ "$fails" -eq 0 ] && echo "pre-commit backprop: all $checks checks pass" || echo "pre-commit backprop: $fails of $checks FAILED"
exit "$fails"
