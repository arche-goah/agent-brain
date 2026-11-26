#!/usr/bin/env bash
# post-os-ok.sh <owner/repo> <pr> <macOS|Windows|Linux> <details-file> — write this instance's OS OK for a PR at its
# CURRENT head, in the structured form helpers/os-review.cjs reads (`<!-- os-review: os=… verdict=ok head=… -->`), so no
# word of the details can cancel it. The details (what was run, the numbers) come from a file and stand below the OK line.
# It WRITES the body (next to the details file, `<details>.os-ok.md`) and PRINTS the post line; the session runs that
# line itself. It never posts: a post from inside a script is invisible to public-text-guard and instance-key-gate,
# which read only the command the tool runs (Windows review 2026-11-17, finding on core #567: measured 2026-11-12,
# 30 comments posted through a script, two carried a home-path placeholder, the text-leak workflow went red - the
# first barrier, working rule #11, never saw them).
#
# WHY (ported 2026-11-17 from an instance alpha, used in 13 sessions): the OS reader judged an OK by its words and
# dropped one whose line also held "open", "pending" or "0 missing" — three merges held in one day (2026-10-28). The head
# is the PR's BRANCH read with `git ls-remote` (2026-10-28 the API lagged once; 2026-10-31 refs/pull/N/head stood one
# push behind the branch). The instance key comes from scripts/instance_key.py (SHARED_MEMORY_SELF); without a key
# nothing is posted, since the readers count only a text that carries one.
# POST_OS_OK_DRY=1 prints the body instead of posting (the fixture's seam; POST_OS_OK_HEAD sets the head).
# Exit 0 = body written and the post line printed (or, dry, the body printed), 2 = could not run.
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
live_head() {
  local branch ref
  branch="$(gh pr view "$PR" -R "$REPO" --json headRefName,isCrossRepository -q 'select(.isCrossRepository|not) | .headRefName' 2>/dev/null)"
  ref="${branch:+refs/heads/$branch}"; ref="${ref:-refs/pull/$PR/head}"
  git ls-remote "https://github.com/$REPO" "$ref" | cut -c1-40
}
head="${POST_OS_OK_HEAD:-}"
if [ -z "$head" ]; then
  head="$(live_head)"
elif [ "${POST_OS_OK_DRY:-}" != 1 ]; then
  # A given head is checked against the PR's own (2026-11-17, macOS instance: an OK on #576 named 7b760f1, the
  # checkout's HEAD after a refused train build, not the PR head 421aef9). POST_OS_OK_LIVE_HEAD is the fixture's seam.
  live="${POST_OS_OK_LIVE_HEAD:-$(live_head)}"
  case "$live" in
    "$head"*) ;;
    *) echo "post-os-ok: POST_OS_OK_HEAD $head is not the head of $REPO#$PR (${live:-unreadable}) - check that checkout, or leave POST_OS_OK_HEAD unset" >&2; exit 2 ;;
  esac
fi
[[ "$head" =~ ^[0-9a-f]{7,40}$ ]] || { echo "post-os-ok: no head for $REPO#$PR" >&2; exit 2; }
f="${DETAILS%.*}.os-ok.md"
{
  printf '%s\n' "$key"
  printf '<!-- os-review: os=%s verdict=ok head=%s -->\n' "$OS" "$head"
  printf '**%s OK at head `%s`** (the %s instance, %s).\n\n' "$OS" "${head:0:7}" "$OS" "$(date +%Y-%m-%d)"
  cat "$DETAILS"
} > "$f"
if [ "${POST_OS_OK_DRY:-}" = 1 ]; then cat "$f"; exit 0; fi
echo "post-os-ok: body written to $f - post it with this line, run directly so the text guards see it:"
printf 'gh pr comment %s -R %s --body-file %s\n' "$PR" "$REPO" "$f"
