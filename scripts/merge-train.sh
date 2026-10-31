#!/usr/bin/env bash
# merge-train.sh <pr>... — one CI run for a stack of ready PRs instead of one run per PR.
# long-run: detached
#
# WHY (measured 2026-10-31 on the macOS instance): 21 core PRs needed a new CI run after a CI-image fix;
# GitHub ran at most a handful of jobs at a time (each run ~13 jobs, macOS and Windows among them), so
# the runs queued for over half an hour before the first one started, and a single run took ~45 min.
# The operator (translated): "do the train branch, everything else is madness - new PRs keep coming".
#
# WHAT: a branch `train/<date>-<n>` from main; every PR's BRANCH head (refs/heads/<branch>, never
# refs/pull/N/head, which lags - #128, same day) is merged in UNCHANGED with a merge commit, in the order
# given. A PR that conflicts with the train so far is left out and named. The script prints the train's
# manifest (PR -> head sha) as the PR body. Pushing the branch and opening the train PR is the caller's
# step (the push gate wants a green core-push-lint stamp for the train head first).
#
# MERGE: the train PR merges into main with a MERGE commit (not squash) - every contained PR's head is
# then reachable from main and GitHub marks that PR merged. The checks the ruleset demands run once, on
# the train PR; the OS checks by hand (macOS, Windows) are asked once, for the train head, which holds
# every contained head byte for byte plus their combination.
#
# Usage: merge-train.sh [--repo DIR] [--name NAME] <pr> [<pr>...]   (DIR: a clone of the repo; default cwd)
# Exit 0 = train built (at least one PR in), 1 = no PR could join, 2 = could not run.
set -u
DIR="."; NAME=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) DIR="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --) shift; break ;;
    -*) echo "merge-train: unknown option $1" >&2; exit 2 ;;
    *) break ;;
  esac
done
[ $# -gt 0 ] || { echo "usage: merge-train.sh [--repo DIR] [--name NAME] <pr>..." >&2; exit 2; }
GH="${MERGE_TRAIN_GH:-gh}"
slug="$(git -C "$DIR" remote get-url origin 2>/dev/null | sed -E 's#(\.git)?$##; s#^.*github\.com[:/]##')"
[ -n "$slug" ] || { echo "merge-train: $DIR has no github origin" >&2; exit 2; }
git -C "$DIR" fetch --quiet origin main || exit 2
NAME="${NAME:-train/$(date +%Y-%m-%d)-$(date +%H%M)}"
git -C "$DIR" checkout --quiet -B "$NAME" origin/main || exit 2

joined=(); left=()
for pr in "$@"; do
  branch="$("$GH" pr view "$pr" -R "$slug" --json headRefName,isCrossRepository,state \
            -q 'select(.state=="OPEN" and (.isCrossRepository|not)) | .headRefName' 2>/dev/null)"
  if [ -z "$branch" ]; then left+=("#$pr (not an open same-repo PR)"); continue; fi
  if ! git -C "$DIR" fetch --quiet origin "+refs/heads/$branch:refs/remotes/origin/train-src-$pr"; then
    left+=("#$pr (branch $branch not fetched)"); continue
  fi
  head="$(git -C "$DIR" rev-parse "refs/remotes/origin/train-src-$pr")"
  if git -C "$DIR" -c user.email=train@local -c user.name=merge-train merge --quiet --no-ff \
       -m "train: #$pr $branch @ ${head:0:7}" "$head" >/dev/null 2>&1; then
    joined+=("#$pr $branch ${head}")
  else
    git -C "$DIR" merge --abort >/dev/null 2>&1
    left+=("#$pr (conflicts with the train so far)")
  fi
done

echo "## Merge train $NAME"
echo
echo "Base: main @ $(git -C "$DIR" rev-parse --short origin/main) · train head: $(git -C "$DIR" rev-parse --short HEAD)"
echo
echo "Contains (each PR's branch head, merged unchanged):"
for j in "${joined[@]:-}"; do [ -n "$j" ] && echo "- $j"; done
if [ ${#left[@]} -gt 0 ]; then
  echo
  echo "Left out:"
  for l in "${left[@]}"; do echo "- $l"; done
fi
[ ${#joined[@]} -gt 0 ] || exit 1
exit 0
