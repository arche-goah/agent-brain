export const meta = {
  name: 'full-audit-synthesis',
  description: 'Synthesis stage of the full audit: dedupes the findings from brain-scan + memory-dream + coherence-scan into ONE measure catalog (mechanical fixes vs. decision agenda)',
  whenToUse: 'ONLY as stage 4 of the full-audit skill, after the individual reports exist. args {date, scratch:"<abs. scratch dir>", reports:{brain, memory, coherence}} = paths.',
  phases: [
    { title: 'Catalog', detail: 'Read reports, dedupe across scans, classify; the catalog is written to a file' },
    { title: 'Report', detail: 'Write overall report + proposals to the order list, read from the file' },
  ],
}

// ── Configuration ──────────────────────────────────────────────────────────
// Core rule: never hardcode instance paths — repo via args, default = cwd of the agents.
const REPO = (typeof args === 'object' && args && args.repo) || '.'
const REPORT_DIR = `${REPO}/docs/research/full-audit`
const AUFTRAEGE = `${REPO}/docs/maintenance/brain-scan-auftraege.md`

let A = args
if (typeof A === 'string') { try { A = JSON.parse(A) } catch (e) { A = null } }
if (!A || !A.date || !A.scratch || !A.reports || !A.reports.brain || !A.reports.memory || !A.reports.coherence) {
  throw new Error('full-audit-synthesis requires args {date, scratch:"<abs. path>", reports:{brain,memory,coherence}} — scratch = session scratchpad subfolder, reports = paths of the three individual reports')
}
const DATE = A.date
const OUT = `${REPORT_DIR}/gesamt-${DATE}.md`
// The catalog's bulk lives here; the report stage reads it from disk.
const CATALOG = `${A.scratch}/catalog.json`

// Shape of ONE measure as it is written to the catalog file. Prompt text now, not a
// StructuredOutput schema: sources and proposals never come back through a return value
// (see the producer-writes block below).
const MASSNAHME_ITEM = {
  type: 'object', required: ['prio', 'typ', 'titel', 'quellen', 'vorschlag'],
  properties: {
    prio: { type: 'string', enum: ['P0', 'P1', 'P2', 'INFO'] },
    typ: { type: 'string', enum: ['mechanisch', 'entscheidung'] },
    titel: { type: 'string', description: '1 line, concrete — unique within the file' },
    quellen: { type: 'array', minItems: 1, maxItems: 4, items: { type: 'string', description: 'report path + section' } },
    vorschlag: { type: 'string', description: 'fix or decision question with options' },
  },
}

// ── Multi-agent invariant: only the producer writes (rules/intelligence.md) ─
// A number the model REPORTS is a claim; the same number computed here is a measurement.
// The measurement wins, and a mismatch aborts rather than being footnoted.
const assertCount = (machine, claimed, what) => {
  if (claimed !== undefined && claimed !== machine) {
    throw new Error(`${what}: agent reported ${claimed}, script counted ${machine} — the script-side count wins (rules/intelligence.md, "only the producer writes"). Aborting instead of returning numbers that do not match the data.`)
  }
}

// ── Producer-writes helpers (begin) — extracted VERBATIM by scripts/test-full-audit-synthesis-files.sh
// Bulk data never crosses an agent boundary inside a prompt: the agent that PRODUCES
// the catalog writes it to a file, and the consumer reads that file itself. Across the
// boundary travel only a path, a count and a narrow index (prio + typ + title) — typ is
// routing-critical, it decides which half of the report a measure lands in, so it stays
// schema-validated instead of living only in the file.
// Measured 2026-09-13 on a coherence-scan run: 241,137 chars relayed through one prompt,
// 60,000 arrived, and the counts stayed green because they matched while the content did
// not. This workflow relayed the full catalog — 40 measures with sources and proposals —
// through one 50,000-char relay: the same cut, one workflow over.
const fileName = (p) => String(p).replace(/\\/g, '/').split('/').pop()
// `expected` is what the script STARTED; `found` is what a consumer reports it read from
// disk (its ls, not its memory). Compared by file name: script and agent may spell the
// same directory differently (separators, drive forms) while the names inside one
// directory are unique. Any gap aborts — a report written without the catalog file reads
// exactly like one written from it.
const assertFiles = (expected, found, what) => {
  const have = new Set((found || []).map(fileName))
  const missing = expected.filter(f => !have.has(fileName(f)))
  if (missing.length) {
    throw new Error(`${what}: ${missing.length} of ${expected.length} file(s) missing — ${missing.map(fileName).join(', ')}. Aborting instead of continuing on a partial corpus (rules/intelligence.md, "only the producer writes").`)
  }
}
// ── Producer-writes helpers (end)

