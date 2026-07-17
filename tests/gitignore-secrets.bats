#!/usr/bin/env bats
# Compliance regression guard for push-protection.md#required-gitignore-entries:
# .gitignore MUST carry the baseline secret patterns so private key material and
# dotenv files are never committed. Minimum enforced set: .env, *.pem, *.key.

GITIGNORE="${BATS_TEST_DIRNAME}/../.gitignore"

# Normalize line endings (handles both LF and CRLF) for cross-platform compatibility.
has_entry() {
  local pattern="$1"
  tr -d '\r' < "$GITIGNORE" | grep -qE "$pattern"
}

@test ".gitignore exists at the repo root" {
  [ -f "$GITIGNORE" ]
}

@test ".gitignore ignores dotenv files" {
  has_entry '^\.env$'
}

@test ".gitignore ignores PEM key material (*.pem)" {
  has_entry '^\*\.pem$'
}

@test ".gitignore ignores private key files (*.key)" {
  has_entry '^\*\.key$'
}
