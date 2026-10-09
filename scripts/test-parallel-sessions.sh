#!/usr/bin/env bash
# Fixture test for scripts/parallel-sessions.sh — the machine-wide count (Windows path).
# The must-stay-quiet case is the incident (2026-10-09): one session plus `claude plugin list`
# calls from onboarding-verify.sh, reported as "2 claude sessions".
# Must report: two real sessions, and a headless `-p` run next to a session.
# Usage: bash scripts/test-parallel-sessions.sh (exit 0 = pass)
set -u
S="$(cd "$(dirname "$0")" && pwd)/parallel-sessions.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
run() { printf '%s\n' "$@" > "$T/cl"; out=$(PARALLEL_SESSIONS_CMDLINES="$T/cl" bash "$S" "$T" 2>&1); rc=$?; }

EXE='"C:\Users\x y\.local\bin\claude.exe"'
run "$EXE" "$EXE plugin list" "$EXE plugin list --json" "$EXE --version"
[ "$rc" = 0 ] && case "$out" in *'1 claude session'*) true;; *) false;; esac \
  && ok "one session plus CLI calls counts as one" || bad "incident case: rc=$rc '$out'"

run "$EXE" "$EXE --resume"
[ "$rc" = 1 ] && case "$out" in *'2 claude sessions'*) true;; *) false;; esac \
  && ok "two sessions are reported" || bad "two sessions: rc=$rc '$out'"

run "$EXE" "$EXE -p do-something"
[ "$rc" = 1 ] && ok "a headless -p run counts as a session" || bad "headless: rc=$rc '$out'"

run "/usr/local/bin/claude" "claude mcp list"
[ "$rc" = 0 ] && ok "unquoted paths: mcp call is not a session" || bad "unquoted: rc=$rc '$out'"

run ""
[ "$rc" = 0 ] && case "$out" in *'0 claude session'*) true;; *) false;; esac \
  && ok "empty list counts zero" || bad "empty: rc=$rc '$out'"

# negative control: counting every line (the old tasklist behaviour) must fail the incident case
n=$(grep -c . <<EOF
$EXE
$EXE plugin list
EOF
)
[ "$n" -gt 1 ] && ok "control: a plain line count calls the incident two sessions" || bad "control counted $n"

[ "$fail" = 0 ] && echo "parallel-sessions: all checks passed" || echo "parallel-sessions: FAILURES"
exit "$fail"
