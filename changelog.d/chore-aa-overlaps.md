- **Overlaps from the audit of the audits (package G): one tool per question, a trigger for the report that had
  none** (test: T1) (level: writer; higher: design - one registry of "which tool answers which question" that a
  lint holds against new scripts, not built here because the audit of the audits itself is that registry for now;
  debt: the label lines of the stop dispatcher are the instance's words, so `skill-first-measure.py` attributes
  them by position, and a line starting with a stray capital word can read as a label). Measured on the macOS
  instance 2026-11-02 (audit of the audits, rows AA-23, AA-24, AA-27, AA-29, AA-45):
  (a) `scripts/gate-precision.py` removed: 12 of 13 gates "not measurable by text diff", no fixture, the same
  question as `skill-first-measure.py`; its os-traps baseline row and the optional instance file
  `gate-answer-markers.json` go with it.
  (b) `skill-first-measure.py` keeps its gate part and attributes by marker: any `[CODE]` of the block (the
  dispatcher's codes are not all `-GATE`, e.g. `[AUTONOMOUS-IDLE]`), else the dispatcher's label at a line start.
  Over 729 stop blocks since 2026-10-20 the untagged share fell from 523 to 2. Kept rather than dropped: the
  per-turn-kind split (notification turn or operator turn) is answered nowhere else.
  (c) `carrier-audit.py --presence` is the one entry point for the presence question (`lesson-carriers.py` stays
  the implementation its fixture imports); `brain-scan-prep.py` calls it, the session close and the pre-commit
  already call `carrier-audit.py`. Both fixtures pass; `carrier-audit-test.py` gains the `--presence` cases.
  (d) `backprop-report.py` gets its trigger: the pre-commit prints its report when a rule file is staged
  (`rules/*.md`, `.claude/rules/*.md`, `templates/feedback.md`, `templates/rules-instance/*.md`) and never
  blocks; fixture `scripts/test-pre-commit-backprop.sh` (no rule file: silent; a new dated rule: commit passes,
  the older place is named).
  (e) `plugin-scope-check.py` stays: it has a caller, `scripts/onboarding-verify.sh` step 2 (the core installed
  exactly once) — the audit's "no caller" was a search miss; a duplicate scope that appears after onboarding is
  left to that check.
  os-traps OS-3 baseline: `scripts/test-pre-commit-backprop.sh=1` after review — its temp dir reaches the hook only
  as the working directory, and the hook passes git's own `--show-toplevel` (native on every platform) to python.
