- **check-catalog.py: every check the core ships, by the moment it runs, with trigger and what it checks — generated, never kept by hand** (test: T1) (level: design; higher: none; debt: the price per deep check is still the reference number in `rules/intelligence.md` until the local-run price from the same audit lands; instance checks are not listed)
  From the audit-audit run on the Windows instance (2026-11-10, released by the operator the same day): an
  inventory found 173 checks while the rules name six, and a fresh AI found no level above the full audit from
  its loaded context. The catalog reads hooks/hooks.json, the stop-check template, session-bootup.sh, the
  workflows, the check skills and the self-tests (278 entries on today's main; one file without a header shows
  as such). Printed, never committed — a stored copy would collide in every merge train. `rules/intelligence.md`
  names the command next to the three self-check levels. Fixture: `scripts/check-catalog-test.py` (18 checks).
