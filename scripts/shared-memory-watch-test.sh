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

# Build the sandbox WITHOUT cloning an empty repository. The first version did, and it
# passed on the author's machine and failed on all three CI runners: the empty clone
# left a checkout whose first commit staged nothing, `branch -M main` then had no
# commit to rename, and the push died with "src refspec main does not match any" — a
# failure three steps downstream of its cause. init + remote + push is the same setup
# with no version- or config-dependent edge (`init.defaultBranch` differs per machine,
# which is why it is pinned here instead of assumed).
git -c init.defaultBranch=main init -q --bare "$BARE"
git -c init.defaultBranch=main init -q "$WORK"
# autocrlf is pinned off in the sandbox: with the Git-for-Windows default (true),
# every add/commit of the LF fixtures spams "LF will be replaced by CRLF" warnings
# into the test output — cosmetic, but noise a reader has to rule out by hand.
git -C "$WORK" config core.autocrlf false
git -C "$WORK" config user.email me@local
git -C "$WORK" config user.name Me
git -C "$WORK" remote add origin "$BARE"
mkdir -p "$WORK/domain"
printf 'one\n' > "$WORK/domain/a.md"
git -C "$WORK" add -A
git -C "$WORK" commit -qm "first"
git -C "$WORK" push -q -u origin main

# Preconditions, checked instead of assumed: everything below is meaningless if the
# sandbox did not come up, and "watcher reported nothing" would then be blamed on the
# watcher. This is the same class the watcher itself guards against.
if ! git -C "$WORK" rev-parse origin/main >/dev/null 2>&1; then
  echo "SETUP FAILED: no origin/main in the sandbox — this is a test-harness fault, not a watcher finding"
  git -C "$WORK" status --short --branch
  exit 1
fi

git clone -q "$BARE" "$OTHER"
git -C "$OTHER" config core.autocrlf false
git -C "$OTHER" config user.email colleague@local
git -C "$OTHER" config user.name Colleague
[ -d "$OTHER/domain" ] || { echo "SETUP FAILED: colleague checkout has no content"; exit 1; }

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
