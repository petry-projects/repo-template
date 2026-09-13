#!/usr/bin/env bats
# Compliance regression guard for ci.yml network-operation reliability (issue #196).
#
# The CI workflow failed at ~75% across the monitored window with the classic
# bimodal "normal vs. stalled" signature (p50 61s, p95 1245s). Prior remediations
# hardened the *retry* surface (#152 stale apt index, #155 transient apt install
# retry, #163 gitleaks download retry) and bounded the total job runtime (#169
# per-job timeout-minutes). But the retry loops wrap network commands that are
# NOT bounded per attempt: a single stalled `apt-get update`/`apt-get install`/
# `curl` (a wedged mirror, a hung DNS lookup, a half-open TCP connection) blocks
# the loop indefinitely — a retry loop "never advances while its command is
# blocked" (see ci-job-timeout.bats). The job then runs until the 10-minute job
# timeout kills it and is counted as a FAILURE, not a recovery, inflating both
# p95 and the failure rate.
#
# This guard pins the fix: every network command inside a CI retry loop must be
# bounded per attempt — apt commands wrapped in `timeout <seconds>`, and the
# gitleaks download given `curl --max-time <seconds>` — so a stall is killed
# quickly and the surrounding retry loop can actually recover on the next attempt
# instead of consuming the whole job budget. It complements ci-apt-retry.bats /
# ci-secret-scan.bats (which pin the retry loops themselves) and
# ci-job-timeout.bats (which pins the per-job ceiling).

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

# Assert that a job's apt commands are each bounded by a per-attempt `timeout`,
# so a stalled apt operation is killed quickly and the retry loop can recover.
assert_apt_is_time_bounded() {
  local job="$1" block
  block="$(job_block "$job")"

  local update_line install_line
  update_line="$(printf '%s\n' "$block" | grep -E 'apt(-get)?([[:space:]]+-[a-zA-Z0-9-]+)*[[:space:]]+update' | head -1)"
  install_line="$(printf '%s\n' "$block" | grep -E 'apt(-get)?[[:space:]]+install' | head -1)"

  [ -n "$update_line" ] || { echo "$job: no apt update command found"; return 1; }
  [ -n "$install_line" ] || { echo "$job: no apt install command found"; return 1; }

  # `timeout <seconds>` must govern each apt network command so a wedged mirror
  # or DNS stall is bounded to a few seconds per attempt, not the whole job.
  printf '%s\n' "$update_line" | grep -qE 'timeout[[:space:]]+[0-9]+' \
    || { echo "$job: apt update is not bounded by a per-attempt 'timeout <seconds>'"; return 1; }
  printf '%s\n' "$install_line" | grep -qE 'timeout[[:space:]]+[0-9]+' \
    || { echo "$job: apt install is not bounded by a per-attempt 'timeout <seconds>'"; return 1; }
}

@test "ci.yml exists at the expected path" {
  [ -f "$CI_YML" ]
}

@test "build-and-test bounds its apt commands with a per-attempt timeout" {
  assert_apt_is_time_bounded build-and-test
}

@test "coverage bounds its apt commands with a per-attempt timeout" {
  assert_apt_is_time_bounded coverage
}

@test "secret-scan bounds the gitleaks download with curl --max-time" {
  block="$(job_block secret-scan)"
  curl_line="$(printf '%s\n' "$block" | grep -E '([[:space:]]|^)curl[[:space:]]' | head -1)"
  [ -n "$curl_line" ] || { echo "secret-scan: no curl download command found"; return 1; }
  # curl must cap the total transfer time so a half-open connection cannot hang
  # the download until the job timeout; the retry loop then recovers on retry.
  printf '%s\n' "$curl_line" | grep -qE -- '--max-time[[:space:]]+[0-9]+' \
    || { echo "secret-scan: gitleaks curl is not bounded by --max-time <seconds>"; return 1; }
}
