# busy-tree.sh — sourced: `busy_tree_mark <checkout> <what>` marks a checkout busy, `busy_tree_clear` takes the mark
# away; the caller puts `busy_tree_clear` into its own EXIT trap. helpers/shared-working-copy-guard.cjs holds a call
# that rewrites the tree files there while a fresh mark stands.
#
# WHY (measured 2026-11-23 on the macOS instance): a detached core-push-lint.sh ran in a core clone, the agent switched
# that clone to another branch meanwhile; the lint stamped the SHA, not the tree it read. The first fix (#649) read the
# process list - on Windows node finds no `ps` and the path has four spellings, so it never fired there (Windows review
# 2026-11-24). A mark the run writes itself into the checkout's own git dir needs neither.
#
# The mark is one file in `<git-dir>/agent-busy/`. No trap of its own: reading the caller's trap back (`trap -p` in a
# command substitution) showed it on bash 3.2 and lost it on bash 5 (ubuntu CI 2026-11-26). A run killed hard leaves
# the mark behind; the guard ignores a mark older than two hours.
busy_tree_mark() {
  local gd
  gd="$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null)" || return 0
  mkdir -p "$gd/agent-busy" 2>/dev/null || return 0
  BUSY_TREE_FILE="$gd/agent-busy/$$-$RANDOM"
  printf '%s\n' "$2" > "$BUSY_TREE_FILE" || BUSY_TREE_FILE=""
}
busy_tree_clear() { [ -n "${BUSY_TREE_FILE:-}" ] && rm -f "$BUSY_TREE_FILE"; BUSY_TREE_FILE=""; }
