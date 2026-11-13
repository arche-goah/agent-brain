"""merge_ready.py — is another login's PR ready to merge: both systems said yes at its head?

One answer for the two readers of "whose move is this PR" (open-items.py `ball()` and
pr-ball.py, the session start's PR line): a second answer would let the two disagree on the
same PR, as two OS-review readers did on 2026-11-06 (helpers/os-review.cjs, WHY).

WHY (measured 2026-11-13 on the macOS instance): a suite PR had macOS OK (2026-10-25) and
Windows OK (2026-11-12) at the same head, CI green, CLEAN — and both readers parked it: open-items
as "waiting on" its author, pr-ball said nothing (no commit since our last look). collab-watch
step 4 (operator decision 2026-10-11): when both sides said yes, whoever comes first merges.

Ready = not a draft, GitHub reads it MERGEABLE, and a hand review says OK at its head for macOS
AND Windows. The OS verdict is read by helpers/os-review.cjs (its CLI), the one reader the merge
gate and release-preflight use. No node, no reader, a timeout: not ready — the PR keeps its old
reading, never a false "ours".
"""
import subprocess
from pathlib import Path

OS_REVIEW = Path(__file__).resolve().parent.parent / "helpers" / "os-review.cjs"
REQUIRED_OS = ("macOS", "Windows")


def hand_review(text, os_name, head):
    """True when `text` is a hand review that says OK for `os_name` at `head`."""
    try:
        r = subprocess.run(["node", str(OS_REVIEW), os_name, "--head", head], input=text,
                           capture_output=True, text=True, encoding="utf-8", timeout=10)
        return r.returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def merge_ready(pr, oid, review_key="latestReviews"):
    """`pr` = a GraphQL PullRequest node (isDraft, mergeable, body, comments, `review_key`)."""
    head = (oid or "")[:7]
    if pr.get("isDraft") or pr.get("mergeable") != "MERGEABLE" or not head or not OS_REVIEW.exists():
        return False
    nodes = ((pr.get("comments") or {}).get("nodes") or []) + ((pr.get(review_key) or {}).get("nodes") or [])
    texts = [t for t in [pr.get("body") or ""] + [(n or {}).get("body") or "" for n in nodes] if head in t]
    return all(any(hand_review(t, o, head) for t in texts) for o in REQUIRED_OS)
