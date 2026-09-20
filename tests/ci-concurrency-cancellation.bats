#!/usr/bin/env bats
# Compliance regression guard for ci.yml concurrency scoping (issue #208).
#
# The org CI standard now mandates SHA-scoped concurrency. Source of truth:
# petry-projects/.github standards/ci-standards.md §1 ("Why SHA-scoped
# concurrency?") and standards/workflows/ci.yml, which require:
#
#   concurrency:
#     group: ci-${{ github.ref }}-${{ github.sha }}
#     cancel-in-progress: true
#
# A per-ref-only group (`ci-${{ github.ref }}`) with `cancel-in-progress: true`
# creates a race: when the final push arrives while the previous cancellation is
# still in flight, GitHub may not fire a new `pull_request: synchronize` event,
# leaving the HEAD commit with no CI results and blocking the PR indefinitely
# (issue #208). Scoping the group to `github.sha` gives every commit its own
# concurrency slot so CI always runs to completion on HEAD.
#
# `cancel-in-progress: true` is retained: with SHA-scoped groups no two pushes
# share a slot, so it is effectively a no-op, but it is kept to declare intent —
# if the group formula is ever changed back to a per-ref pattern, the intended
# cancellation behaviour takes effect immediately without a separate edit.
#
# NOTE (policy history): an earlier remediation (#201) keyed the group by ref
# *only* and forbade github.sha. The org standard has since reversed that
# decision to fix the #208 race; this guard now pins the current standard.
#
# This guard pins the fix: ci.yml's concurrency group must be keyed by both
# github.ref and github.sha, and cancel-in-progress must stay true.

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

@test "concurrency group embeds github.sha (gives every commit its own slot)" {
  local group
  group="$(group_value)"
  # A sha in the group gives every commit a unique slot so a burst of pushes never
  # leaves HEAD with no CI results via a dropped synchronize event (issue #208).
  # Require the full `${{ github.sha }}` expression, not just the literal text
  # `github.sha`, so a group that omits the expression wrapper (e.g.
  # `ci-github.ref-github.sha`) cannot pass while failing to interpolate at runtime.
  # Literal `[{][{]`/`[}][}]` character classes with basic grep avoid GNU grep 3.8+
  # stray-backslash warnings, and `[[:space:]]` keeps the pattern POSIX-portable.
  printf '%s\n' "$group" | grep -q '[$][{][{][[:space:]]*github\.sha[[:space:]]*[}][}]' \
    || { echo "concurrency group must contain the github.sha expression (e.g. \${{ github.sha }}): $group"; return 1; }
}

@test "cancel-in-progress is enabled so a new push supersedes the stale run" {
  # Accept an optionally quoted `true` and tolerate a trailing inline comment so a
  # valid config (`cancel-in-progress: "true" # …`) is not a false negative.
  concurrency_block | grep -qE '^[[:space:]]+cancel-in-progress:[[:space:]]*(true|"true"|'\''true'\'')([[:space:]]*|[[:space:]]+#.*)$' \
    || { echo "concurrency must set cancel-in-progress: true"; return 1; }
}
