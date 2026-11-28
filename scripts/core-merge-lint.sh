#!/usr/bin/env bash
# core-merge-lint.sh <pr> — the core's CI lint on the state a merge would CREATE: the PR head with
# today's main merged in, in a throwaway checkout. Green writes a stamp the merge gate reads
# (<brain>/.claude-state/core-merge-lint/<head>-<main>.ok); a moved head or main makes the stamp stale.
# long-run: detached
#
# WHY (ported 2026-11-17 from an instance alpha, in use since 2026-10-28 in 129 sessions): the core
# ruleset does not demand "branch up to date" (a merge queue is not available to a personal account, and
# the up-to-date rule cost one CI run and one hand OS check per PR per merge). What that rule caught — CI
# green against an old main, red against today's (2026-10-27, English ratchet) — this lint catches: the
# lint jobs of ci-lint-local.sh plus every fixture that names a file the PR touches, on the merged tree
# (2026-10-28: two PRs green apart, red together, caught here before the merge). Measured duration: 2 to
# 10 min. Gate: helpers/core-merge-lint-gate.cjs.
#
# The repo is the origin of the core checkout this script lives in (in a brain: its core/ submodule);
# CORE_LINT_REPO=<owner/name> overrides. Clone cache: CORE_MERGE_LINT_CLONE (default
# ~/.cache/agent-brain/core-merge-lint). Leak watch list: <brain>/.claude/rules/leak-names.json.
# Run it detached (Working Rule #13); exit 0 = green and stamped, 1 = red, 2 = could not run.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/project-dir.sh"
PY=python3; "$PY" -c 'import sys' >/dev/null 2>&1 || PY=python   # Windows: python3 can be the Store stub (OS-17)
PR="${1:-}"; [[ "$PR" =~ ^[0-9]+$ ]] || { echo "usage: core-merge-lint.sh <pr-number>" >&2; exit 2; }
REPO="${CORE_LINT_REPO:-$(git -C "$HERE/.." config --get remote.origin.url 2>/dev/null | sed -E 's#\.git$##; s#^.*[:/]([^/:]+/[^/:]+)$#\1#')}"
case "$REPO" in */*) ;; *) echo "core-merge-lint: no core repo (origin of $HERE/.. unreadable; set CORE_LINT_REPO)" >&2; exit 2 ;; esac
ROOT="$(resolve_project_dir "$HERE")"
CLONE="${CORE_MERGE_LINT_CLONE:-$HOME/.cache/agent-brain/core-merge-lint}"
STAMPS="${CORE_MERGE_LINT_STAMPS:-$ROOT/.claude-state/core-merge-lint}"
mkdir -p "$STAMPS" "$(dirname "$CLONE")"
[ -d "$CLONE/.git" ] || git clone --quiet "https://github.com/$REPO" "$CLONE" || exit 2
# The PR's head is its BRANCH, not refs/pull/N/head: measured 2026-10-31 (#128) GitHub's pull ref stood
# one push behind the branch and headRefOid — the lint judged a stale head. The branch name comes from the
# API (a name does not go stale); a fork PR (no branch here) falls back to the pull ref.
branch="$(gh pr view "$PR" -R "$REPO" --json headRefName,isCrossRepository -q 'select(.isCrossRepository|not) | .headRefName' 2>/dev/null)"
src="${branch:+refs/heads/$branch}"; src="${src:-pull/$PR/head}"
git -C "$CLONE" fetch --quiet origin main "+$src:refs/remotes/origin/pr-$PR" || exit 2
head="$(git -C "$CLONE" rev-parse "refs/remotes/origin/pr-$PR")"
main="$(git -C "$CLONE" rev-parse origin/main)"
# main is in the head: the merge creates nothing new — the merged tree IS the head's (measured 2026-11-01: a
# train's merge commit and its head shared one tree), and the CI at the head judged exactly it.
if git -C "$CLONE" merge-base --is-ancestor "$main" "$head"; then
  printf '%s\n' "main ${main:0:7} is in head ${head:0:7}: merged state = head, CI at the head counts" > "$STAMPS/$head-$main.ok"
  echo "core-merge-lint: GREEN PR #$PR head ${head:0:7} + main ${main:0:7} — main is in the head, the merged state is the head (CI at the head counts)"
  exit 0
fi
git -C "$CLONE" checkout --quiet --detach --force "$head" || exit 2
# The merged state's leak scan with the brain's watch list (2026-11-04: a local scan without the list said 0
# findings where the CI, reading its secret list, went red).
NAMES="${CORE_PUSH_LINT_NAMES:-$ROOT/.claude/rules/leak-names.json}"
if [ -f "$NAMES" ]; then LEAK_NAMES_JSON="$(cat "$NAMES")"; export LEAK_NAMES_JSON; fi
git -C "$CLONE" clean -fdq
if ! git -C "$CLONE" -c user.email=lint@local -c user.name=lint merge --quiet --no-edit "$main" >/dev/null 2>&1; then
  git -C "$CLONE" merge --abort >/dev/null 2>&1
  echo "core-merge-lint: PR #$PR head ${head:0:7} does not merge cleanly with main ${main:0:7}"; exit 1
fi
. "$HERE/busy-tree.sh"; trap busy_tree_clear EXIT; busy_tree_mark "$CLONE" "core-merge-lint PR #$PR"
out="$(bash "$CLONE/scripts/ci-lint-local.sh" 2>&1)"; rc=$?
summary="$(printf '%s\n' "$out" | grep -a 'ci-lint-local:' | tail -1)"

# The neighbours' fixtures on the merged state: ci-lint-local runs the lint jobs only; the fixtures live in the
# portability job. Every fixture that names a file the PR touches (or is touched itself) runs here.
fixtures=()
while IFS= read -r f; do
  [ -n "$f" ] || continue
  base="$(basename "$f")"; stem="${base%.*}"
  # a stem under 4 characters matches as a substring everywhere ("ci" of ci.yml pulled 74 fixtures, 2026-10-31)
  [ "${#stem}" -ge 4 ] || continue
  for t in "$CLONE"/scripts/test-*.sh "$CLONE"/scripts/*-test.sh "$CLONE"/scripts/*-test.py "$CLONE"/scripts/test-*.cjs; do
    [ -f "$t" ] || continue
    if [ "scripts/$(basename "$t")" = "$f" ] || grep -aqF "$stem" "$t"; then fixtures+=("$t"); fi
  done
done < <(git -C "$CLONE" diff --name-only "$main...$head")
fx_fail=0; fx_n=0
# read line by line, not `for t in $(…)`: the clone path can hold a space (a Windows profile name, OS-10)
while IFS= read -r t; do
  [ -n "$t" ] || continue
  fx_n=$((fx_n + 1))
  case "$t" in *.py) "$PY" "$t" >/dev/null 2>&1 ;; *.cjs) node "$t" >/dev/null 2>&1 ;; *) bash "$t" >/dev/null 2>&1 ;; esac
  [ $? -eq 0 ] || { fx_fail=$((fx_fail + 1)); echo "  FAIL fixture on the merged state: scripts/$(basename "$t")"; }
done < <(printf '%s\n' "${fixtures[@]:-}" | sort -u)
[ "$fx_fail" -eq 0 ] || rc=1
summary="$summary; $fx_n neighbour fixture(s), $fx_fail failed"
git -C "$CLONE" checkout --quiet --detach --force "$head"
if [ "$rc" -eq 0 ]; then
  printf '%s\n' "$summary" > "$STAMPS/$head-$main.ok"
  echo "core-merge-lint: GREEN PR #$PR head ${head:0:7} + main ${main:0:7} — $summary"
  exit 0
fi
printf '%s\n' "$out" | grep -aE '^ *FAIL|ci-lint-local:'
echo "core-merge-lint: RED PR #$PR head ${head:0:7} + main ${main:0:7}"
exit 1
