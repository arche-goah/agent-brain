#!/usr/bin/env bash
# parallel-sessions.sh — who else is currently working in this repo?
#
# WHY (incident 2026-08-03): two Claude sessions on the same machine shared the
# brain-core checkout — foreign branches in one's own working directory, a
# force-push, and troubleshooting first ran against the wrong MACHINE. No agent
# could SEE that a second session sat in the same folder next door. That is
# exactly what this script makes visible — read-only, stdlib (ps + lsof).
#
# Usage: parallel-sessions.sh [repo-path]      (default: cwd)
# Output: one line per claude process with this cwd.
#
# Exit codes (three-valued since 2026-08-04 — "cannot be checked" is NOT green):
#   0 = at most this own session can be sitting in this repo
#   1 = more than one session (repo-exact via lsof, or machine-wide on Windows)
#   2 = check cannot be performed (neither lsof nor tasklist) — the caller must handle this
#
# WHY three-valued: until 2026-08-04 the missing-lsof path ended with exit 0. On
# Windows the protection mandated by AGENTS §8 was thereby blind AND reported
# green — on 2026-08-04 a commit went to main unreviewed this way while two
# sessions used the same checkout. A check that cannot measure must not report a pass.
#
# A CLI call is not a session (measured 2026-10-09, Windows): `claude plugin list`,
# `claude --version` and friends are claude processes too. During a portability smoke
# onboarding-verify.sh started 36 of them in four minutes, and the machine-wide count
# reported "2 claude sessions" while only one ran. A process whose first argument is a
# CLI subcommand or an info flag is not counted; `-p`/`--print` stays counted — a
# headless run works in the repo like any session.
set -u
R="${1:-$PWD}"
R="$(cd "$R" 2>/dev/null && pwd)" || { echo "parallel-sessions: path unreadable: $1"; exit 2; }

# is_cli_call <command line> — true when the process is a short CLI call, not a session.
is_cli_call() {
  local args
  args=$(printf '%s' "$1" | tr -d '\r' | sed -E 's/^("[^"]*"|[^ ]+) *//')
  case "${args%% *}" in
    plugin|mcp|config|update|doctor|install|setup-token|migrate-installer|--version|-v|--help|-h) return 0 ;;
  esac
  return 1
}

# count_cmdlines — reads one claude command line per stdin line, prints the session count.
count_cmdlines() {
  local n=0 line
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    is_cli_call "$line" || n=$((n + 1))
  done
  echo "$n"
}

machine_wide() {  # $1 = count, $2 = source
  if [ "$1" -gt 1 ]; then
    echo "!! $1 claude sessions on this machine ($2) — cannot attribute repo-exact without lsof."
    echo "   Follow the collision rules: commit after every block, NEVER force-push, hand off via a memory note."
    exit 1
  fi
  echo "parallel-sessions: $1 claude session on this machine ($2, not repo-exact) — a second one is not possible"
  exit 0
}

# Fixture seam: a file with one command line per claude process stands in for the
# Windows process list, so the filter is testable on every platform.
if [ -n "${PARALLEL_SESSIONS_CMDLINES:-}" ]; then
  machine_wide "$(count_cmdlines < "$PARALLEL_SESSIONS_CMDLINES")" "fixture"
fi

if ! command -v lsof >/dev/null 2>&1; then
  # Windows/Git Bash: no lsof, so no cwd per process — only a machine-wide COUNT.
  # That is weaker than repo-exact, but honest: with exactly one running session, a
  # second CANNOT be sitting in this repo — that is a real answer. The command line
  # (CIM) separates sessions from CLI calls; tasklist only has the image name.
  if command -v powershell.exe >/dev/null 2>&1 &&
     cl=$(powershell.exe -NoProfile -NonInteractive -Command \
       "Get-CimInstance Win32_Process -Filter \"Name='claude.exe'\" | ForEach-Object { \$_.CommandLine }" 2>/dev/null); then
    machine_wide "$(printf '%s\n' "$cl" | count_cmdlines)" "process list"
  fi
  if command -v tasklist >/dev/null 2>&1; then
    n=$(tasklist //FI "IMAGENAME eq claude.exe" //NH 2>/dev/null | grep -c '^claude\.exe')
    machine_wide "$n" "tasklist, CLI calls counted too"
  fi
  echo "parallel-sessions: neither lsof nor tasklist — check CANNOT be performed (do not treat as green)"
  exit 2
fi

count=0
for pid in $(ps -axo pid=,comm= | awk '$2 ~ /(^|\/)claude$/ {print $1}'); do
  is_cli_call "$(ps -o args= -p "$pid" 2>/dev/null)" && continue
  cwd=$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)
  if [ "$cwd" = "$R" ]; then
    echo "claude-session pid=$pid cwd=$cwd"
    count=$((count + 1))
  fi
done

# One session (this one) is the normal case; from two on, work is shared.
if [ "$count" -gt 1 ]; then
  echo "!! $count sessions in $R — follow the collision rules: commit after every block, NEVER force-push, hand off via a memory note"
  exit 1
fi
exit 0
