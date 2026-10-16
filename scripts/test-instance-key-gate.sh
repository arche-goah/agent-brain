#!/usr/bin/env bash
# covers: instance-key-gate instance_key
# test-instance-key-gate.sh — a GitHub text an AI posts carries its instance key, or it is
# not sent; the reading side (instance_key.py) computes the SAME key. Both directions, no
# network: the gate only reads the command and the files it hands over.
#
# WHY (2026-10-11): one GitHub login carried two instances; the checks that decide whose move
# a PR is read the other machine's PR and its OK as their own and stayed silent.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$ROOT/helpers/instance-key-gate.cjs"
PY=python3; "$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/brain/.claude"

KEY="$(node -e 'console.log(require(process.argv[1]).keyFor("mac"))' "$(native "$GATE")")"
PYKEY="$(PYTHONPATH="$(native "$ROOT/scripts")" "$PY" -c 'import instance_key as k; print(k.key_for("mac"))')"
[ -n "$KEY" ] && [ "$KEY" = "$PYKEY" ] && ok "gate and reader compute the same key ($KEY)" || bad "key mismatch: js=$KEY py=$PYKEY"

probe() { # $1 label, $2 command, $3 block|allow, [$4 SELF value, default mac]
  local out rc
  out=$(printf '%s' "{\"tool_name\":\"Bash\",\"cwd\":\"$(native "$T")\",\"tool_input\":{\"command\":$(node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$2")}}" \
        | CLAUDE_PROJECT_DIR="$(native "$T/brain")" SHARED_MEMORY_SELF="${4-mac}" node "$(native "$GATE")" 2>&1); rc=$?
  if [ "$rc" -eq 2 ]; then [ "$3" = block ] && ok "$1 blocks" || bad "$1 blocked: ${out:0:120}"
  else [ "$3" = allow ] && ok "$1 allows" || bad "$1 did NOT block (rc=$rc)"; fi
}

probe "comment without key" "gh pr comment 5 -R o/r --body \"OK to merge\"" block
probe "comment with own key" "gh pr comment 5 -R o/r --body \"OK <!-- instance-key: $KEY -->\"" allow
probe "comment with ANOTHER instance's key" "gh pr comment 5 -R o/r --body \"OK <!-- instance-key: 0123456789 -->\"" block
printf 'body\n<!-- instance-key: %s -->\n' "$KEY" > "$T/body.md"
probe "create with key in --body-file" "gh pr create --head x --title t --body-file $(native "$T/body.md")" allow
printf 'body without key\n' > "$T/nokey.md"
probe "create, --body-file without key" "gh pr create --head x --title t --body-file $(native "$T/nokey.md")" block
probe "issue comment without key" "gh issue comment 9 -R o/r --body hi" block
probe "review --approve without a body" "gh pr review 5 -R o/r --approve" block
probe "merge with a marker comment is not a post" "gh pr merge 5 -R o/r --squash # MECHANISM-OK: x" allow
probe "read-only gh is not a post" "gh pr view 5 -R o/r --json body" allow
probe "no instance id: nothing to check" "gh pr comment 5 -R o/r --body hi" allow ""

# The block message names the exact line to add (an agent must not have to guess the key).
out=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"gh pr comment 5 --body hi"}}' \
      | CLAUDE_PROJECT_DIR="$(native "$T/brain")" SHARED_MEMORY_SELF=mac node "$(native "$GATE")" 2>&1)
case "$out" in *"<!-- instance-key: $KEY -->"*) ok "block message carries the exact marker" ;; *) bad "marker missing in: $out" ;; esac

# The id may come from the brain's settings env when the process env has none.
printf '{"env":{"SHARED_MEMORY_SELF":"mac, mac-alias"}}\n' > "$T/brain/.claude/settings.json"
out=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"gh pr comment 5 --body hi"}}' \
      | CLAUDE_PROJECT_DIR="$(native "$T/brain")" env -u SHARED_MEMORY_SELF node "$(native "$GATE")" 2>&1); rc=$?
[ "$rc" -eq 2 ] && case "$out" in *"$KEY"*) true ;; *) false ;; esac && ok "id read from settings env (first token)" || bad "settings env: rc=$rc $out"

# The PowerShell tool is the same channel on Windows (2026-10-16): same command, same verdict.
out=$(printf '%s' '{"tool_name":"PowerShell","tool_input":{"command":"gh pr comment 5 --body hi"}}'       | CLAUDE_PROJECT_DIR="$(native "$T/brain")" SHARED_MEMORY_SELF=mac node "$(native "$GATE")" 2>&1); rc=$?
[ "$rc" -eq 2 ] && case "$out" in *"instance-key"*) true ;; *) false ;; esac && ok "PowerShell write without the key blocks" || bad "PowerShell: rc=$rc $out"

[ "$fail" -eq 0 ] && echo "test-instance-key-gate: all checks passed"
exit "$fail"
