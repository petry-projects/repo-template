#!/usr/bin/env bats
# Drift & compliance regression guard for the pr-review-mention thin caller stub.
#
# .github/workflows/pr-review-mention.yml is copied VERBATIM from the canonical
# org template (petry-projects/.github → standards/workflows/pr-review-mention.yml)
# and must stay byte-identical across every adopting repo, modulo the per-repo
# channel pin on the `uses:` ref. Any other diff is drift — the silent-revert
# class of failure the fleet stub-drift monitor exists to catch (fleet_stub_drift.sh).
#
# The stub's behavior lives entirely in the central reusable; its `uses:` ref,
# trigger events, and job `permissions:` block are drift-protected and MUST NOT
# be edited in the caller (see the file's own "AGENTS — READ BEFORE EDITING"
# banner and ci-standards.md → Reusable workflow versioning). This guard pins
# those invariants so drift is caught in CI rather than in production run health.

STUB="${BATS_TEST_DIRNAME}/../.github/workflows/pr-review-mention.yml"

@test "pr-review-mention stub exists" {
  [ -f "$STUB" ]
}

@test "pr-review-mention stub is byte-identical to the canonical template" {
  # Inline canonical snapshot — update this heredoc whenever the central template
  # (petry-projects/.github/standards/workflows/pr-review-mention.yml) changes.
  # Replaces the external seed-repo-template.sh dependency that was not present in
  # this repo and caused CI to fail with exit 127 on every run.
  local canon
  canon="$(mktemp)"
  # The live canonical (petry-projects/.github → standards/workflows/pr-review-mention.yml,
  # blob 2d6c410e) ships this stub WITH a single trailing newline. Emit the heredoc
  # with exactly one trailing newline (printf '%s\n') so this guard stays byte-faithful
  # to the upstream blob that the fleet stub-drift monitor compares SHAs against.
  printf '%s\n' "$(cat << 'CANONICAL'
# ─────────────────────────────────────────────────────────────────────────────
# SOURCE OF TRUTH: petry-projects/.github/standards/workflows/pr-review-mention.yml
# Standard:        petry-projects/.github/standards/ci-standards.md
# Reusable:        petry-projects/.github/.github/workflows/pr-review-mention-reusable.yml
#
# AGENTS — READ BEFORE EDITING:
#   • This file is a THIN CALLER STUB. All review-dispatch logic lives in the
#     reusable workflow above.
#   • You MUST NOT change: the `uses:` ref — it is pinned to the
#     `pr-review-mention/v2-stable` channel, a moving tag advanced centrally.
#     Never repoint it to `@main`, a SHA, or a frozen `@vX` (see
#     ci-standards.md → Reusable workflow versioning). Also do not change the
#     trigger events or the job-level `permissions:` block — reusable workflows
#     can be granted no more permissions than the calling job, so removing the
#     stanza breaks the reusable's gh API calls.
#   • If you need different behaviour, open a PR against the reusable in the
#     central repo. A new release is rolled out by moving the channel tag
#     centrally — never by editing callers, so no fanout PR is needed.
# ─────────────────────────────────────────────────────────────────────────────
#
# PR Review Mention — thin caller for the org-level reusable.
# To adopt: copy this file to .github/workflows/pr-review-mention.yml in your repo.
# Requires (org secrets, already present in petry-projects org):
#   GH_PAT_DON_PETRY     canonical PAT for API calls and dispatching the review agent.
#                        GH_PAT_WORKFLOWS is the deprecated transition alias, kept as the
#                        `||` fallback until the persona rename lands fleet-wide.
#   DON_PETRY_BOT_GH_PAT PAT owned by donpetry-bot, for posting acknowledgement comments.
name: PR Review — Mention Trigger

on:
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]
  pull_request:
    types: [review_requested]

permissions: {}

jobs:
  pr-review-mention:
    permissions:
      pull-requests: write
    uses: petry-projects/.github/.github/workflows/pr-review-mention-reusable.yml@pr-review-mention/v2-stable  # NOSONAR(githubactions:S7637) first-party channel ref
    secrets:
      GH_PAT_WORKFLOWS: ${{ secrets.GH_PAT_DON_PETRY || secrets.GH_PAT_WORKFLOWS }}
      DON_PETRY_BOT_GH_PAT: ${{ secrets.DON_PETRY_BOT_GH_PAT }}
CANONICAL
)" > "$canon"
  run cmp -- "$canon" "$STUB"
  rm -f "$canon"
  [ "$status" -eq 0 ] || {
    echo "stub drifted from canonical: $output"
    return 1
  }
}

@test "uses: ref is pinned to the pr-review-mention/v2-stable channel" {
  grep -qF 'uses: petry-projects/.github/.github/workflows/pr-review-mention-reusable.yml@pr-review-mention/v2-stable' "$STUB"
}

@test "uses: ref is not repointed to @main, a SHA, or a frozen @vN" {
  if grep -qE 'pr-review-mention-reusable\.yml@(main|[0-9a-f]{7,40}|v[0-9]+)' "$STUB"; then
    echo "Error: The uses: ref in $STUB is pointed to a forbidden ref (main, SHA, or frozen vN)." >&2
    echo "It must be pinned to the pr-review-mention/stable channel." >&2
    return 1
  fi
}

@test "all three trigger events are present" {
  grep -qE '^  issue_comment:' "$STUB" || { echo "Missing issue_comment trigger"; return 1; }
  grep -qE '^  pull_request_review_comment:' "$STUB" || { echo "Missing pull_request_review_comment trigger"; return 1; }
  grep -qE '^  pull_request:' "$STUB" || { echo "Missing pull_request trigger"; return 1; }
  grep -qE '^    types: \[review_requested\]' "$STUB" || { echo "Missing pull_request review_requested type"; return 1; }
}

@test "top-level permissions are locked down to {}" {
  grep -q '^permissions: {}' "$STUB" || { echo "Top-level permissions are not locked down to {}"; return 1; }
}

@test "job grants exactly pull-requests: write and forwards named secrets" {
  grep -qE '^      pull-requests: write' "$STUB" || { echo "Missing pull-requests: write permission"; return 1; }
  grep -qF 'GH_PAT_WORKFLOWS: ${{ secrets.GH_PAT_DON_PETRY || secrets.GH_PAT_WORKFLOWS }}' "$STUB" \
    || { echo "Missing GH_PAT_WORKFLOWS secret with GH_PAT_DON_PETRY fallback"; return 1; }
  grep -qF 'DON_PETRY_BOT_GH_PAT: ${{ secrets.DON_PETRY_BOT_GH_PAT }}' "$STUB" \
    || { echo "Missing DON_PETRY_BOT_GH_PAT secret"; return 1; }
}
