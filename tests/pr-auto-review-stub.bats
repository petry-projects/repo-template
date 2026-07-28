#!/usr/bin/env bats
# Drift & compliance regression guard for the pr-auto-review thin caller stub.
#
# .github/workflows/pr-auto-review.yml is a THIN CALLER STUB whose readiness-gate
# logic lives entirely in the central reusable (petry-projects/.github →
# .github/workflows/pr-auto-review-reusable.yml). Its `uses:` channel ref, trigger
# event types, and job `permissions:` block are drift-protected and MUST NOT be
# edited in the caller (see the file's own "AGENTS — READ BEFORE EDITING" banner
# and ci-standards.md → Reusable workflow versioning).
#
# Unlike the other caller stubs, ONE thing IS a per-repo customization point: the
# `workflow_run.workflows` list must name this repo's CI workflow(s). For
# repo-template that workflow is named "CI" (.github/workflows/ci.yml), so the
# shipped value is already correct and carries no outstanding TODO. This guard
# pins that invariant — and, per SonarCloud githubactions:S1135 (issue #98),
# asserts no TODO/FIXME marker lingers in the stub so the finding stays at zero.

STUB="${BATS_TEST_DIRNAME}/../.github/workflows/pr-auto-review.yml"
CI_WORKFLOW="${BATS_TEST_DIRNAME}/../.github/workflows/ci.yml"

@test "pr-auto-review stub exists" {
  [ -f "$STUB" ]
}

@test "stub carries no TODO/FIXME marker (SonarCloud githubactions:S1135 regression guard)" {
  if grep -nE '(TODO|FIXME)' "$STUB"; then
    echo "Error: $STUB still contains a TODO/FIXME marker — SonarCloud S1135 will re-open." >&2
    echo "Complete the task and reword the comment instead of leaving a TODO." >&2
    return 1
  fi
}

@test "workflow_run.workflows names this repo's CI workflow" {
  # The stub gates on the named CI workflow completing; that name must match the
  # `name:` of the repo's actual CI workflow. repo-template ships ci.yml as "CI".
  grep -qE '^    workflows: \["CI"\]' "$STUB" \
    || { echo "workflow_run.workflows is not [\"CI\"]"; return 1; }
  grep -qE '^name: CI$' "$CI_WORKFLOW" \
    || { echo "ci.yml is not named 'CI' — update the stub's workflows list to match"; return 1; }
}

@test "uses: ref is pinned to the pr-auto-review/v1-stable channel" {
  grep -qF 'uses: petry-projects/.github/.github/workflows/pr-auto-review-reusable.yml@pr-auto-review/v1-stable' "$STUB"
}

@test "uses: ref is not repointed to @main, a SHA, or a frozen @vN" {
  if grep -qE 'pr-auto-review-reusable\.yml@(main|[0-9a-f]{7,40}|v[0-9]+([[:space:]]|$))' "$STUB"; then
    echo "Error: The uses: ref in $STUB is pointed to a forbidden ref (main, SHA, or frozen vN)." >&2
    echo "It must be pinned to the pr-auto-review/v1-stable channel." >&2
    return 1
  fi
}

@test "all four trigger events are present" {
  grep -qE '^  workflow_run:' "$STUB" || { echo "Missing workflow_run trigger"; return 1; }
  grep -qE '^  check_suite:' "$STUB" || { echo "Missing check_suite trigger"; return 1; }
  grep -qE '^  pull_request_review:' "$STUB" || { echo "Missing pull_request_review trigger"; return 1; }
  grep -qE '^  pull_request:' "$STUB" || { echo "Missing pull_request trigger"; return 1; }
}

@test "top-level permissions are locked down to {}" {
  grep -q '^permissions: {}' "$STUB" || { echo "Top-level permissions are not locked down to {}"; return 1; }
}

@test "job grants exactly the read scopes the reusable needs and forwards the named secret" {
  grep -qE '^      pull-requests: read' "$STUB" || { echo "Missing pull-requests: read permission"; return 1; }
  grep -qE '^      checks: read' "$STUB" || { echo "Missing checks: read permission"; return 1; }
  grep -qE '^      actions: read' "$STUB" || { echo "Missing actions: read permission"; return 1; }
  grep -qF 'GH_PAT_WORKFLOWS: ${{ secrets.GH_PAT_DON_PETRY || secrets.GH_PAT_WORKFLOWS }}' "$STUB" \
    || { echo "Missing GH_PAT_WORKFLOWS secret with GH_PAT_DON_PETRY fallback"; return 1; }
}
