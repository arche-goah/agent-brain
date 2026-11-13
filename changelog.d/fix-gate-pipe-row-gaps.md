- **mechanism-rules: the gate-through-a-pipe row also holds `2>&1 |`, a quoted path with a space, an interpreter
  flag and a gate on its own line** (test: T1) (level: reader; higher: writer — a gate that fails loudly through any
  pipe would need every gate script changed; not in reach of one row; debt: other runners than bash/sh/python/node,
  e.g. `pwsh`, stay unseen) — review finding on #448 (2026-11-12, the Windows instance): the row ported there let its
  commonest shape through, `leak-scan.py 2>&1 | tail` (the `[^|;&]*` stopped at the `&` of `2>&1`), the way this
  machine names any absolute path (a quoted path under a home directory with a space), `python3 -I …` and a gate on a
  new line. Five probes in `scripts/test-guards.sh`; with the old row the four block probes are red (measured on
  Windows, Git Bash), with this one all pass. The allow cases stay: exit code read alone, `git show … | sed`.
  Same class, searched over every row: the two foreground-wait rows (`ci-watch.sh pr|ref`, `wait-*.sh`/`*-watch.sh`)
  missed a quoted script path with a space too (`(?:\S*/)?` stops at the space; measured with a probe) — their path
  prefix now takes a quoted path as well, two more block probes, red against main's rules.
