#!/usr/bin/env bats
# Compliance regression guard for ci.yml apt-install reliability (issue #155).
#
# Issue #152 removed the uninstallable `kcov` package and added an `apt-get update`
# before `apt-get install` so a stale package index could not turn a bats install
# into a hard failure. It did NOT make apt resilient to *transient* failures:
# `apt-get update` / `apt-get install` still ran exactly once, so a single network
# hiccup (temporary DNS failure, hash-sum mismatch, a briefly-unavailable mirror)
# hard-fails the whole job on the first attempt — the same install surface that
# produced the #152 `kcov` failures.
#
# This guard pins the fix: every job that installs packages via apt must wrap the
# install in a bounded retry loop with a backoff, so a transient failure is retried
# instead of failing the run. It complements ci-runner-setup.bats (which pins the
# update-before-install ordering and the kcov ban).

CI_YML="${BATS_TEST_DIRNAME}/../.github/workflows/ci.yml"

# Print the body of a top-level job block — from `  <job>:` up to the next
# top-level job key — so an assertion can be scoped to a single job.
job_block() {
  awk -v job="$1" '
    $0 ~ "^  " job ":[[:space:]]*(#.*)?$" { f = 1; print; next }
    f && (/^  [A-Za-z][A-Za-z0-9_-]*:[[:space:]]*(#.*)?$/ || /^[A-Za-z]/) { f = 0 }
    f { print }
  ' "$CI_YML"
}

# First line number (within a job block) matching a regex, or empty if none.
first_line() {
  printf '%s\n' "$1" | grep -nE "$2" | head -1 | cut -d: -f1
}

# Assert that a single job block wraps its apt install in a bounded retry loop.
assert_apt_install_is_retried() {
  local job="$1" block
  block="$(job_block "$job")"

  local install_line update_line loop_line sleep_line
  install_line="$(first_line "$block" 'apt(-get)?([[:space:]]+-[a-zA-Z0-9-]+)*[[:space:]]+install')"
  update_line="$(first_line "$block" 'apt(-get)?([[:space:]]+-[a-zA-Z0-9-]+)*[[:space:]]+update')"
  loop_line="$(first_line "$block" '^[[:space:]]*(for|while|until)[[:space:]]')"
  sleep_line="$(first_line "$block" '^[[:space:]]*sleep[[:space:]]')"

  # An install must exist, and an update must precede it (preserves the #152 fix).
  [ -n "$install_line" ] || { echo "$job: no apt install found"; return 1; }
  [ -n "$update_line" ] || { echo "$job: no apt update found"; return 1; }
  [ "$update_line" -lt "$install_line" ] || { echo "$job: apt update must precede install"; return 1; }

  # A retry loop must open before the install, and a backoff sleep must be present,
  # so a transient apt failure is retried rather than failing the run outright.
  [ -n "$loop_line" ] || { echo "$job: apt install is not wrapped in a retry loop"; return 1; }
  [ "$loop_line" -lt "$install_line" ] || { echo "$job: retry loop must open before the apt install"; return 1; }
  [ -n "$sleep_line" ] || { echo "$job: retry loop has no backoff sleep"; return 1; }
}

@test "ci.yml exists at the expected path" {
  [ -f "$CI_YML" ]
}

@test "build-and-test retries its apt package install" {
  assert_apt_install_is_retried build-and-test
}

@test "coverage retries its apt package install" {
  assert_apt_install_is_retried coverage
}

@test "no apt-using job installs the uninstallable kcov package" {
  # Reinforce the #152 invariant at the same time we harden the install: a retry
  # loop must never sit atop a package that can never resolve.
  ! grep -qE 'apt(-get)?[[:space:]]+install.*[[:space:]]kcov([[:space:]]|$)' "$CI_YML"
}
