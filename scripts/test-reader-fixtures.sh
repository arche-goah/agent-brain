#!/usr/bin/env bash
# Fixture for scripts/reader-fixtures.sh — which fixtures a change owes (core-push-lint.sh --fast and core-merge-lint.sh
# share the rule). One throwaway repo under a path with a space, one commit per case.
# Usage: bash scripts/test-reader-fixtures.sh   (exit 0 = all cases pass)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/scripts/reader-fixtures.sh"
. "$ROOT/scripts/git-sandbox.sh"   # the host's global hooksPath must not judge the probe commits
T="$(mktemp -d)"
# shellcheck disable=SC2064  # expand now: the paths are fixed
trap "rm -rf \"$T\"; ${GIT_CONFIG_GLOBAL:+rm -f \"$GIT_CONFIG_GLOBAL\"}" EXIT
R="$T/probe repo"
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
g() { git -C "$R" -c commit.gpgsign=false "$@" >/dev/null 2>&1; }

mkdir -p "$R/scripts" "$R/hooks"
g init -q
echo '{}' > "$R/hooks/hooks.json"
echo 'x' > "$R/scripts/gone.sh"
echo 'x' > "$R/scripts/old-name.py"
echo 'x' > "$R/hooks/my file.json"
echo 'x' > "$R/README.md"
echo 'x' > "$R/notes.MD"
echo 'cat hooks/hooks.json'     > "$R/scripts/test-hooks.sh"
echo 'bash scripts/gone.sh'     > "$R/scripts/test-gone.sh"
echo 'python3 old-name.py'      > "$R/scripts/old-reader-test.py"
echo 'cat "hooks/my file.json"' > "$R/scripts/test-space.cjs"
echo 'grep x README.md notes.MD' > "$R/scripts/test-docs.sh"
echo 'echo nothing'             > "$R/scripts/test-self.sh"
g add -A; g commit -qm base

# $1 name, $2 expected selection (space-separated, sorted)
check() {
  local got
  got="$(reader_fixtures "$R" HEAD~1 HEAD | tr '\n' ' ' | sed 's/ $//')"
  if [ "$got" = "$2" ]; then ok "$1"; else bad "$1: got '$got', want '$2'"; fi
}

echo '{"a":1}' > "$R/hooks/hooks.json"; g commit -qam c1
check changed-reader 'scripts/test-hooks.sh'
g rm -q scripts/gone.sh; g commit -qm c2
check deleted-file-pulls-reader 'scripts/test-gone.sh'
g mv scripts/old-name.py scripts/new-name.py; g commit -qm c3
check renamed-old-name-pulls-reader 'scripts/old-reader-test.py'
echo y > "$R/hooks/my file.json"; g commit -qam c4
check space-in-name 'scripts/test-space.cjs'
echo y > "$R/README.md"; echo y > "$R/notes.MD"; g commit -qam c5
check docs-any-case-pull-nothing ''
echo 'echo changed' > "$R/scripts/test-self.sh"; g commit -qam c6
check changed-fixture-runs-itself 'scripts/test-self.sh'
g rm -q scripts/test-self.sh; g commit -qm c7
check deleted-fixture-not-run ''

if [ "$fail" -eq 0 ]; then echo "reader-fixtures fixtures: ALL passed"; exit 0; fi
echo "reader-fixtures fixtures: FAILED"; exit 1
