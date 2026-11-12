#!/usr/bin/env bash
# covers: pre-commit
# Fixture for the change-level step of helpers/git-hooks/pre-commit: a staged changelog fragment whose level field
# change-level.cjs refuses blocks the commit; a valid one and a commit without fragments pass. Measured 2026-11-03 on
# the macOS instance: six fragments with "higher: none" on reader/writer reached the lint before anything said so.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/../helpers/git-hooks/pre-commit"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0; checks=0
ok()  { checks=$((checks + 1)); echo "  ok   $1"; }
bad() { checks=$((checks + 1)); fails=$((fails + 1)); echo "  FAIL $1 — $2"; }
mkdir -p "$T/nohooks"
g() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main -c core.autocrlf=false -c core.hooksPath="$T/nohooks" "$@"; }
gq() { g "$@" >/dev/null 2>&1; }
hook() { (cd "$1" && bash "$HOOK" 2>&1); }

R="$T/repo"; mkdir -p "$R/helpers" "$R/changelog.d"
cp "$HERE/../helpers/change-level.cjs" "$R/helpers/change-level.cjs"
gq init -q "$R"; echo a > "$R/a.txt"; gq -C "$R" add -A; gq -C "$R" commit -qm seed

echo "change level in the pre-commit"
echo b > "$R/a.txt"; gq -C "$R" add -A
o=$(hook "$R"); [ $? -eq 0 ] && ok "a commit without a fragment passes" || bad "no fragment" "$o"
printf '%s\n' '- **x** (test: T1) (level: reader; higher: none; debt: none). Body.' > "$R/changelog.d/bad.md"; gq -C "$R" add -A
o=$(hook "$R"); [[ $? -ne 0 && "$o" == *"change-level"* && "$o" == *"higher: none on level reader"* ]] \
  && ok "higher: none on reader is refused, the reason named" || bad "bad fragment" "$o"
printf '%s\n' '- **x** (test: T1) (level: reader; higher: writer — not needed here; debt: none). Body.' > "$R/changelog.d/bad.md"; gq -C "$R" add -A
o=$(hook "$R"); [ $? -eq 0 ] && ok "a valid fragment passes" || bad "valid fragment" "$o"

# The English-only ratchet in the same hook (2026-11-03): a staged German line is refused at commit time.
mkdir -p "$R/scripts"; cp "$HERE/english-only.py" "$R/scripts/english-only.py"
: > "$R/scripts/english-legacy.txt"   # the sandbox has no legacy files; the real list would name files that are not here
gq -C "$R" add -A; gq -C "$R" commit -qm tool --no-verify
# The German sentence is decoded at run time, so this file itself stays English for the same ratchet.
de="$(printf '%s' 'RGllIFBydWVmdW5nIGxhZXVmdCB1ZWJlciBkZW4gS2VybiB1bmQgbWVsZGV0IGRpZSBXb2VydGVyLg==' | base64 --decode 2>/dev/null || printf '%s' 'RGllIFBydWVmdW5nIGxhZXVmdCB1ZWJlciBkZW4gS2VybiB1bmQgbWVsZGV0IGRpZSBXb2VydGVyLg==' | base64 -D)"
printf '%s\n' "- **x** (test: T1) (level: reader; higher: writer — not needed; debt: none). $de" > "$R/changelog.d/de.md"; gq -C "$R" add -A
o=$(hook "$R"); [[ $? -ne 0 && "$o" == *"english-only"* ]] && ok "a staged German line is refused by the English-only ratchet" || bad "German line" "$o"
rm "$R/changelog.d/de.md"; gq -C "$R" add -A
o=$(hook "$R"); [ $? -eq 0 ] && ok "  ... and passes once it is gone" || bad "after removal" "$o"

# The content guard in the same hook (2026-11-12): a literal invisible character in a staged file is refused at
# commit time, not first at the full lint. The character is written by printf, so this file holds none.
cp "$HERE/content-guard.py" "$R/scripts/content-guard.py"; gq -C "$R" add -A; gq -C "$R" commit -qm guard --no-verify
printf 'bom = "\xef\xbb\xbf"\n' > "$R/scripts/x.py"; gq -C "$R" add -A
o=$(hook "$R"); [[ $? -ne 0 && "$o" == *"content-guard"* ]] && ok "a staged invisible character is refused by the content guard" || bad "invisible char" "$o"
printf 'bom = chr(0xFEFF)\n' > "$R/scripts/x.py"; gq -C "$R" add -A
o=$(hook "$R"); [ $? -eq 0 ] && ok "  ... and passes written as a code point" || bad "code point" "$o"
# Windows review of #511: the guard reads what the commit carries (the index), not the working tree.
gq -C "$R" commit -qm cp --no-verify
printf 'junk = "\xef\xbb\xbf"\n' > "$R/scripts/untracked.py"; echo c > "$R/a.txt"; gq -C "$R" add a.txt
o=$(hook "$R"); [ $? -eq 0 ] && ok "an untracked file with an invisible character does not hold another commit" || bad "untracked held" "$o"
rm "$R/scripts/untracked.py"
printf 'bom = "\xef\xbb\xbf"\n' > "$R/scripts/y.py"; gq -C "$R" add scripts/y.py; printf 'bom = 1\n' > "$R/scripts/y.py"
o=$(hook "$R"); [[ $? -ne 0 && "$o" == *"content-guard"* ]] && ok "a staged blob cleaned only in the working tree is still refused" || bad "cleaned in tree passed" "$o"
gq -C "$R" reset -q -- scripts/y.py; rm -f "$R/scripts/y.py"
# The same for leak-scan (class of the finding above): the commit's blobs, not the tree. The home path is built at run
# time, so this file holds none.
cp "$HERE/leak-scan.py" "$R/scripts/leak-scan.py"; gq -C "$R" add -A; gq -C "$R" commit -qm ls --no-verify
hp="/Us""ers/someone/x"
printf 'p = "%s"\n' "$hp" > "$R/scripts/untracked2.py"; echo d > "$R/a.txt"; gq -C "$R" add a.txt
o=$(hook "$R"); [ $? -eq 0 ] && ok "an untracked file with a home path does not hold another commit" || bad "leak-scan untracked held" "$o"
rm "$R/scripts/untracked2.py"
printf 'p = "%s"\n' "$hp" > "$R/scripts/z.py"; gq -C "$R" add scripts/z.py; printf 'p = 1\n' > "$R/scripts/z.py"
o=$(hook "$R"); [[ $? -ne 0 && "$o" == *"leak-scan"* ]] && ok "a staged home path cleaned only in the tree is still refused by leak-scan" || bad "leak-scan cleaned passed" "$o"

echo ""
[ "$fails" -eq 0 ] && echo "pre-commit change-level: all $checks checks pass" || echo "pre-commit change-level: $fails of $checks FAILED"
exit "$fails"
