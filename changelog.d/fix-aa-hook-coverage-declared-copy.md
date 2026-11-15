- **hook-coverage: a copy of a plugin hook declared in local-machinery.json is no duplicate to drop** (test: T1) (level: reader; higher: writer — the plugin cannot reach projects outside its scope, so the user-level copy is the brain's own decision, not a wiring error; debt: none)
  Measured 2026-11-10 on the Windows instance (audit-audit AA-5): the operator's input guard runs as the
  plugin hook (project scope, brain only) AND as a user-level copy that guards every other project; after the
  copy was renewed to the core text, hook-coverage reported "runs twice - drop the copy" at every start,
  which would remove the only guard outside the brain. A wired command that is a key of
  `.claude/rules/local-machinery.json` (instance, or alpha with a date not passed, each with a `why`) is
  skipped; an expired declaration hides nothing. Fixture: `scripts/test-hook-coverage.sh` (two new cases).
