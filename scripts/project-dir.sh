#!/usr/bin/env bash
# Sourced helper: where does THIS brain keep its runtime state (`.claude-state/`)?
#
#   . "$HERE/project-dir.sh"; PROJECT_DIR="$(resolve_project_dir "$HERE")"
#
# Why (measured 2026-10-11, Windows instance): three watchers and the session-start check built
# their state path from `${CLAUDE_PROJECT_DIR:-.}`. `CLAUDE_PROJECT_DIR` is set for hooks, NOT for
# a Bash/Monitor call, so the fallback `.` meant "whatever directory the caller happens to be in".
# A watcher armed from inside `core/` wrote a NEW cursor there, found none, reset its baseline to
# the current head — loudly, but every entry between the real cursor and now would have been
# skipped — and left a second state directory inside the submodule. A path that depends on the
# caller's cwd is a different path per caller.
#
# Order: the env var when set; otherwise the superproject that carries this script as a
# submodule (the brain); otherwise the repo this script lives in (a standalone core checkout —
# the tests); otherwise `.`, as before.
resolve_project_dir() {
  local here="${1:-.}" p
  if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then printf '%s\n' "$CLAUDE_PROJECT_DIR"; return 0; fi
  p=$(git -C "$here" rev-parse --show-superproject-working-tree 2>/dev/null)
  [[ -z "$p" ]] && p=$(git -C "$here" rev-parse --show-toplevel 2>/dev/null)
  printf '%s\n' "${p:-.}"
}
