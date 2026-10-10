#!/usr/bin/env node
/**
 * memory-sync — keep the auto-memory (which lives OUTSIDE the repo) in sync with a
 * committed snapshot under docs/memory-snapshot/, so memory travels via git between
 * machines (mac <-> linux).
 *
 * Live memory dir:  ~/.claude/projects/<slug>/memory/   (slug = repo abs path, '/'->'-')
 * Snapshot dir:     <repo>/docs/memory-snapshot/        (committed)
 * Manifest:         <repo>/docs/memory-snapshot/.sync-manifest.json  (per-file hash+ts = the
 *                   "common base" used to detect divergence)
 *
 * Commands:
 *   export        live memory  -> snapshot   (refresh what gets committed)
 *   import        snapshot     -> live memory (load other machine's memory)
 *   status        show per-file state, no changes
 *   push          export, then git add/commit/push docs/memory-snapshot
 *   pull          git pull, then import
 *   prune         remove snapshot files whose live counterpart was deleted, and
 *                 manifest entries whose file exists on neither side.
 *                 DELIBERATELY not part of export: on a machine that never imported,
 *                 "snapshot-only" is indistinguishable from "deleted here" — auto-
 *                 deleting on export could drop the other machine's memories. Run
 *                 prune consciously right after deleting live memories.
 *
 * Conflict model (per file): 3-way against the base THIS MACHINE last synced to.
 *   - only snapshot changed  -> snapshot wins (copy into live)
 *   - only live changed       -> live wins (write to snapshot)
 *   - both changed (DIVERGED) -> keep BOTH: import writes the snapshot copy as
 *                                <name>.incoming.md into live; export leaves the snapshot
 *                                alone and flags; never overwrite -> no data loss.
 *   - base unknown            -> treated as DIVERGED whenever the two sides differ.
 *
 * The base lives in <live>/.sync-base.json, per machine and untracked. It used to be
 * the tracked manifest — which, right after a `git pull`, holds the OTHER machine's view:
 * every live file on a machine that had not synced for weeks looked "changed", and the
 * export running as a Stop hook wrote the stale memory over the freshly pulled snapshot
 * (measured 2026-10-10: 458 lines of the other machine's memory gone from the working
 * tree, caught before the commit). The tracked manifest now only says what the snapshot
 * holds (memory-lint reads it); who is ahead is a question each machine answers for itself.
 * Hook-safe: writes progress to stderr, nothing to stdout, always exits 0.
 */
const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');
const { execFileSync } = require('child_process');

const repoRoot = (process.env.CLAUDE_PROJECT_DIR || process.cwd()).replace(/\/+$/, '');
const snapshotDir = path.join(repoRoot, 'docs', 'memory-snapshot');
const manifestPath = path.join(snapshotDir, '.sync-manifest.json');

function liveDir() {
  if (process.env.CLAUDE_MEMORY_DIR) return process.env.CLAUDE_MEMORY_DIR;
  // Claude Code mints the folder by replacing every non-alphanumeric character with '-'.
  // The old split('/') form matched that on POSIX by accident and not at all on Windows:
  // it left the drive colon and the backslashes standing, so export aimed at
  // ~/.claude/projects/C:\Users\...\memory and reported "no live memory dir" on every
  // close (measured 2026-08-03 — which is why docs/memory-snapshot/ had never been written).
  const slug = repoRoot.replace(/[^A-Za-z0-9]/g, '-');
  return path.join(os.homedir(), '.claude', 'projects', slug, 'memory');
}

const log = (...a) => process.stderr.write(a.join(' ') + '\n');
const nowISO = () => new Date().toISOString();
const sha = (s) => crypto.createHash('sha256').update(s).digest('hex');

function listMd(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir).filter(
    (f) => f.endsWith('.md') && f !== 'README.md' && !f.endsWith('.incoming.md')
  );
}
function readFileSafe(p) { try { return fs.readFileSync(p, 'utf8'); } catch (e) { return null; } }
// The manifest is a TRACKED file (the common 3-way base must travel between machines),
// and this script runs as a Stop and SessionEnd hook. Measured 2026-09-13 on two
// machines: an export that changed no file still rewrote `lastSync`, so the manifest was
// dirty after every close commit — one line of diff, every session, and `git pull
// --ff-only` on the other machine failed on it. So `lastSync` now means "the tracked set
// last changed", and a save whose `files` equal what was loaded writes nothing.
let loadedFiles = null;
function loadManifest() {
  try {
    const m = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
    loadedFiles = JSON.stringify(m.files || {});
    return m;
  } catch (e) { loadedFiles = null; return { files: {}, lastSync: null }; }
}
function saveManifest(m) {
  if (loadedFiles !== null && JSON.stringify(m.files) === loadedFiles) return;
  m.lastSync = nowISO();
  fs.mkdirSync(snapshotDir, { recursive: true });
  fs.writeFileSync(manifestPath, JSON.stringify(m, null, 2) + '\n');
}

