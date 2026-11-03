- **shared-reach-check reads project repos shared with a collaborator** (test: T1) (level: reader; higher: design — the
  essence rule stays, its check now sees where project results are written; debt: raw data and the ledger stay out, the
  write-up is the unit). Measured on the macOS instance 2026-11-03 (operator: "are our test results … in the shared memory
  for the collaborator, or only with us?"): a week of bench results lived in the project repo, the shared topic carried none of
  them, and the close check said nothing — it read the brain's `docs/` only, with the ledger excluded.
  - Instance data `project_repos: [{repo, topic, roots, exclude}]`: every `.md` changed under `roots` inside the window must
    be NAMED in a fact file of `<topic>/` (INDEX/OPEN excluded), else `FAIL shared-reach: project …` listing the files.
    A first variant compared dates and was measured wrong the same day: an unrelated newer reply in the topic hid the gap.
  - Summary line gains `projects_behind=N`. Fixture +3 (missing write-up named; control: a fact naming it is silent;
    control: changes before the window are not asked for).
  - A broken instance file (`shared-reach.json` not JSON) is a FAIL line "instance data unreadable — NOT checked", not
    a run on defaults: measured the same day, a straight quote inside a string turned the check silently green
    (`projects_behind=0`, `pointed=0`). Fixture +1.
