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
 *       "marker":  "CLASS-GATE",            // the check's id: log name, legacy echo token
 *       "cmd":     "core/helpers/class-gate.cjs",   // relative to the project root
 *       "mode":    "block" | "record",      // record = never blocks, writes a log
 *       "args":    ["--record"],            // optional argv for the child
 *       "extract": "Touched this turn:\\s*(.+)",    // optional capture from the block
 *       "template":"{1} -> class? register?",       // {1}.. = capture groups
 *       "basename": true,                   // optional: paths in {1} to basenames
 *       "onNotification": "skip",           // optional: sit out notification turns
 *       "onReissue": "run"                  // optional: also run on the re-issue pass
 *     }]
 *   }
 *
 * RE-ISSUE PASS (stop_hook_active). By default the dispatcher stays silent once a stop hook
 * has blocked in the turn — a re-issue passes. A check whose point is that a repetition must
 * NOT pass (stoppen-gate since 2026-10-15: an operator decision re-issued as closing prose
 * instead of through the question tool) opts in with `"onReissue": "run"`; only those checks
 * run then, and each judges the re-issue itself. A check may also answer without blocking but
 * with a `systemMessage` (a loud let-through); the dispatcher forwards it to the operator.
 *
 * Three properties that are easy to lose and were built in deliberately:
 *
 *  - COOLDOWNS KEEP WORKING. Every gate reads its own echo back out of the replayed
 *    feedback to know it just fired. Each check gets `stop_check: {label, marker}` in its
 *    payload; a gate that finds its echo by the label at the start of its line says so
 *    with `echo: "label"` in its block, and its line goes out without a token. Every
 *    other line keeps the marker in brackets — dropping it for a gate that still reads
 *    the token kills that gate's cooldown, the exact class of defect these gates exist
 *    to catch (helpers/stop-echo.cjs; operator 2026-10-10: no codes in the lines).
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
 * TURN KIND (2026-10-07). Not every turn answers the operator: a background task that
 * finishes, a watcher event, a CI verdict arrives as a user record of its own, and the
 * reply to it ends a turn like any other. Measured on the proving brain: 39 of 164 real
 * Stop-check firings (24 %) in 2026-09-07..10-06 landed on such a notification turn,
 * spread across five checks — so the cut belongs here, not in one gate. The dispatcher
 * reads which record OPENED the running turn and hands every check `turn_kind`
 * ("operator" | "notification" | "unknown") in its stdin payload. A check entry may say
 * `"onNotification": "skip"` to sit those turns out; without it every check runs as
 * before — the default changes nothing, and each switch is a measured, per-check
 * decision in the instance config.
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
const TAIL_BYTES = 4 * 1024 * 1024;
const HOOK_ECHO = /^\s*Stop hook feedback/;
// One definition of "notification record", shared with every gate's cooldown count.
const { isNotification } = require('./turn-kind.cjs');

function recordText(msg) {
  if (typeof msg.content === 'string') return msg.content;
  if (!Array.isArray(msg.content) || msg.content.some((b) => b.type === 'tool_result')) return null;
  const t = msg.content.filter((b) => b.type === 'text').map((b) => b.text).join('\n');
  return t || null;
}

/** Which record opened the running turn: the operator, or a harness notification. */
function turnKind(transcriptPath) {
  try {
    const size = fs.statSync(transcriptPath).size;
    const start = Math.max(0, size - TAIL_BYTES);
    const fd = fs.openSync(transcriptPath, 'r');
    const buf = Buffer.alloc(size - start);
    try { fs.readSync(fd, buf, 0, buf.length, start); } finally { fs.closeSync(fd); }
    let kind = 'unknown';
    for (const line of buf.toString('utf8').split('\n')) {
      if (!line.trim()) continue;
      let d;
      try { d = JSON.parse(line); } catch (e) { continue; }
      if (!d.message || d.message.role !== 'user') continue;
      const t = recordText(d.message);
      if (t === null || HOOK_ECHO.test(t)) continue;
      kind = isNotification(t) ? 'notification' : 'operator';
    }
    return kind;
  } catch (e) {
    return 'unknown';
  }
}

// LOOP BRAKE (operator 2026-10-31, question tool: "Ja, Bremse bauen"). A check that judges text the
// new reply cannot change (an earlier reply of the turn, a sentence the operator wrote) blocks every
// re-issue and the turn never ends. Measured over the macOS instance's transcripts: 27 runs of >= 3
// consecutive blocks of one check, the longest 33 (empty promise), 14 (clock), 11 (close loss).
// So: how many Stop feedbacks IN A ROW (no other string record between - an operator prompt, a
// notification or a scheduled prompt resets; tool work does not) carried this check's line.
// From the third block on, the check lets the turn end with a loud systemMessage instead.
const LOOP_LIMIT = 2;

