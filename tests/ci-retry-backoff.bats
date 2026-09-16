#!/usr/bin/env bats
# Compliance regression guard for ci.yml retry-backoff reliability (issue #204).
#
# The CI workflow degraded to a 25% failure rate (2 / 8 runs) with a *pure*
# fast-failure signature — p50 25s, p95 33s, no stall tail — landing immediately
# after the concurrency-key fix (#201). Prior remediations hardened every network
# surface: apt/gitleaks are retried (#155, #163), each network command is
# per-attempt time-bounded (#196), and every job is timeout-capped (#169). What
# remained was the *width* of the retry window: each retry loop is bounded to three
# attempts (pinned by ci-apt-retry.bats / ci-secret-scan.bats) spaced by a FIXED
# `sleep 5`, so the whole window spans only ~10s. A transient outage that outlasts
# that window — a briefly-wedged mirror, a slow DNS recovery, or dpkg-lock
# contention from the runner's background unattended-upgrades — burns all three
# attempts within seconds and fast-fails the job, exactly the tight fast-failure
# band the Fleet Monitor flagged. (The repo's own flaky-endpoint convention in
# sonarcloud.yml already waits 30s before retrying; ci.yml waited only 5s.)
#
# This guard pins the fix: every retry-loop backoff must GROW with the attempt
# counter (an increasing/exponential backoff) instead of sleeping a fixed constant,
# so the effective retry window is wide enough to ride out a short transient outage
# rather than exhausting on the first blip. It complements ci-apt-retry.bats /
# ci-secret-scan.bats (which pin the retry loops themselves and the 3-attempt bound)
# and ci-network-timeout.bats (which pins the per-attempt ceiling).

CI_YML="${BATS_TEST_DIRNAME}/../.github/workflows/ci.yml"

# Every retry-loop backoff line: a `sleep` guarded by the `$attempt -lt 3` check
# that gates the pre-final-attempt wait. Comment lines are dropped so a
# commented-out backoff can never satisfy a guard.
backoff_lines() {
  grep -vE '^[[:space:]]*#' "$CI_YML" \
    | awk '{ if (sub(/\\$/, "")) printf "%s ", $0; else print }' \
    | grep -E '\[[[:space:]]*"?\$attempt"?[[:space:]]+-lt[[:space:]]+3[[:space:]]*\].*([[:space:]]|;|&)sleep[[:space:]]' || true
}

@test "ci.yml exists at the expected path" {
  [ -f "$CI_YML" ]
}

@test "ci.yml declares exactly three attempt-bounded retry loops" {
  # build-and-test install, coverage install, and secret-scan download. Pinning the
  # count means a newly-added retry loop cannot slip in without a backoff guard, and
  # a removed one cannot make the per-loop assertions below pass vacuously.
  local count
  count="$(grep -vE '^[[:space:]]*#' "$CI_YML" \
    | grep -cE 'for[[:space:]]+attempt[[:space:]]+in[[:space:]]+1[[:space:]]+2[[:space:]]+3' || true)"
  [ "$count" -eq 3 ] || { echo "expected 3 attempt-bounded retry loops, found $count"; return 1; }
}

@test "every retry loop has a backoff sleep" {
  local count
  count="$(backoff_lines | grep -c 'sleep' || true)"
  [ "$count" -eq 3 ] || { echo "expected 3 attempt-guarded backoff sleeps, found $count"; return 1; }
}

@test "every retry backoff scales with the attempt counter (increasing backoff)" {
  # The sleep argument must reference the attempt counter so the wait grows across
  # attempts, widening the retry window enough to outlast a short transient outage.
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    printf '%s\n' "$line" | grep -qE 'sleep[[:space:]]+.*attempt' \
      || { echo "retry backoff does not scale with \$attempt: $line"; return 1; }
  done < <(backoff_lines)
}

@test "no retry backoff uses a fixed-constant sleep" {
  # A bare `sleep <n>` is the ~10s fixed window that fast-fails on a transient
  # outage (issue #204 root cause); reject it directly.
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if printf '%s\n' "$line" | grep -qE 'sleep[[:space:]]+[0-9]+([[:space:]]|;|$)'; then
      echo "retry backoff uses a fixed-constant sleep: $line"
      return 1
    fi
  done < <(backoff_lines)
}
