- **Four checks no longer report green where they cannot see** (test: T1) (level: reader; higher: design — a general
  "every instrument has a must-fail case" lint over all checks is a larger build, written as a convention in
  CONVENTIONS.md §7 first; debt: the convention has no lint yet). Measured on the macOS instance 2026-11-02 (audit-audit):
  - `scripts/recorder-report.py` read only a gate's own log and dropped the dispatcher's (promise-gate.jsonl: 31
    would_block in 14 days, reported 0), and printed "0 would have blocked" for logs that carry no `would_block` field
    (time-gate 506, closing classifier 603 entries). Now both logs count, a log without the field says "NOT countable",
    and a pure log declares `counts_blocks: false` (mode-log in the template). Fixture 9 cases; the old report fails two.
  - `scripts/brain-selftest.sh` ran no `.cjs` fixture and no `test-*.py`, and printed the last five lines of a failing
    shell fixture although its FAIL lines stood above them. Now node fixtures (`scripts/test-*.cjs`, `scripts/hooks/test-*.cjs`,
    `core/scripts/…`) and `test-*.py` run, a live probe is declared in `manual-tools.json`, and the FAIL lines are shown first.
  - `helpers/stop-dispatcher.cjs` skipped a wired check whose file is missing without a word; now it names it every turn
    (outside a brain, a required core row without a `core/` folder stays silent). Fixture case `GHOST`.
  - `scripts/dead-carriers.py` checked only names that start with a folder, so `memory-usage.py --precision` (a running
    alpha's measurement tool, in no folder of the brain or its pin) passed as "0 missing". Now bare script names are
    searched in the script folders and a skill's own folder, and a workflow offered as `brain-core:<name>` counts as
    present. Fixture +2 cases.
