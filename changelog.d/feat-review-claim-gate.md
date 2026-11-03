- **review-claim-gate: a review comment that says it read the diff is posted only after this PR's diff was read**
  (test: T1) (level: writer; higher: design - a review record the merge gate reads, not built because the comment
  is the record the merging side reads today; debt: a diff read outside the transcript, e.g. in a subagent or on
  the web, needs the `# DIFF-READ: <where>` marker). New PreToolUse gate on `gh pr comment|review` and
  `gh issue comment`: when the text says "read the diff", "read its diff", "reviewed the diff" or "reviewed the
  code", the transcript must show, before the post, a `gh pr diff <n>` / `git diff|show` naming the PR
  (`pr-<n>`, `pull/<n>`) or the head the comment names, or - after the previous post - a diff of a file the
  comment names in backticks. Agreed with the operator on 2026-11-03 (question tool). Measured on the macOS
  instance the same day: a comment claimed "read the diff of `scripts/open-items.py`" while the diff read before
  it was another PR's, on the same file. Replay over this brain's transcripts: 8 posts with such a claim, the gate
  holds exactly that one; `api-request-blob` records are skipped (read as calls they made four false holds in the
  first replay). Fixture `scripts/test-review-claim-gate.sh`, 14 cases.
