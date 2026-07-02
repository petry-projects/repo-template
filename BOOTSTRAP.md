# Bootstrap a new repo from this template

This template ships the org baseline: the thin-caller workflow stubs (pinned to
their published `@<name>/stable` channel tags) and the root/baseline files. Most
of it works out of the box. Two things are **per-stack** and must be picked once,
after you create your repo from the template:

## 1. Pick your Dependabot stack

`.github/dependabot.yml` ships with the `frontend` (npm) stack by default.
Replace it with the stack that matches your project — the canonical stacks live
in `petry-projects/.github` under `standards/dependabot/<stack>.yml`. Available
stacks: `frontend` (npm), `backend-go`, `backend-python`, `backend-rust`,
`fullstack` (npm + Go + Terraform), and `infra-terraform`.

## 2. Customize `ci.yml` for your stack

`.github/workflows/ci.yml` ships as a documented **customize-per-stack stub**.
It runs the stack-agnostic checks out of the box; add your build/test/lint steps
for your language and toolchain. (The single-template default keeps one `ci.yml`
that you tailor; per-stack `ci.yml` variants remain an advisory open question and
are not required to start.)

## 3. Set up the SonarCloud project

The `sonarcloud` workflow is guarded on `SONAR_TOKEN`, so it is a green no-op
until the token is present. Once the org-wide `SONAR_TOKEN` is visible to the
repo, the scan runs — and it will **fail** (`Could not find the project` /
`...pullrequest`) until the SonarCloud project actually exists. Provision it:

1. **Match the keys in `sonar-project.properties`** to your repo:
   ```
   sonar.projectKey=petry-projects_<repo-name>
   sonar.organization=petry-projects
   ```
   (`sonar.sources` / `sonar.tests` / language settings are per-stack.)

2. **Import the project in SonarCloud.** In <https://sonarcloud.io>, open the
   **petry-projects** organization → **Analyze new project** → select the repo.
   Confirm the generated project key equals `petry-projects_<repo-name>`.

3. **Use CI-based analysis, not Automatic Analysis.** The `sonarcloud` workflow
   runs the scanner itself, which conflicts with SonarCloud's Automatic Analysis.
   In the project's **Administration → Analysis Method**, turn **Automatic
   Analysis OFF** (CI-based). Leaving both on causes "you can't analyze with both"
   errors.

4. **Confirm `SONAR_TOKEN` is available to the repo.** It is provided org-wide;
   if a repo can't see it, add a repo secret `SONAR_TOKEN` (a SonarCloud token
   from **My Account → Security**).

5. **Set the New Code definition / quality gate** for the project (org default
   is fine for most repos).

6. **Re-run** the `SonarCloud` job (push, or re-run the workflow). The required
   `SonarCloud` status check should now pass. Until this is done, `SonarCloud` is
   a required check that fails for non-admins (org-admins bypass via the
   `code-quality` ruleset).

---

## What this template does NOT do

Two onboarding questions are resolved here so they are not left implicit:

- **Framework subtrees (`frameworks/`) are opt-in — they are not seeded by this
  template.** The agentic frameworks (`bmad-method`, `spec-kit`, `gsd`) are
  `git subtree` development tooling maintained in `petry-projects/.github-private`;
  a product repo does not need them on day 0. If your project uses one, add it on
  demand with `git subtree add` against its upstream — see that repo's `AGENTS.md`.

- **App installs (Claude, CodeRabbit) are a manual org-admin step — the bootstrap
  does not install them.** `bootstrap-new-repo.sh` runs as `GITHUB_TOKEN` and
  cannot install org GitHub Apps; installation is a one-time org-level action by an
  org admin. The bootstrap only *disables those apps' check-suite auto-trigger* on
  the new repo (so queued-but-never-completed suites never block auto-merge),
  assuming the apps are already installed org-wide.

---

The rest — CODEOWNERS, AGENTS.md/CLAUDE.md pointers, LICENSE, SECURITY.md,
.gitignore — is ready as shipped. Repo settings, rulesets, labels, and security
configuration are applied separately by the org `bootstrap-new-repo.sh` flow.
