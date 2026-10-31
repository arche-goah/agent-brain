# The shared-memory format

A shared memory is ONE private git repository that several brains (and the people behind
them) read and write. This page is the format in one place, for a team that sets one up from
scratch. The scripts named here enforce it; their docstrings carry the measured reasons.

## Layout

```
<shared-memory>/
  README.md            the repo's own rules and the list of areas (one line each)
  PEOPLE.md            who takes part: a section per person, their devices, since when, for which areas
  parties.json         machine-readable people -> devices (+ handover settings), read by the scripts
  INDEX.md             GENERATED root index: one line per area
  devices/<device>.json  each device reports its own state (core version, suites, watch, activity)
  <area>/              one folder per area (a project or a domain); the folder IS the unit of scale
    INDEX.md           GENERATED: one routing line per entry
    OPEN.md            GENERATED: every open entry that lives here or is filed here
    LOG.md             running notes, append-only, chronological
    <entry>.md         one file per fact
```

A new area is a new folder plus its line in the README list; a new repo only when someone may
see just one area that others must not (a real access boundary, which folders cannot give).
Knowledge that belongs to a tool (protocol details, gotchas) lives in that tool's suite, not
here — this repo holds coordination: who does what, which state, which decision.

## One file per fact

```markdown
---
name: <kebab-case-slug, same as the file name>
description: "<one line for the index>"
metadata:
  type: project | feedback | reference | decision
  von: <person>-<device>          # the writer; an AI writes, a person is quoted
  audience: <device>[, …] | person:<p> | os:<macos|windows|linux> | <all>
  topic: <area>                   # the folder it lives in
  date: <YYYY-MM-DD>              # the date the entry is about, not the last edit
  status: open | decided | superseded | info | answered | done | closed
  next: <device>[, …]             # who is on the move; required while status is open
  related: [<area>/<entry>.md, …]
  topics: [<area>, …]             # further areas it is filed into; never copied or moved
  supersedes: <area>/<entry>.md
  answers: <area>/<entry>         # this entry settles a request
  closes: <entry>.md              # the asker settles their own request
---

<the fact; dates absolute, a measurement with its date and how it was measured>
```

- `audience` is the ADDRESSEE, never the area; `topic` is the area. Both are required, so
  "who is it for" and "what is it about" stay separately searchable
  (`shared-memory-audience.md`).
- The routing fields (`status`, `next`, `related`, `topics`, `supersedes`) and how the indexes
  use them: `shared-memory-fields.md`.
- A person's words enter only quoted, with name and date; otherwise the entry says it is
  derived.

## The LOG of an area

For what does not deserve its own file: status pings, "testing X now", interim results. One
heading per entry — date, writer, a short title — then two to four lines. A LOG is
append-only for its headings: an answer can refer to a heading by its place that day
(`<area>/LOG@<date>#<n>`). A LOG entry that turns into a lasting decision moves into its own
file; the LOG line stays as the trace.

## Who decides: the circle

Every decision names the smallest circle that contains everyone whose terrain it touches —
when in doubt one level higher, never lower:

| Code | Circle | For |
|---|---|---|
| A | one AI alone | technical, reversible, own terrain, inside an agreed frame |
| B | one side: a person and their AI | that person's matter: money, hardware, risk, release, publication |
| C | the AIs of several sides | shared technique inside the agreed frame: format, interface, merge, division of work |
| D | the AIs of several sides plus ONE person | touches exactly one person's terrain; the others are informed |
| E | the AIs plus SEVERAL people | direction, outward effect, shared carriers |
| F | person to person, no AI | decided directly; an AI records the result |

Irreversible means at least E.

## The scripts (in this core)

| Script | Does |
|---|---|
| `shared-memory-post.py` | writes a request, note, reply or claim — ONE way, with its state fields |
| `shared-memory-lint.py` | the deterministic checks: fields, vocabulary, dead links, LOG headings (also `--staged` at commit) |
| `shared-memory-index.py` | generates `INDEX.md`, `<area>/INDEX.md`, `<area>/OPEN.md`; `--since` for fresh entries, `--mine` for "your move" (with #196) |
| `shared-memory-inbox.py` | what was pushed FOR this device, as readable lines (session start) |
| `device-status.py` | which device runs which core and suites, from `devices/<device>.json` |

## Writing rules

- Push an entry straight to `main`, never as a PR: it is a message, not a change under review.
- Commit the entry together with the indexes the post script regenerated, or the next
  `pull --ff-only` is blocked.
- On a push race, rebase your OWN one commit and push again; never rewrite anyone else's.
- No secrets, no credentials, no live state that a tool can read (addresses in use, links,
  counters) — identity is written, state is read.
