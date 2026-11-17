- **os-review: a structured OS OK the readers take as is, and a poster that writes it — ported from an instance alpha** (test: T1) (level: writer; higher: design — the OS check as a GitHub check run or review state would need every instance's posting step and a token with checks rights; debt: an OK written by hand without the form is still judged by its words)
  Measured 2026-10-28 on the macOS instance: the OS reader dropped an OK whose line also held "open" (a fixture
  name), "pending" or "0 missing"; three merges were held in one day (#164, #193, #192), and every narrowing of the
  word lists since (#187, #324, #473, #529) fixed the next wording, not the form. `helpers/os-review.cjs` now reads
  one HTML comment line `<!-- os-review: os=<OS> verdict=ok|fail head=<sha> -->`; where a text carries it for an OS,
  it alone is that text's verdict (`handReview` for release-preflight check 8 and content-review-gate, and
  `merge-request-gate` through the same `formSays`); a void line leaves the prose reader. `scripts/post-os-ok.sh
  <owner/repo> <pr> <OS> <details-file>` writes it for the PR's branch head read with `git ls-remote`, with the
  instance key from `instance_key.py` (none = nothing written), into `<details>.os-ok.md`, and prints the post line
  for the session to run - it never posts itself (Windows review 2026-11-17, finding: a post from inside a script is
  invisible to public-text-guard and instance-key-gate, the leak class of 2026-11-12); the instance alpha had the
  repo, the OS and the key in its code. Fixture `scripts/test-os-ok-form.sh` (20, both directions, incl. a class
  guard that the script calls no post); against main's reader 4 cases are red
  (a fail form, another head, reordered fields, the merge gate with a fail form) — main reads an OK form line as
  prose by chance ("macOS verdict=ok"), which is why the OK cases pass there.
