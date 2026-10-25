#!/usr/bin/env bash
# covers: public-text-guard
#
# Fixture test for helpers/public-text-guard.cjs — both directions. A fake `gh` answers the
# visibility question; the watch list holds a made-up name. Every must-block case is also run
# against an always-allow stub and must come back "allow" there (negative control).
#
# Usage: bash scripts/test-public-text-guard.sh [gate.cjs]   (exit 0 = all fixtures pass)
set -u

native() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
resolve() { for c in "core/$1" "$1"; do [ -f "$ROOT/$c" ] && { printf '%s' "$ROOT/$c"; return 0; }; done; return 1; }
if [ $# -ge 1 ]; then GATE="$1"; else
  GATE=$(resolve helpers/public-text-guard.cjs) || { echo "  --  public-text-guard not in this layout"; exit 0; }
fi
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
NT=$(native "$T")
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }

STUB="$T/always-allow.cjs"
printf '%s\n' "process.stdin.resume(); process.stdin.on('end', () => process.exit(0));" > "$STUB"

# --- layout: a brain with a watch list, a fake gh, a public and a private clone ---
B="$T/brain"; mkdir -p "$B/.claude/rules" "$T/bin"
printf '{"names": ["zorbalina"], "instances": ["zorba-rig"]}\n' > "$B/.claude/rules/leak-names.json"
cat > "$T/bin/fake-gh.cjs" <<'EOF'
const a = process.argv.slice(2).join(' ');
if (a.includes('repos/o/pub')) console.log('public');
else if (a.includes('repos/o/priv')) console.log('private');
else process.exit(1);
EOF
export PUBLIC_TEXT_GUARD_FAKE_GH="$NT/bin/fake-gh.cjs"
git init -q "$T/pubclone" && git -C "$T/pubclone" remote add origin https://github.com/o/pub.git
git init -q "$T/privclone" && git -C "$T/privclone" remote add origin git@github.com:o/priv.git
for c in pubclone privclone; do
  git -C "$T/$c" config user.name "acct"; git -C "$T/$c" config user.email "1+acct@users.noreply.github.com"
done
git init -q "$T/namedclone" && git -C "$T/namedclone" remote add origin https://github.com/o/pub.git
git -C "$T/namedclone" config user.name "Zorbalina Example"; git -C "$T/namedclone" config user.email "z@example.org"
git init -q "$T/namedpriv" && git -C "$T/namedpriv" remote add origin https://github.com/o/priv.git
git -C "$T/namedpriv" config user.name "Zorbalina Example"; git -C "$T/namedpriv" config user.email "z@example.org"
printf 'Thanks to Zorbalina for the review.\n' > "$T/named.md"
printf 'Thanks for the review.\n' > "$T/clean.md"

# run <gate> <cwd> <command> -> prints the exit code
run() {
  local json
  json=$(CMD="$3" CWD="$(native "$2")" node -e \
    'process.stdout.write(JSON.stringify({tool_name: "Bash", cwd: process.env.CWD, tool_input: {command: process.env.CMD}}))')
  printf '%s' "$json" | CLAUDE_PROJECT_DIR="$NT/brain" node "$1" >/dev/null 2>&1
  echo $?
}
expect() { # <label> <want: block|allow> <cwd> <command>
  local rc want="$2"
  rc=$(run "$GATE" "$3" "$4")
  if { [ "$want" = block ] && [ "$rc" = 2 ]; } || { [ "$want" = allow ] && [ "$rc" = 0 ]; }; then ok "$1"; else bad "$1 (rc=$rc, want $want)"; fi
  if [ "$want" = block ]; then
    rc=$(run "$STUB" "$3" "$4")
    [ "$rc" = 0 ] || bad "$1: negative control did not allow (rc=$rc)"
  fi
}

