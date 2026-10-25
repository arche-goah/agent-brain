#!/usr/bin/env bash
# covers: shared_channels open-items shared-memory-check collab-watch shared-memory-watch
# Fixture for N shared-memory channels (operator decision 2026-10-24) — both directions, sandbox
# repos only (bare remotes + clones), no network.
#
# Why: the start report and the live watch knew exactly ONE shared-memory repo. A private device
# channel worked with every tool through --repo, but nothing read it at session start, and a
# second shared-memory line in collab-watch shared the one cursor file (and the one lock), so it
# was refused or skipped. Proven here:
#   - no channel file, and an empty list, leave every output exactly as before;
#   - two channels: each is read (its own requests, its own commit count), each line names its
#     channel, each keeps its own cursor; a channel whose members exclude this device is neither
#     read nor watched; a missing clone and a broken file are loud, never "nothing open";
#   - collab-watch arms BOTH shared-memory channels at once, each with its own cursor and lock,
#     and a find in the further channel carries its label.
# Exit 0 = all pass.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY=python3
"$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
T="$(mktemp -d)"
ARM=""
cleanup() { [[ -n "$ARM" ]] && kill "$ARM" 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT
fails=0; checks=0
ok()  { checks=$((checks + 1)); echo "  ok   $1"; }
bad() { checks=$((checks + 1)); fails=$((fails + 1)); echo "  FAIL $1 — $2"; }
has()   { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "missing [$2] in: $3" ;; esac; }
hasnt() { case "$3" in *"$2"*) bad "$1" "unexpected [$2] in: $3" ;; *) ok "$1" ;; esac; }
# OS-3: python and node are native processes; a Git-Bash /tmp path handed to them as DATA (a JSON
# value, an environment variable) does not resolve on Windows.
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
git_q() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main -c core.autocrlf=false "$@" >/dev/null 2>&1; }
TODAY=$(date +%Y-%m-%d)

# A shared-memory repo: bare remote + this device's clone (+ one for "another device").
mkrepo() { # $1 name, [$2 parties.json]
  git_q init -q --bare "$T/$1.git"
  git_q clone -q "$T/$1.git" "$T/$1"
  mkdir -p "$T/$1/core"; printf '# Log\n' > "$T/$1/core/LOG.md"
  [[ -n "${2:-}" ]] && printf '%s\n' "$2" > "$T/$1/parties.json"
  push "$1" seed
}
push() { git_q -C "$T/$1" add -A; git_q -C "$T/$1" commit -qm "$2"; git_q -C "$T/$1" push -q origin HEAD:main; git_q -C "$T/$1" fetch -q origin; }
request() { # $1 repo dir, $2 area/file, $3 von, $4 audience, $5 description
  printf -- '---\nname: %s\ndescription: "%s"\nmetadata:\n  type: project\n  von: %s\n  audience: %s\n  topic: core\n  date: %s\n  status: open\n  next: %s\n---\n\nbody\n' \
    "$(basename "$2" .md)" "$5" "$3" "$4" "$TODAY" "$4" > "$1/$2"
}
OP='{"people": {"op": {"github": "op", "devices": {"op-win": {"os": "windows"}, "op-mac": {"os": "macos"}}}}}'
KIM='{"people": {"kim": {"github": "kim", "devices": {"kim-win": {"os": "windows"}}}}}'
mkrepo shared
mkrepo devices "$OP"
mkrepo crew "$KIM"
request "$T/shared" core/request-shared-one-"$TODAY".md peer-mac op-win "SHARED-ONE asks this device"
push shared req
request "$T/devices" core/request-devices-one-"$TODAY".md op-mac op-win "DEVICES-ONE asks this device"
printf '\n## %s · op-mac — AN op-win: LOGDEV please check the bridge\n\nno file\n' "$TODAY" >> "$T/devices/core/LOG.md"
push devices req
request "$T/crew" core/request-crew-one-"$TODAY".md kim-win op-win "CREW-ONE in a channel this device is not in"
push crew req

INST="$T/inst"; mkdir -p "$INST/.claude/rules"
CH="$INST/.claude/rules/shared-memory-channels.json"
two='{"channels": [
  {"label": "devices", "repo": "'"$(native "$T/devices")"'", "members": ["person:op"]},
  {"label": "crew", "repo": "'"$(native "$T/crew")"'", "members": ["kim-win"]}]}'
export SHARED_MEMORY_SELF=op-win SHARED_MEMORY_REPO; SHARED_MEMORY_REPO="$(native "$T/shared")"

