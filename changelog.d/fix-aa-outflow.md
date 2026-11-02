- **Coherence scan: a partial run under the cadence; findings get the brain-scan's outflow** (test: T1) (level: writer;
  higher: design — one shared exit checker every audit report runs through is the class fix, built after this; debt:
  that checker). Measured on the macOS instance 2026-11-02 (audit-audit): four full coherence runs in 24 days, ~6.7 M
  tokens over the 14-day cadence, because the trigger "five new dated rules" is met at almost any rule pace; operator
  decision the same day: "Teil-Lauf bei Bedarf".
  - `workflows/coherence-scan.js`: `args.partial = {since: "YYYY-MM-DD"}` audits only the rule sources changed since
    that date against CLAUDE.md and every core and instance rule file, with three lenses and no scenario traces.
  - `helpers/freshness-gate.cjs` lets a partial run through under the cadence; a full run, or a partial without a date,
    is held as before. Fixture +3 (19/19).
  - `scripts/brain-scan-prep.py` suggests the partial run, with its `since`, when the last register is under 14 days old.
    Fixture +1.
  - The return channel's recurrence count no longer stops at a bare tick: a ledger entry ticked without a `check:` line is
    `done-unproven` and keeps counting toward the third-time decision (on 2026-10-30 seven keys the channel called done
    came back; the six that returned after a tick had no check). An index exit `done-already` stays done. Fixture +2.
  - `workflows/brain-scan.js`: a gate that fails after the report was written names in its error the report path, the
    findings folder, the decisions and the top findings (the 10-15 run lost its return that way). The gate still fails.
  - The coherence corpus takes the first 40 lines of every instance script and of every synthesis/register/report under
    `docs/research/` (a 10-25 register said no level above the full audit exists; the audit-audit reports stood there).
