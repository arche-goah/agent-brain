# Brain-Scan Order List

> Read by the brain-scan workflow (`core/workflows/brain-scan.js`) and named at session
> start by `session-bootup.sh` (the OPEN count). Lives at
> `docs/maintenance/brain-scan-auftraege.md`.
>
> Rule (order fidelity, HARD): items marked `origin: operator` are worked in a session with
> the operator; the scan lists them, it does not execute them (since 2026-10-09 the scan
> reports and sorts, it never fixes). Items marked `origin: derived` are PROPOSALS. The scan
> writes every finding that needs a later hand into this list with `id: <key>` and
> `exit: <exit>`, and at its next run states per earlier finding whether it is done,
> decided, dropped, still open or vanished — so an entry is closed by ticking it (`[x]`),
> or by a line saying `decided` or `dropped`. An empty open list is a success, not an
> emergency. An open entry carrying the token `rebuild-ahead` announces a structural rebuild;
> the scan then suggests a full audit.
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
