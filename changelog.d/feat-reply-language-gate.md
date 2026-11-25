- **Stop check: the reply is in the instance's declared chat language** (test: T1)
  (level: writer; higher: design — one declared language that every language-aware gate reads (today each
  template carries its own word lists); this PR adds the field and its first reader only; debt: the other
  gates' word lists still stand on their own).
  New `helpers/reply-language-gate.cjs`, opt-in in the stop-checks template (`_optional_checks`). The instance
  declares its language and that language's unambiguous function words in `.claude/rules/reply-language.json`
  (the core ships the English list only, as every language-aware gate does); missing file, "en" or no words =
  the check does nothing, so an English brain carries no cost. A reply with at least 12 unambiguous English function words and
  more of them than of the declared language blocks; code, inline code, quotes, blockquotes, paths, links and
  command output (`<bash-stdout>`) are not counted. `--record` writes instead of blocking, `--replay <dir>`
  measures a brain's false alarms before it switches the check on. Origin: a Windows instance answered its
  German-speaking operator in English several replies in a row (2026-11-09); its local alpha ran since then.
  Replay of this gate over that instance's November transcripts (2026-11-25, terse German output style): 443
  replies, 2 flagged, both truly English, 0 false alarms. Fixture: `--selftest`, 11 cases.
