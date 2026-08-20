#!/usr/bin/env node
/**
 * ONE Stop hook that runs the others and reports their findings TOGETHER.
 *
 * Why (operator, 2026-08-20): seven Stop hooks each wrote their own block, so a turn
 * that tripped three of them buried the answer under ~20 lines of machine text in three
 * separate slabs. The rounds do not change — the gates fire in parallel and their
 * feedback arrives bundled, so it was one re-issue before and it is one now. What
 * changes is what the operator has to read.
 *
 * Each check keeps its own file, its own detection and its own fixtures. This
 * dispatcher feeds every one of them the SAME stdin payload, collects whoever blocks,
 * and compresses each block into one line. The long form of a rule belongs in the hook
 * header and the rule files, not in every message.
 *
 * WHICH checks run is INSTANCE DATA, never code: `.claude/rules/stop-checks.json`.
 * That file is also where the operator's language lives — labels, the header, and the
 * per-check phrasing. The engine itself carries no wording beyond an English fallback,
 * which is what lets the same file serve a brain that speaks something else.
 *
 * Config shape (array under "checks", first match wins, order = display order):
 *   {
 *     "header": "STOP-CHECKS ({n})",        // optional, only used for 2+ findings
 *     "checks": [{
 *       "label":   "CLASS",                 // what the operator reads
 *       "marker":  "CLASS-GATE",            // the check's own OWN_ECHO token
 *       "cmd":     "core/helpers/class-gate.cjs",   // relative to the project root
 *       "mode":    "block" | "record",      // record = never blocks, writes a log
 *       "args":    ["--record"],            // optional argv for the child
 *       "extract": "Touched this turn:\\s*(.+)",    // optional capture from the block
 *       "template":"{1} -> class? register?",       // {1}.. = capture groups
 *       "basename": true                    // optional: paths in {1} to basenames
 *     }]
 *   }
 *
 * Three properties that are easy to lose and were built in deliberately:
 *
 *  - COOLDOWNS KEEP WORKING. Every gate reads its own marker back out of the replayed
 *    feedback to know it just fired, so each compressed line carries that marker in
 *    brackets. Drop it and every cooldown dies at once — the exact class of defect
 *    these gates exist to catch.
 *  - NOTHING IS SWALLOWED. A block whose `extract` does not match is passed through in
 *    full. A compressor that silently drops a finding is worse than the noise it saves.
 *  - NO FRAME AROUND A SINGLE FINDING. The harness already prints "Ran 1 stop hook"
 *    above; a header, a counter and a closing instruction around one line of content
 *    are three lines of overhead.
 *
 * A check in mode "record" never blocks: it appends what it found to
 * `.claude-state/<marker>.jsonl` (gitignored — a measurement series is not
 * documentation) for a report tool to read back. Switching a noisy-but-usually-right
 * check from blocking to recording is a one-word change in the config.
 *
 * Fails open by design: a broken dispatcher silently disables every check at once, so
 * its fixture run (`scripts/test-stop-dispatcher.sh`) is the only proof they still
 * fire and belongs in the recurring audit, not in someone's memory.
 */
const { execFile } = require('child_process');
const fs = require('fs');
const path = require('path');

let data = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { data += c; });

const ROOT = process.env.CLAUDE_PROJECT_DIR || process.cwd();
const CONFIG = path.join(ROOT, '.claude', 'rules', 'stop-checks.json');
const DEFAULT_HEADER = 'STOP-CHECKS ({n})';

function loadConfig() {
  try {
    const cfg = JSON.parse(fs.readFileSync(CONFIG, 'utf8'));
    return {
      header: typeof cfg.header === 'string' ? cfg.header : DEFAULT_HEADER,
      checks: Array.isArray(cfg.checks) ? cfg.checks : [],
    };
  } catch (e) {
    return { header: DEFAULT_HEADER, checks: [] };
  }
}

function short(s, n) {
  const t = String(s).trim();
  return t.length > n ? `${t.slice(0, n - 1)}…` : t;
}

/** One line out of a block: capture, optionally shorten paths, fill the template. */
function compress(check, reason) {
  if (!check.extract || !check.template) return null;
  let m;
  try { m = new RegExp(check.extract, 'u').exec(reason); } catch (e) { return null; }
  if (!m) return null;
  return check.template.replace(/\{(\d+)\}/g, (_, i) => {
    let v = m[Number(i)] || '';
    if (check.basename) {
      v = v.split(',').map((f) => path.basename(f.trim())).join(', ');
    }
    return short(v, check.maxLength || 70);
  });
}

/**
 * Append what a recording check found, one JSON object per line.
 *
 * `.claude-state/` is gitignored on purpose: this grows with every session, and the
 * conclusions belong in the invariant register, not in the raw log.
 */
function record(check, items, payload) {
  try {
    const input = JSON.parse(payload);
    const dir = path.join(ROOT, '.claude-state');
    fs.mkdirSync(dir, { recursive: true });
    const session = path.basename(input.transcript_path || 'unknown', '.jsonl');
    const stamp = new Date().toISOString();
    const file = path.join(dir, `${check.marker.toLowerCase()}.jsonl`);
    const lines = items.map((it) => JSON.stringify({
      at: stamp, session, check: check.marker, ...it,
    })).join('\n');
    fs.appendFileSync(file, `${lines}\n`);
  } catch (e) { /* recording must never break a turn */ }
}

function run(check, payload) {
  return new Promise((resolve) => {
    const cmd = path.isAbsolute(check.cmd) ? check.cmd : path.join(ROOT, check.cmd);
    if (!fs.existsSync(cmd)) return resolve(null);
    const child = execFile('node', [cmd, ...(check.args || [])], { timeout: 10000 },
      (err, stdout) => {
        let parsed = {};
        try { parsed = JSON.parse(String(stdout || '').trim() || '{}'); }
        catch (e) { /* a check that prints nothing has nothing to say */ }
        if (check.mode === 'record') {
          if (Array.isArray(parsed.record) && parsed.record.length) {
            record(check, parsed.record, payload);
          }
          return resolve(null); // a recorder never blocks, by construction
        }
        resolve(parsed.decision === 'block' && parsed.reason
          ? { check, reason: parsed.reason } : null);
      });
    child.stdin.end(payload);
  });
}

process.stdin.on('end', async () => {
  let input = {};
  try { input = JSON.parse(data); } catch (e) { process.exit(0); }
  if (input.stop_hook_active) process.exit(0);

  const cfg = loadConfig();
  if (cfg.checks.length === 0) process.exit(0);

  const results = (await Promise.all(cfg.checks.map((c) => run(c, data))))
    .filter(Boolean);
  if (results.length === 0) process.exit(0);

  const body = ({ check, reason }) => compress(check, reason)
    // No match => the full original text, never a swallowed finding.
    || reason.split('\n').filter((l) => l.trim()).join(' ').trim();

  const label = (r) => `${r.check.label} — ${body(r)}   [${r.check.marker}]`;
  const width = Math.max(...results.map((r) => r.check.label.length));

  const reason = results.length === 1
    ? label(results[0])
    : `${cfg.header.replace('{n}', String(results.length))}\n`
      + results.map((r) => `· ${r.check.label.padEnd(width)} ${body(r)}`
        + `   [${r.check.marker}]`).join('\n');

  console.log(JSON.stringify({ decision: 'block', reason }));
  process.exit(0);
});
