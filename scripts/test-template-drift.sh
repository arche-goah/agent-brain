#!/usr/bin/env bash
# Fixture for scripts/template-drift.py — both directions.
# The must-report case is the incident (2026-10-26, Windows instance): a brain whose settings
# lack template allow rules (gh pr ready among them) heard nothing at session start.
# Usage: bash scripts/test-template-drift.sh (exit 0 = pass)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/template-drift.py"
PY=python3
"$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }

TPL="$T/template.json"
printf '%s\n' '{"permissions":{"allow":["Bash(gh pr ready*)","Bash(gh pr create*)","Bash(git status*)"],"ask":["Edit(.claude/settings.json)"],"deny":["Bash(git push --force*)"]}}' > "$TPL"
brain() { mkdir -p "$T/$1/.claude"; printf '%s\n' "$2" > "$T/$1/.claude/settings.json"; }
run() { "$PY" "$S" --repo "$(native "$T/$1")" --template "$(native "$TPL")" 2>&1; }

# 1 the incident: allow rules missing
brain b1 '{"permissions":{"allow":["Bash(git status*)"],"ask":["Edit(.claude/settings.json)"],"deny":["Bash(git push --force*)"]}}'
out="$(run b1)"
case "$out" in *'!! settings: 2 permission rule(s)'*'gh pr ready'*'gh pr create'*) ok "missing allow rules are named";; *) bad "missing allow rules not named: '$out'";; esac

# 2 complete brain: silent
brain b2 '{"permissions":{"allow":["Bash(gh pr ready*)","Bash(gh pr create*)","Bash(git status*)","Bash(extra)"],"ask":["Edit(.claude/settings.json)"],"deny":["Bash(git push --force*)"]}}'
out="$(run b2)"
[ -z "$out" ] && ok "complete brain (plus own extras) is silent" || bad "complete brain reported: '$out'"

# 3 a declared deviation with a reason is silent; an empty reason is not a declaration
brain b3 '{"permissions":{"allow":["Bash(git status*)","Bash(gh pr create*)"],"ask":["Edit(.claude/settings.json)"],"deny":["Bash(git push --force*)"],"_template_deviations":{"Bash(gh pr ready*)":"this brain never drafts"}}}'
out="$(run b3)"
[ -z "$out" ] && ok "declared deviation with a reason is silent" || bad "declared deviation reported: '$out'"
brain b3b '{"permissions":{"allow":["Bash(git status*)","Bash(gh pr create*)"],"ask":["Edit(.claude/settings.json)"],"deny":["Bash(git push --force*)"],"_template_deviations":{"Bash(gh pr ready*)":"  "}}}'
out="$(run b3b)"
case "$out" in *'gh pr ready'*) ok "a blank reason is no declaration";; *) bad "blank reason silenced the rule: '$out'";; esac

# 4 a missing deny is named too (a dropped limit)
brain b4 '{"permissions":{"allow":["Bash(gh pr ready*)","Bash(gh pr create*)","Bash(git status*)"],"ask":["Edit(.claude/settings.json)"]}}'
out="$(run b4)"
case "$out" in *'deny 1: Bash(git push --force*)'*) ok "missing deny is named";; *) bad "missing deny not named: '$out'";; esac

# 5 broken settings: said so, exit 0
brain b5 '{not json'
out="$(run b5)"; rc=$?
case "$out" in *'not valid JSON'*) [ "$rc" = 0 ] && ok "broken settings named, exit 0" || bad "broken settings exit $rc";; *) bad "broken settings not named: '$out'";; esac

# 6 the real template against an empty brain: reports (the shipped template is read)
brain b6 '{"permissions":{}}'
out="$("$PY" "$S" --repo "$(native "$T/b6")" 2>&1)"
case "$out" in *'permission rule(s) of the core template'*'allow '[1-9]*) ok "the shipped template is read by default";; *) bad "shipped template not read: '$out'";; esac

[ "$fail" = 0 ] && echo "template-drift: all cases pass" || { echo "template-drift: FAILURES"; exit 1; }
