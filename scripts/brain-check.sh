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
PY=python3
"$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || exit 1
PY="${PYTHON:-python3}"
STAMP=".claude-state/brain-check.stamp"

rc=0
self_out=$(bash scripts/brain-selftest.sh 2>&1) || rc=1
fric_out=$("$PY" scripts/brain-friction.py 2>&1) || rc=1
mkdir -p .claude-state
date '+%Y-%m-%d %H:%M' > "$STAMP"

if [ "${1:-}" != "--brief" ]; then
  printf '%s\n\n%s\n' "$self_out" "$fric_out"
  exit "$rc"
fi

# --- brief: the numbers that change, not the list that does not ---------------
unproven=$(printf '%s' "$self_out" | grep -c '^  ??' || true)
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
echo "   full run: bash scripts/brain-check.sh"
exit "$rc"
