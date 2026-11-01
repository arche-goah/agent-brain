#!/usr/bin/env bash
# ci-lint-local.sh — run the CI's own check steps on this checkout, read from
# .github/workflows/ci.yml, so a counter-check of a PR runs what CI runs.
# long-run: detached
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
# Steps that read GitHub context (`${{ … }}`) are listed as SKIP — unless the context sits only in
# `env:` and every such variable has a local stand-in (see local_context: the PR view against
# origin/main), then they run and say so;
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
# interpreter — the Windows Store stub (OS-17) — a `python3` file onto the probed one goes first on
# PATH, through BASH_ENV so nested bash calls (the fixture suites) see it too. Measured 2026-10-21
# on the Windows instance: five lint steps red that CI runs green. A FILE, not a bash function
# (measured 2026-10-25, Windows instance with the stub): a fixture that probed `command -v python3`
# got the function's name, kept `PY=python3`, and ran `env … "$PY"` — `env` is no bash, it found
# the stub on PATH and the fixture read red ("Python was not found") where CI is green.
PRE="$T/prelude.sh"; : >"$PRE"
if [[ "$PY" != python3 ]]; then
  mkdir -p "$T/py3"
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$(command -v "$PY")" >"$T/py3/python3"; chmod +x "$T/py3/python3"
  printf 'export PATH=%q:"$PATH"\n' "$T/py3" >"$PRE"
fi

# LOCAL CONTEXT: a step whose only GitHub context sits in `env:` runs when every such variable
# has a local stand-in, the PR view of this checkout against origin/main. Measured 2026-10-25 on
# the Windows instance: the english-only ratchet was listed as SKIP, the PR went red in CI on a
# stale legacy-names entry the same command finds locally in a second. A variable without a
# stand-in keeps the step a SKIP.
local_context() { # $1 = variable name -> prints its local value, rc 1 when there is none
  local main; main=$(git -C "$ROOT" rev-parse --verify -q origin/main 2>/dev/null) || main=""
  case "$1" in
    ENGLISH_ONLY_BASE) [[ -n "$main" ]] && echo origin/main ;;
    BASE) [[ -n "$main" ]] && git -C "$ROOT" merge-base origin/main HEAD 2>/dev/null ;;
    HEAD) git -C "$ROOT" rev-parse -q --verify HEAD 2>/dev/null ;;
    *) return 1 ;;
  esac
}

fail=0; ran=0; skipped=0; partial=0
while IFS=$'\t' read -r n job name why; do
  for s in "${skips[@]+"${skips[@]}"}"; do
    [[ -n "$s" && "$name" == *"$s"* ]] && why="skip:--skip $s"
  done
  set_env=""
  if [[ "$why" == env:* ]]; then
    vars="${why#env:}"
    for v in ${vars//,/ }; do
      val=$(local_context "$v") && [[ -n "$val" ]] || { why="skip:reads GitHub context ($v has no local value)"; break; }
      set_env+="export $v=$(printf %q "$val"); "
    done
  fi
  if [[ "$why" == skip:* ]]; then
    echo "  SKIP $job / $name (${why#skip:})"; skipped=$((skipped+1)); continue
  fi
  ran=$((ran+1))
  # </dev/null: a step that reads stdin (a fixture suite did) would eat the rest of the step list
  # this loop reads — measured 2026-10-21, four steps vanished and the run still said "all passed".
  if (cd "$ROOT" && eval "$set_env" && BASH_ENV="$PRE" bash -e "$T/$n.sh") </dev/null >"$T/$n.log" 2>&1; then
    echo "  OK   $job / $name${set_env:+ (GitHub context set locally: ${why#env:})}"
    # A step that passed but says it did NOT check something (english-only names unstaged files):
    # locally that is not the run CI will see. Measured 2026-10-28 on the macOS instance: a new
    # script with German words passed here unstaged and went red in CI; the step's own note never
    # reached the reader, because only the OK line was printed.
    # Only a step's own note line counts: fixture suites print test NAMES with these words.
    if grep -qE '^[[:space:]]*note: .*NOT checked' "$T/$n.log"; then
      grep -E '^[[:space:]]*note: .*NOT checked' "$T/$n.log" | sed 's/^ */       /'
      partial=$((partial+1))
    fi
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
if (( partial )); then
  echo "ci-lint-local: $partial step(s) passed but did NOT check everything (lines above) — stage the files and re-run; this is not the run CI will see"
  exit 1
fi
echo "ci-lint-local: all $ran step(s) passed ($skipped skipped)"
