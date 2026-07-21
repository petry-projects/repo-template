#!/usr/bin/env bats
# S7635 regression guard: reusable-workflow caller stubs must forward only the
# secrets the called reusable declares — never a blanket `secrets: inherit`,
# which hands the reusable every org/repo secret (SonarCloud githubactions:S7635,
# "Only pass required secrets to this workflow").
#
# The org-canonical form is an explicit `secrets:` mapping (see the already-
# compliant siblings dependabot-rebase.yml, pr-review-mention.yml, and
# add-to-project.yml). A caller whose reusable needs no secrets (GITHUB_TOKEN is
# auto-provided) omits the `secrets:` key entirely. This guard pins that
# invariant fleet-wide so a regression is caught in CI, not in SonarCloud.

WORKFLOWS="${BATS_TEST_DIRNAME}/../.github/workflows"

@test "no caller stub uses blanket 'secrets: inherit'" {
  [ -d "$WORKFLOWS" ] || { echo "Workflows directory not found: $WORKFLOWS" >&2; return 1; }
  # Anchored to the mapping line (leading whitespace only) so prose mentions of
  # `secrets: inherit` inside comment banners don't count.
  if grep -rEn '^[[:space:]]+secrets:[[:space:]]*inherit[[:space:]]*$' "$WORKFLOWS"; then
    echo "Found 'secrets: inherit' above — replace with an explicit named-secrets" >&2
    echo "block that forwards only the secrets the reusable declares (S7635)." >&2
    return 1
  fi
}

@test "auto-rebase stub forwards no secrets (reusable uses GITHUB_TOKEN only)" {
  STUB="$WORKFLOWS/auto-rebase.yml"
  [ -f "$STUB" ] || { echo "Stub file not found: $STUB" >&2; return 1; }
  if grep -qE '^[[:space:]]+secrets:' "$STUB"; then
    echo "auto-rebase.yml must not forward any secrets — it uses GITHUB_TOKEN only." >&2
    return 1
  fi
}

@test "dependabot-automerge stub forwards exactly APP_ID + APP_PRIVATE_KEY" {
  STUB="$WORKFLOWS/dependabot-automerge.yml"
  [ -f "$STUB" ] || { echo "Stub file not found: $STUB" >&2; return 1; }
  grep -qF 'APP_ID: ${{ secrets.APP_ID }}' "$STUB" \
    || { echo "Missing explicit APP_ID secret"; return 1; }
  grep -qF 'APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}' "$STUB" \
    || { echo "Missing explicit APP_PRIVATE_KEY secret"; return 1; }
  count=$(grep -cE '^[[:space:]]+[A-Z_]+:[[:space:]]*\$\{\{[[:space:]]*secrets\.' "$STUB")
  [ "$count" -eq 2 ] \
    || { echo "Expected exactly 2 forwarded secrets, found $count — remove extras (S7635)"; return 1; }
}

@test "dev-lead stub forwards its documented named secrets, not inherit" {
  STUB="$WORKFLOWS/dev-lead.yml"
  [ -f "$STUB" ] || { echo "Stub file not found: $STUB" >&2; return 1; }
  grep -qF 'CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}' "$STUB" \
    || { echo "Missing explicit CLAUDE_CODE_OAUTH_TOKEN secret"; return 1; }
  grep -qF 'GH_PAT_WORKFLOWS: ${{ secrets.GH_PAT_WORKFLOWS }}' "$STUB" \
    || { echo "Missing explicit GH_PAT_WORKFLOWS secret"; return 1; }
  grep -qF 'GOOGLE_API_KEY: ${{ secrets.GOOGLE_API_KEY }}' "$STUB" \
    || { echo "Missing explicit GOOGLE_API_KEY secret"; return 1; }
  grep -qF 'GH_PAT: ${{ secrets.GH_PAT }}' "$STUB" \
    || { echo "Missing explicit GH_PAT secret"; return 1; }
  count=$(grep -cE '^[[:space:]]+[A-Z_]+:[[:space:]]*\$\{\{[[:space:]]*secrets\.' "$STUB")
  [ "$count" -eq 4 ] \
    || { echo "Expected exactly 4 forwarded secrets, found $count — remove extras or update this test (S7635)"; return 1; }
}
