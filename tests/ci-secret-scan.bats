#!/usr/bin/env bats
# Compliance regression guard for push-protection.md#required-ci-job:
# ci.yml must carry the canonical gitleaks secret-scan job and the repo must
# ship a .gitleaks.toml config, or the `Secret scan (gitleaks)` required check
# cannot run.

CI_YML="${BATS_TEST_DIRNAME}/../.github/workflows/ci.yml"
GITLEAKS_TOML="${BATS_TEST_DIRNAME}/../.gitleaks.toml"

# Print the body of a top-level job block — from `  <job>:` up to the next
# top-level job key — so an assertion can be scoped to a single job.
job_block() {
  awk -v job="$1" '
    $0 ~ "^  " job ":[[:space:]]*(#.*)?$" { f = 1; print; next }
    f && (/^  [A-Za-z][A-Za-z0-9_-]*:[[:space:]]*(#.*)?$/ || /^[A-Za-z]/) { f = 0 }
    f { print }
  ' "$CI_YML"
}

# First line number (within a block passed as the first argument $1) matching a regex.
first_line() {
  printf '%s\n' "$1" | grep -nE "$2" | head -1 | cut -d: -f1
}

@test "ci.yml defines a secret-scan job" {
  grep -qE '^  secret-scan:' "$CI_YML"
}

@test "secret-scan job has the required display name" {
  grep -qF 'name: Secret scan (gitleaks)' "$CI_YML"
}

@test "secret-scan checks out full git history" {
  grep -qE 'fetch-depth: 0' "$CI_YML"
}

@test "secret-scan installs the pinned, checksum-verified gitleaks version" {
  grep -qF 'GITLEAKS_VERSION: "8.30.1"' "$CI_YML"
  grep -qF 'GITLEAKS_CHECKSUM: "551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb"' "$CI_YML"
}

@test "secret-scan runs gitleaks detect with the required flags" {
  grep -qF 'gitleaks detect --source . --config .gitleaks.toml --redact --verbose --exit-code 1' "$CI_YML"
}

# Guards githubactions:S6506 — the gitleaks download must restrict redirects to
# HTTPS so a redirect can never downgrade the fetch to an insecure http:// host.
@test "secret-scan downloads gitleaks with insecure redirects disabled" {
  grep -qE "curl.*--proto-redir '=https'.*gitleaks\.tar\.gz" "$CI_YML"
}

# Compliance regression guard for ci.yml secret-scan reliability (issue #163).
#
# The `build-and-test` and `coverage` jobs already retry their apt installs
# (see ci-apt-retry.bats). The secret-scan job, however, fetched the gitleaks
# tarball with a single `curl` — one transient network failure (temporary DNS
# failure, a briefly-unavailable GitHub releases mirror) hard-failed the org
# required `Secret scan (gitleaks)` check, degrading the whole CI status. This
# guard pins the fix: the download must be wrapped in a bounded retry loop with a
# backoff and a post-loop failure gate so a transient fetch is retried instead of
# failing the run on the first attempt.
@test "secret-scan retries the gitleaks download" {
  block="$(job_block secret-scan)"

  # A bounded retry-loop opener (matched as a whole word so one-liner loops are
  # also caught) must exist within the secret-scan job.
  loop_line="$(first_line "$block" '([[:space:]]|^)(for|while|until)[[:space:]]')"
  [ -n "$loop_line" ] || { echo "secret-scan: gitleaks download is not wrapped in a retry loop"; return 1; }

  # Find the `done` that closes the loop so assertions can be scoped to its body.
  done_line="$(printf '%s\n' "$block" | awk -v lo="$loop_line" '
    NR > lo && /^[[:space:]]*done([[:space:]]|$)/ { print NR; exit }
  ')"
  [ -n "$done_line" ] || { echo "secret-scan: retry loop has no closing done"; return 1; }

  loop_body="$(printf '%s\n' "$block" | awk -v lo="$loop_line" -v hi="$done_line" 'NR >= lo && NR <= hi')"
  after_loop="$(printf '%s\n' "$block" | awk -v lo="$done_line" 'NR > lo')"

  # The loop must be bounded to three attempts.
  printf '%s\n' "$loop_body" | grep -qE 'in[[:space:]]+(1[[:space:]]+2[[:space:]]+3|[{]1\.\.3[}])' \
    || { echo "secret-scan: retry loop is not bounded to 3 attempts"; return 1; }

  # The gitleaks download (curl) must live inside the retry loop.
  [ -n "$(first_line "$loop_body" '([[:space:]]|^)curl[[:space:]]')" ] \
    || { echo "secret-scan: curl download not found inside the retry loop"; return 1; }

  # The backoff sleep must be guarded by an attempt-less-than-3 check so the
  # final attempt does not emit a spurious "retrying" message or waste 5 s.
  printf '%s\n' "$loop_body" | grep -qE '\[.*"?\$attempt"?[[:space:]]+-lt[[:space:]]+3' \
    || { echo "secret-scan: retry sleep is not guarded by attempt < 3 check"; return 1; }
  [ -n "$(first_line "$loop_body" '([[:space:]]|^)sleep[[:space:]]')" ] \
    || { echo "secret-scan: retry loop has no backoff sleep"; return 1; }

  # A post-loop failure gate must exist after the closing done so an exhausted
  # retry loop fails loudly rather than checksumming a missing/partial tarball.
  printf '%s\n' "$after_loop" | grep -qE '(command[[:space:]]+-v|test[[:space:]]+-s|\[[[:space:]]+-s)' \
    || { echo "secret-scan: no post-loop failure check after the retry loop"; return 1; }
}

@test ".gitleaks.toml config exists at the repo root" {
  [ -f "$GITLEAKS_TOML" ]
}

@test ".gitleaks.toml declares an allowlist section" {
  grep -qE '^\[allowlist\]' "$GITLEAKS_TOML"
}
