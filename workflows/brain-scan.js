export const meta = {
  name: 'brain-scan',
  description: 'Brain scan & agentic self-improvement: checklist audit + SOTA delta + ordered fixes + report',
  whenToUse: 'Recurring self-audit of the brain setup. Call with args {date:"YYYY-MM-DD"}.',
  phases: [
    { title: 'Context', detail: 'Order list + checklist + latest report', model: 'haiku' },
    { title: 'Scan', detail: '5 repo checks + 2 SOTA delta checks in parallel', model: 'haiku' },
    { title: 'Fixes', detail: 'ONLY items with von: Operator, sequential with verify' },
    { title: 'Report', detail: 'Write scan report, update the order list' },
  ],
}

// ── Configuration ──────────────────────────────────────────────────────────
// Core rule: never hardcode instance paths — repo via args, default = cwd of the agents.
const REPO = (typeof args === 'object' && args && args.repo) || '.'
// Both are INSTANCE artifacts and may be missing. If the checklist is missing, the scan
// runs against the rule files and reports the absence as a finding; if the order list is
// missing, derived items go into the report. In no case are they improvised into
// existence — their structure is the operator's decision (mechanism discipline).
const CHECKLIST = `${REPO}/docs/maintenance/brain-scan-checklist.md`
const AUFTRAEGE = `${REPO}/docs/maintenance/brain-scan-auftraege.md`
const REPORT_DIR = `${REPO}/docs/research/brain-scan`

let A = args
if (typeof A === 'string') { try { A = JSON.parse(A) } catch (e) { A = null } }
if (!A || !A.date) throw new Error('brain-scan requires args {date:"YYYY-MM-DD"} — fetch the date via Bash `date +%F` and pass it in')
const DATE = A.date
const REPORT = `${REPORT_DIR}/scan-${DATE}.md`

const FINDINGS_SCHEMA = {
  type: 'object',
  required: ['summary', 'findings'],
  properties: {
    summary: { type: 'string' },
    findings: {
      type: 'array', maxItems: 20,
      items: {
        type: 'object', required: ['severity', 'title'],
        properties: {
          severity: { type: 'string', enum: ['P0', 'P1', 'P2', 'INFO', 'OK'] },
          title: { type: 'string', description: '1 sentence, concrete, with file path/evidence' },
          state: {
            type: 'string', enum: ['configured', 'verified'],
            description: 'Required when severity is OK (checklist section 0): configured = precondition read/parsed · verified = the declared behavior check was actually run. Schema/existence checks are NEVER verified.',
          },
        },
      },
    },
  },
}

// ── Phase 1: Context ───────────────────────────────────────────────────────
phase('Context')
const ctx = await agent(
  `Read (1) ${AUFTRAEGE}, (2) ${CHECKLIST}, (3) the newest existing report in ${REPORT_DIR}/ (ls, then read the newest scan-*.md; if none exists: last_scan_date = null, prev_open = []).
Return via StructuredOutput: orders = ONLY the items from the section "Offen (bestellt)" (open, ordered) with origin "von: Operator" that are (a) unfinished (checkbox [ ] — skip [x]) AND (b) carry NO "eigene Session"/"EIGENE-SESSION" (own-session) note (the scan never touches such projects, only reports them as open). Full wording; last_scan_date; prev_open = unresolved finding titles from the last report. The return value is raw data.`,
  { label: 'context', phase: 'Context', model: 'haiku', schema: {
    type: 'object', required: ['orders', 'prev_open'],
    properties: {
      orders: { type: 'array', items: { type: 'string' }, maxItems: 20 },
      last_scan_date: { type: ['string', 'null'] },
      prev_open: { type: 'array', items: { type: 'string' }, maxItems: 40 },
    },
  } },
)
if (!ctx) throw new Error('Context agent failed')
log(`${ctx.orders.length} ordered tasks, last scan: ${ctx.last_scan_date || 'never'}`)

