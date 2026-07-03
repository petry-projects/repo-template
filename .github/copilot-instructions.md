# Copilot Instructions — repo-template

## About

`repo-template` is the org baseline scaffold for new `petry-projects` repositories:
click **Use this template** to create a repo pre-wired with the standard workflow
stubs and baseline files. Its "code" is GitHub Actions workflows, Bash automation
scripts, and Markdown docs — there is no application runtime. The workflow stubs and
baseline files are a distribution artifact of the org standards in
[`petry-projects/.github`](https://github.com/petry-projects/.github) (`standards/`)
and are regenerated from there.

## Tech Stack

- **Runtime:** None — this is a template/scaffold repo, not a deployable application.
- **Automation:** Bash (POSIX-ish, `bash` shebangs, `set -euo pipefail`) under `.dev-lead/scripts/`.
- **CI / config:** GitHub Actions workflows (YAML) under `.github/workflows/`; Dependabot; SonarCloud.
- **Docs:** Markdown (`AGENTS.md`, `CLAUDE.md`, `BOOTSTRAP.md`, `README.md`, `SECURITY.md`).
- **Tooling:** `shellcheck` (lint), `bats` (shell tests), `python3` + PyYAML (agent-profile
  frontmatter validation), `gh` CLI (workflow automation).

## Project Structure

```
.github/
  workflows/          # Thin-caller workflow stubs (ci, sonarcloud, dependabot-*, dev-lead, …)
  copilot-instructions.md   # This file
  CODEOWNERS
  dependabot.yml      # Per-stack — picked once during bootstrap (see BOOTSTRAP.md)
.dev-lead/
  scripts/            # Bash automation + orchestration (dev-lead engine, release, rebase, …)
    lib/              # Shared shell libraries sourced by the scripts above
AGENTS.md             # Points to org-wide standards in petry-projects/.github
BOOTSTRAP.md          # One-time, per-stack setup steps for repos made from this template
sonar-project.properties  # SonarCloud project key / sources (customize per repo)
```

Baseline workflow stubs (`ci.yml`, `copilot-setup-steps.yml`) ship as **customize-per-stack**
stubs: they pass out of the box and are tailored to each repo's language after creation.

## Local Dev Commands

There is no install/build/dev-run step — the repo has no application dependencies.

- Lint (all):   `bash .dev-lead/scripts/dev-lead-lint.sh`  ← run before finishing any change
- ShellCheck:   `shellcheck --severity=warning -x .dev-lead/scripts/**/*.sh`
- Shell tests:  `bash .dev-lead/scripts/run-bats.sh <test-file.bats> …`
- Preflight:    `bash .dev-lead/scripts/dev-lead-preflight.sh`

## Required Environment Variables

No application secrets are needed for local work. In CI:

- `SONAR_TOKEN`: SonarCloud analysis token — provided org-wide; the `sonarcloud` workflow is a
  green no-op until it is present. Never commit a real token.
- `GITHUB_TOKEN`: provided automatically by GitHub Actions; used by `gh` in the automation
  workflows. Do not hard-code personal access tokens.

## Testing Framework

- Runner: `bats` for Bash scripts, invoked via `.dev-lead/scripts/run-bats.sh` (resilient
  wrapper that skips missing test files and fails only on real test failures).
- Static analysis: `shellcheck` at `--severity=warning` with `-x` (follow sourced files).
- No coverage threshold applies — there is no application code to cover.

## Repo-Specific Overrides

- **Edit the standards, not these copies.** Workflow stubs and baseline files are regenerated
  from `petry-projects/.github` (`standards/`). Changes to the org-wide pattern belong in a PR
  against that repo and are then propagated to the fleet — do not fork the pattern here.
- `ci.yml` ships as a passing placeholder; a real repo replaces the stub step with its stack's
  lint / format / typecheck / test / coverage steps (see `BOOTSTRAP.md`).

## Org Standards

See [petry-projects/.github — AGENTS.md](https://github.com/petry-projects/.github/blob/main/AGENTS.md)
for org-wide development standards.

_No language-specific instruction files are deployed to `.github/instructions/` in this repo, so
the per-language links block is intentionally omitted per the Copilot Instructions Standard._
