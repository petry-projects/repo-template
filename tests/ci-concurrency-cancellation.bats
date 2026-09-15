#!/usr/bin/env bats
# Compliance regression guard for ci.yml concurrency-cancellation reliability (issue #201).
#
# The CI workflow failed at ~59% across the monitored window (p50 28s, p95 178s) —
# a fast-failure signature, not the stall signature the earlier remediations
# targeted (#152 stale apt index, #155 apt retry, #163 gitleaks retry, #169 per-job
# timeout, #196 per-attempt network timeout). The driver was the concurrency key:
#
#   concurrency:
#     group: ci-${{ github.ref }}-${{ github.sha }}   # <- github.sha
#     cancel-in-progress: true
#
# Because the group embeds ${{ github.sha }}, every commit lands in a *distinct*
# concurrency group, so `cancel-in-progress: true` can never match — and therefore
# never supersede — an in-flight run for the same ref. When an automation branch
# receives a burst of pushes seconds apart (observed: 4 pushes ~26s apart on one
# branch), each spawns a full run that runs to completion. Every superseded run that
# should have been *cancelled* instead runs and *fails*, inflating the failure rate
# the Fleet Monitor flags. Every sibling workflow in this repo (auto-rebase,
# dependabot-rebase, feature-ideation, add-to-project, initiative-driver) keys its
# group by a *stable* identity (ref / repo / event) precisely so cancellation works.
#
# This guard pins the fix: ci.yml's concurrency group must be keyed by github.ref
# and must NOT contain github.sha, and cancel-in-progress must stay true, so a new
# push to a ref cancels the stale in-flight run instead of letting both complete.

CI_YML="${BATS_TEST_DIRNAME}/../.github/workflows/ci.yml"

# Print the top-level `concurrency:` block — from the `concurrency:` line up to the
# next top-level (column-0) key — so assertions are scoped to it. Comment lines are
# dropped so a commented-out key can never satisfy a guard.
concurrency_block() {
  awk '
    /^concurrency:[[:space:]]*(#.*)?$/ { f = 1; print; next }
    f && /^[A-Za-z]/ { f = 0 }
    f { print }
  ' "$CI_YML" | grep -v '^[[:space:]]*#'
}

# The value of the concurrency `group:` key (everything after `group:`), or empty.
# An inline YAML comment (` # …`) is stripped so comment text can never satisfy a
# guard — e.g. `group: ci-static # github.ref is required` must NOT pass the
# github.ref check on the strength of the comment alone.
group_value() {
  concurrency_block | grep -E '^[[:space:]]+group:' | head -1 \
    | sed -E 's/^[[:space:]]+group:[[:space:]]*//; s/[[:space:]]+#.*$//; s/[[:space:]]+$//'
}

@test "ci.yml exists at the expected path" {
  [ -f "$CI_YML" ]
}

@test "ci.yml declares a top-level concurrency block" {
  grep -qE '^concurrency:[[:space:]]*(#.*)?$' "$CI_YML"
}

@test "concurrency block defines a group" {
  local group
  group="$(group_value)"
  [ -n "$group" ] || { echo "ci.yml concurrency has no 'group:' key"; return 1; }
}

@test "concurrency group is keyed by github.ref" {
  local group
  group="$(group_value)"
  printf '%s\n' "$group" | grep -qE 'github\.ref' \
    || { echo "concurrency group must be keyed by github.ref so pushes to a ref share a group: $group"; return 1; }
}

@test "concurrency group does not embed github.sha (would defeat cancel-in-progress)" {
  local group
  group="$(group_value)"
  # A sha in the group gives every commit a unique group, so cancel-in-progress can
  # never supersede a stale run for the same ref (issue #201 root cause).
  ! printf '%s\n' "$group" | grep -qE 'github\.sha' \
    || { echo "concurrency group must NOT contain github.sha: $group"; return 1; }
}

@test "cancel-in-progress is enabled so a new push supersedes the stale run" {
  # Accept an optionally quoted `true` and tolerate a trailing inline comment so a
  # valid config (`cancel-in-progress: "true" # …`) is not a false negative.
  concurrency_block | grep -qE '^[[:space:]]+cancel-in-progress:[[:space:]]*(true|"true"|'\''true'\'')([[:space:]]*|[[:space:]]+#.*)$' \
    || { echo "concurrency must set cancel-in-progress: true"; return 1; }
}
