- **session-audit: a saved bootup output under a home path with a space is read whole** (test: T1) (level: reader; higher: writer — the harness writes the path unquoted into its preview, not ours to change; debt: none) — the reader cut the
  "Full output saved to:" path at the first space, so on a Windows home like `C:\Users\First Last` it never found the
  saved file, missed the end marker and reported every long start as "aborted partway". Measured 2026-10-19 on the
  Windows instance: five starts flagged, all five had run through (`=== END BOOTUP ===` in the saved file and in the
  hook's `stdout`). The path now runs to the end of its line. Fixture: the existing persisted case writes its file
  under a folder with a space; without the fix it reports a fourth finding.
