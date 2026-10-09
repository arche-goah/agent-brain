#!/usr/bin/env bash
# parallel-sessions-watch.sh — one line whenever the set of Claude sessions working in a repo
# changes. Built for Monitor; normally started by scripts/collab-watch.sh.
#
#   parallel-sessions-watch.sh [repo-path] [interval_s]     (defaults: cwd, 60)
#
# WHY (measured on the proving instance): the session-start check reports parallel sessions
# only at the moment a session STARTS. Two sessions joined hours later, nothing said so, and
# a PR from one of them was reviewed as a collaborator's foreign work. A snapshot at start
# cannot see a later arrival; a watch can.
#
# The detection itself lives ONCE, in scripts/parallel-sessions.sh — this only diffs its
# output between polls. Comparing the whole output (not parsed pids) keeps it right on
# Windows too, where that script can only count sessions machine-wide. Its exit 2 means
# "cannot be checked" and is said, never read as "alone".
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R="${1:-$PWD}"
INTERVAL="${2:-60}"
PARENT=$PPID
prev=""
first=1
unknown_said=0

while true; do
  out=$(bash "$HERE/parallel-sessions.sh" "$R" 2>/dev/null); rc=$?
  out="${out//$'\r'/}"
  if [[ $rc -eq 2 ]]; then
    [[ $unknown_said -eq 0 ]] && echo "SESSIONS: check not performable here — parallel sessions are UNKNOWN, not absent"
    unknown_said=1
  else
    unknown_said=0
    summary=$(printf '%s' "$out" | tr '\n' '|' | sed 's/|$//; s/|/ | /g')
    if [[ $first -eq 1 ]]; then
      echo "SESSIONS: ${summary:-at most this session in $R}"
      first=0
    elif [[ "$out" != "$prev" ]]; then
      echo "SESSIONS: changed — ${summary:-at most this session in $R} — own-account commits/PRs may come from any of them"
    fi
    prev="$out"
  fi
  for (( slept = 0; slept < INTERVAL; slept += 5 )); do
    sleep 5
    kill -0 "$PARENT" 2>/dev/null || exit 0
  done
done
