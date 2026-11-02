- **The brain-scan reads what was only written** (test: T1) (level: reader; higher: writer — a stage that reads the mode
  log, the pause register and decision-review against the operator's corrections needs a judging agent and is the
  audit-audit's effectiveness part for now; debt: that behaviour stage). Measured on the macOS instance 2026-11-02
  (audit-audit): the skill root-cause-review promised "every two weeks with the brain-scan" and never ran; five logs in
  `.claude-state/` were written for weeks and read by nothing; of 144 register entries no one said who found the mishap,
  so the checks' hit rate (6 %) could only be counted by keyword.
  - `scripts/brain-scan-prep.py` runs `helpers/root-cause-gate.cjs --review --since <last scan>` and names the review due
    when a correction stayed without a cause or a cause without a mechanism.
  - `brain-scan-prep.py` reports every `.claude-state/` log that no second file names (a recorder's log, read by
    recorder-report, counts as read).
  - The carrier-register entry gains `found-by:` (operator | work | ci | the check) and `should-have:`; the cause gate
    asks for it and `--review` counts how many entries a check found.
  - `root-cause-gate.cjs --review` leaves out headless model calls (first `entrypoint` = `sdk-cli`): 24 of the 40 newest
    transcripts were prompt-classifier calls, whose prompt quotes the operator and matched the correction words; with
    them out the same window reads 499 operator turns instead of 224.
  Fixtures: brain-scan-prep-test +3 cases, test-root-cause-gate +2.
