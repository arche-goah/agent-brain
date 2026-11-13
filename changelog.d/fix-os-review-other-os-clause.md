- **os-review: an OS named inside another system's OK is no verdict for it** (test: T1) (level: reader; higher:
  writer — a verdict line that names one OS only would need every reviewer's prose to change, the reader is the one
  place all three gates share; debt: none) — measured 2026-11-13 on grandma3-suite #253: the Windows instance's line
  "Windows OK at head 53e5f99… — … (257 tests, 256 pass — the same totals as macOS) …; CI green" was read by
  `saysOk(line, 'macOS')` as the macOS OK (the pass-word branch found "rc 0" / "green" after "macOS"), and
  `merge-request-gate` let the merge through without a macOS verdict at the head. The pass-word branch now counts only
  where no other system's statement opened earlier in the line. Replay over the last 60 merged PRs of agent-brain and
  of grandma3-suite each (120 PRs, 5289 lines, old vs new reader): 5 lines flip, all from OK to no OK, all an OS named in
  the evidence of the other system's OK ("Since the Windows OK at `02b04be` …", "With the Windows OK …", "Windows plugin
  cache … pass", "Windows check … requested"); 0 lines lose a real OK. Fixture: `scripts/test-merge-request-gate.sh`
  +3 (the incident blocks, red against main's reader; the same OK plus a macOS line of its own passes; a labelled
  second verdict in the same line, "macOS: all 256 pass", stays a macOS OK — the macOS review's edge);
  `release-preflight-test.sh` 61/61 unchanged.