// ── Phase 1: Catalog (1 agent — needs ALL reports at once, no fan-out) ─────
phase('Catalog')
const katalog = await agent(
  `You are the synthesis stage of a full audit. Read these three reports COMPLETELY:
1. Conformance (brain-scan): ${A.reports.brain}
2. Memory hygiene (memory-dream): ${A.reports.memory}
3. Norm coherence (coherence-scan): ${A.reports.coherence}
Plus the open part of ${AUFTRAEGE} (do NOT re-include items already done/[x]).

Build the cross-scan measure catalog:
- DEDUPE: the same issue often appears in 2-3 reports (e.g. index drift in
  memory-dream AND as a coherence finding) → ONE measure, reference all sources
  as report+section.
- CLASSIFY, typ per measure:
  * "mechanisch" (mechanical) = docs==reality drift, dead paths/references, stale
    statuses, index sync — cleanly verifiable, NO rule has to win.
  * "entscheidung" (decision) = a rule/structure has to win or the operator has to
    weigh in (rule-conflict protocol stage 3 in rules/thinking-protocol.md: explain,
    discuss, decide case by case).
- PRIORITIZE by real damage potential (P0-P2/INFO), strongest first.
- Do NOT duplicate points already marked [x] done in the order file or already open
  there — count them under skipped_existing instead.

OUTPUT — you are the producer, you write: save the catalog as JSON to ${CATALOG} (mkdir -p ${A.scratch}) with exactly this shape: {"summary": "<3-5 sentences incl. dedupe balance>", "skipped_existing": <number>, "massnahmen": [<objects>]} where every object satisfies this JSON schema: ${JSON.stringify(MASSNAHME_ITEM)}. Sources and proposals are this stage's data and travel ONLY through that file — none of them come back through your return value.
After writing, MEASURE the file (node -e or jq, not from memory).
Return via StructuredOutput: file (the path you wrote), summary, skipped_existing, and massnahmen = the INDEX only — prio + typ + titel verbatim as written in the file.`,
  { label: 'catalog', phase: 'Catalog', schema: {
    type: 'object', required: ['file', 'summary', 'massnahmen'],
    properties: {
      file: { type: 'string', description: 'path of the JSON file you wrote' },
      summary: { type: 'string', description: 'Overall picture in 3-5 sentences incl. dedupe balance' },
      skipped_existing: { type: 'number' },
      massnahmen: {
        type: 'array', maxItems: 40,
        items: {
          type: 'object', required: ['prio', 'typ', 'titel'],
          properties: {
            prio: { type: 'string', enum: ['P0', 'P1', 'P2', 'INFO'] },
            typ: { type: 'string', enum: ['mechanisch', 'entscheidung'] },
            titel: { type: 'string', description: 'verbatim the "titel" field in the file' },
          },
        },
      },
    },
  } },
)
if (!katalog) throw new Error('Catalog agent failed')
// First gate, claim level, before any report tokens are spent: the catalog file exists
// by the name the script named. A null (agent died) never reaches here.
assertFiles([CATALOG], [katalog.file], 'catalog: file written')
log(`${katalog.massnahmen.length} measures (deduped) in ${CATALOG}, ${katalog.skipped_existing || 0} already on the order list`)

// ── Phase 2: Report + order-list appendix ─────────────────────────────────
phase('Report')
const mech = katalog.massnahmen.filter(m => m.typ === 'mechanisch')
const dec = katalog.massnahmen.filter(m => m.typ === 'entscheidung')
const rep = await agent(
  `Write the full-audit overall report to ${OUT} (mkdir -p ${REPORT_DIR}). Date: ${DATE}.
DATA BASIS ON DISK — the catalog lies in ${CATALOG}; read it COMPLETELY before writing, never from memory of the previous stage. If the file is missing, STOP: return files_read = [], report_path = "" (the script aborts on that; never write the report from a remembered catalog).
AUTHORITATIVE numbers (machine-derived from the validated index): ${mech.length} mechanical, ${dec.length} decision measures. Header and prose state exactly these; if the file's own summary deviates, the index wins.
Catalog summary: ${katalog.summary}
Source reports (link in the header, incl. a note if a report is reused/older — the date is in the filename): brain=${A.reports.brain}, memory=${A.reports.memory}, coherence=${A.reports.coherence}
Structure: (1) header: scan scope, source reports, dedupe balance; (2) "Mechanical fixes"
by priority (each: title, sources, proposal); (3) "Decision agenda for the operator" by
priority (each: question, options, recommendation if available); (4) "Next steps":
EVERY implementation needs the operator (promotion to the list's own operator marker — origin: operator, or the legacy von: Operator / documented-name form — or an explicit blanket OK).
THEN append the P0/P1 measures to ${AUFTRAEGE} under the existing proposed-items structure
as 1-line items, origin "abgeleitet (full-audit ${DATE})" (abgeleitet = derived), with a
pointer to ${OUT} — implement NOTHING, change no existing entries.
Return via StructuredOutput: files_read (every data file you actually read, from your ls), report_path, mech_count, decision_count, appended.`,
  { label: 'report', phase: 'Report', schema: {
    type: 'object', required: ['files_read', 'report_path'],
    properties: {
      files_read: { type: 'array', items: { type: 'string' }, maxItems: 20 },
      report_path: { type: 'string' }, mech_count: { type: 'number' }, decision_count: { type: 'number' }, appended: { type: 'number' },
    },
  } },
)
if (!rep) throw new Error('Report agent failed')
// Second gate, measured: what the consumer found on disk, against what was written.
assertFiles([CATALOG], rep.files_read, 'report: catalog read from disk')
assertCount(mech.length, rep.mech_count, 'full-audit mechanical measures')
assertCount(dec.length, rep.decision_count, 'full-audit decision agenda')

return {
  gesamt_report: rep.report_path,
  massnahmen: katalog.massnahmen.length,
  mechanisch: mech.length,
  entscheidungen: dec.length,
  vorschlaege_angehaengt: rep.appended || 0,
}
