#!/usr/bin/env bash
# collab-watch.sh — THE collaboration watch: arms every configured channel at once and
# merges their events onto this script's stdout, so ONE Monitor call covers the lot:
#
#   Monitor({ command: "bash core/scripts/collab-watch.sh", persistent: true })
#   bash core/scripts/collab-watch.sh --dry-run      # print the plan, arm nothing
#
# Channels (which ones, which repos, which intervals = INSTANCE data, never in this file):
#   shared memory      scripts/shared-memory-watch.sh  — commits from other instances/parties
#   repo watches       scripts/repo-activity-watch.sh  — PRs, merges, comments, review comments
#   parallel sessions  scripts/parallel-sessions-watch.sh — sessions joining/leaving this repo
# Each runs under scripts/watch-supervisor.sh, so a child that dies says so.
#
# Config: $COLLAB_WATCH_CONFIG, default <instance>/.claude/rules/collab-watch.json
#         (template: templates/rules-instance/collab-watch.json)
# Scope:  $COLLAB_WATCH_SCOPE = all (default) | peers | <party label/id/login>
# State:  $COLLAB_WATCH_STATE, default <instance>/.claude-state/collab-watch — cursors AND
#         locks of every channel. Its own shared-memory cursor on purpose: sharing the cursor
#         of the session-start check lets ANY session's start consume a find before the
#         designated watcher reports it. Two sessions that must watch independently each set
#         their own COLLAB_WATCH_STATE (it moves the locks too, so neither is refused).
#
# Skill: skills/collab-watch/SKILL.md (procedure, handling flow, lessons).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTANCE="${CLAUDE_PROJECT_DIR:-$PWD}"
CONFIG="${COLLAB_WATCH_CONFIG:-$INSTANCE/.claude/rules/collab-watch.json}"
SCOPE="${COLLAB_WATCH_SCOPE:-all}"
STATE="${COLLAB_WATCH_STATE:-$INSTANCE/.claude-state/collab-watch}"
PY=python3
"$PY" -c 'import sys' >/dev/null 2>&1 || PY=python

PLAN=$("$PY" "$HERE/collab-watch-plan.py" "$CONFIG" "$SCOPE") || exit $?
PLAN="${PLAN//$'\r'/}"
field() { awk -v k="$1" '$1 == k { $1 = ""; sub(/^ /, ""); print }' <<<"$PLAN"; }
ONLY_LOGINS=$(field SCOPE_LOGINS)
ONLY_PARTIES=$(field SCOPE_PARTIES)
SCOPE_LABEL=$(field SCOPE_LABEL)

if [[ "${1:-}" == "--dry-run" ]]; then
  printf '%s\n' "$PLAN"
  exit 0
fi

# Party filter for the shared-memory stream. Only FOUND: lines are judged; NOTE/ERROR lines
# always pass, and a find whose party could NOT be determined passes too — an unknown party
# is a finding, not noise. fflush(), or the line sits in awk's buffer and the watch looks
# silent. Applied to the WHOLE stdout, not piped onto one background job: a pipe would make
# `$!` the filter's pid, and the cleanup would kill the filter while the watch kept polling.
sm_scope_filter() {
  if [[ "$ONLY_PARTIES" != "-" ]]; then
    awk -v list="$ONLY_PARTIES" \
      'BEGIN { n = split(list, p, " ") }
       /^FOUND:/ {
         if (index($0, "unknown party")) { print; fflush(); next }
         for (i = 1; i <= n; i++) if (index($0, p[i])) { print; fflush(); next }
         next
       }
       { print; fflush() }'
  else
    cat
  fi
}
exec > >(sm_scope_filter)

mkdir -p "$STATE"
pids=()
# Supervisors kill their own child on TERM (see watch-supervisor.sh), so killing them is
# enough — portable, no pkill.
# TERM/INT must EXIT, not only clean up: a bash trap that does not exit swallows the signal,
# and the script went on polling its parent with every supervisor already gone (measured in
# the live smoke of this script: TaskStop-style TERM left the arm process running).
cleanup() { for p in "${pids[@]}"; do kill "$p" 2>/dev/null; done; }
trap cleanup EXIT
trap 'exit 0' INT TERM

armed=()
while read -r kind a b rest; do
  case "$kind" in
    SM)
      repo="$b${rest:+ $rest}"
      repo="${repo/#\~/$HOME}"
      sm_cursor="$STATE/shared-memory-cursor.json"
      if [[ ! -s "$sm_cursor" ]]; then
        git -C "$repo" fetch -q origin main 2>/dev/null
        sha=$(git -C "$repo" rev-parse origin/main 2>/dev/null)
        if [[ -z "$sha" ]]; then
          echo "ERROR: cannot read origin/main in $repo — shared-memory channel NOT armed"
          continue
        fi
        printf '{\n  "lastSeenSha": "%s",\n  "lastCheckedAt": "seeded"\n}\n' "$sha" > "$sm_cursor"
        echo "NOTE: shared-memory cursor seeded at ${sha:0:8} — older commits are NOT reported"
      fi
      SHARED_MEMORY_REPO="$repo" SHARED_MEMORY_STATE="$sm_cursor" SHARED_MEMORY_LOCK_DIR="$STATE" \
        bash "$HERE/watch-supervisor.sh" shared-memory \
        bash "$HERE/shared-memory-watch.sh" watch "$a" &
      pids+=($!); armed+=("shared-memory ${a}s") ;;
    REPO)
      REPO_ACTIVITY_STATE_DIR="$STATE" REPO_ACTIVITY_TAG="$a" GH_WATCH_REPOS="$rest" \
        GH_SELF_LOGIN="-" GH_ONLY_LOGINS="$ONLY_LOGINS" \
        bash "$HERE/watch-supervisor.sh" "repos-$a" \
        bash "$HERE/repo-activity-watch.sh" "$b" &
      pids+=($!); armed+=("$a [$rest] ${b}s") ;;
    SESSIONS)
      bash "$HERE/watch-supervisor.sh" parallel-sessions \
        bash "$HERE/parallel-sessions-watch.sh" "$INSTANCE" "$a" &
      pids+=($!); armed+=("parallel sessions ${a}s") ;;
  esac
done <<<"$PLAN"

echo "NOTE: collaboration watch armed, scope=$SCOPE ($SCOPE_LABEL) — $(IFS=';'; echo "${armed[*]}") (state: $STATE)"
if [[ "$ONLY_LOGINS" != "-" ]]; then
  echo "NOTE: reporting ONLY $ONLY_LOGINS (parties: $ONLY_PARTIES) — everything else, the operator's own other machines included, is dropped and NOT replayed after switching back"
fi

# The watch lives and dies with the session that armed it. A plain `wait` never returns
# (supervisors restart forever), so an orphaned tree would keep polling and keep the locks.
PARENT=$PPID
while kill -0 "$PARENT" 2>/dev/null; do sleep 5 & wait $!; done
exit 0
