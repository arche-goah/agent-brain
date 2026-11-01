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
run() { "$PY" "$S" --repo "$(native "$T/$1")" --template "$(native "$TPL")" --rules-template "$(native "$T/no-rules")" 2>&1; }

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
urun() { CLAUDE_CONFIG_DIR="$(native "$U")" "$PY" "$S" --repo "$(native "$T/b7")" --template "$(native "$TPL")" --rules-template "$(native "$T/no-rules")" --user-template "$(native "$UT")" "$@" 2>&1; }
out="$(urun)"
case "$out" in *'(4 missing)'*'--apply-user'*) ok "missing autoMode entries are named, with the command";; *) bad "missing autoMode not named: '$out'";; esac
# The printed command names the interpreter the caller resolved (PYTHON — the session start passes
# its own), else the running one; never a fixed python3 (fresh-brain trial 2026-10-31 on Windows,
# where python3 was the Store stub and the session start had resolved python).
out="$(PYTHON=pyfix urun)"
case "$out" in *'! pyfix core/scripts/template-drift.py --apply-user'*) ok "the command names the interpreter the caller resolved";; *) bad "PYTHON not used: '$out'";; esac
own=$("$PY" -c 'import os,sys; e=os.path.basename(sys.executable); print(e[:-4] if e.lower().endswith(".exe") else e)' | tr -d '\r')
out="$(unset PYTHON; urun)"
case "$out" in *"! $own core/scripts/template-drift.py --apply-user"*) ok "without PYTHON it names the running interpreter ($own)";; *) bad "running interpreter not named ($own): '$out'";; esac
out="$(urun --apply-user)"
case "$out" in *'4 autoMode entr(y/ies) written'*'(org acme)'*) ok "--apply-user writes, org from the marketplace repo";; *) bad "--apply-user did not write: '$out'";; esac
grep -q 'github.com/acme' "$U/settings.json" && grep -q '"theme": "dark"' "$U/settings.json" \
  && ok "the org is filled in and the person's own keys stay" || bad "user settings wrong: $(cat "$U/settings.json")"
ls "$U"/settings.2*.json >/dev/null 2>&1 && ok "a dated copy of the previous file is kept" || bad "no dated copy"
out="$(urun)"
[ -z "$out" ] && ok "after --apply-user the report is silent" || bad "still reported: '$out'"
out="$(urun --apply-user)"
case "$out" in *'nothing written'*) ok "a second --apply-user writes nothing";; *) bad "second apply: '$out'";; esac
out="$(CLAUDE_CONFIG_DIR="$(native "$U")" "$PY" "$S" --repo "$(native "$T/b2")" --template "$(native "$TPL")" --rules-template "$(native "$T/no-rules")" --user-template "$(native "$UT")" 2>&1)"
[ -z "$out" ] && ok "no marketplace repo, no org: the user half stays silent (control)" || bad "no-org case reported: '$out'"

# 12-14 a narrowed entry: its wider old form is RETIRED and must go, not stay next to it (2026-10-26)
UR="$T/user-template-retired.json"
printf '%s\n' '{"autoMode":{"allow":["$defaults","Own PRs in github.com/<org> by members may be counter-checked"]},"_retired":{"allow":["Every PR in github.com/<org> may be counter-checked"]}}' > "$UR"
U2="$T/user12"; mkdir -p "$U2"
printf '%s\n' '{"autoMode":{"allow":["$defaults","Every PR in github.com/acme may be counter-checked","my own entry"]}}' > "$U2/settings.json"
rrun() { CLAUDE_CONFIG_DIR="$(native "$U2")" "$PY" "$S" --repo "$(native "$T/b7")" --template "$(native "$TPL")" --rules-template "$(native "$T/no-rules")" --user-template "$(native "$UR")" "$@" 2>&1; }
out="$(rrun)"
case "$out" in *'1 retired but still present'*) ok "a retired entry still present is named";; *) bad "retired entry not named: '$out'";; esac
out="$(rrun --apply-user)"
! grep -q 'Every PR in github.com/acme' "$U2/settings.json" && grep -q 'by members' "$U2/settings.json" && grep -q 'my own entry' "$U2/settings.json" \
  && ok "--apply-user removes the retired entry, adds the narrow one, keeps the person's own" || bad "retire wrong: $(cat "$U2/settings.json")"
