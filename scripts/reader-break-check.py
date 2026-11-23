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

  reader-break-check.py [--root <repo>]                       (the staged commit; the pre-commit hook)
  reader-break-check.py --root <repo> --history <YYYY-MM-DD>  (replay: each commit since then, with its own readers)
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


def readers(root, tree=None):
    """Reader pairs (file, phrase, source) in the staged tree, or in commit `tree` (the history replay)."""
    # POSIX class, not \s: git grep -E on macOS does not know \s and matched nothing (measured 2026-11-23)
    # the tree stands AFTER the pattern (git grep <pattern> <tree>); before it, git read the tree name as the pattern and the
    # history replay judged 4404 commits with no reader at all (measured 2026-11-23)
    where = [tree] if tree else []
    opts = [] if tree else ['--cached']
    rc, out = git(root, 'grep', *opts, '-n', '-I', '-E', r'^[[:space:]]*(check:|home:)', *where, '--', '*.md')
    if rc not in (0, 1):
        return []
    found = []
    for line in out.splitlines():
        if tree and line.startswith(tree + ':'):
            line = line[len(tree) + 1:]
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


def breaks_between(root, changed, before_ref, after_spec, tree=None):
    out = []
    for path, phrase, src in readers(root, tree):
        if path not in changed:
            continue
        before = blob(root, f'{before_ref}:{path}')
        if before is None or phrase not in before:
            continue
        after = blob(root, f'{after_spec}{path}') or ''
        if phrase not in after:
            out.append(f'  {path}: "{phrase[:70]}" is read by {src}')
    return out


def history(root, since):
    """Replay over the repo's history: each commit judged with the readers of ITS tree (parent as HEAD, the commit
    staged), the way the pre-commit hook would have judged it."""
    rc, out = git(root, 'log', '--no-merges', '--format=%h %ad', '--date=short', f'--since={since}')
    rows = [r.split() for r in out.splitlines() if r.strip()]
    hits = []
    for sha, day in rows:
        rc, names = git(root, 'diff', '--name-only', '--diff-filter=MD', f'{sha}~1', sha)
        changed = set(names.split())
        if rc != 0 or not changed:
            continue
        found = breaks_between(root, changed, f'{sha}~1', f'{sha}:', tree=sha)
        if found:
            hits.append((day, sha, found))
    days = {d for d, _, _ in hits}
    readers_n = sum(len(f) for _, _, f in hits)
    print(f'reader-break history since {since}: {len(rows)} commits judged, {len(hits)} held, {readers_n} broken readers, on {len(days)} days')
    for day, sha, found in hits:
        print(f'{day} {sha}')
        print('\n'.join(found))
    return 0


def main(argv):
    root = argv[argv.index('--root') + 1] if '--root' in argv else '.'
    if '--history' in argv:
        return history(root, argv[argv.index('--history') + 1])
    rc, staged = git(root, 'diff', '--cached', '--name-only', '--diff-filter=MD')
    changed = set(staged.split())
    if not changed:
        return 0
    breaks = breaks_between(root, changed, 'HEAD', ':')
    if not breaks:
        return 0
    print('reader-break: this commit removes a phrase a reader greps from its file:')
    print('\n'.join(breaks))
    print('Keep the phrase, or change the reader in the same commit so it measures the invariant, not the sentence.')
    return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
