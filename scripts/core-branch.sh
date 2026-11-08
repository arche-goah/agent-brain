#!/usr/bin/env bash
# core-branch.sh — a fresh clone + branch for one change, with the public identity set: one step instead of four.
#
# WHY (measured 2026-11-08 on the macOS instance, one session): twelve throwaway clones were made by hand for twelve core
# branches; twice the local identity was forgotten and public-text-guard refused the commit (the global author carries the
# operator's name), once a clone was switched to another branch while a queued push lint still pointed at it. Released by
# the operator 2026-11-08 (question tool).
#
# Usage: core-branch.sh <branch> [--repo <owner/name>] [--base <ref>] [--into <parent dir>]
#   --repo   default: the origin of the core checkout this script lives in
#   --base   default: origin/main (a stacked change: the other branch's name, e.g. fix/x)
#   --into   default: $CLAUDE_SCRATCHPAD, else $TMPDIR; the clone lands in <parent>/<repo-name>-<branch with / as ->
# Identity: CORE_BRANCH_NAME / CORE_BRANCH_EMAIL, else the GitHub login and its noreply address (`gh api user`).
# Never switches an existing folder: a folder that exists is refused (a queued lint may still read it).
# Prints the clone path on the last line. Exit 0 = ready, 2 = refused or could not run.
set -u
branch="${1:-}"; shift || true
[ -n "$branch" ] && [ "${branch#-}" = "$branch" ] || { echo "usage: core-branch.sh <branch> [--repo o/n] [--base ref] [--into dir]" >&2; exit 2; }
here="$(cd "$(dirname "$0")/.." && pwd)"
repo=""; base="origin/main"; into="${CLAUDE_SCRATCHPAD:-${TMPDIR:-/tmp}}"
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="${2:-}"; shift 2 ;;
    --base) base="${2:-}"; shift 2 ;;
    --into) into="${2:-}"; shift 2 ;;
    *) echo "core-branch: unknown argument $1" >&2; exit 2 ;;
  esac
done
if [ -z "$repo" ]; then
  repo="$(git -C "$here" config --get remote.origin.url | sed -E 's#\.git$##; s#^.*[:/]([^/:]+/[^/:]+)$#\1#')"
fi
case "$repo" in */*) ;; *) echo "core-branch: --repo must be owner/name (got '$repo')" >&2; exit 2 ;; esac

name="${CORE_BRANCH_NAME:-}"; email="${CORE_BRANCH_EMAIL:-}"
if [ -z "$name" ] || [ -z "$email" ]; then
  who="$(gh api user --jq '"\(.login) \(.id)"' 2>/dev/null)" || who=""
  [ -n "$who" ] || { echo "core-branch: no public identity - set CORE_BRANCH_NAME/CORE_BRANCH_EMAIL or log in with gh" >&2; exit 2; }
  name="${name:-${who% *}}"; email="${email:-${who#* }+${who% *}@users.noreply.github.com}"
fi

dir="$into/${repo#*/}-$(printf '%s' "$branch" | tr '/' '-')"
[ -e "$dir" ] && { echo "core-branch: $dir exists - refused (never switch a folder a queued lint may still read; pick another branch name)" >&2; exit 2; }
mkdir -p "$into" || exit 2
# Test seam: CORE_BRANCH_URL replaces the GitHub URL (the fixture clones a local bare repo, no network).
git clone -q "${CORE_BRANCH_URL:-https://github.com/$repo.git}" "$dir" || { echo "core-branch: clone failed" >&2; exit 2; }
git -C "$dir" config --local user.name "$name"
git -C "$dir" config --local user.email "$email"
start="$base"
case "$base" in origin/*) ;; *) git -C "$dir" rev-parse -q --verify "origin/$base" >/dev/null && start="origin/$base" ;; esac
git -C "$dir" checkout -q -b "$branch" "$start" || { echo "core-branch: base $base not found" >&2; exit 2; }
echo "core-branch: $branch from $start, author $name <$email>"
echo "$dir"
