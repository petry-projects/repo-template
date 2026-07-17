#!/usr/bin/env bats
# Compliance regression guard for push-protection.md#required-gitignore-entries:
# .gitignore MUST carry the baseline secret patterns so private key material and
# dotenv files are never committed. Minimum enforced set: .env, *.pem, *.key.

GITIGNORE="${BATS_TEST_DIRNAME}/../.gitignore"

@test ".gitignore exists at the repo root" {
  [ -f "$GITIGNORE" ]
}

@test ".gitignore ignores dotenv files" {
  grep -qE '^\.env$' "$GITIGNORE"
}

@test ".gitignore ignores PEM key material (*.pem)" {
  grep -qE '^\*\.pem$' "$GITIGNORE"
}

@test ".gitignore ignores private key files (*.key)" {
  grep -qE '^\*\.key$' "$GITIGNORE"
}
