#!/usr/bin/env bash
# A submodule off its pin is loud — unless the brain DECLARED an alpha inside it that is
# still within its date (operator 2026-10-13: "if it all fits, do not report it as an error
# every time"). Runs the real submodule block of helpers/session-bootup.sh on a temp brain.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/../helpers/session-bootup.sh"
BLOCK="$(sed -n '/^declared_alpha() {/,/^done < <(git submodule status/p' "$SRC")"
[ -n "$BLOCK" ] || { echo "bootup-declared-alpha: submodule block not found in session-bootup.sh"; exit 1; }
PY=python3; "$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
g() { git -c user.name=t -c user.email=t@t -c protocol.file.allow=always "$@" >/dev/null 2>&1; }
g init "$T/sub"; g -C "$T/sub" commit --allow-empty -m one
g init "$T/brain"; g -C "$T/brain" submodule add "$T/sub" core; g -C "$T/brain" commit -m pin
g -C "$T/sub" commit --allow-empty -m two
g -C "$T/brain/core" pull origin HEAD
mkdir -p "$T/brain/.claude/rules"
fail=0
run() { # name, alpha json, expect: quiet|loud
  printf '{"alpha": %s}\n' "$2" > "$T/brain/.claude/rules/local-machinery.json"
  local out; out="$(cd "$T/brain" && PY="$PY" bash -c "$BLOCK")"
  local got=other
  [[ "$out" == "submodule core runs a declared alpha"* ]] && got=quiet
  [[ "$out" == "!! submodule core off its committed pin"* ]] && got=loud
  if [ "$got" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (want $3, got $got: $out)"; fail=1; fi
}
run "alpha inside core, in date: quiet"   '{"core/scripts/x.py": {"until": "2999-01-01"}}' quiet
run "alpha on core itself: quiet"         '{"core": {"until": "2999-01-01"}}'              quiet
run "alpha past its date: loud"           '{"core/scripts/x.py": {"until": "2000-01-01"}}' loud
run "alpha elsewhere: loud"               '{"scripts/x.py": {"until": "2999-01-01"}}'      loud
run "prefix is not a path (corex/): loud" '{"corex/a.py": {"until": "2999-01-01"}}'        loud
run "no declaration: loud (control)"      '{}'                                             loud
[ "$fail" = 0 ] && echo "bootup-declared-alpha: all cases pass" || { echo "bootup-declared-alpha: FAILURES"; exit 1; }
