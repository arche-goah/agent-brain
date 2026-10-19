- **shared-memory-lint: stdout pinned to UTF-8, so `--inventory`/`--json` files parse on Windows** (test: T1) — OS-9,
  one more site where the answer to "does anything parse this output?" is yes: `shared-memory-dream` redirects
  `--inventory` into a JSON file its agents read. Measured on a Windows brain (2026-10-18 at core #24, again
  2026-10-19): unpinned, Python wrote the platform codepage, a description's `·` left as 0xb7 and a planted accented
  letter as its single cp1252 byte, so the file was no valid UTF-8 JSON. Fixed at the producer (`sys.stdout.reconfigure` in `main()`, like
  `open-items.py`). Fixture: `portability-smoke.sh` pipes `--inventory` of a planted entry with accented letters and parses it
  as UTF-8 JSON — fails without the pin on Windows. OS-9 note updated.
