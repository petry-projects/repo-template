#!/usr/bin/env bats
# Drift & compliance regression guard for the auto-rebase thin caller stub.
#
# .github/workflows/auto-rebase.yml is copied VERBATIM from the canonical org
# template (petry-projects/.github → standards/workflows/auto-rebase.yml) and must
# stay byte-identical across every adopting repo, modulo the per-repo channel pin
# on the `uses:` ref. Any other diff is drift — the silent-revert class of failure
# the fleet stub-drift monitor exists to catch (fleet_stub_drift.sh).
#
# The stub's behavior lives entirely in the central reusable; its `uses:` ref,
# trigger events, concurrency group, and job `permissions:` block are drift-
# protected and MUST NOT be edited in the caller (see the file's own "AGENTS —
# READ BEFORE EDITING" banner and ci-standards.md → Reusable workflow versioning).
#
# The reusable needs no caller-supplied secrets (GITHUB_TOKEN only), so the stub
# forwards NO `secrets:` block — this satisfies SonarCloud githubactions:S7635
# ("Only pass required secrets to this workflow") without a blanket
# `secrets: inherit`.

STUB="${BATS_TEST_DIRNAME}/../.github/workflows/auto-rebase.yml"

@test "auto-rebase stub exists" {
  [ -f "$STUB" ]
}

@test "uses: ref is pinned to the auto-rebase/stable channel" {
  grep -qF 'uses: petry-projects/.github/.github/workflows/auto-rebase-reusable.yml@auto-rebase/stable' "$STUB"
}

@test "uses: ref is not repointed to @main, a SHA, or a frozen @vN" {
  if grep -qE 'auto-rebase-reusable\.yml@(main|[0-9a-f]{7,40}|v[0-9]+)' "$STUB"; then
    echo "Error: The uses: ref in $STUB is pointed to a forbidden ref (main, SHA, or frozen vN)." >&2
    echo "It must be pinned to the auto-rebase/stable channel." >&2
    return 1
  fi
}

@test "trigger events (push to main + workflow_dispatch) are present" {
  grep -qE '^  push:' "$STUB" || { echo "Missing push trigger"; return 1; }
  grep -qE '^  workflow_dispatch:' "$STUB" || { echo "Missing workflow_dispatch trigger"; return 1; }
}

@test "concurrency group is auto-rebase with cancel-in-progress off" {
  grep -qE '^  group: auto-rebase$' "$STUB" || { echo "Wrong/missing concurrency group"; return 1; }
  grep -qE '^  cancel-in-progress: false$' "$STUB" || { echo "cancel-in-progress must be false"; return 1; }
}

@test "top-level permissions are locked down to {}" {
  grep -q '^permissions: {}' "$STUB" || { echo "Top-level permissions are not locked down to {}"; return 1; }
}

@test "job grants exactly contents: write + pull-requests: write" {
  grep -qE '^      contents: write' "$STUB" || { echo "Missing contents: write permission"; return 1; }
  grep -qE '^      pull-requests: write' "$STUB" || { echo "Missing pull-requests: write permission"; return 1; }
}

@test "stub does not use blanket secrets: inherit (S7635)" {
  if grep -qE '^[[:space:]]*secrets:[[:space:]]+inherit[[:space:]]*$' "$STUB"; then
    echo "Error: $STUB uses 'secrets: inherit'; the reusable needs no caller secrets." >&2
    echo "Remove the secrets block (GITHUB_TOKEN is provided automatically)." >&2
    return 1
  fi
}

@test "stub forwards no secrets block (reusable uses GITHUB_TOKEN only)" {
  if grep -qE '^    secrets:' "$STUB"; then
    echo "Error: $STUB declares a job-level secrets block; none is required." >&2
    return 1
  fi
}

@test "auto-rebase stub is byte-identical to the canonical template" {
  # Inline canonical snapshot — update this heredoc whenever the central
  # template (petry-projects/.github/standards/workflows/auto-rebase.yml) changes.
  # The committed stub has NO trailing newline, so capture via command
  # substitution (strips trailing newlines) + printf '%s' (adds none) to stay
  # byte-faithful to the committed production stub.
  local canon
  canon="$(mktemp)"
  printf '%s' "$(cat << 'CANONICAL'
# ─────────────────────────────────────────────────────────────────────────────
# SOURCE OF TRUTH: petry-projects/.github/standards/workflows/auto-rebase.yml
# Standard:        petry-projects/.github/standards/ci-standards.md
# Reusable:        petry-projects/.github/.github/workflows/auto-rebase-reusable.yml
#
# AGENTS — READ BEFORE EDITING:
#   • This file is a THIN CALLER STUB. All branch-update logic lives in the
#     reusable workflow above.
#   • You MUST NOT change: the `uses:` ref — it is pinned to the
#     `auto-rebase/stable` channel, a moving tag advanced centrally. Never
#     repoint it to `@main`, a SHA, or a frozen `@vX` (see ci-standards.md →
#     Reusable workflow versioning). Also do not change the trigger event,
#     the concurrency group name,
#     or the job-level `permissions:` block — reusable workflows can be
#     granted no more permissions than the calling job has, so removing
#     the stanza breaks the reusable's gh API calls.
#   • If you need different behaviour, open a PR against the reusable in the
#     central repo.
# ─────────────────────────────────────────────────────────────────────────────
#
# Auto-rebase non-Dependabot PRs — thin caller for the org-level reusable.
# To adopt: copy this file to .github/workflows/auto-rebase.yml in your repo.
# No secrets required — uses GITHUB_TOKEN only.
#
# By default the reusable only updates *review-ready* PRs: non-draft AND
# (carrying a current APPROVED review OR the `auto-rebase:ready` label). This
# keeps the workflow from fanning out branch-update CI runs to every behind PR.
# To tune it, pass inputs to the reusable, e.g.:
#
#   with:
#     eligibility: review-ready      # default; or `all` to update every behind PR
#     ready_label: auto-rebase:ready # label that opts a non-draft PR in
#
name: Auto-rebase non-Dependabot PRs

on:
  push:
    branches:
      - main
  workflow_dispatch:

concurrency:
  group: auto-rebase
  cancel-in-progress: false

permissions: {}

jobs:
  auto-rebase:
    permissions:
      contents: write      # update-branch via GITHUB_TOKEN (may touch .github/workflows/)
      pull-requests: write # post comments on PRs
    uses: petry-projects/.github/.github/workflows/auto-rebase-reusable.yml@auto-rebase/stable  # NOSONAR(githubactions:S7637) first-party channel ref
CANONICAL
)" > "$canon"
  run diff -u -- "$canon" "$STUB"
  rm -f "$canon"
  [ "$status" -eq 0 ] || {
    echo "stub drifted from canonical: $output"
    return 1
  }
}
