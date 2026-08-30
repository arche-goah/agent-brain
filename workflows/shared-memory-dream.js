export const meta = {
  name: 'shared-memory-dream',
  description: 'Judgment pass over the shared-memory repo (read-only): duplicates, contradictions, superseded entries, buried open points — report with proposals, no fixes',
  whenToUse: 'The judging half of the shared-memory tidy-up, after shared-memory-lint has settled the mechanical half. Call with args {date:"YYYY-MM-DD", shared:"<abs. path to the shared-memory repo>"}. Fixes NEVER run from here — a shared repo needs the OTHER party\'s OK, not just the operator\'s.',
  phases: [
    { title: 'Inventory', detail: 'Index + frontmatter table of the whole repo', model: 'haiku' },
    { title: 'Analysis', detail: 'Four lenses in parallel over the real files' },
    { title: 'Verify', detail: 'Adversarial re-check of every finding' },
    { title: 'Report', detail: 'Findings by class, each with a proposal and an owner' },
  ],
}

// ── Configuration ──────────────────────────────────────────────────────────
// Never hardcode instance paths (core rule). The REPORT goes into the private
// instance, never into the shared repo: it names who wrote what and what looks
// contradictory, which is exactly the kind of judgment that should not land in a
// repo the other party reads before they have seen it.
const INSTANCE = (typeof args === 'object' && args && args.repo) || '.'
const REPORT_DIR = `${INSTANCE}/docs/research/shared-memory-tidy`

let A = args
if (typeof A === 'string') { try { A = JSON.parse(A) } catch (e) { A = null } }
if (!A || !A.date || !A.shared) {
  throw new Error('shared-memory-dream requires args {date:"YYYY-MM-DD", shared:"<abs. path>"} — date via `date +%F`, shared = the cloned shared-memory repo')
}
const DATE = A.date
const SHARED = A.shared
const REPORT = `${REPORT_DIR}/report-${DATE}.md`

// The one framing that separates this from memory-dream: a SECOND author exists, and
// "wrong" is usually "measured somewhere else", not "mistaken".
const COMMON = `You audit a SHARED memory repo at ${SHARED}/ — STRICTLY READ-ONLY, you
change NOTHING, you propose. Layout: INDEX.md at the root links every entry; one fact per
file under <topic>/<slug>.md; LOG.md files are append-only protocols; frontmatter carries
name, description, metadata.type/von/audience/topic.

WHAT MAKES THIS REPO DIFFERENT FROM A PRIVATE MEMORY, and it changes every judgment you
make: it is written by SEVERAL parties — different instances of the same operator plus an
external collaborator. Consequences you must hold on to:

1. The \`von:\` field says WHO wrote an entry, and it is the only reliable discriminator.
   Two instances can push under the SAME git account, so never infer the author from git
   history — read the field.
2. Two entries that disagree are usually NOT one mistake. They are more often the same
   thing measured on two different machines, two software versions, or two shows. Before
   calling anything a contradiction, ask what would have to be true for BOTH to be right,
   and say so in the finding. A real contradiction survives that question.
3. A file written by the other party is never "wrong" in your report. Findings about it
   are questions or observations addressed TO them, and the report must name whose call
   each proposal is.
4. Deletion is never a proposal. This repo's protocol files are append-only, and its fact
   files are the shared record of a collaboration. The strongest move you may propose is
   ARCHIVE (move under archive/<year>/, keep a one-line index entry pointing at the new
   path) or MERGE (one file absorbs another, the absorbed slug keeps a pointer).

Every finding needs file + a verbatim quote. Return value = raw data via StructuredOutput,
not prose for a human.`

const FINDINGS_SCHEMA = {
  type: 'object',
  required: ['summary', 'findings'],
  properties: {
    summary: { type: 'string' },
    findings: {
      type: 'array', maxItems: 15,
      items: {
        type: 'object',
        required: ['klass', 'severity', 'title', 'claim', 'sources', 'proposal', 'owner'],
        properties: {
          klass: {
            type: 'string',
            enum: ['duplicate', 'contradiction', 'superseded', 'stale', 'buried', 'open-question'],
          },
          severity: { type: 'string', enum: ['P0', 'P1', 'P2', 'INFO'] },
          title: { type: 'string', description: '1 line, concrete' },
          claim: { type: 'string', description: 'What exactly overlaps / collides / is out of date' },
          sources: {
            type: 'array', minItems: 1, maxItems: 4,
            items: {
              type: 'object', required: ['file', 'quote'],
              properties: {
                file: { type: 'string' },
                quote: { type: 'string', description: 'verbatim, shortened ok' },
                von: { type: 'string', description: 'the metadata.von of that file, if present' },
              },
            },
          },
          both_right_if: {
            type: 'string',
            description: 'For contradiction/superseded: the condition under which BOTH entries are correct (different machine, version, show). Empty only if none exists — that is what makes it a real contradiction.',
          },
          proposal: { type: 'string', description: 'merge / archive / add-pointer / ask — an option, never an instruction. Never delete.' },
          owner: {
            type: 'string',
            enum: ['us', 'other-party', 'operator', 'both'],
            description: 'Who can decide this: us = the writing instance, other-party = whoever the von: field names on the other side, operator = goal/money/hardware/risk, both = needs agreement',
          },
        },
      },
    },
  },
}

