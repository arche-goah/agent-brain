#!/usr/bin/env bash
# covers: diagnose-gate
# Fixture test for helpers/diagnose-gate.cjs — both directions.
# Fires: a tool result in the turn reports a state failure AND no log was read in the turn.
# Silent: no failure, a log read in the same turn, a failure shown by a file/text tool (source
# code is no state report), a guard's refusal, a re-issue pass, the cooldown after its own block.
# Usage: bash scripts/test-diagnose-gate.sh   (exit 0 = all fixtures pass)
set -u

native() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }

G=""
for cand in "$ROOT/helpers/diagnose-gate.cjs" "$ROOT/core/helpers/diagnose-gate.cjs"; do
  [ -f "$cand" ] && { G="$cand"; break; }
done
[ -n "$G" ] || { echo "  FAIL diagnose-gate.cjs not found"; exit 1; }

# The fixture brings its own instance data: a site log tool and a tool-specific failure word.
EN="$T/plain"; SITE="$T/site"
mkdir -p "$EN/.claude/rules" "$SITE/.claude/rules"
printf '%s\n' '{"failure_patterns":["\\bprobe ✗"],"log_read_patterns":["\\bmcp__site__device_events\\b"]}' \
  > "$SITE/.claude/rules/diagnose-patterns.json"

call()   { printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"%s","id":"%s","input":{"command":"%s"}}]}}\n' "$1" "$2" "$3"; }
result() { printf '{"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"%s","content":"%s"}]}}\n' "$1" "$2"; }
say()    { printf '{"message":{"role":"assistant","content":[{"type":"text","text":"%s"}]}}\n' "$1"; }
prompt() { printf '{"message":{"role":"user","content":"%s"}}\n' "$1"; }

# $1 name, $2 transcript file, $3 block|allow, $4 cwd, $5 extra payload json (optional)
check() {
  local out extra="${5:-}"
  out="$(printf '{"transcript_path":"%s","stop_hook_active":false,"cwd":"%s"%s}' "$(native "$2")" "$(native "$4")" "$extra" \
        | node "$G" 2>&1)"
  if [ "$3" = "block" ]; then
    case "$out" in *'"decision":"block"'*Reported*) ok "$1 blocks";; *) bad "$1 did not block: '${out:0:160}'";; esac
  else
    [ -z "$out" ] && ok "$1 allows" || bad "$1 blocked wrongly: '${out:0:160}'"
  fi
}

{ prompt "check the device"; call Bash b1 "ping -c 3 192.0.2.10"; result b1 "ERROR: connection timed out"
  say "The device does not answer because the port is down."; } > "$T/fail.jsonl"
check "failure, no log read" "$T/fail.jsonl" block "$EN"

{ prompt "check the device"; call Bash b1 "ping -c 3 192.0.2.10"; result b1 "3 packets transmitted, 0.0% packet loss"
  say "All green."; } > "$T/healthy.jsonl"
check "negative control: 0.0% packet loss is healthy" "$T/healthy.jsonl" allow "$EN"

{ prompt "check the device"; call Bash b1 "ping -c 3 192.0.2.10"; result b1 "40% packet loss"
  call Bash b2 "journalctl -u netd --since -10min"; result b2 "link flapped at 10:01"
  say "Loss came with the flap in the journal."; } > "$T/logread.jsonl"
check "failure with a log read in the turn" "$T/logread.jsonl" allow "$EN"

{ prompt "where is the timeout set?"; call Bash b1 "grep -n timeout server.py"; result b1 "12: request timed out after timeout=8"
  say "Line 12."; } > "$T/code.jsonl"
check "a grep showing source is no state report" "$T/code.jsonl" allow "$EN"

{ prompt "read it"; call Read r1 ""; result r1 "unreachable or empty coverage"; say "Read."; } > "$T/read.jsonl"
check "a Read tool result never counts" "$T/read.jsonl" allow "$EN"

{ prompt "write it"; call Bash b1 "site-tool write"; result b1 "REFUSED: preview only, timed out waiting for confirm"
  say "Preview shown."; } > "$T/guard.jsonl"
check "a guard's refusal is no failure" "$T/guard.jsonl" allow "$EN"

# instance data extends both lists
{ prompt "probe"; call Bash b1 "site-probe all"; result b1 "dev1 probe ✗"; say "dev1 is broken."; } > "$T/sitefail.jsonl"
check "instance failure word fires with its data" "$T/sitefail.jsonl" block "$SITE"
check "the same word without the data stays silent" "$T/sitefail.jsonl" allow "$EN"
{ prompt "probe"; call Bash b1 "site-probe all"; result b1 "dev1 probe ✗"; call mcp__site__device_events m1 ""
  result m1 "dev1 rebooted"; say "dev1 rebooted."; } > "$T/sitelog.jsonl"
check "an instance log tool counts as the log read" "$T/sitelog.jsonl" allow "$SITE"

# cooldown: its own echo two operator turns back keeps it quiet
{ prompt "check"; call Bash b1 "ping x"; result b1 "unreachable"; say "Down."
  prompt 'Stop hook feedback:\nDIAGNOSE — A tool reported unreachable'; prompt "and now?"
  call Bash b2 "ping x"; result b2 "unreachable"; say "Still down."; } > "$T/cool.jsonl"
check "cooldown after its own label echo" "$T/cool.jsonl" allow "$EN" ',"stop_check":{"label":"DIAGNOSE","marker":"DIAGNOSE-GATE"}'
check "negative control: without the label the echo is foreign" "$T/cool.jsonl" block "$EN"

out="$(printf '{"transcript_path":"%s","stop_hook_active":true,"cwd":"%s"}' "$(native "$T/fail.jsonl")" "$(native "$EN")" | node "$G" 2>&1)"
[ -z "$out" ] && ok "re-issue pass silent" || bad "re-issue pass fired: '$out'"

echo
[ "$fail" -eq 0 ] && echo "diagnose-gate fixtures: ALL passed" || echo "diagnose-gate fixtures: FAILURE"
exit "$fail"
