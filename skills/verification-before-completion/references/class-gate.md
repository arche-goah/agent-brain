# Class Gate — the mechanics behind Class Discipline

Rule: `rules/thinking-protocol.md` § Class Discipline (short form, always loaded). This file carries the long form the rule had before the context diet of 2026-10-20, verbatim; the gate itself is the "Class Gate" section of this skill's `SKILL.md`, the history behind it `docs/rule-history.md`.

A fix hits the instance the incident names; the class stays open and comes back. A found defect therefore counts as done only when the FINDING
CLASS is addressed: (1) name the invariant, not the anecdote, (2) enumerate by
SEARCH, not by recollection, (3) close or register every found site. The
finding-class question is a search, not speculation — executed, it returns
measurements. It is NOT the procedure-class question ("is my activity
repeatable, is there a skill?"), which is asked up front and needs no data —
`rules/intelligence.md`, Knowledge Carriers, keeps the two apart; letting the
front one shape how observations are read is the failure it names.

**Goal before class** (operator decision 2026-08-06): the class question comes AFTER
the goal and level question — what is this for, is it still the bigger goal, is this
the right object? Whatever gets a mechanical carrier dominates attention, because
countable sites feel like results; so every new carrier is asked which axis it
weakens.

This rule deliberately does NOT carry the mechanics. They live in:
- skill `verification-before-completion` (the Class Gate, runs at "done"),
- the instance's invariant register + `core/scripts/invariant-check.py` (a class
  needs a place where it stays open; the runner re-runs every registered search).

Build threshold (operator decision 2026-08-06): the search is always mandatory ·
1 site = done · 2 sites = fix both, no mechanism · >=3 sites or a repeat after a
fix = build a mechanism (the check must catch the CLASS, not the known case).
Sites outside the order: list, don't fix — but what is in reach and belongs to
the same matter gets DONE, not tabled.

**A wrongly kept state is a defect of its own** (operator decision 2026-10-19): an entry
listed open while the work is done — or ticked while it is not — is a finding with a cause
(copied from a report, fixed in passing, nobody re-measured), and the cause is fixed, not
only the checkbox. A ledger entry therefore names how "done" is measured (`check:` — a
read-only command, or `check: none — <why not>`); `core/scripts/ledger-reconcile.py` runs
those checks at every session start against the ledgers in `.claude/rules/ledgers.json`.
