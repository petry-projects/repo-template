#!/usr/bin/env bash
# Seeding utility for petry-projects/repo-template.
#
# Usage:
#   seed-repo-template.sh --emit-workflow <workflow-name>
#     Prints the canonical stub bytes for the named workflow to stdout.
#     Used by tests/pr-review-mention-stub.bats to enforce byte-identity.

set -euo pipefail

emit_workflow() {
  local name="${1:?workflow name required}"
  case "$name" in
    pr-review-mention.yml)
      cat << 'CANONICAL'
# ─────────────────────────────────────────────────────────────────────────────
# SOURCE OF TRUTH: petry-projects/.github/standards/workflows/pr-review-mention.yml
# Standard:        petry-projects/.github/standards/ci-standards.md
# Reusable:        petry-projects/.github/.github/workflows/pr-review-mention-reusable.yml
#
# AGENTS — READ BEFORE EDITING:
#   • This file is a THIN CALLER STUB. All review-dispatch logic lives in the
#     reusable workflow above.
#   • You MUST NOT change: the `uses:` ref — it is pinned to the
#     `pr-review-mention/stable` channel, a moving tag advanced centrally.
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
# Requires: GH_PAT_WORKFLOWS org secret (already present in petry-projects org).
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
    uses: petry-projects/.github/.github/workflows/pr-review-mention-reusable.yml@pr-review-mention/stable  # NOSONAR(githubactions:S7637) first-party channel ref
    secrets: inherit
CANONICAL
      ;;
    *)
      printf 'seed-repo-template.sh: unknown workflow: %s\n' "$name" >&2
      exit 1
      ;;
  esac
}

main() {
  local mode="" workflow=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --emit-workflow)
        mode="emit"
        workflow="${2:?--emit-workflow requires a workflow filename}"
        shift 2
        ;;
      *)
        printf 'seed-repo-template.sh: unknown option: %s\n' "$1" >&2
        exit 1
        ;;
    esac
  done

  case "$mode" in
    emit) emit_workflow "$workflow" ;;
    *)
      printf 'Usage: seed-repo-template.sh --emit-workflow <workflow-name>\n' >&2
      exit 1
      ;;
  esac
}

main "$@"
