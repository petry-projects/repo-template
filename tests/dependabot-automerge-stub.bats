#!/usr/bin/env bats
# Drift & compliance regression guard for the dependabot-automerge thin caller stub.
#
# .github/workflows/dependabot-automerge.yml is copied VERBATIM from the canonical
# org template (petry-projects/.github → standards/workflows/dependabot-automerge.yml)
# and must stay byte-identical across every adopting repo, modulo the per-repo
# channel pin on the `uses:` ref. Any other diff is drift — the silent-revert
# class of failure the fleet stub-drift monitor exists to catch (fleet_stub_drift.sh).
#
# This guard specifically pins the compliance invariant from issue #105: the
# `uses:` ref MUST target the major-scoped channel `dependabot-automerge/v<M>-stable`
# (currently v2-stable). A bare `dependabot-automerge/stable` tier pin is drift per
# ci-standards.md → Reusable workflow versioning (Centralization tiers).
#
# The stub's behavior lives entirely in the central reusable; its `uses:` ref,
# trigger event, job `permissions:` block, and `secrets: inherit` are drift-protected
# and MUST NOT be edited in the caller (see the file's own "AGENTS — READ BEFORE
# EDITING" banner). This guard pins those invariants so drift is caught in CI rather
# than in production run health.

STUB="${BATS_TEST_DIRNAME}/../.github/workflows/dependabot-automerge.yml"

@test "dependabot-automerge stub exists" {
  [ -f "$STUB" ]
}

@test "dependabot-automerge stub is byte-identical to the canonical template" {
  # Inline canonical snapshot — update this heredoc whenever the central template
  # (petry-projects/.github/standards/workflows/dependabot-automerge.yml) changes.
  local canon
  canon="$(mktemp)"
  # The committed stub has NO trailing newline, so emit the heredoc with its
  # trailing newline stripped (printf '%s') to stay byte-faithful to the committed,
  # production stub that the fleet stub-drift monitor compares SHAs against.
  printf '%s' "$(cat << 'CANONICAL'
# ─────────────────────────────────────────────────────────────────────────────
# SOURCE OF TRUTH: petry-projects/.github/standards/workflows/dependabot-automerge.yml
# Standard:        petry-projects/.github/standards/dependabot-policy.md
# Reusable:        petry-projects/.github/.github/workflows/dependabot-automerge-reusable.yml
#
# AGENTS — READ BEFORE EDITING:
#   • This file is a THIN CALLER STUB. All eligibility logic and the GitHub
#     App token dance live in the reusable workflow above.
#   • You MAY change: nothing in this file in normal use. Adopt verbatim.
#   • You MUST NOT change: trigger event (must be `pull_request_target`),
#     the `uses:` line, `secrets: inherit`, or the job-level `permissions:`
#     block — reusable workflows can be granted no more permissions than the
#     calling job has, so removing the stanza breaks the reusable's gh API
#     calls.
#   • If you need different behaviour, open a PR against the reusable in the
#     central repo.
# ─────────────────────────────────────────────────────────────────────────────
#
# Dependabot auto-merge — thin caller for the org-level reusable.
# To adopt: copy this file to .github/workflows/dependabot-automerge.yml in your repo.
# Required org/repo secrets (inherited):
#   APP_ID         — GitHub App ID with contents:write and pull-requests:write
#   APP_PRIVATE_KEY — GitHub App private key
name: Dependabot auto-merge

on:
  pull_request_target:
    branches:
      - main

permissions: {}

jobs:
  dependabot-automerge:
    permissions:
      contents: read
      pull-requests: read
    uses: petry-projects/.github/.github/workflows/dependabot-automerge-reusable.yml@dependabot-automerge/v2-stable  # NOSONAR(githubactions:S7637) first-party channel ref
    secrets: inherit  # NOSONAR(githubactions:S7635) first-party trusted reusable
CANONICAL
)" > "$canon"
  run diff -u "$canon" "$STUB"
  rm -f "$canon"
  [ "$status" -eq 0 ] || {
    echo "stub drifted from canonical:"
    echo "$output"
    return 1
  }
}

@test "uses: ref is pinned to the dependabot-automerge/v2-stable channel" {
  grep -qF 'uses: petry-projects/.github/.github/workflows/dependabot-automerge-reusable.yml@dependabot-automerge/v2-stable' "$STUB"
}

@test "uses: ref is not a bare dependabot-automerge/stable tier pin (issue #105)" {
  if grep -qE 'dependabot-automerge-reusable\.yml@dependabot-automerge/stable' "$STUB"; then
    echo "Error: The uses: ref in $STUB is a bare 'dependabot-automerge/stable' tier pin." >&2
    echo "It must be pinned to the major-scoped 'dependabot-automerge/v<M>-stable' channel." >&2
    return 1
  fi
}

@test "uses: ref is not repointed to @main, a SHA, or a frozen @vN" {
  if grep -qE 'dependabot-automerge-reusable\.yml@(main([^a-z0-9-]|$)|[0-9a-f]{7,40}([^a-z0-9-]|$)|v[0-9]+([^a-z-]|$))' "$STUB"; then
    echo "Error: The uses: ref in $STUB is pointed to a forbidden ref (main, SHA, or frozen vN)." >&2
    echo "It must be pinned to the dependabot-automerge/v2-stable channel." >&2
    return 1
  fi
}

@test "trigger is pull_request_target on main" {
  grep -qE '^  pull_request_target:' "$STUB" || { echo "Missing/renamed pull_request_target trigger"; return 1; }
  grep -qE '^      - main$' "$STUB" || { echo "Trigger not scoped to the main branch"; return 1; }
}

@test "top-level permissions are locked down to {}" {
  grep -q '^permissions: {}' "$STUB" || { echo "Top-level permissions are not locked down to {}"; return 1; }
}

@test "job grants exactly contents: read + pull-requests: read and inherits secrets" {
  grep -qE '^      contents: read' "$STUB" || { echo "Missing contents: read permission"; return 1; }
  grep -qE '^      pull-requests: read' "$STUB" || { echo "Missing pull-requests: read permission"; return 1; }
  grep -qE '^    secrets: inherit' "$STUB" || { echo "Missing secrets: inherit"; return 1; }
}
