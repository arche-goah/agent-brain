- **open-items.py: an open issue whose last word is another instance asking us is our move** (test: T1) (level: reader; higher: writer — the asking instance could also post a shared-memory request, but an issue thread is where collaborators ask, so the reader has to read it; debt: the ask phrases are English words, `ISSUE_ASK`)
  Measured 2026-11-09 on the macOS instance: content-toolsuite#58 — a collaborator's AI wrote "this … waits for an OK
  from your side" on 2026-10-26; no session start named it for two weeks (the reader read PRs, ledgers and the shared
  memory, no issue threads). Now a second search `is:issue is:open` over the same owners: an issue whose last comment
  (or body, without comments) carries another instance's word (login and key, `is_self`) with an ask phrase becomes
  `[issue|ai]`; our own last word or a note without an ask is none. Paged like the PR search; a cut list reads as
  "issue search" unread (measured on the porting machine: 52 open issues, one page holds 50). Fixture:
  `scripts/test-open-items.sh` (ask, own word, note, sibling instance, cut list).
