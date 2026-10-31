#!/usr/bin/env bash
# covers: loop-watchdog
# Fixture: an alarm the watchdog raises outside a session reaches the operator (operator
# decision 2026-10-15: an issue in the instance's private repo, which GitHub mails) and the
# next session start (measured 2026-10-28: after `check` moved the state to .stale, `status
# --brief` said nothing). gh is a stub that records its arguments.
# Usage: bash scripts/test-loop-watchdog-alarm.sh   (exit 0 = pass)
set -u
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
W="$(cd "$(dirname "$0")" && pwd)/loop-watchdog.sh"
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
P="$T/brain"; mkdir -p "$P/.claude-state" "$P/.claude/rules"
printf '%s\n' '#!/usr/bin/env bash' "printf '%s\n' \"\$*\" >> \"$T/gh-calls\"" > "$T/gh"; chmod +x "$T/gh"
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
wd() { CLAUDE_PROJECT_DIR="$(native "$P")" LOOP_WATCHDOG_GH="$T/gh" LOOP_WATCHDOG_NO_NOTIFY=1 bash "$W" "$@" 2>&1; }
stale() { printf '%s\n' "$1" 30 "$(( $(date +%s) - 5400 ))" "$(( $(date +%s) - 7200 ))" 0 0 > "$P/.claude-state/loop-watchdog.state"; }

stale run-a; wd check >/dev/null
[ -f "$P/.claude-state/loop-watchdog.state.stale" ] && ok "check moves the silent run to .stale" || bad "no .stale after check"
[ -s "$T/gh-calls" ] && bad "an issue was opened without instance data: $(cat "$T/gh-calls")" || ok "no issue_repo: no issue opened"
out=$(wd status --brief); rc=$?
case "$out" in *"raised an alarm while no session watched: 'run-a'"*"disarm"*) ok "the next start reports the alarm that fired";; *) bad "start line: '$out'";; esac
[ "$rc" -eq 1 ] && ok "status --brief exits 1 on a fired alarm" || bad "rc=$rc"
out=$(wd disarm)
case "$out" in *"cleared the alarm of 'run-a'"*) ok "disarm clears the fired alarm";; *) bad "disarm: '$out'";; esac
[ -z "$(wd status --brief)" ] && ok "after disarm the start is silent" || bad "still reported after disarm"

printf '%s\n' '{"issue_repo": "owner/private-brain"}' > "$P/.claude/rules/loop-watchdog.json"
stale run-b; wd check >/dev/null
case "$(cat "$T/gh-calls" 2>/dev/null)" in *"issue create -R owner/private-brain --title loop-watchdog: Loop 'run-b'"*) ok "with issue_repo the alarm opens an issue there";; *) bad "gh calls: '$(cat "$T/gh-calls" 2>/dev/null)'";; esac
grep -q "issue opened in owner/private-brain" "$P/.claude-state/loop-watchdog.log" && ok "the opened issue is logged" || bad "no log line for the issue"
wd disarm >/dev/null

printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "$T/gh"
stale run-c; wd check >/dev/null
grep -q "issue NOT opened in owner/private-brain: gh failed" "$P/.claude-state/loop-watchdog.log" && ok "a failed issue is logged, never silent" || bad "failed issue not logged"

echo
[ "$fail" -eq 0 ] && echo "loop-watchdog-alarm: all cases pass" || echo "loop-watchdog-alarm: FAILURES"
exit "$fail"
