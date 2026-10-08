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

(( fail )) && { echo "test-local-machinery: FAILED"; exit 1; }
echo "test-local-machinery: all checks passed"
