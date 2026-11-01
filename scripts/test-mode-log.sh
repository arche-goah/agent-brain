#!/usr/bin/env bash
# Fixture for helpers/mode-log.cjs: the mode a turn ends in is written as a fact, through the real
# stop-dispatcher as a `mode: record` check. Usage: bash scripts/test-mode-log.sh   (exit 0 = pass)
set -u
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
_D="$(cd "$(dirname "$0")" && pwd)"
H="$_D/../helpers/mode-log.cjs"
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
js() { node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$1"; }
user() { printf '{"type":"user","message":{"role":"user","content":%s}}\n' "$(js "$1")"; }
asst() { printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":%s}]}}\n' "$(js "$1")"; }
run() { printf '{"transcript_path":%s,"cwd":%s}' "$(js "$(native "$1")")" "$(js "$(native "$T")")" | CLAUDE_PROJECT_DIR="$(native "$T")" node "$(native "$H")"; }

f="$T/a.jsonl"; { user "work through the list autonomously"; asst "on it"; } > "$f"
out="$(run "$f")"
case "$out" in *'"mode":"autonomous"'*) ok "an autonomous turn is recorded as autonomous";; *) bad "autonomous: $out";; esac
case "$out" in *'"prompt":"work through the list autonomously"'*) ok "the record names the operator word it was read from";; *) bad "prompt: $out";; esac
f="$T/b.jsonl"; { user "fix the parser"; asst "done"; } > "$f"
out="$(run "$f")"
case "$out" in *'"mode":"interactive"'*) ok "an interactive turn is recorded as interactive";; *) bad "interactive: $out";; esac
out="$(printf '{}' | node "$(native "$H")")"
[ -z "$out" ] && ok "no transcript: no record, no error" || bad "no transcript: $out"
out="$(run "$T/none.jsonl")"
case "$out" in *'"mode":"interactive"'*) ok "an unreadable transcript records the default";; *) bad "unreadable: $out";; esac

# Through the real dispatcher: a recorder writes .claude-state/mode-log.jsonl and never blocks.
mkdir -p "$T/.claude/rules"
printf '%s\n' '{"checks":[{"label":"MODE LOG","marker":"MODE-LOG","cmd":"'"$(native "$H")"'","mode":"record"}]}' > "$T/.claude/rules/stop-checks.json"
f="$T/c.jsonl"; { user "work through the list autonomously"; asst "x"; } > "$f"
dout="$(printf '{"transcript_path":%s,"cwd":%s}' "$(js "$(native "$f")")" "$(js "$(native "$T")")" | CLAUDE_PROJECT_DIR="$(native "$T")" node "$(native "$_D/../helpers/stop-dispatcher.cjs")" 2>&1)"
case "$dout" in *'"block"'*) bad "the recorder blocked: $dout";; *) ok "the recorder never blocks";; esac
if grep -q '"mode":"autonomous"' "$T/.claude-state/mode-log.jsonl" 2>/dev/null && grep -q '"check":"MODE-LOG"' "$T/.claude-state/mode-log.jsonl"; then
  ok "the dispatcher appends the record with time, session and check"
else bad "no mode-log.jsonl line: $(cat "$T/.claude-state/mode-log.jsonl" 2>&1)"; fi

[ $fail -eq 0 ] && echo "mode-log: all passed" || echo "mode-log: FAILED"
exit $fail
