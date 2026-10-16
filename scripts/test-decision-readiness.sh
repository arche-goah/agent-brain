#!/usr/bin/env bash
# Fixture for scripts/decision-readiness.py — both directions, offline, in a temp brain.
# Usage: bash scripts/test-decision-readiness.sh   (exit 0 = all pass)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
PY=python3; "$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1: $2"; fail=1; }
has()   { case "$3" in *"$2"*) ok "$1";; *) bad "$1" "'$3'";; esac; }
hasnt() { case "$3" in *"$2"*) bad "$1" "'$3'";; *) ok "$1";; esac; }

B="$T/brain"
run() { "$PY" "$HERE/decision-readiness.py" --root "$(native "$B")" 2>&1; }

# 0 — not a brain: silent
mkdir -p "$B"; out="$(run)"; [ -z "$out" ] && ok "not a brain: silent" || bad "not a brain: silent" "'$out'"

# 1 — a brain on an old core (measured 2026-10-16: core without ASK OR ACT), old template settings, no list
mkdir -p "$B/core/rules" "$B/.claude/rules"
printf '# old rules\n' > "$B/core/rules/working-rules.md"; printf '# x\n' > "$B/core/rules/intelligence.md"
printf '@core/rules/working-rules.md\n@core/rules/intelligence.md\n' > "$B/CLAUDE.md"
printf '{"permissions":{"allow":["Bash(git add*)"],"ask":["Bash(git commit*)","Bash(git push*)","Edit(.claude/settings.json)"]}}\n' > "$B/.claude/settings.json"
out="$(run)"
has "old core named" "predates ASK OR ACT" "$out"
has "missing list named" "no .claude/rules/operator-only.json" "$out"
has "everyday dialog named" "everyday git/gh steps raise a permission dialog" "$out"
hasnt "a settings edit under ask is no finding" "Edit(.claude/settings.json)" "$out"

# 2 — the human's answer of the same day: Bash(*) and an empty ask
printf '{"permissions":{"allow":["Bash(*)"],"ask":[]}}\n' > "$B/.claude/settings.json"
out="$(run)"
has "Bash(*) named" "Bash(*)\` is allowed" "$out"
hasnt "empty ask raises no dialog finding" "permission dialog" "$out"

# 3 — rules not imported at all
printf '# no imports\n```\n@core/rules/working-rules.md\n```\n' > "$B/CLAUDE.md"
out="$(run)"
has "rules not imported (an @ inside a code fence does not count)" "does not import core/rules/working-rules.md" "$out"

# 4 — the ready brain: current rule, filled list, template settings
printf '@core/rules/working-rules.md\n@core/rules/intelligence.md\n' > "$B/CLAUDE.md"
printf 'ASK OR ACT — the one ordered procedure\n' > "$B/core/rules/working-rules.md"
cp "$HERE/../templates/rules-instance/operator-only.json" "$B/.claude/rules/operator-only.json"
printf '{"permissions":{"allow":["Bash(git commit*)","Bash(git push*)","Bash(gh pr comment*)"],"ask":["Edit(.claude/settings.json)","Bash(git push * main*)"]}}\n' > "$B/.claude/settings.json"
out="$(run)"
[ -z "$out" ] && ok "ready brain (targeted allow, main push and settings edits ask, list filled): silent" \
  || bad "ready brain: silent" "'$out'"

# 5 — an empty list is a finding
printf '{"matters":[]}\n' > "$B/.claude/rules/operator-only.json"
out="$(run)"
has "empty list named" "broken or empty" "$out"

echo
[ "$fail" -eq 0 ] && echo "test-decision-readiness: all checks passed" || echo "test-decision-readiness: FAILURES"
exit "$fail"
