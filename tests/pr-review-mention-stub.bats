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
SEED="${BATS_TEST_DIRNAME}/../.dev-lead/scripts/seed-repo-template.sh"

@test "pr-review-mention stub exists" {
  [ -f "$STUB" ]
}

@test "pr-review-mention stub is byte-identical to the canonical template" {
  # seed-repo-template.sh --emit-workflow reproduces the canonical stub content
  # exactly (same mechanism template_stub_drift.sh uses for byte-identity checks).
  # Compare raw bytes with cmp — bats' $output normalizes trailing newlines, which
  # would mask exactly the kind of trailing-newline drift this guard must catch.
  local canon emit_status
  canon="$(mktemp)"
  bash "$SEED" --emit-workflow pr-review-mention.yml > "$canon"
  emit_status=$?
  if [ "$emit_status" -ne 0 ]; then
    rm -f "$canon"
    echo "seed-repo-template.sh --emit-workflow failed (exit $emit_status)"
    return 1
  fi
  run cmp -- "$canon" "$STUB"
  rm -f "$canon"
  [ "$status" -eq 0 ] || {
    echo "stub drifted from canonical: $output"
    return 1
  }
}

@test "uses: ref is pinned to the pr-review-mention/stable channel" {
  grep -qF 'uses: petry-projects/.github/.github/workflows/pr-review-mention-reusable.yml@pr-review-mention/stable' "$STUB"
}

@test "uses: ref is not repointed to @main, a SHA, or a frozen @vN" {
  ! grep -qE 'pr-review-mention-reusable\.yml@(main|[0-9a-f]{40}|v[0-9])' "$STUB"
}

@test "all three trigger events are present" {
  grep -qE '^  issue_comment:' "$STUB"
  grep -qE '^  pull_request_review_comment:' "$STUB"
  grep -qE '^  pull_request:' "$STUB"
  grep -qE '^    types: \[review_requested\]' "$STUB"
}

@test "top-level permissions are locked down to {}" {
  grep -qE '^permissions: \{\}' "$STUB"
}

@test "job grants exactly pull-requests: write and inherits secrets" {
  grep -qE '^      pull-requests: write' "$STUB"
  grep -qF 'secrets: inherit' "$STUB"
}
