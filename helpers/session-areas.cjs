#!/usr/bin/env node
/**
 * session-areas.cjs — every session in a brain knows who else works there, on what, and who owns
 * which area. Hook and CLI in one file.
 *
 * WHY (measured 2026-11-08 on the macOS instance): two sessions in one brain edited the same
 * project folder (a PCB in a project repo) without knowing of each other. The parallel-sessions
 * check named pid, cwd and a count — never WHAT each one worked on — and coordination started only
 * after the operator asked. Who writes where is already in every tool call; it only has to be
 * written down where the other sessions read.
 *
 *   PostToolUse  (Write|Edit|MultiEdit|NotebookEdit|Bash|PowerShell):  session-areas.cjs record
 *       derives the written area from the call (file path; `git commit -- <paths>` for a shell) and
 *       stores it in `.claude-state/session-areas/<session id>.json`. When that write meets a
 *       live peer's area or claim for the first time, the session is told at once (additionalContext).
 *   UserPromptSubmit:  session-areas.cjs prompt
 *       the operator's prompt names other / parallel sessions (regexes in `session-areas.json` at the
 *       core root, the instance's language in `.claude/rules/session-areas.json`) -> the session map
 *       plus the order to coordinate now.
 *   CLI:  claim <path> [--note <text>] · release [<path>] · show [--brief] [--peers-only] · overlaps
 *       (`--root <brain>`, `--session <id>`; default CLAUDE_PROJECT_DIR / cwd and CLAUDE_CODE_SESSION_ID)
 *
 * Who a session is (name as ListAgents shows it, pid, status) is read from the harness's own session
 * registry `<config dir>/sessions/<pid>.json`, never rebuilt. A record whose pid is gone is deleted.
 * An area is the written file's folder, cut to AREA_DEPTH levels below its repo root; two areas
 * overlap when equal or one contains the other — a repo root alone (a commit without paths) is
 * shown, never an overlap, since every session commits in the brain. Fails open: a hook error is
 * silence. Fixture: scripts/test-session-areas.sh.
 */
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const { shellSegments, unquote, nativePath } = require('./published-text.cjs');

