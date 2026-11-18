#!/usr/bin/env bash
# effect-check E5: a bare script name in a rule must exist in a script folder of the brain or the core.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/.claude/rules" "$T/scripts" "$T/.claude/skills/tool-x"
printf '%s\n' '# rules' 'Run `effect-check.sh` and `gone-carrier.py`; local `brain-own.sh`; skill `skill-own.py`.' > "$T/CLAUDE.md"
: > "$T/scripts/brain-own.sh"
: > "$T/.claude/skills/tool-x/skill-own.py"
line="$(bash "$HERE/effect-check.sh" "$T" 2>/dev/null | grep ' E5 ')"
fails=0
case "$line" in *gone-carrier.py*) echo "  OK  a bare name that exists nowhere is reported" ;; *) echo "  FAIL bare dangling name not reported: $line"; fails=1 ;; esac
case "$line" in *effect-check.sh*) echo "  FAIL a core script was reported: $line"; fails=1 ;; *) echo "  OK  a bare core script name resolves" ;; esac
case "$line" in *brain-own.sh*) echo "  FAIL a brain script was reported: $line"; fails=1 ;; *) echo "  OK  a bare brain script name resolves" ;; esac
case "$line" in *skill-own.py*) echo "  FAIL a skill's own script was reported: $line"; fails=1 ;; *) echo "  OK  a skill's own script resolves" ;; esac
[ "$fails" = 0 ] && echo "effect-check E5 fixtures: ALL passed" || echo "effect-check E5 fixtures: FAILURES"
exit "$fails"
