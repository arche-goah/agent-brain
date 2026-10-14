#!/usr/bin/env bash
# Fixture: a shared-memory-watch.sh cursor belongs to ONE repo.
#
# Measured 2026-10-14 (Windows instance): the watcher pointed at a project repo through
# SHARED_MEMORY_REPO, without SHARED_MEMORY_STATE, used the shared memory's default cursor.
# Three properties, each against a sandbox (two bare remotes + checkouts, no network):
#   1. FOREIGN AT ARM: a cursor that is no commit of the watched repo -> ERROR, exit != 0,
#      cursor file untouched
#   2. FOREIGN LATER: a second writer swaps in a foreign sha while the watcher runs -> ERROR,
#      cursor file keeps the foreign sha (not overwritten)
#   3. OWN CURSOR (negative control): a cursor of the watched repo -> watcher runs and
#      reports a foreign commit as before
#
# Usage: shared-memory-watch-cursor-test.sh [path-to-watch.sh]   (exit 0 = all pass)
# Run it against the unpatched watcher to see 1 and 2 fail.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
WATCH="${1:-$HERE/shared-memory-watch.sh}"
TMP=$(mktemp -d)
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$TMP"' EXIT
fails=0
pass() { echo "OK   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }

mkrepo() { # $1 = name -> bare $TMP/$1.git, checkout $TMP/$1
  git -c init.defaultBranch=main init -q --bare "$TMP/$1.git"
  git -c init.defaultBranch=main init -q "$TMP/$1"
  git -C "$TMP/$1" config core.autocrlf false
  git -C "$TMP/$1" config user.email me@local
  git -C "$TMP/$1" config user.name Me
  git -C "$TMP/$1" remote add origin "$TMP/$1.git"
  mkdir -p "$TMP/$1/domain"; printf '%s\n' "$1" > "$TMP/$1/domain/a.md"
  git -C "$TMP/$1" add -A; git -C "$TMP/$1" commit -qm "first $1"
  git -C "$TMP/$1" push -q -u origin main
}
mkrepo shared
mkrepo project
SHARED_SHA=$(git -C "$TMP/shared" rev-parse HEAD)
PROJECT_SHA=$(git -C "$TMP/project" rev-parse HEAD)
[[ -n "$SHARED_SHA" && -n "$PROJECT_SHA" ]] || { echo "SETUP FAILED: sandbox repos"; exit 1; }

cursor() { printf '{\n  "lastSeenSha": "%s",\n  "lastCheckedAt": "x"\n}\n' "$1" > "$2"; }
sha_in() { grep -o '"lastSeenSha" *: *"[^"]*"' "$1" | sed -E 's/.*"([^"]*)"$/\1/'; }
export SHARED_MEMORY_REPO="$TMP/project" WATCH_CLAIM_GRACE=0 SHARED_MEMORY_WATCH_TICK=1

# 1. FOREIGN AT ARM
STATE="$TMP/state1.json"; cursor "$SHARED_SHA" "$STATE"
OUT=$(SHARED_MEMORY_STATE="$STATE" SHARED_MEMORY_LOCK_DIR="$TMP/lock1" timeout 20 bash "$WATCH" watch 1 2>&1); rc=$?
if [[ $rc -ne 0 && $rc -ne 124 ]] && grep -q 'is no commit of' <<<"$OUT"; then pass "foreign cursor at arm is refused"
else fail "foreign cursor at arm (rc=$rc): ${OUT:0:200}"; fi
[[ "$(sha_in "$STATE")" == "$SHARED_SHA" ]] && pass "foreign cursor at arm left untouched" \
  || fail "foreign cursor at arm was overwritten with $(sha_in "$STATE")"

# 2. FOREIGN LATER
STATE="$TMP/state2.json"; cursor "$PROJECT_SHA" "$STATE"
OUT2="$TMP/out2.txt"
SHARED_MEMORY_STATE="$STATE" SHARED_MEMORY_LOCK_DIR="$TMP/lock2" timeout 30 bash "$WATCH" watch 1 > "$OUT2" 2>&1 &
W2=$!
sleep 3
cursor "$SHARED_SHA" "$STATE"
i=0; while kill -0 "$W2" 2>/dev/null && [[ $i -lt 20 ]]; do sleep 1; i=$((i + 1)); done
if grep -q 'is no commit of' "$OUT2"; then pass "foreign cursor swapped in later is refused"
else fail "foreign cursor swapped in later: $(head -c 200 "$OUT2")"; fi
[[ "$(sha_in "$STATE")" == "$SHARED_SHA" ]] && pass "swapped-in foreign cursor not overwritten" \
  || fail "swapped-in foreign cursor overwritten with $(sha_in "$STATE")"
kill "$W2" 2>/dev/null

# 3. OWN CURSOR (negative control): the watcher still runs and reports
STATE="$TMP/state3.json"; cursor "$PROJECT_SHA" "$STATE"
OUT3="$TMP/out3.txt"
SHARED_MEMORY_STATE="$STATE" SHARED_MEMORY_LOCK_DIR="$TMP/lock3" timeout 40 bash "$WATCH" watch 1 > "$OUT3" 2>&1 &
W3=$!
sleep 3
git clone -q "$TMP/project.git" "$TMP/other"
git -C "$TMP/other" config user.email c@local; git -C "$TMP/other" config user.name C
git -C "$TMP/other" config core.autocrlf false
printf -- '---\nname: b\nmetadata:\n  von: kim-win\n---\n\nnew\n' > "$TMP/other/domain/b.md"
git -C "$TMP/other" add -A; git -C "$TMP/other" commit -qm "colleague"; git -C "$TMP/other" push -q origin main
i=0; while ! grep -q '^FOUND:' "$OUT3" && [[ $i -lt 30 ]]; do sleep 1; i=$((i + 1)); done
grep -q '^FOUND:' "$OUT3" && pass "own cursor: watcher runs and reports" \
  || fail "own cursor: no FOUND line: $(head -c 200 "$OUT3")"
grep -q 'is no commit of' "$OUT3" && fail "own cursor wrongly refused" || pass "own cursor not refused"
kill "$W3" 2>/dev/null

echo
[[ $fails -eq 0 ]] && echo "shared-memory-watch-cursor-test: all passed" || echo "shared-memory-watch-cursor-test: $fails FAILED"
exit $fails
