#!/usr/bin/env bats
# Drift & compliance regression guard for the dependabot-rebase thin caller stub.
#
# .github/workflows/dependabot-rebase.yml is copied VERBATIM from the canonical
# org template (petry-projects/.github → standards/workflows/dependabot-rebase.yml)
# and must stay byte-identical across every adopting repo, modulo the per-repo
# channel pin on the `uses:` ref. Any other diff is drift — the silent-revert
# class of failure the fleet stub-drift monitor exists to catch (fleet_stub_drift.sh).
#
# The stub's behavior lives entirely in the central reusable; its `uses:` ref,
# trigger events, concurrency group, job `permissions:` block, and secrets block
# are drift-protected and MUST NOT be edited in the caller (see the file's own
# "AGENTS — READ BEFORE EDITING" banner and ci-standards.md → Reusable workflow
# versioning). This guard pins those invariants so drift is caught in CI rather
# than in production run health. NOTE: this guard cannot catch transient upstream
# failures (e.g. an api.github.com/graphql 504 inside the reusable's merge step) —
# those are hardened in the central reusable, not in this caller stub.

STUB="${BATS_TEST_DIRNAME}/../.github/workflows/dependabot-rebase.yml"

@test "dependabot-rebase stub exists" {
  [ -f "$STUB" ]
}

@test "dependabot-rebase stub is byte-identical to the canonical template" {
  # Inline canonical snapshot — update this heredoc whenever the central template
  # (petry-projects/.github/standards/workflows/dependabot-rebase.yml) changes.
  local canon
  canon="$(mktemp)"
  # The committed stub has NO trailing newline — unlike pr-review-mention.yml
  # which ships with one — so emit the heredoc with its trailing newline
  # stripped (printf '%s') to stay byte-faithful to the committed, production stub
  # that the fleet stub-drift monitor compares SHAs against.
  printf '%s' "$(cat << 'CANONICAL'
# ─────────────────────────────────────────────────────────────────────────────
# SOURCE OF TRUTH: petry-projects/.github/standards/workflows/dependabot-rebase.yml
# Standard:        petry-projects/.github/standards/dependabot-policy.md
# Reusable:        petry-projects/.github/.github/workflows/dependabot-rebase-reusable.yml
#
# AGENTS — READ BEFORE EDITING:
#   • This file is a THIN CALLER STUB. All rebase/merge serialization logic
#     lives in the reusable workflow above.
#   • You MUST NOT change: the `uses:` ref — it is pinned to the
#     `dependabot-rebase/v2-stable` channel, a moving tag advanced centrally.
#     Never repoint it to `@main`, a SHA, or a frozen `@vX` (see
#     ci-standards.md → Reusable workflow versioning). Also do not change the
#     concurrency group name, the explicit secrets
#     block, or the job-level `permissions:` block — reusable workflows can be
#     granted no more permissions than the calling job has, so removing the
#     stanza breaks the reusable's gh API calls. Do not remove any trigger
#     (`push` keeps the self-sustaining chain; `schedule` is the safety net
#     when no PR merges have occurred recently; `workflow_dispatch` allows
#     manual queue flushes).
#   • If you need different behaviour, open a PR against the reusable in the
#     central repo.
# ─────────────────────────────────────────────────────────────────────────────
#
# Dependabot update-and-merge — thin caller for the org-level reusable.
# To adopt: copy THIS file (standards/workflows/dependabot-rebase.yml) to
#   .github/workflows/dependabot-rebase.yml in your repo. Do NOT copy
#   .github/workflows/dependabot-rebase.yml from this repo — that file uses a
#   local ref only valid in the source-of-truth repo.
# Required org/repo secrets (inherited):
#   APP_ID         — GitHub App ID with contents:write and pull-requests:write
#   APP_PRIVATE_KEY — GitHub App private key
name: Dependabot update and merge

on:
  push:
    branches:
      - main
  schedule:
    - cron: '0 */4 * * *' # every 4 hours — safety net when no pushes to main trigger the chain
  workflow_dispatch: # allow manual trigger to flush Dependabot PR queue

concurrency:
  group: dependabot-update-and-merge
  cancel-in-progress: false

permissions: {}

jobs:
  dependabot-rebase:
    permissions:
      contents: write   # update-branch via GITHUB_TOKEN (may touch .github/workflows/)
      pull-requests: write  # re-approve PRs after branch update
    uses: petry-projects/.github/.github/workflows/dependabot-rebase-reusable.yml@dependabot-rebase/v2-stable  # NOSONAR(githubactions:S7637) first-party channel ref
    secrets:
      APP_ID: ${{ secrets.APP_ID }}
      APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}
CANONICAL
)" > "$canon"
  run diff -u "$canon" "$STUB"
  rm -f "$canon"
  [ "$status" -eq 0 ] || {
    echo "stub drifted from canonical:"
    echo "$output"
    return 1
  }
}

@test "uses: ref is pinned to the dependabot-rebase/v2-stable channel" {
  grep -qF 'uses: petry-projects/.github/.github/workflows/dependabot-rebase-reusable.yml@dependabot-rebase/v2-stable' "$STUB"
}

@test "uses: ref is not repointed to @main, a SHA, or a frozen @vN" {
  if grep -qE 'dependabot-rebase-reusable\.yml@(main|[0-9a-f]{7,40}|v[0-9]+)' "$STUB"; then
    echo "Error: The uses: ref in $STUB is pointed to a forbidden ref (main, SHA, or frozen vN)." >&2
    echo "It must be pinned to the dependabot-rebase/v2-stable channel." >&2
    return 1
  fi
}

@test "all three trigger events are present" {
  grep -qE '^  push:' "$STUB" || { echo "Missing push trigger"; return 1; }
  grep -qE '^  schedule:' "$STUB" || { echo "Missing schedule trigger"; return 1; }
  grep -qE '^  workflow_dispatch:' "$STUB" || { echo "Missing workflow_dispatch trigger"; return 1; }
}

@test "concurrency group is dependabot-update-and-merge with cancel-in-progress off" {
  grep -qE '^  group: dependabot-update-and-merge$' "$STUB" || { echo "Wrong/missing concurrency group"; return 1; }
  grep -qE '^  cancel-in-progress: false$' "$STUB" || { echo "cancel-in-progress must be false (merges serialize, not cancel)"; return 1; }
}

@test "top-level permissions are locked down to {}" {
  grep -q '^permissions: {}' "$STUB" || { echo "Top-level permissions are not locked down to {}"; return 1; }
}

@test "job grants exactly contents: write + pull-requests: write and forwards named secrets" {
  grep -qE '^      contents: write' "$STUB" || { echo "Missing contents: write permission"; return 1; }
  grep -qE '^      pull-requests: write' "$STUB" || { echo "Missing pull-requests: write permission"; return 1; }
  grep -qF 'APP_ID: ${{ secrets.APP_ID }}' "$STUB" \
    || { echo "Missing APP_ID secret"; return 1; }
  grep -qF 'APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}' "$STUB" \
    || { echo "Missing APP_PRIVATE_KEY secret"; return 1; }
}
