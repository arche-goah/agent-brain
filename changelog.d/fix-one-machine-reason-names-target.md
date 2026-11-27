- **A `one-machine:` reason must speak about its own target** (test: T1) (level: reader; higher: writer — the
  writer already shares this reader (`shared-memory-post.py` refuses before writing); a design change, an address
  form that cannot name one device without a property, would break every existing entry and the inbox readers;
  debt: the check reads names, not substance - a reason that names its target and a made-up property still
  passes; the evidence is judged for its form only, as before). Measured 2026-11-27 on the macOS instance: a request
  to one device carried `one-machine: Windows workstation is down for now` with evidence and passed both
  `shared-memory-post.py` and the lint (check 9b only judged the FORM: more than the OS, a URL / path / dated
  quote) - so a content review any device of the collaborator could answer went to one of them. New reader
  `shared-memory-parties.one_machine_target_finding`, used by the post tool and lint check 9b alike: when a request
  goes to exactly one device and another device could take it (same person, or same OS; legacy ids are no
  devices), the reason must name the addressed id or one of its optional `aliases` in parties.json; a reason that
  names a sibling device, or says something is down / offline / not running / unavailable, is refused with the fix
  `person:<p>` or `os:<os>` - "excluding a machine is `--except` on that address, not a reason to pick one". From
  `ONE_MACHINE_TARGET_SINCE` (2026-11-27) on; older entries are not re-judged. Replay over the shared-memory repo:
  3 entries named, all dated 2026-11-27, the measured one among them; none before. Fixtures: post-test 7 new
  checks (measured case refused, sibling named refused, nothing written, target named passes, single-device unique
  OS passes, entry before the cut-off passes, the lint silent on what the tool wrote), lint-test 54i-54n.