// The per-machine base: hash per file as THIS machine last saw both sides agree (after an
// import or export). Lives next to the live memory, never tracked — the tracked manifest
// travels between machines and therefore cannot be anyone's base (see header).
function basePath() { return path.join(liveDir(), '.sync-base.json'); }
function loadBase() {
  try { return JSON.parse(fs.readFileSync(basePath(), 'utf8')); } catch (e) { return { files: {} }; }
}
function saveBase(b) {
  fs.mkdirSync(liveDir(), { recursive: true });
  fs.writeFileSync(basePath(), JSON.stringify(b, null, 2) + '\n');
}

// Multiple Claude Code sessions in the SAME repo each run this hook at their own
// SessionStart — measured 2026-08-20 (invariant I-7): memory-lint.py, also a
// SessionStart check, read the manifest while a write here was still in flight and
// reported a phantom "content differs". This lock does not serialize writers against
// each other (each file write is its own writeFileSync, and hash-convergent — a second
// writer re-doing the same export is a no-op, not corruption); it only gives a READER
// something to check so it can skip instead of misreading a half-written state. Age-
// checked, not held-checked: a hook that died mid-run must never leave a permanent lock.
// Stale threshold lives on the reader's side (memory-lint.py's LOCK_STALE_S).
const lockPath = path.join(snapshotDir, '.sync.lock');
function withLock(fn) {
  fs.mkdirSync(snapshotDir, { recursive: true });
  fs.writeFileSync(lockPath, JSON.stringify({ pid: process.pid, ts: nowISO() }));
  try { fn(); }
  finally { try { fs.unlinkSync(lockPath); } catch (e) { /* already gone */ } }
}

function doExport() {
  const live = liveDir();
  if (!fs.existsSync(live)) { log(`[memory-sync] no live memory dir (${live}); nothing to export`); return; }
  fs.mkdirSync(snapshotDir, { recursive: true });
  const m = loadManifest();
  const b = loadBase();
  let changed = 0, held = 0, pending = 0;
  for (const name of listMd(live)) {
    const content = readFileSafe(path.join(live, name));
    if (content == null) continue;
    const h = sha(content);
    const snapPath = path.join(snapshotDir, name);
    const snapContent = readFileSafe(snapPath);
    const snapHash = snapContent == null ? null : sha(snapContent);
    const base = b.files[name];

    if (snapHash === h) { // both sides agree: that IS the base, whatever it was before
      b.files[name] = { hash: h };
      m.files[name] = { hash: h, updated: (m.files[name] && m.files[name].updated) || nowISO() };
      continue;
    }
    const liveChanged = !base || base.hash !== h;
    const snapChanged = snapHash != null && (!base || base.hash !== snapHash);
    if (snapHash == null || (liveChanged && !snapChanged)) {
      fs.writeFileSync(snapPath, content);
      b.files[name] = { hash: h };
      m.files[name] = { hash: h, updated: nowISO() };
      changed++;
      log(`[memory-sync] export: ${name}`);
    } else if (!liveChanged) {
      pending++; // snapshot moved under us (a pull) — import brings it in, export must not undo it
      log(`[memory-sync] snapshot newer, import pending: ${name}`);
    } else {
      held++;
      log(`[memory-sync] CONFLICT: ${name} changed on both sides — snapshot left untouched, run import`);
    }
  }
  saveBase(b);
  saveManifest(m);
  log(`[memory-sync] export done (${changed} file(s) updated, ${pending} pending import, ${held} held)`);
}

function doImport() {
  const live = liveDir();
  fs.mkdirSync(live, { recursive: true });
  const m = loadManifest();
  const b = loadBase();
  let copied = 0, kept = 0, conflicts = 0;
  for (const name of listMd(snapshotDir)) {
    const snapContent = readFileSafe(path.join(snapshotDir, name));
    if (snapContent == null) continue;
    const snapHash = sha(snapContent);
    const livePath = path.join(live, name);
    const liveContent = readFileSafe(livePath);
    const base = b.files[name];
    const entry = m.files[name];

    if (liveContent == null) {
      fs.writeFileSync(livePath, snapContent);
      b.files[name] = { hash: snapHash };
      m.files[name] = { hash: snapHash, updated: (entry && entry.updated) || nowISO() };
      copied++; log(`[memory-sync] import (new): ${name}`); continue;
    }
    const liveHash = sha(liveContent);
    if (liveHash === snapHash) {
      b.files[name] = { hash: snapHash };
      m.files[name] = { hash: snapHash, updated: (entry && entry.updated) || nowISO() };
      continue;
    }

    const snapChanged = !base || base.hash !== snapHash;
    const liveChanged = !base || base.hash !== liveHash;
    if (snapChanged && !liveChanged) {
      fs.writeFileSync(livePath, snapContent);
      b.files[name] = { hash: snapHash };
      m.files[name] = { hash: snapHash, updated: (entry && entry.updated) || nowISO() };
      copied++; log(`[memory-sync] import (incoming wins): ${name}`);
    } else if (!snapChanged && liveChanged) {
      kept++; log(`[memory-sync] keep local (local newer): ${name}`);
    } else {
      const inc = path.join(live, name.replace(/\.md$/, '.incoming.md'));
      fs.writeFileSync(inc, snapContent);
      conflicts++; log(`[memory-sync] CONFLICT: ${name} -> kept local + wrote ${path.basename(inc)} (reconcile manually)`);
    }
  }
  saveBase(b);
  saveManifest(m);
  log(`[memory-sync] import done (${copied} copied, ${kept} kept-local, ${conflicts} conflict(s))`);
  if (conflicts) log(`[memory-sync] ${conflicts} conflict(s): review *.incoming.md in ${live}`);
}

