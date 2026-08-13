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
 * Escapes (all deliberate, none silent):
 *  - `resumeFromRunId` set — resume IS the recommended cheap path, never gated;
 *  - `FRESHNESS-OK: <reason>` comment in the script — the relaunch names which
 *    question the existing artifacts do not answer;
 *  - prior run failed/killed, or below the token floor (cheap probes re-run freely).
 *
 * Core/instance split: this engine is generic; thresholds are instance DATA in
 *   <project>/.claude/rules/freshness-gate.json
 *   { "thresholdDays": 14, "minTokens": 50000,
 *     "workflows": { "<name>": { "thresholdDays": 6, "minTokens": 0 } } }
 * A scheduled cadence (e.g. a weekly scan) sets its per-workflow threshold below
 * the cadence instead of carrying a permanent marker. Missing/broken file =
 * defaults. Fail-open throughout: a gate that errors must never block work.
 */
const fs = require('fs');
const path = require('path');
const os = require('os');

const DEFAULT_THRESHOLD_DAYS = 14;
const DEFAULT_MIN_TOKENS = 50000;

function allow() { process.exit(0); }

function loadConfig(projectRoot) {
  const cfg = { thresholdDays: DEFAULT_THRESHOLD_DAYS, minTokens: DEFAULT_MIN_TOKENS, workflows: {} };
  try {
    const raw = JSON.parse(fs.readFileSync(
      path.join(projectRoot, '.claude', 'rules', 'freshness-gate.json'), 'utf8'));
    if (typeof raw.thresholdDays === 'number') cfg.thresholdDays = raw.thresholdDays;
    if (typeof raw.minTokens === 'number') cfg.minTokens = raw.minTokens;
    if (raw.workflows && typeof raw.workflows === 'object') cfg.workflows = raw.workflows;
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

/** Newest completed run record for this workflow name, across all sessions. */
function newestCompletedRun(stateDir, name) {
  let best = null;
  let sessions;
  try { sessions = fs.readdirSync(stateDir, { withFileTypes: true }); } catch (_) { return null; }
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
      if (rec.workflowName !== name || rec.status !== 'completed') continue;
      let ts = Date.parse(rec.timestamp);
      if (Number.isNaN(ts)) { try { ts = fs.statSync(p).mtimeMs; } catch (_) { continue; } }
      if (!best || ts > best.ts) {
        best = { ts, path: p, tokens: rec.totalTokens || 0,
                 journal: path.join(stateDir, s.name, 'subagents', 'workflows',
                                    f.replace(/\.json$/, ''), 'journal.jsonl') };
      }
    }
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

  const name = ti.name || metaName(script);
  if (!name) return allow();

  const projectRoot = process.env.CLAUDE_PROJECT_DIR || data.cwd || '.';
  const cfg = loadConfig(projectRoot);
  const wfCfg = cfg.workflows[name] || {};
  const thresholdDays = typeof wfCfg.thresholdDays === 'number' ? wfCfg.thresholdDays : cfg.thresholdDays;
  const minTokens = typeof wfCfg.minTokens === 'number' ? wfCfg.minTokens : cfg.minTokens;

  const stateDir = projectStateDir(data);
  if (!stateDir) return allow();
  const prior = newestCompletedRun(stateDir, name);
  if (!prior) return allow();

  const ageDays = (Date.now() - prior.ts) / 86400000;
  if (ageDays >= thresholdDays) return allow();
  if (prior.tokens < minTokens) return allow();

  const when = new Date(prior.ts).toISOString().slice(0, 10);
  console.log(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'deny',
      permissionDecisionReason:
        `FRESHNESS GATE: "${name}" completed ${ageDays.toFixed(1)} days ago ` +
        `(threshold ${thresholdDays}d, ~${Math.round(prior.tokens / 1000)}k tokens). ` +
        `The repeat-run rule (rules/intelligence.md) applies — in order:\n` +
        `1. READ the artifacts instead of regenerating them:\n` +
        `   record:  ${prior.path}\n` +
        `   journal: ${prior.journal}\n` +
        `2. If they answer the question: use them and declare "reused from ${when}".\n` +
        `3. Re-run only if you can name what the artifacts do NOT answer — relaunch ` +
        `with a script comment "// FRESHNESS-OK: <that question>" (resume via ` +
        `resumeFromRunId passes freely). A scheduled cadence belongs in ` +
        `.claude/rules/freshness-gate.json as a per-workflow threshold, not in a marker.`,
    },
  }));
  process.exit(0);
});
