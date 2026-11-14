- **stop-dispatcher: `--list` prints the effective check list, and recorder-report asks it instead of rebuilding the merge** (test: T1) (level: writer; higher: design — one registry file every reader opens would move "which checks run" out of the dispatcher, a change to the instance data format of every brain; debt: the other scripts that open stop-checks.json themselves (brain-friction.py, brain-scan-prep.py, carrier-audit.py, check-catalog.py, local-machinery.py, template-drift.py among them), each for its own question, were not moved to `--list` and not checked for whether they miss a required check that runs from the template only)
  Follow-up named in the content review of the required-recorders fix (2026-11-10): the dispatcher computes
  which checks run (the instance file plus the template's required ones the instance lacks and did not switch
  off), and `recorder-report.py` carried a second copy of that merge — before the copy existed it said
  "0 recorder(s)" while three recorders ran from the template. `node helpers/stop-dispatcher.cjs --list`
  prints `{"config": <path>, "checks": [...]}` (a template check carries `fromTemplate: true`) and exits
  without reading stdin; the Stop path is untouched. `recorder-report.py` asks the brain's consumed
  dispatcher (`core/helpers/`, else the one next to the script) and, when no list comes back, prints one
  `!!` line and `recorder report summary: recorders NOT countable` — never a zero. Fixtures:
  `scripts/test-stop-dispatcher.sh` (four `--list` cases), `scripts/recorder-report-test.py` (three new
  cases, the bridge among them: the report's recorders equal the record-mode checks of `--list`; two of
  them and all four `--list` cases fail against the state before).
