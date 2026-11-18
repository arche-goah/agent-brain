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

// A path as the shell wrote it, in the form node can open (docs/os-traps.md OS-19): on Windows
// `/c/...` becomes `C:/...`, any other `/...` goes through `cygpath -m`; elsewhere unchanged.
function nativePath(p) {
  const s = String(p);
  if (process.platform !== 'win32' || !s.startsWith('/')) return s;
  const m = /^\/([a-zA-Z])(\/|$)(.*)$/.exec(s);
  if (m) return m[1].toUpperCase() + ':/' + m[3];
  try {
    return require('child_process').execFileSync('cygpath', ['-m', s], { stdio: ['ignore', 'pipe', 'ignore'], timeout: 3000 }).toString().trim() || s;
  } catch (e) { return s; }
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

// The quote and runner patterns ranTexts needs (the same as public-text-guard.cjs, which reads them from here).
const QUOTED_RX = /"(?:[^"\\]|\\.)*"|'[^']*'/g;
const RUNS_RX = /\b(?:ba|z|da)?sh\s+(?:-\w+\s+)*-[a-z]*c[a-z]*\b|\beval\b|\$\(|`/;
// What the shell RUNS of a quoted text is read where it runs, not everywhere (2026-11-18, macOS instance, measured
// with the pinned guard: 7 of 14 core fixtures refused on a hand run - one `$(` anywhere in a script turned EVERY
// quoted probe argument (`pr_probe "…" "gh pr create -R o/lab --fill"`) into a command). Read as commands: the body
// of each `$( … )` and each backtick pair, anywhere (also inside double quotes), and the quoted parts of a segment
// whose OWN command is `sh -c` / `eval`. A quoted argument of any other command stays data.
const RUNNER = /\b(?:ba|z|da)?sh\s+(?:-\w+\s+)*-[a-z]*c[a-z]*\b|\beval\b/; // `-c`, also combined (`-lc`, `-ec`)
// The shell's own reading, char by char: nothing runs inside single quotes, a backslash makes the next char text
// (outside single quotes), `$(` and a backtick run their body outside quotes and inside double quotes.
function substitutions(cmd) {
  const out = [];
  let q = '';
  for (let i = 0; i < cmd.length; i++) {
    const c = cmd[i];
    if (q === "'") { if (c === "'") q = ''; continue; }
    if (c === '\\') { i++; continue; }
    if (c === '"') { q = q === '"' ? '' : '"'; continue; }
    if (c === "'" && !q) { q = "'"; continue; }
    if (c === '$' && cmd[i + 1] === '(') {
      let depth = 0, j = i + 1, iq = '';
      for (; j < cmd.length; j++) {
        const d = cmd[j];
        if (iq === "'") { if (d === "'") iq = ''; continue; }
        if (d === '\\') { j++; continue; }
        if (d === '"' || d === "'") { iq = iq === d ? '' : (iq || d); continue; }
        if (iq) continue;
        if (d === '(') depth++;
        else if (d === ')' && --depth === 0) break;
      }
      out.push(cmd.slice(i + 2, j));
      i = j;
    } else if (c === '`') {
      const j = cmd.indexOf('`', i + 1);
      if (j === -1) break;
      out.push(cmd.slice(i + 1, j));
      i = j;
    }
  }
  return out;
}
// The texts the shell runs inside the command: `$( )` / backtick bodies and the quoted text of an `sh -c` / `eval`
// segment. Their published text is read too (review of this PR, the Windows instance 2026-11-18: a named post run
// through `bash -c '…'` or `echo "$(…)"` was judged a write, but its body was read from the outer command only).
function ranTexts(cmd) {
  if (!RUNS_RX.test(cmd)) return [];
  const ran = substitutions(cmd);
  for (const s of require('./shell-segments.cjs').segments(cmd)) if (RUNNER.test(s.replace(QUOTED_RX, '""'))) ran.push(...[...s.matchAll(QUOTED_RX)].map((m) => m[0].slice(1, -1)));
  return ran;
}
function publishedText(cmd, ps, inner = false) {
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
  // what the shell RUNS inside the command is published too (2026-11-18, review of agent-brain #615: a post through
  // `bash -c '…'` or `$( )` passed every gate that reads published text - their body was read from the outer command)
  if (!inner) {
    for (const t of ranTexts(cmd)) {
      const r = publishedText(t, ps, true);
      if (r) { texts.push(...r.texts); files.push(...r.files); }
    }
  }
  return { texts, files: files.map((f) => expandVars(f, cmd) ?? f), spans };
}

// `$VAR` / `${VAR}` in a handed file path, resolved as the shell would: an assignment in the same
// command first, then the environment. null while a variable stays unknown (the caller says so).
// Measured 2026-10-28 (Windows instance of another brain): `--body-file "$S/pr156-comment.md"`
// was read literally, the instance key in the file went unseen and the post was blocked.
function expandVars(f, cmd) {
  let unknown = false;
  const out = String(f).replace(/\$(?:\{(\w+)\}|(\w+))/g, (all, a, b) => {
    const name = a || b;
    const set = [...String(cmd).matchAll(new RegExp(`(?:^|[;&|\\s])${name}=("[^"]*"|'[^']*'|[^\\s;&|]+)`, 'g'))].pop();
    if (set) return unquote(set[1]);
    if (process.env[name] !== undefined) return process.env[name];
    unknown = true;
    return all;
  });
  return unknown ? null : out;
}

