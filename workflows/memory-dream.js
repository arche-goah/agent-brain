export const meta = {
  name: 'memory-dream',
  description: 'Memory hygiene audit (read-only): duplicates, contradictions, stale info, index hygiene — report with proposals, no fixes',
  whenToUse: 'Analysis part of the memory-dream skill as a building block for full-audit. Call with args {date:"YYYY-MM-DD", scratch:"<abs. scratch dir>"}. Fixes run separately after operator OK or via the skill.',
  phases: [
    { title: 'Analysis', detail: 'Content (duplicates/contradictions/stale) + mechanics (index/links/limits) in parallel; each writes its findings to a file' },
    { title: 'Report', detail: 'Write report with proposals, read from the files' },
  ],
}

// ── Configuration ──────────────────────────────────────────────────────────
// Core rule: never hardcode instance paths. repo/memdir come via args; default:
// repo = cwd of the agents ('.'), memdir = discovery instruction to the agent.
const REPO = (typeof args === 'object' && args && args.repo) || '.'
const MEMDIR = (typeof args === 'object' && args && args.memdir) ||
  '$HOME/.claude/projects/<absolute project path, every "/" replaced by "-">/memory (agent: resolve this yourself, use pwd)'
const REPORT_DIR = `${REPO}/docs/research/memory-dream`

let A = args
if (typeof A === 'string') { try { A = JSON.parse(A) } catch (e) { A = null } }
if (!A || !A.date || !A.scratch) throw new Error('memory-dream requires args {date:"YYYY-MM-DD", scratch:"<abs. path>"} — date via `date +%F`, scratch = session scratchpad subfolder')
const DATE = A.date
const REPORT = `${REPORT_DIR}/report-${DATE}.md`
// Every stage's bulk output lives here; the next stage reads it from disk.
const FINDINGS_DIR = `${A.scratch}/findings`

const COMMON = `You are a memory audit agent. STRICTLY READ-ONLY — you change NOTHING, you propose.
Audit object: ${MEMDIR}/ (MEMORY.md = index, remaining *.md = 1 fact each).
SUB-INDEXES: a file named index-<topic>.md that MEMORY.md links to is ITSELF an index — the entries
it lists are indexed, not orphaned. Read every linked sub-index before calling anything an orphan or
unindexed (one level only). Same rule as scripts/memory-lint.py.
EXCEPTION RULE (operator directive 2026-07-31): session-log/decision-log in the repo are append-only PROTOCOLS
— memories MAY point at them, but never report "clean up the log". Every finding needs
file + evidence (quote or measurement). Return value = raw data via StructuredOutput.`

