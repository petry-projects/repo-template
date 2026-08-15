#!/usr/bin/env bats
# Compliance regression guard for the pr-quality ruleset Standard
# (petry-projects/.github → standards/github-settings.md#pr-quality--standard-ruleset-all-repositories,
#  codified at standards/rulesets/pr-quality.json).
#
# The org "pr-quality" branch ruleset enforces PR-review quality on the default
# branch. Its parameters are codified as JSON in the org repo (the source of
# truth) and applied to the live repo by the org tooling scripts/apply-rulesets.sh.
# The weekly compliance audit flags drift between the live ruleset and that
# codified standard — e.g. issue #145: require_last_push_approval drifted from the
# expected true to false.
#
# This guard mirrors that audit offline: it pins the codified pull_request rule
# parameters — copied verbatim from the org source of truth into
# standards/rulesets/pr-quality.json — so drift in the codified value is caught in
# CI rather than only by the weekly audit. If the org updates the standard,
# re-copy standards/rulesets/pr-quality.json and update the expectations below.

RULESET_JSON="${BATS_TEST_DIRNAME}/../standards/rulesets/pr-quality.json"

# Read one value from the pull_request rule's parameters as its JSON literal.
# Uses python3 (already installed in CI for the compliance job) — no jq dependency.
pr_param() {
  python3 - "$RULESET_JSON" "$1" << 'PY'
import json, sys
data = json.load(open(sys.argv[1]))
rule = next(r for r in data["rules"] if r["type"] == "pull_request")
print(json.dumps(rule["parameters"][sys.argv[2]]))
PY
}

@test "codified pr-quality ruleset exists" {
  [ -f "$RULESET_JSON" ]
}

@test "codified pr-quality ruleset is valid JSON" {
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$RULESET_JSON"
}

@test "ruleset targets the default branch with active enforcement" {
  run python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["enforcement"], d["conditions"]["ref_name"]["include"])' "$RULESET_JSON"
  [ "$status" -eq 0 ]
  [[ "$output" == *"active"* ]]
  [[ "$output" == *"~DEFAULT_BRANCH"* ]]
}

@test "require_last_push_approval is enabled (guards issue #145 drift)" {
  [ "$(pr_param require_last_push_approval)" = "true" ]
}

@test "required_approving_review_count is 1" {
  [ "$(pr_param required_approving_review_count)" = "1" ]
}

@test "require_code_owner_review is enabled" {
  [ "$(pr_param require_code_owner_review)" = "true" ]
}

@test "required_review_thread_resolution is enabled" {
  [ "$(pr_param required_review_thread_resolution)" = "true" ]
}

@test "dismiss_stale_reviews_on_push is enabled" {
  [ "$(pr_param dismiss_stale_reviews_on_push)" = "true" ]
}

@test "allowed_merge_methods is squash-only" {
  [ "$(pr_param allowed_merge_methods)" = '["squash"]' ]
}
