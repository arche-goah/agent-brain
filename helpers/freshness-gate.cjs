#!/usr/bin/env node
/**
 * freshness-gate.cjs — PreToolUse(Workflow): carrier for the repeat-run rule
 * (rules/intelligence.md, "Repeat Runs").
 *
 * An audit/analysis workflow costs six to seven figures in tokens. The rule says:
 * before one runs AGAIN, read the artifacts of the last run — a report younger
 * than the freshness threshold answers most questions without a re-run. As prose
 * the rule only works if someone remembers it at launch time; this hook asks the
 * question mechanically at exactly that moment.
 *
 * Mechanics: on every Workflow launch, resolve the workflow name (input name, or
 * meta.name from the script text / script file). Search this project's run
 * records (<project>/<session>/workflows/wf_*.json) for the newest COMPLETED run
 * of the same name. If it is younger than the threshold AND cost real tokens,
 * deny with the rule's three steps — read the record and journal, declare
 * "reused from <date>", or relaunch with an explicit justification marker.
 *
 * What counts as the last run (audit-audit on the Windows instance, 2026-11-10, AA-9: a
 * coherence-scan ran 6 days after the previous one because that one had ended `failed` at the
 * script's final check with its register already written, and a run on another machine was
 * invisible here):
 *  - a completed record;
 *  - a FAILED record whose report exists — a dated report of that workflow for the run's date;
 *  - a dated report in the repo with no record here (another machine, a pulled brain):
 *    docs/research/<name>/*-YYYY-MM-DD.md, docs/research/<name>-YYYY-MM-DD/ or
 *    docs/maintenance/<name>-YYYY-MM-DD.md (docs/repeat-runs.md);
 *  - a RESUMED run is one run with the attempt before it: the record then holds only the resumed
 *    part's tokens (measured -58 %), so the token floor does not apply to it.
 *
 * Escapes (all deliberate, none silent):
 *  - `resumeFromRunId` set — resume IS the recommended cheap path, never gated;
 *  - `FRESHNESS-OK: <reason>` comment in the script — the relaunch names which
 *    question the existing artifacts do not answer;
 *  - prior run killed, or failed without a report, or below the token floor (cheap probes
 *    re-run freely).
 *
 * Core/instance split: this engine is generic; thresholds are instance DATA in
 *   <project>/.claude/rules/freshness-gate.json
 *   { "thresholdDays": 14, "minTokens": 50000,
 *     "workflows": { "<name>": { "thresholdDays": 6, "minTokens": 0 } } }
 * A scheduled cadence (e.g. a scan every n days) sets its per-workflow threshold below
 * the cadence instead of carrying a permanent marker. Missing/broken file =
 * defaults. Fail-open throughout: a gate that errors must never block work.
 */
const fs = require('fs');
const { exit: hookExit } = require('./hook-exit.cjs');   // not process.exit: it hung at Node shutdown (2026-11-23)
const path = require('path');
const os = require('os');

const DEFAULT_THRESHOLD_DAYS = 14;
const DEFAULT_MIN_TOKENS = 50000;
// Floors the core itself sets (operator decision 2026-10-18): a brain-scan needs at least 7
// days since the last completed one; the bootup reports it due only after 14. Earlier only
// on the operator's clear word, given as the FRESHNESS-OK marker. An instance entry of the
// same name replaces the default.
const DEFAULT_WORKFLOWS = { 'brain-scan': { thresholdDays: 7 } };

function allow() { hookExit(0); }

function loadConfig(projectRoot) {
  const cfg = { thresholdDays: DEFAULT_THRESHOLD_DAYS, minTokens: DEFAULT_MIN_TOKENS,
                workflows: { ...DEFAULT_WORKFLOWS } };
  try {
    const raw = JSON.parse(fs.readFileSync(
      path.join(projectRoot, '.claude', 'rules', 'freshness-gate.json'), 'utf8'));
    if (typeof raw.thresholdDays === 'number') cfg.thresholdDays = raw.thresholdDays;
    if (typeof raw.minTokens === 'number') cfg.minTokens = raw.minTokens;
    if (raw.workflows && typeof raw.workflows === 'object') Object.assign(cfg.workflows, raw.workflows);
  } catch (_) { /* defaults */ }
  return cfg;
}

