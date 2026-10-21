#!/usr/bin/env bash
# Fixture for scripts/ci-lint-local.sh: a synthetic workflow with a passing step, a failing
# step, a step that reads GitHub context, a `run: |` block and a `sudo` line. Both directions:
# a failing step makes the run red and prints its output; all-passing is green; context and
# --skip are listed, never run.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fails=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; sed 's/^/       /' "$T/out"; fails=$((fails+1)); }

mkdir -p "$T/repo/.github/workflows"
cat > "$T/repo/.github/workflows/ci.yml" <<'YML'
name: CI
on: [push]
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@abc # v1
      - name: passes
        run: test -f .github/workflows/ci.yml
      - name: block with sudo
        run: |
          sudo apt-get install -y nothing-here
          echo block-ran > marker-block
      - name: reads context
        env:
          BASE: ${{ github.event.before }}
        run: echo "$BASE" > marker-ctx
      - name: fails on purpose
        run: |
          echo the-failure-text
          exit 3
  other:
    runs-on: ubuntu-latest
    steps:
      - name: reads stdin
        run: cat > stdin-seen
      - name: other passes
        run: echo other > marker-other
YML

run() { CI_LINT_ROOT="$T/repo" bash "$HERE/ci-lint-local.sh" "$@" >"$T/out" 2>&1; }

echo "ci-lint-local"
run lint; rc=$?
[ "$rc" = 1 ] && ok "a failing step makes the run red (rc 1)" || bad "a failing step makes the run red (rc $rc)"
grep -q "the-failure-text" "$T/out" && ok "the failing step's output is printed" || bad "the failing step's output is printed"
grep -q "OK   lint / passes" "$T/out" && ok "a passing step is OK" || bad "a passing step is OK"
[ -f "$T/repo/marker-block" ] && ok "a run: | block runs, its sudo line dropped" || bad "a run: | block runs, its sudo line dropped"
grep -q "SKIP lint / reads context (reads GitHub context)" "$T/out" && [ ! -f "$T/repo/marker-ctx" ] \
  && ok "a step reading GitHub context is listed, not run" || bad "a step reading GitHub context is listed, not run"

rm -f "$T/repo/marker-"*
run --skip "on purpose" lint; rc=$?
[ "$rc" = 0 ] && ok "--skip leaves the failing step out: green (rc 0)" || bad "--skip leaves the failing step out: green (rc $rc)"
grep -q "SKIP lint / fails on purpose (--skip on purpose)" "$T/out" && ok "--skip is named" || bad "--skip is named"

run other; rc=$?
[ "$rc" = 0 ] && [ -f "$T/repo/marker-other" ] && ok "a named job runs, the others do not" || bad "a named job runs, the others do not"
[ -f "$T/repo/stdin-seen" ] && [ ! -s "$T/repo/stdin-seen" ] && grep -q "OK   other / other passes" "$T/out" \
  && ok "a step that reads stdin gets nothing and the next step still runs" || bad "a step that reads stdin gets nothing and the next step still runs"
grep -q "lint /" "$T/out" && bad "job filter leaked lint steps" || ok "job filter leaks nothing"

run nosuchjob; rc=$?
[ "$rc" = 2 ] && grep -q "unknown job" "$T/out" && ok "an unknown job is rc 2 and named" || bad "an unknown job is rc 2 and named (rc $rc)"

echo
if [ "$fails" -eq 0 ]; then echo "test-ci-lint-local: all checks passed"; exit 0; fi
echo "test-ci-lint-local: $fails check(s) FAILED"; exit 1
