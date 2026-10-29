#!/usr/bin/env node
const fs = require('fs');
const os = require('os');
const path = require('path');

// Run mode at the right end (operator 2026-10-29: "status-line ... interaktiv / autonom mit klarer signalfarbe"):
// the latch every gate reads, helpers/autonomous-mode.cjs of the session's brain (<project>/core/helpers/ in an
// instance, <project>/helpers/ in the core repo itself). A project without it shows nothing. Labels are instance
// data (`statusline_labels` in .claude/rules/autonomous-patterns.json), English by default. The copy under
// ~/.claude/helpers is refreshed from here by the session start, so a change belongs here, never in the copy.
function runMode(d) {
  try {
    const dir = d.workspace?.project_dir || d.cwd;
    const tp = d.transcript_path;
    if (!dir || !tp) return null;
    const helper = [path.join(dir, 'core', 'helpers', 'autonomous-mode.cjs'), path.join(dir, 'helpers', 'autonomous-mode.cjs')]
      .find((p) => fs.existsSync(p));
    if (!helper) return null;
    let labels = {};
    try { labels = JSON.parse(fs.readFileSync(path.join(dir, '.claude', 'rules', 'autonomous-patterns.json'), 'utf8')).statusline_labels || {}; } catch {}
    // the transcript grows with every message: cache the verdict per size, the full read costs ~0.15 s on 30 MB
    // per session: every session hands its OWN transcript, the cache is keyed by it — five parallel sessions show
    // five modes. A fresh session has no transcript file yet: no on word was said, so it is interactive.
    let size = -1;
    try { size = fs.statSync(tp).size; } catch {}
    const cache = path.join(os.tmpdir(), 'statusline-mode-' + path.basename(tp) + '.json');
    let auto = size < 0 ? false : undefined;
    if (auto === undefined) try { const c = JSON.parse(fs.readFileSync(cache, 'utf8')); if (c.size === size) auto = c.auto; } catch {}
    if (auto === undefined) {
      auto = require(helper).autonomousMode(tp, dir);
      try { fs.writeFileSync(cache, JSON.stringify({ size, auto })); } catch {}
    }
    // Both modes side by side, the active one bold in a 24-bit signal colour (the theme's 16-colour "bright magenta"
    // rendered as a soft red, operator 2026-10-29), the other dim. A click cannot switch: a status-line link only
    // opens a URL, and the mode comes from the operator's words in the transcript, nothing else.
    const dim = (s) => `\x1b[38;2;110;110;110m${s}\x1b[0m`;
    const a = labels.autonomous || 'AUTONOMOUS', i = labels.interactive || 'INTERACTIVE';
    const pair = auto ? `\x1b[1;38;2;199;125;255m${a}\x1b[0m ${dim(i)}`      // neon violet
      : `${dim(a)} \x1b[1;38;2;150;255;190m${i}\x1b[0m`;                    // sage neon
    // No hover tooltip exists for the status line (docs: statusline, "Links": OSC 8 only, Cmd/Ctrl+click). The
    // instance names a page that explains the modes and how to switch (`statusline_labels.help`: a project path or
    // a URL); it gets its own ⓘ link next to the pair.
    const help = labels.help && (/^[a-z]+:\/\//.test(labels.help) ? labels.help : 'file://' + path.resolve(dir, labels.help));
    return help ? `${pair} \x1b]8;;${help}\x07\x1b[1;38;2;140;200;255mⓘ\x1b[0m\x1b]8;;\x07` : pair;
  } catch { return null; }
}

let raw = '';
process.stdin.on('data', c => raw += c);
process.stdin.on('end', () => {
  let d = {};
  try { d = JSON.parse(raw); } catch {}

  const model = d.model?.display_name || '?';
  const parts = [`\x1b[36m${model}\x1b[0m`];

  const fmtReset = (epoch) => {
    if (!epoch) return '';
    let s = Math.max(0, epoch - Math.floor(Date.now() / 1000));
    const dDays = Math.floor(s / 86400); s %= 86400;
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    if (dDays > 0) return `${dDays}d ${h}h`;
    if (h > 0) return `${h}h ${m}m`;
    return `${m}m`;
  };

  const color = (rem) => rem <= 10 ? '\x1b[31m' : rem <= 30 ? '\x1b[33m' : '\x1b[32m';

  const win = (label, w) => {
    if (!w || w.used_percentage == null) return;
    const rem = Math.max(0, 100 - w.used_percentage);
    parts.push(`${label}: ${color(rem)}${rem.toFixed(0)}% left\x1b[0m (reset ${fmtReset(w.resets_at)})`);
  };

  win('5h', d.rate_limits?.five_hour);
  win('7d', d.rate_limits?.seven_day);

  const ctx = d.context_window?.used_percentage;
  if (ctx != null) parts.push(`Ctx ${Math.floor(ctx)}%`);

  const mode = runMode(d);
  if (mode) parts.push(mode);

  process.stdout.write(parts.join(' \x1b[90m|\x1b[0m '));
});
