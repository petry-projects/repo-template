#!/usr/bin/env bats
# Compliance regression guard for ci.yml job-timeout reliability (issue #169).
#
# The CI workflow failed at ~60% across the monitored window with a p50 of 20s but
# a p95 of 404s — the classic bimodal "normal vs. stalled" signature. Prior
# remediations hardened the *retry* surface (#152 stale apt index, #155 transient
# apt install retry, #163 gitleaks download retry) but every job could still hang
# for GitHub's 360-minute default when a network operation stalls without ever
# returning (apt/curl/checkout wedged on a bad mirror or DNS) — a retry loop never
# advances while its command is blocked. An un-bounded hang inflates p95, ties up a
# runner, and ultimately counts against the workflow's failure rate.
#
# This guard pins the fix: every runner job in ci.yml must declare a bounded
# `timeout-minutes` so a stalled run fails fast instead of consuming the full
# default budget. It complements ci-runner-setup.bats / ci-apt-retry.bats /
# ci-secret-scan.bats, which harden the individual install/download surfaces.

CI_YML="${BATS_TEST_DIRNAME}/../.github/workflows/ci.yml"

# Upper bound for a sane CI job timeout. Normal runs finish in ~20s (p50); a cap
# far above that still catches a wedged run well before the 360-minute default.
MAX_TIMEOUT_MINUTES=30

# Print the body of a top-level job block — from `  <job>:` up to the next
# top-level job key — so an assertion can be scoped to a single job.
job_block() {
  awk -v job="$1" '
    $0 ~ "^  " job ":[[:space:]]*(#.*)?$" { f = 1; print; next }
    f && (/^  [A-Za-z][A-Za-z0-9_-]*:[[:space:]]*(#.*)?$/ || /^[A-Za-z]/) { f = 0 }
    f { print }
  ' "$CI_YML"
}

# List every top-level job that targets a runner (has a `runs-on:` line). This
# discovers jobs dynamically so a newly-added runner job is covered automatically.
runner_jobs() {
  awk '
    /^  [A-Za-z][A-Za-z0-9_-]*:[[:space:]]*(#.*)?$/ {
      name = $1; sub(/:$/, "", name); job = name
    }
    job && /^    runs-on:/ && !printed[job] {
      print job; printed[job] = 1
    }
  ' "$CI_YML"
}

# The job-level `timeout-minutes:` integer value, or empty if none. Anchored to
# the 4-space job-key indentation so a deeper step-level `timeout-minutes:` can
# never satisfy the guard on behalf of the whole job.
job_timeout_value() {
  job_block "$1" \
    | grep -E '^    timeout-minutes:[[:space:]]*[0-9]+[[:space:]]*(#.*)?$' \
    | head -1 \
    | sed -E 's/^    timeout-minutes:[[:space:]]*([0-9]+).*/\1/'
}

@test "ci.yml exists at the expected path" {
  [ -f "$CI_YML" ]
}

@test "ci.yml declares at least one runner job" {
  # Guards the discovery helper itself: if this ever finds nothing, the
  # per-job timeout assertions below would vacuously pass.
  run runner_jobs
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "every runner job declares a bounded timeout-minutes" {
  local failures=0
  while IFS= read -r job; do
    [ -n "$job" ] || continue
    local value
    value="$(job_timeout_value "$job")"
    if [ -z "$value" ]; then
      echo "$job: no job-level 'timeout-minutes' — a stalled run can hang for the 360-minute default"
      failures=1
      continue
    fi
    if [ "$value" -lt 1 ]; then
      echo "$job: timeout-minutes must be a positive integer (got '$value')"
      failures=1
    fi
    if [ "$value" -gt "$MAX_TIMEOUT_MINUTES" ]; then
      echo "$job: timeout-minutes '$value' exceeds the sane cap of ${MAX_TIMEOUT_MINUTES}m"
      failures=1
    fi
  done < <(runner_jobs)
  [ "$failures" -eq 0 ]
}
