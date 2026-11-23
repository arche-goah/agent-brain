#!/usr/bin/env python3
"""reader-break-check — a commit must not remove a phrase that a reader greps from that file.

Two readers name a phrase in a file by text: a ledger entry's `check: grep -q "<phrase>" <file>` and a memory entry's
`home: <file> :: <phrase>`. Both fail only later — the ledger check at the next reconcile, the home anchor at the next
memory lint — and a ticked entry then counts as broken. Measured on the macOS instance 2026-11-23: a diet of the
always-loaded files cut two such sentences; the start check found them one session later; a replay over that brain's
history since 2026-09-02 found ten earlier commits on seven days that did the same.

Readers are taken from the STAGED tree (so a commit that rewrites the check together with the sentence passes), the
phrase is compared between HEAD and the staged blob of the read file. Negated checks (`! grep`, `grep -v`) want the
phrase gone and are skipped. Exit 1 lists each break; exit 0 otherwise.

  reader-break-check.py [--root <repo>]
"""
import re
import subprocess
import sys

CHECK = re.compile(r'(?<![!\w-])\s*grep\s+-q[a-zA-Z]*\s+(?:--\s+)?"([^"]{4,})"\s+([\w./-]+)')
NEGATED = re.compile(r'(?:!\s*grep|grep\s+-[a-zA-Z]*v)')
HOME = re.compile(r'^\s*home:\s*(\S+)\s+::\s+(.+?)\s*$')


def git(root, *args):
    r = subprocess.run(['git', '-C', root, *args], capture_output=True, text=True, encoding='utf-8', errors='replace')
    return r.returncode, r.stdout


def blob(root, spec):
    rc, out = git(root, 'show', spec)
    return out if rc == 0 else None


def readers(root):
    # POSIX class, not \s: git grep -E on macOS does not know \s and matched nothing (measured 2026-11-23)
    rc, out = git(root, 'grep', '--cached', '-n', '-I', '-E', r'^[[:space:]]*(check:|home:)', '--', '*.md')
    if rc not in (0, 1):
        return []
    found = []
    for line in out.splitlines():
        where, _, text = line.partition(':')
        num, _, text = text.partition(':')
        src = f'{where}:{num}'
        h = HOME.match(text)
        if h:
            found.append((h.group(1), h.group(2), src))
            continue
        if not text.strip().startswith('check:'):
            continue
        for part in re.split(r'&&|\|\|', text):
            if NEGATED.search(part):
                continue
            m = CHECK.search(part)
            if m:
                found.append((m.group(2), m.group(1), src))
    return found


def main(argv):
    root = argv[argv.index('--root') + 1] if '--root' in argv else '.'
    rc, staged = git(root, 'diff', '--cached', '--name-only', '--diff-filter=MD')
    changed = set(staged.split())
    if not changed:
        return 0
    breaks = []
    for path, phrase, src in readers(root):
        if path not in changed:
            continue
        before = blob(root, f'HEAD:{path}')
        if before is None or phrase not in before:
            continue
        after = blob(root, f':{path}') or ''
        if phrase not in after:
            breaks.append(f'  {path}: "{phrase[:70]}" is read by {src}')
    if not breaks:
        return 0
    print('reader-break: this commit removes a phrase a reader greps from its file:')
    print('\n'.join(breaks))
    print('Keep the phrase, or change the reader in the same commit so it measures the invariant, not the sentence.')
    return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
