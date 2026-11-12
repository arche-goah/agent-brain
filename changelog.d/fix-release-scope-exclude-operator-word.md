- **release-scope: leaving an item out of a release takes the operator's quoted word** (test: T1) (level: writer;
  higher: design — the train could list every open own PR at build time so the question comes before the tag, not
  at it; not built: needs the merge-train tool and its own agreement; debt: the quote itself is not yet proven said,
  the mechanism guard's quote check is the carrier for that) — measured 2026-11-11 on the macOS instance: preflight
  check 11 held tag 2.1.5 because 21 own core PRs (opened 2026-11-07..11-10, older than the train) were neither in
  it nor excluded. A written script excluded all 21 with one reason that quoted the operator about the check
  procedure ("one train head per round"), not about leaving them out; the preflight went green and the PRs stood as
  "standing" in every session start after. `release-scope.py exclude` now refuses (rc 3) without
  `RELEASE_SCOPE_EXCLUDE_OK='"<their words>" <YYYY-MM-DD>'` and records the word with the reason; the check's hint
  and the preflight message say to ask. A command-text guard could not carry it: the exclusions ran from a script
  file. Fixture: `scripts/release-scope-test.py` +3 cases (refused without the word, refused without a date, recorded
  with it; red before the fix), 29/29.
