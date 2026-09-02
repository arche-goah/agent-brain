export const meta = {
  name: 'full-audit-synthesis',
  description: 'Synthesis stage of the full audit: dedupes the findings from brain-scan + memory-dream + coherence-scan into ONE measure catalog (mechanical fixes vs. decision agenda)',
  whenToUse: 'ONLY as stage 4 of the full-audit skill, after the individual reports exist. args {date, reports:{brain, memory, coherence}} = paths.',
  phases: [
    { title: 'Catalog', detail: 'Read reports, dedupe across scans, classify' },
    { title: 'Report', detail: 'Write overall report + proposals to the order list' },
  ],
}

// ── Configuration ──────────────────────────────────────────────────────────
// Core rule: never hardcode instance paths — repo via args, default = cwd of the agents.
const REPO = (typeof args === 'object' && args && args.repo) || '.'
const REPORT_DIR = `${REPO}/docs/research/full-audit`
const AUFTRAEGE = `${REPO}/docs/maintenance/brain-scan-auftraege.md`

let A = args
if (typeof A === 'string') { try { A = JSON.parse(A) } catch (e) { A = null } }
if (!A || !A.date || !A.reports || !A.reports.brain || !A.reports.memory || !A.reports.coherence) {
  throw new Error('full-audit-synthesis requires args {date, reports:{brain,memory,coherence}} — paths of the three individual reports')
}
const DATE = A.date
const OUT = `${REPORT_DIR}/gesamt-${DATE}.md`

// ── Multi-agent invariant: only the producer writes (rules/intelligence.md) ─
// A relay through a prompt truncates silently — measured 2026-08-30: 1 of 141 rows
// survived one hop. These two helpers do not make the boundary lossless; they make a
// loss impossible to mistake for complete data, which is the half a script can enforce.
const relay = (obj, limit, what) => {
  const s = JSON.stringify(obj)
  if (s.length <= limit) return s
  log(`RELAY TRUNCATED: ${what} — ${limit} of ${s.length} chars reach the agent`)
  return `${s.slice(0, limit)}
[TRUNCATED: ${limit} of ${s.length} chars — this payload is INCOMPLETE, say so in the report]`
}
// A number the model REPORTS is a claim; the same number computed here is a measurement.
// The measurement wins, and a mismatch aborts rather than being footnoted.
const assertCount = (machine, claimed, what) => {
  if (claimed !== undefined && claimed !== machine) {
    throw new Error(`${what}: agent reported ${claimed}, script counted ${machine} — the script-side count wins (rules/intelligence.md, "only the producer writes"). Aborting instead of returning numbers that do not match the data.`)
  }
}

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
Return via StructuredOutput; return value = raw data, not a report.`,
  { label: 'catalog', phase: 'Catalog', schema: {
    type: 'object', required: ['summary', 'massnahmen'],
    properties: {
      summary: { type: 'string', description: 'Overall picture in 3-5 sentences incl. dedupe balance' },
      skipped_existing: { type: 'number' },
      massnahmen: {
        type: 'array', maxItems: 40,
        items: {
          type: 'object', required: ['prio', 'typ', 'titel', 'quellen', 'vorschlag'],
          properties: {
            prio: { type: 'string', enum: ['P0', 'P1', 'P2', 'INFO'] },
            typ: { type: 'string', enum: ['mechanisch', 'entscheidung'] },
            titel: { type: 'string', description: '1 line, concrete' },
            quellen: { type: 'array', minItems: 1, maxItems: 4, items: { type: 'string', description: 'report path + section' } },
            vorschlag: { type: 'string', description: 'fix or decision question with options' },
          },
        },
      },
    },
  } },
)
if (!katalog) throw new Error('Catalog agent failed')
log(`${katalog.massnahmen.length} measures (deduped), ${katalog.skipped_existing || 0} already on the order list`)

// ── Phase 2: Report + order-list appendix ─────────────────────────────────
phase('Report')
const mech = katalog.massnahmen.filter(m => m.typ === 'mechanisch')
const dec = katalog.massnahmen.filter(m => m.typ === 'entscheidung')
const rep = await agent(
  `Write the full-audit overall report to ${OUT} (mkdir -p ${REPORT_DIR}). Date: ${DATE}.
Data basis (JSON): ${relay({ summary: katalog.summary, mechanisch: mech, entscheidung: dec }, 50000, 'catalog')}
Source reports (link in the header, incl. a note if a report is reused/older — the date is in the filename): brain=${A.reports.brain}, memory=${A.reports.memory}, coherence=${A.reports.coherence}
Structure: (1) header: scan scope, source reports, dedupe balance; (2) "Mechanical fixes"
by priority (each: title, sources, proposal); (3) "Decision agenda for the operator" by
priority (each: question, options, recommendation if available); (4) "Next steps":
EVERY implementation needs the operator (promotion to the list's own operator marker — origin: operator, or the legacy von: Operator / documented-name form — or an explicit blanket OK).
THEN append the P0/P1 measures to ${AUFTRAEGE} under the existing proposed-items structure
as 1-line items, origin "abgeleitet (full-audit ${DATE})" (abgeleitet = derived), with a
pointer to ${OUT} — implement NOTHING, change no existing entries.
Return: report_path, mech_count, decision_count, appended.`,
  { label: 'report', phase: 'Report', schema: {
    type: 'object', required: ['report_path'],
    properties: { report_path: { type: 'string' }, mech_count: { type: 'number' }, decision_count: { type: 'number' }, appended: { type: 'number' } },
  } },
)
if (!rep) throw new Error('Report agent failed')
assertCount(mech.length, rep.mech_count, 'full-audit mechanical measures')
assertCount(dec.length, rep.decision_count, 'full-audit decision agenda')

return {
  gesamt_report: rep.report_path,
  massnahmen: katalog.massnahmen.length,
  mechanisch: mech.length,
  entscheidungen: dec.length,
  vorschlaege_angehaengt: rep.appended || 0,
}
