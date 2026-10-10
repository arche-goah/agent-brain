#!/usr/bin/env bash
# Fixture for the RANGE inbox of shared-memory-inbox.py: upkeep is not an arrival.
# covers: scripts/shared-memory-inbox.py
#
# Why (measured 2026-10-10 on a shared-memory repo with several parties): a tidy-up moved
# 23 old entries into topic areas, lint commits added frontmatter fields to old entries,
# and the watcher reported the touched OLD entries (dated September) as new arrivals from
# other parties — four times in one day. Both directions are checked:
#   silent:  a moved entry, a frontmatter-only edit, a pointer rewrite to a moved file —
#            also with `diff.renames=false` in the git config (the reader must not depend
#            on a user's default);
#   reports: a new file, and a body edit to an existing request.
# NEGATIVE CONTROL: pass the path of an unpatched inbox as $1 — the silent checks must FAIL
# there. Built in: the planted upkeep IS visible to the old reading (`--diff-filter=AM`
# without rename detection), so a silent pass cannot come from a range that missed them.
#
# Sandbox only (bash, git, mktemp, python). Exit 0 = all pass.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
INBOX="${1:-$HERE/shared-memory-inbox.py}"
PY=python3
"$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FAIL=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAIL=1; }

W="$TMP/work"
git -c init.defaultBranch=main init -q "$W"
git -C "$W" config core.autocrlf false
git -C "$W" config user.email me@local
git -C "$W" config user.name Me
mkdir -p "$W/ops" "$W/core"

entry() { # file von description body [extra frontmatter line]
  local extra=""
  [[ -n "${5:-}" ]] && extra="  $5
"
  printf -- '---\nname: %s\ndescription: "%s"\nmetadata:\n  type: project\n  von: %s\n  audience: alle\n  topic: %s\n  date: 2026-09-01\n%s---\n\n%s\n' \
    "$(basename "$1" .md)" "$3" "$2" "$(dirname "$1")" "$extra" "$4" > "$W/$1"
}
entry ops/moved-entry.md sam-laptop "MOVED-ONE an old entry" "Long text of an old entry that will move."
entry ops/old-note.md kim-win "FMONLY-ONE an old note" "A note body that stays as it is."
entry core/pointer-holder.md kim-win "POINTER-ONE names a moved file" "Context: \`ops/moved-entry.md\` holds the details."
entry ops/request-old.md sam-laptop "BODYEDIT-ONE an older request" "Please check X."
entry ops/desc-change.md kim-win "DESCOLD the first summary" "Body stays."
printf 'Old entry without frontmatter.\n' > "$W/ops/no-frontmatter.md"
git -C "$W" add -A
git -C "$W" commit -qm seed
A=$(git -C "$W" rev-parse HEAD)

# The range under test: four kinds of upkeep plus two real arrivals.
mkdir -p "$W/proj"
git -C "$W" mv ops/moved-entry.md proj/moved-entry.md
sed 's/^  topic: ops$/  topic: proj/' "$W/proj/moved-entry.md" > "$TMP/m" && cat "$TMP/m" > "$W/proj/moved-entry.md"
entry ops/old-note.md kim-win "FMONLY-ONE an old note" "A note body that stays as it is." "status: info"
entry core/pointer-holder.md kim-win "POINTER-ONE names a moved file" "Context: \`proj/moved-entry.md\` holds the details."
entry ops/request-old.md sam-laptop "BODYEDIT-ONE an older request" "Please check X.

Addendum: one more thing to check."
entry ops/new-entry.md kim-win "NEW-ONE arrived in this range" "Fresh content."
# The description is the entry's main information: a CHANGED one is content. A FIRST one,
# given to a file that had no frontmatter (what a lint pass does), is upkeep.
entry ops/desc-change.md kim-win "DESCNEW-ONE the revised summary" "Body stays."
entry ops/no-frontmatter.md kim-win "FIRSTFM-ONE frontmatter added by a lint pass" "Old entry without frontmatter."
git -C "$W" add -A
git -C "$W" commit -qm range
B=$(git -C "$W" rev-parse HEAD)

# Built-in control: the planted upkeep is visible to the OLD reading.
OLD=$(git -C "$W" -c diff.renames=false diff --name-status --diff-filter=AM "$A" "$B")
for f in proj/moved-entry.md ops/old-note.md core/pointer-holder.md ops/no-frontmatter.md; do
  grep -q "$f" <<<"$OLD" && pass "control: $f is in the old A/M reading" \
    || fail "control: $f not planted — a silent pass below would prove nothing"
done

check_run() { # label output
  local out="$2"
  grep -q 'NEW-ONE' <<<"$out" && pass "$1: a new file is reported" || fail "$1: new file missing: $out"
  grep -q 'BODYEDIT-ONE' <<<"$out" && pass "$1: a body edit to a request is reported" \
    || fail "$1: body edit missing: $out"
  grep -q 'MOVED-ONE' <<<"$out" && fail "$1: a moved entry reported as new" || pass "$1: moved entry silent"
  grep -q 'FMONLY-ONE' <<<"$out" && fail "$1: frontmatter-only edit reported" || pass "$1: frontmatter-only edit silent"
  grep -q 'POINTER-ONE' <<<"$out" && fail "$1: pointer rewrite reported" || pass "$1: pointer rewrite silent"
  grep -q 'DESCNEW-ONE' <<<"$out" && pass "$1: a changed description is reported" \
    || fail "$1: changed description missing: $out"
  grep -q 'FIRSTFM-ONE' <<<"$out" && fail "$1: first frontmatter on an old file reported" \
    || pass "$1: first frontmatter on an old file silent"
}

check_run "default config" "$("$PY" "$INBOX" --repo "$W" --from "$A" --to "$B" --self '' --max 20 2>&1)"
check_run "diff.renames=false" "$(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=diff.renames GIT_CONFIG_VALUE_0=false \
  "$PY" "$INBOX" --repo "$W" --from "$A" --to "$B" --self '' --max 20 2>&1)"

# --senders feeds the watcher's FOUND line: sam-laptop sent the body edit, kim-win the new
# file. The moved entry (sam-laptop) and the maintained ones (kim-win) add nobody — checked by
# a range that holds ONLY upkeep.
git -C "$W" mv ops/old-note.md proj/old-note.md
entry ops/request-old.md sam-laptop "BODYEDIT-ONE an older request" "Please check X.

Addendum: one more thing to check." "status: answered"
git -C "$W" add -A
git -C "$W" commit -qm upkeep-only
C=$(git -C "$W" rev-parse HEAD)
S=$("$PY" "$INBOX" --repo "$W" --from "$B" --to "$C" --senders 2>&1)
[[ -z "$S" ]] && pass "an upkeep-only range names no sender" || fail "upkeep-only range named: $S"
U=$("$PY" "$INBOX" --repo "$W" --from "$B" --to "$C" --self '' 2>&1)
[[ -z "$U" ]] && pass "an upkeep-only range prints nothing" || fail "upkeep-only range printed: $U"

exit $FAIL
