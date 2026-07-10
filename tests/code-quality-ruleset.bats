#!/usr/bin/env bats
# Compliance regression guard for
# github-settings.md#code-quality--required-checks-ruleset-all-repositories:
#
# The org `code-quality` ruleset (source of truth: standards/rulesets/code-quality.json
# in petry-projects/.github, applied via apply-rulesets.sh) makes four status-check
# contexts required merge gates on every repo it targets. If this template stops
# producing a context — or renames the job that produces it — the ruleset becomes
# unsatisfiable and every PR is permanently blocked. These tests pin the exact job
# and workflow names so that drift is caught here instead of on a bricked PR.
#
# Codified `code-quality` contexts and their producers in this template:
#   SonarCloud                            -> .github/workflows/sonarcloud.yml
#   agent-shield / AgentShield            -> .github/workflows/agent-shield.yml
#   dependency-audit / Detect ecosystems  -> .github/workflows/dependency-audit.yml
#   CodeQL                                -> GitHub-managed default setup (no repo file)
#
# Live ruleset creation is a manual, admin-token procedure (Ruleset Remediation
# Runbook); this guard keeps the template's producers stable so it stays satisfiable.

WF_DIR="${BATS_TEST_DIRNAME}/../.github/workflows"
SONAR_YML="${WF_DIR}/sonarcloud.yml"
AGENT_SHIELD_YML="${WF_DIR}/agent-shield.yml"
DEP_AUDIT_YML="${WF_DIR}/dependency-audit.yml"

# ── SonarCloud context ────────────────────────────────────────────────────────

@test "sonarcloud.yml exists" {
  [ -f "$SONAR_YML" ]
}

@test "sonarcloud.yml declares the 'SonarCloud' required-check job name" {
  grep -qE '^    name: SonarCloud$' "$SONAR_YML"
}

# ── agent-shield / AgentShield context ────────────────────────────────────────

@test "agent-shield.yml exists" {
  [ -f "$AGENT_SHIELD_YML" ]
}

@test "agent-shield.yml keeps the 'AgentShield' workflow name" {
  grep -qE '^name: AgentShield$' "$AGENT_SHIELD_YML"
}

@test "agent-shield.yml keeps the 'agent-shield' job id (required-check prefix)" {
  grep -qE '^  agent-shield:' "$AGENT_SHIELD_YML"
}

@test "agent-shield.yml calls the org agent-shield reusable" {
  grep -qF 'agent-shield-reusable.yml@agent-shield/stable' "$AGENT_SHIELD_YML"
}

# ── dependency-audit / Detect ecosystems context ──────────────────────────────

@test "dependency-audit.yml exists" {
  [ -f "$DEP_AUDIT_YML" ]
}

@test "dependency-audit.yml keeps the 'dependency-audit' job id (required-check prefix)" {
  grep -qE '^  dependency-audit:' "$DEP_AUDIT_YML"
}

@test "dependency-audit.yml calls the org dependency-audit reusable" {
  grep -qF 'dependency-audit-reusable.yml@dependency-audit/stable' "$DEP_AUDIT_YML"
}

# ── CodeQL context ────────────────────────────────────────────────────────────
# CodeQL is produced by GitHub-managed default setup and reports as exactly
# `CodeQL`. A committed CodeQL workflow would instead emit `Analyze (<lang>)`
# contexts, which would NOT satisfy the codified `CodeQL` required check. Guard
# against a template shipping such a workflow.

@test "no committed CodeQL workflow shadows the GitHub-managed 'CodeQL' check" {
  run bash -c 'ls "'"$WF_DIR"'"/codeql*.yml "'"$WF_DIR"'"/codeql*.yaml 2>/dev/null'
  [ "$status" -ne 0 ]
}
