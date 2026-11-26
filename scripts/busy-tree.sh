# busy-tree.sh — sourced: `busy_tree_mark <checkout> <what>` marks a checkout busy until the calling shell exits.
# helpers/shared-working-copy-guard.cjs holds a call that rewrites the tree files there while a fresh mark stands.
#
# WHY (measured 2026-11-23 on the macOS instance): a detached core-push-lint.sh ran in a core clone, the agent switched
# that clone to another branch meanwhile; the lint stamped the SHA, not the tree it read. The first fix (#649) read the
# process list - on Windows node finds no `ps` and the path has four spellings, so it never fired there (Windows review
# 2026-11-24). A mark the run writes itself into the checkout's own git dir needs neither.
#
# The mark is one file in `<git-dir>/agent-busy/`, removed on exit (an existing EXIT trap is kept and runs first).
# A run killed hard leaves it behind; the guard ignores a mark older than two hours.
busy_tree_mark() {
  local gd
  gd="$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null)" || return 0
  mkdir -p "$gd/agent-busy" 2>/dev/null || return 0
  BUSY_TREE_FILE="$gd/agent-busy/$$-$RANDOM"
  printf '%s\n' "$2" > "$BUSY_TREE_FILE" || return 0
  # `trap -p` alone in the substitution: in a pipeline it runs in a subshell, where bash 5 has reset the traps
  # (measured on the ubuntu CI 2026-11-26; bash 3.2 on macOS still showed them).
  local prev
  prev="$(trap -p EXIT)"
  prev="${prev#trap -- \'}"; prev="${prev%\' EXIT}"
  # shellcheck disable=SC2064
  trap "${prev:+$prev; }rm -f '$BUSY_TREE_FILE'" EXIT
}
