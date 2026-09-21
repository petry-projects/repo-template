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
#     would leave a cancelled run, so they get a unique-per-run group (keyed by
#     github.run_id) and never cancel.
# A default-branch trigger with no associated PR also falls back to the
# unique-per-run group so unrelated PRs never collapse into one group.

STUB="${BATS_TEST_DIRNAME}/../.github/workflows/pr-auto-review.yml"

# Semantic parser to extract concurrency fields from the YAML stub.
# This avoids fragile regex/awk parsing of YAML and handles multi-line folded
# strings, comments, and key-ordering changes. PyYAML is already a project test
# dependency (see pr-auto-review-stub.bats).
get_concurrency_val() {
  python3 - "$STUB" "$1" <<'PYEOF'
import yaml, sys
with open(sys.argv[1], encoding="utf-8") as f:
    stub = yaml.safe_load(f)
concurrency = stub.get('concurrency') or {}
val = concurrency.get(sys.argv[2])
if val is None:
    sys.exit(1)
if isinstance(val, str):
    print(" ".join(val.split()))
else:
    print(val)
PYEOF
}

@test "pr-auto-review stub exists" {
  [ -f "$STUB" ]
}

@test "stub declares a top-level concurrency block" {
  grep -qE '^concurrency:[[:space:]]*(#.*)?$' "$STUB" \
    || { echo "pr-auto-review.yml is missing its centrally-owned top-level concurrency block"; return 1; }
}

@test "concurrency block defines a group" {
  get_concurrency_val "group" >/dev/null \
    || { echo "concurrency block has no 'group:' key"; return 1; }
}

@test "group collapses check_suite runs onto one per-PR slot" {
  local group
  group="$(get_concurrency_val "group")" || return 1
  [[ "$group" == '${{'* && "$group" == *'}}' ]] \
    || { echo "group expression must be wrapped in \${{ ... }}"; return 1; }
  printf '%s\n' "$group" | grep -qF "github.event.check_suite.pull_requests[0].number" \
    || { echo "group must key check_suite runs by their PR number"; return 1; }
  printf '%s\n' "$group" | grep -qF "format('pr-auto-review-ready-check-pr-{0}', github.event.check_suite.pull_requests[0].number)" \
    || { echo "group must map a check_suite PR to the shared 'pr-auto-review-ready-check-pr-<n>' slot"; return 1; }
}

@test "group collapses workflow_run runs onto one per-PR slot" {
  local group
  group="$(get_concurrency_val "group")" || return 1
  [[ "$group" == '${{'* && "$group" == *'}}' ]] \
    || { echo "group expression must be wrapped in \${{ ... }}"; return 1; }
  printf '%s\n' "$group" | grep -qF "github.event.workflow_run.pull_requests[0].number" \
    || { echo "group must key workflow_run runs by their PR number"; return 1; }
  printf '%s\n' "$group" | grep -qF "format('pr-auto-review-ready-check-pr-{0}', github.event.workflow_run.pull_requests[0].number)" \
    || { echo "group must map a workflow_run PR to the shared 'pr-auto-review-ready-check-pr-<n>' slot"; return 1; }
}

@test "group falls back to a unique-per-run slot keyed by github.run_id" {
  local group
  group="$(get_concurrency_val "group")" || return 1
  [[ "$group" == '${{'* && "$group" == *'}}' ]] \
    || { echo "group expression must be wrapped in \${{ ... }}"; return 1; }
  # PR-head triggers (and default-branch triggers with no PR) must get their own
  # slot so a cancellation never leaves a cancelled check on a PR head.
  printf '%s\n' "$group" | grep -qF "format('pr-auto-review-ready-check-unique-{0}', github.run_id)" \
    || { echo "group must fall back to a unique-per-run slot ('pr-auto-review-ready-check-unique-<run_id>')"; return 1; }
}

@test "cancel-in-progress is gated to check_suite and workflow_run only" {
  local cancel
  cancel="$(get_concurrency_val "cancel-in-progress")" || return 1
  [[ "$cancel" == '${{'* && "$cancel" == *'}}' ]] \
    || { echo "cancel-in-progress expression must be wrapped in \${{ ... }}"; return 1; }
  # It must NOT be a bare `true`: PR-head triggers must never be cancelled.
  printf '%s\n' "$cancel" | grep -qF "github.event_name == 'check_suite' || github.event_name == 'workflow_run'" \
    || { echo "cancel-in-progress must be gated to check_suite/workflow_run only, not a bare true"; return 1; }
}
