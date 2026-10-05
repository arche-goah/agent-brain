#!/usr/bin/env node
/**
 * Stop hook: an ABSENCE claim is a claim about every source, so it needs a search
 * over every source.
 *
 * The class (operator-approved 2026-10-05): "X is documented nowhere", "never
 * measured", "there is no record of it" are statements about the WHOLE knowledge
 * base, but they get made after searching one corner of it. Incident: "the desk's
 * send rate is documented nowhere" was stated after searching only the shared-memory
 * repo — while a manual excerpt sat in a tool suite and a wire measurement sat in a
 * testbench runlog. A wrong absence claim is worse than a wrong presence claim: it
 * ends the search, and the next step is to re-measure what was already measured.
 *
 * What fires: BOTH conditions in the same turn.
 *   (a) an absence claim in the assistant's own prose (built-in English patterns,
 *       other languages are instance data — see below);
 *   (b) at least one registered source root that no search of THIS turn covered.
 *       A search covers a root when it ran on the root, inside it, or on a parent of
 *       it. Search calls: Grep and Glob (their `path`, default the project root),
 *       Read (its `file_path`), Bash with grep / rg / find / ag / ack / fd / git grep
 *       (the path arguments of the command, relative ones against the project root or
 *       a leading `cd`).
 * A deliberately narrower search is legitimate — it just has to be visible. A line
 * `⚙ scope: <what was searched, and why only that>` in the reply lets the claim pass.
 *
 * Source roots are INSTANCE DATA: `.claude/rules/absence-sources.json`
 *   {"roots": ["docs/", "~/some/other/repo"], "claim_patterns": [...],
 *    "scope_markers": [...]}
 * Roots are relative to the project root, absolute, or start with `~`. A brain without
 * that file (or with an empty list) has nothing to check against and this gate stays
 * silent — the template under `templates/rules-instance/` ships empty on purpose.
 * `claim_patterns` and `scope_markers` EXTEND the English built-ins (the layering
 * contract of the premise and promise gates: engine English, languages are data, a
 * class fix lands in the built-ins first).
 *
 * Known blind spot, recorded rather than guessed: a search delegated to a subagent
 * (Agent/Task tool) is invisible here — the parent transcript holds the prompt, not
 * the calls. Record rows carry `delegated` so the precision measurement can see it.
 *
 * Mechanics kept from the sibling gates (proven there): transcript is the source;
 * stdin read to 'end', never on a timer; cooldown of 2 operator turns, read from the
 * gate's own replayed echo; quoted text and code are stripped before matching (talk
 * ABOUT a claim quotes it); `--record` never blocks and prints {record:[...]} for the
 * stop-dispatcher, which appends to `.claude-state/absence-gate.jsonl` — measure, then
 * arm.
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

let data = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { data += c; });

const RECORD = process.argv.includes('--record');
function allow() { process.exit(0); }

const HOOK_ECHO = /^Stop hook feedback:/;
const OWN_ECHO = /ABSENCE-GATE/;
const COOLDOWN_TURNS = 2;
const TAIL_BYTES = 4 * 1024 * 1024;
const WIN = process.platform === 'win32';

// The claim FORM: a statement about the whole record, not about one place. "not in
// this file" is a local observation and stays free; "documented nowhere" is not.
const BUILTIN_CLAIM = [
  '\\b(documented|mentioned|described|recorded|measured|specified|written\\s+down|found)\\s+nowhere\\b',
  '\\bnowhere\\s+(documented|mentioned|described|recorded|measured|specified|written|to\\s+be\\s+found)\\b',
  '\\b(has|have|was|were|is|are)\\s+never\\s+(been\\s+)?(documented|measured|recorded|described|written\\s+down|specified)\\b',
  '\\bnever\\s+(been\\s+)?(documented|measured|recorded)\\s+(anywhere|before|so\\s+far)\\b',
  '\\bnot\\s+(documented|measured|recorded|mentioned|described)\\s+anywhere\\b',
  '\\b(there\\s+is|there\'s|there\\s+are)\\s+no\\s+(documentation|record|records|measurement|measurements|mention|reference|source|data)\\s+(of|for|on|about|anywhere)\\b',
  '\\b(does\\s+not|doesn\'t|do\\s+not|don\'t)\\s+exist\\s+anywhere\\b',
  '\\bexists?\\s+nowhere\\b',
];

const BUILTIN_SCOPE_MARKER = ['⚙\\s*scope\\s*:'];

const SEARCH_BASH = /(^|[\s;&|(])(grep|egrep|fgrep|rg|find|ag|ack|fd|git\s+grep)\b/;

function loadConfig(cwd) {
  let cfg = {};
  try {
    cfg = JSON.parse(fs.readFileSync(path.join(cwd, '.claude', 'rules', 'absence-sources.json'), 'utf8'));
  } catch (e) { /* no instance file — nothing to check against */ }
  const merge = (builtins, extra) => {
    const out = [...builtins];
    if (Array.isArray(extra)) {
      for (const s of extra) {
        try { new RegExp(s); out.push(s); } catch (e) { /* skip broken regex */ }
      }
    }
    return new RegExp(out.join('|'), 'giu');
  };
  const roots = (Array.isArray(cfg.roots) ? cfg.roots : [])
    .filter((r) => typeof r === 'string' && r.trim())
    .map((r) => ({ label: r, abs: resolveFrom(cwd, r) }));
  return {
    roots,
    claim: merge(BUILTIN_CLAIM, cfg.claim_patterns),
    scope: merge(BUILTIN_SCOPE_MARKER, cfg.scope_markers),
  };
}

