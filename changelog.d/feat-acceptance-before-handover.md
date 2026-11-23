- **Acceptance before handover: a result reaches the operator only with a fresh acceptance next to it** (test: T1)
  (level: design; higher: none; debt: results that are no file (chat text, live interfaces) are carried by the skill
  text only). New skill `acceptance-before-handover` and its carrier `scripts/acceptance.py` (`write`, `check`,
  `open`, `selftest`): `open` shows an image only when `<result>.acceptance.json` is newer than the result and names
  the inventory of everything visible, the operator's facts checked, and what fresh eyes (an agent with only the
  result and the operator's words) reported. Why, measured in one instance session 2026-11-23: images went to the
  operator with dimension labels, helper light cones, candidate markers, spot lights of an old variant, round light
  spots for a projector and a cabinet the operator had said does not exist; the agent had checked its own list and
  its measurements, never the whole result. The skill also names why the operator's word gets translated instead of
  followed (order fidelity #4a). Fixture: `python3 scripts/acceptance-test.py`.
