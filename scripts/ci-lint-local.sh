#!/usr/bin/env bash
# ci-lint-local.sh — run the CI's own check steps on this checkout, read from
# .github/workflows/ci.yml, so a counter-check of a PR runs what CI runs.
#
# WHY (measured 2026-10-21, twice in one day on the macOS instance): a PR counter-check ran
# the fixtures of the touched parts and reported "macOS OK"; CI then went red in a lint step
# the check had not run (scripts/invariant-check.py docs/os-traps.md — a new file not in the
# OS-trap register, then a new site of a known trap). A hand-kept list of "the steps to run"
# is the same omission one level up, so the steps come from the workflow file itself.
#
# Usage: bash scripts/ci-lint-local.sh [--skip <text>]... [job ...]
#   job       CI job names to run (default: leaks lint shellcheck)
#   --skip    leave out every step whose name contains <text> (repeatable), e.g. --skip fixture
# Steps that read GitHub context (`${{ … }}`) cannot run locally and are listed as SKIP;
# lines starting with `sudo ` (runner package setup) are dropped, the rest of the step runs.
# exit 0 = every runnable step passed · 1 = a step failed (its full output is printed) ·
# 2 = the workflow or a job could not be read.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${CI_LINT_ROOT:-$HERE/..}" && pwd)"   # CI_LINT_ROOT: the fixture's synthetic repo
PY=python3; "$PY" -c 'import sys' >/dev/null 2>&1 || PY=python   # Windows: python3 can be the Store stub (OS-17)

skips=(); jobs=()
while (( $# )); do
  case "$1" in
    --skip) skips+=("${2:-}"); shift 2 ;;
    -h|--help) sed -n '2,18p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) jobs+=("$1"); shift ;;
  esac
done
(( ${#jobs[@]} )) || jobs=(leaks lint shellcheck)

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
TN="$T"; command -v cygpath >/dev/null 2>&1 && TN="$(cygpath -m "$T")"   # OS-3: native path for python
WF="$ROOT/.github/workflows/ci.yml"; WFN="$WF"; command -v cygpath >/dev/null 2>&1 && WFN="$(cygpath -m "$WF")"
PARSER="$HERE/ci-lint-local-parse.py"; command -v cygpath >/dev/null 2>&1 && PARSER="$(cygpath -m "$PARSER")"

# The parser writes each step's script to <tmp>/<n>.sh and prints one index line per step.
if ! index="$("$PY" "$PARSER" "$WFN" "$TN" "${jobs[@]}")"; then
  echo "ci-lint-local: could not read the steps of $WF"; exit 2
fi

# The CI steps say `python3` (right on the Ubuntu runner). Where `python3` is not the working
# interpreter — the Windows Store stub (OS-17) — every step body gets `python3` as a function onto
# the probed one, through BASH_ENV so nested bash calls (the fixture suites) see it too. Measured
# 2026-10-21 on the Windows instance: five lint steps red that CI runs green.
PRE="$T/prelude.sh"; : >"$PRE"
if [[ "$PY" != python3 ]]; then
  printf 'python3() { %q "$@"; }\nexport -f python3\n' "$(command -v "$PY")" >"$PRE"
fi

fail=0; ran=0; skipped=0
while IFS=$'\t' read -r n job name why; do
  for s in "${skips[@]+"${skips[@]}"}"; do
    [[ -n "$s" && "$name" == *"$s"* ]] && why="skip:--skip $s"
  done
  if [[ "$why" == skip:* ]]; then
    echo "  SKIP $job / $name (${why#skip:})"; skipped=$((skipped+1)); continue
  fi
  ran=$((ran+1))
  # </dev/null: a step that reads stdin (a fixture suite did) would eat the rest of the step list
  # this loop reads — measured 2026-10-21, four steps vanished and the run still said "all passed".
  if (cd "$ROOT" && BASH_ENV="$PRE" bash -e "$T/$n.sh") </dev/null >"$T/$n.log" 2>&1; then
    echo "  OK   $job / $name"
  elif [[ $? -eq 127 ]] && miss=$(sed -n 's/.*: \([^:]*\): command not found.*/\1/p' "$T/$n.log" | head -1) && [[ -n "$miss" ]]; then
    # A tool the step needs is not installed here (the runner installs it): not checked, said so —
    # never a finding, never a silent pass.
    echo "  SKIP $job / $name (not installed here: $miss — this step was NOT checked)"
    ran=$((ran-1)); skipped=$((skipped+1))
  else
    echo "  FAIL $job / $name"
    sed 's/^/       /' "$T/$n.log"
    fail=$((fail+1))
  fi
done <<<"$index"

echo
# Every listed step must have been judged: a count that falls short is a red run, never a green one.
want=$(grep -c . <<<"$index")
if (( ran + skipped != want )); then
  echo "ci-lint-local: only $((ran + skipped)) of $want step(s) judged — the step list was cut short"; exit 1
fi
if (( fail )); then echo "ci-lint-local: $fail of $ran step(s) FAILED ($skipped skipped)"; exit 1; fi
echo "ci-lint-local: all $ran step(s) passed ($skipped skipped)"
