#!/usr/bin/env node
/**
 * Stop check: a promise about future conduct ("from now on I …", or the instance's own phrasing) in this turn's reply
 * needs a MECHANISM written in the same turn — or the turn does not end.
 *
 * Why (operator, 2026-10-26): "a rule in the protocol is no binding mechanic, we have known that for
 * months … a rule entered in the feedback amounts to an empty promise in the long run". Measured the
 * same day with scripts/commitments.py over 14 days of one brain: 17 promises, 2 carried by a
 * mechanism, 13 only by rule text / memory / feedback. commitments.py is a report at session close;
 * by then the turn that made the promise is long over. This check sits at the turn end.
 *
 * Carried = an Edit/Write/MultiEdit in THIS turn to a mechanism path (helpers/*.cjs|js|sh,
 * scripts/*.py|sh|js, hooks/, .claude/settings*.json, .claude/rules/*.json, mechanism-rules.json,
 * .github/workflows/) sharing at least two load-bearing words with the promise (the file name counts).
 * A write to rule text, memory or a feedback file does NOT carry — that is the class this check exists for.
 *
 * Phrasing: English built in; other languages from .claude/rules/commitments.json (the same instance
 * file scripts/commitments.py reads: patterns, first_person, stopwords). Quoted text is a mention, not
 * a promise. Only first-person sentences count.
 * Way out: build the mechanism in this turn, or take the promise back (say what is NOT guaranteed).
 * Wired in .claude/rules/stop-checks.json with "onReissue": "run", so a re-issue that repeats the
 * promise without a mechanism blocks again.
 */
const fs = require('fs');
const path = require('path');
const { isNotification, isAgentOrigin, isTranscriptRecord } = require('./turn-kind.cjs');
const { declare } = require('./stop-echo.cjs');

