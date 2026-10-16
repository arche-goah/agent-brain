#!/usr/bin/env bash
# Fixture for scripts/autonomy-diagnose-run.sh: every way the run can break on a foreign machine
# must end with exit 0, five summary lines, and a named reason — never a silent abort. A fake
# `claude` (a bash script; the runner calls it from bash) stands in for the real one.
# Usage: bash scripts/test-autonomy-diagnose-run.sh   (exit 0 = all pass)
set -u
here="$(cd "$(dirname "$0")" && pwd)"
RUN="$here/autonomy-diagnose-run.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }

# fake claude: --version, --help (FAKE_OLD=1 drops the new flags), -p reads the brief from stdin
FC="$T/fake-claude"
printf '%s\n' '#!/usr/bin/env bash' \
  'case "${1:-}" in --version) echo "9.9.9 (Claude Code fake)"; exit 0;; --help)' \
  '  echo "  -p, --print"; echo "  --tools <tools...>"; echo "  --add-dir <dirs...>"' \
  '  [ "${FAKE_OLD:-}" = 1 ] || { echo "  --safe-mode"; echo "  --permission-prompts <t>"; echo "  --no-session-persistence"; }; exit 0;; esac' \
  'brief="$(cat)"; [ "${FAKE_FAIL:-}" = 1 ] && { echo "fake: model overloaded" >&2; exit 3; }' \
  'case "$brief" in ---*) echo "error: unknown option" >&2; exit 1;; esac' \
  'echo "# Fake report"; echo "args: $*"; echo "brief-first-line: $(printf "%s\n" "$brief" | head -1)"' > "$FC"
chmod +x "$FC"

B="$T/brain"; mkdir -p "$B/.claude"; printf '# Brain\n' > "$B/CLAUDE.md"
P="$T/brief.md"
printf -- '---\nname: x\n---\n\nHuman instructions.\n\n<!-- agent-brief -->\n# BRIEF\nRead everything.\n' > "$P"
PN="$T/brief-nomarker.md"; printf '# Whole brief\nRead.\n' > "$PN"

case_run() { # $1 name, then env assignments and args via the caller; writes $T/<name>.out
  local name="$1"; shift
  ( cd "$B" && env DIAG_OUT_ROOT="$T/out-$name" DIAG_CLAUDE="$FC" "$@" ) > "$T/$name.out" 2>&1
  echo $? > "$T/$name.rc"
  SUMF="$(ls -d "$T/out-$name"/run-*/summary.txt 2>/dev/null | head -1)"
}
check() { # $1 case, $2 fixed string expected in summary.txt
  if [ -n "$SUMF" ] && grep -qF -- "$2" "$SUMF"; then ok "$1: $2"; else bad "$1: expected '$2' in summary: $(cat "$SUMF" 2>/dev/null)"; fi
}
always() { # exit 0 and five summary lines
  [ "$(cat "$T/$1.rc")" = 0 ] && ok "$1: exit 0" || bad "$1: exit $(cat "$T/$1.rc")"
  [ "$(grep -c '' "$SUMF" 2>/dev/null)" = 5 ] && ok "$1: five summary lines" || bad "$1: summary has $(grep -c '' "$SUMF" 2>/dev/null) lines"
}

case_run full bash "$RUN" --prompt "$P"
always full
check full "python  ok"; check full "script  ok"; check full "prompt  ok"; check full "from the agent-brief marker"
check full "claude  ok"; check full "agent   ok"
D="$(dirname "$SUMF")"
grep -q "^# Fake report" "$D/diagnose-bericht.md" && ok "full: agent report written" || bad "full: no agent report"
grep -q -- "--safe-mode --tools Read,Grep,Glob --add-dir" "$D/diagnose-bericht.md" && ok "full: safe, read-only flags passed" || bad "full: flags: $(grep args "$D/diagnose-bericht.md")"
grep -q "brief-first-line: # BRIEF" "$D/diagnose-bericht.md" && ok "full: only the brief went in, front matter cut" || bad "full: brief: $(grep brief-first "$D/diagnose-bericht.md")"
[ -s "$D/autonomy-report.md" ] && ok "full: script report written" || bad "full: no script report"
grep -q "^claude: *9.9.9" "$D/env.txt" && ok "full: env.txt records the claude version" || bad "full: env.txt"

case_run oldclaude env FAKE_OLD=1 bash "$RUN" --prompt "$P"
always oldclaude; check oldclaude "claude  FAILED"; check oldclaude "lacks: --safe-mode --permission-prompts --no-session-persistence"
check oldclaude "agent   SKIPPED"; check oldclaude "script  ok"

case_run noclaude env DIAG_CLAUDE="$T/no-such-claude" bash "$RUN" --prompt "$P"
always noclaude; check noclaude "not found in PATH"; check noclaude "agent   SKIPPED"

case_run noprompt bash "$RUN"
always noprompt; check noprompt "prompt  FAILED   no --prompt FILE given"; check noprompt "agent   SKIPPED"

case_run badprompt bash "$RUN" --prompt "$T/missing.md"
always badprompt; check badprompt "does not exist"

case_run nomarker bash "$RUN" --prompt "$PN"
always nomarker; check nomarker "whole file (no agent-brief marker)"; check nomarker "agent   ok"

case_run nopython env DIAG_PYTHONS="no-such-python-1 no-such-python-2" bash "$RUN" --prompt "$P"
always nopython; check nopython "python  FAILED"; check nopython "script  SKIPPED"; check nopython "agent   ok"

# a python that resolves but does not run (the Windows Store stub) must be passed over, not picked
STUB="$T/stubpy"; printf '#!/usr/bin/env bash\necho "Python was not found; run without arguments to install from the Microsoft Store" >&2\nexit 9\n' > "$STUB"; chmod +x "$STUB"
REALPY="$(for c in python3 python; do "$c" -c 'import sys' >/dev/null 2>&1 && { echo "$c"; break; }; done)"
case_run stubpy env DIAG_PYTHONS="$STUB $REALPY" bash "$RUN" --prompt "$P"
always stubpy; check stubpy "via '$REALPY'"; check stubpy "script  ok"

case_run agentfail env FAKE_FAIL=1 bash "$RUN" --prompt "$P"
always agentfail; check agentfail "agent   FAILED"; check agentfail "fake: model overloaded"

printf '{"permissions": ' > "$B/.claude/settings.json"
case_run messy bash "$RUN" --prompt "$P"
always messy; check messy "script  ok"
grep -q "is not valid JSON" "$(dirname "$SUMF")/autonomy-report.md" && ok "messy: invalid settings named in the report" || bad "messy: invalid JSON not named"
rm -f "$B/.claude/settings.json"

NB="$T/notabrain"; mkdir -p "$NB"
( cd "$NB" && env DIAG_OUT_ROOT="$T/out-nb" DIAG_CLAUDE="$FC" bash "$RUN" --prompt "$P" ) > "$T/nb.out" 2>&1; rc=$?
SUMF="$(ls -d "$T/out-nb"/run-*/summary.txt | head -1)"
[ $rc = 0 ] && ok "not a brain: exit 0" || bad "not a brain: exit $rc"
grep -q "no CLAUDE.md" "$(dirname "$SUMF")/run.log" && ok "not a brain: warned in run.log" || bad "not a brain: no warning"

echo
[ "$fail" -eq 0 ] && echo "test-autonomy-diagnose-run: all checks passed" || echo "test-autonomy-diagnose-run: FAILURES"
exit "$fail"