expect "comment with a name to a public repo blocks"        block "$T" 'gh pr comment 1 -R o/pub --body "thanks zorbalina"'
expect "same comment to a private repo passes"              allow "$T" 'gh pr comment 1 -R o/priv --body "thanks zorbalina"'
expect "clean comment to a public repo passes"              allow "$T" 'gh pr comment 1 -R o/pub --body "thanks"'
expect "name only inside --body-file blocks"                block "$T" "gh pr create -R o/pub --title fix --body-file $NT/named.md"
expect "clean --body-file passes"                           allow "$T" "gh pr create -R o/pub --title fix --body-file $NT/clean.md"
expect "name inside \$(cat file) blocks"                    block "$T" "gh issue comment 3 -R o/pub --body \"\$(cat $NT/named.md)\""
expect "gh api field to a public repo blocks"               block "$T" 'gh api repos/o/pub/issues/1/comments -f body="hi Zorbalina"'
expect "instance name (with a dash) blocks"                 block "$T" 'gh pr edit 2 -R o/pub --body "measured on zorba-rig"'
expect "a read command naming someone passes"               allow "$T" 'gh pr view 1 -R o/pub --jq ".body | test(\"zorbalina\")"'
expect "part of a longer word is no hit"                    allow "$T" 'gh pr comment 1 -R o/pub --body "zorbalinas"'
expect "unknown visibility counts as public"                block "$T" 'gh pr comment 1 -R o/gone --body "zorbalina"'
expect "commit message in a public clone blocks"            block "$T/pubclone" 'git commit -m "fix for zorbalina"'
expect "git -C into a public clone blocks"                  block "$T" "git -C $NT/pubclone commit -am \"zorbalina asked\""
expect "commit message in a private clone passes"           allow "$T/privclone" 'git commit -m "fix for zorbalina"'
expect "commit message file in a public clone blocks"       block "$T/pubclone" "git commit -F $NT/named.md"
expect "named commit AUTHOR in a public clone blocks"       block "$T/namedclone" 'git commit -m "clean message"'
expect "named author via git -C, no message flag, blocks"   block "$T" "git -C $NT/namedclone commit --amend --no-edit"
expect "named author in a private clone passes"             allow "$T/namedpriv" 'git commit -m "clean message"'
expect "neutral author in a public clone passes"            allow "$T/pubclone" 'git commit -m "clean message"'
# home paths built at run time: a literal one would trip the core's own leak-scan
U="Users"; HOME_MAC="/$U/zorbalina"; HOME_WIN="C:\\$U\\zorbalina"
expect "a name only in a home path passes"                  allow "$T" "gh pr create -R o/pub --title fix --body-file $HOME_MAC/clean.md"
expect "a name only in a Windows home path passes"          allow "$T" "gh pr comment 1 -R o/pub --body-file $HOME_WIN\\clean.md"
expect "a name in the text next to a home path still blocks" block "$T" "gh pr comment 1 -R o/pub --body \"hi zorbalina\" --repo o/pub"
mkdir -p "$T/scratch-Users-zorbalina-proj" && printf 'clean\n' > "$T/scratch-Users-zorbalina-proj/b.md"
expect "a name inside an existing path passes"              allow "$T" "gh pr create -R o/pub --title fix --body-file $NT/scratch-Users-zorbalina-proj/b.md"
expect "a slash word in the text is no path, still blocks"  block "$T" 'gh pr comment 1 -R o/pub --body "see zorbalina/notes"'
# `~` in the command: the shell expands it, so the guard must too (2026-10-18, Windows instance).
# Before: `git -C ~/<private clone>` found no remote and blocked as "unknown"; a `--body-file
# ~/<file>` stayed unread — and unscanned, so a name in it passed. HOME points at the fixture.
HOME="$NT" USERPROFILE="$NT" expect "git -C ~/<private clone> passes"  allow "$T" 'git -C ~/privclone commit -m "fix for zorbalina"'
HOME="$NT" USERPROFILE="$NT" expect "git -C ~/<public clone> blocks"   block "$T" 'git -C ~/pubclone commit -m "fix for zorbalina"'
HOME="$NT" USERPROFILE="$NT" expect "name inside --body-file ~/<file> blocks" block "$T" 'gh pr comment 1 -R o/pub --body-file ~/named.md'
HOME="$NT" USERPROFILE="$NT" expect "clean --body-file ~/<file> passes"       allow "$T" 'gh pr comment 1 -R o/pub --body-file ~/clean.md'

