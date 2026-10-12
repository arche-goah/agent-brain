- **A mechanism rule may demand the operator's word behind `MECHANISM-OK`.** (test: T1) New field
  `needs_operator_word: true` on a rule (instance file and tool-shipped `mechanism-rules.json` alike).
  For such a rule the marker opens the command only if its justification quotes the operator (`"…"`,
  `„…"` or `“…”`, at least three characters) together with the date it was said (YYYY-MM-DD), or points
  at a record file that exists (`path[:line]`, `.md/.txt/.json/.jsonl/.yaml`; a line beyond the file's
  end does not count, nor does a script). Otherwise the guard denies and names what is missing. Rules
  without the field keep today's behaviour — a brain that never sets it sees no change. Why (operator
  decision 2026-10-12, item 7b of the coherence follow-up): measured 2026-09-12, two merges in a shared
  repo carried the marker with a verbatim operator quote that stands in no transcript of that day; an
  unspecific order had been smoothed into a crisp permission while writing the marker, and the invented
  evidence hid the very gap the marker exists to show. The guard cannot read the transcript, but it can
  refuse the shape that lets a paraphrase pass as a quote. Fixture `scripts/test-guards.sh`: 15 new
  probes — no marker, bare marker, quote without date, date without quote, empty quote, pointer beyond
  the file's end, pointer to a missing file and to a script all deny; quote plus date (ASCII and low-9
  quotes) and a pointer to an existing record pass; the unflagged rule next to it still passes on a bare
  marker and still denies without one (controls). Template `templates/rules-instance/mechanism-rules.json`
  carries one commented example (a marketplace pin); `rules/working-rules.md` and `CONVENTIONS.md` §4
  name the field.
