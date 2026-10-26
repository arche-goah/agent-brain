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
const { isNotification, isPeerMessage, isTranscriptRecord } = require('./turn-kind.cjs');
const { declare } = require('./stop-echo.cjs');

const HOOK_ECHO = /^Stop hook feedback:/;
const TAIL_BYTES = 4 * 1024 * 1024;
const BUILTIN = [/\bfrom now on\b/i, /\bgoing forward\b/i, /\bin future,? i(?:'ll| will)\b/i,
  /\bi(?:'ll| will) always\b/i, /\bfrom here on\b/i, /\bhenceforth\b/i];
const FIRST = [/\b(i|we)\b/i, /\bi'(ll|m)\b/i];
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

/** This turn: [{kind:'text', text}] and [{kind:'write', file, text}] since the last operator message. */
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
      if (!isNotification(msg.content) && !isPeerMessage(d)) events.push({ boundary: true });
      continue;
    }
    if (msg.role !== 'assistant' || !Array.isArray(msg.content)) continue;
    for (const b of msg.content) {
      if (b.type === 'text' && b.text) events.push({ kind: 'text', text: b.text });
      if (b.type !== 'tool_use' || !b.input) continue;
      const file = String(b.input.file_path || '').replace(/\\/g, '/');
      if (!file) continue;
      let text = '';
      if (b.name === 'Edit') text = b.input.new_string || '';
      else if (b.name === 'Write') text = b.input.content || '';
      else if (b.name === 'MultiEdit') text = (b.input.edits || []).map((e) => e.new_string || '').join(' ');
      else continue;
      events.push({ kind: 'write', file, text });
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
  const out = [];
  for (const e of events.filter((x) => x.kind === 'text')) {
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

module.exports = { looseCommitments, MECH };

if (require.main === module) {
  let data = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (c) => { data += c; });
  process.stdin.on('end', () => {
    let input = {};
    try { input = JSON.parse(data); } catch (e) { return allow(); }
    if (!input.transcript_path) return allow();
    let loose = [];
    try {
      loose = looseCommitments(turnEvents(input.transcript_path), loadInstance(input.cwd || process.cwd()));
    } catch (e) { return allow(); }   // unreadable transcript never blocks
    if (!loose.length) return allow();
    console.log(JSON.stringify(declare({
      decision: 'block',
      reason: 'EMPTY PROMISE: a promise about future conduct without a mechanism written this turn:\n' +
        loose.slice(0, 5).map((s) => '  - ' + s).join('\n') +
        '\nBuild the carrier now (a gate, a script a hook runs, gate data, a CI step) — a rule text, memory or ' +
        'feedback entry does not carry it — or take the promise back and say what is not guaranteed.',
    }, input)));
    process.exit(0);
  });
  process.stdin.resume();
}
