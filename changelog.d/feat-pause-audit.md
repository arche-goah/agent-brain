- **pause-audit.cjs: every pause between two turns read back from the transcripts, sorted by the mode written at the turn end — ported from an instance alpha, changed by its evaluation** (test: T1) (level: reader; higher: writer — mode-log already writes the mode at every stop, so the reader only reads it; debt: the stated reason of a "suspect" pause is judged by hand, and the run is not yet part of the brain-scan)
  Operator order 2026-10-29 (the macOS instance): every pause found with its length and reason, checkable afterwards.
  Evaluated 2026-11-10 (operator decision the same day): since the written mode exists, 296 autonomous pauses, 45
  "suspect" — 28 of them carried a BLOCKED line the alpha's line-start pattern missed (`- BLOCKED:`, `**BLOCKED:**`), and
  its recomputed mode for older stops changed with every word-list change. The port reads only the written mode
  (`unknown` without one), takes `END_LINE` from autonomous-idle-gate.cjs (now exported) and reads only this brain's
  own transcripts by default. Fixture: `scripts/test-pause-audit.cjs` (11).
