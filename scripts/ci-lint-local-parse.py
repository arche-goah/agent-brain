"""Read the steps of named jobs from a GitHub Actions workflow — the parser half of
scripts/ci-lint-local.sh (the shell half runs them; Python never starts bash, OS-14).

usage: ci-lint-local-parse.py <workflow.yml> <out-dir> <job> [<job> ...]
Writes each step that has a `run:` to <out-dir>/<n>.sh and prints one line per step:
<n> TAB <job> TAB <step name> TAB run | skip:<why>
Indentation-based, enough for the workflow's shape (jobs: -> <job>: -> steps: -> "- name:" /
"run:" or a "run: |" block). Lines starting with `sudo ` (runner package setup) are dropped.
exit 2 = an unknown job, or no runnable step (the parser no longer matches the file).
"""
import re
import sys


def parse(lines):
    jobs, job, step, in_steps, block, bind = {}, None, None, False, None, 0

    def close():
        nonlocal step
        if job and step is not None:
            jobs[job].append(step)
        step = None

    for ln in lines:
        if block is not None:
            if ln.strip() == "" or len(ln) - len(ln.lstrip()) > bind:
                block.append(ln[bind + 2:] if ln.strip() else "")
                continue
            step["run"] = "\n".join(block).rstrip() + "\n"
            block = None
        m = re.match(r"^  ([\w-]+):\s*$", ln)
        if m:
            close()
            job, in_steps = m.group(1), False
            jobs[job] = []
            continue
        if job is None:
            continue
        if re.match(r"^    steps:\s*$", ln):
            in_steps = True
            continue
        if not in_steps:
            continue
        m = re.match(r"^\s*- (\w[\w-]*):\s*(.*)$", ln)
        if m:
            close()
            step = {"name": "", "run": None, "ctx": False}
            k, v = m.group(1), m.group(2)
            if k == "name":
                step["name"] = v.strip().strip('"')
            elif k == "uses":
                step["name"] = "uses " + v.split("#")[0].strip()
            elif k == "run":
                step["run"] = v.strip() + "\n"
            continue
        if step is None:
            continue
        m = re.match(r"^(\s+)(name|run|env|with):\s*(.*)$", ln)
        if m:
            k, v = m.group(2), m.group(3).strip()
            if k == "name" and not step["name"]:
                step["name"] = v.strip('"')
            elif k == "run" and v in ("|", "|-", ">"):
                block, bind = [], len(m.group(1))
            elif k == "run":
                step["run"] = v + "\n"
            if "${{" in v:
                step["ctx"] = True
            continue
        if "${{" in ln:
            step["ctx"] = True
    if block is not None:
        step["run"] = "\n".join(block).rstrip() + "\n"
    close()
    return jobs


def main(argv):
    if len(argv) < 4:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2
    wf, out, want = argv[1], argv[2], argv[3:]
    # The index is read by the shell half; step names carry non-ASCII (OS-9): pin the encoding.
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
    with open(wf, encoding="utf-8") as f:
        jobs = parse(f.read().splitlines())
    missing = [j for j in want if j not in jobs]
    if missing:
        print("unknown job(s): %s - jobs in the workflow: %s" % (", ".join(missing), ", ".join(jobs)), file=sys.stderr)
        return 2
    n = 0
    for j in want:
        for s in jobs[j]:
            if s["run"] is None:
                continue  # uses: steps (checkout, setup-*) have no local meaning
            n += 1
            why = "skip:reads GitHub context" if s["ctx"] or "${{" in s["run"] else "run"
            body = "\n".join(l for l in s["run"].splitlines() if not l.lstrip().startswith("sudo "))
            with open("%s/%d.sh" % (out, n), "w", encoding="utf-8", newline="\n") as f:
                f.write(body + "\n")
            print("%d\t%s\t%s\t%s" % (n, j, (s["name"] or "(unnamed)").replace("\t", " "), why))
    if n == 0:
        print("no runnable step found - the parser no longer matches the workflow", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
