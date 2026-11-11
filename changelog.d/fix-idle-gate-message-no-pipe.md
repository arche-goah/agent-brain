- **autonomous-idle-gate: the "own-items measurement" refusal says the measurement must stand without a pipe** (test: text only, fixture unchanged and green) (level: symptom; higher: reader - accept `open-items.py | head` as a measurement, not done: the pipe drops the items and their open exits, which is why the matcher refuses it on purpose; debt: none)
  Measured on the Windows instance 2026-11-07: four blocks in a row in one autonomous run, each answered with
  `open-items.py … | head`, because the refusal named only "own-items measurement" while the matcher
  (`measurers()`, `open-items\.py\b[^\n|;&]*$`) counts no command with anything after the view. Both refusals
  that ask for the measurement now name the form: a command of its own, no pipe or filter after it.