// Shape of ONE finding as it is written to the analysis files. Prompt text now, not a
// StructuredOutput schema: the findings never come back through a return value (see the
// producer-writes block below).
const FINDING_ITEM = {
  type: 'object', required: ['severity', 'title', 'proposal'],
  properties: {
    severity: { type: 'string', enum: ['P0', 'P1', 'P2', 'INFO'] },
    title: { type: 'string', description: '1 line with file(s) + evidence' },
    proposal: { type: 'string', description: 'proposal (merge/update/delete/move) — will NOT be executed' },
  },
}
// What an analysis agent returns: a path, measured counts and a summary. The counts are
// routing-critical (they decide the report's numbers), so they stay schema-validated
// instead of living only in the file.
const ANALYSIS_SCHEMA = {
  type: 'object',
  required: ['file', 'finding_count', 'summary'],
  properties: {
    file: { type: 'string', description: 'path of the JSON file you wrote' },
    finding_count: { type: 'number', description: 'length of the findings array IN THE FILE, measured after writing' },
    p0_count: { type: 'number', description: 'number of P0 findings in the file, measured' },
    p1_count: { type: 'number', description: 'number of P1 findings in the file, measured' },
    summary: { type: 'string' },
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

// ── Producer-writes helpers (begin) — extracted VERBATIM by scripts/test-memory-dream-files.sh
// Bulk data never crosses an agent boundary inside a prompt: the agent that PRODUCES
// findings writes them to a file under FINDINGS_DIR, and the consumer reads the files
// itself. Across the boundary travel only a path, a count and a summary.
// Measured 2026-08-30: 1 of 141 rows survived one hop through a prompt; measured
// 2026-09-13 on a coherence-scan run: 241,137 chars relayed, 60,000 arrived, 6 of 9
// producers never reached the consumer — with the counts green, because they matched
// and the content did not. This workflow relayed both analysis summaries AND all
// findings through one 50,000-char relay: the same cut, one workflow over.
const fileName = (p) => String(p).replace(/\\/g, '/').split('/').pop()
// `expected` is what the script STARTED; `found` is what a consumer reports it read
// from disk (its ls, not its memory). Compared by file name: script and agent may
// spell the same directory differently (separators, drive forms) while the names
// inside one directory are unique. Any gap aborts — an analysis whose file is missing
// did not run, and reporting on the rest reads exactly like reporting on everything.
const assertFiles = (expected, found, what) => {
  const have = new Set((found || []).map(fileName))
  const missing = expected.filter(f => !have.has(fileName(f)))
  if (missing.length) {
    throw new Error(`${what}: ${missing.length} of ${expected.length} file(s) missing — ${missing.map(fileName).join(', ')}. Aborting instead of continuing on a partial corpus (rules/intelligence.md, "only the producer writes").`)
  }
}
// ── Producer-writes helpers (end)

// ── Phase 1: Analysis (2 independent perspectives) ────────────────────────
phase('Analysis')
// Model routing (rules/intelligence.md): mechanics is counting/reconciling — small
// model; content judges (contradictions, stale cross-check) — session model.
const LENSES = [
  { slug: 'content', prompt: `CONTENT: Read ALL memory files completely. Find (a) duplicates/overlaps (two files, one topic — name the merge candidate incl. direction), (b) contradictions between files (which one is current per date/repo cross-check?), (c) stale info: relative date references, content marked RESOLVED/SUPERSEDED, facts outdated according to the repo state (spot-check against ${REPO}), (d) overly vague memories with no action-guiding substance.` },
  { slug: 'mechanics', model: 'haiku', prompt: `MECHANICS: (a) measure MEMORY.md limits (wc: lines/bytes vs. 200/25600), (b) index completeness both ways: every file in the index? every index line has a file? (c) spot-check index description vs. file content for contradiction, (d) [[wiki-links]] in files: do they point at existing name slugs? (e) frontmatter consistency (name/description/type present), (f) files referencing repo paths/skills/tools that no longer exist (ls/test against ${REPO}).` },
]
const lensFile = (slug) => `${FINDINGS_DIR}/analysis-${slug}.json`
const lensFiles = LENSES.map(l => lensFile(l.slug))
const results = await parallel(LENSES.map(l => () =>
  agent(`${COMMON}\n\n${l.prompt}\n\nOUTPUT — you are the producer, you write: save your findings as JSON to ${lensFile(l.slug)} (mkdir -p ${FINDINGS_DIR}) with exactly this shape: {"lens": "${l.slug}", "summary": "<3 sentences>", "findings": [<objects>]} where every object satisfies this JSON schema: ${JSON.stringify(FINDING_ITEM)}. The findings array is this audit's data and travels ONLY through that file — nothing of it comes back through your return value. After writing, MEASURE the file: count the findings array and the P0/P1 entries in the file (node -e or jq, not from memory). Return via StructuredOutput: file (the path you wrote), finding_count, p0_count, p1_count (all measured), summary.`,
    { label: `analysis:${l.slug}`, phase: 'Analysis', schema: ANALYSIS_SCHEMA, ...(l.model ? { model: l.model } : {}) })
))
const analyses = results.filter(Boolean)
if (!analyses.length) throw new Error('both analysis agents failed')
// First gate, claim level, before any report tokens are spent: every started analysis
// returned and named its file. A null (agent died/skipped) is a missing file.
assertFiles(lensFiles, results.map(r => r && r.file), 'analysis: files reported')
const rawCount = analyses.reduce((n, r) => n + r.finding_count, 0)
log(`${analyses.length}/${LENSES.length} analyses wrote their file, ${rawCount} findings on disk`)

// ── Phase 2: Report ────────────────────────────────────────────────────────
phase('Report')
const rep = await agent(
  `Write the memory-dream report to ${REPORT} (mkdir -p ${REPORT_DIR}). Date: ${DATE}.
DATA BASIS ON DISK — the analyses wrote their findings as JSON files in ${FINDINGS_DIR}/: ${lensFiles.map(fileName).join(', ')}.
STEP 1: ls ${FINDINGS_DIR} — if any of these files is missing, STOP: return files_read = what exists, finding_count = 0, report_path = "" (the script aborts on that; never report on a partial set).
STEP 2: read ALL of them completely, never from memory of an earlier stage. finding_count = the summed length of their findings arrays, MEASURED (node -e or jq), never estimated.
STEP 3: write the report from what you read.
Structure: header (file/line counts, limits), findings by severity with proposal, section
"Merge/delete candidates" as a table, closing section "Implementation ONLY after operator OK —
respect the snapshot rule: memory changes via auto-memory + memory-sync export, never
docs/memory-snapshot/ directly". NO change to memory files.
Return via StructuredOutput: files_read (every data file you actually read, from your ls), report_path, p0_count, p1_count, finding_count.`,
  { label: 'report', phase: 'Report', schema: {
    type: 'object', required: ['files_read', 'report_path', 'finding_count'],
    properties: {
      files_read: { type: 'array', items: { type: 'string' }, maxItems: 20 },
      report_path: { type: 'string' }, p0_count: { type: 'number' }, p1_count: { type: 'number' }, finding_count: { type: 'number' },
    },
  } },
)
if (!rep) throw new Error('Report agent failed')
// Second gate, measured: what the consumer found on disk, against what was started.
assertFiles(lensFiles, rep.files_read, 'report: analysis files read from disk')
// The counts the script holds are the measurement; the agent's are a claim.
const p0Machine = analyses.reduce((n, r) => n + (r.p0_count || 0), 0)
const p1Machine = analyses.reduce((n, r) => n + (r.p1_count || 0), 0)
assertCount(rawCount, rep.finding_count, 'memory-dream findings read by the report')

return { report: rep.report_path, befunde: rawCount, p0: p0Machine, p1: p1Machine }
