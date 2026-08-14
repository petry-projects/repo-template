#!/usr/bin/env bats
# Drift & compliance regression guard for the auto-rebase thin caller stub.
#
# .github/workflows/auto-rebase.yml is copied VERBATIM from the canonical org
# template (petry-projects/.github → standards/workflows/auto-rebase.yml) and must
# stay byte-identical across every adopting repo. The `uses:` ref is pinned to the
# `auto-rebase/v2-stable` channel — the only permitted channel; never repoint it to
# a bare `auto-rebase/stable`, @main, a SHA, or a frozen @vN. Any other diff is
# drift — the silent-revert class of failure the fleet stub-drift monitor exists to
# catch (fleet_stub_drift.sh).
#
# The stub's behavior lives entirely in the central reusable; its `uses:` ref,
# trigger events, concurrency group, job `permissions:` block, and
# `secrets: inherit` stanza are drift-protected and MUST NOT be edited in the
# caller (see the file's own "AGENTS — READ BEFORE EDITING" banner and
# ci-standards.md → Reusable workflow versioning).
#
# The reusable requires `secrets: inherit` so GITHUB_TOKEN and any org secrets
# are forwarded automatically (S7635 suppressed with NOSONAR — first-party
# trusted reusable).

STUB="${BATS_TEST_DIRNAME}/../.github/workflows/auto-rebase.yml"

@test "auto-rebase stub exists" {
  [ -f "$STUB" ]
}

@test "uses: ref is pinned to the auto-rebase/v2-stable channel" {
  grep -qF 'uses: petry-projects/.github/.github/workflows/auto-rebase-reusable.yml@auto-rebase/v2-stable' "$STUB"
}

@test "uses: ref is not repointed to bare stable, @main, a SHA, or a frozen @vN" {
  if grep -qE 'auto-rebase-reusable\.yml@(auto-rebase/stable([^/]|$)|main|[0-9a-f]{7,40}|v[0-9]+)' "$STUB"; then
    echo "Error: The uses: ref in $STUB is pointed to a forbidden ref (bare stable, main, SHA, or frozen vN)." >&2
    echo "It must be pinned to the auto-rebase/v2-stable channel." >&2
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

@test "stub uses secrets: inherit (first-party trusted reusable)" {
  grep -qE '^    secrets:[[:space:]]+inherit' "$STUB" || {
    echo "Error: $STUB must use 'secrets: inherit' — the reusable is a first-party trusted workflow." >&2
    return 1
  }
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
#     `auto-rebase/v2-stable` channel, a moving tag advanced centrally. Never
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
# By default the reusable updates *every* behind PR (`eligibility: all`). The
# `eligibility` input is a tunable extension point for future modes; to select
# one, pass it to the reusable, e.g.:
#
#   with:
#     eligibility: all  # default — update every behind PR
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
    uses: petry-projects/.github/.github/workflows/auto-rebase-reusable.yml@auto-rebase/v2-stable  # NOSONAR(githubactions:S7637) first-party channel ref
    secrets: inherit  # NOSONAR(githubactions:S7635) first-party trusted reusable
CANONICAL
)" > "$canon"
  run diff -u -- "$canon" "$STUB"
  rm -f "$canon"
  [ "$status" -eq 0 ] || {
    echo "stub drifted from canonical: $output"
    return 1
  }
}
