- **An OS hand check comes once per release, at the head that carries the release commit** (test: T1) (level: writer;
  higher: design — the merge train and release driver asking only at the release head, not built here because the
  driver is still an instance alpha; debt: a request whose check sentence names no OS — "Please, on Windows, at this
  head:" — still passes, the check-word list does not read it; a release named with no head, "for release 2.1.7",
  passes without a lookup). In a repo whose merge takes the CI as OS proof,
  `shared-memory-post.py` refused a hand check of a single PR but let a merge train's PR through - and every late member
  or fix makes a new train head: four Windows hand checks for ONE release on 2026-11-24 (f547c3e, 72c6663, 60ea9e9,
  cbfb4df), about one hour each. The operator's rules name the release as the unit (2026-11-04: a merge counts the green
  Windows CI job, the hand check is for the tag; 2026-11-06: once per OS, nothing twice). A hand check now passes only
  when a named PR or head (`train/…`, `release/…`, `at <sha>`) changes `.claude-plugin/plugin.json`; that check is the
  pin review too. A branch name ends on `[\w-]` (a sentence's full stop is no part of it); a merged, deleted branch is
  judged through its PR; an unreadable lookup is refused as "could not read <head>", never as a measured "no release
  commit". `<repo>#n` without a space binds to that repo (it was read as no PR). Replay over 87 Windows requests
  since 2026-11-06: main refuses 15, this 35; the 20 new holds are train heads and single-PR re-checks, no release head.
