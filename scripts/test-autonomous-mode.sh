#!/usr/bin/env bash
# Fixture for helpers/autonomous-mode.cjs and the stoppen-gate's autonomous branch.
# The reader: only the operator's NEWEST prompt decides; frames, notifications, hook echoes,
# loaded skill text and request blobs never switch the mode; the operator's language is
# instance data. The gate: in autonomous mode a closing decision question is filed, not asked
# through the tool — a "⚙ autonomous:" line passes there and ONLY there.
# Usage: bash scripts/test-autonomous-mode.sh   (exit 0 = pass)
set -u
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
_D="$(cd "$(dirname "$0")" && pwd)"
M="$_D/../helpers/autonomous-mode.cjs"
G="$_D/../helpers/stoppen-gate.cjs"
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
js() { node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$1"; }
user() { printf '{"type":"user","message":{"role":"user","content":%s}}\n' "$(js "$1")"; }
asst() { printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":%s}]}}\n' "$(js "$1")"; }
skill() { printf '{"type":"user","isMeta":true,"sourceToolUseID":"t1","message":{"role":"user","content":%s}}\n' "$(js "$1")"; }
blob() { printf '{"type":"api-request-blob","message":{"role":"user","content":%s}}\n' "$(js "$1")"; }

EN="$T/en"; mkdir -p "$EN"
DE="$T/de"; mkdir -p "$DE/.claude/rules"
printf '%s\n' '{"on_patterns": ["\\bautonom"], "off_patterns": ["\\bnormalmodus\\b"]}' > "$DE/.claude/rules/autonomous-patterns.json"

mode() { # $1 name, $2 transcript, $3 cwd, $4 expected autonomous|interactive
  local got; got="$(node "$M" "$(native "$2")" "$(native "$3")")"
  [ "$got" = "$4" ] && ok "$1: $4" || bad "$1: expected $4, got $got"
}

f="$T/1.jsonl"; { user "work through the list autonomously"; asst "on it"; } > "$f"
mode "an autonomous order" "$f" "$EN" autonomous
f="$T/2.jsonl"; { user "work through the list autonomously"; asst "x"; user "how is it going?"; } > "$f"
mode "a status question keeps it (latch, macOS finding on #143)" "$f" "$EN" autonomous
qcmd() { printf '{"type":"attachment","attachment":{"type":"queued_command","prompt":%s,"origin":{"kind":"human"}}}\n' "$(js "$1")"; }
f="$T/2q.jsonl"; { user "work through the list autonomously"; asst "x"; qcmd "the desk is running, if you need it"; } > "$f"
mode "a remark typed mid-turn keeps it" "$f" "$EN" autonomous
f="$T/3.jsonl"; { user "autonomous, please"; asst "x"; user "status?"; asst "y"; user "back to normal mode"; } > "$f"
mode "an off word ends it" "$f" "$EN" interactive
f="$T/3b.jsonl"; { user "autonomous, please"; asst "x"; qcmd "put the open decisions to me interactively"; } > "$f"
mode "asking for the interactive way ends it" "$f" "$EN" interactive
f="$T/3c.jsonl"; { user "autonomous, please"; asst "x"; user "normal mode"; asst "y"; user "status?"; } > "$f"
mode "after the off word a plain prompt stays interactive" "$f" "$EN" interactive
f="$T/4.jsonl"; { user "work through the list autonomously"; asst "x"; user "<task-notification>watcher fired</task-notification>"; user "Stop hook feedback: STOP-CHECKS"; } > "$f"
mode "notifications and hook echoes keep it" "$f" "$EN" autonomous
f="$T/5.jsonl"; { user "<system-reminder>rules: an autonomous run never asks</system-reminder>fix the parser"; } > "$f"
mode "the word inside instruction frames does not count" "$f" "$EN" interactive
f="$T/6.jsonl"; { user "fix the parser"; skill "Autonomous run skill: work autonomously"; blob "autonomous everything"; } > "$f"
mode "skill text and request blobs are no prompt" "$f" "$EN" interactive
f="$T/7.jsonl"; { user "alles offene autonom abarbeiten"; } > "$f"
mode "the operator's language from instance data" "$f" "$DE" autonomous
mode "the same German prompt without the data file (discriminator)" "$f" "$EN" interactive
mode "missing transcript fails toward interactive" "$T/none.jsonl" "$EN" interactive

# --- stoppen-gate: which way it demands, and the line that passes only in the mode
gate() { # $1 name, $2 transcript, $3 block|allow, $4 expected text in the reason (block)
  local out; out="$(printf '{"transcript_path":"%s","stop_hook_active":false,"cwd":"%s"}' \
    "$(native "$2")" "$(native "$EN")" | node "$G" 2>&1)"
  if [ "$3" = block ]; then
    case "$out" in *"$4"*) ok "$1 blocks ($4)";; *) bad "$1: expected a block with '$4', got '$out'";; esac
  else
    [ -z "$out" ] && ok "$1 allows" || bad "$1 blocked wrongly: '$out'"
  fi
}
Q="The fix is ready. Should I proceed with the merge?"
f="$T/g1.jsonl"; { user "work through the list autonomously"; asst "$Q"; } > "$f"
gate "autonomous closing question: file it, not the tool" "$f" block "question ledger"
f="$T/g2.jsonl"; { user "work through the list autonomously"; asst "⚙ autonomous: filed in docs/questions.md
$Q"; } > "$f"
gate "autonomous line in the mode" "$f" allow
f="$T/g3.jsonl"; { user "status?"; asst "⚙ autonomous: filed in docs/questions.md
$Q"; } > "$f"
gate "the same line outside the mode is no way out" "$f" block "AskUserQuestion"
f="$T/g4.jsonl"; { user "status?"; asst "$Q"; } > "$f"
gate "interactive closing question still asks for the tool" "$f" block "AskUserQuestion"

echo
[ "$fail" -eq 0 ] && echo "autonomous-mode fixtures: ALL passed" || { echo "autonomous-mode fixtures: FAILURE"; exit 1; }