// ── Phase 2: Scan (repo + SOTA in parallel) ───────────────────────────────
const SCAN_COMMON = `You are a brain-scan agent for ${REPO}. STRICTLY READ-ONLY. Check EVERY check of your checklist section from ${CHECKLIST} individually and concretely (measure/read/test, do not guess). Already-known unresolved findings from the last scan: ${JSON.stringify(ctx.prev_open).slice(0, 3000)} — prefix such findings with "RECURRING:". Severity OK = check passed (report only in summarized form) — then "state" is REQUIRED: "verified" ONLY if you yourself executed the behavior check declared in section 0/your section and can name the result; reading/parsing/schema-checking is "configured". When in doubt: "configured".
FRESHNESS REQUIREMENT: every statement about rule/doc files (CLAUDE.md, rules/, checklist, settings) must rest on a read from disk IN THIS RUN — never quote injected context/system-prompt copies (2026-08-01: two stale findings, refuted by grep).
ADDITIONAL CRITERION in YOUR area (every section, no auto-fix): if you notice a construct that only resolves on macOS/BSD (BSD-only flags like \`stat -f\`/\`date -r\`, \`zsh\`-specific syntax, \`launchd\`, fixed paths like /opt/homebrew, assumption of \`/\` path separators, tools like \`system_profiler\`/\`ioreg\` without fallback) — report it as a separate finding prefixed "OS:" (severity INFO, never higher for this alone), file+line, 1 sentence why it could break on Windows/Linux, plus — where evident — a brief suggestion for the Windows/POSIX equivalent. No fix, no judgment: making it robust needs its own review session with the Windows machine + PR reconciliation, not this scan.
StructuredOutput per schema; return value = raw data.`

const SCANS = [
  { slug: 'effect', prompt: `Section 0 (Effect). Run via Bash \`bash ${REPO}/core/scripts/effect-check.sh ${REPO}\`. Report EVERY RED line as its own finding (P1, title = wording of the line) and EVERY INFO line pointing to something shipped-but-not-wired as INFO. Summarize the OK lines into ONE finding of severity OK with state "verified" — this script IS the behavior check, it compares declaration against the consuming side. Invent nothing: only what the script outputs. If the script fails (missing/exit>1), THAT is the finding.` },
  { slug: 'permissions-hooks', prompt: `Sections 1 (Permissions & security) + 3 (Hooks & settings). Files: ${REPO}/.claude/settings.json, ${REPO}/.claude/settings.local.json and EVERY script wired inside them — since the core split the hook helpers live under ${REPO}/core/helpers/, not under .claude/helpers/. Check the paths that actually appear in the settings instead of expecting a location.` },
  { slug: 'skills', prompt: `Section 2 (Skills). Two sources, both count: instance skills under ${REPO}/.claude/skills/ (may be empty — instance skills are optional) AND the core skills under ${REPO}/core/skills/, which are loaded as brain-core:<name>. Measure listing size (sum of frontmatter descriptions in characters), check symlinks, reconcile against the auto-fire table in ${REPO}/.claude/rules/intelligence-instanz.md. An empty .claude/skills/ is NOT a finding; an auto-fire row without an existing skill is.` },
  { slug: 'docs', prompt: `Section 4 (Docs vs. reality). ${REPO}/CLAUDE.md + ${REPO}/.claude/rules/*.md against system reality (check versions via Bash), reference files, .mcp.json reconciliation.` },
  { slug: 'memory', prompt: `Section 5 (Memory). The auto-memory directory ($HOME/.claude/projects/<project path, "/" replaced by "-">/memory/) + ${REPO}/docs/memory-snapshot/ (measure limits, diff, manifest, index completeness).` },
  { slug: 'git-hygiene', prompt: `Section 6 (Git & repo hygiene). git status/branch/remote distance, root whitelist, junk files, large binaries (git ls-files + du).` },
  { slug: 'sota-claude-code', prompt: `Section 7, Claude Code part. Load WebSearch/WebFetch via ToolSearch "select:WebSearch,WebFetch". Changelog/release notes since ${ctx.last_scan_date || '2026-07-29'}: breaking changes in the hooks API, skills budget, permissions, memory limits, subagents. Report only setup-relevant deltas, with source.` },
  { slug: 'sota-mcp-security', prompt: `Section 7, MCP/security part. Load WebSearch/WebFetch via ToolSearch "select:WebSearch,WebFetch".
STEP 1 — determine the server inventory YOURSELF, do not assume. Three sources, check all three: (a) ${REPO}/.mcp.json (may be missing), (b) "mcpServers" in ~/.claude.json, (c) plugin-provided servers: ~/.claude/plugins/installed_plugins.json plus the loaded tool names (prefix mcp__plugin_<plugin>_<server>__). If you find no server, THAT is this section's result — then no research on invented servers.
STEP 2 — only research with this list: MCP spec changes/deprecations since ${ctx.last_scan_date || '2026-07-29'} and new CVE/attack patterns that apply to the FOUND servers (transport, dependencies, installation path). Only what is relevant, with source.
STEP 3 — check the installation path of the found servers: lockfile respected? Lifecycle scripts allowed? Floating ranges? A server that reinstalls itself unpinned on every start is a finding.
Name explicitly WHICH servers you found in the result — a section about servers that do not exist here is worthless.` },
]

