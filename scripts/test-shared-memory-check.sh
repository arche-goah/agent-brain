#!/usr/bin/env bash
# Fixture for helpers/shared-memory-check.sh — its first. The level-1 read side of the
# cross-instance class: at session start, what did the others push, and (since
# 2026-09-13) what is NEW BY TOPIC since this instance last looked.
#
# Two directions per property: the freshness line must appear with a correct per-topic
# tally when dated entries landed after the last check, and must stay silent when the
# cursor is current — a bootup line that prints on a quiet repo trains the reader to
# skip it, which is the same failure as printing nothing.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/../helpers/shared-memory-check.sh"
fails=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1 — $2"; fails=$((fails + 1)); }
has()   { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "missing [$2] in: $3" ;; esac; }
hasnt() { case "$3" in *"$2"*) bad "$1" "unexpected [$2]" ;; *) ok "$1" ;; esac; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git_q() { git -c user.email=t@t -c user.name=t "$@" >/dev/null 2>&1; }

entry() { # entry <topic> <slug> <date>
  mkdir -p "$SHARED/$1"
  printf -- '---\nname: %s\ndescription: "d"\nmetadata:\n  type: reference\n  von: x\n  audience: y\n  topic: %s\n  date: %s\n---\n\nbody\n' \
    "$2" "$1" "$3" > "$SHARED/$1/$2.md"
}

# Shared repo with a remote (the check fetches origin/main), one old commit as the cursor.
SHARED="$TMP/shared"; REMOTE="$TMP/remote.git"; STATE="$TMP/state.json"
git_q init -q --bare "$REMOTE"
git_q -C "$TMP" clone -q "$REMOTE" shared
entry ops old 2026-08-01
git_q -C "$SHARED" add -A; git_q -C "$SHARED" commit -qm old; git_q -C "$SHARED" push -q -u origin HEAD:main
OLD_SHA=$(git -C "$SHARED" rev-parse HEAD)

# Two fresh entries in two topics, pushed after the cursor.
entry core fresh-a 2026-09-10
entry ops fresh-b 2026-09-11
git_q -C "$SHARED" add -A; git_q -C "$SHARED" commit -qm fresh; git_q -C "$SHARED" push -q origin HEAD:main

# The repo path reaches a NATIVE process: the check hands it to python as `--repo`. Git
# Bash's /tmp/... does not resolve for python.exe — it would read nothing and the
# freshness line would stay silent, which this fixture could not tell from "correctly
# silent". OS-3 in docs/os-traps.md: state the path natively via cygpath -m where it
# exists; git accepts the mixed form too, so one variable serves both consumers.
SHARED_NATIVE="$SHARED"
command -v cygpath >/dev/null 2>&1 && SHARED_NATIVE="$(cygpath -m "$SHARED")"
run_check() { SHARED_MEMORY_REPO="$SHARED_NATIVE" SHARED_MEMORY_STATE="$STATE" bash "$CHECK" 2>&1; }

echo "positive control: cursor behind, checked before the fresh entries"
printf '{\n  "lastSeenSha": "%s",\n  "lastCheckedAt": "2026-09-05T08:00:00Z"\n}\n' "$OLD_SHA" > "$STATE"
out="$(run_check)"
has "the commit line still comes first" "new commit" "$out"
has "the freshness line counts the dated entries" "2 entries dated since 2026-09-05" "$out"
has "and tallies core" "core 1" "$out"
has "and tallies ops" "ops 1" "$out"
has "and names the query for the list" "--since 2026-09-05" "$out"

echo "negative control 1: cursor current -> silence"
out="$(run_check)"   # the previous run advanced the cursor to HEAD
hasnt "no commit line" "new commit" "$out"
hasnt "no freshness line" "dated since" "$out"

echo "negative control 2: cursor behind, but nothing dated after the last check"
printf '{\n  "lastSeenSha": "%s",\n  "lastCheckedAt": "2026-09-12T08:00:00Z"\n}\n' "$OLD_SHA" > "$STATE"
out="$(run_check)"
has   "the commit line reports the moved repo" "new commit" "$out"
hasnt "but the freshness line stays silent — nothing dated since 09-12" "dated since" "$out"

echo "no state file yet: first run seeds silently"
rm -f "$STATE"
out="$(run_check)"
hasnt "no line on the seeding run" "shared-memory:" "$out"
[ -s "$STATE" ] && ok "cursor written" || bad "cursor written" "state file missing"

echo
if [ "$fails" -eq 0 ]; then echo "test-shared-memory-check: all checks passed"; exit 0; fi
echo "test-shared-memory-check: $fails check(s) FAILED"; exit 1