const AREA_DEPTH = 3;          // levels below the repo root an area keeps
const AREA_TTL_H = 8;          // a write older than this is no longer "recent"
const MAX_AREAS = 12;          // per session, newest kept
const NO_PID_TTL_H = 12;       // a record without a known pid expires after this
// System text that arrives as a prompt (the list of basics-hint.cjs plus <agent-message).
const NOT_A_PROMPT = /^\s*(<task-notification|<system-reminder|<cross-session-message|<agent-message|<local-command|Stop hook feedback|\[Request interrupted)/;
// Another session's or a subagent's words anywhere in the prompt (measured 2026-11-08: a subagent hand-back arrived
// as a queued peer command `<agent-message from="…">\n[Subagent hand-back] …` naming "parallel sessions" and fired the map).
const PEER_TEXT = /<agent-message\b|\[Subagent hand-back\]|<cross-session-message\b/;

function readJson(p, d) { try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch (e) { return d; } }
const norm = (p) => path.resolve(String(p)).replace(/\\/g, '/').replace(/\/+$/, '');
const home = norm(os.homedir());
const tilde = (p) => (p === home || p.startsWith(home + '/') ? '~' + p.slice(home.length) : p);
const inside = (a, b) => a === b || a.startsWith(b + '/');   // a inside (or equal to) b

function stateDir(root) { return path.join(root, '.claude-state', 'session-areas'); }

/** The harness's session registry: [{pid, sessionId, cwd, name, status}]. */
function registry() {
  const dir = path.join(process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude'), 'sessions');
  let files = [];
  try { files = fs.readdirSync(dir).filter((f) => f.endsWith('.json')); } catch (e) { return []; }
  return files.map((f) => readJson(path.join(dir, f), null)).filter((r) => r && r.sessionId);
}

function alive(pid) {
  if (process.env.SESSION_AREAS_ALIVE) return process.env.SESSION_AREAS_ALIVE.split(',').includes(String(pid)); // fixture seam
  try { process.kill(Number(pid), 0); return true; } catch (e) { return e.code === 'EPERM'; }
}

const repoCache = new Map();
function repoRoot(dir) {
  if (repoCache.has(dir)) return repoCache.get(dir);
  let d = dir; let found = null;
  for (;;) {
    if (fs.existsSync(path.join(d, '.git'))) { found = norm(d); break; }
    const up = path.dirname(d);
    if (up === d) break;
    d = up;
  }
  repoCache.set(dir, found);
  return found;
}

/** A written path -> {area, root}. A folder path (commit pathspec) counts as itself. */
function areaOf(p, isDir) {
  const abs = norm(p);
  const dir = isDir ? abs : norm(path.dirname(abs));
  const root = repoRoot(dir);
  if (!root) return { area: dir, root: null };
  const rel = dir === root ? [] : dir.slice(root.length + 1).split('/').slice(0, AREA_DEPTH);
  return { area: rel.length ? `${root}/${rel.join('/')}` : root, root };
}

/** The files of the commit a Bash call made, read from its own output `[<branch> <sha>] …`. */
function committedFiles(root, resp) {
  const text = typeof resp === 'string' ? resp : resp ? String(resp.stdout || '') : '';
  const m = text.match(/^\[[^\]\n]*?\s([0-9a-f]{7,40})\]/m);
  if (!m) return [];
  try {
    return require('child_process').execFileSync('git', ['-C', root, 'show', '--name-only', '--format=', m[1]],
      { encoding: 'utf8', timeout: 2000, stdio: ['ignore', 'pipe', 'ignore'] }).split('\n').filter(Boolean);
  } catch (e) { return []; }
}

/** The word arrays of every `git … commit …` call in a command line. A line the parser cannot read to the
 *  end (a heredoc, an open quote) falls back to a plain split — a hook here only records, never blocks. */
function commitCalls(cmd, ps) {
  const segs = shellSegments(cmd, ps) || cmd.split(/&&|\|\||;|\n/).map((s) => s.trim().split(/\s+/).map(unquote));
  return segs.filter((w) => { const g = w.indexOf('git'); return g >= 0 && w.indexOf('commit', g) > g; })
    .map((w) => w.slice(w.indexOf('git')));
}

/** The areas one tool call writes to. */
function areasFromCall(input) {
  const ti = input.tool_input || {};
  const cwd = input.cwd || process.cwd();
  const fp = ti.file_path || ti.notebook_path;
  if (fp && /^(Write|Edit|MultiEdit|NotebookEdit)$/.test(input.tool_name || '')) return [areaOf(path.resolve(cwd, fp), false)];
  const ps = input.tool_name === 'PowerShell';
  if ((input.tool_name !== 'Bash' && !ps) || typeof ti.command !== 'string') return [];
  const out = [];
  // Every `git [-C <dir>] … commit … [-- <paths>]` segment, read as the shell reads it (quotes, comments)
  // with published-text's word split; a path in the shell's form is made native first (OS-19: Git Bash
  // `/c/...` resolved by node on Windows to `C:\c\...`, measured 2026-11-11 on the Windows instance).
  for (const words of commitCalls(ti.command, ps)) {
    const ci = words.indexOf('commit');
    const c = words.slice(0, ci).indexOf('-C');   // `git commit -C <sha>` after the verb is a message source
    const base = path.resolve(cwd, c >= 0 ? nativePath(words[c + 1]) : '.');
    const dd = words.indexOf('--', ci);
    const specs = dd >= 0 ? words.slice(dd + 1).filter((s) => !/^[|>]/.test(s)) : [];
    if (!specs.length) {
      // No pathspec: the files of the commit this call made (its sha from the tool's own output); else the
      // repo root, which is an unknown area — shown, never an overlap.
      const r = repoRoot(norm(base));
      if (!r) continue;
      const files = committedFiles(r, input.tool_response);
      if (files.length) for (const f of files) out.push(areaOf(path.join(r, f), false));
      else out.push({ area: r, root: r });
      continue;
    }
    for (const s of specs) {
      const abs = path.resolve(repoRoot(norm(base)) || base, nativePath(s));
      let isDir = false; try { isDir = fs.statSync(abs).isDirectory(); } catch (e) { isDir = false; }
      out.push(areaOf(abs, isDir));
    }
  }
  return out;
}

/** Live sessions of this brain: harness registry + records, dead records deleted. */
function sessions(root, now) {
  const dir = stateDir(root);
  const reg = registry();
  const byId = new Map();
  for (const r of reg) {
    if (norm(r.cwd || '') !== norm(root) || !alive(r.pid)) continue;
    byId.set(r.sessionId, { id: r.sessionId, name: r.name || r.sessionId.slice(0, 8), pid: r.pid, status: r.status || '', areas: {}, claims: [] });
  }
  let files = [];
  try { files = fs.readdirSync(dir).filter((f) => f.endsWith('.json')); } catch (e) { files = []; }
  for (const f of files) {
    const rec = readJson(path.join(dir, f), null);
    if (!rec || !rec.id) continue;
    const reg1 = reg.find((r) => r.sessionId === rec.id);
    const pid = reg1 ? reg1.pid : rec.pid;
    const gone = pid ? !alive(pid) : (now - Date.parse(rec.updated || 0)) / 36e5 > NO_PID_TTL_H;
    if (gone) { try { fs.unlinkSync(path.join(dir, f)); } catch (e) { /* another session pruned it */ } continue; }
    const s = byId.get(rec.id) || { id: rec.id, name: rec.name || rec.id.slice(0, 8), pid, status: '' };
    byId.set(rec.id, { ...s, areas: rec.areas || {}, claims: rec.claims || [], told: rec.told || [] });
  }
  return [...byId.values()];
}

function recent(s, now) {
  return Object.entries(s.areas || {})
    .filter(([, v]) => (now - Date.parse(v.at)) / 36e5 <= AREA_TTL_H)
    .sort((a, b) => Date.parse(b[1].at) - Date.parse(a[1].at));
}

/** Overlaps between session `me` and every peer: [{key, peer, path, why}]. */
function overlaps(me, peers, now) {
  const out = [];
  const mine = recent(me, now);
  for (const p of peers) {
    const theirs = recent(p, now);
    for (const [a, va] of mine) {
      for (const [b, vb] of theirs) {
        const aRepo = va.root === a; const bRepo = vb.root === b;
        if (a === b ? aRepo : !((inside(a, b) && !bRepo) || (inside(b, a) && !aRepo))) continue;
        const at = a.length >= b.length ? a : b;
        out.push({ key: `${p.id}|w|${at}`, peer: p, path: at, why: 'both write' });
      }
    }
    // A write known only as a repo root (a commit whose files are unknown) is no evidence against a claim.
    for (const c of p.claims || []) {
      for (const [a, va] of mine) if (va.root !== a && (inside(a, c.path) || inside(c.path, a))) out.push({ key: `${p.id}|c|${a}`, peer: p, path: a, why: `claimed by ${p.name}${c.note ? ` (${c.note})` : ''}` });
    }
    for (const c of me.claims || []) {
      for (const [b, vb] of theirs) if (vb.root !== b && (inside(b, c.path) || inside(c.path, b))) out.push({ key: `${p.id}|m|${b}`, peer: p, path: b, why: `claimed by ${me.name}${c.note ? ` (${c.note})` : ''}, written by ${p.name}` });
    }
  }
  const seen = new Set();
  return out.filter((o) => !seen.has(o.key) && seen.add(o.key));
}

function ago(at, now) {
  const m = Math.round((now - Date.parse(at)) / 6e4);
  return m < 60 ? `${m} min ago` : `${Math.round(m / 60)} h ago`;
}

/** The claim command as this file sits in the brain (core/helpers/… when pinned, a local copy in an alpha). */
function claimCmd() {
  const root = norm(process.env.CLAUDE_PROJECT_DIR || process.cwd());
  const self = norm(__filename);
  return `node ${self.startsWith(root + '/') ? self.slice(root.length + 1) : tilde(self)} claim <path> --note "<what>"`;
}

function overlapLine(me, o) {
  return `OVERLAP: ${me.name} and ${o.peer.name} — ${o.why} ${tilde(o.path)}. Coordinate now: SendMessage to ${o.peer.name} (its ListAgents name), agree who owns which area, then record it with \`${claimCmd()}\`.`;
}

/** Every pair's overlaps, each once (no session of its own: a watch, a hand run). */
function allOverlapLines(all, now) {
  const seen = new Set(); const lines = [];
  for (const s of all) {
    for (const o of overlaps(s, all.filter((x) => x.id !== s.id), now)) {
      const k = [s.id, o.peer.id].sort().join('|') + o.path;
      if (!seen.has(k)) { seen.add(k); lines.push(overlapLine(s, o)); }
    }
  }
  return lines;
}

/** The session map as text lines. */
function map(root, selfId, now, opts) {
  const all = sessions(root, now);
  const me = all.find((s) => s.id === selfId) || { id: selfId, name: 'this session', areas: {}, claims: [] };
  const peers = all.filter((s) => s.id !== selfId);
  if (opts.peersOnly && !peers.length) return [];
  const lines = [`SESSION MAP: ${all.length} live session(s) in ${tilde(norm(root))}`];
  const listed = opts.peersOnly || !selfId ? peers : [me, ...peers];
  for (const s of listed) {
    const w = recent(s, now).slice(0, opts.brief ? 3 : MAX_AREAS).map(([a, v]) => `${tilde(a)} (${ago(v.at, now)})`);
    const c = (s.claims || []).map((x) => `${tilde(x.path)}${x.note ? ` "${x.note}"` : ''}`);
    lines.push(`- ${s.name}${s.id === selfId ? ' (this session)' : ''}${s.pid ? ` pid ${s.pid}` : ''}${s.status ? ` ${s.status}` : ''}: `
      + `writes ${w.length ? w.join(', ') : 'nothing recorded yet'}; owns ${c.length ? c.join(', ') : 'nothing claimed'}`);
  }
  return lines.concat(selfId ? overlaps(me, peers, now).map((o) => overlapLine(me, o)) : allOverlapLines(all, now));
}

function writeRecord(root, rec) {
  const dir = stateDir(root);
  fs.mkdirSync(dir, { recursive: true });
  const f = path.join(dir, `${rec.id}.json`);
  fs.writeFileSync(f + '.tmp', JSON.stringify(rec, null, 1) + '\n');
  fs.renameSync(f + '.tmp', f);
}

function loadOwn(root, id) {
  const r = registry().find((x) => x.sessionId === id);
  const rec = readJson(path.join(stateDir(root), `${id}.json`), null) || { id, areas: {}, claims: [], told: [] };
  if (r) { rec.name = r.name; rec.pid = r.pid; }
  return rec;
}

/** PostToolUse: record the areas, tell the session about a NEW overlap once. */
function record(input, now) {
  const root = process.env.CLAUDE_PROJECT_DIR || input.cwd || process.cwd();
  const id = input.session_id;
  if (!id) return null;
  const found = areasFromCall(input);
  if (!found.length) return null;
  const rec = loadOwn(root, id);
  const at = new Date(now).toISOString();
  for (const f of found) rec.areas[f.area] = { at, root: f.root };
  rec.areas = Object.fromEntries(Object.entries(rec.areas).sort((a, b) => Date.parse(b[1].at) - Date.parse(a[1].at)).slice(0, MAX_AREAS));
  rec.updated = at;
  const all = sessions(root, now);
  const me = { ...rec, name: rec.name || id.slice(0, 8) };
  const fresh = overlaps(me, all.filter((s) => s.id !== id), now).filter((o) => !(rec.told || []).includes(o.key));
  rec.told = [...(rec.told || []), ...fresh.map((o) => o.key)].slice(-50);
  writeRecord(root, rec);
  return fresh.length ? fresh.map((o) => overlapLine(me, o)).join('\n') : null;
}

function triggers(root) {
  const core = readJson(path.join(__dirname, '..', 'session-areas.json'), {}).triggers || [];
  const inst = readJson(path.join(root, '.claude', 'rules', 'session-areas.json'), {}).triggers || [];
  const out = [];
  for (const s of core.concat(inst)) { try { out.push(new RegExp(s, 'i')); } catch (e) { /* skip */ } }
  return out;
}

/** UserPromptSubmit: the operator speaks of other sessions -> the map and the order to coordinate. */
function prompt(input, now) {
  const root = process.env.CLAUDE_PROJECT_DIR || input.cwd || process.cwd();
  const text = String(input.prompt || '');
  // A watch event, a peer's message or a hook's feedback arrives as a prompt too — it is no operator word
  // (measured 2026-11-08 in the alpha: a SESSIONS task-notification "… 2 sessions in …" fired the map).
  if (NOT_A_PROMPT.test(text) || PEER_TEXT.test(text) || !triggers(root).some((r) => r.test(text))) return null;
  const lines = map(root, input.session_id, now, {});
  return `<session-map>\nThe operator speaks of other sessions. Coordinate NOW, before further writes: for every peer below, `
    + 'SendMessage it (ListAgents name) what you work on and which area you take; settle each OVERLAP line by agreeing who '
    + `owns which path, and record your areas with \`${claimCmd()}\`. `
    + 'Tell the operator in one line who works on what.\n' + lines.join('\n') + '\n</session-map>';
}

function cli(argv, now) {
  const opt = (k) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] : undefined; };
  const root = opt('--root') || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const id = opt('--session') || process.env.CLAUDE_CODE_SESSION_ID || '';
  const cmd = argv[0];
  const pos = argv.filter((a, i) => i > 0 && !a.startsWith('--') && !(argv[i - 1] || '').startsWith('--'));
  if (cmd === 'claim' || cmd === 'release') {
    if (!id) { console.error('session-areas: no session id (CLAUDE_CODE_SESSION_ID unset) — pass --session <id>'); return 2; }
    const rec = loadOwn(root, id);
    rec.claims = rec.claims || [];
    if (cmd === 'claim') {
      if (!pos[0]) { console.error('usage: session-areas.cjs claim <path> [--note <text>]'); return 2; }
      const p = norm(path.resolve(pos[0]));
      rec.claims = rec.claims.filter((c) => c.path !== p).concat({ path: p, note: opt('--note') || '', at: new Date(now).toISOString() });
    } else {
      rec.claims = pos[0] ? rec.claims.filter((c) => c.path !== norm(path.resolve(pos[0]))) : [];
    }
    rec.updated = new Date(now).toISOString();
    writeRecord(root, rec);
  }
  if (['claim', 'release', 'show', 'overlaps'].includes(cmd)) {
    let lines = map(root, id, now, { brief: argv.includes('--brief'), peersOnly: argv.includes('--peers-only') });
    if (cmd === 'overlaps') lines = lines.filter((l) => l.startsWith('OVERLAP:'));
    if (lines.length) console.log(lines.join('\n'));
    return 0;
  }
  console.error('usage: session-areas.cjs record|prompt (hook, JSON on stdin) | claim <path> [--note <text>] | release [<path>] | show [--brief] [--peers-only] | overlaps  [--root <brain>] [--session <id>]');
  return 2;
}

if (require.main === module) {
  const argv = process.argv.slice(2);
  const now = process.env.SESSION_AREAS_NOW ? Date.parse(process.env.SESSION_AREAS_NOW) : Date.now();
  if (argv[0] === 'record' || argv[0] === 'prompt') {
    let raw = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (c) => { raw += c; });
    process.stdin.on('end', () => {
      let out = null;
      try { const input = JSON.parse(raw); out = argv[0] === 'record' ? record(input, now) : prompt(input, now); } catch (e) { out = null; }
      if (out && argv[0] === 'record') process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: 'PostToolUse', additionalContext: out } }) + '\n');
      else if (out) process.stdout.write(out + '\n');
      process.exit(0);
    });
  } else {
    process.exit(cli(argv, now));
  }
}

module.exports = { areasFromCall, overlaps, record, prompt, map, sessions };
