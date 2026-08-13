#!/usr/bin/env node
/**
 * Cross-platform notification sound (best-effort, never fails the hook).
 * macOS: afplay; Linux: paplay/aplay/canberra, else terminal bell; Windows: PowerShell beep.
 * Falls back to writing a BEL to stderr so it works even with no audio tooling.
 */
const os = require('os');
const { spawn } = require('child_process');

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

if (platform === 'darwin') {
  tryRun('afplay', ['/System/Library/Sounds/Ping.aiff']);
} else if (platform === 'win32') {
  tryRun('powershell', ['-NoProfile', '-c', '[console]::beep(800,150); [console]::beep(1000,150)']);
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