function invocations(cmd, ps, prog, subs, verbs) {
  const segs = shellSegments(cmd, ps);
  if (!segs) return null;
  if (!prog) return segs;
  const out = [];
  // the program by its name: a path to it and a Windows `.exe` count (Windows review of #526, 2026-11-13:
  // `gh.exe pr create` and `& "<...>\gh.exe" pr create` were no gh call for any gate reading this)
  const named = (x) => String(x).replace(/\\/g, '/').replace(/^.*\//, '').replace(/\.exe$/i, '') === prog;
  for (const w of segs) {
    const i = w.findIndex(named);
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
    // A value in single quotes is literal; anything else holding $( … ) or backquotes runs code —
    // unless the shell's own escape makes them literal (`\`` and `\$(` in double quotes). Measured
    // 2026-10-28: a PR comment quoting "\`bash scripts/<lint>.sh\`" in double quotes kept its body,
    // and a foreground rule fired on the quoted script name.
    const literal = /^'[\s\S]*'$/.test(raw.replace(/^--?[\w-]+=/, ''));
    // PowerShell has no backslash escape (its escape is the backquote itself): there it stays.
    if (/\$\(|`/.test(ps ? raw : raw.replace(/\\[\s\S]/g, '')) && !literal) continue;
    out = out.slice(0, a) + '<MESSAGE-STRIPPED>' + out.slice(b);
  }
  return out;
}

// The local shell scripts a command RUNS, read one level deep: `bash|sh|zsh <file> …` and a path
// run directly (`./x.sh`, `dir/x`) whose first line is a shell shebang. Measured 2026-11-12, on both
// instances: a `gh pr comment` inside a script started as `bash <file>` reached GitHub past the text
// gates - they read only the outer command. Windows: two comments with a home-path placeholder, the
// repo's text-leaks workflow went red; macOS: `bash <scratch>/fixed-note.sh <sha>` posted nine.
// Returns [{ file, text, why }]: `text` null when the script cannot be read (`why` says so); a path
// that does not exist is left out - the shell cannot run it either. Over SCRIPT_MAX: a `bash <file>`
// counts as unreadable, a directly run path is skipped (it may well be a binary).
const SCRIPT_MAX = 200 * 1024;
const SHELL_RX = /^(?:.*[\\/])?(?:ba|z|da|k)?sh(?:\.exe)?$/;
function scriptBodies(cmd, ps, cwd) {
  const segs = shellSegments(cmd, ps);
  if (!segs) return [];
  const fs = require('fs');
  const path = require('path');
  const native = nativePath;
  const out = [];
  for (const w of segs) {
    let i = 0;
    while (i < w.length && /^[A-Za-z_]\w*=/.test(w[i])) i++; // VAR=value prefixes
    let file = null;
    let direct = false;
    if (SHELL_RX.test(w[i] || '')) {
      let j = i + 1;
      for (; j < w.length && /^[-+]/.test(w[j]); j++) if (/^-[a-zA-Z]*c[a-zA-Z]*$/.test(w[j])) { j = w.length; break; } // -c: inline text
      file = w[j] || null;
    } else if (/[\\/]/.test(w[i] || '')) {
      file = w[i];
      direct = true;
    }
    if (!file) continue;
    const v = expandVars(file, cmd);
    if (v === null) { out.push({ file, text: null, why: 'its path holds a shell variable the hook cannot expand' }); continue; }
    const p = path.resolve(cwd || '.', native(v.replace(/^~(?=$|[\\/])/, require('os').homedir())));
    let st;
    try { st = fs.statSync(p); } catch (e) {
      if (e.code !== 'ENOENT' && e.code !== 'ENOTDIR') out.push({ file, text: null, why: e.code || 'cannot be read' });
      continue;
    }
    if (!st.isFile()) continue;
    if (st.size > SCRIPT_MAX) { if (!direct) out.push({ file, text: null, why: `larger than ${SCRIPT_MAX} bytes` }); continue; }
    let text;
    try { text = fs.readFileSync(p, 'utf8'); } catch (e) { out.push({ file, text: null, why: e.code || 'cannot be read' }); continue; }
    if (direct && !/^#!\s*\S*?(?:\/env\s+)?(?:ba|z|da|k)?sh\b/.test(text)) continue;
    out.push({ file, text, why: '' });
  }
  return out;
}

// The operator's half of a question-tool answer. The harness writes `"<the AI's question>"="<the chosen label>"`
// pairs; the left half is the AI's own text. Windows review 2026-11-12: conditional-order-gate lost the answer to its
// quote stripper, mechanism-guard took the question text as the operator's word. Answer halves joined by newlines,
// '' when the text has no pair.
const ANSWER_PAIR = /"(?:[^"\\]|\\.)*"="((?:[^"\\]|\\.)*)"/g;
function answerHalves(text) {
  return [...String(text || '').matchAll(ANSWER_PAIR)].map((m) => m[1]).join('\n');
}

module.exports = { shellSegments, publishedText, ranTexts, substitutions, invocations, withoutPublished, unquote, expandVars, nativePath, answerHalves, scriptBodies };
