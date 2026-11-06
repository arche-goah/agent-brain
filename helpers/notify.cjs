#!/usr/bin/env node
/**
 * Cross-platform notification sound (best-effort, never fails the hook).
 * macOS: afplay; Linux: paplay/aplay/canberra, else terminal bell; Windows: PowerShell beep.
 * Falls back to writing a BEL to stderr so it works even with no audio tooling.
 */
const os = require('os');
const { spawn, spawnSync } = require('child_process');

// Windows: the hook waits for the beep. Measured 2026-11-02 on the Windows instance: a PowerShell child
// spawned and unref'd - with or without `detached` - wrote nothing (0/3 each) once node exited at once;
// the same child with the parent waiting wrote its file. The environment ends the children with the
// parent, so the sound never played. The beep is ~0.3 s; the timeout bounds a slow PowerShell start.
// NOTIFY_WIN_CMD (fixture seam): a command line run in place of the beep, to prove it runs to its end.
function runAndWait(cmd, args) {
  try { spawnSync(cmd, args, { stdio: 'ignore', windowsHide: true, timeout: 5000 }); } catch (e) { /* best effort */ }
}

function tryRun(cmd, args) {
  try {
    const p = spawn(cmd, args, { stdio: 'ignore', detached: true });
    p.on('error', () => {}); // swallow "command not found"
    p.unref();
    return true;
  } catch (e) {
    return false;
  }
}

const platform = os.platform();

// The fixture seam comes before the platform: on macOS the darwin branch ran first and the
// seam was never reached (measured 2026-11-03 by the macOS instance, test-notify.sh red there).
if (process.env.NOTIFY_WIN_CMD) {
  runAndWait(process.execPath, ['-e', process.env.NOTIFY_WIN_CMD]);
} else if (platform === 'darwin') {
  tryRun('afplay', ['/System/Library/Sounds/Ping.aiff']);
} else if (platform === 'win32') {
  runAndWait('powershell', ['-NoProfile', '-c', '[console]::beep(800,150); [console]::beep(1000,150)']);
} else {
  // Linux / other: try common players, all best-effort.
  const sound = '/usr/share/sounds/freedesktop/stereo/complete.oga';
  tryRun('paplay', [sound]) ||
    tryRun('canberra-gtk-play', ['-i', 'complete']) ||
    tryRun('aplay', ['-q', '/usr/share/sounds/alsa/Front_Center.wav']);
}

// Always emit a terminal bell as a guaranteed fallback.
process.stderr.write('\x07');
process.exit(0);
