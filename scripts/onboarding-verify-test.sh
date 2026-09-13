#!/usr/bin/env bash
# covers: onboarding-verify (where the report lands)
#
# The verifier writes a report INTO the brain it checks. Until 2026-09-13 that meant the
# brain ROOT — a file the root whitelist (rules/working-rules.md) has no seat for, so
# every run created what the next session had to move or delete (measured three times
# on one instance). The report is an artifact and lands in docs/maintenance/, named by
# host and date. This fixture runs the REAL script against throwaway brains; the eleven
# checks themselves go red there (no plugin, no gh) — fine, only the report's PLACE is
# under test, so the verifier's exit code is ignored. Both directions: a recognised
# brain must keep its root clean, and no brain at all must still leave a report.
#
# Run: bash scripts/onboarding-verify-test.sh    Exit 0 = all green.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
V="$HERE/onboarding-verify.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0
ok()  { echo "  OK   $*"; }
bad() { echo "  FAIL $*"; fails=$((fails + 1)); }

NAME="onboarding-report-${HOSTNAME:-$(hostname)}-$(date +%F).txt"
make_brain() { mkdir -p "$1/core" "$1/.claude"; printf '{}\n' > "$1/.claude/settings.json"; }

# Isolation: a HOME without Projects/*-brain, no BRAIN_DIR, an empty plugin cache — the
# script may find only what the fixture put in front of it, never the real brain.
mkdir -p "$T/home" "$T/cfg" "$T/elsewhere"
run() { # $1 working directory, rest = verifier arguments
  local d="$1"; shift
  ( cd "$d" && HOME="$T/home" CLAUDE_CONFIG_DIR="$T/cfg" env -u BRAIN_DIR bash "$V" "$@" >/dev/null 2>&1 )
}

echo "onboarding-verify — report placement:"

# --- 1 the documented call: brain path as argument, run from elsewhere ---------------
B1="$T/brain1"; make_brain "$B1"
run "$T/elsewhere" "$B1"
[ -e "$B1/onboarding-report.txt" ] && bad "argument: brain root got onboarding-report.txt" \
  || ok "argument: brain root stays clean"
[ -f "$B1/docs/maintenance/$NAME" ] && ok "argument: report at docs/maintenance/$NAME" \
  || bad "argument: report missing under docs/maintenance"

# --- 2 --out wins, and the default is not written beside it -------------------------
B2="$T/brain2"; make_brain "$B2"
run "$T/elsewhere" "$B2" --out "$T/custom/report.txt"
[ -f "$T/custom/report.txt" ] && ok "--out: report at the given path (directory created)" \
  || bad "--out: ignored"
[ -e "$B2/docs/maintenance/$NAME" ] && bad "--out: default file written anyway" \
  || ok "--out: default suppressed"
[ -e "$B2/onboarding-report.txt" ] && bad "--out: brain root got onboarding-report.txt" \
  || ok "--out: brain root stays clean"

# --- 3 the incident path: no argument, standing INSIDE a brain outside ~/Projects ----
B3="$T/brain3"; make_brain "$B3"
run "$B3"
[ -e "$B3/onboarding-report.txt" ] && bad "cwd-is-brain: root got onboarding-report.txt" \
  || ok "cwd-is-brain: root stays clean"
[ -e "$B3/$NAME" ] && bad "cwd-is-brain: report in the root under the new name" \
  || ok "cwd-is-brain: nothing in the root under the new name either"
[ -f "$B3/docs/maintenance/$NAME" ] && ok "cwd-is-brain: report under docs/maintenance" \
  || bad "cwd-is-brain: report missing under docs/maintenance"

# --- 4 no brain anywhere: the working directory keeps the report (unchanged) --------
mkdir -p "$T/nowhere"
run "$T/nowhere"
[ -f "$T/nowhere/$NAME" ] && ok "no brain: report in the working directory" \
  || bad "no brain: report not in the working directory"

echo
if (( fails )); then echo "onboarding-verify-test: $fails FAILURE(S)"; exit 1; fi
echo "onboarding-verify-test: all 9 checks passed"
