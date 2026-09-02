#!/usr/bin/env bash
# onboarding-verify.sh — checks the onboarding contract (docs/onboarding-contract.md)
# and writes onboarding-report.txt INTO the verified brain (the report describes that
# brain's state, so it belongs there — not in this repo's checkout). Read-only apart
# from the report file. Exit 0 = every mandatory check green.
#
# Call: bash scripts/onboarding-verify.sh [path-to-your-brain]
# Without an argument the brain is looked up via BRAIN_DIR or under ~/Projects/*-brain.
set -uo pipefail
fail=0

# Resolve the brain FIRST — the report lands inside it.
BRAIN="${1:-${BRAIN_DIR:-}}"
if [ -z "$BRAIN" ]; then BRAIN=$(ls -d "$HOME"/Projects/*-brain 2>/dev/null | head -1); fi
if [ -n "$BRAIN" ] && [ -d "$BRAIN" ]; then REPORT="$BRAIN/onboarding-report.txt"
else REPORT="$PWD/onboarding-report.txt"; fi

{
echo "=== Onboarding verify $(date '+%F %T') ==="
echo "Host: $(uname -s) $(uname -m), node $(node --version 2>/dev/null || echo MISSING)"

check() { # $1 nr, $2 name, $3 = 0/1 result, $4 detail
  if [ "$3" -eq 0 ]; then printf 'OK   %2s %s — %s\n' "$1" "$2" "$4"
  else printf 'FAIL %2s %s — %s\n' "$1" "$2" "$4"; fail=1; fi
}
skip() { # $1 nr, $2 name, $3 reason — check not applicable, does NOT set fail
  printf 'SKIP %2s %s — %s\n' "$1" "$2" "$3"
}

# Resolve the Python interpreter: the python.org installer on Windows ships ONLY
# `python`, no `python3` — items 8-10 would be red although Python is cleanly installed.
PY=python3
"$PY" -c 'import sys' >/dev/null 2>&1 || PY=python

# 1 Access
gh auth status >/dev/null 2>&1; gh_ok=$?
# `ssh -T git@github.com` ALWAYS exits 1 (GitHub gives no shell) — in a pipe,
# `set -o pipefail` turns that into a red no matter what grep finds. So capture the
# output. accept-new: on first contact the known_hosts entry is missing and BatchMode
# would abort ("Host key verification failed") — green key, red check.
ssh_out=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -T git@github.com 2>&1 || true)
printf '%s\n' "$ssh_out" | grep -q "successfully authenticated"; ssh_ok=$?
check 1 "Access" $(( gh_ok || ssh_ok )) "gh=$([ $gh_ok -eq 0 ] && echo ok || echo red), ssh=$([ $ssh_ok -eq 0 ] && echo ok || echo red)"

# 2 Plugins enabled — mandatory is ONLY the core plugin; additional suites are
# opt-in on explicit request and are checked here only WHEN installed.
pl=$(claude plugin list 2>/dev/null)
# Either channel counts — brain-core-next is the same repo on a test tag (a beta
# machine has next enabled and brain-core disabled; the literal match read that as
# MISSING — same class as the updater's silent submodule skip, 2026-09-02).
echo "$pl" | grep -qE "brain-core(-next)?@"; p1=$?
check 2 "Plugins" $p1 "core channel=$([ $p1 -eq 0 ] && echo present || echo MISSING) (brain-core or brain-core-next; suites are opt-in — default is core only)"

# Find the plugin cache root
cache="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache"
bc_dir=$(find "$cache" -maxdepth 4 -type d \( -name "brain-core" -o -name "brain-core-next" \) 2>/dev/null | head -1)
# Suites, generically: every cached plugin BESIDES brain-core that ships an MCP
# server manifest counts as an installed suite (suite shape per CONVENTIONS section 2).
suite_dirs=$(find "$cache" -maxdepth 5 -name ".mcp.json" -not -path "*brain-core*" 2>/dev/null | xargs -I{} dirname {} 2>/dev/null | sort -u)
# The cache nests versions (cache/<marketplace>/<plugin>/<version>/) — a bare
# basename yields "1.1.0" instead of the plugin name (measured 2026-08-14), so
# climb past components that look like a version number.
suite_name() {
  local d="$1" b
  b=$(basename "$d")
  while printf '%s' "$b" | grep -qE '^[0-9]+(\.[0-9]+)*$'; do
    d=$(dirname "$d"); b=$(basename "$d")
  done
  printf '%s' "$b"
}
suite_names=""
for d in $suite_dirs; do suite_names="$suite_names$(suite_name "$d") "; done

# 3 Skills from the core plugin (suite skills only when a suite is installed)
s1=""; [ -n "$bc_dir" ] && s1=$(find "$bc_dir" -name "SKILL.md" 2>/dev/null | head -1)
if [ -n "$suite_dirs" ]; then
  s2=""
  for d in $suite_dirs; do
    s2=$(find "$d" -name "SKILL.md" 2>/dev/null | head -1)
    [ -n "$s2" ] || break
  done
  check 3 "Plugin skills" $(( $([ -n "$s1" ] && echo 0 || echo 1) || $([ -n "$s2" ] && echo 0 || echo 1) )) "core=$([ -n "$s1" ] && echo present || echo MISSING), suites=$([ -n "$s2" ] && echo present || echo MISSING) ($suite_names)"
else
  check 3 "Plugin skills" $([ -n "$s1" ] && echo 0 || echo 1) "core=$([ -n "$s1" ] && echo present || echo MISSING), suites=none installed"
fi

# 4 Output style from the plugin
st=""; [ -n "$bc_dir" ] && st=$(find "$bc_dir" -name "caveman.md" -path "*output-styles*" 2>/dev/null | head -1)
check 4 "Output style" $([ -n "$st" ] && echo 0 || echo 1) "${st:-caveman.md not in the plugin cache}"

# 5 Own brain + bootup hook
if [ -n "$BRAIN" ] && [ -f "$BRAIN/.claude/settings.json" ] && grep -q "core/helpers/session-bootup.sh" "$BRAIN/.claude/settings.json" 2>/dev/null; then
  out=$(cd "$BRAIN" && /bin/zsh core/helpers/session-bootup.sh 2>/dev/null || bash core/helpers/session-bootup.sh 2>/dev/null)
  echo "$out" | grep -q "BRAIN BOOTUP CHECK"; b_ok=$?
  check 5 "Brain+hooks" $b_ok "$BRAIN (bootup output $([ $b_ok -eq 0 ] && echo appears || echo MISSING))"
else
  check 5 "Brain+hooks" 1 "no brain with core-wired hooks found (set the argument or BRAIN_DIR?)"
fi

# 6+7 only when a suite is installed — the default scope is core only
if [ -n "$suite_dirs" ]; then
  # 6 Runtime deps of the suites: a suite that declares npm dependencies needs
  # node_modules (the plugin's install hook puts them into the plugin data dir).
  d_ok=0; d_detail=""
  for d in $suite_dirs; do
    name=$(suite_name "$d")
    if [ -f "$d/package.json" ] || [ -f "$d/mcp/package.json" ]; then
      nm=$(find "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins" -maxdepth 6 -type d -name "node_modules" -path "*$name*" 2>/dev/null | head -1)
      if [ -n "$nm" ]; then d_detail="$d_detail$name=deps-ok "
      else d_ok=1; d_detail="$d_detail$name=node_modules-MISSING (restart Claude Code after the plugin install?) "; fi
    else
      d_detail="$d_detail$name=no-npm-deps "
    fi
  done
  check 6 "Suite runtime deps" $d_ok "$d_detail"

  # 7 Suite MCP startable (without the device/console: server source + node)
  nmaj=$(node --version 2>/dev/null | sed 's/v//' | cut -d. -f1)
  check 7 "Suite MCP" $([ "${nmaj:-0}" -ge 23 ] && echo 0 || echo 1) "server manifests: $suite_names; node>=23=$([ "${nmaj:-0}" -ge 23 ] && echo yes || echo no); a live round-trip needs the connected device"
else
  skip 6 "Suite runtime deps" "no suite installed (default: core only — suites on explicit request)"
  skip 7 "Suite MCP" "no suite installed (default: core only — suites on explicit request)"
fi

# 8 Leak check across the own brain: no FOREIGN home paths may have landed in it
# (templates and copied examples are the usual carrier).
if [ -n "$BRAIN" ] && [ -d "$BRAIN" ]; then
  me=$(id -un)
  # Filters: the own username is this brain's business; /Users/Shared is a macOS
  # system path; pure-punctuation "names" are doc ellipsis placeholders, not users.
  hits=$(grep -rhoE '/(Users|home)/[A-Za-z0-9._-]+' "$BRAIN" --exclude-dir=.git --exclude-dir=core --exclude-dir=node_modules 2>/dev/null | grep -vE "^/(Users|home)/$me$" | grep -v '^/Users/Shared$' | grep -vE '^/(Users|home)/[._-]+$' | sort -u | head -3 | tr '\n' ' ')
  check 8 "Leak check brain" $([ -z "$hits" ] && echo 0 || echo 1) "${hits:-no foreign home paths in the own brain}"
else
  check 8 "Leak check brain" 1 "no brain directory to scan"
fi

# 9 suite-check from the own core checkout
if [ -n "$BRAIN" ] && [ -f "$BRAIN/core/scripts/suite-check.py" ]; then
  (cd "$BRAIN/core" && "$PY" scripts/suite-check.py . >/dev/null 2>&1); sc=$?
  check 9 "suite-check" $sc "core checkout verifies itself (exit $sc, $PY)"
else
  check 9 "suite-check" 1 "core/scripts/suite-check.py missing (submodule initialized?)"
fi

# 10 Ecosystem nameable
if [ -n "$BRAIN" ] && [ -f "$BRAIN/config/ecosystem.json" ]; then
  (cd "$BRAIN" && "$PY" core/scripts/ecosystem-sync.py >/dev/null 2>&1); es=$?
  # Drift is normal at the start — nameable (exit 0 or 1 with output) is enough; a parse error is not.
  check 10 "ecosystem" $([ $es -le 1 ] && echo 0 || echo 1) "config/ecosystem.json present, sync exit=$es (drift is fine at the start)"
else
  check 10 "ecosystem" 1 "config/ecosystem.json missing in the brain"
fi

# 11 Shell start into the brain — `claude` in a fresh terminal must land in the
# brain, not in a bare $HOME session (the stumbling block of the first onboarding).
ss=""
for f in "$HOME/.bashrc" "$HOME/.zshrc"; do
  grep -q "brain shell-start" "$f" 2>/dev/null && ss="$f" && break
done
if [ -z "$ss" ] && command -v powershell.exe >/dev/null 2>&1; then
  pp=$(powershell.exe -NoProfile -Command 'Write-Output $PROFILE' 2>/dev/null | tr -d '\r' | tail -1)
  pp_u=$(cygpath -u "$pp" 2>/dev/null || printf '%s' "$pp")
  grep -q "brain shell-start" "$pp_u" 2>/dev/null && ss="$pp"
fi
if [ -n "$ss" ]; then check 11 "Shell start" 0 "marker in $ss"
else check 11 "Shell start" 1 "missing — run bash scripts/setup-shell-start.sh <brain>"; fi

echo
if [ "$fail" -eq 0 ]; then echo "VERIFY: ALL MANDATORY CHECKS GREEN — send the report back to whoever invited you."
else echo "VERIFY: RED — work through the FAIL lines above (a Claude Code session in the brain can drive the fixes)."; fi
} > "$REPORT"
# Redirect instead of `| tee`: a pipe runs the block in a SUBSHELL, the fail=1 set
# there is lost, and exit afterwards read the parent shell's untouched 0 — the
# verifier reported success while the report said FAIL.
cat "$REPORT"
echo "(report written to $REPORT)"
exit "$fail"
