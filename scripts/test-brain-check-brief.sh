#!/usr/bin/env bash
# Fixture test for brain-check.sh --brief, the failure rendering: the failing check is NAMED,
# a Python traceback inside a fixture's output is dropped (frames and caret lines), the
# cache key of a reused verdict is dropped, and ordinary detail lines survive untouched.
# Measured 2026-10-11 on a Windows brain: the session start showed "(reused: … key …)" and
# then only "~~~~^^^^" — the name of the failing check never reached the operator.
# Usage: bash scripts/test-brain-check-brief.sh (exit 0 = pass)
set -u
S="$(cd "$(dirname "$0")" && pwd)/brain-check.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/brain"
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }

cat > "$T/self.txt" <<'EOF'
brain self-test — /x/brain

fixtures (effect proof):
  ok  test-absence-gate
  !!  brain-selftest-test FAILED
          OK   a declared hand tool is not executed
          FAIL the hand tool was skipped without saying so — silence is not a report
          Traceback (most recent call last):
            File "/x/brain/core/scripts/thing.py", line 3, in <module>
              main()
              ~~~~^^
          ~~~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   (reused: out of date, re-measuring in the background; this is the previous result, measured 19m ago, key 9975d4ba34f4)
SELF-TEST: FAILURE — something with a proof failed it
EOF
out=$(CLAUDE_PROJECT_DIR="$(native "$T/brain")" BRAIN_CHECK_STUB_SELF="$(native "$T/self.txt")" BRAIN_CHECK_STUB_RC=1 bash "$S" --brief 2>&1)

case "$out" in *'!! brain-check: needs a look'*) ok "red is announced";; *) bad "no announcement: '$out'";; esac
case "$out" in *'brain-selftest-test FAILED'*) ok "the failing check is named";; *) bad "check not named: '$out'";; esac
case "$out" in *'FAIL the hand tool was skipped'*) ok "the FAIL detail line survives";; *) bad "detail line lost: '$out'";; esac
case "$out" in *'^^^'*) bad "caret line leaked: '$out'";; *) ok "caret lines are dropped";; esac
case "$out" in *'File "'*|*'Traceback'*) bad "traceback frame leaked: '$out'";; *) ok "traceback frames are dropped";; esac
case "$out" in *'(reused: out of date'*) ok "the reused-verdict note survives";; *) bad "reused note lost: '$out'";; esac
case "$out" in *'key 9975'*) bad "cache key leaked: '$out'";; *) ok "the cache key is dropped";; esac

# negative control: the unfiltered shape (the old grep alone) DOES leak the caret line
old=$(grep -aE '^  !!|^        |^   \(reused:|FAILURE' "$T/self.txt")
case "$old" in *'^^^'*) ok "control: the old rendering leaks the caret line";; *) bad "control did not leak";; esac

# --cached (the session start): first start says the run is in the background and returns at once;
# the background run leaves the brief result, which the next start prints with its time.
C="$T/cached"; mkdir -p "$C"
cached() { CLAUDE_PROJECT_DIR="$(native "$C")" BRAIN_CHECK_STUB_SELF="$(native "$T/self.txt")" BRAIN_CHECK_STUB_RC=1 bash "$S" --cached 2>&1; }
t0=$(date +%s); first=$(cached); t1=$(date +%s)
case "$first" in *'first run measuring in the background'*) ok "--cached: a first start says the run is in the background";; *) bad "--cached first: '$first'";; esac
[ $((t1 - t0)) -le 2 ] && ok "--cached returns at once" || bad "--cached took $((t1 - t0)) s"
n=0; while [ ! -s "$C/.claude-state/brain-check.brief" ] && [ "$n" -lt 50 ]; do sleep 0.2; n=$((n + 1)); done
[ -s "$C/.claude-state/brain-check.brief" ] && ok "--cached: the background run leaves its result" || bad "no background result"
# Wait for COMPLETION, not for absence (Windows review of #379): on a slow process start "no temporary file yet"
# and "the run is finished" look the same, so the check waits until the result file is newer than a marker.
touch "$C/marker"; sleep 1
second=$(cached)
case "$second" in *'brain-selftest-test FAILED'*) ok "--cached: the next start shows the stored result";; *) bad "--cached second: '$second'";; esac
case "$second" in *'(brain-check: result of '*) ok "--cached: the stored result says when it was measured";; *) bad "no time note: '$second'";; esac
n=0; while ! [ "$C/.claude-state/brain-check.brief" -nt "$C/marker" ] && [ "$n" -lt 50 ]; do sleep 0.2; n=$((n + 1)); done
[ "$C/.claude-state/brain-check.brief" -nt "$C/marker" ] && ok "--cached: the second background run finished" || bad "second background run never finished"
ls "$C/.claude-state/brain-check.brief."* >/dev/null 2>&1 && bad "a temporary result file was left behind" || ok "--cached: no temporary file left behind"
[ -s "$C/.claude-state/brain-check.stamp.epoch" ] && ok "--cached: the run stores its time as a number" || bad "no epoch stamp"

# A commit after the stored result (2026-10-28: a self-test red at 12:44, fixed at 13:00, still
# read FAILURE at the 13:48 start): the reused result says that commits came after it.
G="$T/cachedgit"; mkdir -p "$G/.claude-state"
cp "$C/.claude-state/brain-check.brief" "$G/.claude-state/"
date '+%Y-%m-%d %H:%M' > "$G/.claude-state/brain-check.stamp"
echo $(( $(date +%s) - 100 )) > "$G/.claude-state/brain-check.stamp.epoch"
git -C "$G" init -q; printf x > "$G/f"; git -C "$G" add f
git -C "$G" -c user.email=t@t -c user.name=t commit -qm fix
gcached() { CLAUDE_PROJECT_DIR="$(native "$G")" BRAIN_CHECK_STUB_SELF="$(native "$T/self.txt")" BRAIN_CHECK_STUB_RC=1 bash "$S" --cached 2>&1; }
out=$(gcached)
case "$out" in *'1 commit(s) since that result'*) ok "--cached: a commit after the result is named";; *) bad "newer commit not named: '$out'";; esac
echo $(( $(date +%s) + 100 )) > "$G/.claude-state/brain-check.stamp.epoch"
out=$(gcached)
case "$out" in *'since that result'*) bad "named commits although none is newer: '$out'";; *) ok "--cached: no note when nothing is newer";; esac

[ "$fail" = 0 ] && echo "brain-check-brief: all checks passed" || echo "brain-check-brief: FAILURES"
exit "$fail"
