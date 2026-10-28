#!/usr/bin/env bash
# The two machinery checks, together, as one command.
#
#   bash scripts/brain-check.sh          # both, full output
#   bash scripts/brain-check.sh --brief  # both, one summary line — unless something
#                                        # is wrong, then the full detail follows
#
# The session start runs --cached, which is --brief one start late (see below; operator, translated: this has to run at every
# session start, no exceptions). Full run every time, short output every time:
# skipping the run when
# nothing changed would have missed everything that breaks WITHOUT a file changing —
# a submodule update, a deleted target, a permission change. The cost is ~5 s of wall
# clock at startup, and the output is one line when all is well.
#
# WHY the pair (operator, 2026-08-20): "does every mechanism still run" and "do those
# mechanisms contradict each other" are different questions with different failure
# modes. The first is answered by executing fixtures, the second by comparing wiring
# against wiring. Neither is a substitute for the other, and neither needs a model.
set -u
PY="${PYTHON:-python3}"
"$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
# Sibling scripts are resolved next to THIS file, never relative to the brain: when the
# core runs against a consuming brain, scripts/ is the brain's directory and the suite
# lives in core/scripts. Measured 2026-08-20 — the wrapper looked for its own tools in
# the wrong repo and reported a failure that was its own path handling.
HERE="$(cd "$(dirname "$0")" && pwd)"
# Root is one level further up when this file lives in core/scripts (a consumed
# brain) than when it lives in scripts/ (the bare agent-brain repo) — going up a
# fixed one level lands on core/ itself for the former. Measured 2026-08-20: with
# CLAUDE_PROJECT_DIR unset (true for a manually invoked shell, not just hooks),
# ROOT resolved to .../core, `.claude/settings.json` was unreachable from there,
# and the hooks-wired check silently reported 0 hooks instead of 15 — a false
# green, not an error.
if [ "$(basename "$(dirname "$HERE")")" = "core" ]; then
  DEFAULT_ROOT="$(cd "$HERE/../.." && pwd)"
else
  DEFAULT_ROOT="$(cd "$HERE/.." && pwd)"
fi
ROOT="${CLAUDE_PROJECT_DIR:-$DEFAULT_ROOT}"
cd "$ROOT" || exit 1
STAMP=".claude-state/brain-check.stamp"

# --cached: what the SESSION START runs. It prints the brief result of the previous run and
# starts the next full run in the background, so the start pays a file read, not the run.
# Measured 2026-10-16 on a Windows brain on v1.4.4: brain-check took 15 s of the bootup even
# when the self-test verdict was reused (the non-fixture half and brain-friction still ran in
# the foreground), the whole start 42 s against the hook's 30 s, and past the limit the harness
# kills the hook and the AI gets no session-start report at all. The run still happens at
# every start — only its answer arrives one start later, said with its time. A person running
# brain-check by hand never gets this mode.
if [ "${1:-}" = "--cached" ]; then
  mkdir -p .claude-state
  OUT=".claude-state/brain-check.brief"
  if [ -s "$OUT" ]; then
    cat "$OUT"
    echo "   (brain-check: result of $(cat "$STAMP" 2>/dev/null || echo 'an earlier start'); the next run is measuring in the background)"
    # A reused result can be overtaken by a commit made after it (measured 2026-10-28 on the
    # macOS instance: a self-test red at 12:44, fixed at 13:00, still read FAILURE at the 13:48
    # start). Count the commits since the run; the reader then knows a finding may be fixed.
    since=$(cat "$STAMP.epoch" 2>/dev/null)
    if [ -n "$since" ]; then
      newer=$(git log -n 200 --format=%ct 2>/dev/null | awk -v s="$since" '$1 > s' | wc -l | tr -d ' ')
      [ "${newer:-0}" -gt 0 ] && echo "   ($newer commit(s) since that result — a finding above may be fixed already; the background run re-measures)"
    fi
  else
    echo "brain-check: first run measuring in the background — its result comes at the next session start"
  fi
  # $$ in the temporary name: two sessions starting together must not write into one file.
  ( BRAIN_SELFTEST_BG=1 bash "$HERE/brain-check.sh" --brief > "$OUT.$$" 2>/dev/null
    mv -f "$OUT.$$" "$OUT" ) >/dev/null 2>&1 &
  exit 0
fi