echo "the channel list (scripts/shared_channels.py)"
further() { SHARED_MEMORY_CHANNELS_CONFIG="$(native "$1")" "$PY" "$HERE/shared_channels.py" further 2>&1; }
printf '%s\n' "$two" > "$CH"
out=$(further "$CH"); rc=$?
[[ $rc -eq 0 ]] && ok "two channels: read (rc 0)" || bad "two channels: rc" "$rc: $out"
has   "a member channel is listed with its clone" "devices	$(native "$T/devices")" "$out"
hasnt "a channel whose members exclude this device is not" "crew" "$out"
out=$(SHARED_MEMORY_SELF= further "$CH")
has   "no SELF: membership cannot be told, the channel is read (loud side)" "crew" "$out"
out=$(further "$T/none.json")
[[ -z "$out" ]] && ok "no file: no further channel" || bad "no file" "$out"
refuse() { # $1 name, $2 file content, $3 expected text
  printf '%s\n' "$2" > "$T/bad.json"; local o r; o=$(further "$T/bad.json"); r=$?
  [[ $r -eq 1 && "$o" == *"$3"* ]] && ok "refused: $1" || bad "refused: $1" "rc $r: $o"
}
refuse "a label used twice (one cursor for two channels)" '{"channels": [{"label": "a", "repo": "/x"}, {"label": "a", "repo": "/y"}]}' "used twice"
refuse "a template placeholder" '{"channels": [{"label": "a", "repo": "~/Projects/<repo>"}]}' "placeholder"
refuse "a label the open-items keys already use" '{"channels": [{"label": "start", "repo": "/x"}]}' "kebab-case"
refuse "the default shared memory listed again" '{"channels": [{"label": "a", "repo": "'"$(native "$T/shared")"'"}]}' "default shared memory"
refuse "broken JSON" '{"channels": [' "not valid JSON"

echo "open-items: every member channel read, ids labelled"
mkdir -p "$T/core/scripts"
for f in open-items.py instance_key.py project_dir.py shared_answers.py shared_channels.py \
         shared-memory-inbox.py shared-memory-index.py shared-memory-lint.py shared-memory-parties.py \
         ledger-reconcile.py; do
  cp "$HERE/$f" "$T/core/scripts/"
done
# No work ledgers registered on purpose — without the file open-items says "work ledgers NOT checked".
printf '%s\n' '{"ledgers": []}' > "$INST/.claude/rules/ledgers.json"
printf '%s\n' '{"data":{"viewer":{"login":"me"},"search":{"issueCount":0,"nodes":[]}}}' > "$T/noprs.json"
oi() { SHARED_MEMORY_CHANNELS_CONFIG="$(native "$1")" OPEN_ITEMS_PR_FIXTURE="$(native "$T/noprs.json")" \
         "$PY" "$(native "$T/core/scripts/open-items.py")" --owner me --repo "$(native "$T/shared")" \
         --root "$(native "$INST")" --hook-input '{}' "${@:2}" 2>&1; }
out=$(oi "$CH")
has   "header counts the items of both channels" "open for us: 3 —" "$out"
has   "default item keeps its plain id" "] $TODAY core/request-shared-one-$TODAY.md — peer-mac" "$out"
has   "further channel's file request carries its label" "] $TODAY devices:core/request-devices-one-$TODAY.md — op-mac" "$out"
has   "further channel's LOG request carries its label" "devices:core/LOG@$TODAY#1 — op-mac" "$out"
hasnt "a channel without this device is not read" "CREW-ONE" "$out"
hasnt "nothing reads as failed" "NOT checked" "$out"
out=$(oi "$CH" --classify "devices:core/LOG@$TODAY#1=ai:fixture")
has   "--classify takes a channel id" "classified: devices:core/LOG@$TODAY#1 = ai" "$out"
out=$(oi "$CH")
has   "and the class sticks to that item" "[request|ai] $TODAY devices:core/LOG@$TODAY#1" "$out"
base=$(oi "$T/none.json")
has   "no channel file: the default item alone" "open for us: 1 —" "$base"
empty=$(printf '{"channels": []}\n' > "$T/empty.json"; oi "$T/empty.json")
[[ "$base" == "$empty" ]] && ok "an empty list prints exactly what no file prints" || bad "empty list differs" "$empty"
printf '%s\n' '{"channels": [{"label": "devices", "repo": "'"$(native "$T/nowhere")"'"}]}' > "$T/gone.json"
out=$(oi "$T/gone.json")
has   "a listed channel without a clone is NOT checked, not nothing" "shared-memory requests [devices] NOT checked" "$out"
has   "and the default channel is still read" "core/request-shared-one-$TODAY.md" "$out"
printf '{"channels": [\n' > "$T/broken.json"
out=$(oi "$T/broken.json")
has   "a broken channel file is NOT checked" "shared-memory channels (broken.json is not valid JSON" "$out"
has   "  ... and the default channel is still read" "core/request-shared-one-$TODAY.md" "$out"
hasnt "  ... and never says nothing open" "- nothing open" "$out"