/** One comparable form: forward slashes, no trailing slash, Git Bash drive mapped. */
function norm(p) {
  let s = String(p).replace(/\\/g, '/');
  if (WIN) {
    const m = /^\/([a-zA-Z])(\/|$)/.exec(s); // Git Bash /c/... -> C:/...
    if (m) s = `${m[1].toUpperCase()}:/${s.slice(3)}`;
  }
  s = path.resolve(s).replace(/\\/g, '/');
  if (s.length > 1 && s.endsWith('/') && !/^[A-Za-z]:\/$/.test(s)) s = s.slice(0, -1);
  return WIN ? s.toLowerCase() : s;
}

function resolveFrom(base, p) {
  let s = String(p).trim().replace(/^["']|["']$/g, '');
  if (s === '~' || s.startsWith('~/') || s.startsWith('~\\')) s = path.join(os.homedir(), s.slice(1));
  else if (s.startsWith('$HOME/')) s = path.join(os.homedir(), s.slice(5));
  const abs = /^([A-Za-z]:[\\/]|\/)/.test(s) ? s : path.join(base, s);
  return norm(abs);
}

/** a covers b: same path, or b lies inside a. */
function covers(a, b) {
  return a === b || b.startsWith(a.endsWith('/') ? a : `${a}/`);
}

/** Paths a Bash search command looks at. Rough by design — record mode measures it. */
function bashPaths(cmd, cwd) {
  let base = cwd;
  const cd = /(?:^|[;&|]\s*)cd\s+("[^"]+"|'[^']+'|\S+)/.exec(cmd);
  if (cd) base = resolveFrom(cwd, cd[1]);
  const out = [];
  // Only the segments that actually search; `cd x && grep -r foo .` -> the grep part.
  for (const seg of cmd.split(/&&|\|\||;|\|/)) {
    if (!SEARCH_BASH.test(seg)) continue;
    const toks = seg.match(/"[^"]*"|'[^']*'|\S+/g) || [];
    let pathish = 0;
    for (const t0 of toks) {
      const t = t0.replace(/^["']|["']$/g, '');
      if (t.startsWith('-')) {
        const m = /^-C(.+)$/.exec(t); // git -C<dir> written joined
        if (m) out.push(resolveFrom(base, m[1]));
        continue;
      }
      if (t === '.' || t === '..' || t.startsWith('~') || t.startsWith('$HOME/')
          || /^([A-Za-z]:[\\/]|\/|\.\.?[\\/])/.test(t)
          || /^[\w.-]+[\\/]/.test(t)) {
        out.push(resolveFrom(base, t)); pathish += 1;
      }
    }
    // A search with no path argument runs where the shell stands.
    if (pathish === 0) out.push(norm(base));
  }
  return out;
}

function stripQuoted(text) {
  return text
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/`[^`\n]*`/g, ' ')
    .replace(/„[^“”"\n]*[“”"]/g, ' ')
    .replace(/“[^”]*”/g, ' ')
    .replace(/"[^"\n]*"/g, ' ')
    .replace(/‹[^›]*›|«[^»]*»/g, ' ')
    .replace(/^\s*>.*$/gm, ' ');
}

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
  } finally {
    fs.closeSync(fd);
  }
}

/** Texts and searched paths of the running turn, plus cooldown state. */
function analyze(transcriptPath, cwd) {
  const events = [];
  for (const line of readTail(transcriptPath)) {
    if (!line.trim()) continue;
    let d;
    try { d = JSON.parse(line); } catch (e) { continue; }
    const msg = d.message;
    if (!msg) continue;
    if (msg.role === 'user' && typeof msg.content === 'string') {
      if (HOOK_ECHO.test(msg.content)) {
        if (OWN_ECHO.test(msg.content)) events.push({ gate: true });
        continue;
      }
      events.push({ boundary: true });
      continue;
    }
    if (msg.role !== 'assistant' || !Array.isArray(msg.content)) continue;
    for (const b of msg.content) {
      if (b.type === 'text' && b.text) { events.push({ text: b.text }); continue; }
      if (b.type !== 'tool_use' || !b.name) continue;
      const inp = b.input || {};
      if (b.name === 'Grep' || b.name === 'Glob') {
        events.push({ searched: [inp.path ? resolveFrom(cwd, inp.path) : norm(cwd)] });
      } else if (b.name === 'Read' && inp.file_path) {
        events.push({ searched: [resolveFrom(cwd, inp.file_path)] });
      } else if (b.name === 'Bash' && typeof inp.command === 'string' && SEARCH_BASH.test(inp.command)) {
        events.push({ searched: bashPaths(inp.command, cwd) });
      } else if (b.name === 'Agent' || b.name === 'Task') {
        events.push({ delegated: true });
      }
    }
  }

  let last = 0;
  for (let i = events.length - 1; i >= 0; i--) {
    if (events[i].boundary) { last = i; break; }
  }
  const texts = [];
  const searched = [];
  let delegated = 0;
  for (let i = last; i < events.length; i++) {
    if (events[i].text) texts.push(events[i].text);
    if (events[i].searched) searched.push(...events[i].searched);
    if (events[i].delegated) delegated += 1;
  }

  let lastGate = -1;
  for (let i = events.length - 1; i >= 0; i--) {
    if (events[i].gate) { lastGate = i; break; }
  }
  let turnsSinceGate = Infinity;
  if (lastGate >= 0) {
    turnsSinceGate = 0;
    for (let i = lastGate + 1; i < events.length; i++) if (events[i].boundary) turnsSinceGate++;
  }
  return { texts, searched, delegated, quiet: turnsSinceGate < COOLDOWN_TURNS };
}

process.stdin.on('end', () => {
  let input = {};
  try { input = JSON.parse(data); } catch (e) { return allow(); }
  if (input.stop_hook_active) return allow();
  if (!input.transcript_path) return allow();

  const cwd = input.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  let claims = [];
  let missing = [];
  let scoped = false;
  let seen;
  let cfg;
  try {
    cfg = loadConfig(cwd);
    if (cfg.roots.length === 0) return allow(); // nothing registered, nothing to hold against
    seen = analyze(input.transcript_path, cwd);
    const raw = seen.texts.join('\n');
    const clean = stripQuoted(raw);
    for (const h of clean.match(cfg.claim) || []) {
      const n = h.toLowerCase().replace(/\s+/g, ' ').trim();
      if (!claims.includes(n)) claims.push(n);
    }
    if (claims.length === 0) return allow();
    scoped = cfg.scope.test(raw); // the marker may sit in code formatting — read raw
    missing = cfg.roots
      // on the root, on a parent of it, or inside it — a look into the root counts
      .filter((r) => !seen.searched.some((s) => covers(s, r.abs) || covers(r.abs, s)))
      .map((r) => r.label);
  } catch (e) {
    return allow(); // transcript unreadable — never block because of that
  }

  const due = missing.length > 0 && !scoped;
  if (RECORD) {
    console.log(JSON.stringify({ record: [{
      claims: claims.slice(0, 4), roots: cfg.roots.length, unsearched: missing,
      searches: seen.searched.length, delegated: seen.delegated, scoped,
      would_block: due && !seen.quiet,
    }] }));
    return allow();
  }
  if (!due || seen.quiet) return allow();

  const reason = 'ABSENCE-GATE — an absence claim covers every source, but this turn ' +
    'searched only some of them.\n' +
    `Absence wording: ${claims.slice(0, 3).join(' · ')}\n` +
    `Unsearched roots: ${missing.join(', ')}\n` +
    'Search those before saying it exists nowhere. A narrower search on purpose is ' +
    'fine when it is visible: add a line "⚙ scope: <what was searched, and why only ' +
    'that>" and re-issue.';
  console.log(JSON.stringify({ decision: 'block', reason }));
  process.exit(0);
});

process.stdin.resume();
