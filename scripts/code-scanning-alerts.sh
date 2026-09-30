#!/usr/bin/env bash
# code-scanning-alerts.sh — name the open code-scanning alerts of every repo an owner carries.
#
# THE OCCASION, measured 2026-09-30: eight CodeQL alerts in a vendored skill of the public
# core had stood open since its first public cut (2026-08-13). The scanner ran; nothing
# ever showed its result, so nobody looked. Reading the code behind them found worse than
# the alerts said: browser session cookies read silently on every run, a full `gh` token
# posted to a third party. A scanner without a display path is an instrument nobody reads.
#
# WHAT: for each non-archived repo of <owner>, the count of open alerts and the top-level
# folders they sit in. One line, only when there is something open; silent when all is
# clean. A repo without code scanning (404) or without access (403) is skipped silently —
# not every repo runs a scanner. Listing the repos failing is NOT silence: it says so.
#
# Cost: one call per repo (~7.7 s for 15 repos, measured 2026-09-30), so the session start
# runs it through scripts/cached-verdict.sh with a time window — foreign state, no local key.
#
# usage: code-scanning-alerts.sh <owner>      exit 0 always
set -uo pipefail
owner="${1:?usage: code-scanning-alerts.sh <owner>}"

repos=$(gh repo list "$owner" --no-archived -L 200 --json name --jq '.[].name' 2>/dev/null) || {
  echo "code scanning: NOT checked - listing the repos of $owner failed (offline or not logged in)"
  exit 0
}

hits="" total=0
while IFS= read -r repo; do
  [ -n "$repo" ] || continue
  # "<count> <folder,folder>" — folder = first two path parts, so a vendored skill names itself
  line=$(gh api "repos/$owner/$repo/code-scanning/alerts?state=open&per_page=100" \
    --jq '"\(length) \([.[].most_recent_instance.location.path | split("/")[:2] | join("/")] | unique | join(","))"' \
    2>/dev/null) || continue
  n=${line%% *}
  [ "${n:-0}" -gt 0 ] 2>/dev/null || continue
  total=$((total + n))
  hits="${hits:+$hits · }$repo $n (${line#* })"
done <<< "$repos"

if [ "$total" -gt 0 ]; then
  echo "!! code scanning: $total open alert(s) — $hits — list: gh api repos/$owner/<repo>/code-scanning/alerts?state=open"
fi
exit 0