echo "session-start check: one run per channel, own cursor, labelled lines"
CHECK="$HERE/../helpers/shared-memory-check.sh"
chk() { CLAUDE_PROJECT_DIR="$(native "$INST")" SHARED_MEMORY_CHANNELS_CONFIG="$(native "$1")" bash "$CHECK" 2>&1; }
out=$(chk "$CH")
[[ -z "$out" ]] && ok "first start: every channel sets its baseline silently" || bad "first start not silent" "$out"
sha_of() { grep -o '"lastSeenSha" *: *"[^"]*"' "$1" 2>/dev/null | sed -E 's/.*"([^"]*)"$/\1/'; }
[[ "$(sha_of "$INST/.claude-state/shared-memory-state.json")" == "$(git -C "$T/shared" rev-parse origin/main)" ]] \
  && ok "default cursor: the default repo's head, old file name" || bad "default cursor" "$(cat "$INST/.claude-state/shared-memory-state.json" 2>&1)"
[[ "$(sha_of "$INST/.claude-state/shared-memory-state-devices.json")" == "$(git -C "$T/devices" rev-parse origin/main)" ]] \
  && ok "devices cursor: its own file, its own repo's head" || bad "devices cursor" "$(cat "$INST/.claude-state/shared-memory-state-devices.json" 2>&1)"
[[ ! -e "$INST/.claude-state/shared-memory-state-crew.json" ]] && ok "no cursor for a channel this device is not in" || bad "crew cursor" "written"
# Another device posts into the device channel.
git_q clone -q "$T/devices.git" "$T/devices-other"
request "$T/devices-other" core/request-devices-two-"$TODAY".md op-mac op-win "DEVICES-TWO arrived since the last start"
push devices-other other
out=$(chk "$CH")
has   "default channel line unchanged" "shared-memory: nothing new since last start" "$out"
has   "further channel names itself and counts its own commit" "shared-memory [devices]: 1 new commit since last start — core/request-devices-two-$TODAY.md" "$out"
has   "its inbox line is labelled" "shared-memory [devices] inbox (for this instance)" "$out"
has   "its open requests are labelled (hand run)" "shared-memory [devices] open requests to this instance: 3" "$out"
hasnt "the channel without this device stays silent" "[crew]" "$out"
out=$(chk "$T/none.json")
[[ "$out" == "shared-memory: nothing new since last start (about commits only — open points are listed separately, new or not)"* ]] \
  && ok "no channel file: exactly the old output" || bad "no channel file" "$out"
hasnt "  ... with no channel line" "[devices]" "$out"
out=$(chk "$T/gone.json")
has   "a listed channel without a clone is loud" "!! shared-memory [devices]: NOT checked — no clone at" "$out"
out=$(chk "$T/broken.json")
has   "a broken channel file is one NOT-checked line" "shared-memory channels: NOT checked - " "$out"
has   "  ... after the default channel's own line" "shared-memory: nothing new since last start" "$out"

