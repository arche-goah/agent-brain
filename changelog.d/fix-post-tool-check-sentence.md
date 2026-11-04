- **shared-memory-post: a check word rules its sentence, not the whole text; a bare PR number follows the repo its sentence names** (test: T1)
  (level: writer; higher: design - a parsed request grammar (verb, OS, PR) instead of regexes over sentences; not built, the
  four measured misreads are all sentence-scope errors; debt: a check sentence that names two repos still binds a bare
  number to the default repo).
  Measured 2026-11-04 on the macOS instance: four correct requests refused in one day. "checked on macOS: 7/7" in the
  evidence was read as a macOS request to a Windows audience; "#402 fixes the red CI" bound the CI check to a PR nobody
  asked a check for; "#233, #234" next to a grandma3-suite PR URL were read as core PRs and judged by the core's CI; the
  pin rule quoted in a request ("on Windows and on macOS") counted as a macOS request. Each check was right in intent
  (lint 9b, green CI before a check) and read words instead of references. Now `os_check_misaddressed` and
  `os_check_not_ready` look only at the sentences that carry a check word: an OS counts as asked only there, a PR number
  binds the CI check only there, a bare `#n` in a sentence that names one repo (`owner/repo#n` or a PR URL) belongs to
  that repo, and "checked" (a report) is no check word. Fixture `scripts/shared-memory-post-test.py`: six new cases, the
  stub `gh` answers per repo.
