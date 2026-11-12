- **release-scope: no scope before a pin is due — `open` takes the operator's word naming the release** (test: T1)
  (level: writer; higher: design — the release tool could open the scope itself at the tag step, so no session
  ever decides the moment; not built: needs the merge-train/tag tool and its own agreement; debt: the quote is not
  yet proven said, and "acutely due" is the operator's word, not a measured state) — operator 2026-11-12,
  translated: "As long as no pin is acutely due, the train is collected. How do you come to say now what will be in
  the train in maybe several days and automatically exclude everything else? That is exactly the opposite of how
  we want to work." Measured the same day on the macOS instance: `release-scope.py open 2.1.6` ran right after a
  train merge with no pin or tag due; from then on the release was an opt-in list, leaving anything out needed the
  operator's quoted word, and `helpers/release-freeze-gate.cjs` held every new core branch outside it — an early
  scope turned "the train is open" into "the train is closed". `open` now refuses (rc 3) without
  `--operator-word '"<their words, at least three>" <YYYY-MM-DD>'` (the form of RELEASE_EARLY_OK and
  RELEASE_SCOPE_EXCLUDE_OK), says the train is open and collects everything until a pin is due, and stores the word
  in the scope file; the freeze gate reads an open scope without `operator_word` (opened before this rule) as
  holding nothing. No scope is the normal state: the gate and open-items already pass it; preflight check 11 still
  demands a scope at the tag, its message now names the word. Docs: the script's docstring, pr-watchdog step 0,
  AGENTS.md, helpers/README. Fixtures: `scripts/release-scope-test.py` 34/34 (+7: refused without the word, without
  a date, unquoted, one-word quote; stored; shown; reopen after close needs it), `scripts/test-release-freeze-gate.sh`
  21/21 (+1: an open scope without the word holds nothing); against main 25/34 and 20/21.