function metaName(scriptText) {
  if (!scriptText) return null;
  const m = scriptText.slice(0, 4000).match(/\bname\s*:\s*['"`]([^'"`\n]+)['"`]/);
  return m ? m[1] : null;
}

/** Project dir in ~/.claude/projects — exact via transcript_path, else munged cwd. */
function projectStateDir(input) {
  if (input.transcript_path) return path.dirname(input.transcript_path);
  const root = input.cwd || process.env.CLAUDE_PROJECT_DIR;
  if (!root) return null;
  const slug = root.replace(/[^A-Za-z0-9]/g, '-');
  return path.join(os.homedir(), '.claude', 'projects', slug);
}

const localDate = (ms) => {
  const d = new Date(ms);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};

/** Dated reports of this workflow in the repo: [{date, ts, path}]. The file's mtime gives the hour when it falls
 *  on the named day (the producing machine); otherwise the day's start counts (a pulled or checked-out file). */
function reportRuns(projectRoot, name) {
  const out = [];
  const add = (p, date) => {
    const start = Date.parse(`${date}T00:00:00`);
    if (Number.isNaN(start)) return;
    let ts = start;
    try { const m = fs.statSync(p).mtimeMs; if (m >= start && m < start + 86400000) ts = m; } catch (_) { return; }
    out.push({ date, ts, path: p });
  };
  const esc = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const scan = (dir, re) => {
    let names;
    try { names = fs.readdirSync(dir); } catch (_) { return; }
    for (const n of names) { const m = n.match(re); if (m) add(path.join(dir, n), m[1]); }
  };
  const root = projectRoot || '.';
  scan(path.join(root, 'docs', 'research', name), /-(\d{4}-\d{2}-\d{2})\.md$/);
  scan(path.join(root, 'docs', 'research'), new RegExp(`^${esc}-(\\d{4}-\\d{2}-\\d{2})$`));
  scan(path.join(root, 'docs', 'maintenance'), new RegExp(`^${esc}-(\\d{4}-\\d{2}-\\d{2})\\.md$`));
  return out;
}

/** A resume rewrites the record with the resumed part only; the earlier attempt's agents finished before it started. */
function wasResumed(agentDir, startTime) {
  if (typeof startTime !== 'number') return false;
  let names;
  try { names = fs.readdirSync(agentDir); } catch (_) { return false; }
  return names.some((n) => {
    if (!/^agent-.*\.jsonl$/.test(n)) return false;
    try { return fs.statSync(path.join(agentDir, n)).mtimeMs < startTime; } catch (_) { return false; }
  });
}

/** Newest run of this workflow name: completed records across all sessions, failed records whose report exists,
 *  and dated reports in the repo without a record here. tokens null = the cost is not in one record (a report only,
 *  or a resumed run) and the token floor does not apply. */
function newestCompletedRun(stateDir, name, projectRoot) {
  let best = null;
  const reports = reportRuns(projectRoot, name);
  let sessions;
  try { sessions = fs.readdirSync(stateDir, { withFileTypes: true }); } catch (_) { sessions = []; }
  for (const s of sessions) {
    if (!s.isDirectory()) continue;
    const wfDir = path.join(stateDir, s.name, 'workflows');
    let files;
    try { files = fs.readdirSync(wfDir); } catch (_) { continue; }
    for (const f of files) {
      if (!/^wf_.*\.json$/.test(f)) continue;
      const p = path.join(wfDir, f);
      let rec;
      try { rec = JSON.parse(fs.readFileSync(p, 'utf8')); } catch (_) { continue; }
      if (rec.workflowName !== name || (rec.status !== 'completed' && rec.status !== 'failed')) continue;
      let ts = Date.parse(rec.timestamp);
      if (Number.isNaN(ts)) { try { ts = fs.statSync(p).mtimeMs; } catch (_) { continue; } }
      let runDate = localDate(ts);
      try { const a = typeof rec.args === 'string' ? JSON.parse(rec.args) : rec.args; if (a && /^\d{4}-\d{2}-\d{2}$/.test(a.date)) runDate = a.date; } catch (_) { /* timestamp date */ }
      const report = reports.find((r) => r.date === runDate);
      if (rec.status === 'failed' && !report) continue;  // failed before its report: no run to reuse
      const agentDir = path.join(stateDir, s.name, 'subagents', 'workflows', f.replace(/\.json$/, ''));
      const resumed = wasResumed(agentDir, rec.startTime);
      if (!best || ts > best.ts) {
        best = { ts, path: p, status: rec.status, resumed, report: report ? report.path : null,
                 tokens: resumed ? null : (rec.totalTokens || 0),
                 journal: path.join(agentDir, 'journal.jsonl') };
      }
    }
  }
  // A report newer (by date) than every record: the run happened elsewhere, or its record is gone.
  for (const r of reports) {
    if (!best || r.date > localDate(best.ts)) best = { ts: r.ts, path: null, report: r.path, tokens: null };
  }
  return best;
}

let input = '';
process.stdin.on('data', (d) => (input += d));
process.stdin.on('end', () => {
  let data;
  try { data = JSON.parse(input); } catch (_) { return allow(); }
  const ti = data.tool_input || {};

  if (ti.resumeFromRunId) return allow();

  let script = ti.script || '';
  if (!script && ti.scriptPath) {
    try { script = fs.readFileSync(ti.scriptPath, 'utf8'); } catch (_) { /* name may still resolve */ }
  }
  if (/FRESHNESS-OK:/.test(script)) return allow();
  // A coherence-scan PARTIAL run is the decided way under the cadence (operator decision 2026-11-02, macOS
  // instance: "Teil-Lauf bei Bedarf") — it audits only the rule files changed since a date, three lenses.
  let wfArgs = ti.args;
  if (typeof wfArgs === 'string') { try { wfArgs = JSON.parse(wfArgs); } catch (_) { wfArgs = null; } }
  if (wfArgs && typeof wfArgs === 'object' && wfArgs.partial && typeof wfArgs.partial === 'object'
      && /^\d{4}-\d{2}-\d{2}$/.test(String(wfArgs.partial.since || ''))) return allow();

  const name = ti.name || metaName(script);
  if (!name) return allow();

  const projectRoot = process.env.CLAUDE_PROJECT_DIR || data.cwd || '.';
  const cfg = loadConfig(projectRoot);
  const wfCfg = cfg.workflows[name] || {};
  const thresholdDays = typeof wfCfg.thresholdDays === 'number' ? wfCfg.thresholdDays : cfg.thresholdDays;
  const minTokens = typeof wfCfg.minTokens === 'number' ? wfCfg.minTokens : cfg.minTokens;

  const stateDir = projectStateDir(data);
  if (!stateDir) return allow();
  const prior = newestCompletedRun(stateDir, name, projectRoot);
  if (!prior) return allow();

  const ageDays = (Date.now() - prior.ts) / 86400000;
  if (ageDays >= thresholdDays) return allow();
  if (prior.tokens !== null && prior.tokens < minTokens) return allow();

  const when = localDate(prior.ts);
  const how = !prior.path ? 'wrote its report (no run record on this machine)'
    : prior.status === 'failed' ? 'ended failed after writing its report'
    : prior.resumed ? 'completed after a resume' : 'completed';
  const cost = prior.tokens === null ? '' : `, ~${Math.round(prior.tokens / 1000)}k tokens`;
  const artifacts = (prior.path ? `   record:  ${prior.path}\n   journal: ${prior.journal}\n` : '') +
    (prior.report ? `   report:  ${prior.report}\n` : '');
  console.log(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'deny',
      permissionDecisionReason:
        `FRESHNESS GATE: "${name}" ${how} ${ageDays.toFixed(1)} days ago ` +
        `(threshold ${thresholdDays}d${cost}). ` +
        `The repeat-run rule (rules/intelligence.md) applies — in order:\n` +
        `1. READ the artifacts instead of regenerating them:\n` +
        artifacts +
        `2. If they answer the question: use them and declare "reused from ${when}".\n` +
        `3. Re-run only if you can name what the artifacts do NOT answer — relaunch ` +
        `with a script comment "// FRESHNESS-OK: <that question>" (resume via ` +
        `resumeFromRunId passes freely). A scheduled cadence belongs in ` +
        `.claude/rules/freshness-gate.json as a per-workflow threshold, not in a marker.`,
    },
  }));
  hookExit(0);
});
