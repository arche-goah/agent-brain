- **Template guard rule: a push that names `main`/`master` is turned to the upstream push before it meets the
  ask rule** (test: `scripts/test-guards.sh`, ten cases) (level: writer; higher: design - not taken, the command
  form is caught before it is issued and the settings template's ask rule on pushes to main is right and stays;
  debt: an instance with a different push policy adapts or drops the example rule, like rule 3). Measured on the
  Windows instance 2026-11-06: `git push -q origin main` into the shared-memory repo matched the template's ask
  form and held an autonomous run at a permission prompt until the operator came by; the lesson stood only as
  memory. `templates/rules-instance/mechanism-rules.json` gains example rule 4 (pattern from the instance carrier
  of the Windows brain, probe 10/10 there): blocks `push -q origin main`, `-C <path> push origin main`,
  `push origin HEAD:main`, `push origin master`; passes `-C <path> push`, `push -q`, `push origin feat/main-fix`,
  `push -u origin fix/x`, `log origin/main`, `pull --ff-only origin main`. Released by the operator 2026-11-06
  ("Ja, Workstation baut", shared memory `core/reply-reply-push-names-main-guard-rule-released-workstat-2026-11-06.md`).
