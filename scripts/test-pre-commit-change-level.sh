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

# The CI lint's commit steps in the same hook (2026-11-12): where the repo ships ci-lint-local.sh, the hook runs its
# --commit mode, so a step the lint holds is held at commit time too. Two steps as the core's ci.yml has them, plus a
# failing step named shellcheck that --commit must leave out (the one step over the threshold, measured ~21 s).
L="$T/lintrepo"; mkdir -p "$L/scripts" "$L/helpers" "$L/.github/workflows"
cp "$HERE/ci-lint-local.sh" "$HERE/ci-lint-local-parse.py" "$L/scripts/"
cat > "$L/.github/workflows/ci.yml" <<'YML'
jobs:
  leaks:
    runs-on: ubuntu-latest
    steps:
      - name: stands in for the leak scan
        run: "true"
  lint:
    runs-on: ubuntu-latest
    steps:
      - name: no bare python3 in shell scripts
        run: |
          hits=$(grep -rnE '(^|\$\(|\||&&|;)[[:space:]]*python3[[:space:]]' \
                   --include='*.sh' . | grep -avE ':[0-9]+:[[:space:]]*#' || true)
          if [ -n "$hits" ]; then
            echo "$hits"
            exit 1
          fi
      - name: helpers parse (node syntax check)
        run: |
          for f in helpers/*.cjs; do node --check "$f"; done
  shellcheck:
    runs-on: ubuntu-latest
    steps:
      - name: shellcheck (severity error) over helpers/ and scripts/
        run: exit 1
YML
echo 'module.exports = 1;' > "$L/helpers/ok.cjs"
gq init -q "$L"; gq -C "$L" add -A; gq -C "$L" commit -qm seed --no-verify

echo "the CI lint's commit steps in the pre-commit"
echo 'echo hi' > "$L/scripts/fine.sh"; gq -C "$L" add -A
o=$(hook "$L"); [ $? -eq 0 ] && ok "a clean commit passes; the slow shellcheck step is left out" || bad "clean commit (lint)" "$o"
# the bare interpreter is assembled at run time, so this fixture's own line is no hit for the same lint step
printf '%s %s\n' "python3" "-c 1" > "$L/scripts/bare.sh"; gq -C "$L" add -A
o=$(hook "$L"); [[ $? -ne 0 && "$o" == *"ci lint (--commit)"* && "$o" == *"bare.sh"* ]] \
  && ok "a staged shell script with a bare python3 is refused at commit time" || bad "bare python3" "$o"
rm "$L/scripts/bare.sh"; gq -C "$L" add -A
if command -v node >/dev/null 2>&1; then
  echo 'module.exports = {;' > "$L/helpers/broken.cjs"; gq -C "$L" add -A
  o=$(hook "$L"); [[ $? -ne 0 && "$o" == *"helpers parse"* ]] \
    && ok "a staged helper with a JS syntax error is refused at commit time" || bad "JS syntax error" "$o"
  rm "$L/helpers/broken.cjs"; gq -C "$L" add -A
fi
o=$(hook "$L"); [ $? -eq 0 ] && ok "  ... and passes once both are gone" || bad "after removal (lint)" "$o"

echo ""
[ "$fails" -eq 0 ] && echo "pre-commit change-level: all $checks checks pass" || echo "pre-commit change-level: $fails of $checks FAILED"
exit "$fails"
