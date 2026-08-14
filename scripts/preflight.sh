#!/usr/bin/env bash
# preflight.sh — checks onboarding prerequisites, REPORTS what is missing,
# installs NOTHING. Companion of ONBOARDING.md (repo root).
# Exit 0 = everything green, 1 = at least one item red.
set -uo pipefail
fail=0
ok()   { printf '  OK   %s\n' "$1"; }
bad()  { printf '  FAIL %s\n     -> %s\n' "$1" "$2"; fail=1; }
# WARN = noteworthy, but no reason to stop the onboarding (does NOT set fail).
warn() { printf '  WARN %s\n     -> %s\n' "$1" "$2"; }

echo "=== Onboarding preflight ==="

case "$(uname -s 2>/dev/null)" in
  Darwin) ok "macOS detected" ;;
  Linux)  ok "Linux detected" ;;
  MINGW*|MSYS*|CYGWIN*) ok "Windows (Git Bash) detected" ;;
  *) bad "unknown OS" "use Git Bash (Windows) or a macOS/Linux shell" ;;
esac

if command -v node >/dev/null 2>&1; then
  v=$(node --version | sed 's/v//')
  major=${v%%.*}; minor=$(echo "$v" | cut -d. -f2)
  if [ "$major" -gt 23 ] || { [ "$major" -eq 23 ] && [ "$minor" -ge 6 ]; }; then
    ok "node $v (>= 23.6)"
  else
    bad "node $v too old" "install Node >= 23.6 (nodejs.org) — suite MCP servers rely on native type stripping"
  fi
else
  bad "node missing" "install Node >= 23.6 (nodejs.org / winget install OpenJS.NodeJS) — then open a NEW terminal, otherwise node stays missing from PATH"
fi

command -v git >/dev/null 2>&1 && ok "git $(git --version | awk '{print $3}')" || bad "git missing" "install git (git-scm.com)"

# Python: the verify step (leak-scan, suite-check, ecosystem-sync) runs on stock
# Python. On Windows the PATH often carries ONLY the Microsoft Store stub
# (python3.exe that opens the Store when called) — so do not trust `command -v`,
# EXECUTE it.
PY=""
for c in python3 python; do
  if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys' >/dev/null 2>&1; then PY="$c"; break; fi
done
if [ -n "$PY" ]; then
  ok "python: $PY $("$PY" -c 'import platform; print(platform.python_version())')"
else
  bad "python missing (or only the Microsoft Store stub)" "install Python 3 (python.org, tick 'Add python.exe to PATH') — then open a NEW terminal. No extra packages needed, the core scripts are stdlib-only"
fi

# Windows path limit: git ships its OWN switch and ignores the Windows setting
# LongPathsEnabled. Measured 2026-08-10 (Win 11, git 2.43): with LongPathsEnabled=1
# in the registry but core.longpaths=false, a clone into a 193-character target
# path aborts with "Filename too long" — mid-clone, with a message that looks like
# an access problem. Hence this check runs BEFORE the first clone.
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*)
    if [ "$(git config --get core.longpaths 2>/dev/null || true)" = "true" ]; then
      ok "git core.longpaths active (long paths)"
    else
      bad "git core.longpaths off" "git config --global core.longpaths true — the Windows setting 'LongPathsEnabled' alone is NOT enough, git has its own switch. Without it, clones of deep repos abort with 'Filename too long'"
    fi
    ;;
esac

if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then ok "gh CLI logged in"; else bad "gh CLI not logged in" "gh auth login (browser login)"; fi
else
  bad "gh CLI missing" "install it: brew install gh / winget install GitHub.cli — then open a NEW terminal (PATH), then gh auth login"
fi

# The question is "can I reach GitHub over SSH", not "is an agent running". So the
# access itself is measured first; the agent is only a hint afterwards.
#
# Two traps that both used to bite here:
#  1. `ssh -T git@github.com` ALWAYS exits 1 (GitHub gives no shell). In a pipe,
#     `set -o pipefail` turns the grep hit red with that — the check could never go
#     green on ANY system. So capture the output first, then check it.
#  2. On first contact there is no known_hosts entry yet; BatchMode then refuses to
#     accept the host key ("Host key verification failed") — perfect key, red check.
#     Hence StrictHostKeyChecking=accept-new.
ssh_out=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -T git@github.com 2>&1 || true)
if printf '%s\n' "$ssh_out" | grep -q "successfully authenticated"; then
  ok "SSH access to GitHub proven$(printf '%s' "$ssh_out" | sed -n 's/^Hi \([^!]*\)!.*/ (as \1)/p')"
  if ssh-add -l >/dev/null 2>&1; then
    ok "ssh-agent running, key loaded"
  else
    warn "ssh-agent not reachable — harmless, access is already proven" \
      "Only needed if your key has a passphrase: eval \"\$(ssh-agent -s)\" && ssh-add ~/.ssh/id_ed25519 . On Windows, Git Bash fundamentally cannot see the Windows service (named pipe vs. Unix socket) — that stays this way and is not an error."
  fi
else
  bad "SSH to GitHub not proven (message: $(printf '%s' "$ssh_out" | head -1))" \
    "Create a key: ssh-keygen -t ed25519 -C \"$(whoami)\" · show the public key: cat ~/.ssh/id_ed25519.pub · add it at https://github.com/settings/ssh/new · then run this script again"
fi

command -v claude >/dev/null 2>&1 && ok "claude CLI $(claude --version 2>/dev/null | head -1)" || bad "claude CLI missing" "install Claude Code (claude.com/claude-code) — then open a NEW terminal, otherwise the shell does not know the 'claude' command"

echo
if [ "$fail" -eq 0 ]; then echo "Preflight: ALL GREEN"; else echo "Preflight: RED — work through the items above, then measure AGAIN (run the script once more)"; fi
exit "$fail"
