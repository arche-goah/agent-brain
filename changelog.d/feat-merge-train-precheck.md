- **merge-train.sh: an instance precheck keeps a PR the train cannot carry out of it** (test: T1) (level: writer; higher:
  design — the train could read the repo's PR-class map itself; not built, the map is instance alpha data today; debt: an
  instance without a precheck command builds trains as before). Measured 2026-11-03 on the macOS instance: train #368 ran
  ~57 min on all three systems and was then held at the merge, because one of its PRs changed the marketplace pin file and
  needs a by-hand review on two instances that no CI job gives. `MERGE_TRAIN_PRECHECK="<cmd>"` is called as
  `<cmd> <owner/repo> <n>` per PR before it joins; a non-zero exit leaves the PR out, named with the command's first output
  line. Fixture `scripts/test-merge-train.sh` +2 (refused PR named with its reason; a passed PR joins).
