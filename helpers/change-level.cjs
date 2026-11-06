#!/usr/bin/env node
/**
 * Every change declares its level (rules/working-rules.md, "Identity is written, state is
 * read"; operator decision 2026-10-19, fixes and features alike). One parser for three users:
 * CI (`check`), the PR gate (`instance-key-gate.cjs` calls `check` before `gh pr create`) and
 * the debt list (`debts`, read by the session start).
 *
 * THE FIELD, inline in a changelog fragment next to `(test: …)`:
 *   (level: <symptom|reader|writer|design>; higher: <level> — <why not> | none; debt: <what stays open> | none)
 * optionally `; settles-debt: <fragment-slug>` — this change builds the higher level that an
 * earlier change named as its debt.
 * The ladder: symptom (the one reported case) · reader (the reader interprets differently) ·
 * writer (the producer writes it down: contract + tool) · design (the object or flow changes
 * so the class cannot arise). `higher` names the level above the chosen one that was seen and
 * why it was not built; `none` only on `design`.
 *
 * WHY: measured 2026-10-19 on the macOS instance — a reader heuristic was rebuilt five times in
 * nine days and the fifth PR still called itself the class fix; the level of a change lived in
 * nobody's text, so no review and no later session could see what had been left open. The
 * field says it at the place the change is written; the debt list brings the open part back.
 *
 * Fragments assembled into CHANGELOG.md keep their slug as `<!-- fragment: <slug> -->`
 * (scripts/changelog-assemble.py), so a debt and its settlement survive the release cut.
 *
 * Usage: node helpers/change-level.cjs check [--root DIR]
 *        node helpers/change-level.cjs debts [--root DIR] [--brief] [--days N]
 * check: exit 0 all fragments carry a valid field, 1 a finding (one line each).
 * debts: lists the open debts oldest first; --brief prints one line only when a debt is older
 * than N days (default 14), else nothing. Exit 0 always.
 */
const fs = require('fs');
const path = require('path');

const LEVELS = ['symptom', 'reader', 'writer', 'design'];
const MARK = /<!--\s*fragment:\s*([\w.-]+)\s*-->/;