out="$(rrun)"
[ -z "$out" ] && ok "after retiring the report is silent" || bad "still reported after retire: '$out'"

# Template DATA files a core helper reads (macOS finding on #142: autonomous-patterns.json never reached an older brain).
RT="$T/rules-tpl"; HL="$T/helpers"; mkdir -p "$RT" "$HL"
printf '%s\n' '{"on_patterns":[]}' > "$RT/autonomous-patterns.json"
printf '%s\n' '{}' > "$RT/nobody-reads.json"
printf '%s\n' "const p = path.join(cwd, '.claude', 'rules', 'autonomous-patterns.json');" > "$HL/autonomous-mode.cjs"
brain d1 '{"permissions":{"allow":["Bash(gh pr ready*)","Bash(gh pr create*)","Bash(git status*)"],"ask":["Edit(.claude/settings.json)"],"deny":["Bash(git push --force*)"]}}'
drun() { "$PY" "$S" --repo "$(native "$T/d1")" --template "$(native "$TPL")" --rules-template "$(native "$RT")" --helpers "$(native "$HL")" 2>&1; }
out="$(drun)"
case "$out" in *"autonomous-patterns.json"*) case "$out" in *nobody-reads*) bad "a file no helper reads is named";; *) ok "a helper-read data file the brain lacks is named";; esac;; *) bad "missing data file not named: '$out'";; esac
mkdir -p "$T/d1/.claude/rules"; cp "$RT/autonomous-patterns.json" "$T/d1/.claude/rules/"
out="$(drun)"
[ -z "$out" ] && ok "with the data file in place the report is silent" || bad "still reported: '$out'"

# --copy-data (bootstrap-brain.sh; fresh-brain trial 2026-10-31: bootstrap's own hand list carried
# 8 of the 16 files, the first start was red): copies exactly what the report names, never over a file.
printf '%s\n' '{"rules":[]}' > "$RT/skill-gate.json"
printf '%s\n' "const g = path.join(cwd, '.claude', 'rules', 'skill-gate.json');" > "$HL/skill-gate.cjs"
brain d2 '{"permissions":{}}'; mkdir -p "$T/d2/.claude/rules"
printf '%s\n' '{"on_patterns":["mine"]}' > "$T/d2/.claude/rules/autonomous-patterns.json"
crun() { "$PY" "$S" --repo "$(native "$T/d2")" --rules-template "$(native "$RT")" --helpers "$(native "$HL")" "$@" 2>&1; }
out="$(crun --copy-data)"
case "$out" in *"1 data file(s) copied"*"skill-gate.json"*) ok "--copy-data copies the helper-read file the brain lacks";; *) bad "--copy-data: '$out'";; esac
[ -f "$T/d2/.claude/rules/skill-gate.json" ] && [ ! -e "$T/d2/.claude/rules/nobody-reads.json" ] \
  && ok "--copy-data leaves out a file no helper reads" || bad "--copy-data copied the wrong set: $(ls "$T/d2/.claude/rules")"
grep -q '"mine"' "$T/d2/.claude/rules/autonomous-patterns.json" && ok "--copy-data never overwrites an existing file" \
  || bad "--copy-data overwrote: $(cat "$T/d2/.claude/rules/autonomous-patterns.json")"
out="$(crun)"
case "$out" in *"data file(s) of core/templates"*) bad "after --copy-data the report still names data files: '$out'";; *) ok "after --copy-data the data report is silent";; esac

[ "$fail" = 0 ] && echo "template-drift: all cases pass" || { echo "template-drift: FAILURES"; exit 1; }