function priorStreaks(transcriptPath, checks) {
  const streak = new Map();
  try {
    const size = fs.statSync(transcriptPath).size;
    const start = Math.max(0, size - TAIL_BYTES);
    const fd = fs.openSync(transcriptPath, 'r');
    const buf = Buffer.alloc(size - start);
    try { fs.readSync(fd, buf, 0, buf.length, start); } finally { fs.closeSync(fd); }
    const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const tests = checks.map((c) => ({
      c, re: new RegExp(`(?:^|\\n)(?:· )?${esc(c.label)}(?: —|\\s)|\\[${esc(c.marker)}\\]`, 'u'),
    }));
    for (const line of buf.toString('utf8').split('\n')) {
      if (!line.trim()) continue;
      let d;
      try { d = JSON.parse(line); } catch (e) { continue; }
      if (!d.message || d.message.role !== 'user') continue;
      const t = recordText(d.message);
      if (t === null) continue; // a tool result: work inside the turn, no reset
      if (!HOOK_ECHO.test(t)) { streak.clear(); continue; }
      for (const { c, re } of tests) {
        if (re.test(t)) streak.set(c.marker, (streak.get(c.marker) || 0) + 1);
        else streak.delete(c.marker);
      }
    }
  } catch (e) { /* unreadable transcript: no brake, the checks judge as before */ }
  return streak;
}

function recordLoop(r, n) {
  try {
    fs.mkdirSync(path.join(ROOT, '.claude-state'), { recursive: true });
    fs.appendFileSync(path.join(ROOT, '.claude-state', 'stop-loops.jsonl'), JSON.stringify({
      at: new Date().toISOString(), label: r.check.label, marker: r.check.marker, blocks: n + 1,
      reason: short(r.reason, 300),
    }) + '\n');
  } catch (e) { /* the systemMessage still names it */ }
}

// REQUIRED CHECKS REACH EVERY BRAIN (2026-10-26). The template reaches a brain once, at bootstrap — a
// check added to it later shipped with the plugin and ran nowhere (same class as hook-coverage.py). A
// template check marked `"required": true` therefore runs in every brain whose instance file lacks its
// marker. A brain switches one off only by name with a reason: `"disabled": {"<MARKER>": "<why>"}`.
const TEMPLATE = path.join(__dirname, '..', 'templates', 'rules-instance', 'stop-checks.json');

function requiredFromTemplate(instanceChecks, disabled) {
  let tpl;
  try { tpl = JSON.parse(fs.readFileSync(TEMPLATE, 'utf8')); } catch (e) { return []; }
  const have = new Set(instanceChecks.map((c) => c.marker));
  return (Array.isArray(tpl.checks) ? tpl.checks : [])
    .filter((c) => c.required === true && c.marker && !have.has(c.marker)
      && !(disabled && typeof disabled[c.marker] === 'string' && disabled[c.marker].trim()));
}

function loadConfig() {
  let cfg = {};
  try { cfg = JSON.parse(fs.readFileSync(CONFIG, 'utf8')); } catch (e) { cfg = {}; }
  const checks = Array.isArray(cfg.checks) ? cfg.checks : [];
  return {
    header: typeof cfg.header === 'string' ? cfg.header : DEFAULT_HEADER,
    checks: checks.concat(requiredFromTemplate(checks, cfg.disabled)),
  };
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
 * Size-based rotation, one generation: a log at or above the limit is renamed to
 * `<name>.1.jsonl` (replacing the older generation) and the append starts a fresh file.
 * Measured 2026-10-09 on the proving brain: one recorder log had grown to 539 KB with
 * nothing ever trimming it. Limit: `STOP_RECORD_MAX_BYTES` (default 512 KiB, 0 = off).
 */
const RECORD_MAX_BYTES = (() => {
  const n = Number(process.env.STOP_RECORD_MAX_BYTES);
  return Number.isFinite(n) && n >= 0 && process.env.STOP_RECORD_MAX_BYTES !== '' ? n : 512 * 1024;
})();
function rotate(file) {
  try {
    if (RECORD_MAX_BYTES > 0 && fs.statSync(file).size >= RECORD_MAX_BYTES) {
      fs.renameSync(file, file.replace(/\.jsonl$/, '.1.jsonl'));
    }
  } catch (e) { /* no file yet, or rotation failed: append as before */ }
}

/**
 * Append what a recording check found, one JSON object per line.
 *
 * `.claude-state/` is gitignored on purpose: this grows with every session, and the
 * conclusions belong in the invariant register, not in the raw log. It is bounded by
 * `rotate()` above — the newest generation plus one older stay on disk.
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
    rotate(file);
    fs.appendFileSync(file, `${lines}\n`);
  } catch (e) { /* recording must never break a turn */ }
}

function run(check, base) {
  // Each check learns its own label and marker, so it can find its echo without a token
  // in the operator's line (helpers/stop-echo.cjs).
  const payload = JSON.stringify({ ...base, stop_check: { label: check.label, marker: check.marker } });
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
          } else if (parsed.decision === 'block' && parsed.reason) {
            // A gate without a --record mode answers a recorder slot with a block. Dropping
            // it recorded nothing, ever: measured 2026-10-23, premise-gate ran as a recorder
            // in the template and no premise-gate.jsonl existed on any brain checked.
            record(check, [{ would_block: true, reason: short(parsed.reason, 300) }], payload);
          }
          return resolve(null); // a recorder never blocks, by construction
        }
        const message = typeof parsed.systemMessage === 'string' && parsed.systemMessage.trim()
          ? parsed.systemMessage.trim() : null;
        if (parsed.decision === 'block' && parsed.reason) {
          return resolve({ check, reason: parsed.reason, message, byLabel: parsed.echo === 'label' });
        }
        resolve(message ? { check, message } : null);
      });
    child.stdin.end(payload);
  });
}

