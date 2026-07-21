#!/usr/bin/env bats
# Drift & compliance regression guard for the dev-lead thin caller stub.
#
# .github/workflows/dev-lead.yml is copied VERBATIM from the canonical org template
# and must stay full-file identical across every adopting repo, modulo the per-repo
# channel pin on the `uses:` ref and its matching `agent_ref`. Any other diff is
# drift — the silent-revert class of failure the fleet stub-drift monitor exists to
# catch (fleet_stub_drift.sh).
#
# The stub's behavior lives entirely in the central reusable; its `uses:` ref,
# trigger events, top-level `permissions:`, and job `permissions:` block are drift-
# protected and MUST NOT be edited in the caller (see the file's own header banner
# and ci-standards.md → Reusable workflow versioning). Secrets are forwarded by
# explicit name rather than `secrets: inherit`, which satisfies SonarCloud
# githubactions:S7635 ("Only pass required secrets to this workflow").

STUB="${BATS_TEST_DIRNAME}/../.github/workflows/dev-lead.yml"

@test "dev-lead stub exists" {
  [ -f "$STUB" ]
}

@test "uses: ref is pinned to the dev-lead/stable channel" {
  grep -qF 'uses: petry-projects/.github-private/.github/workflows/dev-lead-reusable.yml@dev-lead/stable' "$STUB"
}

@test "uses: ref is not repointed to @main, a SHA, or a frozen @vN" {
  if grep -qE 'dev-lead-reusable\.yml@(main|[0-9a-f]{7,40}|v[0-9]+)' "$STUB"; then
    echo "Error: The uses: ref in $STUB is pointed to a forbidden ref (main, SHA, or frozen vN)." >&2
    echo "It must be pinned to the dev-lead/stable channel." >&2
    return 1
  fi
}

@test "agent_ref threads the same dev-lead/stable channel" {
  grep -qE '^      agent_ref: dev-lead/stable$' "$STUB" || { echo "Missing/wrong agent_ref"; return 1; }
}

@test "core trigger events are present" {
  grep -qE '^  pull_request:' "$STUB" || { echo "Missing pull_request trigger"; return 1; }
  grep -qE '^  pull_request_review:' "$STUB" || { echo "Missing pull_request_review trigger"; return 1; }
  grep -qE '^  issue_comment:' "$STUB" || { echo "Missing issue_comment trigger"; return 1; }
  grep -qE '^  issues:' "$STUB" || { echo "Missing issues trigger"; return 1; }
  grep -qE '^  repository_dispatch:' "$STUB" || { echo "Missing repository_dispatch trigger"; return 1; }
}

@test "top-level permissions are locked down to {}" {
  grep -q '^permissions: {}' "$STUB" || { echo "Top-level permissions are not locked down to {}"; return 1; }
}

@test "job permissions block is intact" {
  grep -qE '^      contents: write' "$STUB" || { echo "Missing contents: write permission"; return 1; }
  grep -qE '^      pull-requests: write' "$STUB" || { echo "Missing pull-requests: write permission"; return 1; }
  grep -qE '^      issues: write' "$STUB" || { echo "Missing issues: write permission"; return 1; }
  grep -qE '^      actions: read' "$STUB" || { echo "Missing actions: read permission"; return 1; }
  grep -qE '^      checks: read' "$STUB" || { echo "Missing checks: read permission"; return 1; }
  grep -qE '^      statuses: read' "$STUB" || { echo "Missing statuses: read permission"; return 1; }
}

@test "required and optional secrets are forwarded by explicit name" {
  grep -qF 'CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}' "$STUB" \
    || { echo "Missing required CLAUDE_CODE_OAUTH_TOKEN secret"; return 1; }
  grep -qF 'GH_PAT_WORKFLOWS: ${{ secrets.GH_PAT_WORKFLOWS }}' "$STUB" \
    || { echo "Missing optional GH_PAT_WORKFLOWS secret"; return 1; }
  grep -qF 'GOOGLE_API_KEY: ${{ secrets.GOOGLE_API_KEY }}' "$STUB" \
    || { echo "Missing optional GOOGLE_API_KEY secret"; return 1; }
  grep -qF 'GH_PAT: ${{ secrets.GH_PAT }}' "$STUB" \
    || { echo "Missing optional GH_PAT secret"; return 1; }
}

@test "stub does not use blanket secrets: inherit (S7635)" {
  if grep -qE '^[[:space:]]*secrets:[[:space:]]+inherit[[:space:]]*$' "$STUB"; then
    echo "Error: $STUB uses 'secrets: inherit'; forward the documented secrets by name instead." >&2
    return 1
  fi
}

