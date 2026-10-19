#!/usr/bin/env node
/**
 * ONE answer to "what does this shell command publish, and which commands does it run?" for
 * every gate that looks at outgoing text — public-text-guard.cjs (names), instance-key-gate.cjs
 * (instance key, change level) and mechanism-guard.cjs (banned shortcuts).
 *
 * WHY (measured 2026-10-19 on the macOS instance): each of the three gates parsed `gh`/`git`
 * commands with its own regexes over the WHOLE command line, and each read text the command
 * only carries as data. The same day: the name guard blocked on a path and on a shell comment;
 * the mechanism guard on a commit message (fixed there on its own); the instance-key gate held
 * a plain `git commit` because its message quoted the PR command. Three gates, one class:
 * command words and message text were not told apart. This module tells them apart once.
 *
 * - shellSegments(cmd, ps): the command as the shell reads it — one word array per segment,
 *   each array carrying `.spans` ([start, end) of every word in `cmd`, quotes included).
 * - publishedText(cmd, ps): { texts, files, spans } — what reaches GitHub (flag and field
 *   values, the gh api endpoint, the commit message), the files handed over as text, and
 *   where in `cmd` the text values stand.
 * - invocations(cmd, ps, prog, subs, verbs): the segments that RUN a program (and subcommand);
 *   a program name inside a quoted message is part of one word and never counts.
 * - withoutPublished(cmd, ps): `cmd` with every published TEXT value blanked, everything else
 *   left byte for byte — for gates whose rules are regexes over the raw command. A value that
 *   can execute (`$(…)`, backquotes) stays.
 * Each returns null when the command cannot be read to the end (a heredoc, an unbalanced
 * quote): the caller falls back to its old whole-line reading — unsure means stricter.
 * PowerShell (`ps`) has no backslash escape: there a `\` is a path separator, as it is inside
 * bash double quotes unless it precedes `$`, a backquote, `"`, `\` or a newline.
 */

