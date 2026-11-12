#!/usr/bin/env node
/**
 * pause-audit.cjs — every pause between two turns, read back from the transcripts.
 *
 * WHY (operator order 2026-10-29, the macOS instance): every pause is to be found with its length and reason, so
 * one can check afterwards whether a stop was justified or an idle stretch arose. The transcripts already record
 * every turn end (the Stop hooks' `stop_hook_summary`) and every restart (the next prompt record) with timestamps,
 * so the measurement is a reader, not a recorder. Ported from an instance alpha after its evaluation (2026-11-10,
 * operator decision the same day), with two changes: the mode is only the one WRITTEN at the turn end
 * (helpers/mode-log.cjs) — the alpha recomputed older stops with today's word lists and rewrote the past —, and a
 * stated block is read with the idle gate's own END_LINE (the alpha's line-start-only pattern sorted 28 of 45
 * "suspect" pauses wrongly: `- BLOCKED:` and `**BLOCKED:**`).
 *
 * Per pause: session, stop/restart time, seconds, the written mode, the closing text (the stated reason), the tools
 * of the closing turn, what restarted it (operator, notification, wakeup, continuation), and a first sort — a
 * PROPOSAL for the review, never a verdict:
 *   interactive            written mode interactive: a turn end is the normal hand-over, not judged
 *   unknown                no mode written near the stop (before mode-log, or a stop it missed)
 *   confirmed-unnecessary  autonomous, and the operator's restart asks why it stopped
 *   stated-block           autonomous, the closing text carries a BLOCKED / POOL EMPTY / LIST EMPTY line
 *   suspect                autonomous, anything else — the review decides
 *
 * Usage: node scripts/pause-audit.cjs [--since YYYY-MM-DD] [--min-s N] [--out FILE] [FILE.jsonl ...]
 *   default: the transcripts of THIS brain (~/.claude/projects/<the brain dir, encoded>), pauses of 60 s and more,
 *   rows to stdout as JSON lines, a summary to stderr. Complaint words: English built-in, other languages in
 *   `.claude/rules/stop-patterns.json` key `pause_complaint_patterns`. Fixture: scripts/test-pause-audit.cjs.
 */
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');

const BRAIN = process.env.CLAUDE_PROJECT_DIR || process.cwd();
const { END_LINE } = require('../helpers/autonomous-idle-gate.cjs');

const COMPLAINT = (() => {
  const parts = ['why did you stop', 'why (are you|did you) (wait|paus)', 'what are you waiting for', 'stopped for nothing'];
  try {
    const d = JSON.parse(fs.readFileSync(path.join(BRAIN, '.claude', 'rules', 'stop-patterns.json'), 'utf8'));
    for (const x of d.pause_complaint_patterns || []) { try { new RegExp(x); parts.push(x); } catch (e) { /* skip */ } }
  } catch (e) { /* built-ins only */ }
  return new RegExp(parts.join('|'), 'i');
})();

function arg(name, dflt) {
  const i = process.argv.indexOf(name);
  return i > 0 ? process.argv[i + 1] : dflt;
}

function transcripts(since) {
  const files = process.argv.slice(2).filter((a, i, all) => a.endsWith('.jsonl') && !/^--/.test(all[i - 1] || ''));
  if (files.length) return files;
  // this brain's own transcripts only: Claude Code names the folder after the project path, every
  // character that is no letter or digit turned into '-'
  const dir = path.join(os.homedir(), '.claude', 'projects', path.resolve(BRAIN).replace(/[^A-Za-z0-9]/g, '-'));
  const out = [];
  let names = [];
  try { names = fs.readdirSync(dir); } catch (e) { return out; }
  for (const n of names) {
    if (!n.endsWith('.jsonl')) continue;
    const f = path.join(dir, n);
    if (since && fs.statSync(f).mtime < new Date(since)) continue;
    out.push(f);
  }
  return out;
}

function text(content) {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';
  return content.filter((b) => b && b.type === 'text').map((b) => b.text).join('\n');
}

/** A record that starts a turn: a user record that is no tool result and no meta record. */
function turnStart(d) {
  if (d.type !== 'user' || d.isMeta || d.isSidechain) return null;
  const m = d.message;
  if (!m || m.role !== 'user') return null;
  const c = m.content;
  if (Array.isArray(c) && c.some((b) => b && b.type === 'tool_result')) return null;
  const t = text(c).trim();
  if (!t || /^\s*Stop hook feedback:/.test(t)) return null;
  return t;
}

function restartKind(t) {
  if (/^<task-notification>/.test(t)) return 'notification';
  if (/^This session is being continued/.test(t)) return 'continuation';
  if (/<<autonomous-loop|^\s*\/loop\b/.test(t)) return 'wakeup';
  return 'operator';
}

// The mode as WRITTEN at the turn end (core mode-log.cjs, wired here 2026-11-02) beats the recomputation:
// recomputing with today's reader and word lists rewrote the past (pause register 2026-11-01 and 2026-11-02 -
// initial_mode autonomous turned 2026-10-20..25 autonomous). Records: {at, session, mode} per stop.
const MODE_LOG = process.env.PAUSE_AUDIT_MODE_LOG || path.join(BRAIN, '.claude-state', 'mode-log.jsonl');
const WRITTEN_WINDOW_MS = 10000;