@test "dev-lead stub is byte-identical to the canonical template" {
  # Inline canonical snapshot — update this heredoc whenever the central
  # template (petry-projects/.github-private → dev-lead.yml) changes.
  # The committed stub has NO trailing newline, so capture via command
  # substitution (strips trailing newlines) + printf '%s' (adds none) to stay
  # byte-faithful to the committed production stub.
  local canon
  canon="$(mktemp)"
  printf '%s' "$(cat << 'CANONICAL'
# ─────────────────────────────────────────────────────────────────────────────
# Dev-Lead Agent — thin caller stub
# Standard:  petry-projects/.github/standards/ci-standards.md#5-dev-lead-agent
# Reusable:  petry-projects/.github-private/.github/workflows/dev-lead-reusable.yml
#
# ADOPTING THIS WORKFLOW:
#   1. Copy this file verbatim to .github/workflows/dev-lead.yml in your repo.
#   2. Ensure CLAUDE_CODE_OAUTH_TOKEN is set as an org or repo secret.
#   3. Optionally set GH_PAT_WORKFLOWS (required if Claude pushes workflow files).
#   4. Optionally set vars.DEV_LEAD_ENGINE = "claude" | "gemini" | "copilot".
#   5. SonarCloud-gated repo? Nothing to do — the `uses:` line below already
#      carries the inline `# NOSONAR(githubactions:S7637)` marker. The ref is a
#      first-party reusable pinned to a moving channel/ring tag, so without the
#      marker SonarCloud's githubactions:S7637 would fail the Quality Gate. The
#      marker travels with this file on copy; no sonar-project.properties entry
#      is needed. See https://github.com/petry-projects/.github/blob/main/standards/ci-standards.md#sonarcloud-exemption-first-party-reusable-ref-s7637.
#
# This stub is copied VERBATIM and is full-file identical across every adopting
# repo, modulo the per-repo ring/channel pin on the `uses:` ref and its matching
# `agent_ref` (below). Any other diff is drift, not a repo-specific liberty:
# `on:`, `permissions:`, and `concurrency:` are NOT repo-adjustable — do not trim
# a trigger, narrow a permission, or add a concurrency block on a PR branch. The
# behavior lives in the reusable, so change it there (or via a standards PR) and
# let the channel tag promote it centrally — never by editing this caller. See
# https://github.com/petry-projects/.github/blob/main/standards/ci-standards.md#centralization-tiers and
# https://github.com/petry-projects/.github/blob/main/standards/ci-standards.md#reusable-workflow-versioning--the-stable-channel.
#
# REQUIRED secrets: CLAUDE_CODE_OAUTH_TOKEN
# OPTIONAL secrets: GH_PAT_WORKFLOWS, GOOGLE_API_KEY, GH_PAT
# ─────────────────────────────────────────────────────────────────────────────

name: Dev-Lead Agent

on:
  pull_request:
    branches: [main]
    types: [opened, reopened, synchronize]
  pull_request_review:
    types: [submitted]
  pull_request_review_comment:
    types: [created]
  issue_comment:
    types: [created]
  issues:
    types: [labeled]
  check_run:
    types: [completed]
  repository_dispatch:
    types: [dev-lead-ci-failure, dev-lead-reviews-retry, dev-lead-issue-retry]

permissions: {}

# Concurrency is centralised in the reusable workflow (dev-lead-reusable.yml) with
# per-issue / per-PR lanes, so issue pickups are never cancelled by PR follow-up
# traffic and the grouping can't drift per-repo. See petry-projects/.github#402.

jobs:
  dev-lead:
    # Pinned to the moving dev-lead/stable channel tag, not @main, so a broken
    # change to dev-lead can no longer gate its own fix (the self-host circular
    # dependency). Promotion is done by moving the dev-lead/stable tag centrally; this
    # caller is never edited on release. agent_ref threads the same channel into
    # dev-lead's own scripts/prompts checkout. See https://github.com/petry-projects/.github/blob/main/standards/ci-standards.md#dev-lead-agent.
    uses: petry-projects/.github-private/.github/workflows/dev-lead-reusable.yml@dev-lead/stable  # NOSONAR(githubactions:S7637) first-party channel ref
    with:
      agent_ref: dev-lead/stable
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
      GH_PAT_WORKFLOWS: ${{ secrets.GH_PAT_WORKFLOWS }}
      GOOGLE_API_KEY: ${{ secrets.GOOGLE_API_KEY }}
      GH_PAT: ${{ secrets.GH_PAT }}
    permissions:
      contents: write
      pull-requests: write
      issues: write
      actions: read
      checks: read
      statuses: read
CANONICAL
)" > "$canon"
  run diff -u -- "$canon" "$STUB"
  rm -f "$canon"
  [ "$status" -eq 0 ] || {
    echo "stub drifted from canonical: $output"
    return 1
  }
}
