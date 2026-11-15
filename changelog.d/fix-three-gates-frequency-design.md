- **commitment-carrier-gate, autonomous-idle-gate and decision-presentation-gate state their frequency design**
  (test: `scripts/brain-friction.py` check 4 - 3 `no-cooldown` hits on the Windows instance at the v2.1.3 pin; each
  edited file now carries the `Frequency design:` marker that check reads)
  (level: reader; higher: design - a frequency field every gate declares in data, not built here for the same
  reason as #415: the gates' behaviour is right and only the statement the no-cooldown check reads was missing;
  debt: none new). The brain-check on the Windows instance listed the three as `no-cooldown` on 2026-11-07, the
  same class #414 and #415 closed for close-loss-gate and delivered-read-gate. Each gets the `Frequency design:`
  paragraph: what triggers it (a promise in this turn, the autonomous mode or released work, the asking moment),
  how often it blocks and what ends it. Comment only, no code change.