phase('Scan')
const scanResults = await parallel(SCANS.map(s => () =>
  agent(`${SCAN_COMMON}\n\n${s.prompt}`, { label: `scan:${s.slug}`, phase: 'Scan', model: 'haiku', schema: FINDINGS_SCHEMA })
))
const scans = scanResults.filter(Boolean)
log(`${scans.length}/${SCANS.length} scans done`)

// ── Phase 3: Fixes (ordered only, sequential) ─────────────────────────────
phase('Fixes')
const fixResults = []
for (const order of ctx.orders) {
  const r = await agent(
    `You are implementing a task ORDERED by the operator in the repo ${REPO}:\n"${order}"\n
Rules (HARD): CLAUDE.md + .claude/rules/ apply in full (ponytail, order fidelity, no scope creep — ONLY this task). NO live-rig/network/show-hardware access from the brain scan — if the task needs live writes, abort with status "braucht-eigene-session". After implementation, VERIFY (test/measurement, do not assert). No git commit/push. StructuredOutput.`,
    { label: `fix:${order.slice(0, 40)}`, phase: 'Fixes', schema: {
      type: 'object', required: ['order', 'status', 'detail'],
      properties: {
        order: { type: 'string' },
        status: { type: 'string', enum: ['umgesetzt-verifiziert', 'fehlgeschlagen', 'braucht-eigene-session'] },
        detail: { type: 'string', description: 'what was done + how it was verified, or why not' },
      },
    } },
  )
  if (r) fixResults.push(r)
  log(`Fix "${order.slice(0, 50)}": ${r ? r.status : 'agent-error'}`)
}

// ── Phase 4: Report ───────────────────────────────────────────────────────
phase('Report')
const allFindings = scans.flatMap(s => s.findings.map(f => `[${f.severity}${f.state ? '/' + f.state : ''}] ${f.title}`))
const summary = await agent(
  `You are the report agent of the brain scan of ${DATE}. Input below. Tasks:
1. Write ${REPORT}: header (date, last scan ${ctx.last_scan_date || 'never'}), overall state in 3-5 sentences, findings sorted P0>P1>P2>INFO (RECURRING marked), OK checks as a short list **with state \`configured\`/\`verified\`** (checklist section 0; an OK without a state is itself a P1 finding against the scan), fix protocol (ordered tasks + status + verify), new proposals (derived).
2. Update ${AUFTRAEGE} via Edit: move successfully implemented ordered items to "Erledigt" (done, with date ${DATE}); failed/braucht-eigene-session items stay open with a note; append NEW derived proposals (only real ones, deduplicated against existing) under "Vorgeschlagen" (proposed). NEVER fill the section "Offen (bestellt)" yourself.
3. StructuredOutput: summary = 4-6 sentences overall state incl. P0/P1 counts, findings = the 10 most important.

Scan findings:\n${allFindings.join('\n')}\n\nScan summaries:\n${scans.map(s => `- ${s.summary}`).join('\n')}\n\nFix results:\n${JSON.stringify(fixResults)}`,
  { label: 'report', phase: 'Report', schema: FINDINGS_SCHEMA },
)

return {
  date: DATE,
  report: REPORT,
  ordersExecuted: fixResults,
  summary: summary ? summary.summary : null,
  topFindings: summary ? summary.findings.map(f => `[${f.severity}] ${f.title}`) : allFindings.slice(0, 15),
}