process.stdin.on('end', async () => {
  let input = {};
  try { input = JSON.parse(data); } catch (e) { process.exit(0); }
  const cfg = loadConfig();
  // The re-issue pass runs only the checks that opted in (header, RE-ISSUE PASS).
  const reissue = !!input.stop_hook_active;
  const eligible = cfg.checks.filter((c) => !reissue || c.onReissue === 'run');
  if (eligible.length === 0) process.exit(0);

  const kind = input.transcript_path ? turnKind(input.transcript_path) : 'unknown';
  const payload = { ...input, turn_kind: kind };
  const due = eligible.filter((c) => !(kind === 'notification' && c.onNotification === 'skip'));
  const answered = (await Promise.all(due.map((c) => run(c, payload))))
    .filter(Boolean);
  // A let-through never comes back as hook feedback, so no cooldown reads it: the label
  // names the check, no token needed.
  let notes = answered.filter((r) => r.message).map((r) => `${r.check.label} — ${r.message}`);
  let results = answered.filter((r) => r.reason);
  // Loop brake: a check that blocked the last LOOP_LIMIT Stop passes in a row lets the turn end now.
  if (results.length && input.transcript_path) {
    const streaks = priorStreaks(input.transcript_path, results.map((r) => r.check));
    const braked = results.filter((r) => (streaks.get(r.check.marker) || 0) >= LOOP_LIMIT);
    for (const r of braked) {
      const n = streaks.get(r.check.marker);
      recordLoop(r, n);
      notes.push(`${r.check.label} — blocked ${n + 1} times in a row, the turn ends anyway (loop brake; .claude-state/stop-loops.jsonl)`);
    }
    results = results.filter((r) => !braked.includes(r));
  }
  if (results.length === 0) {
    if (notes.length) console.log(JSON.stringify({ systemMessage: notes.join('\n') }));
    process.exit(0);
  }

  // SHORT LINES, NOTHING SWALLOWED (2026-10-31, the operator: the stop hook "is really a background
  // process I would hide completely if I could - keep it as short and informative as possible").
  // The block reason is shown to the operator AND read by the model; it cannot be split. So every
  // finding is ONE line: the check's template, else its fixed `short` line, else the first sentence
  // of the gate's text cut to `maxLength`. Whatever a line cuts goes in full to a detail file the
  // model can read, named once at the end. Measured on the proving brain 2026-10-17..10-31: 478
  // stop feedbacks, 77 lines passed the gate's full English text through (a template whose extract
  // no longer matched, or none), median 595 characters for the worst check.
  const flat = (s) => s.split('\n').map((l) => l.trim()).filter(Boolean).join(' ');
  const cutFallback = (check, reason) => {
    if (typeof check.short === 'string' && check.short.trim()) return check.short.trim();
    const t = flat(reason);
    const first = (/^(.+?[.!?])(?:\s|$)/.exec(t) || [null, t])[1];
    return short(first, check.maxLength || 140);
  };
  const lines = results.map((r) => {
    const compressed = compress(r.check, r.reason);
    const text = compressed || cutFallback(r.check, r.reason);
    return { r, text, cut: !compressed && text !== flat(r.reason) };
  });
  let detail = '';
  if (lines.some((l) => l.cut)) {
    const rel = path.join('.claude-state', 'stop-detail.txt');
    try {
      fs.mkdirSync(path.join(ROOT, '.claude-state'), { recursive: true });
      fs.writeFileSync(path.join(ROOT, rel),
        lines.filter((l) => l.cut).map((l) => `${l.r.check.label} [${l.r.check.marker}]\n${l.r.reason.trim()}\n`).join('\n'));
      detail = `\nDetails: ${rel.split(path.sep).join('/')}`;
    } catch (e) {
      // Cannot write the detail file: never swallow, fall back to the full text.
      for (const l of lines) if (l.cut) { l.text = flat(l.r.reason); l.cut = false; }
    }
  }

  // The bracket stays only for a check that still finds its echo by the token.
  const tag = (r) => (r.byLabel ? '' : `   [${r.check.marker}]`);
  const width = Math.max(...results.map((r) => r.check.label.length));
  const header = cfg.header.trim() ? `${cfg.header.replace('{n}', String(results.length))}\n` : '';

  const reason = (results.length === 1
    ? `${lines[0].r.check.label} — ${lines[0].text}${tag(lines[0].r)}`
    : header + lines.map((l) => `· ${l.r.check.label.padEnd(width)} ${l.text}${tag(l.r)}`).join('\n'))
    + detail;

  console.log(JSON.stringify(notes.length
    ? { decision: 'block', reason, systemMessage: notes.join('\n') }
    : { decision: 'block', reason }));
  process.exit(0);
});
