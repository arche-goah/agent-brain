#!/usr/bin/env bash
# text-leaks-notice.sh <scan.out> — the notice the text-leaks workflow posts to the poster.
#
# Input: the stdout of `leak-scan.py --no-tree --text <file>` (finding lines start with `!! `:
# `!! [<class>] text:<file>:<line>: <match>`). Output: a Markdown comment body on stdout, or
# nothing when the scan had no finding line.
#
# WHY a script: the notice must NEVER repeat what was found. leak-scan redacts names,
# instances and emails, but prints a private address or a home path as matched — quoting
# the scan output in a public comment would post the leak a second time. This script keeps
# only the finding's CLASS and LINE and is proven both ways by scripts/test-text-leaks-notice.sh.
#
# Environment (set by the workflow; empty is tolerated): AUTHOR (GitHub login to mention),
# WHAT (event name: issue_comment | pull_request | pull_request_review |
# pull_request_review_comment), RUN_URL (the run that found it).
set -euo pipefail
scan="${1:?usage: text-leaks-notice.sh <scan.out>}"
[ -r "$scan" ] || { echo "text-leaks-notice: cannot read $scan" >&2; exit 2; }

# class and line only — the match after the third colon is dropped, whatever it holds
findings="$(grep -E '^!! \[[a-z_]+\] ' "$scan" \
  | sed -E 's/^!! \[([a-z_]+)\] [^ ]+:([0-9]+): .*$/- \1 at line \2/' || true)"
[ -n "$findings" ] || exit 0

case "${WHAT:-}" in
  pull_request)               what="pull request title or body" ;;
  pull_request_review)        what="review" ;;
  pull_request_review_comment) what="review comment" ;;
  *)                          what="comment" ;;
esac
who="${AUTHOR:+@$AUTHOR — }"
run="${RUN_URL:+ Run: $RUN_URL}"

cat <<EOF
${who}**leak scan: your ${what} names a person, a machine or a private address — this repository is public.**

${findings}

The ${what} is hidden where the API allows it; the text is still in its history. Please delete it and post it again without the name or address — an edit keeps the old text readable. Public wording: "the operator", "a collaborator", "the macOS instance" / "the Windows instance"; machine ids only in private repos.

This scan is the last barrier, not the first: your brain's \`public-text-guard\` should have refused the text before it was posted. If it did not, that is a finding for the core — please say how the text was posted (command, file or variable).${run}
EOF
