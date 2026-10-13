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

[ "$fail" = 0 ] && echo "brain-check-brief: all checks passed" || echo "brain-check-brief: FAILURES"
exit "$fail"
