#!/usr/bin/env bash
# Negative control for shared-memory-watch.sh — the proof that the FIND PATH fires.
#
# Why this file exists at all: a watcher that has never been seen to fire cannot be
# told apart from a broken one, because both are silent. Two properties are checked
# against a sandbox repo (bare remote + two checkouts, no network, no real data):
#   1. a foreign commit is reported at all
#   2. a SECOND foreign commit is still reported afterwards — the exit-on-find version
#      would already be dead here, while looking armed
#
# Runs on every OS the core supports (bash, git, mktemp only). Exit 0 = both pass.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
WATCH="$HERE/shared-memory-watch.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

BARE="$TMP/remote.git"
WORK="$TMP/work"      # "our" checkout — the one the watcher polls
OTHER="$TMP/other"    # somebody else's checkout

git init -q --bare "$BARE"
git clone -q "$BARE" "$WORK" 2>/dev/null   # "cloned an empty repository" is expected here
git -C "$WORK" config user.email me@local
git -C "$WORK" config user.name Me
mkdir -p "$WORK/domain"
echo one > "$WORK/domain/a.md"
git -C "$WORK" add -A
git -C "$WORK" commit -qm "first"
git -C "$WORK" branch -M main
git -C "$WORK" push -q origin main

git clone -q "$BARE" "$OTHER"
git -C "$OTHER" config user.email colleague@local
git -C "$OTHER" config user.name Colleague

STATE="$TMP/state.json"
printf '{\n  "lastSeenSha": "%s",\n  "lastCheckedAt": "x"\n}\n' \
  "$(git -C "$WORK" rev-parse HEAD)" > "$STATE"

export SHARED_MEMORY_REPO="$WORK" SHARED_MEMORY_STATE="$STATE" SHARED_MEMORY_LOCK_DIR="$TMP/lock"
OUT="$TMP/out.txt"
bash "$WATCH" watch 2 > "$OUT" 2>&1 &
WATCHER=$!
sleep 3

push_from_other() {   # $1 = file, $2 = message
  echo "$2" > "$OTHER/domain/$1"
  git -C "$OTHER" add -A
  git -C "$OTHER" commit -qm "$2"
  git -C "$OTHER" push -q origin main
}

push_from_other b.md "colleague one"
sleep 6
FIRST=$(grep -c '^FOUND:' "$OUT" || true)

push_from_other c.md "colleague two"
sleep 6
SECOND=$(grep -c '^FOUND:' "$OUT" || true)

# Braces + redirect: the shell prints its own "Terminated" job message on wait,
# which reads like a test failure in the log and is not one.
{ kill "$WATCHER"; wait "$WATCHER"; } 2>/dev/null || true

echo "--- watcher output ---"
cat "$OUT"
echo "--- verdict ---"
fail=0
if [[ "$FIRST" -ge 1 ]]; then echo "PASS: first foreign commit reported"
else echo "FAIL: first foreign commit NOT reported"; fail=1; fi
if [[ "$SECOND" -ge 2 ]]; then echo "PASS: watcher survived and reported the second"
else echo "FAIL: no second report — watcher died after the first find"; fail=1; fi
exit "$fail"
