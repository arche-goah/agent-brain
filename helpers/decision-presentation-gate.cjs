#!/usr/bin/env node
/**
 * Stop hook: at the right moment, the operator's open decisions go through the question tool.
 *
 * WHY (measured 2026-10-26 on the Windows instance): asked "is anything open for me?", the reply
 * listed four real operator decisions in prose, each with "recommendation: yes" and no question
 * mark, so stoppen-gate (which looks for a closing question) let it pass. The operator had to ask
 * again (translated): "then put the decisions to me clearly, interactively", and then ordered: the
 * core must make sure that real operator decisions are put as interactive questions, at the right
 * moment only, and never during an autonomous run.
 *
 * The right moment, in a turn that is NOT autonomous (autonomous-mode.cjs):
 *   - the operator's newest prompt asks what is open (built-in English words; the instance's own
 *     `ask_patterns` in .claude/rules/open-items.json, the same key open-items-gate reads), or
 *   - the operator's prompt before it was autonomous: the first turn after an autonomous run, when
 *     the questions the run collected are due.
 * Open decisions: entries `- [ ]` with `class: decision` in the registered ledgers
 * (.claude/rules/ledgers.json), plus questions in the question-gate register
 * (.claude-state/open-questions.json) with status deferred or unanswered.
 * Blocks when such decisions exist and the running turn called no AskUserQuestion. Each question
 * is to be re-measured before it is put (the question-gate's RECHECKED rule on the macOS side);
 * this hook only demands the tool, never the wording.
 * Output: {"decision":"block","reason":"... Missing: <titles>"}. Fails open on unreadable input.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { promptModes } = require('./autonomous-mode.cjs');
const { queuedHumanPrompt } = require('./turn-kind.cjs');

const ASK_BUILTIN = ['\\banything (still |else )?(open|left|pending)\\b', '\\bwhat is (still )?open\\b',
  '\\bopen (for|to) me\\b', '\\bdo you need (anything|something)\\b'];

function readJson(p) { try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch (e) { return null; } }

function askRx(root) {
  const list = [...ASK_BUILTIN];
  const cfg = readJson(path.join(root, '.claude', 'rules', 'open-items.json')) || {};
  for (const s of cfg.ask_patterns || []) { try { new RegExp(s); list.push(s); } catch (e) { /* skip */ } }
  return new RegExp(list.join('|'), 'iu');
}

/** Open `class: decision` entries of the registered ledgers, as short titles. */
function ledgerDecisions(root) {
  const cfg = readJson(path.join(root, '.claude', 'rules', 'ledgers.json')) || {};
  const out = [];
  for (const rel of cfg.ledgers || []) {
    let text;
    try { text = fs.readFileSync(path.join(root, rel), 'utf8'); } catch (e) { continue; }
    const lines = text.split(/\r?\n/);
    for (let i = 0; i < lines.length; i++) {
      const m = /^- \[ \] (.*)$/.exec(lines[i]);
      if (!m) continue;
      let j = i + 1;
      const block = [lines[i]];
      while (j < lines.length && lines[j].startsWith(' ')) block.push(lines[j++]);
      if (/\bclass:\s*`?decision\b/i.test(block.join('\n'))) out.push(m[1].replace(/\*\*/g, '').slice(0, 80));
    }
  }
  return out;
}

function registerDecisions(root) {
  const reg = readJson(path.join(root, '.claude-state', 'open-questions.json')) || {};
  return Object.values(reg).filter((q) => q && ['deferred', 'unanswered'].includes(q.status))
    .map((q) => String(q.q || '').slice(0, 80));
}

/** Did the running turn (after the newest operator prompt) call the question tool? */
function askedThisTurn(transcriptPath, lastPrompt) {
  let lines;
  try { lines = fs.readFileSync(transcriptPath, 'utf8').split('\n'); } catch (e) { return false; }
  let asked = false;
  for (let i = lines.length - 1; i >= 0; i--) {
    const l = lines[i];
    if (!l.trim()) continue;
    let d;
    try { d = JSON.parse(l); } catch (e) { continue; }
    const queued = queuedHumanPrompt(d); // the newest prompt may have been typed mid-turn
    if (queued && lastPrompt && queued.includes(lastPrompt.trim().slice(0, 60))) break;
    const msg = d.message;
    if (!msg) continue;
    if (msg.role === 'user' && lastPrompt) {
      const c = msg.content;
      const t = typeof c === 'string' ? c : Array.isArray(c) ? c.filter((b) => b && b.type === 'text').map((b) => b.text).join('\n') : '';
      if (t && t.includes(lastPrompt.trim().slice(0, 60))) break;
    }
    if (msg.role === 'assistant' && Array.isArray(msg.content)
      && msg.content.some((b) => b && b.type === 'tool_use' && b.name === 'AskUserQuestion')) asked = true;
  }
  return asked;
}

function judge(input) {
  const root = process.env.CLAUDE_PROJECT_DIR || input.cwd || process.cwd();
  const modes = promptModes(input.transcript_path || '', root);
  if (!modes.length) return null;
  const now = modes[modes.length - 1];
  if (now.autonomous) return null;
  const back = modes.length > 1 && modes[modes.length - 2].autonomous;
  const asks = askRx(root).test(now.text);
  if (!back && !asks) return null;
  const open = [...ledgerDecisions(root), ...registerDecisions(root)];
  if (!open.length) return null;
  if (askedThisTurn(input.transcript_path, now.text)) return null;
  const why = back ? 'this is the first turn after the autonomous run' : 'the operator asked what is open';
  return `DECISION-PRESENTATION: ${why}, and ${open.length} operator decision(s) are open - put them through the question ` +
    'tool (AskUserQuestion: one question each, recommended option first), each re-measured before it is asked; ' +
    `prose is not the way. Missing: ${open.slice(0, 4).join(' | ')}${open.length > 4 ? ` (+${open.length - 4} more)` : ''}`;
}

if (require.main === module) {
  let raw = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (c) => { raw += c; });
  process.stdin.on('end', () => {
    let input;
    try { input = JSON.parse(raw); } catch (e) { process.exit(0); }
    if (input.stop_hook_active) process.exit(0);
    let reason = null;
    try { reason = judge(input); } catch (e) { reason = null; }
    if (reason) console.log(JSON.stringify({ decision: 'block', reason }));
    process.exit(0);
  });
}

module.exports = { judge, ledgerDecisions, registerDecisions };
