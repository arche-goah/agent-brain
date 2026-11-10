- **recorder-report: the template's `required` recorders count too** (test: T1) (level: reader; higher: writer — the dispatcher already runs them by design, the reader only has to see the same set; debt: none)
  Measured 2026-11-10 on the Windows instance (audit-audit AA-5): TIME, CLOCK and DIAGNOSE run from the
  template through `requiredFromTemplate` in stop-dispatcher.cjs, but the report read only the instance's
  stop-checks.json and printed "0 recorder(s)" — a false zero the day their first entry lands. Now the
  report adds every `required` template check the instance file lacks, minus the ones `disabled` with a
  reason (the dispatcher's own rule). Same brain afterwards: 8 recorders. Fixture:
  `scripts/recorder-report-test.py` (two new cases, 11 in all).
