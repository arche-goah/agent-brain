- **New `scripts/sync-after-merge.py`: after a data PR is merged, untracked local copies are removed only where the
  merged ref holds the same path with the same blob, then `pull --ff-only`** (test: `scripts/sync-after-merge-test.py`,
  seven cases in real throwaway repos) (level: writer; higher: design - not taken, the app writing its data untracked
  into the operator's copy is the project's choice, the tool makes the hand-over safe; debt: none). Ported from an
  instance where it ran since 2026-11-02 (measured there: removing the local copies by hand in the same batch as a merge
  call that a gate held deleted 22 measurement files until the merge went through). Two defects of the instance copy
  are fixed and pinned by the fixture, which is red against it (6 of 7): `ls-files` output split on whitespace turned
  a path with a space into two (the run crashed on `hash-object`), and exit 1 came only from a failed pull although the
  docstring promised it for any file left behind. Now NUL-separated, exit 1 for a failed pull or a kept file (each
  listed with its reason, never removed), exit 2 when it cannot run; `--ref` names the merged ref (default origin/main).
