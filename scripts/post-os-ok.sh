#!/usr/bin/env bash
# post-os-ok.sh <owner/repo> <pr> <macOS|Windows|Linux> <details-file> — post this instance's OS OK on a PR at its CURRENT
# head, in the structured form helpers/os-review.cjs reads (`<!-- os-review: os=… verdict=ok head=… -->`), so no word of
# the details can cancel it. The details (what was run, the numbers) come from a file and stand below the OK line.
#
# WHY (ported 2026-11-17 from an instance alpha, used in 13 sessions): the OS reader judged an OK by its words and
# dropped one whose line also held "open", "pending" or "0 missing" — three merges held in one day (2026-10-28). The head
# is the PR's BRANCH read with `git ls-remote` (2026-10-28 the API lagged once; 2026-10-31 refs/pull/N/head stood one
# push behind the branch). The instance key comes from scripts/instance_key.py (SHARED_MEMORY_SELF); without a key
# nothing is posted, since the readers count only a text that carries one.
# POST_OS_OK_DRY=1 prints the body instead of posting (the fixture's seam; POST_OS_OK_HEAD sets the head).
# Exit 0 = posted (or printed), 2 = could not run.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY=python3; "$PY" -c 'import sys' >/dev/null 2>&1 || PY=python   # Windows: python3 can be the Store stub (OS-17)
REPO="${1:-}"; PR="${2:-}"; OS="${3:-}"; DETAILS="${4:-}"
usage() { echo "usage: post-os-ok.sh <owner/repo> <pr> <macOS|Windows|Linux> <details-file>" >&2; exit 2; }
case "$REPO" in */*) ;; *) usage ;; esac
[[ "$PR" =~ ^[0-9]+$ ]] || usage
case "$OS" in macOS|Windows|Linux) ;; *) usage ;; esac
[ -f "$DETAILS" ] && [ -s "$DETAILS" ] || { echo "post-os-ok: details file '$DETAILS' missing or empty - say what was run" >&2; exit 2; }
key="$("$PY" "$HERE/instance_key.py" 2>/dev/null | grep -aE '^<!-- instance-key: [0-9a-f]+ -->$' | head -1)"
[ -n "$key" ] || { echo "post-os-ok: no instance key (SHARED_MEMORY_SELF unset?) - nothing posted" >&2; exit 2; }
head="${POST_OS_OK_HEAD:-}"
if [ -z "$head" ]; then
  branch="$(gh pr view "$PR" -R "$REPO" --json headRefName,isCrossRepository -q 'select(.isCrossRepository|not) | .headRefName' 2>/dev/null)"
  ref="${branch:+refs/heads/$branch}"; ref="${ref:-refs/pull/$PR/head}"
  head="$(git ls-remote "https://github.com/$REPO" "$ref" | cut -c1-40)"
fi
[[ "$head" =~ ^[0-9a-f]{7,40}$ ]] || { echo "post-os-ok: no head for $REPO#$PR" >&2; exit 2; }
f="$(mktemp "${TMPDIR:-/tmp}/os-ok.XXXXXX")"; trap 'rm -f "$f"' EXIT
{
  printf '%s\n' "$key"
  printf '<!-- os-review: os=%s verdict=ok head=%s -->\n' "$OS" "$head"
  printf '**%s OK at head `%s`** (the %s instance, %s).\n\n' "$OS" "${head:0:7}" "$OS" "$(date +%Y-%m-%d)"
  cat "$DETAILS"
} > "$f"
if [ "${POST_OS_OK_DRY:-}" = 1 ]; then cat "$f"; exit 0; fi
gh pr comment "$PR" -R "$REPO" --body-file "$f"
