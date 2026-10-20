# Project Lifecycle

Rule: `rules/working-rules.md` § Project Lifecycle (operator order 2026-08-14). The rule
file keeps the pointer; the six steps stand here (moved verbatim in the context diet of
2026-10-20). Why and incidents: `docs/rule-history.md`, "Project Lifecycle".

("The ledger rule above" is `rules/working-rules.md` § Project Work Ledgers, which stands
just above the pointer in the rule file.)

The ledger rule above says how project work is TRACKED; this one says what gets
CREATED when a new project domain starts (a new tool, a new show system, a new
pipeline) — top-down and identical in every brain, so any colleague opening the
same topic lands in the same layout:

1. **Decide the cut first: tool vs. instance** (CONVENTIONS §11). Executable
   capability any operator could reuse => own TOOL repo (public-able, English,
   suite conventions: AGENTS.md, leak-scan, release-preflight + tag CI).
   Operator orders, hardware context and intermediate states => the PRIVATE
   brain. A project that starts as "just a folder" in the brain gets the
   decision recorded, not skipped. The reverse holds too: a folder is no proof
   of a realised project — ask before treating it as one (operator base rule).
2. **The instance ledger is born with the first order:**
   `docs/<domain>/offene-punkte.md` (or the instance's equivalent) per the
   Project Work Ledgers rule — field convention `id`/`class`/`reach`/`origin`
   from day one; the founding order is its first entry.
3. **History goes domain-keyed:** a change log in the domain docs; pillar
   decisions additionally in the decision log (Session Traceability). Ledger
   `class: decision` entries point there — never a second copy.
4. **Memory follows the working directory.** Sessions working IN a project
   repo grow that repo's own auto-memory; the brain memory keeps pointers.
   As soon as a second brain works the project: `reach: shared` entries and
   one-file-one-fact exports to the org's shared-memory repo, with a
   back-reference to the source `id`. **The project gets its own AREA there in
   the same pass** (operator order 2026-10-10): folder + `LOG.md` + a line in
   the README's area list — never filed into the catch-all folder "for now". Carrier: `core/scripts/shared-memory-lint.py`,
   check "project without an area".
5. **Register the ledger with the instance's aggregator.** The generated
   overview sees only registered detail lists — an unregistered domain is
   invisible by construction (deliberate: no silent glob fallback). Adding the
   source line is part of creating the ledger, not a later cleanup.
6. **When the project ships tools:** ecosystem record entry (which state runs
   here), marketplace pin once it becomes a plugin, release discipline
   (preflight, tags, English-only).

None of this is optional per project — a domain that skips a step files
differently than every other and breaks the cross-instance interface.
