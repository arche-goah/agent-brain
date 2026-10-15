#!/usr/bin/env bash
# covers: git_sandbox
# Fixture for scripts/git_sandbox.py — both directions.
# The planted case is the incident (2026-10-14): a host whose GLOBAL core.hooksPath carries a
# pre-commit that refuses the commit. Under it, every python fixture that commits in a temp
# repo must still pass — the host's hook never reaches the fixture repo. The negative control
# proves the hook is really reached without the helper: a plain commit under the same global
# config must fail. A third check: the helper is a no-op for LOCAL config, so a repo that sets
# its own hooksPath still runs that hook.
# Usage: bash scripts/test-git-sandbox.sh (exit 0 = pass)
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY=python3; "$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }
# A path git reads from DATA (the config file) goes through cygpath on Windows (os-traps OS-3).
nat() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }

mkdir -p "$T/hooks"
printf '#!/bin/sh\necho "host hook refuses" >&2\nexit 1\n' > "$T/hooks/pre-commit"
chmod +x "$T/hooks/pre-commit"
printf '[user]\n\tname = host\n\temail = host@example.invalid\n[core]\n\thooksPath = %s\n' \
  "$(nat "$T/hooks")" > "$T/gitconfig"
export GIT_CONFIG_GLOBAL="$(nat "$T/gitconfig")" GIT_CONFIG_NOSYSTEM=1
unset GIT_SANDBOX

# --- negative control: without the helper the host hook IS reached -------------------------
git init -q "$T/plain"
: > "$T/plain/f"
git -C "$T/plain" add f
if git -C "$T/plain" commit -qm c >/dev/null 2>&1; then
  bad "negative control: the refusing host hook must block a plain commit (it did not run)"
else
  ok "negative control: the refusing host hook blocks a plain commit"
fi

# --- the helper alone: a commit under the same global config goes through ------------------
git init -q "$T/boxed"
: > "$T/boxed/f"
git -C "$T/boxed" add f
if "$PY" -c "import sys; sys.path.insert(0, sys.argv[1]); import git_sandbox, subprocess
subprocess.run(['git', '-C', sys.argv[2], 'commit', '-qm', 'c'], check=True)" "$HERE" "$T/boxed" \
   >/dev/null 2>&1; then
  ok "helper: the same commit passes once the process is isolated"
else
  bad "helper: the commit still met the host hook"
fi

# --- local config stays: a repo's OWN hooksPath still runs ---------------------------------
git init -q "$T/own"
mkdir -p "$T/own/.githooks"
printf '#!/bin/sh\nexit 1\n' > "$T/own/.githooks/pre-commit"
chmod +x "$T/own/.githooks/pre-commit"
git -C "$T/own" config core.hooksPath .githooks
: > "$T/own/f"
git -C "$T/own" add f
if "$PY" -c "import sys; sys.path.insert(0, sys.argv[1]); import git_sandbox, subprocess
subprocess.run(['git', '-C', sys.argv[2], 'commit', '-qm', 'c'], check=True)" "$HERE" "$T/own" \
   >/dev/null 2>&1; then
  bad "local config: the repo's own hook must still run under the helper"
else
  ok "local config: the repo's own hook still runs under the helper"
fi

# --- the planted case: every committing python fixture passes under the hostile host -------
for t in shared-memory-audience-test shared-memory-index-test shared-memory-lint-test \
         staged-names-test device-status-test; do
  if "$PY" "$HERE/$t.py" >/dev/null 2>&1; then
    ok "planted: $t passes under a global hooksPath that refuses every commit"
  else
    bad "planted: $t fails under a global hooksPath that refuses every commit"
  fi
done

if [ "$fail" -eq 0 ]; then echo "test-git-sandbox: all green"; else echo "test-git-sandbox: FAILED"; fi
exit "$fail"
