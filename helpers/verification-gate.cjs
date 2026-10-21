#!/usr/bin/env node
/**
 * Stop check (opt-in per instance): a reply that declares the work finished after code was
 * changed in the turn, while skill `verification-before-completion` was never loaded in the
 * session.
 *
 * WHY: the rules say "every code change -> skill verification-before-completion" and "before
 * reporting done, check whether ALL requirements are fulfilled" — and nothing carries it.
 * skill-gate cannot: it fires on a TOOL call, and "done" is a sentence, not a tool. Proposed by
 * the Windows instance 2026-10-19, agreed by the macOS instance the same day as opt-in per
 * instance (the lesson of core PR #22: no gate is switched on for every brain silently).
 *
 * OPT-IN: the dispatcher runs it only when the instance lists it in `.claude/rules/stop-checks.json`
 * (example entry: `_optional_checks` in the template). Done claims are the ONE definition in
 * done-claim.cjs (instance language: `done_claim_patterns` in `.claude/rules/watch-gate.json`).
 *
 * Fires when, in the running turn (since the operator's last message; harness notifications,
 * hook echoes and a skill's own text are no boundary):
 *   - an Edit/Write/MultiEdit/NotebookEdit touched a file that is not prose (.md/.txt/.rst), AND
 *   - the last reply text matches a done claim (quoted text and code stripped), AND
 *   - no Skill call and no Read of `.../skills/verification-before-completion/SKILL.md` in the
 *     whole session.
 * Blocks once per turn; a re-issue (stop_hook_active) or its own echo passes. Fails open on an
 * unreadable transcript. Fixture: scripts/test-verification-gate.sh.
 */
'use strict';
const fs = require('fs');
const { isNotification, isSkillExpansion, isTranscriptRecord } = require('./turn-kind.cjs');
const { doneClaimRegex } = require('./done-claim.cjs');
const { ownEcho, declare } = require('./stop-echo.cjs');

const SKILL = 'verification-before-completion';
const HOOK_ECHO = /^Stop hook feedback:/;
const EDIT_TOOLS = new Set(['Edit', 'Write', 'MultiEdit', 'NotebookEdit']);
const PROSE = /\.(md|markdown|mdx|txt|rst)$/i;
const TAIL_BYTES = 4 * 1024 * 1024;

function readTail(p) {
  const size = fs.statSync(p).size;
  const start = Math.max(0, size - TAIL_BYTES);
  const fd = fs.openSync(p, 'r');
  try {
    const buf = Buffer.alloc(size - start);
    fs.readSync(fd, buf, 0, buf.length, start);
    const lines = buf.toString('utf8').split('\n');
    if (start > 0) lines.shift();
    return lines;
  } finally { fs.closeSync(fd); }
}

function promptText(msg) {
  if (typeof msg.content === 'string') return msg.content;
  if (!Array.isArray(msg.content) || msg.content.some((b) => b && b.type === 'tool_result')) return null;
  return msg.content.filter((b) => b && b.type === 'text').map((b) => b.text).join('\n') || null;
}

function stripQuoted(text) {
  return String(text || '')
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/`[^`\n]*`/g, ' ')
    .replace(/„[^“”"\n]*[“”"]/g, ' ')
    .replace(/“[^”]*”/g, ' ')
    .replace(/"[^"\n]*"/g, ' ')
    .replace(/^\s*>.*$/gm, ' ');
}

function scan(tp, echo) {
  let loaded = false; let code = []; let lastText = ''; let fired = false;
  const tail = `/skills/${SKILL}/skill.md`;
  for (const line of readTail(tp)) {
    if (!line.trim()) continue;
    let d; try { d = JSON.parse(line); } catch (e) { continue; }
    const msg = d.message; if (!msg || !isTranscriptRecord(d)) continue;
    if (msg.role === 'user') {
      if (isSkillExpansion(d)) continue; // a loaded skill's text
      const t = promptText(msg);
      if (t === null) continue;
      if (HOOK_ECHO.test(t)) { if (echo.test(t)) fired = true; continue; }
      if (isNotification(t)) continue;
      code = []; lastText = ''; fired = false; // the operator opened a new turn
      continue;
    }
    if (msg.role !== 'assistant' || !Array.isArray(msg.content)) continue;
    const text = msg.content.filter((b) => b && b.type === 'text').map((b) => b.text).join('\n');
    if (text.trim()) lastText = text;
    for (const b of msg.content) {
      if (!b || b.type !== 'tool_use' || !b.input) continue;
      if (b.name === 'Skill' && String(b.input.skill || '').split(':').pop() === SKILL) loaded = true;
      if (b.name === 'Read' && String(b.input.file_path || '').replace(/\\/g, '/').toLowerCase().endsWith(tail)) loaded = true;
      const file = String(b.input.file_path || b.input.notebook_path || '');
      if (EDIT_TOOLS.has(b.name) && file && !PROSE.test(file)) code.push(file);
    }
  }
  return { loaded, code, lastText, fired };
}

let data = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { data += c; });
process.stdin.on('end', () => {
  let input = {};
  try { input = JSON.parse(data || '{}'); } catch (e) { process.exit(0); }
  if (input.stop_hook_active || !input.transcript_path) process.exit(0);
  const root = input.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  let s;
  try { s = scan(input.transcript_path, ownEcho(input, /VERIFICATION-GATE/)); } catch (e) { process.exit(0); }
  if (s.fired || s.loaded || s.code.length === 0) process.exit(0);
  const m = stripQuoted(s.lastText).match(doneClaimRegex(root));
  if (!m) process.exit(0);
  const files = [...new Set(s.code.map((f) => f.replace(/\\/g, '/').split('/').pop()))].slice(0, 5).join(', ');
  console.log(JSON.stringify(declare({
    decision: 'block',
    reason: `VERIFICATION-GATE: the reply declares the work finished ("${m[0]}") after code changed this turn ` +
      `(${files}), and skill ${SKILL} was not loaded in this session. Load it, run its checks, then report ` +
      '— or say in the reply why this change needs none.',
  }, input)));
  process.exit(0);
});
