- **autonomous-gate: the operator's latest word decides whether an ask rule may reach the dialog** (test: T1) (level:
  reader; higher: writer — a turn boundary written when a question-tool answer switches the run on would serve every
  reader; not built, one reader is affected; debt: presence is still read from turn membership, not from time).
  Measured on the macOS instance 2026-11-03: the turn opened with "anything open for me?", the questions were answered,
  the last answer was "continue autonomously"; the turn ran on through a compaction, and 13 minutes later an edit of
  `.claude/settings.json` (ask rule) raised a dialog in the autonomous run. `operatorInTurn` counted the opening prompt
  as the operator being present and dropped question-tool answers from the mode tail. Now a latest answer that switched
  the run on holds the call again. Fixture `scripts/test-autonomous-gate.sh` +2 (the held case passed the old gate).
