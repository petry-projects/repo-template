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
# top-level job key — so an assertion can be scoped to a single job. Comment lines
# are dropped and `\`-continued lines are joined so a command split across several
# lines for readability is matched as a single logical command (and a commented-out
# command can never satisfy a guard).
job_block() {
  awk -v job="$1" '
    $0 ~ "^  " job ":[[:space:]]*(#.*)?$" { f = 1; print; next }
    f && (/^  [A-Za-z][A-Za-z0-9_-]*:[[:space:]]*(#.*)?$/ || /^[A-Za-z]/) { f = 0 }
    f { print }
  ' "$CI_YML" | grep -v '^[[:space:]]*#' | awk '{ if (sub(/\\$/, "")) printf "%s ", $0; else print }'
}

# Assert that a job's apt commands are each bounded by a per-attempt `timeout`,
# so a stalled apt operation is killed quickly and the retry loop can recover.
assert_apt_is_time_bounded() {
  local job="$1" block
  block="$(job_block "$job")"

  local update_line install_line
  update_line="$(printf '%s\n' "$block" | grep -E 'apt(-get)?([[:space:]]+-[a-zA-Z0-9-]+)*[[:space:]]+update' | head -1)"
  install_line="$(printf '%s\n' "$block" | grep -E 'apt(-get)?([[:space:]]+-[a-zA-Z0-9-]+)*[[:space:]]+install' | head -1)"

  # Jobs that invoke apt subcommands must be checked. If apt is present but no
  # recognized update/install pattern matched, fail closed (not silently skip).
  # Match apt with network-relevant subcommands to avoid false positives from prose.
  if printf '%s\n' "$block" | grep -qE 'apt(-get)?[[:space:]]+(update|install|upgrade|dist-upgrade|autoremove|clean|autoclean)'; then
    [ -n "$update_line" ] || [ -n "$install_line" ] || { echo "$job: apt command found but no 'update'/'install' pattern matched — add timeout bound"; return 1; }
  else
    return 0
  fi

  # `timeout <seconds>` must directly govern each apt network command — i.e. the
  # `timeout <n>` token must immediately precede the apt invocation (an optional
  # `sudo` between them is allowed). Requiring the binding, rather than a bare
  # `timeout` anywhere on the line, closes the gap where unrelated text containing
  # the word `timeout` could satisfy the guard while apt itself stays unbounded.
  if [ -n "$update_line" ]; then
    printf '%s\n' "$update_line" | grep -qE 'timeout[[:space:]]+[0-9]+[[:space:]]+(sudo[[:space:]]+)?apt(-get)?([[:space:]]+-[a-zA-Z0-9-]+)*[[:space:]]+update' \
      || { echo "$job: apt update is not directly bounded by a per-attempt 'timeout <seconds>'"; return 1; }
  fi
  if [ -n "$install_line" ]; then
    printf '%s\n' "$install_line" | grep -qE 'timeout[[:space:]]+[0-9]+[[:space:]]+(sudo[[:space:]]+)?apt(-get)?([[:space:]]+-[a-zA-Z0-9-]+)*[[:space:]]+install' \
      || { echo "$job: apt install is not directly bounded by a per-attempt 'timeout <seconds>'"; return 1; }
  fi
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

@test "secret-scan bounds the gitleaks download with curl --connect-timeout and --max-time" {
  block="$(job_block secret-scan)"
  curl_lines="$(printf '%s\n' "$block" | grep -E '([[:space:]]|^)curl[[:space:]]')"
  [ -n "$curl_lines" ] || { echo "secret-scan: no curl download command found"; return 1; }
  # Every curl invocation must cap both the connection-establishment time
  # (--connect-timeout) and the total transfer time (--max-time) so neither a hung
  # DNS/TCP handshake nor a half-open connection mid-transfer can hang the download
  # until the job timeout; the retry loop then recovers on retry. Checking every
  # curl line — not just the first — closes the gap where a second, unbounded
  # download (e.g. an added tool fetch) could slip in without failing this guard.
  while IFS= read -r curl_line; do
    [ -n "$curl_line" ] || continue
    printf '%s\n' "$curl_line" | grep -qE -- '--connect-timeout[[:space:]]+[0-9]+' \
      || { echo "secret-scan: a gitleaks curl is not bounded by --connect-timeout <seconds>: $curl_line"; return 1; }
    printf '%s\n' "$curl_line" | grep -qE -- '--max-time[[:space:]]+[0-9]+' \
      || { echo "secret-scan: a gitleaks curl is not bounded by --max-time <seconds>: $curl_line"; return 1; }
  done <<< "$curl_lines"
}
