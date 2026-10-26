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
# Every case reads a fake user config dir, never the real ~/.claude (its autoMode block would leak in).
mkdir -p "$T/user-none"
export CLAUDE_CONFIG_DIR="$(native "$T/user-none")"
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

# 7-11 the user half: autoMode lives only in ~/.claude/settings.json (classifier docs, 2026-10-26)
UT="$T/user-template.json"
printf '%s\n' '{"autoMode":{"environment":["$defaults","Source control: github.com/<org>"],"allow":["$defaults","Own PRs in github.com/<org> may be marked ready"]}}' > "$UT"
brain b7 '{"extraKnownMarketplaces":{"m":{"source":{"source":"github","repo":"acme/claude-marketplace"}}},"permissions":{"allow":["Bash(gh pr ready*)","Bash(gh pr create*)","Bash(git status*)"],"ask":["Edit(.claude/settings.json)"],"deny":["Bash(git push --force*)"]}}'
U="$T/user7"; mkdir -p "$U"; printf '%s\n' '{"theme":"dark"}' > "$U/settings.json"
urun() { CLAUDE_CONFIG_DIR="$(native "$U")" "$PY" "$S" --repo "$(native "$T/b7")" --template "$(native "$TPL")" --user-template "$(native "$UT")" "$@" 2>&1; }
out="$(urun)"
case "$out" in *'4 autoMode entr(y/ies)'*'--apply-user'*) ok "missing autoMode entries are named, with the command";; *) bad "missing autoMode not named: '$out'";; esac
out="$(urun --apply-user)"
case "$out" in *'written to'*'(org acme)'*) ok "--apply-user writes, org from the marketplace repo";; *) bad "--apply-user did not write: '$out'";; esac
grep -q 'github.com/acme' "$U/settings.json" && grep -q '"theme": "dark"' "$U/settings.json" \
  && ok "the org is filled in and the person's own keys stay" || bad "user settings wrong: $(cat "$U/settings.json")"
ls "$U"/settings.2*.json >/dev/null 2>&1 && ok "a dated copy of the previous file is kept" || bad "no dated copy"
out="$(urun)"
[ -z "$out" ] && ok "after --apply-user the report is silent" || bad "still reported: '$out'"
out="$(urun --apply-user)"
case "$out" in *'nothing written'*) ok "a second --apply-user writes nothing";; *) bad "second apply: '$out'";; esac
out="$(CLAUDE_CONFIG_DIR="$(native "$U")" "$PY" "$S" --repo "$(native "$T/b2")" --template "$(native "$TPL")" --user-template "$(native "$UT")" 2>&1)"
[ -z "$out" ] && ok "no marketplace repo, no org: the user half stays silent (control)" || bad "no-org case reported: '$out'"

[ "$fail" = 0 ] && echo "template-drift: all cases pass" || { echo "template-drift: FAILURES"; exit 1; }