const HOOK_ECHO = /^Stop hook feedback:/;
const TAIL_BYTES = 4 * 1024 * 1024;
const BUILTIN = [/\bfrom now on\b/i, /\bgoing forward\b/i, /\bin future,? i(?:'ll| will)\b/i,
  /\bi(?:'ll| will) always\b/i, /\bfrom here on\b/i, /\bhenceforth\b/i];
const FIRST = [/\b(i|we)\b/i, /\bi'(ll|m)\b/i];
const RETRACT = [/\bi take (that|it|this|the promise|the statement) back\b/i, /\bis not guaranteed\b/i, /\bi withdraw (that|it|the promise)\b/i];
const STOP = new Set(['which', 'every', 'their', 'there', 'these', 'those', 'about', 'after', 'before', 'where',
  'would', 'should', 'could', 'other', 'being', 'doing', 'start', 'starts', 'always', 'future', 'going', 'forward']);
const MECH = /\/helpers\/[^/]+\.(?:c?js|mjs|sh)$|\/scripts\/[^/]+\.(?:py|sh|c?js|mjs|ps1)$|\/hooks\/|\/\.claude\/(?:settings(?:\.local)?\.json|rules\/[^/]+\.json)$|mechanism-rules\.json$|\/\.github\/workflows\//i;

function allow() { process.exit(0); }

function readTail(file) {
  const size = fs.statSync(file).size;
  const start = Math.max(0, size - TAIL_BYTES);
  const fd = fs.openSync(file, 'r');
  try {
    const buf = Buffer.alloc(size - start);
    fs.readSync(fd, buf, 0, buf.length, start);
    const lines = buf.toString('utf8').split('\n');
    if (start > 0) lines.shift();
    return lines;
  } finally { fs.closeSync(fd); }
}

const fold = (s) => s.toLowerCase().replace(/\u00e4/g, 'ae').replace(/\u00f6/g, 'oe').replace(/\u00fc/g, 'ue').replace(/\u00df/g, 'ss');
function words(text, stop) {
  return new Set((fold(text).match(/[a-z]{5,}/g) || []).filter((w) => !stop.has(w)));
}

/** Lines of `neu` that `old` did not have: an Edit repeats its context, and an old "never" in it is no new rule. */
function addedLines(old, neu) {
  const had = new Set(String(old || '').split('\n').map((l) => l.trim()));
  return String(neu || '').split('\n').filter((l) => !had.has(l.trim())).join('\n');
}

/** This turn: [{kind:'text', text}] and [{kind:'write', file, text, added}] since the last operator message. */
function turnEvents(transcriptPath) {
  const events = [];
  for (const line of readTail(transcriptPath)) {
    if (!line.trim()) continue;
    let d;
    try { d = JSON.parse(line); } catch (e) { continue; }
    const msg = d.message;
    if (!msg || !isTranscriptRecord(d)) continue;
    if (msg.role === 'user' && typeof msg.content === 'string') {
      if (HOOK_ECHO.test(msg.content)) continue;
      if (!isNotification(msg.content) && !isAgentOrigin(d)) events.push({ boundary: true });
      continue;
    }
    if (msg.role !== 'assistant' || !Array.isArray(msg.content)) continue;
    for (const b of msg.content) {
      if (b.type === 'text' && b.text) events.push({ kind: 'text', text: b.text });
      if (b.type !== 'tool_use' || !b.input) continue;
      const file = String(b.input.file_path || '').replace(/\\/g, '/');
      if (!file) continue;
      let text = '', added = '';
      if (b.name === 'Edit') { text = b.input.new_string || ''; added = addedLines(b.input.old_string, b.input.new_string); }
      else if (b.name === 'Write') { text = b.input.content || ''; added = text; }
      else if (b.name === 'MultiEdit') {
        text = (b.input.edits || []).map((e) => e.new_string || '').join(' ');
        added = (b.input.edits || []).map((e) => addedLines(e.old_string, e.new_string)).join('\n');
      } else continue;
      events.push({ kind: 'write', file, text, added });
    }
  }
  let last = -1;
  for (let i = events.length - 1; i >= 0; i--) if (events[i].boundary) { last = i; break; }
  return events.slice(last + 1);
}

function loadInstance(cwd) {
  try {
    return JSON.parse(fs.readFileSync(path.join(cwd, '.claude', 'rules', 'commitments.json'), 'utf8'));
  } catch (e) { return {}; }
}

/** The promises in `text` that no mechanism write of the turn carries. Exported for the fixture. */
function looseCommitments(events, inst) {
  const patterns = BUILTIN.concat((inst.patterns || []).map((p) => new RegExp(p, 'i')));
  const first = FIRST.concat((inst.first_person || []).map((p) => new RegExp(p, 'i')));
  const stop = new Set([...STOP, ...(inst.stopwords || []).map((s) => s.toLowerCase())]);
  const mech = events.filter((e) => e.kind === 'write' && MECH.test(e.file))
    .map((e) => words(e.text + ' ' + path.basename(e.file).replace(/[^A-Za-z]+/g, ' '), stop));
  // A later text of the same turn that takes the promise back clears what came before it — the
  // way out the block message names. Measured 2026-10-28: the retraction was written, and the gate
  // read the earlier sentence again on every stop, a loop.
  const retract = RETRACT.concat((inst.retract_patterns || []).map((p) => new RegExp(p, 'iu')));
  let out = [];
  for (const e of events.filter((x) => x.kind === 'text')) {
    if (retract.some((p) => p.test(e.text))) { out = []; continue; }
    for (const sent of e.text.split(/(?<=[.!?])\s+|\n+/)) {
      const bare = sent.replace(/„[^“”]*[“”]|"[^"]*"|`[^`]*`|'[^']{3,}'/g, ' ');
      if (!patterns.some((p) => p.test(bare)) || !first.some((p) => p.test(bare))) continue;
      const need = words(sent, stop);
      const carried = need.size && mech.some((w) => [...need].filter((x) => w.has(x)).length >= Math.min(2, need.size));
      if (!carried) out.push(sent.trim().slice(0, 160));
    }
  }
  return out;
}

// The write IS the promise (operator, 2026-10-28: "a note … is not enough, we need mechanically binding ways of
// working"; measured the same day: a rule went straight into memory, the reply carried no future word, this check
// stayed silent). A write to a prose file whose ADDED lines carry rule words, in a turn that writes no mechanism,
// is a promise without a carrier — unless the text names an existing mechanism file as its carrier.
// Replay of the instance alpha over one brain's history (393 transcripts): 568 such writes in 207 sessions.
const PROSE = [/\/\.claude\/projects\/[^/]+\/memory\/[^/]+\.md$/i, /\/\.claude\/rules\/[^/]+\.md$/i, /\/CLAUDE\.md$/, /\/AGENTS\.md$/];
const PROSE_EXEMPT = [/\/memory\/MEMORY\.md$/i, /\/docs\/memory-snapshot\//i, /\/SKILL\.md$/i];
const RULE_WORDS = [/\bnever\b/i, /\balways\b/i, /\bmust\b/i, /\bbefore every\b/i, /\bfrom now on\b/i];
const CARRIER_WORDS = ['Carrier', 'carried by'];

function carrierNamed(text, root, inst) {
  const label = CARRIER_WORDS.concat(inst.carrier_words || []).join('|');
  const line = new RegExp(`(?:${label})\\s*:?\\s*\`?([^\`\\s,;)]+)`, 'giu');
  let m;
  while ((m = line.exec(text))) {
    const p = m[1].replace(/^~(?=\/)/, require('os').homedir());
    const abs = path.isAbsolute(p) ? p : path.join(root, p);
    if (fs.existsSync(abs) && MECH.test('/' + abs.replace(/\\/g, '/'))) return true;
  }
  return false;
}

/** Prose writes of the turn that carry a rule and no mechanism: ["<file>: <line>"]. Exported for the fixture. */
function proseRules(events, inst, root) {
  const rx = (l) => (l || []).map((p) => new RegExp(p, 'iu'));
  const prose = PROSE.concat(rx(inst.prose_paths));
  const exempt = PROSE_EXEMPT.concat(rx(inst.exempt_paths));
  const ruleWords = RULE_WORDS.concat(rx(inst.rule_words));
  const writes = events.filter((e) => e.kind === 'write');
  const isProse = (f) => prose.some((p) => p.test(f));
  if (writes.some((e) => MECH.test(e.file) && !isProse(e.file))) return [];
  const out = [];
  for (const w of writes) {
    if (!isProse(w.file) || exempt.some((p) => p.test(w.file))) continue;
    const added = w.added === undefined ? w.text : w.added;
    const word = ruleWords.find((p) => p.test(added));
    if (!word || carrierNamed(added, root, inst)) continue;
    const line = added.split('\n').find((l) => word.test(l)) || '';
    out.push(path.basename(w.file) + ': ' + line.trim().slice(0, 120));
  }
  return out;
}

module.exports = { looseCommitments, proseRules, MECH };

if (require.main === module) {
  let data = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (c) => { data += c; });
  process.stdin.on('end', () => {
    let input = {};
    try { input = JSON.parse(data); } catch (e) { return allow(); }
    if (!input.transcript_path) return allow();
    let loose = [], prose = [];
    try {
      const root = input.cwd || process.cwd();
      const events = turnEvents(input.transcript_path), inst = loadInstance(root);
      loose = looseCommitments(events, inst);
      prose = proseRules(events, inst, root);
    } catch (e) { return allow(); }   // unreadable transcript never blocks
    if (!loose.length && !prose.length) return allow();
    console.log(JSON.stringify(declare({
      decision: 'block',
      reason: 'EMPTY PROMISE: conduct promised without a mechanism written this turn:\n' +
        loose.slice(0, 5).map((s) => '  - ' + s).join('\n') + (loose.length ? '\n' : '') +
        prose.slice(0, 5).map((s) => '  - rule written into prose: ' + s).join('\n') + (prose.length ? '\n' : '') +
        'Build the carrier now (a gate, a script a hook runs, gate data, a CI step) — a rule text, memory or ' +
        'feedback entry does not carry it; a written rule may name an existing mechanism file ("Carrier: <path>") — ' +
        'or take the promise back and say what is not guaranteed.',
    }, input)));
    process.exit(0);
  });
  process.stdin.resume();
}
