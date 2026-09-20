#!/usr/bin/env bats
# Compliance regression guard for the pr-auto-review thin caller stub's
# `concurrency:` surface (issue #209).
#
# .github/workflows/pr-auto-review.yml is a THIN CALLER STUB. Its `on:` triggers,
# `permissions:` grants, and `concurrency:` block are owned centrally by
# petry-projects/.github → standards/workflows/pr-auto-review.yml and are NOT
# repo-adjustable (only the documented `with:` inputs and the tier channel pin
# may differ per repo). This guard pins the centrally-owned `concurrency:`
# surface so it cannot silently drift back out of sync.
#
# The canonical block deduplicates ONLY the default-branch-context triggers
# (issue #1126):
#   • check_suite / workflow_run — head_branch=main, the check does NOT attach to
#     the PR head, so superseding an in-flight run is SAFE. Both events collapse
#     onto one group per PR (`…-pr-<number>`) with cancel-in-progress: true.
#   • pull_request / pull_request_review — run on the PR head; a cancelled run
#     would leave a cancelled check on the head, so they get a unique-per-run
#     group (keyed by github.run_id) and never cancel.
# A default-branch trigger with no associated PR also falls back to the
# unique-per-run group so unrelated PRs never collapse into one group.

STUB="${BATS_TEST_DIRNAME}/../.github/workflows/pr-auto-review.yml"

# Print the top-level `concurrency:` block — from the `concurrency:` line up to
# the next top-level (column-0) key — so assertions are scoped to it. Comment
# lines are dropped so a commented-out key can never satisfy a guard.
concurrency_block() {
  awk '
    /^concurrency:[[:space:]]*(#.*)?$/ { f = 1; print; next }
    f && /^[A-Za-z]/ { f = 0 }
    f { print }
  ' "$STUB" | grep -v '^[[:space:]]*#'
}

# The concurrency block with all runs of whitespace collapsed to single spaces,
# so a multi-line folded (`>-`) group formula can be matched as one string.
concurrency_flat() {
  concurrency_block | tr '\n' ' ' | tr -s '[:space:]' ' '
}

@test "pr-auto-review stub exists" {
  [ -f "$STUB" ]
}

@test "stub declares a top-level concurrency block" {
  grep -qE '^concurrency:[[:space:]]*(#.*)?$' "$STUB" \
    || { echo "pr-auto-review.yml is missing its centrally-owned top-level concurrency block"; return 1; }
}

@test "concurrency block defines a group" {
  concurrency_block | grep -qE '^[[:space:]]+group:' \
    || { echo "concurrency block has no 'group:' key"; return 1; }
}

@test "group collapses check_suite runs onto one per-PR slot" {
  local flat
  flat="$(concurrency_flat)"
  printf '%s\n' "$flat" | grep -qF "github.event.check_suite.pull_requests[0].number" \
    || { echo "group must key check_suite runs by their PR number"; return 1; }
  printf '%s\n' "$flat" | grep -qF "format('pr-auto-review-ready-check-pr-{0}', github.event.check_suite.pull_requests[0].number)" \
    || { echo "group must map a check_suite PR to the shared 'pr-auto-review-ready-check-pr-<n>' slot"; return 1; }
}

@test "group collapses workflow_run runs onto one per-PR slot" {
  local flat
  flat="$(concurrency_flat)"
  printf '%s\n' "$flat" | grep -qF "github.event.workflow_run.pull_requests[0].number" \
    || { echo "group must key workflow_run runs by their PR number"; return 1; }
  printf '%s\n' "$flat" | grep -qF "format('pr-auto-review-ready-check-pr-{0}', github.event.workflow_run.pull_requests[0].number)" \
    || { echo "group must map a workflow_run PR to the shared 'pr-auto-review-ready-check-pr-<n>' slot"; return 1; }
}

@test "group falls back to a unique-per-run slot keyed by github.run_id" {
  local flat
  flat="$(concurrency_flat)"
  # PR-head triggers (and default-branch triggers with no PR) must get their own
  # slot so a cancellation never leaves a cancelled check on a PR head.
  printf '%s\n' "$flat" | grep -qF "format('pr-auto-review-ready-check-unique-{0}', github.run_id)" \
    || { echo "group must fall back to a unique-per-run slot ('pr-auto-review-ready-check-unique-<run_id>')"; return 1; }
}

@test "cancel-in-progress is gated to check_suite and workflow_run only" {
  local flat
  flat="$(concurrency_flat)"
  # It must NOT be a bare `true`: PR-head triggers must never be cancelled.
  printf '%s\n' "$flat" | grep -qF "cancel-in-progress: \${{ github.event_name == 'check_suite' || github.event_name == 'workflow_run' }}" \
    || { echo "cancel-in-progress must be gated to check_suite/workflow_run only, not a bare true"; return 1; }
}
