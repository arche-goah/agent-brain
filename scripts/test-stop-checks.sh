#!/usr/bin/env bash
# covers: class-gate stop-verifier diagnose-gate stoppen-gate reconnect-gate umlaut-gate
#
# Effect proof for the Stop checks that had none. They run bundled behind the
# dispatcher, and a bundled check that stopped firing is invisible: the turn simply
# ends, which is what a satisfied check looks like too.
#
# Both directions per check. The "must stay silent" half carries the weight here —
# these gates interrupt a finished answer, so a false positive costs a whole re-issue.
#
# Usage: bash scripts/test-stop-checks.sh   (exit 0 = all fixtures pass)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }

# Two layouts, one fixture: inside a brain the helpers live under core/helpers, inside
# the core repo itself under helpers. A fixture that only knows one of them silently
# tests nothing in the other — so resolution is explicit, and a missing subject is
# SKIPPED loudly rather than passing quietly.
resolve() {
  for cand in "core/$1" "$1"; do
    [ -f "$cand" ] && { printf '%s' "$cand"; return 0; }
  done
  return 1
}
skip() { echo "  --  $1 (not in this layout)"; }


# $1 name, $2 hook path, $3 transcript, $4 block|allow, $5 expected marker (block only)
run_hook() {
  local out hook
  hook=$(resolve "$2") || { skip "$1"; return 0; }
  out=$(printf '{"transcript_path":"%s","stop_hook_active":false,"cwd":"%s"}' "$3" "$ROOT" \
        | CLAUDE_PROJECT_DIR="$ROOT" node "$hook" 2>&1)
  if [ "$4" = "block" ]; then
    case "$out" in *"${5:-}"*) ok "$1 blocks";; *) bad "$1 did not block: ${out:0:120}";; esac
  else
    [ -z "$out" ] && ok "$1 allows" || bad "$1 blocked wrongly: ${out:0:120}"
  fi
}

# build a transcript: $1 file, $2 assistant text (json string), $3.. tool_use entries
mk() {
  local f="$1"; shift
  printf '%s\n' '{"message":{"role":"user","content":"frage"}}' > "$f"
  printf '%s\n' "$@" >> "$f"
}

echo "Stop checks:"

# --- class-gate: fires after a turn that changed code, not on doc-only work ---
mk "$T/code.jsonl" '{"message":{"role":"assistant","content":[{"type":"text","text":"fertig"},{"type":"tool_use","name":"Edit","id":"e1","input":{"file_path":"scripts/hooks/probe.cjs","new_string":"x"}}]}}'
run_hook "class-gate/code turn" core/helpers/class-gate.cjs "$T/code.jsonl" block "CLASS-GATE"
mk "$T/doc.jsonl" '{"message":{"role":"assistant","content":[{"type":"text","text":"notiert"},{"type":"tool_use","name":"Edit","id":"e1","input":{"file_path":"docs/maintenance/session-log.md","new_string":"x"}}]}}'
run_hook "class-gate/doc turn" core/helpers/class-gate.cjs "$T/doc.jsonl" allow

# --- stop-verifier: only markers THIS turn wrote count -----------------------
# The marker word is assembled so this fixture file does not contain it literally —
# same reason the hook itself does it: a test that trips its own subject is useless.
M="TO""DO"
mk "$T/marker.jsonl" '{"message":{"role":"assistant","content":[{"type":"text","text":"gebaut"},{"type":"tool_use","name":"Write","id":"w1","input":{"file_path":"scripts/x.py","content":"# '"$M"': spaeter"}}]}}'
run_hook "stop-verifier/unfinished marker" core/helpers/stop-verifier.cjs "$T/marker.jsonl" block "INCOMPLETE"
mk "$T/clean.jsonl" '{"message":{"role":"assistant","content":[{"type":"text","text":"gebaut"},{"type":"tool_use","name":"Write","id":"w1","input":{"file_path":"scripts/x.py","content":"print(1)"}}]}}'
run_hook "stop-verifier/clean code" core/helpers/stop-verifier.cjs "$T/clean.jsonl" allow

# --- diagnose-gate: a tool reported a failure and no log was read ------------
mk "$T/fail.jsonl" \
  '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","id":"b1","input":{"command":"ping x"}}]}}' \
  '{"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"b1","content":"ERROR: connection timeout"}]}}' \
  '{"message":{"role":"assistant","content":[{"type":"text","text":"Das Geraet antwortet nicht, weil der Port down ist."}]}}'
run_hook "diagnose-gate/tool failure" scripts/hooks/diagnose-gate.cjs "$T/fail.jsonl" block "DIAGNOSE-GATE"
mk "$T/nofail.jsonl" '{"message":{"role":"assistant","content":[{"type":"text","text":"Alles gruen, Messwert im Log."}]}}'
run_hook "diagnose-gate/no failure" scripts/hooks/diagnose-gate.cjs "$T/nofail.jsonl" allow

# --- stoppen-gate: a closing permission question is a disguised stop ---------
mk "$T/ask.jsonl" '{"message":{"role":"assistant","content":[{"type":"text","text":"Aufbau steht. Soll ich jetzt weitermachen?"}]}}'
run_hook "stoppen-gate/closing question" scripts/hooks/stoppen-gate.cjs "$T/ask.jsonl" block "STOPPEN-GATE"
mk "$T/report.jsonl" '{"message":{"role":"assistant","content":[{"type":"text","text":"Aufbau steht, gemessen und berichtet."}]}}'
run_hook "stoppen-gate/plain report" scripts/hooks/stoppen-gate.cjs "$T/report.jsonl" allow

# --- reconnect-gate: asking for a reconnect without arming the watcher -------
mk "$T/reconnect.jsonl" '{"message":{"role":"assistant","content":[{"type":"text","text":"Das Tool greift erst nach einem /mcp-Reconnect — sag Bescheid, wenn du neu verbunden hast."}]}}'
run_hook "reconnect-gate/unarmed request" scripts/hooks/reconnect-gate.cjs "$T/reconnect.jsonl" block "RECONNECT-GATE"
mk "$T/narration.jsonl" '{"message":{"role":"assistant","content":[{"type":"text","text":"Nach dem Reconnect war der Boot-Stamp frisch, damit ist der neue Prozess bewiesen."}]}}'
run_hook "reconnect-gate/narration" scripts/hooks/reconnect-gate.cjs "$T/narration.jsonl" allow
mk "$T/noreconnect.jsonl" '{"message":{"role":"assistant","content":[{"type":"text","text":"Tool gebaut, Fixtures gruen."}]}}'
run_hook "reconnect-gate/no request" scripts/hooks/reconnect-gate.cjs "$T/noreconnect.jsonl" allow

# --- umlaut-gate: unwired since 2026-08-20, still has to detect --------------
# It runs as a report now, so its detection must keep working even though nothing
# blocks on it any more — an unwired mechanism decays unnoticed by definition.
mk "$T/ascii.jsonl" '{"message":{"role":"assistant","content":[{"type":"text","text":"Das ist noetig und laeuft waehrend der Messung."}]}}'
run_hook "umlaut-gate/transliterated" scripts/hooks/umlaut-gate.cjs "$T/ascii.jsonl" block "UMLAUT-GATE"
mk "$T/proper.jsonl" '{"message":{"role":"assistant","content":[{"type":"text","text":"Das ist nötig und läuft während der Messung."}]}}'
run_hook "umlaut-gate/real umlauts" scripts/hooks/umlaut-gate.cjs "$T/proper.jsonl" allow

echo
[ "$fail" -eq 0 ] && echo "stop-check fixtures: ALL passed" || echo "FAILURE"
exit "$fail"
