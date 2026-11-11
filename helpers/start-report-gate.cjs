#!/usr/bin/env node
/**
 * PreToolUse hook (Bash): the start report comes first. In the FIRST turn of a session no call that acts outside
 * this machine (merge, push, post, comment, release) runs before the first reply, unless the operator's first
 * message orders work explicitly - then it runs at once and the start report rides with the first closing reply
 * (open-items-gate checks that).
 *
 * WHY (measured 2026-10-27 on the macOS instance): the operator opened with "status?"; the session start listed a
 * PR under a standing approval ("handle these, then report ... no question needed") and the AI merged it before any
 * reply. The operator: "I got no start report. I only asked for the current state and you just started a merge?"
 * Instance alpha 2026-10-27 .. 2026-11-10, evaluated over 168 sessions: 1 real catch, 5 false alarms in 2 sessions
 * (both causes fixed: a question-tool answer opens a turn, a message typed mid-turn is an order), no operator turn
 * spent; ported on the operator's decision of 2026-11-10.
 *
 * First turn = exactly one operator prompt in the transcript (user record, not a notification, skill text, peer
 * message or tool result) or question-tool answer, and the harness has not yet closed a turn (`system/turn_duration`,
 * written only after every Stop hook let the reply through); a message typed mid-turn opens no turn but its words
 * count. Windows review of #482: without the turn end, a session opened on one prompt and then driven by watcher
 * notifications stayed in its "first turn" for hours (18 outward calls over 2 h 24 min in one replayed session).
 * Bash and PowerShell are judged alike (the hook is wired on both).
 * Words: .claude/rules/start-report-patterns.json (template in templates/rules-instance/). Escape: a Bash command
 * carrying `# START-REPORT-OK: <quoted order>`. Every deny and every escape is logged to
 * .claude-state/start-report-gate.jsonl. Fails open on unreadable input or a missing pattern file.
 * CLI: node start-report-gate.cjs --replay <transcript.jsonl>...  -> one line per session that would have been
 * denied (history measurement; a question-tool answer ends the first turn there too).
 * Fixture: scripts/test-start-report-gate.sh.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { isNotification, isSkillExpansion, isPeerMessage, isTranscriptRecord, queuedHumanPrompt, isTurnEnd } =
  require('./turn-kind.cjs');
const { segments } = require('./shell-segments.cjs');

const ROOT = process.env.CLAUDE_PROJECT_DIR || path.join(__dirname, '..', '..');

function patterns() {
  try {
    const d = JSON.parse(fs.readFileSync(path.join(ROOT, '.claude', 'rules', 'start-report-patterns.json'), 'utf8'));
    return { order: d.order_patterns.map((p) => new RegExp(p, 'i')), effect: d.effect_patterns.map((p) => new RegExp(p, 'i')) };
  } catch (e) { return null; }
}

/** Operator text of a transcript record, or null. */
function promptText(d) {
  if (!d || d.type !== 'user' || !isTranscriptRecord(d) || isSkillExpansion(d) || isPeerMessage(d)) return null;
  const c = d.message && d.message.content;
  let text = typeof c === 'string' ? c : Array.isArray(c)
    ? c.filter((x) => x && x.type === 'text').map((x) => x.text).join('\n') : '';
  if (!text.trim() || isNotification(text)) return null;
  text = text.replace(/<system-reminder>[\s\S]*?<\/system-reminder>/g, '').trim();
  return text || null;
}

/**
 * The operator's answer in the question tool: a tool_result for an AskUserQuestion call this
 * transcript made. It opens a turn like a prompt (measured 2026-10-29: the start report stood, the
 * operator answered "Ja, alles autonom", and the gate still denied the push as "first turn").
 */
function questionAnswer(d, askIds) {
  if (!d || d.type !== 'user' || !Array.isArray(d.message && d.message.content)) return null;
  const r = d.message.content.find((x) => x && x.type === 'tool_result' && askIds.has(x.tool_use_id) && !x.is_error);
  return r ? '[question-tool answer]' : null;
}

/**
 * Prompts the operator typed while the first turn ran (queued commands with a human origin). They open
 * no turn, but they are the operator's words: an order typed mid-turn is an order (measured 2026-11-06:
 * "autonom abarbeiten" typed during the first turn, every later push and read with an effect word was
 * still denied as "the first message orders no work").
 */
function queuedPrompts(transcript) {
  const out = [];
  let lines = [];
  try { lines = fs.readFileSync(transcript, 'utf8').split('\n'); } catch (e) { return out; }
  for (const l of lines) {
    if (!l) continue;
    let d; try { d = JSON.parse(l); } catch (e) { continue; }
    const q = queuedHumanPrompt(d);
    if (q) out.push(q);
  }
  return out;
}

function prompts(transcript) {
  const out = [];
  out.ended = false;
  const askIds = new Set();
  let lines = [];
  try { lines = fs.readFileSync(transcript, 'utf8').split('\n'); } catch (e) { return null; }
  for (const l of lines) {
    if (!l) continue;
    let d; try { d = JSON.parse(l); } catch (e) { continue; }
    if (isTurnEnd(d)) { out.ended = true; continue; }
    if (d.type === 'assistant') {
      for (const c of ((d.message && d.message.content) || [])) {
        if (c && c.type === 'tool_use' && c.name === 'AskUserQuestion') askIds.add(c.id);
      }
      continue;
    }
    const t = promptText(d) || questionAnswer(d, askIds);
    if (t) out.push(t);
  }
  return out;
}

