#!/usr/bin/env node
/**
 * tokens-per-request — what one request of the operator costs in tokens, measured from the session transcripts.
 *
 * WHY: a change to the way of working (more checks, a register, more reflection per step) is paid in tokens per
 * request, and "it got more expensive" is a claim until it is counted. The transcripts hold the count: every model
 * call records its `usage`. transcript-latency.py measures seconds and characters per turn, run-price.py sums one
 * workflow run; neither says what a request costs. Ordered 2026-11-23 for an alpha of the working method: the
 * baseline has to be measured BEFORE the alpha is armed, or there is nothing to compare with.
 *
 * A REQUEST is everything between two prompts the operator typed (helpers/turn-kind.cjs `operatorPrompt` - the one
 * reader; notifications, hook echoes, peer messages, timer prompts and local commands open no request), in one
 * session. An answer the operator gives in the question tool is no typed prompt either, and neither is a refusal of
 * a question, with or without a message the operator wrote into it: both are a tool result, they stay inside the
 * request that asked, so a request with questions costs what it took to settle them (Windows review of #651,
 * 2026-11-24: on one workstation in November 58 such answers stood against 84 typed prompts - counted as requests of
 * their own, the cost per request would have dropped by about 40 % without anything getting cheaper).
 * On purpose the OPPOSITE of turn-kind.cjs `questionAnswers()`, which takes the same answer as an operator word that
 * ends a gate's turn window: a gate asks "has the operator spoken since?", this script asks "what did the request
 * cost?". Do not unify them; the fixture holds both readings (test-tokens-per-request.cjs, "question tool").
 * Its tokens are the usage of every model call in that span, each message id counted once (a call is
 * written as several records with the same id), plus the calls of the sub-agents the session started in that span
 * (`<session>/subagents/*.jsonl`, assigned by timestamp). Headless calls (`sdk-cli`) are no session.
 *
 * Four numbers per call, kept apart because they cost differently: `in` (fresh input), `cache_write`
 * (cache_creation_input_tokens), `cache_read`, `out`. `spent` = in + cache_write + out, the sum run-price.py uses
 * for a workflow run, so the two compare; `total` adds the cache reads (every call re-reads the context it has, so
 * a long request reads its own history many times - large, cheap, and the first number to move when requests get
 * longer). No price is computed: prices change, the four counts do not.
 * NOT the same number as `subagent_tokens` in a task notification: measured 2026-11-23 on ten sub-agents of one
 * session, that figure equalled the context of the agent's LAST call (10 of 10 exact), not what the agent used -
 * their sum was 3.49M, the agents' `spent` 4.22M, their `total` 49.9M.
 *
 * Usage: tokens-per-request.cjs [--dir <transcripts>] [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--by week|day] [--json]
 *   --dir   default: this project's transcript folder (turn-kind.cjs `projectTranscriptDir` of CLAUDE_PROJECT_DIR or cwd)
 * Exit 0 = report printed, 2 = no transcript folder.
 * Limits: a request that spans a session resume is cut at the file; a sub-agent call outside every request span of
 * its session (before the first typed prompt) is counted to no request and reported as `unassigned`.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const tk = require('../helpers/turn-kind.cjs');

const KEYS = ['in', 'cache_write', 'cache_read', 'out'];
const zero = () => ({ in: 0, cache_write: 0, cache_read: 0, out: 0 });
const of = (u) => ({ in: +u.input_tokens || 0, cache_write: +u.cache_creation_input_tokens || 0, cache_read: +u.cache_read_input_tokens || 0, out: +u.output_tokens || 0 });
const add = (a, b) => { for (const k of KEYS) a[k] += b[k]; return a; };
const total = (t) => KEYS.reduce((s, k) => s + t[k], 0);
const spent = (t) => t.in + t.cache_write + t.out;   // without cache reads: the sum run-price.py and a run record use

function records(file) {
  const out = [];
  let text;
  try { text = fs.readFileSync(file, 'utf8'); } catch (e) { return out; }
  for (const line of text.split('\n')) {
    if (!line) continue;
    try { out.push(JSON.parse(line)); } catch (e) { /* a cut line */ }
  }
  return out;
}

