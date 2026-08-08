#!/usr/bin/env bats
# Drift & compliance regression guard for the agent-shield thin caller stub.
#
# .github/workflows/agent-shield.yml is copied VERBATIM from the canonical
# org template (petry-projects/.github → standards/workflows/agent-shield.yml)
# and must stay byte-identical across every adopting repo, modulo the per-repo
# channel pin on the `uses:` ref. Any other diff is drift — the silent-revert
# class of failure the fleet stub-drift monitor exists to catch (fleet_stub_drift.sh).
#
# The stub's behavior lives entirely in the central reusable; its `uses:` ref,
# trigger events, and top-level `permissions:` block are drift-protected and
# MUST NOT be edited in the caller (see the file's own "AGENTS — READ BEFORE
# EDITING" banner and ci-standards.md → Centralization tiers). In particular the
# ref MUST be pinned to the `agent-shield/stable` channel.
# This guard pins those invariants so drift is caught in CI rather than in
# production run health.

STUB="${BATS_TEST_DIRNAME}/../.github/workflows/agent-shield.yml"

@test "agent-shield stub exists" {
  [ -f "$STUB" ]
}

@test "agent-shield stub is byte-identical to the canonical template" {
  # Inline canonical snapshot — update this heredoc whenever the central template
  # (petry-projects/.github/standards/workflows/agent-shield.yml) changes.
  local canon
  canon="$(mktemp)"
  # The committed stub has NO trailing newline, so emit the heredoc with its
  # trailing newline stripped (printf '%s') to stay byte-faithful to the
  # committed, production stub that the fleet stub-drift monitor compares SHAs against.
  printf '%s' "$(cat << 'CANONICAL'
# ─────────────────────────────────────────────────────────────────────────────
# SOURCE OF TRUTH: petry-projects/.github/standards/workflows/agent-shield.yml
# Standard:        petry-projects/.github/standards/agent-standards.md
# Reusable:        petry-projects/.github/.github/workflows/agent-shield-reusable.yml
#
# AGENTS — READ BEFORE EDITING:
#   • This file is a THIN CALLER STUB. The AgentShield CLI scan and the
#     org-specific structural checks live in the reusable workflow above.
#   • You MAY change: the `with:` inputs (min-severity, agentshield-version,
#     required-files, org-standards-ref) — only if your repo genuinely needs
#     a different policy.
#   • You MUST NOT change: trigger events, the `uses:` line, or the job name
#     (used as a required status check).
#   • If you need different behaviour beyond the inputs, open a PR against
#     the reusable in the central repo.
# ─────────────────────────────────────────────────────────────────────────────
#
# AgentShield — thin caller for the org-level reusable.
# To adopt: copy this file to .github/workflows/agent-shield.yml in your repo.
name: AgentShield

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read

jobs:
  agent-shield:
    uses: petry-projects/.github/.github/workflows/agent-shield-reusable.yml@agent-shield/stable  # NOSONAR(githubactions:S7637) first-party channel ref
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

@test "uses: ref is pinned to the agent-shield/stable channel" {
  grep -qF 'uses: petry-projects/.github/.github/workflows/agent-shield-reusable.yml@agent-shield/stable' "$STUB"
}

@test "uses: ref is not repointed to @main, a SHA, or a frozen @vN" {
  if grep -qE 'agent-shield-reusable\.yml@(main|[0-9a-f]{7,40}|v[0-9]+([[:space:]#]|$))' "$STUB"; then
    echo "Error: The uses: ref in $STUB is pointed to a forbidden ref (main, SHA, or frozen vN)." >&2
    echo "It must be pinned to the agent-shield/stable channel." >&2
    return 1
  fi
}

@test "uses: ref is not pinned to a frozen or SHA ref" {
  # The ref must be pinned to a stable channel (agent-shield/stable), not a frozen version
  # (@agent-shield/vN) or a SHA commit.
  if grep -qE 'agent-shield-reusable\.yml@(main|[0-9a-f]{7,40}|v[0-9]+)' "$STUB"; then
    echo "Error: The uses: ref in $STUB is pinned to a forbidden ref (main, SHA, or frozen vN)." >&2
    echo "It must be pinned to the agent-shield/stable channel." >&2
    return 1
  fi
}

@test "both trigger events are present" {
  grep -qE '^  push:' "$STUB" || { echo "Missing push trigger"; return 1; }
  grep -qE '^  pull_request:' "$STUB" || { echo "Missing pull_request trigger"; return 1; }
}

@test "top-level permissions are locked down to contents: read" {
  grep -qE '^permissions:' "$STUB" || { echo "Missing top-level permissions block"; return 1; }
  grep -qE '^  contents: read$' "$STUB" || { echo "Top-level permissions must grant contents: read only"; return 1; }
}
