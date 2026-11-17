- **effect-check E3 skips environment prefixes; memory-lint measures bold sub-index entries; skill registry regenerated**
  (test: T1) (level: reader; higher: writer — the hook template could name hook targets in a field of their own instead
  of being parsed out of command strings; not built: every brain's settings would change for one false alarm; debt: E3
  still parses command text, a target hidden behind another wrapper form is not seen) — three findings of a brain-scan on
  the macOS instance, 2026-11-16. (1) `effect-check.sh` E3 read `VAR="$CLAUDE_PROJECT_DIR/<dir>"`, an environment value
  set before the hook command, as a hook target and reported the directory as a missing script (ROT, a false alarm);
  values after `=` are now skipped. Fixture `scripts/test-effect-check-e3.sh` (new: env prefix skipped, missing target
  still named; red against the previous script). (2) `memory-lint.py` measured the 400-character limit only on link
  entries (`- [Title](file.md)`); a bold sub-index entry (`- **Topic** — …`) of 529 characters passed unseen. Both forms
  count now; `scripts/memory-lint-test.py` case "overlong bold entry inside sub-index reported" (red against the previous
  lint). (3) `skills/REGISTRY.md` said 28 skills while 29 exist; regenerated with `scripts/regen-skill-registry.py`.
  The E3 skip is narrowed to an assignment in command-word position (identifier name), so a `--require=$CLAUDE_PROJECT_DIR/…`
  argument stays a checked target (fixture case "missing --require= target named"; Windows review 2026-11-17).