# Only the PUBLISHED text is scanned (2026-10-19): the values of the text flags and fields, the
# gh api endpoint, the commit message, the handed-over files. Paths, comments, the working
# directory are never published. Before, the guard scanned the whole command and masked path
# forms: a comment or a path with a missing parent blocked, and a path-shaped word INSIDE a body
# was masked and passed unchecked.
expect "a name only in a shell comment passes"              allow "$T" 'gh pr comment 1 -R o/pub --body "thanks" # zorbalina asked'
expect "a name in a path whose folder is missing passes"    allow "$T" "gh pr create -R o/pub --title fix --body-file $NT/no-such-zorbalina/x.md"
expect "a name in the git -C path, clean message, passes"   allow "$T" "git -C $NT/pubclone/../zorbalina-gone/../pubclone commit -m \"clean message\""
expect "a path-shaped word inside the body blocks"          block "$T" "gh pr comment 1 -R o/pub --body \"see $NT/scratch-Users-zorbalina-proj/b.md\""
expect "short title flag -t blocks"                         block "$T" 'gh issue create -R o/pub -t "for zorbalina" -b "x"'
expect "--title=<text> blocks"                              block "$T" 'gh pr create -R o/pub --title=zorbalina --body x'
expect "release notes -n block"                             block "$T" 'gh release create v1 -R o/pub -n "thanks zorbalina"'
expect "gh pr create -F <file> reads the file"              block "$T" "gh pr create -R o/pub --title fix -F $NT/named.md"
expect "gh api -F body=@<file> reads the file"              block "$T" "gh api repos/o/pub/issues/1/comments -F body=@$NT/named.md"
expect "gh api clean field passes"                          allow "$T" 'gh api repos/o/pub/issues/1/comments -f body="thanks"'
expect "gh api endpoint naming someone blocks"              block "$T" 'gh api repos/o/pub/contents/notes-zorbalina.md -X PUT -f message=x'
expect "git -am <text> blocks"                              block "$T/pubclone" 'git commit -am "zorbalina asked"'
expect "git -m<text> attached blocks"                       block "$T/pubclone" 'git commit -mzorbalina'
expect "git --message=<text> blocks"                        block "$T/pubclone" 'git commit --message="for zorbalina"'
expect "a second command after ; is read too"               block "$T" 'echo ok; gh pr comment 1 -R o/pub --body "zorbalina"'
expect "an unknown \$(...) in the body is checked"          block "$T" 'gh pr comment 1 -R o/pub --body "$(echo zorbalina)"'
expect "a heredoc is read whole and blocks"                 block "$T" "gh pr comment 1 -R o/pub --body \"\$(cat <<'X'
zorbalina
X
)\""
expect "an unbalanced quote is read whole and blocks"       block "$T" 'gh pr comment 1 -R o/pub --body "zorbalina'
# PowerShell: a backslash is a path separator, not an escape - the handed-over file keeps its
# path (checked on the parser, so it runs on every OS; the file read itself is the same code)
got=$(GATE_JS="$(native "$GATE")" node -e '
  const { publishedText } = require(process.env.GATE_JS);
  const ps = publishedText("gh pr comment 1 -R o/pub --body-file C:\\U\\x\\b.md", true).files[0];
  const sh = publishedText("gh pr comment 1 -R o/pub --body-file \"C:\\U\\x\\b.md\"", false).files[0];
  process.stdout.write(ps + "|" + sh);' 2>&1)
[ "$got" = 'C:\U\x\b.md|C:\U\x\b.md' ] && ok "backslash paths survive (PowerShell, bash double quotes)" \
  || bad "backslash paths survive (got: $got)"

# no watch list: nothing to check against
rc=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"gh pr comment 1 -R o/pub --body zorbalina"}}' \
     | CLAUDE_PROJECT_DIR="$NT/nobrain" node "$GATE" >/dev/null 2>&1; echo $?)
