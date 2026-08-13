export const meta = {
  name: 'memory-dream',
  description: 'Memory hygiene audit (read-only): duplicates, contradictions, stale info, index hygiene — report with proposals, no fixes',
  whenToUse: 'Analysis part of the memory-dream skill as a building block for full-audit. Call with args {date:"YYYY-MM-DD"}. Fixes run separately after operator OK or via the skill.',
  phases: [
    { title: 'Analysis', detail: 'Content (duplicates/contradictions/stale) + mechanics (index/links/limits) in parallel' },
    { title: 'Report', detail: 'Write report with proposals' },
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
if (!A || !A.date) throw new Error('memory-dream requires args {date:"YYYY-MM-DD"} — fetch via `date +%F`')
const DATE = A.date
const REPORT = `${REPORT_DIR}/report-${DATE}.md`

const COMMON = `You are a memory audit agent. STRICTLY READ-ONLY — you change NOTHING, you propose.
Audit object: ${MEMDIR}/ (MEMORY.md = index, remaining *.md = 1 fact each).
EXCEPTION RULE (operator directive 2026-07-31): session-log/decision-log in the repo are append-only PROTOCOLS
— memories MAY point at them, but never report "clean up the log". Every finding needs
file + evidence (quote or measurement). Return value = raw data via StructuredOutput.`

const FINDINGS_SCHEMA = {
  type: 'object',
  required: ['summary', 'findings'],
  properties: {
    summary: { type: 'string' },
    findings: {
      type: 'array', maxItems: 20,
      items: {
        type: 'object', required: ['severity', 'title', 'proposal'],
        properties: {
          severity: { type: 'string', enum: ['P0', 'P1', 'P2', 'INFO'] },
          title: { type: 'string', description: '1 line with file(s) + evidence' },
          proposal: { type: 'string', description: 'proposal (merge/update/delete/move) — will NOT be executed' },
        },
      },
    },
  },
}

// ── Phase 1: Analysis (2 independent perspectives) ────────────────────────
phase('Analysis')
// Model routing (rules/intelligence.md): mechanics is counting/reconciling — small
// model; content judges (contradictions, stale cross-check) — session model.
const LENSES = [
  { slug: 'content', prompt: `CONTENT: Read ALL memory files completely. Find (a) duplicates/overlaps (two files, one topic — name the merge candidate incl. direction), (b) contradictions between files (which one is current per date/repo cross-check?), (c) stale info: relative date references, content marked RESOLVED/SUPERSEDED, facts outdated according to the repo state (spot-check against ${REPO}), (d) overly vague memories with no action-guiding substance.` },
  { slug: 'mechanics', model: 'haiku', prompt: `MECHANICS: (a) measure MEMORY.md limits (wc: lines/bytes vs. 200/25600), (b) index completeness both ways: every file in the index? every index line has a file? (c) spot-check index description vs. file content for contradiction, (d) [[wiki-links]] in files: do they point at existing name slugs? (e) frontmatter consistency (name/description/type present), (f) files referencing repo paths/skills/tools that no longer exist (ls/test against ${REPO}).` },
]
const results = await parallel(LENSES.map(l => () =>
  agent(`${COMMON}\n\n${l.prompt}`, { label: `analysis:${l.slug}`, phase: 'Analysis', schema: FINDINGS_SCHEMA, ...(l.model ? { model: l.model } : {}) })
))
const analyses = results.filter(Boolean)
if (!analyses.length) throw new Error('both analysis agents failed')
const findings = analyses.flatMap(r => r.findings)
log(`${findings.length} findings from ${analyses.length}/2 analyses`)

// ── Phase 2: Report ────────────────────────────────────────────────────────
phase('Report')
const rep = await agent(
  `Write the memory-dream report to ${REPORT} (mkdir -p ${REPORT_DIR}). Date: ${DATE}.
Data basis (JSON): ${JSON.stringify({ summaries: analyses.map(a => a.summary), findings }).slice(0, 50000)}
Structure: header (file/line counts, limits), findings by severity with proposal, section
"Merge/delete candidates" as a table, closing section "Implementation ONLY after operator OK —
respect the snapshot rule: memory changes via auto-memory + memory-sync export, never
docs/memory-snapshot/ directly". NO change to memory files.
Return: report_path, p0_count, p1_count, finding_count.`,
  { label: 'report', phase: 'Report', schema: {
    type: 'object', required: ['report_path', 'finding_count'],
    properties: { report_path: { type: 'string' }, p0_count: { type: 'number' }, p1_count: { type: 'number' }, finding_count: { type: 'number' } },
  } },
)
if (!rep) throw new Error('Report agent failed')

return { report: rep.report_path, befunde: rep.finding_count, p0: rep.p0_count || 0, p1: rep.p1_count || 0 }
