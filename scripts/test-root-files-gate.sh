#!/usr/bin/env bash
# Fixture for helpers/root-files-gate.cjs: an untracked, not ignored file directly in the repo
# root that is not on the list holds the turn. Cases: clean root, a stray file (block, named),
# a listed root file, a file in a folder, an ignored file, a tracked file, the instance list,
# the re-issue, no git repo.
# The repo path goes to node through the hook payload, built with native() (OS-3).
set -uo pipefail
# A fixture that runs `git init` must not inherit the hook variables of a commit in progress.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX

HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="$HERE/../helpers/root-files-gate.cjs"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FAIL=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAIL=1; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

R="$TMP/brain"
mkdir -p "$R/docs" "$R/.claude/rules"
git -C "$R" init -q
git -C "$R" config user.email fixture@example.invalid
git -C "$R" config user.name fixture
printf '*.log\n' > "$R/.gitignore"
printf 'x\n' > "$R/docs/note.md"
printf 'x\n' > "$R/legacy.txt"
git -C "$R" add .gitignore docs/note.md legacy.txt
git -C "$R" commit -q -m seed

run() { # name expect(block|allow) [extra payload] [dir]
  local out dir="${4:-$R}"
  out=$(printf '{"cwd":"%s"%s}' "$(native "$dir")" "${3:-}" | env -u CLAUDE_PROJECT_DIR node "$GATE")
  if [[ "$2" == block ]]; then
    grep -q 'ROOT-FILES' <<<"$out" && grep -q 'capture.png' <<<"$out" && pass "$1" || fail "$1 (expected block): $out"
  else
    [[ -z "$out" ]] && pass "$1" || fail "$1 (expected allow): $out"
  fi
}

run "a clean root passes (a tracked extra file is the scan's matter)" allow

printf 'x\n' > "$R/README.md"; printf 'x\n' > "$R/docs/new.md"; printf 'x\n' > "$R/run.log"; mkdir "$R/newdir"; printf 'x\n' > "$R/newdir/a.txt"
run "a listed root file, a file in a folder, an ignored file and a new folder pass" allow

printf 'x\n' > "$R/capture.png"
run "a stray file in the root blocks and is named" block
out=$(printf '{"cwd":"%s"}' "$(native "$R")" | env -u CLAUDE_PROJECT_DIR node "$GATE")
grep -q 'README.md\|run.log\|newdir\|legacy.txt' <<<"$out" && fail "the block names a file that is allowed: $out" || pass "the block names only the stray file"

run "the re-issue passes (one hold per turn)" allow ',"stop_hook_active":true'

out=$(printf '{"cwd":"%s","stop_check":{"label":"ROOT FILE","marker":"ROOT-FILES"}}' "$(native "$R")" | env -u CLAUDE_PROJECT_DIR node "$GATE")
grep -q '"echo":"label"' <<<"$out" && pass "behind the dispatcher the block declares the label echo" || fail "no label declaration: $out"

printf '{"allowed":["capture.png"]}\n' > "$R/.claude/rules/root-files.json"
run "a file the instance declares passes" allow
rm "$R/.claude/rules/root-files.json"

mkdir "$TMP/plain"; printf 'x\n' > "$TMP/plain/capture.png"
run "a folder that is no git repo passes (cannot measure)" allow '' "$TMP/plain"

# The list has two homes, the rule text and the gate; this case fails when they differ.
node -e '
const fs = require("fs"), path = require("path");
const { CORE } = require(process.argv[1]);
const text = fs.readFileSync(path.join(path.dirname(process.argv[1]), "..", "rules", "working-rules.md"), "utf8");
const m = text.match(/\*\*Root files:\*\* only([\s\S]+?)\(an instance/);
const rule = m ? m[1].split(",").map((s) => s.trim()).filter(Boolean).sort() : [];
process.exit(JSON.stringify(rule) === JSON.stringify([...CORE].sort()) ? 0 : 1);
' "$(native "$GATE")" && pass "the gate's list is the rule's list (working-rules.md, File Rules)" || fail "the gate's list and the rule's list differ"

exit $FAIL
