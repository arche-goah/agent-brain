- **session-pull: an ended session's leftovers no longer stop the brain pull; memory-sync: no export onto a snapshot the upstream moved past**
  (test: T1) (level: writer; higher: design — a pending area outside the tracked snapshot that the close takes over
  would remove the leftovers at their source; not built: the operator chose the smallest form on 2026-11-16; debt:
  the hooks still write into the tracked tree, the start commits what they leave) — measured 2026-11-16 on a
  Windows instance: 28 brain commits since 2026-10-15 touch `docs/memory-snapshot/`, several of them leftovers of
  sessions that ended without the close; each such start reported "uncommitted changes" and skipped the brain pull.
  `helpers/session-pull.sh`: when the brain's ONLY changes are `docs/memory-snapshot/` and
  `docs/maintenance/session-log.md`, the brain is fetched and fast-forwarded anyway (git refuses the fast-forward
  itself when incoming commits touch the same files) and the leftovers are committed by path afterwards, never
  pushed; any other change next to them keeps the old behaviour. `helpers/memory-sync.cjs` export: held with one
  line when the last-fetched upstream has commits on `docs/memory-snapshot/` this checkout lacks (pull, import,
  then export; no fetch inside the hook). Fixtures: `scripts/test-session-pull.sh` (+6: pulled and committed,
  clean tree, commit message, stderr line, a real edit next to a leftover still blocks) and
  `scripts/test-session-helpers.sh` (+3: held while behind, says why, runs once level); against main 4 and 2 of
  them fail.
