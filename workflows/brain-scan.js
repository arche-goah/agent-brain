export const meta = {
  name: 'brain-scan',
  description: 'Brain scan & agentic self-improvement: checklist audit + SOTA delta + ordered fixes + report',
  whenToUse: 'Recurring self-audit of the brain setup. Call with args {date:"YYYY-MM-DD", scratch:"<abs. scratch dir>"}.',
  phases: [
    { title: 'Context', detail: 'Order list + checklist + latest report', model: 'haiku' },
    { title: 'Scan', detail: '5 repo checks + 2 SOTA delta checks in parallel; each writes its findings to a file', model: 'haiku' },
    { title: 'Fixes', detail: 'ONLY operator-ordered items (origin: operator / von: Operator / von: <name>), sequential with verify; each writes its protocol to a file' },
    { title: 'Report', detail: 'Write scan report from the files, update the order list' },
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
if (!A || !A.date || !A.scratch) throw new Error('brain-scan requires args {date:"YYYY-MM-DD", scratch:"<abs. path>"} — date via Bash `date +%F`, scratch = session scratchpad subfolder')
const DATE = A.date
const REPORT = `${REPORT_DIR}/scan-${DATE}.md`
// Every stage's bulk output lives here; the report stage reads it from disk.
const FINDINGS_DIR = `${A.scratch}/findings`

// Shape of ONE finding as it is written to the scan files. Prompt text now, not a
// StructuredOutput schema: the findings travel to the report through the files.
const FINDING_ITEM = {
  type: 'object', required: ['severity', 'title'],
  properties: {
    severity: { type: 'string', enum: ['P0', 'P1', 'P2', 'INFO', 'OK'] },
    title: { type: 'string', description: '1 sentence, concrete, with file path/evidence' },
    state: {
      type: 'string', enum: ['configured', 'verified'],
      description: 'Required when severity is OK (checklist section 0): configured = precondition read/parsed · verified = the declared behavior check was actually run. Schema/existence checks are NEVER verified.',
    },
  },
}
// What a scan agent returns: a path, measured counts, a summary. The counts are
// routing-critical (they decide the report's numbers), so they stay schema-validated
// instead of living only in the file.
const SCAN_RESULT_SCHEMA = {
  type: 'object', required: ['file', 'finding_count', 'summary'],
  properties: {
    file: { type: 'string', description: 'path of the JSON file you wrote' },
    finding_count: { type: 'number', description: 'length of the findings array IN THE FILE, measured after writing' },
    p0_count: { type: 'number', description: 'number of P0 findings in the file, measured' },
    p1_count: { type: 'number', description: 'number of P1 findings in the file, measured' },
    summary: { type: 'string' },
  },
}

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

// ── Producer-writes helpers (begin) — extracted VERBATIM by scripts/test-brain-scan-files.sh
// Bulk data never crosses an agent boundary inside a prompt: the agent that PRODUCES
// findings (or a fix protocol) writes them to a file under FINDINGS_DIR, and the report
// agent reads the files itself. Across the boundary travel only a path, a count and a
// status. Measured 2026-09-13 on a coherence-scan run: 241,137 chars relayed through one
// prompt, 60,000 arrived, and the counts stayed green because they matched while the
// content did not. Here the report prompt carried every finding line of 8 scans plus
// `JSON.stringify(fixResults)` — unbounded, with no marker if it was cut.
const fileName = (p) => String(p).replace(/\\/g, '/').split('/').pop()
// `expected` is what the script STARTED; `found` is what a consumer reports it read
// from disk (its ls, not its memory). Compared by file name: script and agent may
// spell the same directory differently (separators, drive forms) while the names
// inside one directory are unique. Any gap aborts — a scan section whose file is
// missing did not run, and a report over the rest reads exactly like a full one.
const assertFiles = (expected, found, what) => {
  const have = new Set((found || []).map(fileName))
  const missing = expected.filter(f => !have.has(fileName(f)))
  if (missing.length) {
    throw new Error(`${what}: ${missing.length} of ${expected.length} file(s) missing — ${missing.map(fileName).join(', ')}. Aborting instead of continuing on a partial corpus (rules/intelligence.md, "only the producer writes").`)
  }
}
// ── Producer-writes helpers (end)

// ── Phase 1: Context ───────────────────────────────────────────────────────
phase('Context')
const ctx = await agent(
  `Read (1) ${AUFTRAEGE}, (2) ${CHECKLIST}, (3) the newest existing report in ${REPORT_DIR}/ (ls, then read the newest scan-*.md; if none exists: last_scan_date = null, prev_open = []).
Return via StructuredOutput: orders = ONLY the items from the section headed "Offen (bestellt)" or "Open (ordered)" (the same section, German or English template) that are operator-ordered — the origin marker is any of these three forms: "origin: operator", the literal "von: Operator", or "von: <the operator's documented name>" (e.g. "von: Emil"); all three count as ordered, "derived"/"abgeleitet" never does — and that are (a) unfinished (checkbox [ ] — skip [x]) AND (b) carry NO "eigene Session"/"EIGENE-SESSION" (own-session) note (the scan never touches such projects, only reports them as open). Full wording; last_scan_date; prev_open = unresolved finding titles from the last report. The return value is raw data.`,
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
const SCAN_COMMON = `You are a brain-scan agent for ${REPO}. STRICTLY READ-ONLY. Check EVERY check of your checklist section from ${CHECKLIST} individually and concretely (measure/read/test, do not guess). Already-known unresolved findings from the last scan: ${relay(ctx.prev_open, 3000, 'prev_open')} — prefix such findings with "RECURRING:". Severity OK = check passed (report only in summarized form) — then "state" is REQUIRED: "verified" ONLY if you yourself executed the behavior check declared in section 0/your section and can name the result; reading/parsing/schema-checking is "configured". When in doubt: "configured".
FRESHNESS REQUIREMENT: every statement about rule/doc files (CLAUDE.md, rules/, checklist, settings) must rest on a read from disk IN THIS RUN — never quote injected context/system-prompt copies (2026-08-01: two stale findings, refuted by grep).
ADDITIONAL CRITERION in YOUR area (every section, no auto-fix): if you notice a construct that only resolves on macOS/BSD (BSD-only flags like \`stat -f\`/\`date -r\`, \`zsh\`-specific syntax, \`launchd\`, fixed paths like /opt/homebrew, assumption of \`/\` path separators, tools like \`system_profiler\`/\`ioreg\` without fallback) — report it as a separate finding prefixed "OS:" (severity INFO, never higher for this alone), file+line, 1 sentence why it could break on Windows/Linux, plus — where evident — a brief suggestion for the Windows/POSIX equivalent. No fix, no judgment: making it robust needs its own review session with the Windows machine + PR reconciliation, not this scan.
StructuredOutput per schema; return value = raw data.`

const CVE_RULE = `CVE DISCIPLINE: a CVE identifier may only be reported as fact if you read it IN THIS RUN from an official source — the affected repo's GitHub Security Advisories (\`gh api repos/<owner>/<repo>/security-advisories\`), an NVD/MITRE record fetched by its ID, or the vendor's own advisory page. A number that appears only in web-search results (blogs, news, aggregators) is reported with "UNCONFIRMED" in the title, state "configured" (never "verified"), and its search source named. The underlying recommendation (e.g. "update the CLI") may still carry the severity the official facts support. (2026-08-13: a scan reported five CVE numbers as P0/verified that exist in no official source — changelog and advisory list both came back empty.)`

const SCANS = [
  { slug: 'effect', prompt: `Section 0 (Effect). Run via Bash \`bash ${REPO}/core/scripts/effect-check.sh ${REPO}\`. Report EVERY RED line as its own finding (P1, title = wording of the line) and EVERY INFO line pointing to something shipped-but-not-wired as INFO. Summarize the OK lines into ONE finding of severity OK with state "verified" — this script IS the behavior check, it compares declaration against the consuming side. Invent nothing: only what the script outputs. If the script fails (missing/exit>1), THAT is the finding.` },
  { slug: 'permissions-hooks', prompt: `Sections 1 (Permissions & security) + 3 (Hooks & settings). Files: ${REPO}/.claude/settings.json, ${REPO}/.claude/settings.local.json and EVERY script wired inside them — since the core split the hook helpers live under ${REPO}/core/helpers/, not under .claude/helpers/. Check the paths that actually appear in the settings instead of expecting a location.` },
  { slug: 'skills', prompt: `Section 2 (Skills). Two sources, both count: instance skills under ${REPO}/.claude/skills/ (may be empty — instance skills are optional) AND the core skills under ${REPO}/core/skills/, which are loaded as brain-core:<name>. Measure listing size (sum of frontmatter descriptions in characters), check symlinks, reconcile against the auto-fire table in ${REPO}/.claude/rules/intelligence-instance.md (legacy name in not-yet-migrated brains: intelligence-instanz.md — use whichever exists). An empty .claude/skills/ is NOT a finding; an auto-fire row without an existing skill is.` },
  { slug: 'docs', prompt: `Section 4 (Docs vs. reality). ${REPO}/CLAUDE.md + ${REPO}/.claude/rules/*.md against system reality (check versions via Bash), reference files, .mcp.json reconciliation.` },
  { slug: 'memory', prompt: `Section 5 (Memory). The auto-memory directory ($HOME/.claude/projects/<project path, "/" replaced by "-">/memory/) + ${REPO}/docs/memory-snapshot/ (measure limits, diff, manifest, index completeness).` },
  { slug: 'git-hygiene', prompt: `Section 6 (Git & repo hygiene). git status/branch/remote distance, root whitelist, junk files, large binaries (git ls-files + du).` },
  { slug: 'sota-claude-code', prompt: `Section 7, Claude Code part. Load WebSearch/WebFetch via ToolSearch "select:WebSearch,WebFetch". Changelog/release notes since ${ctx.last_scan_date || '2026-07-29'}: breaking changes in the hooks API, skills budget, permissions, memory limits, subagents. Report only setup-relevant deltas, with source. ${CVE_RULE}` },
  { slug: 'sota-mcp-security', prompt: `Section 7, MCP/security part. Load WebSearch/WebFetch via ToolSearch "select:WebSearch,WebFetch".
STEP 1 — determine the server inventory YOURSELF, do not assume. Three sources, check all three: (a) ${REPO}/.mcp.json (may be missing), (b) "mcpServers" in ~/.claude.json, (c) plugin-provided servers: ~/.claude/plugins/installed_plugins.json plus the loaded tool names (prefix mcp__plugin_<plugin>_<server>__). If you find no server, THAT is this section's result — then no research on invented servers.
STEP 2 — only research with this list: MCP spec changes/deprecations since ${ctx.last_scan_date || '2026-07-29'} and new CVE/attack patterns that apply to the FOUND servers (transport, dependencies, installation path). Only what is relevant, with source. ${CVE_RULE}
STEP 3 — check the installation path of the found servers: lockfile respected? Lifecycle scripts allowed? Floating ranges? A server that reinstalls itself unpinned on every start is a finding.
Name explicitly WHICH servers you found in the result — a section about servers that do not exist here is worthless.` },
]

phase('Scan')
const scanFile = (slug) => `${FINDINGS_DIR}/scan-${slug}.json`
const scanFiles = SCANS.map(s => scanFile(s.slug))
const scanResults = await parallel(SCANS.map(s => () =>
  agent(`${SCAN_COMMON}\n\n${s.prompt}\n\nOUTPUT — you are the producer, you write: save your findings as JSON to ${scanFile(s.slug)} (mkdir -p ${FINDINGS_DIR}) with exactly this shape: {"section": "${s.slug}", "summary": "<3 sentences>", "findings": [<objects>]} where every object satisfies this JSON schema: ${JSON.stringify(FINDING_ITEM)}. The findings array is this scan's data and travels ONLY through that file — nothing of it comes back through your return value. After writing, MEASURE the file: count the findings array and the P0/P1 entries in it (node -e or jq, not from memory). Return via StructuredOutput: file (the path you wrote), finding_count, p0_count, p1_count (all measured), summary.`,
    { label: `scan:${s.slug}`, phase: 'Scan', model: 'haiku', schema: SCAN_RESULT_SCHEMA })
))
const scans = scanResults.filter(Boolean)
// First gate, claim level, before any report tokens are spent: every started scan
// returned and named its file. A null (agent died/skipped) is a missing file.
assertFiles(scanFiles, scanResults.map(r => r && r.file), 'scan: section files reported')
const rawCount = scans.reduce((n, r) => n + r.finding_count, 0)
log(`${scans.length}/${SCANS.length} scans wrote their file, ${rawCount} findings on disk`)

// ── Phase 3: Fixes (ordered only, sequential) ─────────────────────────────
phase('Fixes')
const fixResults = []
const fixFile = (i) => `${FINDINGS_DIR}/fix-${i + 1}.json`
const fixFiles = ctx.orders.map((o, i) => fixFile(i))
for (const [i, order] of ctx.orders.entries()) {
  const r = await agent(
    `You are implementing a task ORDERED by the operator in the repo ${REPO}:\n"${order}"\n
Rules (HARD): CLAUDE.md + .claude/rules/ apply in full (ponytail, order fidelity, no scope creep — ONLY this task). NO live-rig/network/show-hardware access from the brain scan — if the task needs live writes, abort with status "braucht-eigene-session". After implementation, VERIFY (test/measurement, do not assert). No git commit/push.
OUTPUT — you are the producer, you write: save your protocol as JSON to ${fixFile(i)} (mkdir -p ${FINDINGS_DIR}) as {"order": "<the task verbatim>", "status": "<your status>", "detail": "<what you did + how you verified it, or why not>"}. The detail is this stage's data and travels ONLY through that file. Write the file EVEN IF you failed or aborted — a missing file aborts the run.
Return via StructuredOutput: file (the path you wrote), order, status.`,
    { label: `fix:${order.slice(0, 40)}`, phase: 'Fixes', schema: {
      type: 'object', required: ['file', 'order', 'status'],
      properties: {
        file: { type: 'string', description: 'path of the JSON file you wrote' },
        order: { type: 'string' },
        status: { type: 'string', enum: ['umgesetzt-verifiziert', 'fehlgeschlagen', 'braucht-eigene-session'] },
      },
    } },
  )
  if (r) fixResults.push(r)
  log(`Fix "${order.slice(0, 50)}": ${r ? r.status : 'agent-error'}`)
}
// Same gate for the fix stage: a fix agent that died leaves no file, and a protocol
// missing from the report is indistinguishable from a task that was never ordered.
assertFiles(fixFiles, fixResults.map(r => r && r.file), 'fixes: protocol files reported')

// ── Phase 4: Report ───────────────────────────────────────────────────────
phase('Report')
const dataFiles = [...scanFiles, ...fixFiles]
const summary = await agent(
  `You are the report agent of the brain scan of ${DATE}. Tasks:
1. Write ${REPORT}: header (date, last scan ${ctx.last_scan_date || 'never'}), overall state in 3-5 sentences, findings sorted P0>P1>P2>INFO (RECURRING marked), OK checks as a short list **with state \`configured\`/\`verified\`** (checklist section 0; an OK without a state is itself a P1 finding against the scan), fix protocol (ordered tasks + status + verify), new proposals (derived).
2. Update ${AUFTRAEGE} via Edit: move successfully implemented ordered items to "Erledigt" (done, with date ${DATE}); failed/braucht-eigene-session items stay open with a note; append NEW derived proposals (only real ones, deduplicated against existing) under "Vorgeschlagen" / "Proposed (derived)" (whichever heading the list uses). NEVER fill the section "Offen (bestellt)" / "Open (ordered)" yourself.
3. StructuredOutput: files_read (every data file you actually read, from your ls), summary = 4-6 sentences overall state incl. P0/P1 counts, findings = the 10 most important, finding_count = the summed length of the scan files' findings arrays, MEASURED (node -e or jq), never estimated.

DATA BASIS ON DISK — read these COMPLETELY before writing, never from memory of an earlier stage. They lie in ${FINDINGS_DIR}/: the scan sections ${scanFiles.map(fileName).join(', ')}${fixFiles.length ? ` and the fix protocols ${fixFiles.map(fileName).join(', ')}` : ' (no ordered tasks ran, so there are no fix protocols)'}.
STEP 1: ls ${FINDINGS_DIR} — if one of these files is missing, STOP: return files_read = what exists, finding_count = 0, findings = [] (the script aborts on that; never report on a partial set).
STEP 2: read them all, then write the report.
AUTHORITATIVE number (machine-derived from the validated returns): ${rawCount} findings across ${scans.length} scan sections. If a file's own summary deviates, this number wins.`,
  { label: 'report', phase: 'Report', schema: {
    type: 'object',
    required: ['files_read', 'summary', 'findings'],
    properties: {
      files_read: { type: 'array', items: { type: 'string' }, maxItems: 40 },
      finding_count: { type: 'number' },
      ...FINDINGS_SCHEMA.properties,
    },
  } },
)
if (summary) {
  // Second gate, measured: what the consumer found on disk, against what was started.
  assertFiles(dataFiles, summary.files_read, 'report: data files read from disk')
  assertCount(rawCount, summary.finding_count, 'brain-scan findings read by the report')
}

return {
  date: DATE,
  report: REPORT,
  // Status and order per fix, not the protocols — those stay in their files.
  ordersExecuted: fixResults.map(r => ({ order: r.order, status: r.status, file: r.file })),
  findings: rawCount,
  findingsDir: FINDINGS_DIR,
  summary: summary ? summary.summary : null,
  topFindings: summary ? summary.findings.map(f => `[${f.severity}] ${f.title}`) : [],
}
