- **Acceptance: an optimizer is judged on the image, not only on what it measured** (test: T0)
  (level: writer; higher: design — a projector check in acceptance.py itself (incidence, brightness, focus); one
  case so far, the skill step carries it until a second one; debt: no mechanical check of a projector's image).
  `skills/acceptance-before-handover` step 4 (Reality): a search that places devices optimizes only its own metric;
  for a projector the image itself is checked too (incidence at most about 55°, brightest vs. darkest spot, focus,
  lens shift before tilting). Measured 2026-11-25 on a Windows instance: a projector tilted 64° up came out of a
  search that only minimized shadows. Ported from that instance's acceptance skill, where it was added the same day.
