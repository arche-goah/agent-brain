#!/usr/bin/env bash
# Fixture for helpers/git-hooks/prepare-commit-msg: a shared-memory commit (repo with parties.json)
# gets Device-State (and, for a suite topic, Suite-State) trailers; any other repo is left alone; a
# merge message is left alone; a message that already carries the trailer is not stamped twice.
# Sandbox only. The hook is called directly (as git would), with paths as ARGUMENTS (OS-3 safe).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../helpers/git-hooks/prepare-commit-msg"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FAIL=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAIL=1; }
# GIT_CONFIG_GLOBAL is a path handed to the native git as DATA in an env var: native() (OS-3).
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
export GIT_CONFIG_GLOBAL="$(native "$TMP/gitconfig")" GIT_CONFIG_NOSYSTEM=1
printf '[user]\n\tname = t\n\temail = t@example.invalid\n[init]\n\tdefaultBranch = main\n' > "$GIT_CONFIG_GLOBAL"

# A brain whose core/ sits on a tag, and its settings naming this device.
B="$TMP/brain"; mkdir -p "$B/core" "$B/.claude"
git -C "$B/core" init -q
echo x > "$B/core/f"; git -C "$B/core" add -A; git -C "$B/core" commit -qm c; git -C "$B/core" tag v9.9.9
printf '{"env":{"SHARED_MEMORY_SELF":"kim-box,kim"}}\n' > "$B/.claude/settings.json"
printf '{"repos":{"widget-suite":{"kind":"suite","version":"v0.4.0","commit":"abcdef1234567"}}}\n' > "$TMP/eco.json"
mkdir -p "$B/config"; cp "$TMP/eco.json" "$B/config/ecosystem.json"

S="$TMP/shared"; mkdir -p "$S/widget"; git -C "$S" init -q
printf '{"people":{"kim":{"devices":{"kim-box":{"os":"linux"}}}}}\n' > "$S/parties.json"
echo note > "$S/widget/note.md"; git -C "$S" add -A

stamp() { # $1 repo  $2 message file  [$3 source]
  # The host's SHARED_MEMORY_SELF must not leak in (it outranks the sandbox brain's settings).
  ( cd "$1" && env -u SHARED_MEMORY_SELF -u SHARED_MEMORY_REPO CLAUDE_PROJECT_DIR="$B" CLAUDE_CONFIG_DIR="$TMP/cfg" \
      bash "$HOOK" "$2" ${3:-} )
}

printf 'widget: a note\n' > "$TMP/m1"; stamp "$S" "$TMP/m1"
grep -q '^Device-State: device=kim-box os=linux core=v9.9.9@' "$TMP/m1" && pass "a shared-memory commit gets Device-State" \
  || fail "Device-State missing: $(cat "$TMP/m1")"
grep -q '^Suite-State: widget-suite=v0.4.0@abcdef1' "$TMP/m1" && pass "a suite topic adds that suite's state" \
  || fail "Suite-State missing: $(cat "$TMP/m1")"

stamp "$S" "$TMP/m1"
[ "$(grep -c '^Device-State:' "$TMP/m1")" = 1 ] && pass "an already stamped message is not stamped twice" || fail "stamped twice"

printf 'Merge branch x\n' > "$TMP/m2"; stamp "$S" "$TMP/m2" merge
grep -q 'Device-State' "$TMP/m2" && fail "a merge message was stamped" || pass "a merge message is left alone"

# NEGATIVE CONTROL: a repo without parties.json is not a shared memory and gets nothing.
O="$TMP/other"; mkdir -p "$O"; git -C "$O" init -q; echo y > "$O/y"; git -C "$O" add -A
printf 'other: change\n' > "$TMP/m3"; stamp "$O" "$TMP/m3"
grep -q 'Device-State' "$TMP/m3" && fail "a non-shared repo was stamped" || pass "control: any other repo is left alone"

exit $FAIL
