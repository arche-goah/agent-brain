#!/usr/bin/env bash
# covers: session-bootup (automatic core update)
# The session start runs brain-update.sh by itself when a core channel is behind the pin
# (operator decision 2026-11-25), detached, and the next start reports how it ended. Held - and
# failing CLOSED - when the run would destroy something or the brain said no (review of #670 on
# Windows, 2026-11-25: nine hold-file forms, a clean core/ with local commits and two simultaneous
# starts each started it). Runs the real block of helpers/session-bootup.sh on a temp brain with a
# stub brain-update.sh and a stub machine-key.sh.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/../helpers/session-bootup.sh"
BLOCK="$(sed -n '/^BU_LOG=/,/^# end automatic update/p' "$SRC")"
[ -n "$BLOCK" ] || { echo "bootup-auto-update: block not found in session-bootup.sh"; exit 1; }
PY=python3; "$PY" -c 'import sys' >/dev/null 2>&1 || PY=python   # OS-17
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
g() { git -c user.name=t -c user.email=t@t "$@" >/dev/null 2>&1; }
mkdir -p "$T/stubcore/helpers" "$T/stubcore/scripts"
printf '%s\n' '#!/usr/bin/env bash' 'touch .claude-state/stub-ran' \
  'if [ "${STUB_RC:-0}" = 0 ]; then echo "WARN stub warning"; echo "DONE — already up to date."; else echo "FAIL stub failure"; fi' \
  'exit "${STUB_RC:-0}"' > "$T/stubcore/scripts/brain-update.sh"
printf '%s\n' 'machine_key() { echo testbox; }' > "$T/stubcore/scripts/machine-key.sh"
fail=0
wait_rc() { local i=0; while [ ! -s "$1/.claude-state/brain-update-auto.rc" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done; }
fresh() { # $1 name -> a brain whose core/ is a clean checkout detached on a release tag (the normal state)
  rm -rf "$T/$1"; mkdir -p "$T/$1/.claude/rules"; g init "$T/$1/core"; g -C "$T/$1/core" commit --allow-empty -m one
  g -C "$T/$1/core" tag v1.0.0; g -C "$T/$1/core" checkout --detach v1.0.0
}
run() { # $1 brain, then env assignments; prints the block's output
  local b="$1"; shift
  (cd "$T/$b" && env "$@" PY="$PY" HERE="$T/stubcore/helpers" bash -c "core_alpha=\"\${core_alpha:-}\"; ahead_note=\"\${ahead_note:-}\"; upd=\"\${upd:-}\"; $BLOCK")
}
check() { # name, output, pattern (case glob)
  case "$2" in $3) echo "ok   $1" ;; *) echo "FAIL $1: $2"; fail=1 ;; esac
}
held() { # name, brain, reason glob, env...
  local n="$1" b="$2" p="$3"; shift 3
  local out; out=$(run "$b" upd="x -> y" "$@")
  check "$n" "$out" "!! update available*held: $p*"
  [ -f "$T/$b/.claude-state/stub-ran" ] && { echo "FAIL $n: the update ran anyway"; fail=1; }
}
hold_file() { # brain, printf format of the file content (bytes)
  fresh "$1"; printf "$2" > "$T/$1/.claude/rules/core-update.json"
}

fresh a
out=$(run a upd="core rules v2.0.4 -> v2.1.7")
check "behind the pin: the start runs the update" "$out" "core update started automatically:*"
wait_rc "$T/a"
[ -f "$T/a/.claude-state/stub-ran" ] && echo "ok   the update really ran" || { echo "FAIL the stub never ran"; fail=1; }
[ -d "$T/a/.claude-state/brain-update-auto.lock" ] && { echo "FAIL the lock outlived the run"; fail=1; }
out=$(run a)
check "the next start reports a clean end, with the WARN lines" "$out" "core update ran automatically*DONE*warnings: WARN stub warning*"
out=$(run a)
check "the report comes once" "$out" ""

fresh b
run b upd="x -> y" STUB_RC=1 >/dev/null; wait_rc "$T/b"
rm -f "$T/b/.claude-state/stub-ran"
out=$(run b upd="x -> y")
check "a failed run is reported loud with its FAIL line" "$out" "!! automatic core update*rc 1*FAIL stub failure*"
check "... and the next try waits (no run per start)" "$out" "*held: the last automatic run failed*"
[ -f "$T/b/.claude-state/stub-ran" ] && { echo "FAIL a failed run was retried at the next start"; fail=1; }
out=$(run b upd="x -> y" BU_QUIET_H=0)
check "after the quiet period it runs again" "$out" "core update started automatically:*"
wait_rc "$T/b"

