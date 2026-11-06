- **template-drift: a note for a template stop check the brain's stop-checks.json lacks** (test: T1)
  (level: reader; higher: design - the dispatcher merging every template check by itself, as it already does
  for `required` ones; not built because an optional check is the brain's choice, the operator agreed on a note
  (2026-11-05, macOS session, "Ja, als Hinweis"); debt: none new). Measured 2026-11-05 on the Windows instance:
  MODE-LOG stood in `templates/rules-instance/stop-checks.json` and not in the brain's file, and no session start
  said so - the gap was found by hand. `template-drift.py` (run at every session start) now names each template
  marker that is not `required` (those run from the template anyway, `requiredFromTemplate` in
  `stop-dispatcher.cjs`), is missing from the brain's file and is not switched off in `"disabled"` with a reason.
  A `note:` line, not a `!!`. A brain without its own `stop-checks.json` stays silent. Fixture: five new cases in
  `scripts/test-template-drift.sh` (named / required left out / a note / disabled with a reason silent / blank
  reason named / no file silent); against main's script two of them fail. Against the Windows brain's file before
  the wiring it names exactly MODE-LOG, after it nothing.
