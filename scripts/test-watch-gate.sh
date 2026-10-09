#!/usr/bin/env bash
# Fixture test for helpers/watch-gate.cjs — both directions.
# The must-block case is the incident itself (2026-10-09): an answer pushed into the
# shared-memory repo, addressed to another instance, turn ended, no watcher — the
# follow-up request only surfaced when the operator asked. Must-allow cases carry the
# weight: a live watcher (plain or inside collab-watch), a closed entry (`status: info`),
# a note to oneself, someone else's entry, a push in an EARLIER turn, a re-issue. A dead
# pid in the lock (an expired Monitor) must count as not armed.
# Usage: bash scripts/test-watch-gate.sh (exit 0 = pass)
set -u
T="$(mktemp -d)"
SLEEPERS=()
trap 'for p in "${SLEEPERS[@]}"; do kill "$p" 2>/dev/null; done; rm -rf "$T"' EXIT
G="$(cd "$(dirname "$0")" && pwd)/../helpers/watch-gate.cjs"
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
[ -f "$G" ] || { echo "  FAIL gate missing: $G"; exit 1; }

# OS-3: node opens these paths; a Git-Bash /tmp path would not resolve on Windows.
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
js() { node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$1"; }

SM="$T/brain-shared-memory"
fresh() { # a new history, so exactly the next entry is in range
  rm -rf "$SM"; git init -q "$SM"; mkdir -p "$SM/core"
  git -C "$SM" config user.email t@t; git -C "$SM" config user.name t; git -C "$SM" config core.autocrlf false
}
fresh
entry() { # $1 file, $2 von, $3 audience, [$4 status]
  { echo '---'; echo "name: x"; echo 'metadata:'; echo "  von: $2"; echo "  audience: $3"
    [ -n "${4:-}" ] && echo "  status: $4"; echo '---'; echo body; } > "$SM/core/$1"
  git -C "$SM" add -A; git -C "$SM" commit -q -m "$1"
}

user() { printf '{"timestamp":"%s","message":{"role":"user","content":%s}}\n' "${2:-2020-01-01T00:00:00Z}" "$(js "$1")"; }
tool() { printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"%s","input":{"command":%s%s}}]}}\n' \
  "$1" "$(js "$2")" "${3:+,\"run_in_background\":true}"; }
asst() { printf '{"message":{"role":"assistant","content":[{"type":"text","text":%s}]}}\n' "$(js "$1")"; }
PUSH="cd ~/Projects/brain-shared-memory && git commit -q -m x && git push -q"

check() { # $1 name, $2 transcript, $3 block|allow, $4 project root, [$5 stop_hook_active]
  local out
  out="$(printf '{"transcript_path":"%s","stop_hook_active":%s}' "$(native "$2")" "${5:-false}" \
    | CLAUDE_PROJECT_DIR="$(native "$4")" SHARED_MEMORY_REPO="$(native "$SM")" SHARED_MEMORY_SELF="ws" \
      node "$G" 2>&1)"
  if [ "$3" = block ]; then
    case "$out" in *'"decision":"block"'*) ok "$1 blocks";; *) bad "$1 did not block: '$out'";; esac
  else
    [ -z "$out" ] && ok "$1 allows" || bad "$1 blocked wrongly: '$out'"
  fi
}
live_lock() { sleep 60 & SLEEPERS+=("$!"); mkdir -p "$(dirname "$1")"; echo "$!" > "$1"; }

R="$T/brain"; mkdir -p "$R"

# --- the incident: answer to another party pushed, no watcher
entry answer.md ws mac
{ user "bitte windows checks starten"; tool Bash "$PUSH"; asst "done"; } > "$T/t1.jsonl"
check "pushed answer to another party, no watcher" "$T/t1.jsonl" block "$R"

# notifications inside the turn are not a boundary
{ user "go"; tool Bash "$PUSH"; user "<task-notification>agent done</task-notification>"; asst "ok"; } > "$T/t2.jsonl"
check "push, then a task notification" "$T/t2.jsonl" block "$R"

# an expired Monitor leaves a dead pid
mkdir -p "$R/.claude-state"; echo 999999 > "$R/.claude-state/shared-memory-watch.pid"
check "lock with a dead pid (expired watch)" "$T/t1.jsonl" block "$R"

