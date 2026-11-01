#!/usr/bin/env bash
# The opening question ("n I can handle — shall I?") belongs to the session START only
# (operator correction 2026-10-10). Runs the real closing block of helpers/session-bootup.sh
# with each SessionStart source: compact must not order the question, startup/resume must.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/../helpers/session-bootup.sh"
BLOCK="$(sed -n '/^# The opening question/,/^fi$/p' "$SRC")"
[ -n "$BLOCK" ] || { echo "bootup-compact: closing block not found in session-bootup.sh"; exit 1; }
fail=0
run() { # name, hook input, expect: ask|no-ask
  local out; out="$(HOOK_INPUT="$2" bash -c "$BLOCK")"
  local got=no-ask; [[ "$out" == *"shall I?\" (ONE OK"* ]] && got=ask
  if [ "$got" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (want $3, got $got)"; fail=1; fi
}
run "startup asks once"            '{"session_id":"s","source":"startup"}' ask
run "resume asks once"             '{"session_id":"s","source":"resume"}'  ask
run "hand run (no payload) asks"   ''                                      ask
run "compaction does not ask"      '{"session_id":"s","source":"compact"}' no-ask
run "compaction with spaces"       '{"source": "compact"}'                 no-ask
# The instructions print BEFORE the block (2026-10-30: a 29.7 KB report, the harness preview held 2 KB,
# instructions after the block were outside it).
ins=$(grep -n "^  printf '%s\\\\n' '-> Claude: start the first reply" "$SRC" | head -1 | cut -d: -f1)
blk=$(grep -n "^printf '%s\\\\n' '<session-bootup trust" "$SRC" | head -1 | cut -d: -f1)
if [ -n "$ins" ] && [ -n "$blk" ] && [ "$ins" -lt "$blk" ]; then echo "ok   instructions print before the block"
else echo "FAIL instructions print before the block (instruction line ${ins:-?}, block line ${blk:-?})"; fail=1; fi
[ "$fail" = 0 ] && echo "bootup-compact: all cases pass" || { echo "bootup-compact: FAILURES"; exit 1; }
