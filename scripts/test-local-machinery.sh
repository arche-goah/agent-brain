#!/usr/bin/env bash
# Fixture for scripts/local-machinery.py — both directions: silent when every hook is core or
# declared, loud for an undeclared instance hook, an undeclared outside hook and an expired alpha.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY=python3; "$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }

mk() { # $1 = settings hooks json, $2 = stop-checks json, $3 = declarations json
  rm -rf "$T/b"; mkdir -p "$T/b/.claude/rules"
  printf '%s' "$1" > "$T/b/.claude/settings.json"
  [[ -n "$2" ]] && printf '%s' "$2" > "$T/b/.claude/rules/stop-checks.json"
  [[ -n "$3" ]] && printf '%s' "$3" > "$T/b/.claude/rules/local-machinery.json"
  "$PY" "$HERE/local-machinery.py" --repo "$T/b" --today 2026-10-08
}
H() { printf '{"hooks":{"Stop":[{"hooks":[%s]}]}}' "$1"; }
C() { printf '{"type":"command","command":"%s"}' "$1"; }

out=$(mk "$(H "$(C 'node \"$CLAUDE_PROJECT_DIR/core/helpers/a.cjs\"')")" '[{"cmd":"core/helpers/b.cjs"}]' '')
[[ -z "$out" ]] && ok "core-only-silent" || bad "core-only-silent: $out"

out=$(mk "$(H "$(C 'node \"$CLAUDE_PROJECT_DIR/scripts/hooks/x.cjs\"')")" '' '')
grep -q 'instance hook(s) without a reason' <<< "$out" && grep -q 'x.cjs' <<< "$out" && ok "undeclared-instance-named" || bad "undeclared-instance-named: $out"

out=$(mk "$(H "$(C 'node \"$CLAUDE_PROJECT_DIR/scripts/hooks/x.cjs\"')")" '' '{"instance":{"scripts/hooks/x.cjs":"renders only for this printer"}}')
[[ -z "$out" ]] && ok "declared-instance-silent" || bad "declared-instance-silent: $out"

out=$(mk "$(H "$(C 'node /elsewhere/agent-brain-dev/helpers/d.cjs')")" '' '')
grep -q '^!! local machinery: 1 hook(s) run from outside' <<< "$out" && ok "undeclared-outside-loud" || bad "undeclared-outside-loud: $out"

out=$(mk "$(H "$(C 'node /elsewhere/agent-brain-dev/helpers/d.cjs')")" '' '{"alpha":{"/elsewhere/agent-brain-dev/":{"until":"2026-10-20","why":"alpha"}}}')
[[ -z "$out" ]] && ok "alpha-in-date-silent" || bad "alpha-in-date-silent: $out"

out=$(mk "$(H "$(C 'node /elsewhere/agent-brain-dev/helpers/d.cjs')")" '' '{"alpha":{"/elsewhere/agent-brain-dev/":{"until":"2026-10-01","why":"alpha"}}}')
grep -q 'past their date' <<< "$out" && ok "alpha-expired-loud" || bad "alpha-expired-loud: $out"

out=$(mk "$(H "$(C 'node /elsewhere/agent-brain-dev/helpers/d.cjs')")" '' '{"alpha":{"/elsewhere/agent-brain-dev/":{"why":"no date"}}}')
grep -q 'past their date' <<< "$out" && ok "alpha-without-date-loud" || bad "alpha-without-date-loud: $out"

out=$(mk "$(H "$(C 'node \"$CLAUDE_PROJECT_DIR/core/helpers/a.cjs\"')")" '[{"cmd":"/elsewhere/dev/helpers/g.cjs"}]' '')
grep -q 'run from outside' <<< "$out" && grep -q 'g.cjs' <<< "$out" && ok "stop-check-outside-counted" || bad "stop-check-outside-counted: $out"

out=$(mk '{' '' '')
rc=$?; [[ $rc -eq 0 && -z "$out" ]] && ok "broken-settings-silent-exit0" || bad "broken-settings-silent-exit0 rc=$rc: $out"

mk "$(H "$(C 'node \"$CLAUDE_PROJECT_DIR/core/helpers/a.cjs\"')")" '' '' >/dev/null
git -C "$T/b" init -q 2>/dev/null; mkdir -p "$T/b/core"; git -C "$T/b/core" init -q
printf 'x\n' > "$T/b/core/rule.md"; git -C "$T/b/core" add rule.md
git -C "$T/b/core" -c user.email=t@t -c user.name=t commit -q -m init
out=$("$PY" "$HERE/local-machinery.py" --repo "$T/b" --today 2026-10-08)
[[ -z "$out" ]] && ok "clean-core-silent" || bad "clean-core-silent: $out"
printf 'y\n' >> "$T/b/core/rule.md"
out=$("$PY" "$HERE/local-machinery.py" --repo "$T/b" --today 2026-10-08)
grep -q 'core file(s) edited inside core/: rule.md' <<< "$out" && ok "edited-core-loud" || bad "edited-core-loud: $out"