function doStatus() {
  const live = liveDir();
  const m = loadManifest();
  const b = loadBase();
  const names = new Set([...listMd(live), ...listMd(snapshotDir)]);
  log(`live:     ${live}`);
  log(`snapshot: ${snapshotDir}`);
  log(`lastSync: ${m.lastSync || '(never)'}`);
  log(`base:     ${fs.existsSync(basePath()) ? basePath() : '(none yet — differing files count as DIVERGED until the first import/export)'}`);
  log('--- per file ---');
  for (const name of [...names].sort()) {
    const lc = readFileSafe(path.join(live, name));
    const sc = readFileSafe(path.join(snapshotDir, name));
    const base = b.files[name];
    let state;
    if (lc == null) state = 'snapshot-only (import will add)';
    else if (sc == null) state = 'live-only (export will add)';
    else if (sha(lc) === sha(sc)) state = 'in-sync';
    else {
      const sChg = !base || base.hash !== sha(sc);
      const lChg = !base || base.hash !== sha(lc);
      state = sChg && lChg ? 'DIVERGED (conflict)' : sChg ? 'snapshot-newer' : 'live-newer';
    }
    log(`  ${name.padEnd(36)} ${state}`);
  }
}

function doPrune() {
  const live = liveDir();
  if (!fs.existsSync(live)) { log('[memory-sync] prune ABORTED: no live memory dir — refusing to prune blind'); return; }
  const m = loadManifest();
  const b = loadBase();
  let removed = 0;
  for (const name of listMd(snapshotDir)) {
    if (!fs.existsSync(path.join(live, name))) {
      fs.unlinkSync(path.join(snapshotDir, name));
      delete m.files[name];
      delete b.files[name];
      removed++;
      log(`[memory-sync] prune: ${name} (no live counterpart)`);
    }
  }
  // Manifest ghosts: an entry whose file exists on NEITHER side (memory deleted and the
  // snapshot copy removed outside prune). The loop above only walks snapshot files, so
  // such an entry stayed forever — memory-lint.py reports it and names prune as the fix.
  // Dropping it loses nothing: the entry is a hash of content that no longer exists.
  for (const name of Object.keys(m.files)) {
    if (!fs.existsSync(path.join(snapshotDir, name)) && !fs.existsSync(path.join(live, name))) {
      delete m.files[name];
      delete b.files[name];
      removed++;
      log(`[memory-sync] prune: ${name} (manifest entry without a file)`);
    }
  }
  saveBase(b);
  saveManifest(m);
  log(`[memory-sync] prune done (${removed} file(s) removed)`);
}

function git(args) {
  return execFileSync('git', args, { cwd: repoRoot, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
}
function doPush() {
  doExport();
  try {
    const status = git(['status', '--porcelain', 'docs/memory-snapshot']);
    if (!status.trim()) { log('[memory-sync] push: snapshot already up to date'); return; }
    git(['add', 'docs/memory-snapshot']);
    git(['commit', '-m', 'chore(memory): sync snapshot']);
    git(['push']);
    log('[memory-sync] push: committed + pushed snapshot');
  } catch (e) { log('[memory-sync] push failed: ' + (e.stderr || e.message)); }
}
function doPull() {
  try { git(['pull', '--ff-only']); log('[memory-sync] pull: fetched latest'); }
  catch (e) { log('[memory-sync] git pull failed (resolve manually): ' + (e.stderr || e.message)); }
  doImport();
}

const cmd = process.argv[2] || 'status';
try {
  if (cmd === 'export') withLock(doExport);
  else if (cmd === 'import') withLock(doImport);
  else if (cmd === 'status') doStatus();
  else if (cmd === 'push') withLock(doPush);
  else if (cmd === 'pull') withLock(doPull);
  else if (cmd === 'prune') withLock(doPrune);
  else log(`[memory-sync] unknown command: ${cmd} (use export|import|status|push|pull|prune)`);
} catch (e) {
  log('[memory-sync] error: ' + (e && e.message)); // never throw out of a hook
}
process.exit(0);