// Every `(level: …)` group of a text, parentheses balanced (the reasons may carry their own).
// Inline code is blanked first: a fragment that QUOTES the form (`(level: …)`) is not a field.
function groups(raw) {
  const text = String(raw).replace(/`[^`\n]*`/g, (m) => ' '.repeat(m.length));
  const out = [];
  let at = 0;
  for (;;) {
    const i = text.indexOf('(level:', at);
    if (i < 0) return out;
    let depth = 0;
    let j = i;
    for (; j < text.length; j++) {
      if (text[j] === '(') depth++;
      else if (text[j] === ')' && --depth === 0) break;
    }
    out.push(text.slice(i + 1, j));
    at = j + 1;
  }
}

function parse(inner) {
  const f = {};
  for (const part of inner.split(/;\s*(?=(?:level|higher|debt|settles-debt):)/)) {
    const m = /^(level|higher|debt|settles-debt):\s*([\s\S]*)$/.exec(part.trim());
    if (m) f[m[1]] = m[2].trim();
  }
  return f;
}

// Findings for one field (empty = valid).
function problems(f) {
  const out = [];
  const lvl = (f.level || '').toLowerCase();
  if (!LEVELS.includes(lvl)) out.push(`level "${f.level || ''}" is not one of ${LEVELS.join('|')}`);
  const h = f.higher;
  if (h === undefined) out.push('higher: is missing (the level above that was seen, and why not; or none)');
  else if (/^none\b/i.test(h)) {
    if (LEVELS.includes(lvl) && lvl !== 'design') out.push(`higher: none on level ${lvl} - only design has nothing above it`);
  } else {
    const m = /^(\w+)\s*(?:—|--|-|:)\s*(\S[\s\S]*)$/.exec(h);
    if (!m) out.push(`higher: "${h}" names no reason - write "<level> — <why not>"`);
    else if (!LEVELS.includes(m[1].toLowerCase())) out.push(`higher: "${m[1]}" is not a level`);
    else if (LEVELS.includes(lvl) && LEVELS.indexOf(m[1].toLowerCase()) <= LEVELS.indexOf(lvl)) {
      out.push(`higher: ${m[1]} is not above ${lvl}`);
    }
  }
  if (!f.debt) out.push('debt: is missing (what stays open on this level, or none)');
  return out;
}

function fragmentFiles(root) {
  const d = path.join(root, 'changelog.d');
  try {
    return fs.readdirSync(d).filter((n) => n.endsWith('.md') && n.toLowerCase() !== 'readme.md').sort()
      .map((n) => path.join(d, n));
  } catch (e) {
    return null;
  }
}

function read(p) {
  try { return fs.readFileSync(p, 'utf8'); } catch (e) { return ''; }
}

// Released entries of CHANGELOG.md: { slug, date, text } per bullet that carries a marker or a field.
function released(root) {
  const out = [];
  let date = '';
  let cur = null;
  const flush = () => { if (cur) out.push(cur); cur = null; };
  for (const line of read(path.join(root, 'CHANGELOG.md')).split('\n')) {
    const h = /^## \S+ — (\d{4}-\d{2}-\d{2})/.exec(line);
    if (h) { flush(); date = h[1]; continue; }
    if (/^## /.test(line)) { flush(); date = ''; continue; }
    if (/^- /.test(line)) { flush(); cur = { date, text: line }; continue; }
    if (cur) cur.text += '\n' + line;
  }
  flush();
  for (const e of out) {
    const m = MARK.exec(e.text);
    e.slug = m ? m[1] : '';
  }
  return out;
}

// The fragments a branch adds or changes against its base (the PR gate's scope), or null when the
// base cannot be named (no remote, detached fixture repo) — then the caller checks every fragment.
// Measured 2026-11-06 on the macOS instance, pin v2.1.3: `gh pr create` for a one-file hook PR in a
// suite was held for eleven fragments ALREADY ON THAT SUITE'S MAIN, written before the field's form
// was enforced there; the gate said "a changelog fragment of this PR" and named none of the PR's.
// CI keeps checking the whole folder (`check` without a list): the repo's own debt stays visible.
function changedFragments(root, base) {
  const git = (args) => require('child_process').execFileSync('git', ['-C', root, ...args],
    { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
  let ref = base || '';
  if (!ref) {
    try { ref = git(['symbolic-ref', '-q', '--short', 'refs/remotes/origin/HEAD']).trim(); } catch (e) { ref = ''; }
  }
  for (const r of ref ? [ref] : ['origin/main', 'origin/master']) {
    try { git(['rev-parse', '--verify', '-q', r]); } catch (e) { continue; }
    try {
      const names = new Set(git(['diff', '--name-only', `${r}...HEAD`, '--', 'changelog.d']).split('\n'));
      for (const l of git(['status', '--porcelain', '--untracked-files=all', '--', 'changelog.d']).split('\n')) {
        if (l.length > 3) names.add(l.slice(3).trim());
      }
      return [...names].filter((n) => n.endsWith('.md') && !/readme\.md$/i.test(n))
        .map((n) => path.join(root, n)).filter((p) => fs.existsSync(p));
    } catch (e) { return null; }
  }
  return null;
}

function check(root, only) {
  const all = fragmentFiles(root);
  if (all === null) return { skipped: true, findings: [] };
  const files = Array.isArray(only) ? all.filter((p) => only.some((o) => path.resolve(o) === path.resolve(p))) : all;
  const known = new Set(all.map((p) => path.basename(p, '.md')));
  for (const e of released(root)) if (e.slug) known.add(e.slug);
  const findings = [];
  for (const p of files) {
    const name = path.relative(root, p).replace(/\\/g, '/');
    const gs = groups(read(p));
    if (!gs.length) {
      findings.push(`${name}: no (level: …; higher: …; debt: …) field - every change declares its level`);
      continue;
    }
    for (const g of gs) {
      const f = parse(g);
      for (const pr of problems(f)) findings.push(`${name}: ${pr}`);
      if (f['settles-debt'] && !known.has(f['settles-debt'])) {
        findings.push(`${name}: settles-debt: "${f['settles-debt']}" names no fragment, open or released`);
      }
    }
  }
  return { skipped: false, findings };
}

function debts(root, today) {
  const entries = released(root).map((e) => ({ ...e, where: 'CHANGELOG.md' }));
  for (const p of fragmentFiles(root) || []) {
    let date = '';
    try { date = fs.statSync(p).mtime.toISOString().slice(0, 10); } catch (e) { /* keep empty */ }
    entries.push({ slug: path.basename(p, '.md'), date, text: read(p), where: 'changelog.d' });
  }
  const settled = new Set();
  const open = [];
  for (const e of entries) {
    for (const g of groups(e.text)) {
      const f = parse(g);
      if (f['settles-debt']) settled.add(f['settles-debt']);
      if (f.debt && !/^none\b/i.test(f.debt)) {
        const title = (/\*\*(.+?)\*\*/.exec(e.text) || [, e.text.slice(2, 80)])[1];
        open.push({ slug: e.slug, date: e.date, debt: f.debt, title, where: e.where });
      }
    }
  }
  const t = today || new Date();
  return open.filter((d) => !d.slug || !settled.has(d.slug)).map((d) => ({
    ...d, age: d.date ? Math.floor((t - new Date(d.date + 'T00:00:00Z')) / 86400000) : null,
  })).sort((a, b) => (b.age || 0) - (a.age || 0));
}

function main(argv) {
  const cmd = argv[0];
  const opt = (k, dflt) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] : dflt; };
  const root = path.resolve(opt('--root', path.join(__dirname, '..')));
  if (cmd === 'check') {
    const r = check(root);
    if (r.skipped) { console.log('change-level: no changelog.d/ here - nothing to check'); return 0; }
    if (!r.findings.length) { console.log('change-level: every fragment declares its level'); return 0; }
    r.findings.forEach((f) => console.log('FAIL ' + f));
    console.log('Each change answers four questions: which levels did you see (symptom, reader, writer, design),\n' +
      'which one did you build, why not the next higher one, and what stays open (the debt)?');
    return 1;
  }
  if (cmd === 'debts') {
    const days = Number(opt('--days', '14'));
    const list = debts(root);
    if (argv.includes('--brief')) {
      const old = list.filter((d) => d.age !== null && d.age > days);
      if (old.length) {
        console.log(`open level debts: ${list.length}, ${old.length} older than ${days} days - oldest: ` +
          `${old[0].title} (${old[0].age} d): ${old[0].debt.slice(0, 120)}`);
      }
      return 0;
    }
    if (!list.length) { console.log('change-level: no open debt'); return 0; }
    console.log(`open level debts: ${list.length} (oldest first)`);
    for (const d of list) {
      console.log(`- ${d.age === null ? '?' : d.age} d  ${d.title}  [${d.slug || 'no slug'}, ${d.where}]\n    debt: ${d.debt}`);
    }
    return 0;
  }
  console.error('usage: change-level.cjs check|debts [--root DIR] [--brief] [--days N]');
  return 2;
}

if (require.main === module) process.exit(main(process.argv.slice(2)));

module.exports = { check, changedFragments, debts, parse, problems, groups, LEVELS };
