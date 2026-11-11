- **CI: node and shellcheck come from the runner image, apt only when missing** (test: the CI run of this PR, `node --version` and `shellcheck --version` print the image's tools) (level: writer; higher: design — pinning both tools through a setup action would add a version to keep current while the image already ships them; debt: none)
  Measured 2026-11-11: the `helpers parse` step went red twice on one day (runs 43033807933 and 43036724559) from
  "Temporary failure resolving 'security.ubuntu.com'" while apt fetched a nodejs the runner already has. The same
  apt line stood in the shellcheck job.
