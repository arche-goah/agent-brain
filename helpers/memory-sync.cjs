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
 *   prune         remove snapshot files whose live counterpart was deleted.
 *                 DELIBERATELY not part of export: on a machine that never imported,
 *                 "snapshot-only" is indistinguishable from "deleted here" — auto-
 *                 deleting on export could drop the other machine's memories. Run
 *                 prune consciously right after deleting live memories.
 *
 * Conflict model (per file): 3-way using the manifest hash as the common base.
 *   - only snapshot changed  -> snapshot wins (copy into live)
 *   - only live changed       -> live wins (keep live)
 *   - both changed (DIVERGED) -> keep BOTH: write snapshot copy as <name>.incoming.md
 *                                into live and flag; never overwrite -> no data loss.
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
function loadManifest() {
  try { return JSON.parse(fs.readFileSync(manifestPath, 'utf8')); }
  catch (e) { return { files: {}, lastSync: null }; }
}
function saveManifest(m) {
  m.lastSync = nowISO();
  fs.mkdirSync(snapshotDir, { recursive: true });
  fs.writeFileSync(manifestPath, JSON.stringify(m, null, 2) + '\n');
}

function doExport() {
  const live = liveDir();
  if (!fs.existsSync(live)) { log(`[memory-sync] no live memory dir (${live}); nothing to export`); return; }
  fs.mkdirSync(snapshotDir, { recursive: true });
  const m = loadManifest();
  let changed = 0;
  for (const name of listMd(live)) {
    const content = readFileSafe(path.join(live, name));
    if (content == null) continue;
    const h = sha(content);
    const prev = m.files[name];
    if (!prev || prev.hash !== h) {
      fs.writeFileSync(path.join(snapshotDir, name), content);
      m.files[name] = { hash: h, updated: nowISO() };
      changed++;
      log(`[memory-sync] export: ${name}`);
    } else if (!fs.existsSync(path.join(snapshotDir, name))) {
      fs.writeFileSync(path.join(snapshotDir, name), content); // restore missing snapshot copy
    }
  }
  saveManifest(m);
  log(`[memory-sync] export done (${changed} file(s) updated)`);
}

function doImport() {
  const live = liveDir();
  fs.mkdirSync(live, { recursive: true });
  const m = loadManifest();
  let copied = 0, kept = 0, conflicts = 0;
  for (const name of listMd(snapshotDir)) {
    const snapContent = readFileSafe(path.join(snapshotDir, name));
    if (snapContent == null) continue;
    const snapHash = sha(snapContent);
    const livePath = path.join(live, name);
    const liveContent = readFileSafe(livePath);
    const base = m.files[name];

    if (liveContent == null) {
      fs.writeFileSync(livePath, snapContent);
      m.files[name] = { hash: snapHash, updated: nowISO() };
      copied++; log(`[memory-sync] import (new): ${name}`); continue;
    }
    const liveHash = sha(liveContent);
    if (liveHash === snapHash) { m.files[name] = { hash: snapHash, updated: (base && base.updated) || nowISO() }; continue; }

    const snapChanged = !base || base.hash !== snapHash;
    const liveChanged = !base || base.hash !== liveHash;
    if (snapChanged && !liveChanged) {
      fs.writeFileSync(livePath, snapContent);
      m.files[name] = { hash: snapHash, updated: nowISO() };
      copied++; log(`[memory-sync] import (incoming wins): ${name}`);
    } else if (!snapChanged && liveChanged) {
      kept++; log(`[memory-sync] keep local (local newer): ${name}`);
    } else {
      const inc = path.join(live, name.replace(/\.md$/, '.incoming.md'));
      fs.writeFileSync(inc, snapContent);
      conflicts++; log(`[memory-sync] CONFLICT: ${name} -> kept local + wrote ${path.basename(inc)} (reconcile manually)`);
    }
  }
  saveManifest(m);
  log(`[memory-sync] import done (${copied} copied, ${kept} kept-local, ${conflicts} conflict(s))`);
  if (conflicts) log(`[memory-sync] ${conflicts} conflict(s): review *.incoming.md in ${live}`);
}

function doStatus() {
  const live = liveDir();
  const m = loadManifest();
  const names = new Set([...listMd(live), ...listMd(snapshotDir)]);
  log(`live:     ${live}`);
  log(`snapshot: ${snapshotDir}`);
  log(`lastSync: ${m.lastSync || '(never)'}`);
  log('--- per file ---');
  for (const name of [...names].sort()) {
    const lc = readFileSafe(path.join(live, name));
    const sc = readFileSafe(path.join(snapshotDir, name));
    const base = m.files[name];
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
  let removed = 0;
  for (const name of listMd(snapshotDir)) {
    if (!fs.existsSync(path.join(live, name))) {
      fs.unlinkSync(path.join(snapshotDir, name));
      delete m.files[name];
      removed++;
      log(`[memory-sync] prune: ${name} (no live counterpart)`);
    }
  }
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
  if (cmd === 'export') doExport();
  else if (cmd === 'import') doImport();
  else if (cmd === 'status') doStatus();
  else if (cmd === 'push') doPush();
  else if (cmd === 'pull') doPull();
  else if (cmd === 'prune') doPrune();
  else log(`[memory-sync] unknown command: ${cmd} (use export|import|status|push|pull|prune)`);
} catch (e) {
  log('[memory-sync] error: ' + (e && e.message)); // never throw out of a hook
}
process.exit(0);
