- **Settings template: everyday collaboration needs no permission dialog; pushes that name `main` and settings edits still ask; force pushes and `--delete` are denied.** (test: T1)

  **Why (measured 2026-10-16 on a collaborator's brain, core v1.3.41; v1.4.4 has the same template):** every commit and push raised a dialog the human did not understand ("why do you ask me the bash command?"), and the AI read push as "needs the operator". That is one of the main causes of an instance that asks before every step. The template put `git push*` under `ask` and had no rule for `gh pr`.

  **allow:**
  - `git push*`, `git -C * push*`;
  - `git -C * add/commit/status/log/diff*`, `git [-C *] pull --ff-only*`;
  - the everyday `gh pr` verbs (`view list diff checks comment review create edit ready checkout close`);
  - `gh issue *`, `gh run list/view*`.

  **ask:** settings edits (`settings.json`, `settings.local.json`, `.mcp.json`), and a push that names `main` or `HEAD:main` (also with `-C`).

  **deny:** `--force`, `-f`, `+ref` and `--delete`, also with `-C`.

  **No rule on purpose:**
  - `gh pr merge` — the classifier and `mechanism-guard` decide merges.
  - a `:ref` delete — a pattern ending in `:*` is read as the legacy prefix form, so it cannot be written safely; this spelling is a known gap, named in the `_comment`.

  The review on Windows found the first version's three gaps (main push ALLOW, `gh pr *` covering merge, `+ref` / `:ref` / `--delete` passing). A probe with `autonomy-diagnose.py`'s matcher over 22 commands now gives the intended verdict for each.

  **Existing brains do not pick this up** (the template is read at bootstrap). A human edits `.claude/settings.json`; the AI may not grant itself permissions.
