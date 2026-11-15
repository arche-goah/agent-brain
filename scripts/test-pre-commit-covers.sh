#!/usr/bin/env bash
# covers: pre-commit
# Fixture for the covers step of helpers/git-hooks/pre-commit: a staged data file runs the opted-in fixture whose
# `# covers:` line names its base name; a red fixture blocks, a green one passes; a fixture without the opt-in line
# never runs; a staged fixture runs itself; a removed data file still runs its fixture. Sandbox repos only.
# Exit 0 = all pass.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/../helpers/git-hooks/pre-commit"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0; checks=0
ok()  { checks=$((checks + 1)); echo "  ok   $1"; }
bad() { checks=$((checks + 1)); fails=$((fails + 1)); echo "  FAIL $1 — $2"; }
mkdir -p "$T/nohooks"
g() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main -c core.autocrlf=false \
        -c core.hooksPath="$T/nohooks" "$@"; }
gq() { g "$@" >/dev/null 2>&1; }
hook() { (cd "$1" && bash "$HOOK" 2>&1); }

R="$T/brain"
mkdir -p "$R/.claude/rules" "$R/scripts"
echo '{"ok": true}' > "$R/.claude/rules/demo-rules.json"
echo 'x' > "$R/.claude/rules/other-data.txt"
# opted-in fixture: red while demo-rules.json says "ok": false or is missing
cat > "$R/scripts/test-demo-rules.sh" <<'EOF'
#!/usr/bin/env bash
# covers: demo-rules (the demo data)
# pre-commit: covers
grep -q '"ok": true' .claude/rules/demo-rules.json || { echo "demo-rules: FAIL"; exit 1; }
echo "demo-rules: pass"
EOF
# fixture WITHOUT the opt-in line: always red, must never run from the hook
cat > "$R/scripts/test-other-data.sh" <<'EOF'
#!/usr/bin/env bash
# covers: other-data
echo "other-data: ran"; exit 1
EOF
echo "seed" > "$R/notes.txt"
gq init -q "$R"; gq -C "$R" add -A; gq -C "$R" commit -qm seed

echo "covers step in the pre-commit"
echo "more" >> "$R/notes.txt"; gq -C "$R" add notes.txt
o=$(hook "$R"); rc=$?
[[ $rc -eq 0 && "$o" != *"fixture scripts/"* ]] && ok "unrelated file staged: no fixture runs" || bad "unrelated file" "rc=$rc out: $o"
gq -C "$R" commit -qm notes

echo '{"ok": true, "n": 2}' > "$R/.claude/rules/demo-rules.json"; gq -C "$R" add .claude/rules/demo-rules.json
o=$(hook "$R"); rc=$?
[[ $rc -eq 0 ]] && ok "covered data staged, fixture green: commit passes" || bad "green fixture blocked" "rc=$rc out: $o"
gq -C "$R" commit -qm green

echo '{"ok": false}' > "$R/.claude/rules/demo-rules.json"; gq -C "$R" add .claude/rules/demo-rules.json
o=$(hook "$R"); rc=$?
[[ $rc -ne 0 && "$o" == *"fixture scripts/test-demo-rules.sh BLOCKS"* && "$o" == *"demo-rules: FAIL"* ]] \
  && ok "covered data staged, fixture red: commit blocked, output shown" || bad "red fixture did not block" "rc=$rc out: $o"
gq -C "$R" reset -q; g -C "$R" checkout -q -- .claude/rules/demo-rules.json

echo 'y' > "$R/.claude/rules/other-data.txt"; gq -C "$R" add .claude/rules/other-data.txt
o=$(hook "$R"); rc=$?
[[ $rc -eq 0 && "$o" != *"other-data"* ]] && ok "fixture without the opt-in line never runs" || bad "un-opted fixture ran" "rc=$rc out: $o"
gq -C "$R" commit -qm other

printf '%s\n' '#!/usr/bin/env bash' '# covers: demo-rules' '# pre-commit: covers' 'echo broken; exit 1' > "$R/scripts/test-demo-rules.sh"
gq -C "$R" add scripts/test-demo-rules.sh
o=$(hook "$R"); rc=$?
[[ $rc -ne 0 && "$o" == *"test-demo-rules.sh BLOCKS"* ]] && ok "a staged fixture runs itself" || bad "staged fixture not run" "rc=$rc out: $o"
gq -C "$R" reset -q; g -C "$R" checkout -q -- scripts/test-demo-rules.sh

gq -C "$R" rm -q .claude/rules/demo-rules.json
o=$(hook "$R"); rc=$?
[[ $rc -ne 0 && "$o" == *"test-demo-rules.sh BLOCKS"* ]] && ok "a removed covered file still runs its fixture" || bad "removal not checked" "rc=$rc out: $o"
gq -C "$R" reset -q; g -C "$R" checkout -q -- .claude/rules/demo-rules.json

# a JS fixture (// comments, run with node) takes part the same way (reach finding at #453)
echo '{"on": false}' > "$R/.claude/rules/js-rules.json"
printf '%s\n' '// covers: js-rules' '// pre-commit: covers' \
  'const ok = require("fs").readFileSync(".claude/rules/js-rules.json", "utf8").includes("\"on\": true");' \
  'console.log(ok ? "js-rules: pass" : "js-rules: FAIL"); process.exit(ok ? 0 : 1);' > "$R/scripts/test-js-rules.cjs"
gq -C "$R" add scripts/test-js-rules.cjs .claude/rules/js-rules.json
o=$(hook "$R"); rc=$?
[[ $rc -ne 0 && "$o" == *"test-js-rules.cjs BLOCKS"* && "$o" == *"js-rules: FAIL"* ]] \
  && ok "a JS fixture runs with node and blocks when red" || bad "JS fixture not run" "rc=$rc out: $o"
echo '{"on": true}' > "$R/.claude/rules/js-rules.json"; gq -C "$R" add .claude/rules/js-rules.json
o=$(hook "$R"); rc=$?
[[ $rc -eq 0 ]] && ok "a green JS fixture lets the commit pass" || bad "green JS fixture blocked" "rc=$rc out: $o"

echo ""
[ "$fails" -eq 0 ] && echo "pre-commit covers: all $checks checks pass" || echo "pre-commit covers: $fails of $checks FAILED"
exit "$fails"
