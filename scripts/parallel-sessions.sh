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
set -u
R="${1:-$PWD}"
R="$(cd "$R" 2>/dev/null && pwd)" || { echo "parallel-sessions: path unreadable: $1"; exit 2; }

if ! command -v lsof >/dev/null 2>&1; then
  # Windows/Git Bash: no lsof, so no cwd per process. tasklist can at least COUNT.
  # That is weaker (machine-wide instead of repo-exact), but honest: with exactly one
  # running session, a second CANNOT be sitting in this repo — that is a real answer.
  if command -v tasklist >/dev/null 2>&1; then
    n=$(tasklist //FI "IMAGENAME eq claude.exe" //NH 2>/dev/null | grep -c '^claude\.exe')
    if [ "$n" -gt 1 ]; then
      echo "!! $n claude sessions on this machine (tasklist) — cannot attribute repo-exact without lsof."
      echo "   Follow the collision rules: commit after every block, NEVER force-push, hand off via a memory note."
      exit 1
    fi
    echo "parallel-sessions: $n claude session on this machine (tasklist, not repo-exact) — a second one is not possible"
    exit 0
  fi
  echo "parallel-sessions: neither lsof nor tasklist — check CANNOT be performed (do not treat as green)"
  exit 2
fi

count=0
for pid in $(ps -axo pid=,comm= | awk '$2 ~ /(^|\/)claude$/ {print $1}'); do
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
