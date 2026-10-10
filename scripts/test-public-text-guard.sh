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

# no watch list: nothing to check against
rc=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"gh pr comment 1 -R o/pub --body zorbalina"}}' \
     | CLAUDE_PROJECT_DIR="$NT/nobrain" node "$GATE" >/dev/null 2>&1; echo $?)
[ "$rc" = 0 ] && ok "no watch list allows" || bad "no watch list allows (rc=$rc)"
# another tool: not this gate's business
rc=$(printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"x","new_string":"zorbalina"}}' \
     | CLAUDE_PROJECT_DIR="$NT/brain" node "$GATE" >/dev/null 2>&1; echo $?)
[ "$rc" = 0 ] && ok "non-Bash tool allows" || bad "non-Bash tool allows (rc=$rc)"
# the visibility answer is cached for the next call
grep -q '"o/pub"' "$B/.claude-state/repo-visibility.json" 2>/dev/null && ok "visibility cached" || bad "visibility cached"

[ "$fail" -eq 0 ] && echo "public-text-guard: all checks passed" || echo "public-text-guard: FAILURE"
exit "$fail"