fresh c; held "a declared core alpha holds it" c "a declared core alpha*" core_alpha=1
fresh d; held "a checkout ahead of the pin holds it" d "the core checkout is ahead*" ahead_note="ahead"
fresh e; echo dirt > "$T/e/core/x.txt"; held "local changes in core/ hold it" e "core/ has local changes*"
fresh f2; g -C "$T/f2/core" commit --allow-empty -m local; held "a clean core/ with a local commit holds it" f2 "core/ HEAD is no released tag*"
fresh f3; g -C "$T/f3/core" checkout -b feature; held "core/ on a branch holds it" f3 "core/ is on branch feature*"

hold_file h1 '{"hold_until": "2999-01-01", "reason": "show day"}\n'; held "a hold date holds it, with its reason" h1 "held until 2999-01-01*show day*"
hold_file h2 '\357\273\277{"hold_until": "2999-01-01"}\n'; held "a hold file with a UTF-8 BOM holds" h2 "held until 2999-01-01*"
hold_file h3 '\377\376{\000"\000h\000o\000l\000d\000_\000u\000n\000t\000i\000l\000"\000:\000"\0002\0009\0009\0009\000-\0000\0001\000-\0000\0001\000"\000}\000'; held "a UTF-16 hold file holds" h3 "held until 2999-01-01*"
hold_file h4 '{"hold_until": "2999-01-01",}\n'; held "an unparsable hold file holds" h4 "*not readable as a hold*"
hold_file h5 '{"auto": "false"}\n'; held "auto as a string holds" h5 '*sets auto "false"*'
hold_file h6 '{"auto": 0}\n'; held "auto 0 holds" h6 "*sets auto 0*"
hold_file h7 ''; held "an empty hold file holds" h7 "*not readable as a hold*"
hold_file h8 '{"hold_until": "01.01.2027"}\n'; held "a non-ISO date holds" h8 "*is no YYYY-MM-DD date*"
hold_file h9 '[{"hold_until": "2999-01-01"}]\n'; held "a list instead of an object holds" h9 "*is no JSON object*"
hold_file h10 '{"Hold_Until": "2999-01-01"}\n'; held "keys in any case count" h10 "held until 2999-01-01*"
hold_file h11 '{"auto": false, "reason": "test machine"}\n'; held "auto false holds it" h11 "*sets auto false (test machine)*"
hold_file h12 '{"hold_until": "2000-01-01"}\n'
out=$(run h12 upd="x -> y"); check "a past hold date holds nothing (control)" "$out" "core update started automatically:*"; wait_rc "$T/h12"
hold_file h13 '{"auto": true}\n'
out=$(run h13 upd="x -> y"); check "auto true holds nothing (control)" "$out" "core update started automatically:*"; wait_rc "$T/h13"

fresh m; mkdir -p "$T/m/config/machines"; printf '# testbox\n- Session pull: off\n' > "$T/m/config/machines/testbox.md"
held "the machine profile's session-pull switch holds it" m "switched off on this machine*"
fresh m2; mkdir -p "$T/m2/config/machines"; printf '# testbox\r\n- Core update: OFF (show day)\r\n' > "$T/m2/config/machines/testbox.md"
held "a Core update: off line (CRLF, any case) holds it" m2 "switched off on this machine*"

fresh l; mkdir -p "$T/l/.claude-state/brain-update-auto.lock"; held "a run still going (the lock) holds a second one" l "*still going*"
fresh l2; mkdir -p "$T/l2/.claude-state/brain-update-auto.lock"; touch -t 200001010000 "$T/l2/.claude-state/brain-update-auto.lock"
out=$(run l2 upd="x -> y"); check "a lock older than an hour is taken over" "$out" "core update started automatically:*"; wait_rc "$T/l2"
fresh p; ( run p upd="x -> y" > "$T/p.1" ) & ( run p upd="x -> y" > "$T/p.2" ) & wait
n=$(cat "$T/p.1" "$T/p.2" | grep -ac "started automatically")
[ "$n" = 1 ] && echo "ok   two starts at the same instant: one run" || { echo "FAIL two simultaneous starts gave $n runs"; fail=1; }
wait_rc "$T/p"
fresh o; held "BRAIN_UPDATE_AUTO_OFF holds it" o "BRAIN_UPDATE_AUTO_OFF*" BRAIN_UPDATE_AUTO_OFF=1

fresh k
out=$(run k)
check "nothing behind: nothing started (control)" "$out" ""
[ -f "$T/k/.claude-state/stub-ran" ] && { echo "FAIL control: the update ran with nothing behind"; fail=1; }

[ "$fail" = 0 ] && echo "bootup-auto-update: all cases pass" || { echo "bootup-auto-update: FAILURES"; exit 1; }
