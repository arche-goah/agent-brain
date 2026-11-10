- **ledger-fields.json: one grammar for ledger fields, read by one Python and one JavaScript reader; instrument-watch and shared-reach-check moved onto it** (test: T1) (level: design; higher: none; debt: brain-scan-prep (#475 changes the same line) and autonomous-idle-gate (#480 changes the same function) move after the next train; `exit:` and `check:` still have their own readers)
  Content review of agent-brain #475 (2026-11-10, the macOS instance): four readers of `id:` used four patterns
  (line start only · `\S+` · `[\w-]` · `[\w.:/-]`); instrument-watch still read only line starts and never the
  entry line itself, so a cause written in the field form (`- [ ] … | id: x | class: todo`) read as "stands in no
  registered ledger". The grammar lives in `ledger-fields.json` (lead, value, end; ASCII classes, because `\w` is
  Unicode in Python and ASCII in JavaScript); `scripts/ledger_fields.py` and `helpers/ledger-fields.cjs` build their
  patterns from it. On the porting machine's order list: 331 ids before, 336 after, none lost. Fixtures:
  `scripts/ledger-fields-test.py` (the JSON's cases in both languages), `scripts/test-instrument-watch.sh` (field form).
