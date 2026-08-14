#!/usr/bin/env bash
# setup-shell-start.sh — new terminals that start in $HOME automatically change
# into your own brain. That way a bare `claude` in a fresh terminal ALWAYS starts
# in the right repo (project settings, hooks, output style — instead of a bare
# session).
#
# Usage: bash scripts/setup-shell-start.sh ~/Projects/<your-name>-brain
#
# What it does (idempotent, marker "brain shell-start"):
#   - ~/.bashrc:  cd into the brain when the shell starts in $HOME
#   - Windows:    ~/.bash_profile loads ~/.bashrc (Git Bash is a login shell);
#                 PowerShell profiles (powershell.exe AND pwsh, when present)
#   - macOS:      additionally ~/.zshrc
#   - ExecutionPolicy "Restricted" -> "RemoteSigned" (CurrentUser), otherwise
#     Windows PowerShell loads no profile at all and the fix stays silently inert
#
# Deliberately ONLY on a start in $HOME: whoever cd-s into another repo works
# there unchanged. To remove: delete the marked blocks from the profile files.
set -euo pipefail

BRAIN_IN="${1:?Usage: setup-shell-start.sh <brain-directory>}"
BRAIN="$(cd "$BRAIN_IN" 2>/dev/null && pwd)" || { echo "FAIL $BRAIN_IN does not exist"; exit 1; }
[ -f "$BRAIN/CLAUDE.md" ] || { echo "FAIL $BRAIN has no CLAUDE.md — wrong directory?"; exit 1; }

MARK="brain shell-start"
BEGIN="# >>> $MARK >>>"
END="# <<< $MARK <<<"

add_posix() { # $1 = profile file
  local f="$1"
  if grep -q "$MARK" "$f" 2>/dev/null; then echo "OK   $f — already set up"; return 0; fi
  {
    printf '\n%s\n' "$BEGIN"
    printf '# New shells starting in $HOME change into the brain (claude then starts there).\n'
    printf 'if [ "$PWD" = "$HOME" ] && [ -d "%s" ]; then cd "%s"; fi\n' "$BRAIN" "$BRAIN"
    printf '%s\n' "$END"
  } >> "$f"
  echo "NEW  $f"
}

add_powershell() { # $1 = powershell.exe | pwsh
  local exe="$1" pp pp_u brain_w pol
  command -v "$exe" >/dev/null 2>&1 || return 0
  pp=$("$exe" -NoProfile -Command 'Write-Output $PROFILE' 2>/dev/null | tr -d '\r' | tail -1)
  [ -n "$pp" ] || return 0
  pp_u=$(cygpath -u "$pp" 2>/dev/null || printf '%s' "$pp")
  mkdir -p "$(dirname "$pp_u")"
  brain_w=$(cygpath -w "$BRAIN" 2>/dev/null || printf '%s' "$BRAIN")
  if grep -q "$MARK" "$pp_u" 2>/dev/null; then echo "OK   $pp ($exe) — already set up"
  else
    {
      printf '\n%s\n' "$BEGIN"
      printf "if ((Get-Location).Path -eq \$HOME -and (Test-Path '%s')) { Set-Location '%s' }\n" "$brain_w" "$brain_w"
      printf '%s\n' "$END"
    } >> "$pp_u"
    echo "NEW  $pp ($exe)"
  fi
  pol=$("$exe" -NoProfile -Command 'Get-ExecutionPolicy' 2>/dev/null | tr -d '\r' | tail -1)
  if [ "$pol" = "Restricted" ]; then
    if "$exe" -NoProfile -Command 'Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force' >/dev/null 2>&1; then
      echo "SET  ExecutionPolicy CurrentUser=RemoteSigned (was Restricted — with that, $exe would NEVER have loaded a profile)"
    else
      echo "WARN ExecutionPolicy is Restricted and could not be set — $exe loads no profile this way (group policy?)"
    fi
  fi
}

wire_bash_profile() {
  # Login shells (Git Bash always, bash on macOS likewise) read ~/.bashrc ONLY via
  # ~/.bash_profile — without this bridge the block stays invisible to them.
  if [ ! -f "$HOME/.bash_profile" ]; then
    printf '[ -f ~/.bashrc ] && . ~/.bashrc\n' > "$HOME/.bash_profile"
    echo "NEW  $HOME/.bash_profile (loads ~/.bashrc)"
  elif ! grep -q "bashrc" "$HOME/.bash_profile"; then
    printf '\n[ -f ~/.bashrc ] && . ~/.bashrc\n' >> "$HOME/.bash_profile"
    echo "ADD  $HOME/.bash_profile now loads ~/.bashrc"
  fi
}

echo "=== setup-shell-start: $BRAIN ==="
add_posix "$HOME/.bashrc"

case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*)
    wire_bash_profile
    add_powershell powershell.exe
    add_powershell pwsh
    ;;
  Darwin)
    wire_bash_profile
    add_posix "$HOME/.zshrc"
    ;;
esac

echo
echo "Measurement (fresh login shell, started in \$HOME):"
measured=$(cd "$HOME" && bash -l -c 'pwd' 2>/dev/null | tail -1)
if [ "$measured" = "$BRAIN" ]; then
  echo "  OK   lands in $measured"
else
  echo "  INFO lands in ${measured:-?} — normal with a distro .bashrc that guards for interactive shells;"
  echo "       what counts is the next REAL terminal. The marker is in place."
fi
echo "Done. Takes effect from the next new terminal."
