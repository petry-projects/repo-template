#!/usr/bin/env bats
# Compliance regression guard for SonarCloud githubactions:S7635
# ("Only pass required secrets to this workflow").
#
# The thin caller stubs must NOT blanket-forward every org/repo secret to a
# reusable workflow via `secrets: inherit`. Instead each stub enumerates only
# the secrets its reusable actually consumes — matching the already-compliant
# dependabot-rebase.yml stub. See issue #28.

WF_DIR="${BATS_TEST_DIRNAME}/../.github/workflows"

# ── No stub may use `secrets: inherit` ────────────────────────────────────────

@test "auto-rebase.yml does not use 'secrets: inherit'" {
  ! grep -qE '^\s*secrets:\s*inherit' "$WF_DIR/auto-rebase.yml"
}

@test "dependabot-automerge.yml does not use 'secrets: inherit'" {
  ! grep -qE '^\s*secrets:\s*inherit' "$WF_DIR/dependabot-automerge.yml"
}

@test "dev-lead.yml does not use 'secrets: inherit'" {
  ! grep -qE '^\s*secrets:\s*inherit' "$WF_DIR/dev-lead.yml"
}

@test "pr-review-mention.yml does not use 'secrets: inherit'" {
  ! grep -qE '^\s*secrets:\s*inherit' "$WF_DIR/pr-review-mention.yml"
}

# ── Each stub enumerates exactly its documented secret set ────────────────────

@test "auto-rebase.yml passes no secrets (GITHUB_TOKEN only)" {
  # Reusable uses GITHUB_TOKEN only; the stub must carry no job-level secrets block.
  ! grep -qE '^\s*secrets:' "$WF_DIR/auto-rebase.yml"
}

@test "dependabot-automerge.yml enumerates APP_ID and APP_PRIVATE_KEY" {
  grep -qE '^\s*APP_ID:\s*\$\{\{\s*secrets\.APP_ID\s*\}\}' "$WF_DIR/dependabot-automerge.yml"
  grep -qE '^\s*APP_PRIVATE_KEY:\s*\$\{\{\s*secrets\.APP_PRIVATE_KEY\s*\}\}' "$WF_DIR/dependabot-automerge.yml"
}

@test "dev-lead.yml enumerates the required CLAUDE_CODE_OAUTH_TOKEN secret" {
  grep -qE '^\s*CLAUDE_CODE_OAUTH_TOKEN:\s*\$\{\{\s*secrets\.CLAUDE_CODE_OAUTH_TOKEN\s*\}\}' "$WF_DIR/dev-lead.yml"
}

@test "pr-review-mention.yml enumerates GH_PAT_WORKFLOWS" {
  grep -qE '^\s*GH_PAT_WORKFLOWS:\s*\$\{\{\s*secrets\.GH_PAT_WORKFLOWS\s*\}\}' "$WF_DIR/pr-review-mention.yml"
}