[ "$rc" = 0 ] && ok "no watch list allows" || bad "no watch list allows (rc=$rc)"
# 2026-10-25: text through a shell variable is invisible to the guard - refused in public, free in
# private; a literal '$5' is no variable. Measured the same day: a collaborator's brain posted a
# name into the public core through --body-file and nothing refused it (its own watch list).
expect "a shell variable in --body to a public repo blocks"  block "$T" 'gh pr comment 1 -R o/pub --body "see $BODY"'
expect "a \${VAR} form in --body to a public repo blocks"    block "$T" 'gh pr comment 1 -R o/pub --body "see ${BODY}"'
expect "the same variable to a private repo passes"         allow "$T" 'gh pr comment 1 -R o/priv --body "see $BODY"'
expect "a literal single-quoted \$VAR passes"               allow "$T" "gh pr comment 1 -R o/pub --body 'see \$BODY'"
expect "a dollar amount is no variable"                     allow "$T" 'gh pr comment 1 -R o/pub --body "costs $5"'
# parties.json of the shared memory is a second source of names: a brain whose own watch list
# is EMPTY still refuses the names of every party (the measured gap of 2026-10-25).
P="$T/shared"; mkdir -p "$P" "$T/brain-empty/.claude/rules"
printf '{"people": {"quxperson": {"github": "qux-gh", "devices": {"qux-win": {"os": "windows"}}, "legacy_ids": ["workstation"]}}}\n' > "$P/parties.json"
printf '{"names": [], "instances": []}\n' > "$T/brain-empty/.claude/rules/leak-names.json"
run_brain() { # <brain dir> <cwd> <command> -> exit code, with the shared-memory fixture
  local json
  json=$(CMD="$3" CWD="$(native "$2")" node -e \
    'process.stdout.write(JSON.stringify({tool_name: "Bash", cwd: process.env.CWD, tool_input: {command: process.env.CMD}}))')
  printf '%s' "$json" | SHARED_MEMORY_REPO="$(native "$P")" CLAUDE_PROJECT_DIR="$(native "$1")" node "$GATE" >/dev/null 2>&1
  echo $?
}
rc=$(run_brain "$T/brain-empty" "$T" 'gh pr comment 1 -R o/pub --body "thanks quxperson"')
[ "$rc" = 2 ] && ok "empty own list: a parties.json person still blocks" || bad "empty own list: a parties.json person still blocks (rc=$rc)"
rc=$(run_brain "$T/brain-empty" "$T" 'gh pr comment 1 -R o/pub --body "measured on qux-win"')
[ "$rc" = 2 ] && ok "empty own list: a parties.json device id blocks" || bad "empty own list: a parties.json device id blocks (rc=$rc)"
rc=$(run_brain "$T/brain-empty" "$T" 'gh pr comment 1 -R o/priv --body "thanks quxperson"')
[ "$rc" = 0 ] && ok "parties.json name to a private repo passes" || bad "parties.json name to a private repo passes (rc=$rc)"
rc=$(run_brain "$T/brain-empty" "$T" 'gh pr comment 1 -R o/pub --body "the workstation is on"')
[ "$rc" = 0 ] && ok "a legacy id (plain word) is not on the list" || bad "a legacy id (plain word) is not on the list (rc=$rc)"
rc=$(run_brain "$T/brain" "$T" 'gh pr comment 1 -R o/pub --body "thanks quxperson"')
[ "$rc" = 2 ] && ok "own list plus parties.json: both sources count" || bad "own list plus parties.json: both sources count (rc=$rc)"
rc=$(SHARED_MEMORY_REPO="$(native "$T/no-shared")" run "$GATE" "$T" 'gh pr comment 1 -R o/pub --body "thanks quxperson"')
[ "$rc" = 0 ] && ok "no parties.json: only the own list (control)" || bad "no parties.json: only the own list (control, rc=$rc)"

# another tool: not this gate's business
rc=$(printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"x","new_string":"zorbalina"}}' \
     | CLAUDE_PROJECT_DIR="$NT/brain" node "$GATE" >/dev/null 2>&1; echo $?)
[ "$rc" = 0 ] && ok "non-Bash tool allows" || bad "non-Bash tool allows (rc=$rc)"
# the PowerShell tool carries the same command and is the same channel (Windows, 2026-10-16)
rc=$(printf '%s' '{"tool_name":"PowerShell","tool_input":{"command":"gh pr comment 1 -R o/pub --body zorbalina"}}'      | CLAUDE_PROJECT_DIR="$NT/brain" node "$GATE" >/dev/null 2>&1; echo $?)
[ "$rc" = 2 ] && ok "PowerShell write to a public repo blocks" || bad "PowerShell write to a public repo blocks (rc=$rc)"
# the visibility answer is cached for the next call
grep -q '"o/pub"' "$B/.claude-state/repo-visibility.json" 2>/dev/null && ok "visibility cached" || bad "visibility cached"

[ "$fail" -eq 0 ] && echo "public-text-guard: all checks passed" || echo "public-text-guard: FAILURE"
exit "$fail"
