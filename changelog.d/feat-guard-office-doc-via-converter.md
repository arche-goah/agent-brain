- **mechanism-rules: an office file is built through the office skill, not by a generic converter** (test: T1) (level: writer; higher: design — a check of the finished file (page size, sizes) would also catch a skill that writes it wrong, not built: the skill sets them explicitly and no such case is measured; debt: other converters (e.g. a script library writing docx directly) are not covered)
  Measured 2026-11-11 on the macOS instance: a one-page Word document built with `textutil -convert docx` turned 10.5 pt
  into 12 pt and wrote no page size or margins; in Word it ran over to a second page. The same shape exists for pandoc
  and `soffice --convert-to` on every OS, so the row is a core row (an instance had added a textutil-only row the same
  day). Reading an office file into text or Markdown stays free. Fixture `scripts/test-guards.sh` +5 (3 red against
  main, 2 controls).