function unquote(s) {
  return s.replace(/^(['"])(.*)\1$/, '$2');
}

function shellSegments(cmd, ps) {
  const segs = [Object.assign([], { spans: [] })];
  let word = null; // null = between words
  let start = -1;
  let q = '';
  const cur = () => segs[segs.length - 1];
  const begin = (i) => { if (word === null) { word = ''; start = i; } };
  const push = (end) => {
    if (word !== null) { cur().push(word); cur().spans.push([start, end]); }
    word = null;
  };
  const next = () => segs.push(Object.assign([], { spans: [] }));
  for (let i = 0; i < cmd.length; i++) {
    const c = cmd[i];
    if (q === "'") { if (c === "'") q = ''; else word += c; continue; }
    if (c === '\\' && !ps && (!q || /[$`"\\\n]/.test(cmd[i + 1] || ''))) {
      begin(i);
      word += cmd[i + 1] || '';
      i++;
      continue;
    }
    if (c === '$' && cmd[i + 1] === '(') {
      let depth = 0;
      let j = i;
      for (; j < cmd.length; j++) {
        if (cmd[j] === '(') depth++;
        else if (cmd[j] === ')' && --depth === 0) break;
      }
      if (j >= cmd.length || /<</.test(cmd.slice(i, j))) return null;
      begin(i);
      word += cmd.slice(i, j + 1);
      i = j;
      continue;
    }
    if (q === '"') { if (c === '"') q = ''; else word += c; continue; }
    if (c === "'" || c === '"') { begin(i); q = c; continue; }
    if (c === '<' && cmd[i + 1] === '<') return null; // heredoc / here-string
    if (c === '#' && word === null) {
      while (i < cmd.length && cmd[i] !== '\n') i++;
      next();
      continue;
    }
    if (c === '\n' || /[;&|()]/.test(c)) { push(i); next(); continue; }
    if (/\s/.test(c)) { push(i); continue; }
    begin(i);
    word += c;
  }
  if (q) return null;
  push(cmd.length);
  return segs.filter((s) => s.length);
}

const GH_TEXT = new Set(['--title', '-t', '--body', '-b', '--notes', '-n', '--subject', '--message', '-m']);
const GH_FIELD = new Set(['-f', '--raw-field', '--field']);
const GH_FILE = new Set(['--body-file', '--notes-file', '--input', '--file']);

function publishedText(cmd, ps) {
  const segs = shellSegments(cmd, ps);
  if (!segs) return null;
  const texts = [];
  const files = [];
  const spans = [];
  // `$(cat <file>)` hands a file over; any other `$(...)` is unknown and stays text to check
  const value = (v, span) => {
    texts.push(v.replace(/\$\(\s*cat\s+("[^"]+"|'[^']+'|[^)\s]+)\s*\)/g,
      (m, f) => { files.push(unquote(f)); return ' '; }));
    if (span) spans.push(span);
  };
  const field = (kv, span) => {
    const at = kv.indexOf('=');
    const v = at < 0 ? kv : kv.slice(at + 1);
    if (v.startsWith('@')) { if (v !== '@-') files.push(v.slice(1)); } else value(v, span);
  };
  for (const w of segs) {
    const sp = w.spans;
    const gh = w.indexOf('gh');
    const git = w.indexOf('git');
    if (gh >= 0 && (git < 0 || gh < git)) {
      const api = w[gh + 1] === 'api';
      for (let i = gh + 1; i < w.length; i++) {
        const a = w[i];
        const eq = a.startsWith('--') ? a.indexOf('=') : -1;
        const flag = eq > 0 ? a.slice(0, eq) : a;
        const inline = eq > 0 ? a.slice(eq + 1) : null;
        let at = i;
        const next = () => (inline !== null ? inline : w[at = ++i]);
        let v;
        if (api && i === gh + 2 && !a.startsWith('-')) texts.push(a); // the endpoint names public paths
        else if (GH_TEXT.has(flag)) { if ((v = next()) !== undefined) value(v, sp[at]); }
        else if (GH_FIELD.has(flag)) { if ((v = next()) !== undefined) field(v, sp[at]); }
        else if (flag === '-F') {
          if ((v = next()) === undefined) continue;
          if (api || v.includes('=')) field(v, sp[at]); else if (v !== '-') files.push(v); // gh pr -F = --body-file
        } else if (GH_FILE.has(flag)) { if ((v = next()) !== undefined && v !== '-') files.push(v); }
      }
    } else if (git >= 0) {
      for (let i = git + 1; i < w.length; i++) {
        const a = w[i];
        let v;
        if (a === '-C' || a === '-c') { i++; continue; }
        if (a === '--message' || /^-[a-zA-Z]*m$/.test(a)) { if ((v = w[++i]) !== undefined) value(v, sp[i]); }
        else if (a.startsWith('--message=')) value(a.slice(10), sp[i]);
        else if (/^-m./.test(a)) value(a.slice(2), sp[i]);
        else if (a === '-F' || a === '--file') { if ((v = w[++i]) !== undefined && v !== '-') files.push(v); }
        else if (a.startsWith('--file=')) files.push(a.slice(7));
      }
    }
  }
  return { texts, files, spans };
}

function invocations(cmd, ps, prog, subs, verbs) {
  const segs = shellSegments(cmd, ps);
  if (!segs) return null;
  if (!prog) return segs;
  const out = [];
  for (const w of segs) {
    const i = w.indexOf(prog);
    if (i < 0) continue;
    if (subs && !subs.includes(w[i + 1])) continue;
    if (verbs && !verbs.includes(w[i + 2])) continue;
    out.push(w.slice(i));
  }
  return out;
}

function withoutPublished(cmd, ps) {
  const pub = publishedText(cmd, ps);
  if (!pub) return null;
  let out = cmd;
  for (const [a, b] of [...pub.spans].sort((x, y) => y[0] - x[0])) {
    const raw = cmd.slice(a, b);
    // A value in single quotes is literal; anything else holding $( … ) or backquotes runs code.
    const literal = /^'[\s\S]*'$/.test(raw.replace(/^--?[\w-]+=/, ''));
    if (/\$\(|`/.test(raw) && !literal) continue;
    out = out.slice(0, a) + '<MESSAGE-STRIPPED>' + out.slice(b);
  }
  return out;
}

module.exports = { shellSegments, publishedText, invocations, withoutPublished, unquote };
