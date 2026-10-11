#!/usr/bin/env bash
# Fixture for scripts/project-dir.sh: the state path must not depend on the caller's cwd.
# covers: scripts/project-dir.sh, scripts/shared-memory-watch.sh
#
# Why (measured 2026-10-11): a watcher armed from inside `core/` wrote its cursor into
# `core/.claude-state/`, found no cursor there and reset its baseline to the current head.
# Checked in three directions: env set wins; no env inside a submodule resolves to the
# SUPERPROJECT (not the submodule, not the cwd); no env in a plain repo resolves to its top.
# End to end: the real watcher, started from a foreign cwd with no env, must find the
# cursor that lives in the brain and must not create a state directory anywhere else.
# NEGATIVE CONTROL: pass a path to an old-style helper as $1 (one that answers `.`); every
# cwd-independence check must FAIL there.
#
# Sandbox only (bash, git, mktemp). Exit 0 = all pass.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HELPER="${1:-$HERE/project-dir.sh}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FAIL=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAIL=1; }

g() { git -c core.autocrlf=false -c init.defaultBranch=main -c user.email=t@local -c user.name=T -c protocol.file.allow=always "$@"; }

# A "core" repo with the script inside, mounted as submodule `core/` of a "brain".
CORE_SRC="$TMP/core-src"
g init -q "$CORE_SRC"
mkdir -p "$CORE_SRC/scripts"
cp "$HERE/shared-memory-watch.sh" "$HERE/shared-memory-inbox.py" "$CORE_SRC/scripts/" 2>/dev/null
cp "$HELPER" "$CORE_SRC/scripts/project-dir.sh"
g -C "$CORE_SRC" add -A && g -C "$CORE_SRC" commit -qm core

BRAIN="$TMP/brain"
g init -q "$BRAIN"
g -C "$BRAIN" submodule add -q "$CORE_SRC" core 2>/dev/null
g -C "$BRAIN" commit -qm brain 2>/dev/null
SUB="$BRAIN/core/scripts"

resolve() { # cwd env-value-or-empty helper-dir
  ( cd "$1" && if [[ -n "$2" ]]; then CLAUDE_PROJECT_DIR="$2"; export CLAUDE_PROJECT_DIR; else unset CLAUDE_PROJECT_DIR; fi
    . "$3/project-dir.sh"; resolve_project_dir "$3" )
}

R=$(resolve "$TMP" "/some/where" "$SUB")
[[ "$R" == "/some/where" ]] && pass "env set wins" || fail "env set did not win: $R"

R=$(resolve "$SUB" "" "$SUB")
[[ "$R" -ef "$BRAIN" ]] && pass "no env, cwd inside core/scripts -> the brain" \
  || fail "no env inside the submodule resolved to: $R (want $BRAIN)"

R=$(resolve "$TMP" "" "$SUB")
[[ "$R" -ef "$BRAIN" ]] && pass "no env, foreign cwd -> the brain, not the cwd" \
  || fail "no env from a foreign cwd resolved to: $R (want $BRAIN)"

PLAIN="$TMP/plain"
g init -q "$PLAIN"; mkdir -p "$PLAIN/scripts"; cp "$HELPER" "$PLAIN/scripts/project-dir.sh"
R=$(resolve "$TMP" "" "$PLAIN/scripts")
[[ "$R" -ef "$PLAIN" ]] && pass "no env in a plain repo -> its top" \
  || fail "plain repo resolved to: $R"

# End to end: the watcher from a foreign cwd, no env, with a cursor in the BRAIN.
REMOTE="$TMP/shared.git"; WORKC="$TMP/shared"
g init -q --bare "$REMOTE"
g clone -q "$REMOTE" "$WORKC" 2>/dev/null
echo a > "$WORKC/a.md"; g -C "$WORKC" add -A; g -C "$WORKC" commit -qm one; g -C "$WORKC" push -q origin HEAD:main 2>/dev/null
mkdir -p "$BRAIN/.claude-state"
SHA=$(g -C "$WORKC" rev-parse HEAD)
printf '{\n  "lastSeenSha": "%s"\n}\n' "$SHA" > "$BRAIN/.claude-state/shared-memory-state.json"
OUT=$( cd "$TMP" && unset CLAUDE_PROJECT_DIR; SHARED_MEMORY_REPO="$WORKC" WATCH_CLAIM_GRACE=1 \
       timeout 4 bash "$BRAIN/core/scripts/shared-memory-watch.sh" watch 1 2>&1 )
grep -q 'no cursor found' <<<"$OUT" && fail "watcher from a foreign cwd lost the brain's cursor: $OUT" \
  || pass "watcher from a foreign cwd keeps the brain's cursor"
[[ -d "$TMP/.claude-state" || -d "$BRAIN/core/.claude-state" ]] \
  && fail "a second state directory was created outside the brain" \
  || pass "no state directory outside the brain"

exit $FAIL