// ── Phase 1: Inventory ─────────────────────────────────────────────────────
// DETERMINISTIC, not judged: `shared-memory-lint.py --inventory` emits the table.
//
// This was an agent once, and the first real run showed why it must not be: asked for
// "a compact table of the repo", it returned ONE row — path = the repo root, count = 1,
// a tidy summary that satisfied the schema perfectly — and four analysis lenses then ran
// on nothing. Enumeration is mechanical, so the machine does it and the agent only
// carries the output across. Same principle the lint itself is built on.
phase('Inventory')
// Default is the consumed layout (`<instance>/core/scripts/...`); `args.lint` overrides
// it, which is what makes this workflow runnable against a dev checkout at all — without
// the override it can only ever be proven on an instance that already ships the release
// being tested, which is no proof.
const LINT = A.lint || `${INSTANCE}/core/scripts/shared-memory-lint.py`
const inv = await agent(
  `Run exactly this, once, and return its output UNCHANGED as your structured result:

    python3 ${LINT} --repo ${SHARED} --inventory

It prints JSON with count, files[] and logs[]. Do not summarize it, do not re-order it,
do not drop rows: you are a pipe, not a reader. If the command fails, return count 0 and
an empty files array so the run stops instead of guessing.`,
  { label: 'inventory', phase: 'Inventory', model: 'haiku', schema: {
    type: 'object', required: ['files', 'count'],
    properties: {
      count: { type: 'number' },
      index_bytes: { type: 'number' },
      files: {
        type: 'array', maxItems: 400,
        items: {
          type: 'object', required: ['path'],
          properties: {
            path: { type: 'string' }, von: { type: 'string' }, type: { type: 'string' },
            audience: { type: 'string' }, topic: { type: 'string' },
            description: { type: 'string' }, indexed: { type: 'boolean' },
          },
        },
      },
      logs: { type: 'array', maxItems: 20, items: { type: 'object', properties: { path: { type: 'string' }, bytes: { type: 'number' } } } },
    },
  } },
)
if (!inv) throw new Error('inventory agent failed')
// A degenerate table is the failure this phase exists to prevent — catch it here rather
// than letting four lenses burn their budget on it.
if (!inv.files || inv.files.length < 2 || inv.count !== inv.files.length) {
  throw new Error(`inventory looks degenerate (count=${inv.count}, rows=${(inv.files || []).length}) — expected one row per fact file; check that ${LINT} --inventory runs`)
}
log(`${inv.count} files inventoried (deterministic)`)

// ── Phase 2: Analysis (four lenses, in parallel) ───────────────────────────
// Judgment — session model. Each lens gets the inventory so it can target its reads.
phase('Analysis')
const TABLE = JSON.stringify(inv.files).slice(0, 60000)

const LENSES = [
  {
    slug: 'overlap',
    prompt: `OVERLAP: find files that carry the SAME fact. Typical shape here: a question file,
an answer file, a follow-up and a correction all about one topic, written over several days
by both parties — that is a legitimate thread, NOT a duplicate. A duplicate is two files a
reader must both find to get one fact, with no pointer between them. For each: which file
absorbs which, and what the absorbed one leaves behind as a pointer.`,
  },
  {
    slug: 'collision',
    prompt: `COLLISION: find entries that state opposing things. For EACH, before you report it,
work out what would have to be true for both to be right — different machine (macOS vs.
Windows onPC), different software version, different show, different point in time. Fill
both_right_if with that condition. Report the finding either way, but a collision with an
empty both_right_if is a P1 and one with a plausible condition is INFO plus a proposal to
say the condition out loud in both files.`,
  },
  {
    slug: 'currency',
    prompt: `CURRENCY: find entries reality has overtaken — a question that has since been
answered in another file, a decision that has since been made, a proposal that has since
shipped, a "still open" that is closed. Check against the repo itself AND, where an entry
names a PR/tag/release, against that (gh pr view / git tag are allowed, read-only). A
superseded entry is not wrong, it is unmarked: the proposal is a pointer line, not a
deletion.`,
  },
  {
    slug: 'findability',
    prompt: `FINDABILITY: the operator's actual complaint is that this repo is getting hard to
use. Look at INDEX.md as a READER arriving cold: are the entries that are OPEN and need
someone's action visible near the top, or buried among settled ones? Is anything important
reachable only by knowing the filename? Which entries could be one line shorter without
losing the fact? Report the worst offenders concretely (klass 'buried'), and any file that
asks a question of the other party with no visible answer anywhere (klass 'open-question').`,
  },
]