/** The usage of every model call in a record list: message id -> { ts, usage } (the record with the most output wins). */
function calls(recs) {
  const by = new Map();
  for (const d of recs) {
    const m = d && d.type === 'assistant' && d.message;
    if (!m || !m.usage || !d.timestamp) continue;
    const id = m.id || d.uuid || `${d.timestamp}`;
    const u = of(m.usage);
    const old = by.get(id);
    if (!old || u.out >= old.usage.out) by.set(id, { ts: d.timestamp, usage: u });
  }
  return [...by.values()];
}

function opensRequest(d) {
  const t = tk.operatorPrompt(d);
  if (!t) return false;
  const w = tk.operatorWords(t).trim();
  return Boolean(w) && !tk.isNotification(w) && !/^<(?:command-|local-command|system-reminder|task-notification)/.test(w) && !/^\[Request interrupted/.test(w);
}

/** The requests of one session file: [{ start, own, agents, calls, agent_calls }], and the sub-agent tokens no request holds. */
function requests(file) {
  const recs = records(file);
  const reqs = [];
  let cur = null;
  const ids = new Map();   // message id -> index of the request that holds it (a call belongs to the request it started in)
  for (const d of recs) {
    if (opensRequest(d)) { cur = { start: d.timestamp || '', own: zero(), agents: zero(), calls: 0, agent_calls: 0, _m: new Map() }; reqs.push(cur); continue; }
    const m = d && d.type === 'assistant' && d.message;
    if (!cur || !m || !m.usage) continue;
    const id = m.id || d.uuid || `${d.timestamp}`;
    const holder = ids.has(id) ? reqs[ids.get(id)] : cur;
    if (!ids.has(id)) ids.set(id, reqs.length - 1);
    const u = of(m.usage);
    const old = holder._m.get(id);
    if (!old || u.out >= old.out) holder._m.set(id, u);
  }
  for (const r of reqs) { for (const u of r._m.values()) add(r.own, u); r.calls = r._m.size; delete r._m; }
  const unassigned = zero();
  const subDir = path.join(path.dirname(file), path.basename(file, '.jsonl'), 'subagents');
  let subs = [];
  try { subs = fs.readdirSync(subDir).filter((n) => n.endsWith('.jsonl')).map((n) => path.join(subDir, n)); } catch (e) { /* no sub-agents */ }
  for (const s of subs) {
    for (const c of calls(records(s))) {
      let holder = null;
      for (const r of reqs) { if (r.start && r.start <= c.ts) holder = r; else if (r.start > c.ts) break; }
      if (holder) { add(holder.agents, c.usage); holder.agent_calls++; } else add(unassigned, c.usage);
    }
  }
  return { reqs, unassigned };
}

const med = (xs) => { const s = [...xs].sort((a, b) => a - b); return s.length ? s[Math.floor(s.length / 2)] : 0; };
const p90 = (xs) => { const s = [...xs].sort((a, b) => a - b); return s.length ? s[Math.min(Math.floor(s.length * 0.9), s.length - 1)] : 0; };

function isoWeek(day) {   // "2026-11-23" -> "2026-W48"
  const d = new Date(day + 'T00:00:00Z');
  const n = (d.getUTCDay() + 6) % 7;
  d.setUTCDate(d.getUTCDate() - n + 3);
  const y = d.getUTCFullYear();
  const w = 1 + Math.round(((d - Date.UTC(y, 0, 4)) / 86400000 - 3 + ((new Date(Date.UTC(y, 0, 4)).getUTCDay() + 6) % 7)) / 7);
  return `${y}-W${String(w).padStart(2, '0')}`;
}

function measure(dir, since, until, by) {
  const buckets = new Map();
  const unassigned = zero();
  let sessions = 0;
  for (const n of fs.readdirSync(dir).filter((f) => f.endsWith('.jsonl')).sort()) {
    const file = path.join(dir, n);
    if (tk.isHeadlessTranscript(file)) continue;
    const { reqs, unassigned: un } = requests(file);
    if (reqs.length) sessions++;
    add(unassigned, un);
    for (const r of reqs) {
      const day = String(r.start).slice(0, 10);
      if (!day || day < since || day > until) continue;
      const key = by === 'day' ? day : isoWeek(day);
      if (!buckets.has(key)) buckets.set(key, []);
      buckets.get(key).push(r);
    }
  }
  const rows = {};
  for (const key of [...buckets.keys()].sort()) {
    const rs = buckets.get(key);
    const all = rs.map((r) => total(r.own) + total(r.agents));
    const sp = rs.map((r) => spent(r.own) + spent(r.agents));
    rows[key] = {
      requests: rs.length,
      med_spent: med(sp), p90_spent: p90(sp), sum_spent: sp.reduce((x, y) => x + y, 0),
      med_total: med(all), p90_total: p90(all),
      med_out: med(rs.map((r) => r.own.out)), p90_out: p90(rs.map((r) => r.own.out)),
      med_fresh_in: med(rs.map((r) => r.own.in + r.own.cache_write)),
      med_cache_read: med(rs.map((r) => r.own.cache_read)),
      med_calls: med(rs.map((r) => r.calls)),
      with_agents: rs.filter((r) => r.agent_calls).length,
      sum_own: total(rs.reduce((a, r) => add(a, r.own), zero())),
      sum_agents: total(rs.reduce((a, r) => add(a, r.agents), zero())),
    };
  }
  return { by, sessions, rows, unassigned_agent_tokens: total(unassigned) };
}

function main(argv) {
  const arg = (name, dflt) => { const i = argv.indexOf(name); return i >= 0 && argv[i + 1] ? argv[i + 1] : dflt; };
  const dir = arg('--dir', tk.projectTranscriptDir(process.env.CLAUDE_PROJECT_DIR || process.cwd()));
  if (!fs.existsSync(dir)) { console.error(`tokens-per-request: no transcript folder: ${dir.split(path.sep).join('/')}`); return 2; }
  const rep = measure(dir, arg('--since', '0000-00-00'), arg('--until', '9999-99-99'), arg('--by', 'week') === 'day' ? 'day' : 'week');
  if (argv.includes('--json')) { process.stdout.write(JSON.stringify(rep, null, 1) + '\n'); return 0; }
  const k = (n) => (n >= 1e6 ? (n / 1e6).toFixed(2) + 'M' : n >= 1e3 ? Math.round(n / 1e3) + 'k' : String(n));
  console.log(`== tokens per operator request, per ${rep.by} (${rep.sessions} sessions) ==`);
  console.log(['period'.padEnd(11), 'requests', 'med spent', 'p90 spent', 'sum spent', 'med total', 'p90 total', 'med out', 'p90 out', 'med fresh-in', 'med cache-read', 'med calls', 'with agents', 'sum own', 'sum agents'].join('  '));
  for (const [key, r] of Object.entries(rep.rows))
    console.log([key.padEnd(11), String(r.requests).padStart(8), k(r.med_spent).padStart(9), k(r.p90_spent).padStart(9), k(r.sum_spent).padStart(9), k(r.med_total).padStart(9), k(r.p90_total).padStart(9), k(r.med_out).padStart(7), k(r.p90_out).padStart(7),
      k(r.med_fresh_in).padStart(12), k(r.med_cache_read).padStart(14), String(r.med_calls).padStart(9), String(r.with_agents).padStart(11), k(r.sum_own).padStart(7), k(r.sum_agents).padStart(10)].join('  '));
  console.log(`sub-agent tokens outside every request span: ${k(rep.unassigned_agent_tokens)}`);
  return 0;
}

if (require.main === module) process.exitCode = main(process.argv.slice(2));
module.exports = { requests, measure, isoWeek };
