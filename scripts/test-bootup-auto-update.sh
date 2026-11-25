#!/usr/bin/env bash
# covers: session-bootup (automatic core update)
# The session start runs brain-update.sh by itself when a core channel is behind the pin
# (operator decision 2026-11-25), detached, and the next start reports how it ended. Held when
# the run would destroy something or the brain said no. Runs the real block of
# helpers/session-bootup.sh on a temp brain with a stub brain-update.sh.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/../helpers/session-bootup.sh"
BLOCK="$(sed -n '/^BU_LOG=/,/^# end automatic update/p' "$SRC")"
[ -n "$BLOCK" ] || { echo "bootup-auto-update: block not found in session-bootup.sh"; exit 1; }
PY=python3; "$PY" -c 'import sys' >/dev/null 2>&1 || PY=python   # OS-17
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
g() { git -c user.name=t -c user.email=t@t "$@" >/dev/null 2>&1; }
# A fake core: helpers/ for HERE, scripts/brain-update.sh as the stub (rc from STUB_RC, writes a DONE/FAIL line).
mkdir -p "$T/stubcore/helpers" "$T/stubcore/scripts"
printf '%s\n' '#!/usr/bin/env bash' 'touch .claude-state/stub-ran' \
  'if [ "${STUB_RC:-0}" = 0 ]; then echo "DONE — already up to date."; else echo "FAIL stub failure"; fi' \
  'exit "${STUB_RC:-0}"' > "$T/stubcore/scripts/brain-update.sh"
fail=0
wait_rc() { local i=0; while [ ! -s "$1/.claude-state/brain-update-auto.rc" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done; }
fresh() { # $1 name -> a brain with a clean core/ repo
  rm -rf "$T/$1"; mkdir -p "$T/$1/.claude/rules"; g init "$T/$1/core"; g -C "$T/$1/core" commit --allow-empty -m one
}
run() { # $1 brain, then env assignments; prints the block's output
  local b="$1"; shift
  (cd "$T/$b" && env "$@" PY="$PY" HERE="$T/stubcore/helpers" bash -c "core_alpha=\"\${core_alpha:-}\"; ahead_note=\"\${ahead_note:-}\"; upd=\"\${upd:-}\"; $BLOCK")
}
check() { # name, output, pattern (case glob)
  case "$2" in $3) echo "ok   $1" ;; *) echo "FAIL $1: $2"; fail=1 ;; esac
}

fresh a
out=$(run a upd="core rules v2.0.4 -> v2.1.7")
check "behind the pin: the start runs the update" "$out" "core update started automatically:*"
wait_rc "$T/a"
[ -f "$T/a/.claude-state/stub-ran" ] && echo "ok   the update really ran" || { echo "FAIL the stub never ran"; fail=1; }
out=$(run a)
check "the next start reports a clean end" "$out" "core update ran automatically*DONE*"
out=$(run a)
check "the report comes once" "$out" ""

fresh b
out=$(run b upd="x -> y" STUB_RC=1); wait_rc "$T/b"
out=$(run b)
check "a failed run is reported loud with its FAIL line" "$out" "!! automatic core update*rc 1*FAIL stub failure*"

fresh c
out=$(run c upd="x -> y" core_alpha=1)
check "a declared core alpha holds it" "$out" "!! update available*held: a declared core alpha*"
fresh d
out=$(run d upd="x -> y" ahead_note="core checkout v2.1.8-1 is ahead")
check "a checkout ahead of the pin holds it" "$out" "!! update available*held: the core checkout is ahead*"
fresh e; echo dirt > "$T/e/core/x.txt"
out=$(run e upd="x -> y")
check "local changes in core/ hold it" "$out" "!! update available*held: core/ has local changes*"
fresh f; printf '{"hold_until": "2999-01-01", "reason": "show day"}\n' > "$T/f/.claude/rules/core-update.json"
out=$(run f upd="x -> y")
check "a hold date holds it, with its reason" "$out" "!! update available*held until 2999-01-01*show day*"
fresh h; printf '{"hold_until": "2000-01-01"}\n' > "$T/h/.claude/rules/core-update.json"
out=$(run h upd="x -> y")
check "a past hold date holds nothing (control)" "$out" "core update started automatically:*"
wait_rc "$T/h"
fresh i; printf '{"auto": false, "reason": "test machine"}\n' > "$T/i/.claude/rules/core-update.json"
out=$(run i upd="x -> y")
check "auto false holds it" "$out" "!! update available*auto false (test machine)*"
fresh j; mkdir -p "$T/j/.claude-state"; echo $$ > "$T/j/.claude-state/brain-update-auto.pid"
out=$(run j upd="x -> y")
check "a run still going holds a second one" "$out" "!! update available*still going*"
fresh k
out=$(run k)
check "nothing behind: nothing started (control)" "$out" ""
[ -f "$T/k/.claude-state/stub-ran" ] && { echo "FAIL control: the update ran with nothing behind"; fail=1; }

[ "$fail" = 0 ] && echo "bootup-auto-update: all cases pass" || { echo "bootup-auto-update: FAILURES"; exit 1; }
