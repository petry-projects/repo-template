#!/usr/bin/env bats
# Compliance regression guard for ci.yml runner-setup reliability (issue #152).
#
# The CI workflow failed at ~80% across the monitored window for two runner-setup
# reasons, both guarded here:
#   1. The coverage job tried to `apt-get install kcov`. kcov is not in the Ubuntu
#      runner's apt repositories, so every run died with
#      "E: Unable to locate package kcov".
#   2. bats was installed without first refreshing the apt package index, which
#      fails intermittently once the runner image's cached index goes stale.

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

@test "ci.yml exists at the expected path" {
  [ -f "$CI_YML" ]
}

@test "build-and-test refreshes the apt cache before installing packages" {
  block="$(job_block build-and-test)"
  update_line="$(printf '%s\n' "$block" | grep -nE 'apt(-get)?([[:space:]]+-[a-zA-Z0-9-]+)*[[:space:]]+update' | head -1 | cut -d: -f1)"
  install_line="$(printf '%s\n' "$block" | grep -nE 'apt(-get)?([[:space:]]+-[a-zA-Z0-9-]+)*[[:space:]]+install' | head -1 | cut -d: -f1)"
  # An install must be present, and an update must run before it so a stale
  # package index can never turn "install bats" into a hard failure.
  [ -n "$install_line" ]
  [ -n "$update_line" ]
  [ "$update_line" -lt "$install_line" ]
}

@test "coverage refreshes the apt cache before installing packages" {
  block="$(job_block coverage)"
  update_line="$(printf '%s\n' "$block" | grep -nE 'apt(-get)?([[:space:]]+-[a-zA-Z0-9-]+)*[[:space:]]+update' | head -1 | cut -d: -f1)"
  install_line="$(printf '%s\n' "$block" | grep -nE 'apt(-get)?([[:space:]]+-[a-zA-Z0-9-]+)*[[:space:]]+install' | head -1 | cut -d: -f1)"
  [ -n "$install_line" ]
  [ -n "$update_line" ]
  [ "$update_line" -lt "$install_line" ]
}

@test "ci.yml never apt-get installs the uninstallable kcov package" {
  # kcov is absent from the Ubuntu runner's apt repositories; installing it is the
  # documented root cause of issue #152. Any coverage stack must install a package
  # that actually resolves.
  ! grep -qE 'apt(-get)?[[:space:]]+install.*[[:space:]]kcov([[:space:]]|$)' "$CI_YML"
}
