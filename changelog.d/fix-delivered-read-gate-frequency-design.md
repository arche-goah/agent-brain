- **delivered-read-gate states its frequency design** (test: T1)
  (level: reader; higher: design - a frequency field every gate declares in data, not built here because the gate's
  behaviour is right and only the statement the no-cooldown check reads was missing; debt: none new). `brain-friction.py` reported `delivered-read-gate.cjs` as `no-cooldown` on every brain the
  core template wires it into (measured 2026-11-05 on the Windows instance, scanner at #414's head: the only remaining
  candidate). The gate gets the `Frequency design:` paragraph: its trigger is a delivery in this turn, it blocks at
  most once per turn (own echo, `stop_hook_active`), one Read or `unread-ok:` ends it, and a quiet period would pass
  the acting-on-a-description case it exists for. Comment only, no code change.
