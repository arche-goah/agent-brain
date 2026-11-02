#!/usr/bin/env bash
# A fixture suite that RUNS the session start (helpers/session-bootup.sh, helpers/session-pull.sh)
# gives it a home of its own. Measured 2026-11-01 on the Windows instance: running the suites on a
# real machine rewrote the operator's ~/.claude/helpers/statusline.cjs and ~/.claude/settings.json
# through the bootup's statusline selfheal. CI never shows it: a runner's home is thrown away.
# HOME alone is not the home on Windows - Python's expanduser and node's os.homedir() read
# USERPROFILE there - so a suite needs both. Both directions: the shipped suites pass, and a suite
# that runs the bootup without its own home is named (negative control).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SELF="$(basename "$0")"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }

# A line that runs the session start: `bash "..."` naming the helper or a variable that holds it.
# A cut-out block (`bash -c "$BLOCK"`, `bash "$TMP/block.sh"`) is not the whole bootup and does not count.
RUNS='^[^#]*bash "[^"]*(BOOT|PULL|session-bootup\.sh|session-pull\.sh)'
runs() { # $1 = dir -> every suite in it that runs the session start
  local f
  for f in "$1"/test-*.sh "$1"/*-test.sh "$1"/portability-smoke.sh; do
    [ -f "$f" ] && [ "$(basename "$f")" != "$SELF" ] && grep -qE "$RUNS" "$f" && printf '%s\n' "$f"
  done
  return 0
}
bare() { # $1 = dir -> the suites among them without a home of their own (HOME and USERPROFILE)
  local f
  runs "$1" | while IFS= read -r f; do
    grep -qE '(^|[^A-Z_])HOME=' "$f" && grep -q 'USERPROFILE=' "$f" || basename "$f"
  done
}

n=$(runs "$HERE" | grep -ac .)   # -a: this count is part of the verdict (OS-5)
found=$(bare "$HERE")
[ "$n" -gt 0 ] || bad "no suite runs the session start - the pattern no longer matches the suites"
[ -z "$found" ] && ok "all $n suites that run the session start set their own HOME and USERPROFILE" \
  || bad "runs the session start with the home of the machine running it: ${found//$'\n'/ }"

# Negative control: the check names the suite without its own home, and only that one.
mkdir -p "$T/s"
printf '%s\n' 'out=$(CLAUDE_PROJECT_DIR="$B" bash "$BOOTUP" 2>&1)' > "$T/s/test-bare.sh"
printf '%s\n' 'export HOME="$T/home"' 'out=$(bash "$BOOT")' > "$T/s/test-home-only.sh"
printf '%s\n' 'export HOME="$T/home" USERPROFILE="$T/home"' 'out=$(bash "$BOOT")' > "$T/s/test-own.sh"
printf '%s\n' 'BLOCK="$(sed -n "/x/,/y/p" "$SRC")"' 'out="$(bash -c "$BLOCK")"' > "$T/s/test-block.sh"
got=$(bare "$T/s" | sort | tr '\n' ' ')
[ "$got" = "test-bare.sh test-home-only.sh " ] && ok "negative control: no home and HOME without USERPROFILE are named, own home and a cut-out block are not" \
  || bad "negative control: got '$got'"

[ "$fail" = 0 ] && echo "test-fixture-own-home: all green" || echo "test-fixture-own-home: FAILURES"
exit "$fail"