# Scripts outside hooks: a same-named copy of a core script is loud; an undeclared instance
# script is listed for classification; a declared one and a fixture are silent.
mk "$(H "$(C 'node \"$CLAUDE_PROJECT_DIR/core/helpers/a.cjs\"')")" '' '' >/dev/null
mkdir -p "$T/b/core/scripts" "$T/b/scripts/hooks"
printf 'x\n' > "$T/b/core/scripts/invariant-check.py"; printf 'x\n' > "$T/b/scripts/invariant-check.py"
out=$("$PY" "$HERE/local-machinery.py" --repo "$T/b" --today 2026-10-08)
grep -q '^!! local machinery: 1 instance script(s) shadow a core script of the same name: scripts/invariant-check.py' <<< "$out" && ok "shadow-copy-loud" || bad "shadow-copy-loud: $out"
rm -f "$T/b/scripts/invariant-check.py"; printf 'x\n' > "$T/b/scripts/rig-check.sh"; printf 'x\n' > "$T/b/scripts/test-rig-check.sh"
out=$("$PY" "$HERE/local-machinery.py" --repo "$T/b" --today 2026-10-08)
grep -q 'instance script(s) without a declared reason to live only here: scripts/rig-check.sh$\|instance script(s) without a declared reason to live only here: scripts/rig-check.sh ' <<< "$out" && ! grep -q 'test-rig-check' <<< "$out" && ok "undeclared-script-listed-fixture-skipped" || bad "undeclared-script-listed-fixture-skipped: $out"
printf '{"instance":{"scripts/rig-check.sh":"probes this venue only"}}' > "$T/b/.claude/rules/local-machinery.json"
out=$("$PY" "$HERE/local-machinery.py" --repo "$T/b" --today 2026-10-08)
[[ -z "$out" ]] && ok "declared-script-silent" || bad "declared-script-silent: $out"
printf '{"alpha":{"scripts/rig-check.sh":{"until":"2026-10-20","why":"core port"}}}' > "$T/b/.claude/rules/local-machinery.json"
out=$("$PY" "$HERE/local-machinery.py" --repo "$T/b" --today 2026-10-08)
[[ -z "$out" ]] && ok "alpha-script-in-date-silent" || bad "alpha-script-in-date-silent: $out"
out=$("$PY" "$HERE/local-machinery.py" --repo "$T/b" --today 2026-10-21)
grep -q 'past their date.*scripts/rig-check.sh' <<< "$out" && ok "alpha-script-expired-loud" || bad "alpha-script-expired-loud: $out"
rm -rf "$T/b/scripts" "$T/b/core/scripts" "$T/b/.claude/rules/local-machinery.json"

# Tool sources: an MCP server path or a skill symlink into a suite checkout. The path inside
# .mcp.json is DATA for a native python, so it goes through cygpath on Windows (OS-3).
nat() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }
mkdir -p "$T/suite/skills/s1"; printf 'x\n' > "$T/suite/server.js"
git -C "$T/suite" init -q -b main; git -C "$T/suite" add -A
git -C "$T/suite" -c user.email=t@t -c user.name=t commit -q -m init
rm -rf "$T/b/core"
printf '{"mcpServers":{"s":{"command":"node","args":["%s"]}}}' "$(nat "$T/suite/server.js")" > "$T/b/.mcp.json"
out=$("$PY" "$HERE/local-machinery.py" --repo "$T/b" --today 2026-10-08)
[[ -z "$out" ]] && ok "mcp-source-on-main-silent" || bad "mcp-source-on-main-silent: $out"
git -C "$T/suite" checkout -q -b feat/x
out=$("$PY" "$HERE/local-machinery.py" --repo "$T/b" --today 2026-10-08)
grep -q 'suite@feat/x' <<< "$out" && ok "mcp-source-off-main-loud" || bad "mcp-source-off-main-loud: $out"
printf '{"alpha":{"%s":{"until":"2026-10-20","why":"alpha"}}}' "$(nat "$T/suite")" > "$T/b/.claude/rules/local-machinery.json"
out=$("$PY" "$HERE/local-machinery.py" --repo "$T/b" --today 2026-10-08)
[[ -z "$out" ]] && ok "off-main-declared-alpha-silent" || bad "off-main-declared-alpha-silent: $out"
rm -f "$T/b/.mcp.json" "$T/b/.claude/rules/local-machinery.json"; mkdir -p "$T/b/.claude/skills"
ln -s "$T/suite/skills/s1" "$T/b/.claude/skills/s1" 2>/dev/null
if [[ -L "$T/b/.claude/skills/s1" ]]; then
  out=$("$PY" "$HERE/local-machinery.py" --repo "$T/b" --today 2026-10-08)
  grep -q 'suite@feat/x' <<< "$out" && ok "skill-symlink-off-main-loud" || bad "skill-symlink-off-main-loud: $out"
else
  echo "  SKIP skill-symlink-off-main-loud (no symlinks on this platform)"
fi

(( fail )) && { echo "test-local-machinery: FAILED"; exit 1; }
echo "test-local-machinery: all checks passed"