const analyses = (await parallel(LENSES.map(l => () =>
  agent(`${COMMON}\n\nFILE TABLE (from the inventory, use it to target your reads):\n${TABLE}\n\n${l.prompt}`,
    { label: `lens:${l.slug}`, phase: 'Analysis', schema: FINDINGS_SCHEMA }),
))).filter(Boolean)

if (!analyses.length) throw new Error('all analysis lenses failed')
const raw = analyses.flatMap(r => r.findings)
log(`${raw.length} raw findings from ${analyses.length}/${LENSES.length} lenses`)

// ── Phase 3: Verify (adversarial, per finding) ─────────────────────────────
// A judgment pass that reports its first impression is a rumour generator. Each finding
// is handed to a skeptic whose default is "not a finding".
phase('Verify')
const VERDICT_SCHEMA = {
  type: 'object', required: ['stands', 'why'],
  properties: {
    stands: { type: 'boolean' },
    why: { type: 'string' },
    corrected_severity: { type: 'string', enum: ['P0', 'P1', 'P2', 'INFO'] },
  },
}

// Four lenses at up to 15 findings each is 60 verify agents — more than this whole pass
// is worth, and past any sane workflow size. Cap it, but say what fell off: a silent cap
// reads as "everything was checked" when it was not (no-silent-caps rule).
const VERIFY_CAP = Number(A.verifyCap) || 20
const RANK = { P0: 0, P1: 1, P2: 2, INFO: 3 }
const ordered = [...raw].sort((a, b) => (RANK[a.severity] ?? 9) - (RANK[b.severity] ?? 9))
const toVerify = ordered.slice(0, VERIFY_CAP)
const dropped = ordered.slice(VERIFY_CAP)
if (dropped.length) {
  log(`verify capped at ${VERIFY_CAP}: ${dropped.length} lower-severity finding(s) NOT verified — they go into the report marked unverified, not silently dropped`)
}

const verified = (await parallel(toVerify.map((f, i) => () =>
  agent(`${COMMON}

REFUTE this finding. Open the cited files yourself and read them in full — the quote may be
out of context. Default to stands=false when uncertain. Specific traps in this repo:
- a thread of question/answer/correction over several days is NOT a duplicate;
- two measurements from different machines or software versions are NOT a contradiction;
- an entry that labels itself a snapshot or work-in-progress is not stale for saying so;
- a proposal marked as awaiting someone's decision is not an unanswered question.

FINDING: ${JSON.stringify(f).slice(0, 6000)}`,
    { label: `verify:${(f.title || String(i)).slice(0, 40)}`, phase: 'Verify', schema: VERDICT_SCHEMA })
    .then(v => (v && v.stands ? { ...f, severity: v.corrected_severity || f.severity, verdict: v.why } : null)),
))).filter(Boolean)

log(`${verified.length} of ${toVerify.length} verified findings stood${dropped.length ? `; ${dropped.length} unverified` : ''}`)

// Unverified findings travel WITH the report, flagged — the reader must be able to see
// which claims were adversarially checked and which were only asserted.
const unverified = dropped.map(f => ({ ...f, verdict: 'NOT VERIFIED — verify cap reached' }))

// ── Phase 4: Report ────────────────────────────────────────────────────────
phase('Report')
const rep = await agent(
  `Write the shared-memory tidy-up report to ${REPORT} (mkdir -p ${REPORT_DIR} first). Date: ${DATE}.

DATA (verified findings, JSON): ${JSON.stringify(verified).slice(0, 50000)}
UNVERIFIED findings (verify cap reached — list them in a clearly marked section of their
own, never mixed in with the verified ones): ${JSON.stringify(unverified).slice(0, 12000)}
Lens summaries: ${JSON.stringify(analyses.map(a => a.summary)).slice(0, 4000)}

Structure:
1. one paragraph: what was audited, how many files, how many raw findings, how many were
   verified and how many stood — the drop is information, not noise, so state every
   number, including how many went unverified because the cap was reached;
2. findings grouped by OWNER, because that is what decides who acts: "we can do this"
   (owner us), "needs the other party" (owner other-party or both), "operator decision"
   (owner operator). Inside each group by severity. Each finding: title, the claim, the
   sources with quotes, both_right_if where present, the proposal;
3. a closing section "Not proposed" naming what the pass deliberately did NOT suggest —
   any deletion, and any rewrite of another party's entry — with one sentence on why.

The report is a PROPOSAL DOCUMENT. Nothing in it is executed by this run. Write it in the
instance's language as found in ${INSTANCE}/CLAUDE.md.
Return: report_path, finding_count, by_owner counts.`,
  { label: 'report', phase: 'Report', schema: {
    type: 'object', required: ['report_path', 'finding_count'],
    properties: {
      report_path: { type: 'string' }, finding_count: { type: 'number' },
      us: { type: 'number' }, other_party: { type: 'number' }, operator: { type: 'number' },
    },
  } },
)
if (!rep) throw new Error('report agent failed')

return {
  report: rep.report_path,
  raw: raw.length,
  verified: verified.length,
  by_owner: { us: rep.us || 0, other_party: rep.other_party || 0, operator: rep.operator || 0 },
}
