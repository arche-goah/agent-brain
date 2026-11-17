- **open-items.py keeps a GitHub answer for five minutes** (test: `scripts/open-items-gh-cache-test.py`, 7 cases - the
  same gh call twice reaches GitHub once; `--fresh` asks again and its answer is what the next run reads; an expired
  entry asks again; a failed call and a non-gh command are never cached; no cache file, no cache. Against the script on
  main the fixture fails: there is no cache)
  (level: writer; higher: design - the Stop check could accept a standing measurement everywhere (the core's idle gate
  already takes one of the last 30 minutes), not changed here because the instance still runs its own idle check and
  every reader of the list profits from the cache; debt: the cache file keeps a key for every distinct search it saw,
  a handful per brain). Measured 2026-11-16 on the macOS instance: in an autonomous run the Stop check asked for a
  fresh list at every turn end, one session ran this script more than twenty times within an hour, and the account's
  GitHub budget fell to 22 % - the collaboration watch slowed to its 25-minute floor for every repo. Each run sends
  the same GraphQL searches; minutes apart they give the same answer. `run()` now keeps a successful `gh` answer in
  `.claude-state/open-items-gh-cache.json` for `OPEN_ITEMS_GH_CACHE_TTL` seconds (default 300); `--fresh` bypasses it. A TTL that is no whole number (`5m`) falls back to 300 with one stderr line instead of ending the list in a ValueError (Windows review 2026-11-17; test case 8, red against the first head).
