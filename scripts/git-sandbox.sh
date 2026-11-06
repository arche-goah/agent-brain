# git-sandbox.sh — sourced by a shell fixture: its throwaway git repos obey no git config of the host machine.
# The shell twin of scripts/git_sandbox.py (same variables, same reason); usage: `. "$(dirname "$0")/git-sandbox.sh"`.
#
# WHY (measured 2026-11-06 on the macOS instance): the host's global `core.hooksPath` points at the core's own
# helpers/git-hooks; their pre-push guard refused a fixture's `git push origin HEAD:main` into its temp bare repo
# ("push to main of tmp…/suite not in main_ok"), the fixture's quiet git wrapper hid it, and every case after the push
# failed - green in CI (no hooks there), red on every machine that installed the core's hooks.
# Idempotent (GIT_SANDBOX marks an isolated shell); the temp config is removed when the shell exits.
if [ -z "${GIT_SANDBOX:-}" ]; then
  GIT_CONFIG_GLOBAL="$(mktemp "${TMPDIR:-/tmp}/git-sandbox-XXXXXX")"
  printf '[user]\n\tname = sandbox\n\temail = sandbox@example.invalid\n' > "$GIT_CONFIG_GLOBAL"
  export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM=1 GIT_SANDBOX=1 GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=true SSH_ASKPASS=true
  _git_sandbox_file="$GIT_CONFIG_GLOBAL"
  _git_sandbox_prev_trap="$(trap -p EXIT | sed -E "s/^trap -- '(.*)' EXIT$/\1/")"
  # shellcheck disable=SC2064
  trap "rm -f '$_git_sandbox_file'; ${_git_sandbox_prev_trap:-:}" EXIT
fi
