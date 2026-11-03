- **brain-update: provenance auto-heal - a cache that is not the pinned release is reinstalled and checked again**
  (test: T1) (level: writer; higher: design - the harness's plugin cache could key by source commit instead of
  name and version, outside this repo; debt: a reinstall changes what loads, so the run asks for a restart, and a
  reinstall that fails offline leaves the old FAIL line with its hand command). Decided by the macOS and the
  Windows instance on 2026-08-20 (nine occurrences on two machines in one day, the same hand fix every time:
  uninstall + install), then parked and never built. On a provenance mismatch whose cached version is not the
  pinned one, `scripts/brain-update.sh` now runs `claude plugin uninstall <p> --scope <s>` and
  `claude plugin install <p> --scope <s>` itself, reads record and cached version again, and prints
  `provenance auto-heal: … reinstalled and re-checked` when they now match the pin (a restart is required). Only a
  mismatch that survives the reinstall stays FAIL — real foreign content is never overwritten silently, the
  re-check is the line between healing and covering up. A stale record over the right content stays a NOTE as
  before. Fixture `scripts/brain-update-test.sh` case 7 with a `claude` stub: a reinstall that fixes the cache
  heals and leaves no FAIL line; one that changes nothing stays FAIL (negative control: the old code prints no
  auto-heal line).