rc=0
if [ -n "${BRAIN_CHECK_STUB_SELF:-}" ]; then
  # Fixture seam: a stored self-test output stands in for the run, so the brief rendering
  # is testable without a brain (scripts/test-brain-check-brief.sh).
  self_out=$(cat "$BRAIN_CHECK_STUB_SELF"); rc="${BRAIN_CHECK_STUB_RC:-1}"
  fric_out="0 friction candidate(s) — decide each, none of them is a verdict."
else
  self_out=$(bash "$HERE/brain-selftest.sh" "$ROOT" 2>&1) || rc=1
  fric_out=$("$PY" "$HERE/brain-friction.py" "$ROOT" 2>&1) || rc=1
fi
mkdir -p .claude-state
date '+%Y-%m-%d %H:%M' > "$STAMP"
date +%s > "$STAMP.epoch"

if [ "${1:-}" != "--brief" ]; then
  printf '%s\n\n%s\n' "$self_out" "$fric_out"
  exit "$rc"
fi

# --- brief: the numbers that change, not the list that does not ---------------
# "mechanisms without a fixture" and "executables nothing calls" share the same
# "  ??  " marker (brain-selftest.sh:193,252,255) — grepping that marker across the
# whole output double-counts the untriggered list as unproven whenever the fixture
# gap is 0, so it must read brain-selftest.sh's own tally line instead of re-deriving
# it (measured 2026-08-20: reported "2 without an effect proof" while the true count
# was 0, mirroring the untriggered count of 2).
unproven=$(printf '%s' "$self_out" | sed -n 's/^\([0-9]*\) mechanism(s) without an effect proof.*/\1/p')
untrig=$(printf '%s' "$self_out" | sed -n 's/.*(\([0-9]*\) without a trigger.*/\1/p')
fric=$(printf '%s' "$fric_out" | sed -n 's/^\([0-9]*\) friction candidate.*/\1/p')
accepted=$(printf '%s' "$fric_out" | sed -n 's/.*(\([0-9]*\) candidate(s) accepted.*/\1/p')
# Every fixture line, not just the `test-*` shape: since discovery, suites also arrive
# as `<thing>-test.sh` and `<thing>-test.py`, and counting one shape reported 7 green
# where 15 had run — a headline number quietly measuring a third of what it named.
fixtures=$(printf '%s' "$self_out" | sed -n '/^fixtures (effect proof)/,/^$/p' \
           | grep -ac '^  ok  ' || true)

if [ "$rc" -eq 0 ] && [ "${fric:-0}" -eq 0 ]; then
  echo "brain-check: machinery ok — ${fixtures} fixture(s) green, ${unproven:-0} without" \
       "an effect proof, ${untrig:-0} untriggered, ${accepted:-0} friction accepted"
  exit 0
fi

# Something is off: the summary alone would be a shrug, so the detail follows.
echo "!! brain-check: needs a look"
# The failing check, its detail lines (indented eight), and whether the verdict is a
# stored one — "red" alone tells the operator nothing (operator, 2026-09-24: "ich mag
# genau wissen, was anschlaegt"). A red result that names no check is itself a defect of
# the check, and says so instead of leaving a bare FAILURE line to be guessed at.
# Detail lines carry a fixture's own output, and a Python traceback inside it is noise here:
# the operator saw a bare "~~~~^^^^" line where the failing check's name should have stood
# (measured 2026-10-11, Windows). Traceback frames and caret lines go; the FAIL lines stay.
# The cache key of a reused verdict is a handle for the machine, not a word for the reader.
printf '%s\n' "$self_out" | grep -aE '^  !!|^        |^   \(reused:|FAILURE' \
  | grep -avE '^[[:space:]]*(Traceback \(most recent|File "|[~^[:space:]]+$)' \
  | sed -E 's/, key [0-9a-f]{6,}\)/)/' | head -16
if [ "$rc" -ne 0 ] && ! printf '%s\n' "$self_out" | grep -aq '^  !!'; then
  echo "  !!  red, but no check is named as failing — the stored result is incomplete," \
       "not a finding; report it as a defect of the self-test"
fi
# The space before the count is part of the shape brain-friction.py prints
# (`allowlist-contradiction (1):`). Without it in the pattern the range never opens, so
# the brief mode announced "needs a look" and then said NOTHING about what to look at —
# measured 2026-09-24 on a Windows brain, but the miss is OS-independent and had simply
# never been exercised: this branch only runs when a candidate exists.
printf '%s\n' "$fric_out" | sed -n '/^[a-z-]* *([0-9]*):/,$p' | head -12
echo "   full run: bash $HERE/brain-check.sh"
exit "$rc"
