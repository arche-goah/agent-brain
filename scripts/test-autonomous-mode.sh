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
# A timer-fired prompt (ScheduleWakeup, /loop) is not the operator's word (measured 2026-10-28, Claude
# Code 2.1.312: isMeta, promptSource "system", queuePriority "later"). Control: the same text typed.
tick() { printf '{"type":"user","isMeta":true,"promptSource":"system","queuePriority":"later","message":{"role":"user","content":%s}}\n' "$(js "$1")"; }
f="$T/2w.jsonl"; { user "autonomous, please"; asst "x"; user "back to normal mode"; asst "y"; tick "# Autonomous loop check  You're being invoked on a timer"; } > "$f"
mode "a timer-fired prompt does not switch it on" "$f" "$EN" interactive
f="$T/2x.jsonl"; { user "autonomous, please"; asst "x"; tick "back to normal mode"; } > "$f"
mode "a timer-fired prompt does not switch it off" "$f" "$EN" autonomous
f="$T/2y.jsonl"; { user "back to normal mode"; asst "y"; user "# Autonomous loop check"; } > "$f"
mode "the same words typed by the operator switch it (control)" "$f" "$EN" autonomous
f="$T/3.jsonl"; { user "autonomous, please"; asst "x"; user "status?"; asst "y"; user "back to normal mode"; } > "$f"
mode "an off word ends it" "$f" "$EN" interactive
# Asking what is open ends it: the operator is here (operator 2026-10-26, Windows instance).
f="$T/3b.jsonl"; { user "autonomous, please"; asst "x"; user "anything open for me?"; } > "$f"
mode "asking what is open ends it" "$f" "$EN" interactive
f="$T/3e.jsonl"; { user "autonomous, please"; asst "x"; qcmd "anything open for me?"; } > "$f"
mode "asking mid-turn ends it" "$f" "$EN" interactive
# The answer to "continue autonomously?" arrives as a tool result.
# A real answer is the result of an AskUserQuestion call (its tool_use comes first, same id).
answer() { printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t9","name":"AskUserQuestion","input":{"questions":[]}}]}}\n'
  printf '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t9","content":%s}]}}\n' "$(js "Your questions have been answered: $1. You can now continue")"; }
# The same text as the result of a Read (2026-10-28: a fixture read ended the run) is no answer.
readres() { printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"r1","name":"Read","input":{"file_path":"x"}}]}}\n'
  printf '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"r1","content":%s}]}}\n' "$(js "Your questions have been answered: $1. You can now continue")"; }
f="$T/3f.jsonl"; { user "autonomous, please"; user "anything open for me?"; answer '"Continue autonomously?"="Yes, continue (Recommended)"'; } > "$f"
mode "yes to continue autonomously sets it again" "$f" "$EN" autonomous
f="$T/3g.jsonl"; { user "autonomous, please"; user "anything open for me?"; answer '"Continue autonomously?"="No, interactive"'; } > "$f"
mode "no to continue autonomously keeps it off" "$f" "$EN" interactive
f="$T/3h.jsonl"; { user "autonomous, please"; user "anything open for me?"; answer '"Release now?"="Yes"'; } > "$f"
mode "yes to another question sets nothing" "$f" "$EN" interactive
f="$T/3k.jsonl"; { user "autonomous, please"; user "anything open for me?"; answer '"The autonomous gate held the settings edit back; the patch is in a file. Shall I apply it now?"="Yes, apply it now"'; } > "$f"
mode "an on-word outside the question sentence makes no mode question (2026-10-31)" "$f" "$EN" interactive
f="$T/3l.jsonl"; { user "anything open for me?"; answer '"Patch applied. Continue autonomously?"="Yes"'; } > "$f"
mode "the on-word in the question sentence still is the mode question (control)" "$f" "$EN" autonomous
f="$T/3i.jsonl"; { user "fix the parser"; answer '"Continue autonomously?"="Yes"'; user "status?"; } > "$f"
mode "after the yes a status question keeps it" "$f" "$EN" autonomous
f="$T/3r.jsonl"; { user "autonomous, please"; asst "x"; readres '"Continue autonomously?"="No, interactive"'; } > "$f"
mode "a Read result carrying the answer marker is no answer (the 2026-10-28 incident)" "$f" "$EN" autonomous
# The operator's complaints carry the word "interactive" and mean the opposite (macOS finding on #142).
f="$T/3d.jsonl"; { user "autonomous, please"; asst "x"; user "you stopped interactively again, that blocks everything"; } > "$f"
mode "complaining about an interactive stop keeps it" "$f" "$EN" autonomous
f="$T/3j.jsonl"; { user "work through everything autonomously"; user "do not stop everything interactively, collect the questions"; } > "$f"
mode "a negated interactive keeps it" "$f" "$EN" autonomous
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
printf '%s\n' '{"on_patterns": ["\\bautonom"], "off_patterns": ["\\bnormalmodus\\b"], "yes_patterns": ["^\\s*ja\\b"]}' > "$DE/.claude/rules/autonomous-patterns.json"
printf '%s\n' '{"ask_patterns": ["\\birgendwas\\b[^?\\n]{0,30}\\boffen\\b"]}' > "$DE/.claude/rules/open-items.json"
f="$T/7b.jsonl"; { user "weiter autonom"; user "irgendwas offen?"; } > "$f"
mode "the operator's ask wording from instance data ends it" "$f" "$DE" interactive
f="$T/7c.jsonl"; { user "weiter autonom"; user "irgendwas offen?"; answer '"Weiter autonom?"="Ja, weiter autonom"'; } > "$f"
mode "the operator's yes from instance data sets it again" "$f" "$DE" autonomous
mode "missing transcript fails toward interactive" "$T/none.jsonl" "$EN" interactive
# The word inside a question mentions the mode, it does not order it (macOS finding 2026-10-27).
f="$T/8.jsonl"; { user "fix the parser"; user "did I not get the continue autonomously question? why?"; } > "$f"
mode "the word in a question sets nothing" "$f" "$EN" interactive
f="$T/8c.jsonl"; { user "why did it stop? carry on autonomously."; } > "$f"
mode "an order after a question in the same message sets it" "$f" "$EN" autonomous

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
