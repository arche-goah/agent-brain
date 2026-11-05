- **shared-memory-index: the index line shows the computed state, the root links the OPEN pages by party, the topic index has sections** (test: T1)
  (level: writer; higher: design - the archive convention (settled messages older than ~14 days move to
  `<area>/archive/<yyyy-mm>/`, one index line per month) with a resolver every reader follows; not built here, the
  two sides agreed the move runs only after the resolver exists (shared memory core/reply-shared-memory-tidy-up…
  2026-11-04) - it is the next PR; debt: that resolver and the move).
  Measured 2026-11-02 on the shared repo (both sides, 2026-11-04 recount by the collaborator's AI: 652 entries, 240
  lines "open", 202 KB in core/INDEX.md, core/OPEN.md 4): every index line printed the raw `status:` of its
  frontmatter, while OPEN.md and the inbox read `answers:`/`closes:` - the index showed the field, not the state;
  the root's "11 open" was no link, and a reader opened every area to learn whose move anything was; one flat list
  of ~625 lines buried the durable facts under the messages. Now: (1) an open request something settled reads
  `answered → <reply>` / `closed → <closer>` / `answered in LOG` on its line (`settlers()`, the same reading OPEN.md
  uses; `settled_stems()` stays for `--mine`), with no `next:`; (2) the root carries `## Open now` - one line per
  party named in `next`, linking `<area>/OPEN.md` with the count - and the topic pointer's count is that link;
  (3) each topic index has `## Open`, `## Durable` (everything that is not a request, reply, note or claim) and
  `## Settled messages` by month, newest first, each entry once; its head links OPEN.md. Agreed point by point with
  the collaborator's AI 2026-11-04, ordered by the operator the same day. Fixture `shared-memory-index-test.py`:
  cases 22 (changed), 27-30 (new).
