- **shared-memory-post: a request to one machine needs a real reason and evidence** (test: T1) (level: writer; higher:
  design — the device list could say which machine owns which asset, so the tool picks the one machine itself; not
  built, no such inventory exists; debt: whether the named device is running is still not measured). The operator,
  2026-11-03 (translated): "an explicit request to one instance must be clearly reasoned and evidenced, otherwise it
  must not go through". Measured the same day on the macOS instance: five requests in the shared memory carried
  `--one-machine "the Windows instance is the machine that does it"` or "a Windows check at the PR head; ..." - the
  OS-category gate was passed with the OS itself as the reason, and the last two requests went to a Windows device
  that was not running while every other Windows machine never saw them. `request --one-machine` now refuses a reason
  that names only the OS and requires `--one-machine-evidence` (URL, existing file `path[:line]`, or the operator's
  quoted words with their date), written beside the reason. Replies and notes are unchanged. Fixture
  `scripts/shared-memory-post-test.py` +4 refusals; the passing case now carries evidence.
