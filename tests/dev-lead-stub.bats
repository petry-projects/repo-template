#!/usr/bin/env bats
# Drift & compliance regression guard for the dev-lead thin caller stub.
#
# .github/workflows/dev-lead.yml is copied VERBATIM from the canonical org
# template (petry-projects/.github → standards/workflows/dev-lead.yml) and must
# stay byte-identical across every adopting repo, modulo the per-repo channel/ring
# pin on the `uses:` ref and its MATCHING `agent_ref`. Any other diff is drift —
# the silent-revert class of failure the fleet stub-drift monitor exists to catch
# (fleet_stub_drift.sh).
#
# This guard specifically pins the compliance-audit `dev-lead-stub-agent-ref`
# invariant (ci-standards.md → dev-lead-agent): the stub MUST pass
# `with: agent_ref: dev-lead/v<M>-<channel>` — a MAJOR-SCOPED channel tag
# (e.g. dev-lead/v1-stable), not the unversioned `dev-lead/stable` — so the
# reusable checks out its own scripts/prompts from the same major-scoped channel
# as the `uses:` ref. The bare `dev-lead/stable` form is a compliance failure.

STUB="${BATS_TEST_DIRNAME}/../.github/workflows/dev-lead.yml"

@test "dev-lead stub exists" {
  [ -f "$STUB" ]
}

@test "dev-lead stub is byte-identical to the canonical template" {
  # Inline canonical snapshot — update this heredoc whenever the central template
  # (petry-projects/.github/standards/workflows/dev-lead.yml) changes.
  # The channel pin (e.g. dev-lead/v1-stable, dev-lead/v1-next) is the only
  # permitted per-repo diff; derive it from the stub so the canonical snapshot
  # can be substituted before the byte comparison rather than hardcoding v1-stable.
  local channel
  channel=$(grep 'agent_ref:' "$STUB" | grep -oE 'dev-lead/v[0-9]+[^[:space:]]*' | head -1)
  if [ -z "$channel" ]; then
    echo "Could not extract channel from stub agent_ref" >&2
    return 1
  fi
  local canon
  canon="$(mktemp)"
  # The canonical template ends with a single trailing newline, so reconstruct it
  # with printf '%s\n' (command substitution strips the heredoc's trailing newline,
  # which printf then restores) to stay byte-faithful to the committed stub the
  # fleet stub-drift monitor compares SHAs against.
  printf '%s\n' "$(cat << 'CANONICAL'
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
    # Pinned to the moving dev-lead/v1-stable channel tag, not @main, so a broken
    # change to dev-lead can no longer gate its own fix (the self-host circular
    # dependency). Promotion is done by moving the dev-lead/v1-stable tag centrally; this
    # caller is never edited on release. agent_ref threads the same channel into
    # dev-lead's own scripts/prompts checkout. See https://github.com/petry-projects/.github/blob/main/standards/ci-standards.md#dev-lead-agent.
    uses: petry-projects/.github-private/.github/workflows/dev-lead-reusable.yml@dev-lead/v1-stable  # NOSONAR(githubactions:S7637) first-party channel ref
    with:
      agent_ref: dev-lead/v1-stable
    secrets: inherit  # NOSONAR(githubactions:S7635) first-party trusted reusable
    permissions:
      contents: write
      pull-requests: write
      issues: write
      actions: read
      checks: read
      statuses: read
CANONICAL
)" | sed "s|dev-lead/v1-stable|${channel}|g" > "$canon"
  run diff -u "$canon" "$STUB"
  rm -f "$canon"
  [ "$status" -eq 0 ] || {
    echo "stub drifted from canonical:"
    echo "$output"
    return 1
  }
}

@test "with: agent_ref is pinned to the major-scoped dev-lead/v1-stable channel (dev-lead-stub-agent-ref)" {
  # The compliance check requires the dev-lead/v<M>-<channel> form. Anchor the end
  # so a suffix like dev-lead/v1-stable-rogue cannot slip through.
  grep -qE '^[[:space:]]+agent_ref:[[:space:]]+dev-lead/v1-stable([[:space:]]|$)' "$STUB" || {
    echo "agent_ref must be the major-scoped channel 'dev-lead/v1-stable', not the unversioned 'dev-lead/stable'." >&2
    return 1
  }
}

@test "with: agent_ref is not the unversioned dev-lead/stable form" {
  if grep -qE '^[[:space:]]+agent_ref:[[:space:]]+dev-lead/(stable|next)([[:space:]]|$|#)' "$STUB"; then
    echo "Error: agent_ref is the unversioned dev-lead/<channel> form — it must carry the v<M> major scope (e.g. dev-lead/v1-stable)." >&2
    return 1
  fi
}

@test "uses: ref is pinned to the dev-lead/v1-stable channel and matches agent_ref" {
  grep -qE '^[[:space:]]+uses:[[:space:]]+petry-projects/\.github-private/\.github/workflows/dev-lead-reusable\.yml@dev-lead/v1-stable([[:space:]]|$)' "$STUB" || {
    echo "uses: ref must be pinned to the major-scoped dev-lead/v1-stable channel." >&2
    return 1
  }
}

@test "uses: ref is not repointed to the unversioned channel, @main, a SHA, or a frozen @vN" {
  if grep -qE 'dev-lead-reusable\.yml@(main|[0-9a-f]{7,40}|dev-lead/v[0-9]+|dev-lead/(stable|next))([[:space:]]|#|$)' "$STUB"; then
    echo "Error: The uses: ref in $STUB is pointed to a forbidden ref (main, SHA, frozen vN, or unversioned channel)." >&2
    echo "It must be pinned to the dev-lead/v1-stable channel." >&2
    return 1
  fi
}

@test "top-level permissions are locked down to {}" {
  grep -q '^permissions: {}' "$STUB" || { echo "Top-level permissions are not locked down to {}"; return 1; }
}

@test "core trigger events are present" {
  grep -qE '^  pull_request:' "$STUB" || { echo "Missing pull_request trigger"; return 1; }
  grep -qE '^  pull_request_review:' "$STUB" || { echo "Missing pull_request_review trigger"; return 1; }
  grep -qE '^  pull_request_review_comment:' "$STUB" || { echo "Missing pull_request_review_comment trigger"; return 1; }
  grep -qE '^  issue_comment:' "$STUB" || { echo "Missing issue_comment trigger"; return 1; }
  grep -qE '^  issues:' "$STUB" || { echo "Missing issues trigger"; return 1; }
  grep -qE '^  check_run:' "$STUB" || { echo "Missing check_run trigger"; return 1; }
  grep -qE '^  repository_dispatch:' "$STUB" || { echo "Missing repository_dispatch trigger"; return 1; }
}
