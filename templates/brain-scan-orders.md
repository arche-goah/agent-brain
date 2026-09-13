# Brain-Scan Order List

> Read by the brain-scan workflow (`core/workflows/brain-scan.js`) and named at session
> start by `session-bootup.sh` (the OPEN count). Lives at
> `docs/maintenance/brain-scan-auftraege.md`.
>
> Rule (order fidelity, HARD): items marked `origin: operator` are IMPLEMENTED at the next
> scan (with verify + an entry in the scan report). Items marked `origin: derived` are
> PROPOSALS — the scan does not touch them until the operator changes the origin or deletes
> them. An empty open list is a success, not an emergency: the scan then reports findings
> only and refills nothing.
>
> This list carries ONLY brain-function work (consistency, carriers, audits). Project or
> domain work goes to that domain's own ledger (`docs/<domain>/offene-punkte.md` or your
> equivalent) — a domain item here is misfiled and gets moved, not tolerated.

## Field convention

Every entry, four fields, English keys and values — they are the cross-instance interface;
the prose around them may be in your language:

- `id:` stable slug, referencable, survives rephrasing
- `class:` todo | decision | lesson
- `reach:` project | brain | shared — `shared` means it belongs in the shared-memory repo as one-file-one-fact, with a back-reference to this id
- `origin:` operator | derived

## Open (ordered)

- [ ] **<title of the order>** — origin: operator (<date>, "<the operator's words, quoted>").
  id: <slug>
  class: todo
  reach: brain
  origin: operator
  <what exactly, measured state, what "done" means; pointers to the plan or the finding>

## Proposed (derived)

- [ ] **<title of the finding>** — derived (<date>, found by <scan/session>).
  id: <slug>
  class: todo
  reach: brain
  origin: derived
  <the finding, the measurement behind it, the proposed fix; NOT executed until the origin changes>

## Done

- [x] **<title>** — done <date>, verified by <what ran>. (Keep the id; a done entry is a
  protocol, not a fact base — never "clean up" this section.)
  id: <slug>
