- **pre-commit checks a staged changelog fragment's level field** (test: T1) (level: writer; higher: design — one place that
  writes the field for the author would remove the form error; not built, the field is the author's judgement; debt: the
  working-copy fragment is checked, not the staged bytes). Measured on the macOS instance 2026-11-03: six fragments with
  "higher: none" on reader/writer went in and the push lint caught them minutes later, twice. `helpers/git-hooks/pre-commit`
  runs `helpers/change-level.cjs check` when a `changelog.d/*.md` is staged and the repo ships the checker. Fixture
  `scripts/test-pre-commit-change-level.sh` (3 cases; the refused case passed the old hook).
  OS traps register: `test-pre-commit-change-level.sh` joins the OS-3 baseline — it hands no temp path to a native process;
  the hook passes `--root` from `git rev-parse`, which Git Bash already prints in the native form.
  - The English-only ratchet runs in the same hook where the repo ships it (~0.3 s): a German quote in a fragment reached
    the push lint the same day. Fixture +2.
