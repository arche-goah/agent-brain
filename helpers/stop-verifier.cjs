#!/usr/bin/env node
/**
 * Stop Hook: checks for genuine incomplete-work markers in the code THIS TURN wrote.
 *
 * Version 2 (2026-08-19). Version 1 read the git working tree (`git diff HEAD` plus
 * untracked files) and thereby measured HISTORY, not the turn: it flagged leftovers
 * from days ago and stayed blind to work already committed within the turn — false
 * positive and false negative at once. The same construction was measured failing
 * in a sibling gate on 2026-08-06 (a stale artifact from five days earlier blocked
 * an unrelated turn); this file was the second instance of that class.
 *
 * The object the gate wants is "what did THIS turn add", and that is in the
 * transcript: the window since the last real operator message, and inside it the
 * text the edit tools actually wrote (Edit.new_string, Write.content,
 * MultiEdit.edits[].new_string, NotebookEdit.new_source). Scanning the written
 * text instead of the file also means pre-existing markers in a touched file
 * never block — only markers this turn ADDED do.
 *
 * Deliberately kept from version 1:
 *   - doc files (*.md, *.txt, ...) are ignored — intentional notes don't block,
 *   - never blocks when the transcript is unreadable (a broken gate must fail open),
 *   - marker words are assembled from fragments so this file never contains the
 *     literal tokens itself.
 * Known limit, deliberate: files written via Bash (script, redirect) are invisible
 * here — the alternative would be the working tree again, which is the defect.

 * INPUT IS READ TO ITS END, never on a timer. Until 2026-08-20 this ran in a
 * setTimeout(..., 400): if the timer fires before the first data event the buffer is
 * empty, JSON.parse throws, and the hook silently allows. Measured on a sibling hook
 * with 0 ms — same input, same file, once blocking and once completely silent. 400 ms
 * mitigates that, it does not promise it, and a gate that fails open at random is
 * indistinguishable from one that agrees.
 */
const fs = require('fs');

let data = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { data += c; });

// For Stop hooks there is no "allow" decision — emitting no decision permits the stop.
function allow() { process.exit(0); }

// The harness replays a blocked turn's feedback as an operator message. It must not
// end the turn window, or the window would be empty after the first block.
const HOOK_ECHO = /^Stop hook feedback:/;

const TAIL_BYTES = 4 * 1024 * 1024; // a turn fits in this by orders of magnitude

function readTail(file) {
  const size = fs.statSync(file).size;
  const start = Math.max(0, size - TAIL_BYTES);
  const fd = fs.openSync(file, 'r');
  try {
    const buf = Buffer.alloc(size - start);
    fs.readSync(fd, buf, 0, buf.length, start);
    const lines = buf.toString('utf8').split('\n');
    if (start > 0) lines.shift(); // drop the cut-off first line
    return lines;
  } finally {
    fs.closeSync(fd);
  }
}

/** Text written by edit tools in the current turn, as [{file, text}]. */
function writtenThisTurn(transcriptPath) {
  const lines = readTail(transcriptPath);
  const events = [];
  for (const line of lines) {
    if (!line.trim()) continue;
    let d;
    try { d = JSON.parse(line); } catch (e) { continue; }
    const msg = d.message;
    if (!msg) continue;
    if (msg.role === 'user' && typeof msg.content === 'string') {
      if (HOOK_ECHO.test(msg.content)) continue;
      events.push({ boundary: true });
      continue;
    }
    if (msg.role === 'assistant' && Array.isArray(msg.content)) {
      for (const b of msg.content) {
        if (b.type !== 'tool_use' || !b.input) continue;
        const file = b.input.file_path || b.input.notebook_path || '';
        if (!file) continue;
        const texts = [];
        if (b.name === 'Edit' && typeof b.input.new_string === 'string') {
          texts.push(b.input.new_string);
        } else if (b.name === 'Write' && typeof b.input.content === 'string') {
          texts.push(b.input.content);
        } else if (b.name === 'MultiEdit' && Array.isArray(b.input.edits)) {
          for (const e of b.input.edits) {
            if (typeof e.new_string === 'string') texts.push(e.new_string);
          }
        } else if (b.name === 'NotebookEdit' && typeof b.input.new_source === 'string') {
          texts.push(b.input.new_source);
        }
        for (const text of texts) events.push({ file, text });
      }
    }
  }
  let last = events.length;
  for (let i = events.length - 1; i >= 0; i--) {
    if (events[i].boundary) { last = i; break; }
  }
  return events.slice(last).filter((e) => e.text);
}

process.stdin.on('end', () => {
  let input = {};
  try { input = JSON.parse(data); } catch (e) { return allow(); }

  // Prevent infinite loop — if already triggered once, allow stop.
  if (input.stop_hook_active) return allow();
  if (!input.transcript_path) return allow();

  let written = [];
  try {
    written = writtenThisTurn(input.transcript_path);
  } catch (e) {
    return allow(); // transcript unreadable — never block for that
  }

  // Assembled from fragments so the tokens never appear literally in this file.
  const markers = ['TO' + 'DO', 'FIX' + 'ME', 'X' + 'XX', 'HA' + 'CK', 'W' + 'IP'];
  const markerRe = new RegExp('\\b(' + markers.join('|') + ')\\b');
  const docExt = /\.(md|markdown|mdx|txt|rst)$/i;

  const hits = [];
  for (const w of written) {
    if (docExt.test(w.file)) continue;
    for (const l of w.text.split('\n')) {
      if (markerRe.test(l)) hits.push(`${w.file}: ${l.trim().slice(0, 80)}`);
    }
  }

  if (hits.length > 0) {
    console.log(JSON.stringify({
      decision: 'block',
      reason: 'INCOMPLETE: Unfinished markers in code written this turn:\n' +
              hits.slice(0, 10).join('\n') +
              '\nResolve or remove them before stopping.',
    }));
  } else {
    allow();
  }
  process.exit(0);
});

process.stdin.resume();
