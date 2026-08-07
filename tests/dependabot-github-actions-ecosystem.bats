#!/usr/bin/env bats
# Compliance regression guard for the Dependabot GitHub Actions ecosystem
# (petry-projects/.github → standards/dependabot-policy.md#github-actions-all-repos).
#
# Every repo MUST include a dedicated `github-actions` ecosystem entry in
# .github/dependabot.yml. Unlike application ecosystems (npm, etc.) which run
# security-only with open-pull-requests-limit: 0, GitHub Actions use *version
# updates* on a weekly schedule with open-pull-requests-limit: 10, because
# pinned action SHAs do not affect application runtime stability and the
# auto-merge workflow approves all version bumps (SHA-pinned; CI catches
# breaking interface changes).
#
# This guard mirrors the weekly compliance audit's missing-github-actions-
# ecosystem check offline so drift is caught in CI. It parses the config with
# yq rather than grepping, so field placement/ordering is irrelevant.

DEPENDABOT="${BATS_TEST_DIRNAME}/../.github/dependabot.yml"

# yq filter selecting the github-actions update entry (empty if absent).
GHA_SELECT='.updates[] | select(.["package-ecosystem"] == "github-actions")'

setup() {
  if ! command -v yq >/dev/null 2>&1; then
    echo "yq is required but not installed" >&2
    return 1
  fi
}

@test "dependabot.yml exists at .github/dependabot.yml" {
  [ -f "$DEPENDABOT" ]
}

@test "dependabot.yml is valid YAML and version 2" {
  run yq '.version' "$DEPENDABOT"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

@test "a github-actions ecosystem entry is present" {
  run yq "[$GHA_SELECT] | length" "$DEPENDABOT"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ] || {
    echo "Expected exactly one github-actions ecosystem entry, found: $output"
    return 1
  }
}

@test "github-actions entry targets directory /" {
  run yq "$GHA_SELECT | .directory" "$DEPENDABOT"
  [ "$status" -eq 0 ]
  [ "${output//\"/}" = "/" ]
}

@test "github-actions entry uses a weekly schedule" {
  run yq "$GHA_SELECT | .schedule.interval" "$DEPENDABOT"
  [ "$status" -eq 0 ]
  [ "${output//\"/}" = "weekly" ]
}

@test "github-actions entry sets open-pull-requests-limit to 10 (version updates)" {
  run yq "$GHA_SELECT | .[\"open-pull-requests-limit\"]" "$DEPENDABOT"
  [ "$status" -eq 0 ]
  [ "$output" -eq 10 ]
}

@test "github-actions entry carries the security and dependencies labels" {
  run yq "$GHA_SELECT | .labels[]" "$DEPENDABOT"
  [ "$status" -eq 0 ]
  echo "$output" | tr -d '"' | grep -q "^security$"
  echo "$output" | tr -d '"' | grep -q "^dependencies$"
}

@test "pre-existing npm ecosystem entry is preserved (no regression)" {
  run yq '[.updates[] | select(.["package-ecosystem"] == "npm")] | length' "$DEPENDABOT"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ] || {
    echo "Expected exactly one npm ecosystem entry, found: $output"
    return 1
  }

  run yq '.updates[] | select(.["package-ecosystem"] == "npm") | .labels[]' "$DEPENDABOT"
  [ "$status" -eq 0 ]
  echo "$output" | tr -d '"' | grep -q "^security$"
  echo "$output" | tr -d '"' | grep -q "^dependencies$"
}
