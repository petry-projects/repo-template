#!/usr/bin/env bats
# Compliance regression guard for
# github-settings.md#code-quality--required-checks-ruleset-all-repositories:
# the `code-quality` repository ruleset (applied out-of-band by the org
# apply-rulesets.sh from standards/rulesets/code-quality.json) requires four
# status checks on the default branch. Rulesets are live GitHub settings, not
# tracked files — but the checks they require are USELESS unless this repo's
# workflows produce them under EXACTLY those context names. The standard warns:
# "a misnamed context permanently blocks PRs without producing the actual
# analysis." This guard pins the workflow contexts to the four required checks:
#
#   1. SonarCloud                          — sonarcloud.yml   (job `name:`)
#   2. CodeQL                              — GitHub default setup (no workflow file)
#   3. agent-shield / AgentShield          — agent-shield.yml  (job id / reusable job)
#   4. dependency-audit / Detect ecosystems — dependency-audit.yml (job id / reusable job)

WORKFLOWS="${BATS_TEST_DIRNAME}/../.github/workflows"
SONAR_YML="${WORKFLOWS}/sonarcloud.yml"
AGENT_SHIELD_YML="${WORKFLOWS}/agent-shield.yml"
DEP_AUDIT_YML="${WORKFLOWS}/dependency-audit.yml"

# ── Required check 1: SonarCloud ──────────────────────────────────────────────
@test "sonarcloud.yml exists" {
  [ -f "$SONAR_YML" ]
}

@test "sonarcloud.yml produces the 'SonarCloud' required check (job name)" {
  grep -qE '^[[:space:]]+name:[[:space:]]+SonarCloud[[:space:]]*$' "$SONAR_YML"
}

@test "sonarcloud.yml runs on pull_request (else the required check never reports)" {
  grep -qE '^[[:space:]]+pull_request:[[:space:]]*$' "$SONAR_YML"
}

# ── Required check 3: agent-shield / AgentShield ──────────────────────────────
@test "agent-shield.yml exists" {
  [ -f "$AGENT_SHIELD_YML" ]
}

@test "agent-shield.yml declares the 'agent-shield' caller job (context prefix)" {
  grep -qE '^[[:space:]]+agent-shield:[[:space:]]*$' "$AGENT_SHIELD_YML"
}

@test "agent-shield.yml calls the agent-shield reusable (produces 'AgentShield' job)" {
  grep -qF 'agent-shield-reusable.yml@agent-shield/stable' "$AGENT_SHIELD_YML"
}

@test "agent-shield.yml runs on pull_request (else the required check never reports)" {
  grep -qE '^[[:space:]]+pull_request:[[:space:]]*$' "$AGENT_SHIELD_YML"
}

# ── Required check 4: dependency-audit / Detect ecosystems ────────────────────
@test "dependency-audit.yml exists" {
  [ -f "$DEP_AUDIT_YML" ]
}

@test "dependency-audit.yml declares the 'dependency-audit' caller job (context prefix)" {
  grep -qE '^[[:space:]]+dependency-audit:[[:space:]]*$' "$DEP_AUDIT_YML"
}

@test "dependency-audit.yml calls the dependency-audit reusable (produces 'Detect ecosystems' job)" {
  grep -qF 'dependency-audit-reusable.yml@dependency-audit/stable' "$DEP_AUDIT_YML"
}

@test "dependency-audit.yml runs on pull_request (else the required check never reports)" {
  grep -qE '^[[:space:]]+pull_request:[[:space:]]*$' "$DEP_AUDIT_YML"
}

@test "dependency-audit.yml documents the exact 'dependency-audit / Detect ecosystems' required check" {
  grep -qF 'dependency-audit / Detect ecosystems' "$DEP_AUDIT_YML"
}
