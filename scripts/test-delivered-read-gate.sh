#!/usr/bin/env bash
# Fixture for helpers/delivered-read-gate.cjs: a fact file delivered by the inbox in this turn
# must be read in this turn. Cases: unread (block), read by Read, read by a Bash command, a
# LOG-only line (no path, nothing to read), a delivery in an EARLIER turn, the unread-ok escape.
# The transcript path goes to node through the hook payload, built with native() (OS-3).
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="$HERE/../helpers/delivered-read-gate.cjs"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FAIL=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAIL=1; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

user() { printf '{"message":{"role":"user","content":%s}}\n' "$(node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$1")"; }
tool() { printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"%s","input":%s}]}}\n' "$1" "$2"; }
say()  { printf '{"message":{"role":"assistant","content":[{"type":"text","text":%s}]}}\n' "$(node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$1")"; }

EVENT='<task-notification>
<summary>Monitor event</summary>
<event>shared-memory inbox (for this instance), 1 since last start:
  - 2026-10-18 [core] sam-laptop: AN kim-win (status: info): a finding about the updater (core/finding-updater-2026-10-18.md)</event>
</task-notification>'
LOGONLY='<task-notification>
<event>shared-memory inbox (for this instance), 1 since last start:
  - 2026-10-18 [core] sam-laptop: AN kim-win: LOG entry, whole ¶ body line</event>
</task-notification>'

run() { # name expect(block|allow) file
  local out
  out=$(printf '{"transcript_path":"%s"%s}' "$(native "$3")" "${XP:-}" | node "$GATE")
  if [[ "$2" == block ]]; then
    grep -q 'DELIVERED-READ' <<<"$out" && grep -q 'finding-updater' <<<"$out" && pass "$1" || fail "$1 (expected block): $out"
  else
    [[ -z "$out" ]] && pass "$1" || fail "$1 (expected allow): $out"
  fi
}

T="$TMP/unread.jsonl"; { user "please go on"; user "$EVENT"; say "Noted, handing the operator a command."; } > "$T"
run "a delivered fact file that is not read blocks" block "$T"

T="$TMP/read.jsonl"; { user "please go on"; user "$EVENT"; tool Read '{"file_path":"/x/shared/core/finding-updater-2026-10-18.md"}'; say "Read it."; } > "$T"
run "a Read of the delivered file passes" allow "$T"

T="$TMP/bash.jsonl"; { user "please go on"; user "$EVENT"; tool Bash '{"command":"cat core/finding-updater-2026-10-18.md"}'; } > "$T"
run "a Bash command naming the file passes" allow "$T"

T="$TMP/log.jsonl"; { user "please go on"; user "$LOGONLY"; say "The LOG line is the whole message."; } > "$T"
run "a LOG-only line (no fact file) passes" allow "$T"

T="$TMP/earlier.jsonl"; { user "first prompt"; user "$EVENT"; say "later"; user "a new operator prompt"; say "answer"; } > "$T"
run "a delivery in an earlier turn is not this turn's duty" allow "$T"

T="$TMP/escape.jsonl"; { user "please go on"; user "$EVENT"; say "unread-ok: addressed to another instance, not acting on it"; } > "$T"
run "unread-ok with a reason passes" allow "$T"

# NEGATIVE CONTROL for the read check: a Read of a DIFFERENT file does not count.
T="$TMP/other.jsonl"; { user "please go on"; user "$EVENT"; tool Read '{"file_path":"/x/shared/core/LOG.md"}'; } > "$T"
run "control: reading another file does not count as reading this one" block "$T"

# Own echo by LABEL (operator 2026-10-10: no codes in the stop lines): behind the dispatcher
# the gate gets stop_check.label and its line carries no token — one block per turn still holds,
# and another check's line is not its own.
XP=',"stop_check":{"label":"UNREAD","marker":"DELIVERED-READ"}'
T="$TMP/echo-label.jsonl"; { user "please go on"; user "$EVENT"; say "Noted."; user "Stop hook feedback:
UNREAD — shown, not read: core/finding-updater-2026-10-18.md"; say "Not acting on it."; } > "$T"
run "own echo by label: second stop in the turn passes" allow "$T"
T="$TMP/echo-foreign.jsonl"; { user "please go on"; user "$EVENT"; say "Noted."; user "Stop hook feedback:
CLASS — gate.cjs changed"; say "ok"; } > "$T"
run "another check's line is not its own echo" block "$T"
out=$(printf '{"transcript_path":"%s"%s}' "$(native "$T")" "$XP" | node "$GATE")
grep -q '"echo":"label"' <<<"$out" && pass "the block declares the label echo" || fail "no label declaration: $out"
XP=''

exit $FAIL
