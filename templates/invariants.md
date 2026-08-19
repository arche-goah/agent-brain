# Invariant register — <this brain>

> A fix hits the instance the incident names; the class stays open and comes back
> (measured on a proving instance: five classes, up to 15 single fixes of the same
> root in 12 days). This register stores each class as its **invariant** together
> with the search command that spans its space — a class needs a place where it
> stays OPEN instead of vanishing into a feedback line.
>
> Check: `python3 core/scripts/invariant-check.py <this file>` (re-runs every
> registered search; drift and new sites fail loudly). The class question is a
> SEARCH, not a resolution — executed, it returns measurements.
>
> Build threshold (operator decision 2026-08-06): the search is always mandatory ·
> 1 site = done · 2 sites = fix both, no mechanism · >=3 sites or a repeat after a
> fix = build a mechanism (the check must catch the CLASS, not the known case).
>
> **`known` is a baseline, not a target.** It catches newcomers. Whoever closes a
> finding or assesses a new one updates the number — with a line under `note`.
>
> Block format (parsed by the runner — see its docstring for field semantics):
>
>     ## X-1 — short title
>     invariant: the sentence that spans the search space (never an anecdote)
>     pattern:   ERE regex for the search          | OR
>     check:     <external, e.g. a tool>           | when no pattern covers the space
>     paths:     search targets (--include=GLOB filters plus paths)
>     known:     path=N path=N
>     instances: 3
>     repeat:    yes|no
>     status:    open|closed
>     note:      free text — date + assessment for every change

root: ../..

<!-- First entry: take your most recent repeated defect, name the invariant it
     violated, write the search that finds ALL its sites, and record the baseline.
     An empty register on a working brain is a finding, not a clean sheet. -->