echo "collab-watch: both shared-memory channels armed, own cursor and lock each"
printf '%s\n' '{"shared_memory": {"repo": "'"$(native "$T/shared")"'", "interval": 30}}' > "$INST/.claude/rules/collab-watch.json"
export CLAUDE_PROJECT_DIR COLLAB_WATCH_CONFIG SHARED_MEMORY_CHANNELS_CONFIG COLLAB_WATCH_STATE="$T/cw"
CLAUDE_PROJECT_DIR="$(native "$INST")"
COLLAB_WATCH_CONFIG="$(native "$INST/.claude/rules/collab-watch.json")"
SHARED_MEMORY_CHANNELS_CONFIG="$(native "$CH")"
plan=$(bash "$HERE/collab-watch.sh" --dry-run 2>&1 | tr -d '\r')
has   "plan: the default shared memory as before" "SM 30 $(native "$T/shared")" "$plan"
has   "plan: the further channel, cadence inherited" "CHANNEL devices 30 $(native "$T/devices")" "$plan"
has   "plan: the channel without this device is named, not armed" "SKIP crew this instance is not among its members" "$plan"
plan=$(SHARED_MEMORY_CHANNELS_CONFIG="$(native "$T/broken.json")" bash "$HERE/collab-watch.sh" --dry-run 2>&1 | tr -d '\r')
has   "plan: a broken channel file keeps the default watch" "SM 30 $(native "$T/shared")" "$plan"
has   "  ... and names why no further channel is watched" "CHANNEL_ERROR broken.json is not valid JSON" "$plan"
printf '%s\n' '{"channels": [{"label": "devices", "repo": "'"$(native "$T/devices")"'", "interval": 5}]}' > "$T/slow.json"
plan=$(SHARED_MEMORY_CHANNELS_CONFIG="$(native "$T/slow.json")" bash "$HERE/collab-watch.sh" --dry-run 2>&1 | tr -d '\r')
has   "plan: a channel with a bad interval is skipped with the reason" "SKIP devices channel devices: interval must be" "$plan"
has   "  ... and the default watch still plans" "SM 30 $(native "$T/shared")" "$plan"
# Cursors seeded before arming: default at its head, devices one commit back, so the first poll
# of the device channel has exactly one find and the default channel none.
mkdir -p "$T/cw"
printf '{\n  "lastSeenSha": "%s",\n  "lastCheckedAt": "seeded"\n}\n' "$(git -C "$T/shared" rev-parse origin/main)" > "$T/cw/shared-memory-cursor.json"
printf '{\n  "lastSeenSha": "%s",\n  "lastCheckedAt": "seeded"\n}\n' "$(git -C "$T/devices" rev-parse 'origin/main~1')" > "$T/cw/shared-memory-cursor-devices.json"
bash "$HERE/collab-watch.sh" > "$T/arm.out" 2>&1 &
ARM=$!
p1="" p2=""
DEV_HEAD=$(git -C "$T/devices-other" rev-parse HEAD)
for _ in $(seq 1 120); do   # the cursor is written after the find is printed: wait for both
  p1=$(cat "$T/cw/shared-memory-watch.pid" 2>/dev/null); p2=$(cat "$T/cw/shared-memory-devices/shared-memory-watch.pid" 2>/dev/null)
  [[ -n "$p1" && -n "$p2" && "$(sha_of "$T/cw/shared-memory-cursor-devices.json")" == "$DEV_HEAD" ]] \
    && grep -q 'FOUND: \[devices\]' "$T/arm.out" 2>/dev/null && break
  sleep 0.5
done
arm=$(tr -d '\r' < "$T/arm.out")
[[ -n "$p1" ]] && kill -0 "$p1" 2>/dev/null && ok "default channel watcher alive, lock in the state dir" || bad "default watcher" "$arm"
[[ -n "$p2" ]] && kill -0 "$p2" 2>/dev/null && ok "device channel watcher alive, lock in its own dir" || bad "device watcher" "$arm"
[[ "$p1" != "$p2" ]] && ok "two watchers, two locks" || bad "one lock for both" "$p1"
has   "the armed line names both channels" "shared-memory 30s;shared-memory [devices] 30s" "$arm"
has   "the armed watch names the channel it does not watch" "NOTE: shared-memory [crew] not watched — this instance is not among its members" "$arm"
has   "the further channel's find carries its label" "FOUND: [devices] 1 new commit(s) from op-mac" "$arm"
hasnt "the default channel had nothing to find" "FOUND: 1" "$arm"
hasnt "no channel refused a foreign cursor" "belongs to another repo" "$arm"
hasnt "no watcher skipped as a duplicate" "already armed" "$arm"
[[ "$(sha_of "$T/cw/shared-memory-cursor-devices.json")" == "$DEV_HEAD" ]] \
  && ok "device cursor advanced to the device repo's head" || bad "device cursor" "$(cat "$T/cw/shared-memory-cursor-devices.json")"
[[ "$(sha_of "$T/cw/shared-memory-cursor.json")" == "$(git -C "$T/shared" rev-parse origin/main)" ]] \
  && ok "default cursor untouched by the other channel" || bad "default cursor" "$(cat "$T/cw/shared-memory-cursor.json")"
[[ ! -e "$T/cw/shared-memory-crew" ]] && ok "nothing armed for the channel without this device" || bad "crew armed" "dir exists"
kill "$ARM" 2>/dev/null
gone=0
for _ in $(seq 1 24); do
  if ! kill -0 "$ARM" 2>/dev/null && ! kill -0 "$p1" 2>/dev/null && ! kill -0 "$p2" 2>/dev/null; then gone=1; break; fi
  sleep 0.5
done
[[ $gone -eq 1 ]] && ok "TERM tears down both channels" || { bad "teardown" "still alive"; kill -9 "$ARM" "$p1" "$p2" 2>/dev/null; }
ARM=""

echo
if [[ $fails -eq 0 ]]; then echo "test-shared-memory-channels: all $checks checks passed"; exit 0; fi
echo "test-shared-memory-channels: $fails of $checks checks FAILED"; exit 1