# --- must allow
live_lock "$R/.claude-state/shared-memory-watch.pid"
check "live shared-memory watcher" "$T/t1.jsonl" allow "$R"
rm -f "$R/.claude-state/shared-memory-watch.pid"
live_lock "$R/.claude-state/collab-watch/shared-memory-watch.pid"
check "live watcher inside collab-watch" "$T/t1.jsonl" allow "$R"
rm -rf "$R/.claude-state"

check "re-issue (stop_hook_active)" "$T/t1.jsonl" allow "$R" true
{ cat "$T/t1.jsonl"; user "Stop hook feedback: WATCH-GATE: ..."; asst "nothing awaited: pure log line"; } > "$T/t3.jsonl"
check "second stop in the same turn" "$T/t3.jsonl" allow "$R"
{ cat "$T/t1.jsonl"; user "next question" "2099-01-01T00:00:00Z"; asst "answer"; } > "$T/t4.jsonl"
check "push was in an earlier turn" "$T/t4.jsonl" allow "$R"
{ user "go"; tool Bash "cd ~/Projects/other && git push -q"; } > "$T/t5.jsonl"
check "push to another repo" "$T/t5.jsonl" allow "$R"

fresh; entry info.md ws mac info
check "entry closed with status: info" "$T/t1.jsonl" allow "$R"
fresh; entry self.md ws ws
check "note addressed to this instance only" "$T/t1.jsonl" allow "$R"
fresh; entry foreign.md mac ws
check "entry pulled in from another instance" "$T/t1.jsonl" allow "$R"

# --- PR side
{ user "build the PR"; tool Bash "gh pr create --title x --body y"; asst "PR #1"; } > "$T/p1.jsonl"
check "PR created, no watch" "$T/p1.jsonl" block "$R"
{ user "build the PR"; tool Bash "gh pr create --title x --body y"; tool Monitor "bash core/scripts/watch-pr.sh o/r 1 60"; } > "$T/p2.jsonl"
check "PR created, watch-pr armed in the turn" "$T/p2.jsonl" allow "$R"
live_lock "$R/.claude-state/collab-watch/repo-activity-o.pid"
check "PR created, collab-watch repo watch lives" "$T/p1.jsonl" allow "$R"

# --- handover (alpha 2026-10-09): a closing session writes the expectation down
H="$T/brain-h"; mkdir -p "$H/.claude-state"
hcli() { CLAUDE_PROJECT_DIR="$(native "$H")" node "$G" "$@"; }
fresh; entry close-answer.md ws mac
out_h="$(hcli handover "reply from mac on close-answer")"
case "$out_h" in "handover "*) ok "handover CLI records the expectation";; *) bad "handover CLI: '$out_h'";; esac
{ user "session abschliessen" "2000-01-01T00:00:00Z"; tool Bash "$PUSH"; asst "closed"; } > "$T/h1.jsonl"
check "closing turn: push covered by a handover written in the turn" "$T/h1.jsonl" allow "$H"
# Next session: the entry is older than the new prompt, no watcher lives.
{ user "next session" "2999-01-01T00:00:00Z"; asst "hi"; } > "$T/h2.jsonl"
check "next session inherits the expectation, no watcher" "$T/h2.jsonl" block "$H"
live_lock "$H/.claude-state/shared-memory-watch.pid"
check "next session with a live watcher" "$T/h2.jsonl" allow "$H"
[ -z "$(hcli list)" ] && ok "a live watcher takes the handover over (list empty)" || bad "handover not cleared: $(hcli list)"
hcli handover "x" >/dev/null; id="$(hcli list | cut -d' ' -f1)"
hcli drop "$id" >/dev/null
[ -z "$(hcli list)" ] && ok "drop <id> ends one" || bad "drop left: $(hcli list)"

# negative control: an always-allow stub must fail every must-block case, or the
# block assertions above prove nothing
printf 'process.stdin.resume();process.stdin.on("end",()=>process.exit(0));
' > "$T/stub.cjs"
G0="$G"; G="$T/stub.cjs"; before=$fail; fail=0
for c in t1 t2 p1; do check "stub on $c" "$T/$c.jsonl" block "$R" >/dev/null; done
caught=$fail; G="$G0"; fail=$before
[ "$caught" = 1 ] && ok "always-allow stub fails the must-block cases" || bad "negative control: stub passed every must-block case"

[ "$fail" = 0 ] && echo "watch-gate: all checks passed" || echo "watch-gate: FAILURES"
exit "$fail"