function loadModeLog() {
  const by = new Map();
  // the rotated generation too: stop-dispatcher renames a full log to `<name>.1.jsonl` (one generation). Measured
  // 2026-11-10: after a rotation at 16:41 the current file held 7 lines of one session, and 846 of 847 pauses since
  // 2026-11-02 read as "no written mode" (the alpha recomputed them silently instead).
  let raw = '';
  for (const f of [MODE_LOG.replace(/\.jsonl$/, '.1.jsonl'), MODE_LOG]) {
    try { raw += fs.readFileSync(f, 'utf8') + '\n'; } catch (e) { /* missing generation */ }
  }
  if (!raw) return by;
  for (const line of raw.split('\n')) {
    let r; try { r = JSON.parse(line); } catch (e) { continue; }
    if (!r || !r.session || !r.at || !r.mode) continue;
    if (!by.has(r.session)) by.set(r.session, []);
    by.get(r.session).push({ ms: Date.parse(r.at), auto: r.mode === 'autonomous' });
  }
  return by;
}

/** The written mode of the stop at `ts` in `session`, or null when none was written near it. */
function writtenMode(log, session, ts) {
  const recs = log.get(session);
  if (!recs) return null;
  const at = Date.parse(ts);
  let best = null;
  for (const r of recs) {
    const d = Math.abs(r.ms - at);
    if (d <= WRITTEN_WINDOW_MS && (!best || d < best.d)) best = { d, auto: r.auto };
  }
  return best ? best.auto : null;
}

function audit(file, minS, modeLog = new Map()) {
  const session = path.basename(file, '.jsonl');
  let raw;
  try { raw = fs.readFileSync(file, 'utf8').split('\n'); } catch (e) { return []; }
  const recs = [];
  raw.forEach((line, i) => {
    if (!line) return;
    let d;
    try { d = JSON.parse(line); } catch (e) { return; }
    recs.push({ i, d });
  });
  const rows = [];
  let turn = { tools: [], text: '', start: null };
  let stop = null;
  for (const { i, d } of recs) {
    if (d.isSidechain) continue;
    const t = turnStart(d);
    if (t !== null) {
      if (stop && d.timestamp) {
        const s = (Date.parse(d.timestamp) - Date.parse(stop.ts)) / 1000;
        if (s >= minS) {
          const kind = restartKind(t);
          const written = writtenMode(modeLog, session, stop.ts);
          const auto = written;
          let sort = auto === null ? 'unknown' : 'interactive';
          if (auto) {
            if (kind === 'operator' && COMPLAINT.test(t)) sort = 'confirmed-unnecessary';
            else if (END_LINE.test(stop.text)) sort = 'stated-block';
            else sort = 'suspect';
          }
          rows.push({
            session: path.basename(file, '.jsonl').slice(0, 8), project: path.basename(path.dirname(file)),
            stop: stop.ts, restart: d.timestamp, seconds: Math.round(s), autonomous: auto,
            restart_kind: kind, restart_text: t.replace(/\s+/g, ' ').slice(0, 160),
            closing_text: stop.text.replace(/\s+/g, ' ').slice(-400), closing_tools: stop.tools.slice(-8),
            sort,
          });
        }
      }
      stop = null;
      turn = { tools: [], text: '' };
      continue;
    }
    if (d.type === 'assistant' && d.message && Array.isArray(d.message.content)) {
      for (const b of d.message.content) {
        if (b && b.type === 'tool_use') turn.tools.push(b.name);
        if (b && b.type === 'text' && b.text.trim()) turn.text = b.text;
      }
    }
    if (d.type === 'system' && d.subtype === 'stop_hook_summary' && !d.preventedContinuation) {
      stop = { i, ts: d.timestamp, text: turn.text, tools: [...turn.tools], cwd: d.cwd };
    }
  }
  return rows;
}

function main() {
  const since = arg('--since', null);
  const minS = Number(arg('--min-s', 60));
  const out = arg('--out', null);
  const rows = [];
  const modeLog = loadModeLog();
  for (const f of transcripts(since)) {
    for (const r of audit(f, minS, modeLog)) if (!since || r.stop >= since) rows.push(r);
  }
  rows.sort((a, b) => a.stop.localeCompare(b.stop));
  const body = rows.map((r) => JSON.stringify(r)).join('\n') + (rows.length ? '\n' : '');
  if (out) fs.writeFileSync(out, body); else process.stdout.write(body);
  const by = {};
  for (const r of rows) {
    by[r.sort] = by[r.sort] || { n: 0, s: 0 };
    by[r.sort].n += 1; by[r.sort].s += r.seconds;
  }
  const parts = Object.entries(by).map(([k, v]) => `${k} ${v.n} (${Math.round(v.s / 60)} min)`);
  process.stderr.write(`pause-audit: ${rows.length} pauses >= ${minS} s${since ? ` since ${since}` : ''} — ${parts.join(' · ') || 'none'}\n`);
}

if (require.main === module) main();
module.exports = { audit, restartKind, turnStart, loadModeLog };
