#!/usr/bin/env bash
# Fixture for scripts/reader-break-check.py: a commit removing a phrase a ledger check or a memory home anchor reads.
# pre-commit: covers
# covers: reader-break-check
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
py=python3; "$py" -c 'import sys' >/dev/null 2>&1 || py=python
chk="$here/reader-break-check.py"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
# the repo path goes to python as data: native form on Windows (OS-3)
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
expect() {   # expect <want-rc> <label>
  "$py" "$(native "$chk")" --root "$(native "$tmp/r")" >/dev/null 2>&1; local rc=$?
  if [ "$rc" = "$1" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $2 (rc $rc, want $1)"; fi
  git -C "$tmp/r" reset -q --hard
}
git init -q "$tmp/r"
# its own commits run no hook: the global pre-commit would start again inside the temp repo (measured 2026-11-23)
git -C "$tmp/r" config core.hooksPath "$tmp/no-hooks"
git -C "$tmp/r" config user.email t@example.invalid
git -C "$tmp/r" config user.name t
mkdir -p "$tmp/r/docs" "$tmp/r/mem"
printf 'Cadence lives in the core.\nKeep this sentence.\n' > "$tmp/r/RULES.md"
printf -- '- [x] entry\n  check: grep -q "Cadence lives" RULES.md && grep -q "Keep this" RULES.md\n- [x] neg\n  check: ! grep -q "weekly scan" RULES.md\n' > "$tmp/r/docs/ledger.md"
printf -- '---\nname: x\n  home: RULES.md :: Keep this sentence\n---\n' > "$tmp/r/mem/x.md"
printf 'other\n' > "$tmp/r/OTHER.md"
git -C "$tmp/r" add -A && git -c core.hooksPath="$tmp/no-hooks" -C "$tmp/r" commit -qm init

# t1: removing a phrase a ledger check reads -> red
printf 'Keep this sentence.\n' > "$tmp/r/RULES.md"; git -C "$tmp/r" add RULES.md
expect 1 "t1 ledger-read phrase removed"
# t2: same commit rewrites the check -> green
printf 'Keep this sentence.\n' > "$tmp/r/RULES.md"
printf -- '- [x] entry\n  check: grep -q "Keep this" RULES.md\n- [x] neg\n  check: ! grep -q "weekly scan" RULES.md\n' > "$tmp/r/docs/ledger.md"
git -C "$tmp/r" add -A
expect 0 "t2 reader changed in the same commit"
# t3: home anchor phrase removed -> red
printf 'Cadence lives in the core.\n' > "$tmp/r/RULES.md"; git -C "$tmp/r" add RULES.md
expect 1 "t3 home-anchor phrase removed"
# t4: negated check's phrase never there / added-removed -> not a reader
printf 'Cadence lives in the core.\nKeep this sentence.\nweekly scan\n' > "$tmp/r/RULES.md"; git -C "$tmp/r" add RULES.md
git -c core.hooksPath="$tmp/no-hooks" -C "$tmp/r" commit -qm add-weekly
printf 'Cadence lives in the core.\nKeep this sentence.\n' > "$tmp/r/RULES.md"; git -C "$tmp/r" add RULES.md
expect 0 "t4 negated check's phrase removed"
# t5: unrelated file changed -> green
printf 'changed\n' > "$tmp/r/OTHER.md"; git -C "$tmp/r" add OTHER.md
expect 0 "t5 unrelated file"
# t6: read file deleted -> red
git -C "$tmp/r" rm -q RULES.md
expect 1 "t6 read file deleted"
# t7: rewording that keeps the phrase -> green
printf 'Cadence lives in the core, measured.\nKeep this sentence.\n' > "$tmp/r/RULES.md"; git -C "$tmp/r" add RULES.md
expect 0 "t7 phrase kept"
# t8: --history judges each commit with the readers of its own tree (2026-11-23: the tree stood before the pattern, the
# replay judged 4404 commits with no reader and found nothing)
printf 'Cadence lives in the core.\nKeep this sentence.\n' > "$tmp/r/RULES.md"; git -C "$tmp/r" add -A
git -c core.hooksPath="$tmp/no-hooks" -C "$tmp/r" commit -qm restore
printf 'Keep this sentence.\n' > "$tmp/r/RULES.md"; git -C "$tmp/r" add RULES.md; git -c core.hooksPath="$tmp/no-hooks" -C "$tmp/r" commit -qm cut
hist=$("$py" "$(native "$chk")" --root "$(native "$tmp/r")" --history 2000-01-01 2>&1)
case "$hist" in *"1 held"*) pass=$((pass + 1));; *) fail=$((fail + 1)); echo "FAIL: t8 history replay holds the cutting commit: $hist";; esac
echo "reader-break-check: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
