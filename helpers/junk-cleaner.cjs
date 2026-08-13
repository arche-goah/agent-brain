#!/usr/bin/env node
/**
 * PostToolUse Hook: Detects and removes junk files from project root.
 * Only removes files <100 bytes matching known junk patterns.
 */
const fs = require('fs');
const path = require('path');

const ROOT = process.env.CLAUDE_PROJECT_DIR || path.join(__dirname, '..', '..');
const junkPatterns = [
  /^[{(,;)}]+$/,          // punctuation-only: {, (, ,, ;, }
  /^\d+$/,                 // number-only: 10
  /^(flex|mb-\d|px-\d|void\)|BigInt|undefined|null|NaN|true|false)$/,
  /\.(count|type|div)$/    // nonsense extensions
];

try {
  const items = fs.readdirSync(ROOT);
  const deleted = [];

  for (const name of items) {
    if (name.startsWith('.') || name === 'node_modules') continue;

    let isJunk = false;
    for (const pattern of junkPatterns) {
      if (pattern.test(name)) { isJunk = true; break; }
    }

    if (isJunk) {
      const full = path.join(ROOT, name);
      try {
        const stat = fs.statSync(full);
        if (stat.isFile() && stat.size < 100) {
          fs.unlinkSync(full);
          deleted.push(name);
        }
      } catch (e) { /* skip */ }
    }
  }

  if (deleted.length > 0) {
    console.log('[CLEANUP] Removed junk files: ' + deleted.join(', '));
  }
} catch (e) { /* non-fatal */ }
