export const meta = {
  name: 'brain-scan',
  description: 'Brain scan: return channel of the last run + machine checks + checklist audit + SOTA delta; every finding leaves with one exit — reports and sorts, fixes nothing',
  whenToUse: 'Weekly self-audit of the brain setup, on the operator\'s OK. Call with args {date:"YYYY-MM-DD", scratch:"<abs. scratch dir>"}.',
  phases: [
    { title: 'Machine', detail: 'ONE script: what became of the last run\'s findings, machine checks (effect, invariant register, self-test, local machinery, commitments), deep-check line', model: 'haiku' },
    { title: 'Scan', detail: 'Checklist sections + 2 SOTA delta checks in parallel; each writes its findings to a file', model: 'haiku' },
    { title: 'Report', detail: 'Sort every finding into one exit, at most three operator decisions, update the order list, write the report' },
  ],
}

// ── Shape (operator decisions 2026-10-09, after an audit of the audit process) ──
// The scan REPORTS AND SORTS; it never fixes. Measured on the proving brain: 19 of 32 fix
// agents ended "needs its own session" (1.99M tokens for nothing), and fixing happens in
// the session with the operator anyway. It STARTS with the return channel (what became of
// the last run's findings — a deterministic script, not an agent), because the old scan
// was a one-way funnel: proposals piled up unread, done items stayed unticked, the same
// finding came back up to ten times without ever becoming a decision. Every finding
// leaves with exactly one exit (skill backlog-catch-up); a finding seen a third time is
// an operator decision. Checklist section -> executor (fixture: every template section
// has one; a section without an executor is a wish, measured twice):
//   0 effect, 9 invariant register, 10 self-check, boundary (local machinery,
//   commitments)                                         -> Machine (scripts/brain-scan-prep.py)
//   1+3 permissions-hooks · 2 skills · 4 docs · 5 memory · 6 git-hygiene
//   7 sota-claude-code + sota-mcp-security · 8 shared-memory   -> Scan agents
// SECTION_EXECUTORS: 0=machine 1=permissions-hooks 2=skills 3=permissions-hooks 4=docs 5=memory 6=git-hygiene 7=sota 8=shared-memory 9=machine 10=machine

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
  type: 'object', required: ['file', 'finding_count', 'ok_count', 'summary'],
  properties: {
    file: { type: 'string', description: 'path of the JSON file you wrote' },
    finding_count: { type: 'number', description: 'length of the findings array IN THE FILE, measured after writing' },
    ok_count: { type: 'number', description: 'number of severity OK findings in the file, measured' },
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
// findings writes them to a file under FINDINGS_DIR, and the report
// agent reads the files itself. Across the boundary travel only a path, a count and a
// status. Measured 2026-09-13 on a coherence-scan run: 241,137 chars relayed through one
// prompt, 60,000 arrived, and the counts stayed green because they matched while the
// content did not. Here the report prompt carried every finding line of 8 scans plus
// the whole fix-protocol array as one JSON string — unbounded, with no marker if it was cut.
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
// The report is the deliverable, and a returned path is a claim. Measured 2026-10-02 on a
// Windows brain: the harness denied the report agent its Write, the agent returned
// report_path "" and the workflow finished as a normal success. The script has no file
// access, so the gate is: the path must be EXACTLY the one the script named, and the
// writer must return the byte count it MEASURED (wc -c) — empty path or 0 bytes aborts.
const assertReport = (expected, claimedPath, bytes, what) => {
  if (!claimedPath || fileName(claimedPath) !== fileName(expected)) {
    throw new Error(`${what}: report path is "${claimedPath || ''}", expected ${fileName(expected)} — the report was not written where the script asked. Aborting instead of returning a run without its deliverable.`)
  }
  if (!(Number(bytes) > 0)) {
    throw new Error(`${what}: ${fileName(expected)} measured at ${bytes === undefined ? 'no' : bytes} bytes — an empty or unmeasured report is not a report. Aborting.`)
  }
}
// Every finding leaves with exactly ONE exit (skill backlog-catch-up). Measured on the
// proving brain: what ended "needs the operator's decision" lay three weeks, a quarter of
// report-only measures vanished, and one finding came back ten times as the same line.
// `index` is the report's validated list of non-OK findings; an entry may merge several
// raw findings (`merged`, the same matter seen by two sections), but every raw finding
// must be accounted for. A key the return channel marked decision-due (seen twice before,
// unfixed) that comes back is an operator decision — not a fourth identical line. At most
// three decisions are presented; more means the cut is wrong (the rest is offered as a list).
const EXITS = ['done-already', 'ai-does-it', 'other-side', 'parked', 'later-at-system', 'drop', 'operator-decision']
const assertExits = (index, nonOk, decisionDue, decisions, what) => {
  const items = index || []
  const bad = items.filter(i => !EXITS.includes(i.exit))
  if (bad.length) throw new Error(`${what}: ${bad.length} finding(s) without a valid exit (${bad.map(i => `${i.key}=${i.exit}`).join(', ')}) — every finding leaves with exactly one of: ${EXITS.join(', ')}.`)
  const keys = items.map(i => i.key)
  const dup = keys.filter((k, n) => keys.indexOf(k) !== n)
  if (dup.length) throw new Error(`${what}: key(s) used twice (${[...new Set(dup)].join(', ')}) — one key, one exit.`)
  const covered = items.reduce((n, i) => n + (Number(i.merged) > 0 ? Number(i.merged) : 1), 0)
  if (covered !== nonOk) throw new Error(`${what}: the index accounts for ${covered} raw finding(s), the scan files hold ${nonOk} non-OK finding(s) — a finding without an exit is the leak this stage exists to close.`)
  const recur = items.filter(i => (decisionDue || []).includes(i.key) && i.exit !== 'operator-decision')
  if (recur.length) throw new Error(`${what}: ${recur.map(i => i.key).join(', ')} came back a third time without a fix but left as "${recur[0].exit}" — a third recurrence is an operator decision (close the source or accept it), never another line.`)
  const opdec = items.filter(i => i.exit === 'operator-decision').map(i => i.key)
  const ds = decisions || []
  if (ds.length !== Math.min(3, opdec.length)) throw new Error(`${what}: ${opdec.length} operator decision(s) in the index, ${ds.length} presented — present min(3, n), each with a recommendation.`)
  const stray = ds.filter(d => !opdec.includes(d.key) || !d.recommendation)
  if (stray.length) throw new Error(`${what}: presented decision(s) ${stray.map(d => d.key).join(', ')} are not operator-decision items of the index or carry no recommendation.`)
}
// ── Producer-writes helpers (end)

// ── Phase 1: Machine (one script, one cheap runner) ───────────────────────
// The workflow script has no shell, so ONE small agent runs ONE command and returns the
// script's own summary line. It replaces the context-gathering agent (~121k tokens per
// run for reading three files) and the effect-scan agent, and gives the two checklist
// sections that had no executor (invariant register, self-check) one.
phase('Machine')
const PREP_CMD = `python3 ${REPO}/core/scripts/brain-scan-prep.py --repo ${REPO} --out ${FINDINGS_DIR} --today ${DATE}`
const prep = await agent(
  `Run exactly this one command with the Bash tool (timeout 600000 ms; on Windows use \`python\` if \`python3\` is not the real interpreter), and nothing else:
${PREP_CMD}
Its LAST stdout line is a JSON object {"brain_scan_prep": {...}}. Return the inner object via StructuredOutput, values copied from that line — do not compute, summarise or re-run anything. If the command fails or prints no such line, return script_ok false and the error in error.`,
  { label: 'machine', phase: 'Machine', model: 'haiku', effort: 'low', schema: {
    type: 'object', required: ['script_ok', 'machine_findings', 'machine_ok', 'decision_due', 'deep_check'],
    properties: {
      script_ok: { type: 'boolean' },
      error: { type: 'string' },
      last_scan_date: { type: ['string', 'null'] },
      earlier: { type: 'number' },
      states: { type: 'object' },
      decision_due: { type: 'array', items: { type: 'string' }, maxItems: 200 },
      deep_check: { type: 'array', items: { type: 'string' }, maxItems: 5 },
      ordered_open: { type: 'number' },
      machine_findings: { type: 'number' },
      machine_ok: { type: 'number' },
      machine_p0: { type: 'number' },
      machine_p1: { type: 'number' },
    },
  } },
)
if (!prep || !prep.script_ok) throw new Error(`Machine step failed: ${prep ? prep.error : 'agent died'} — without the return channel the scan would report blind; fix the run, not the stage.`)
const MACHINE_FILE = `${FINDINGS_DIR}/scan-machine.json`
const RETURN_FILE = `${FINDINGS_DIR}/return-channel.json`
const REPORT_HEAD = `${FINDINGS_DIR}/report-machine.md`
const LAST_SCAN = prep.last_scan_date || null
log(`return channel: ${prep.earlier || 0} earlier finding(s) (${Object.entries(prep.states || {}).map(([k, v]) => `${k} ${v}`).join(', ')}), decision-due ${prep.decision_due.length}; machine checks ${prep.machine_findings} finding(s); deep check: ${prep.deep_check.length ? prep.deep_check.map(l => l.split(' — ')[0].replace('deep check suggested: ', '')).join(', ') : 'none'}`)

// ── Phase 2: Scan (repo + SOTA in parallel) ───────────────────────────────
const SCAN_COMMON = `You are a brain-scan agent for ${REPO}. STRICTLY READ-ONLY. Check EVERY check of your checklist section from ${CHECKLIST} individually and concretely (measure/read/test, do not guess). Do NOT run effect-check, invariant-check, brain-selftest, local-machinery or commitments — they already ran in the machine step and their findings are in ${MACHINE_FILE}; a second run costs tokens and doubles findings. Recurrence is traced by the report stage, not by you. Severity OK = check passed (report only in summarized form) — then "state" is REQUIRED: "verified" ONLY if you yourself executed the behavior check declared in section 0/your section and can name the result; reading/parsing/schema-checking is "configured". When in doubt: "configured".
FRESHNESS REQUIREMENT: every statement about rule/doc files (CLAUDE.md, rules/, checklist, settings) must rest on a read from disk IN THIS RUN — never quote injected context/system-prompt copies (2026-08-01: two stale findings, refuted by grep).
CONTEXT REQUIREMENT (a single grepped line is not a finding — three scans in a row lost findings this way): (a) before reporting any construct as a portability/OS risk, read +/-5 lines around it and rule out a fallback there (e.g. \`stat -c\` before \`stat -f\`, \`date -d\` after \`date -r\`), and cite the line you actually read; (b) before reporting a file as missing, search every candidate location — \`scripts/\`, \`core/scripts/\`, \`core/helpers/\`, the plugin cache, and a path relative to another repo when the referring line names one (\`~/Projects/<repo>/...\`).
ADDITIONAL CRITERION in YOUR area (every section, no auto-fix): if you notice a construct that only resolves on macOS/BSD (BSD-only flags like \`stat -f\`/\`date -r\`, \`zsh\`-specific syntax, \`launchd\`, fixed paths like /opt/homebrew, assumption of \`/\` path separators, tools like \`system_profiler\`/\`ioreg\` without fallback) — report it as a separate finding prefixed "OS:" (severity INFO, never higher for this alone), file+line, 1 sentence why it could break on Windows/Linux, plus — where evident — a brief suggestion for the Windows/POSIX equivalent. No fix, no judgment: making it robust needs its own review session with the Windows machine + PR reconciliation, not this scan.
StructuredOutput per schema; return value = raw data.`

const CVE_RULE = `CVE DISCIPLINE: a CVE identifier may only be reported as fact if you read it IN THIS RUN from an official source — FIRST the global GitHub advisory database by ID (\`gh api "/advisories?cve_id=<CVE>"\` — it covers advisories the affected repo does not publish itself), else the affected repo's GitHub Security Advisories (\`gh api repos/<owner>/<repo>/security-advisories\`), an NVD/MITRE record fetched by its ID, or the vendor's own advisory page. A confirmed CVE takes its severity from the advisory, not from a search result, and is only P0/P1 if the INSTALLED version (read it: \`.mcp.json\` pin, \`~/.claude/plugins/installed_plugins.json\`, \`claude --version\`) lies inside the advisory's affected range — installed version outside the range, or the range not determinable, is INFO with both versions named. A number that appears only in web-search results (blogs, news, aggregators) is reported with "UNCONFIRMED" in the title, state "configured" (never "verified"), its search source named, and severity at most P2. (2026-08-13: a scan reported five CVE numbers as P0/verified that exist in no official source. 2026-09-24: the same class came back despite this rule — two of those numbers again as P1, and a third as P0 "CVSS 9.0" whose global advisory existed all along, rated MEDIUM, affecting "through 2.1.2" while 4.1.1 was installed.)`

const SCANS = [
  { slug: 'permissions-hooks', prompt: `Sections 1 (Permissions & security) + 3 (Hooks & settings). Files: ${REPO}/.claude/settings.json, ${REPO}/.claude/settings.local.json and EVERY script wired inside them — since the core split the hook helpers live under ${REPO}/core/helpers/, not under .claude/helpers/. Check the paths that actually appear in the settings instead of expecting a location.` },
  { slug: 'skills', prompt: `Section 2 (Skills). Two sources, both count: instance skills under ${REPO}/.claude/skills/ (may be empty — instance skills are optional) AND the core skills under ${REPO}/core/skills/, which are loaded as brain-core:<name>. Measure listing size (sum of frontmatter descriptions in characters), check symlinks, reconcile against the auto-fire table in ${REPO}/.claude/rules/intelligence-instance.md (legacy name in not-yet-migrated brains: intelligence-instanz.md — use whichever exists). An empty .claude/skills/ is NOT a finding; an auto-fire row without an existing skill is.` },
  { slug: 'docs', prompt: `Section 4 (Docs vs. reality). ${REPO}/CLAUDE.md + ${REPO}/.claude/rules/*.md against system reality (check versions via Bash), reference files, .mcp.json reconciliation.` },
  { slug: 'memory', prompt: `Section 5 (Memory). The auto-memory directory ($HOME/.claude/projects/<project path, "/" replaced by "-">/memory/) + ${REPO}/docs/memory-snapshot/ (measure limits, diff, manifest, index completeness).` },
  // Numbers follow templates/brain-scan-checklist.md (0-8). Until 2026-10-05 the template
  // had 6 = Shared memory and no git/SOTA sections, so the section named here as 6 was not
  // the one a template-based brain had as 6, and no agent ever scanned shared memory.
  { slug: 'shared-memory', prompt: `The checklist section titled "Shared memory" (number 8 in the core template; an older instance checklist may number it differently or not have it — then say so as one INFO finding and scan the items below anyway). Shared repo: $SHARED_MEMORY_REPO, default $HOME/Projects/brain-shared-memory; if it is not cloned, that is ONE INFO finding and you stop. Measure: \`python3 ${REPO}/core/scripts/shared-memory-lint.py --repo <repo>\` (every non-zero line is a finding); \`git -C <repo> status --short\` and unpushed commits; \`python3 ${REPO}/core/scripts/shared-memory-inbox.py --open --repo <repo> --to origin/main\` — every listed request is a P1 finding with its date and sender (an unanswered request is the failure this section exists for).` },
  { slug: 'git-hygiene', prompt: `Section 6 (Git & repo hygiene). git status/branch/remote distance, root whitelist, junk files, large binaries (git ls-files + du).` },
  { slug: 'sota-claude-code', prompt: `Section 7, Claude Code part. Load WebSearch/WebFetch via ToolSearch "select:WebSearch,WebFetch". Changelog/release notes since ${LAST_SCAN || '2026-07-29'}: breaking changes in the hooks API, skills budget, permissions, memory limits, subagents. Report only setup-relevant deltas, with source. ${CVE_RULE}` },
  { slug: 'sota-mcp-security', prompt: `Section 7, MCP/security part. Load WebSearch/WebFetch via ToolSearch "select:WebSearch,WebFetch".
STEP 1 — determine the server inventory YOURSELF, do not assume. Three sources, check all three: (a) ${REPO}/.mcp.json (may be missing), (b) "mcpServers" in ~/.claude.json, (c) plugin-provided servers: ~/.claude/plugins/installed_plugins.json plus the loaded tool names (prefix mcp__plugin_<plugin>_<server>__). If you find no server, THAT is this section's result — then no research on invented servers.
STEP 2 — only research with this list: MCP spec changes/deprecations since ${LAST_SCAN || '2026-07-29'} and new CVE/attack patterns that apply to the FOUND servers (transport, dependencies, installation path). Only what is relevant, with source. ${CVE_RULE}
STEP 3 — check the installation path of the found servers: lockfile respected? Lifecycle scripts allowed? Floating ranges? A server that reinstalls itself unpinned on every start is a finding.
Name explicitly WHICH servers you found in the result — a section about servers that do not exist here is worthless.` },
]

phase('Scan')
const scanFile = (slug) => `${FINDINGS_DIR}/scan-${slug}.json`
const scanFiles = SCANS.map(s => scanFile(s.slug))
const scanResults = await parallel(SCANS.map(s => () =>
  agent(`${SCAN_COMMON}\n\n${s.prompt}\n\nOUTPUT — you are the producer, you write exactly ONE file, the path named here, and no other; any path you report back is exactly this one: save your findings as JSON to ${scanFile(s.slug)} (mkdir -p ${FINDINGS_DIR}) with exactly this shape: {"section": "${s.slug}", "summary": "<3 sentences>", "findings": [<objects>]} where every object satisfies this JSON schema: ${JSON.stringify(FINDING_ITEM)}. The findings array is this scan's data and travels ONLY through that file — nothing of it comes back through your return value. After writing, MEASURE the file: count the findings array and the P0/P1 entries in it (node -e or jq, not from memory). Return via StructuredOutput: file (the path you wrote), finding_count, ok_count, p0_count, p1_count (all measured), summary.`,
    { label: `scan:${s.slug}`, phase: 'Scan', model: 'haiku', schema: SCAN_RESULT_SCHEMA })
))
const scans = scanResults.filter(Boolean)
// First gate, claim level, before any report tokens are spent: every started scan
// returned and named its file. A null (agent died/skipped) is a missing file.
assertFiles(scanFiles, scanResults.map(r => r && r.file), 'scan: section files reported')
// Machine findings count too: they are the effect, register and self-check sections.
const rawCount = scans.reduce((n, r) => n + r.finding_count, 0) + prep.machine_findings
const nonOk = scans.reduce((n, r) => n + r.finding_count - r.ok_count, 0) + prep.machine_findings - prep.machine_ok
log(`${scans.length}/${SCANS.length} scans wrote their file; ${rawCount} findings on disk incl. machine checks, ${nonOk} need an exit`)

// ── Phase 3: Report (sort, never fix) ─────────────────────────────────────
phase('Report')
const dataFiles = [MACHINE_FILE, RETURN_FILE, ...scanFiles]
const BODY = `${FINDINGS_DIR}/report-body.md`
const summary = await agent(
  `You are the report agent of the brain scan of ${DATE} (last scan ${LAST_SCAN || 'never'}). The scan REPORTS AND SORTS — you change no file of the brain except the order list (task 3) and the report. Fixing happens in the session with the operator.

DATA BASIS ON DISK — read these COMPLETELY before writing, never from memory of an earlier stage: ${dataFiles.map(fileName).join(', ')} in ${FINDINGS_DIR}/, and the order list ${AUFTRAEGE} (may be missing).
STEP 1: ls ${FINDINGS_DIR} — if one of these files is missing, STOP: return files_read = what exists, finding_count = 0, index = [], decisions = [] (the script aborts on that; never report on a partial set).

TASK 1 — give every non-OK finding EXACTLY ONE exit (skill backlog-catch-up; one key per matter, findings of the same matter from several sections are ONE entry with merged = how many raw findings it covers):
  done-already (a later session already built it — say with which evidence) · ai-does-it (clear, reversible, own brain / own suite / a core PR — the session does it after the scan) · other-side (a collaborator's domain or decision — a shared-memory note) · parked (the operator parked the domain or named a later date; a request from another side still gets a receipt) · later-at-system (a hand-step at a device, raised when work on that system starts) · drop (superseded, without subject, or a false alarm — with the reason) · operator-decision (goal, money, hardware, risk, external effect, release — and NOT answerable by measurement; the operator decides it better than the AI).
  KEYS: ${fileName(RETURN_FILE)} lists the earlier findings with their key and state. When a finding is the same matter as an earlier one, REUSE its key — that is how the next run traces it. A new matter gets a new kebab-case key (stable, about the matter, not the momentary number). These keys are decision-due — seen twice before without a fix; if one comes back now it MUST leave as operator-decision ("close the source mechanically, or accept it consciously" — with a recommendation), never as another line: ${relay(prep.decision_due, 3000, 'decision_due')}.
  At most THREE operator decisions are presented, each with a recommendation, answerable by number. More than three means the cut is wrong: re-check each (is it a decision, does it block now, can only the operator make it?); what fails goes to another exit; if more remain, present three and offer the rest as a list.

TASK 2 — write the report BODY to ${BODY} (mkdir -p ${FINDINGS_DIR}), then assemble the report with ONE shell command, never by retyping: \`cat ${REPORT_HEAD} ${BODY} > ${REPORT}\` (mkdir -p ${REPORT_DIR} first). ${fileName(REPORT_HEAD)} is the script-written head (return channel, ordered items, deep check) and must reach the report byte-identical. The body: a title line "# Brain-Scan Report — ${DATE}"; overall state in 3-5 plain sentences; one line "n I handle myself · m really need you"; "## Decisions for the operator" (the presented ones, each with its recommendation); "## Findings" sorted P0>P1>P2>INFO, each line starting with its severity marker in brackets (\`[P1]\`) and ending with "— exit: <exit>"; "## OK checks" as a short list **with state \`configured\`/\`verified\`** (an OK without a state is itself a P1 finding against the scan); and LAST, exactly this section, one line per index entry, nothing else in it:
## Finding index
- key: <key> | severity: <P0|P1|P2|INFO> | exit: <exit> | title: <one-line title>

TASK 3 — update ${AUFTRAEGE} via Edit (if it exists): for every entry with exit ai-does-it, other-side, parked, later-at-system or operator-decision: if an entry with \`id: <key>\` exists, append one line "  seen again ${DATE} (brain-scan), exit: <exit>"; otherwise append a new entry under "Proposed (derived)" (or the list's own heading for derived items) in the list's field convention — \`id: <key>\`, class, reach, \`origin: derived\`, plus a line \`exit: <exit>\`. For exit done-already with an existing entry: tick it ([x]) and add "done — measured ${DATE} by brain-scan: <evidence>". NEVER fill the ordered section, never tick anything you did not measure.

RETURN via StructuredOutput: files_read (every data file you read, from your ls); finding_count = total findings in the data files incl. OK, MEASURED (node -e or jq); index = one object per index entry {key, severity, exit, merged}; decisions = the presented ones {key, question, recommendation}; deep_check_lines = number of lines starting "deep check suggested:" in the written report (grep -c); summary = 4-6 sentences incl. P0/P1 counts; findings = the 10 most important; report_path = ${REPORT} if written; report_bytes = \`wc -c < ${REPORT}\`. If a write was refused or failed: report_path "" and report_bytes 0 — never a path you did not write.
AUTHORITATIVE numbers (machine-derived): ${rawCount} findings, ${nonOk} of them non-OK and needing an exit. A deviation in your returned counts aborts the run.`,
  { label: 'report', phase: 'Report', schema: {
    type: 'object',
    required: ['files_read', 'summary', 'findings', 'finding_count', 'index', 'decisions', 'deep_check_lines', 'report_path', 'report_bytes'],
    properties: {
      files_read: { type: 'array', items: { type: 'string' }, maxItems: 40 },
      finding_count: { type: 'number' },
      index: { type: 'array', maxItems: 300, items: {
        type: 'object', required: ['key', 'severity', 'exit'],
        properties: {
          key: { type: 'string' },
          severity: { type: 'string', enum: ['P0', 'P1', 'P2', 'INFO'] },
          exit: { type: 'string', enum: EXITS },
          merged: { type: 'number', description: 'raw findings this entry covers (>=1)' },
        },
      } },
      decisions: { type: 'array', maxItems: 3, items: {
        type: 'object', required: ['key', 'question', 'recommendation'],
        properties: { key: { type: 'string' }, question: { type: 'string' }, recommendation: { type: 'string' } },
      } },
      deep_check_lines: { type: 'number' },
      report_path: { type: 'string' },
      report_bytes: { type: 'number' },
      ...FINDINGS_SCHEMA.properties,
    },
  } },
)
// A failed report agent used to fall through `if (summary)` and return as a success with
// the report path the SCRIPT had named — the same silent hole as memory-dream's empty path.
if (!summary) throw new Error('Report agent failed')
// Second gate, measured: what the consumer found on disk, against what was started.
assertFiles(dataFiles, summary.files_read, 'report: data files read from disk')
assertCount(rawCount, summary.finding_count, 'brain-scan findings read by the report')
assertExits(summary.index, nonOk, prep.decision_due, summary.decisions, 'brain-scan exits')
// The deep-check lines come from the script head; a report without them dropped the head.
assertCount(prep.deep_check.length, summary.deep_check_lines, 'deep-check lines in the report')
assertReport(REPORT, summary.report_path, summary.report_bytes, 'brain-scan report')

const exitCounts = {}
for (const i of summary.index) exitCounts[i.exit] = (exitCounts[i.exit] || 0) + 1
return {
  date: DATE,
  report: REPORT,
  findings: rawCount,
  exits: exitCounts,
  decisions: summary.decisions,
  deepCheck: prep.deep_check,
  returnChannel: { earlier: prep.earlier || 0, states: prep.states || {}, decisionDue: prep.decision_due },
  findingsDir: FINDINGS_DIR,
  summary: summary.summary,
  topFindings: summary.findings.map(f => `[${f.severity}] ${f.title}`),
}
