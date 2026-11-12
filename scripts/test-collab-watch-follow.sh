#!/usr/bin/env bash
# covers: collab-watch.sh
# Fixture for the follow mode of collab-watch.sh: a second session on the same state dir
# follows the holder's events instead of being skipped, ignores a stale pid file, and takes
# the watch over when the holder ends.
#
# WHY (measured 2026-11-06): a second session armed collab-watch.sh, every channel answered
# "already armed by another session", and a Windows finding on that session's own PR reached
# only the first session. Negative control: with the follow mode removed, case 1 prints no
# event line and fails.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CW="$HERE/collab-watch.sh"
fails=0; checks=0
ok()  { checks=$((checks + 1)); echo "  OK   $*"; }
bad() { checks=$((checks + 1)); fails=$((fails + 1)); echo "  FAIL $*"; }

T="$(mktemp -d)"
FAKE=""; RUN=""
cleanup() { [[ -n "$RUN" ]] && kill "$RUN" 2>/dev/null; [[ -n "$FAKE" ]] && kill "$FAKE" 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT
# The config reaches python only as an argument (Git Bash converts argv); the state dir only
# reaches bash. Only the local session channel is configured, so a takeover polls no network.
printf '%s\n' '{"parallel_sessions": {"interval": 3600}, "parties": []}' > "$T/cfg.json"
export COLLAB_WATCH_CONFIG="$T/cfg.json" COLLAB_WATCH_STATE="$T/state" COLLAB_WATCH_FOLLOW_POLL=1
export SHARED_MEMORY_CHANNELS_CONFIG="$T/none.json"
mkdir -p "$T/state"

wait_for() {  # $1 file, $2 fixed string, $3 tries of 0.2 s
  local i
  for ((i = 0; i < ${3:-50}; i++)); do grep -qF -- "$2" "$1" 2>/dev/null && return 0; sleep 0.2; done
  return 1
}

echo "1. a live holder: the second session follows its events"
sleep 300 & FAKE=$!
echo "$FAKE" > "$T/state/collab-watch.pid"
bash "$CW" > "$T/out1" 2>&1 & RUN=$!
wait_for "$T/out1" "following its events" 50 && ok "the follower names the holder" || bad "no follow note: $(head -3 "$T/out1")"
echo "COMMENT acme/core https://example.invalid/pull/7 :: a finding on the follower's PR" >> "$T/state/events.log"
wait_for "$T/out1" "a finding on the follower's PR" 50 && ok "a line the holder logs reaches the follower" || bad "event not relayed: $(cat "$T/out1")"
grep -q "NOTE: collaboration watch armed" "$T/out1" && bad "the follower armed channels of its own" || ok "the follower arms nothing of its own"

echo "2. the holder ends: the follower takes over"
kill "$FAKE"; wait "$FAKE" 2>/dev/null; FAKE=""
wait_for "$T/out1" "takes over the collaboration watch" 50 && ok "takeover announced" || bad "no takeover: $(cat "$T/out1")"
wait_for "$T/out1" "NOTE: collaboration watch armed" 50 && ok "the new holder arms the watch" || bad "no arm after takeover: $(cat "$T/out1")"
[[ "$(cat "$T/state/collab-watch.pid" 2>/dev/null)" == "$RUN" ]] && ok "the pid file names the new holder" || bad "pid file: $(cat "$T/state/collab-watch.pid" 2>/dev/null) vs $RUN"
kill "$RUN" 2>/dev/null; wait "$RUN" 2>/dev/null; RUN=""

echo "3. a stale pid file (dead pid) is no holder"
sleep 0 & dead=$!; wait "$dead" 2>/dev/null
echo "$dead" > "$T/state/collab-watch.pid"
bash "$CW" > "$T/out3" 2>&1 & RUN=$!
wait_for "$T/out3" "NOTE: collaboration watch armed" 50 && ok "a dead pid is ignored, the watch arms" || bad "stale pid not ignored: $(cat "$T/out3")"
grep -q "following its events" "$T/out3" && bad "followed a dead holder" || ok "no follow on a dead pid"

echo "4. the holder logs what it reports"
echo "NOTE: fixture line" > /dev/null
wait_for "$T/state/events.log" "NOTE: collaboration watch armed" 50 && ok "the holder's own lines land in events.log" || bad "events.log lacks the holder's arm line"
kill "$RUN" 2>/dev/null; wait "$RUN" 2>/dev/null; RUN=""
sleep 0.5
[[ -f "$T/state/collab-watch.pid" ]] && bad "the holder left its pid file on exit" || ok "the holder removes its pid file on exit"

echo "5. COLLAB_WATCH_SHOW: a session is told only its topic, the log keeps everything (2026-11-12, 3D session)"
in=$'NOTE: armed\nPR acme/3d-print-suite #4: stand\nCOMMENT acme/agent-brain https://x/pull/9 :: core\nERROR: a channel died\nFOUND: 1 new commit(s) - grandma3/LOG.md'
out=$(COLLAB_WATCH_SHOW='3d-print|3d-printing/' bash "$CW" --show-stdin <<<"$in")
grep -q "3d-print-suite #4" <<<"$out" && ok "a matching event passes" || bad "matching event dropped: $out"
grep -q "agent-brain" <<<"$out" && bad "a foreign event passed the filter" || ok "a foreign event is not told"
grep -q "^NOTE: armed" <<<"$out" && grep -q "^ERROR: a channel died" <<<"$out" && ok "NOTE and ERROR lines always pass" || bad "NOTE/ERROR dropped: $out"
[[ "$(COLLAB_WATCH_SHOW= bash "$CW" --show-stdin <<<"$in")" == "$in" ]] && ok "no filter: every line passes" || bad "empty filter changed the stream"
sleep 300 & FAKE=$!
echo "$FAKE" > "$T/state/collab-watch.pid"
COLLAB_WATCH_SHOW='3d-print' bash "$CW" > "$T/out5" 2>&1 & RUN=$!
wait_for "$T/out5" "following its events" 50 || true
echo "COMMENT acme/agent-brain https://x/pull/9 :: a core comment" >> "$T/state/events.log"
echo "PR acme/3d-print-suite #5: a 3d PR" >> "$T/state/events.log"
wait_for "$T/out5" "a 3d PR" 50 && ok "the follower tells its topic" || bad "topic event not relayed: $(cat "$T/out5")"
grep -q "a core comment" "$T/out5" && bad "the follower told a foreign event" || ok "the follower drops a foreign event"
grep -q "a core comment" "$T/state/events.log" && ok "the log still holds the foreign event for other sessions" || bad "log lost a line"
kill "$RUN" 2>/dev/null; wait "$RUN" 2>/dev/null; RUN=""
kill "$FAKE" 2>/dev/null; wait "$FAKE" 2>/dev/null; FAKE=""

echo
echo "$((checks - fails))/$checks passed"
[[ $fails -eq 0 ]]
