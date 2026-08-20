#!/usr/bin/env bash
# The two machinery checks, together, as one command.
#
#   bash scripts/brain-check.sh          # both, full output
#   bash scripts/brain-check.sh --brief  # both, one summary line — unless something
#                                        # is wrong, then the full detail follows
#
# The session start runs --brief (operator, translated: this has to run at every
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
ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || exit 1
STAMP=".claude-state/brain-check.stamp"

rc=0
self_out=$(bash "$HERE/brain-selftest.sh" 2>&1) || rc=1
fric_out=$("$PY" "$HERE/brain-friction.py" 2>&1) || rc=1
mkdir -p .claude-state
date '+%Y-%m-%d %H:%M' > "$STAMP"

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
fixtures=$(printf '%s' "$self_out" | grep -c '^  ok  test-' || true)

if [ "$rc" -eq 0 ] && [ "${fric:-0}" -eq 0 ]; then
  echo "brain-check: machinery ok — ${fixtures} fixture(s) green, ${unproven:-0} without" \
       "an effect proof, ${untrig:-0} untriggered, ${accepted:-0} friction accepted"
  exit 0
fi

# Something is off: the summary alone would be a shrug, so the detail follows.
echo "!! brain-check: needs a look"
printf '%s\n' "$self_out" | grep -E '^  !!|FAILURE' | head -8
printf '%s\n' "$fric_out" | sed -n '/^[a-z-]*([0-9]*):/,$p' | head -12
echo "   full run: bash $HERE/brain-check.sh"
exit "$rc"