/**
 * A segment as the shell runs it: quoted strings and the trailing comment are data, not commands
 * (measured 2026-11-06: `grep -n "gh pr close" settings.json` and `git log -S"gh pr close"` were
 * denied as "this call changes something" — the effect word stood only inside the search pattern).
 * A segment that hands its quoted text to a shell (`bash -c`, `sh -c`, `eval`) keeps it.
 */
function runnable(seg) {
  const s = seg.replace(/(^|\s)#.*$/, '$1');
  if (/^\s*(?:\S+\/)?(?:bash|sh|zsh|eval)\b/.test(s)) return s;
  return s.replace(/"(?:[^"\\]|\\.)*"|'[^']*'/g, '""');
}

/** What the call changes, or null when it only reads. */
function effect(tool, input, pat) {
  if (tool === 'Bash' || tool === 'PowerShell') {
    const cmd = String(input.command || '');
    if (/\s--help\b/.test(cmd) && !/[;&|\n]/.test(cmd)) return null;
    const hit = segments(cmd).some((seg) => pat.effect.some((r) => r.test(runnable(seg))));
    return hit ? cmd.split('\n')[0].slice(0, 120) : null;
  }
  return null;
}

function log(entry) {
  try {
    fs.appendFileSync(process.env.START_REPORT_GATE_LOG || path.join(ROOT, '.claude-state', 'start-report-gate.jsonl'), JSON.stringify({ ts: new Date().toISOString(), ...entry }) + '\n');
  } catch (e) { /* measurement only */ }
}

function judge(input) {
  const pat = patterns();
  if (!pat) return null;
  const what = effect(input.tool_name || '', input.tool_input || {}, pat);
  if (!what) return null;
  const ps = prompts(input.transcript_path || '');
  if (!ps || ps.length !== 1 || ps.ended) return null;
  const first = ps[0];
  const said = [first, ...queuedPrompts(input.transcript_path || '')];
  if (said.some((t) => pat.order.some((r) => r.test(t)))) return null;
  const esc = /#\s*START-REPORT-OK:\s*(.+)/.exec(String((input.tool_input || {}).command || ''));
  // the escape names a quoted order, and the quote has to stand in the operator's own words (Windows review of #482)
  const squash = (x) => String(x || '').toLowerCase().replace(/\s+/g, ' ').trim();
  const quote = esc && squash(esc[1].replace(/^\s*["'„“”]|["'“”]\s*$/g, ''));
  if (esc && quote && said.some((t) => squash(t).includes(quote))) {
    log({ kind: 'escape', session: input.session_id, call: what, reason: esc[1], first }); return null;
  }
  log({ kind: 'deny', session: input.session_id, call: what, first });
  return `START-REPORT-GATE: first turn of the session, and the operator's first message ("${first.slice(0, 80)}") orders no ` +
    `work - this call changes something (${what}). Give the start report first (the operator's request answered, ` +
    'reporting duties, open items), then do the work in the next turn. Reading is free. If the first message does order this ' +
    'work, repeat with `# START-REPORT-OK: <the quoted order>` - the quote must stand in the operator\'s own words.' +
    (esc ? ` The quote "${esc[1].trim().slice(0, 60)}" is not in the operator's messages.` : '');
}

function replay(files) {
  const pat = patterns();
  if (!pat) { process.stdout.write('start-report-gate: no pattern file (.claude/rules/start-report-patterns.json) - nothing to replay\n'); return; }
  for (const f of files) {
    let lines = [];
    try { lines = fs.readFileSync(f, 'utf8').split('\n'); } catch (e) { continue; }
    let n = 0; let first = null; const hits = []; const askIds = new Set();
    for (const l of lines) {
      if (!l) continue;
      let d; try { d = JSON.parse(l); } catch (e) { continue; }
      if (isTurnEnd(d)) break; // the first turn ended (same rule as judge)
      if (d.type === 'assistant') {
        for (const c of ((d.message && d.message.content) || [])) if (c && c.type === 'tool_use' && c.name === 'AskUserQuestion') askIds.add(c.id);
      }
      const t = promptText(d) || questionAnswer(d, askIds);
      if (t) { n++; if (n === 1) first = t; if (n > 1) break; continue; }
      if (n !== 1 || d.type !== 'assistant') continue;
      for (const c of ((d.message && d.message.content) || [])) {
        if (c && c.type === 'tool_use') { const w = effect(c.name, c.input || {}, pat); if (w) hits.push(w); }
      }
    }
    if (first && hits.length && !pat.order.some((r) => r.test(first))) {
      process.stdout.write(JSON.stringify({ transcript: path.basename(f), first: first.slice(0, 80), calls: hits.length, call: hits[0] }) + '\n');
    }
  }
}

if (require.main === module) {
  if (process.argv[2] === '--replay') { replay(process.argv.slice(3)); process.exit(0); }
  let raw = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (c) => { raw += c; });
  process.stdin.on('end', () => {
    let reason = null;
    try { reason = judge(JSON.parse(raw)); } catch (e) { reason = null; }
    if (reason) {
      process.stdout.write(JSON.stringify({ hookSpecificOutput: {
        hookEventName: 'PreToolUse', permissionDecision: 'deny', permissionDecisionReason: reason } }));
    }
    process.exit(0);
  });
}

module.exports = { judge, promptText, effect };
