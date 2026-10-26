#!/usr/bin/env bash
# Fixture for scripts/watch-pr.sh: its own --selftest (cutoff substitution, and with jq the
# negative control that an older review stays out), and the one-watch-per-PR sharing (2026-10-26):
# a second watch on the same PR follows the first one's lines without a GitHub call of its own and
# ends with its MERGED line; a watch on another PR polls on its own. Kept as a test-*.sh so the
# discovered fixture runners (CI, portability-smoke, brain-selftest) execute it on every OS.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$HERE/watch-pr.sh" --selftest || exit 1

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
# A fake gh: logs which watch called it (WATCH_ID), answers one comment, and reports the PR merged
# once the flag file exists.
mkdir -p "$T/bin"
printf '%s\n' '#!/usr/bin/env bash' \
  'echo "$WATCH_ID" >> "$T_DIR/calls"' \
  'case "$*" in *"pr view"*) [ -f "$T_DIR/merged" ] && echo MERGED || echo OPEN ;;' \
  '  *issues/*/comments*) [ -f "$T_DIR/said" ] || { touch "$T_DIR/said"; echo "COMMENT peer: looks good"; } ;; esac' > "$T/bin/gh"
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH" T_DIR="$T" WATCH_PR_LOCK_DIR="$T/locks" WATCH_PR_STEP=1

WATCH_ID=first bash "$HERE/watch-pr.sh" o/r 7 1 > "$T/first" 2>&1 &
first=$!
sleep 2
WATCH_ID=second bash "$HERE/watch-pr.sh" o/r 7 1 > "$T/second" 2>&1 &
second=$!
sleep 3
touch "$T/merged"
wait "$first"; wait "$second"
if grep -q "following its lines" "$T/second" && grep -q "PR #7 MERGED" "$T/second" \
   && ! grep -q "^second$" "$T/calls"; then
  echo "  OK   a second watch on the same PR follows the first: no gh call of its own, ends with MERGED"
else
  echo "  FAIL second watch on the same PR"; sed 's/^/       /' "$T/second"; echo "       calls: $(sort "$T/calls" | uniq -c | tr '\n' ' ')"; fail=1
fi
grep -q "PR #7 MERGED" "$T/first" && echo "  OK   the first watch still reports MERGED itself" \
  || { echo "  FAIL first watch"; sed 's/^/       /' "$T/first"; fail=1; }

# Control: a watch on ANOTHER PR does not attach.
rm -f "$T/merged" "$T/said" "$T/calls"
WATCH_ID=a bash "$HERE/watch-pr.sh" o/r 7 1 > "$T/a" 2>&1 &
a=$!
sleep 2
WATCH_ID=b bash "$HERE/watch-pr.sh" o/r 8 1 > "$T/b" 2>&1 &
b=$!
sleep 2
touch "$T/merged"
wait "$a"; wait "$b"
if ! grep -q "following its lines" "$T/b" && grep -q "^b$" "$T/calls"; then
  echo "  OK   a watch on another PR polls on its own (control)"
else
  echo "  FAIL control: watch on another PR attached"; sed 's/^/       /' "$T/b"; fail=1
fi
[ "$fail" = 0 ] && echo "watch-pr: all checks passed" || { echo "watch-pr: FAILURES"; exit 1; }
