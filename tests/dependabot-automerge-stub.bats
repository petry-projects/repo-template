#!/usr/bin/env bats
# Drift & compliance regression guard for the dependabot-automerge thin caller stub.
#
# .github/workflows/dependabot-automerge.yml is copied VERBATIM from the canonical
# org template (petry-projects/.github → standards/workflows/dependabot-automerge.yml)
# and must stay byte-identical across every adopting repo. The `uses:` ref is pinned
# to the `dependabot-automerge/stable` channel — the only permitted channel; never
# repoint it to an alternate channel, @main, a SHA, or a frozen @vN. Any other diff
# is drift — the silent-revert class of failure the fleet stub-drift monitor exists
# to catch (fleet_stub_drift.sh).
#
# The stub's behavior lives entirely in the central reusable; its `uses:` ref,
# trigger event, and job `permissions:` block are drift-protected and MUST NOT be
# edited in the caller (see the file's own "AGENTS — READ BEFORE EDITING" banner
# and ci-standards.md → Reusable workflow versioning). Secrets are forwarded by
# explicit name (APP_ID / APP_PRIVATE_KEY) rather than `secrets: inherit`, which
# satisfies SonarCloud githubactions:S7635 ("Only pass required secrets to this
# workflow").

STUB="${BATS_TEST_DIRNAME}/../.github/workflows/dependabot-automerge.yml"

@test "dependabot-automerge stub exists" {
  [ -f "$STUB" ]
}

@test "uses: ref is pinned to the dependabot-automerge/stable channel" {
  grep -qF 'uses: petry-projects/.github/.github/workflows/dependabot-automerge-reusable.yml@dependabot-automerge/stable' "$STUB"
}

@test "uses: ref is not repointed to @main, a SHA, or a frozen @vN" {
  if grep -qE 'dependabot-automerge-reusable\.yml@(main|[0-9a-f]{7,40}|v[0-9]+)' "$STUB"; then
    echo "Error: The uses: ref in $STUB is pointed to a forbidden ref (main, SHA, or frozen vN)." >&2
    echo "It must be pinned to the dependabot-automerge/stable channel." >&2
    return 1
  fi
}

@test "trigger is pull_request_target on main" {
  grep -qE '^  pull_request_target:' "$STUB" || { echo "Missing pull_request_target trigger"; return 1; }
}

@test "top-level permissions are locked down to {}" {
  grep -q '^permissions: {}' "$STUB" || { echo "Top-level permissions are not locked down to {}"; return 1; }
}

@test "job grants exactly contents: read + pull-requests: read and forwards named secrets" {
  grep -qE '^      contents: read' "$STUB" || { echo "Missing contents: read permission"; return 1; }
  grep -qE '^      pull-requests: read' "$STUB" || { echo "Missing pull-requests: read permission"; return 1; }
  grep -qF 'APP_ID: ${{ secrets.APP_ID }}' "$STUB" \
    || { echo "Missing APP_ID secret"; return 1; }
  grep -qF 'APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}' "$STUB" \
    || { echo "Missing APP_PRIVATE_KEY secret"; return 1; }
}

@test "stub does not use blanket secrets: inherit (S7635)" {
  if grep -qE '^[[:space:]]*secrets:[[:space:]]+inherit[[:space:]]*$' "$STUB"; then
    echo "Error: $STUB uses 'secrets: inherit'; forward APP_ID / APP_PRIVATE_KEY by name instead." >&2
    return 1
  fi
}

@test "dependabot-automerge stub is byte-identical to the canonical template" {
  # Inline canonical snapshot — update this heredoc whenever the central
  # template (petry-projects/.github/standards/workflows/dependabot-automerge.yml) changes.
  # The committed stub has NO trailing newline, so capture via command
  # substitution (strips trailing newlines) + printf '%s' (adds none) to stay
  # byte-faithful to the committed production stub.
  local canon
  canon="$(mktemp)"
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
#     the `uses:` line, the explicit secrets block, or the job-level `permissions:`
#     block — reusable workflows can be granted no more permissions than the
#     calling job has, so removing the stanza breaks the reusable's gh API
#     calls.
#   • If you need different behaviour, open a PR against the reusable in the
#     central repo.
# ─────────────────────────────────────────────────────────────────────────────
#
# Dependabot auto-merge — thin caller for the org-level reusable.
# To adopt: copy this file to .github/workflows/dependabot-automerge.yml in your repo.
# Required secrets (forwarded explicitly via the secrets: block below):
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
    uses: petry-projects/.github/.github/workflows/dependabot-automerge-reusable.yml@dependabot-automerge/stable  # NOSONAR(githubactions:S7637) first-party channel ref
    secrets:
      APP_ID: ${{ secrets.APP_ID }}
      APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}
CANONICAL
)" > "$canon"
  run diff -u -- "$canon" "$STUB"
  rm -f "$canon"
  [ "$status" -eq 0 ] || {
    echo "stub drifted from canonical: $output"
    return 1
  }
}
