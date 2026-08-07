#!/usr/bin/env bats
# Drift & compliance regression guard for the dependency-audit thin caller stub.
#
# .github/workflows/dependency-audit.yml is a THIN CALLER STUB whose ecosystem
# detection and vulnerability-audit logic live entirely in the central reusable
# (petry-projects/.github → .github/workflows/dependency-audit-reusable.yml). It
# is adopted VERBATIM: its own "AGENTS — READ BEFORE EDITING" banner says you may
# change nothing in normal use, and MUST NOT change the trigger events, the
# `uses:` line, or the job name (the job feeds the required status check). Any
# other diff is drift — the silent-revert class of failure the fleet stub-drift
# monitor exists to catch (fleet_stub_drift.sh). This guard pins those invariants
# so drift is caught in CI rather than in production run health.
#
# NOTE: this guard cannot catch transient upstream failures (e.g. an advisory-DB
# fetch hiccup inside the reusable's audit step) — those are hardened in the
# central reusable, not in this caller stub.

STUB="${BATS_TEST_DIRNAME}/../.github/workflows/dependency-audit.yml"

@test "dependency-audit stub exists" {
  [ -f "$STUB" ]
}

@test "stub carries no TODO/FIXME marker (SonarCloud githubactions:S1135 regression guard)" {
  if grep -nE '(TODO|FIXME)' "$STUB"; then
    echo "Error: $STUB still contains a TODO/FIXME marker — SonarCloud S1135 will re-open." >&2
    echo "Complete the task and reword the comment instead of leaving a TODO." >&2
    return 1
  fi
}

@test "dependency-audit stub is byte-identical to the canonical template" {
  # Inline canonical snapshot — update this heredoc whenever the central template
  # (petry-projects/.github/standards/workflows/dependency-audit.yml) changes.
  local canon
  canon="$(mktemp)"
  # The committed stub has NO trailing newline, so emit the heredoc with its
  # trailing newline stripped (printf '%s') to stay byte-faithful to the
  # committed, production stub that the fleet stub-drift monitor compares SHAs against.
  printf '%s' "$(cat << 'CANONICAL'
# ─────────────────────────────────────────────────────────────────────────────
# SOURCE OF TRUTH: petry-projects/.github/standards/workflows/dependency-audit.yml
# Standard:        petry-projects/.github/standards/ci-standards.md#7-dependency-audit-dependency-audityml
# Reusable:        petry-projects/.github/.github/workflows/dependency-audit-reusable.yml
#
# AGENTS — READ BEFORE EDITING:
#   • This file is a THIN CALLER STUB. All ecosystem-detection and audit logic
#     lives in the reusable workflow above.
#   • You MAY change: nothing in this file in normal use. Adopt verbatim.
#   • You MUST NOT change: trigger events, the `uses:` line, or job name
#     (used as a required status check).
#   • If you need different behaviour (new ecosystem, tool version bump),
#     open a PR against the reusable in the central repo.
# ─────────────────────────────────────────────────────────────────────────────
#
# Dependency vulnerability audit — thin caller for the org-level reusable.
# To adopt: copy this file to .github/workflows/dependency-audit.yml in your repo.
# Add "dependency-audit / Detect ecosystems" as a required status check
# in branch protection.
name: Dependency audit

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

permissions:
  contents: read

jobs:
  dependency-audit:
    uses: petry-projects/.github/.github/workflows/dependency-audit-reusable.yml@dependency-audit/v2-stable  # NOSONAR(githubactions:S7637) first-party channel ref
CANONICAL
)" > "$canon"
  run diff -u "$canon" "$STUB"
  rm -f "$canon"
  [ "$status" -eq 0 ] || {
    echo "stub drifted from canonical:"
    echo "$output"
    return 1
  }
}

@test "uses: ref is pinned to the dependency-audit/v2-stable channel" {
  # Match the actual `uses:` field (not comments) and anchor the end so a suffix
  # like @dependency-audit/v2-stable-rogue cannot slip through.
  grep -qE '^\s+uses:\s+petry-projects/\.github/\.github/workflows/dependency-audit-reusable\.yml@dependency-audit/v2-stable(\s|$|#)' "$STUB"
}

@test "uses: ref is not repointed to @main, a SHA, or a frozen @vN" {
  if grep -qE 'dependency-audit-reusable\.yml@(main|[0-9a-f]{7,40}|v[0-9])' "$STUB"; then
    echo "Error: The uses: ref in $STUB is pointed to a forbidden ref (main, SHA, or frozen vN)." >&2
    echo "It must be pinned to the dependency-audit/v2-stable channel." >&2
    return 1
  fi
}

@test "both trigger events are present on the main branch" {
  python3 - "$STUB" <<'PYEOF'
import yaml, sys
wf = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
# PyYAML (YAML 1.1) parses the bare key 'on' as boolean True
on = wf.get(True) or wf.get('on') or {}
for event in ('pull_request', 'push'):
    if event not in on:
        print(f"Missing trigger event: {event}")
        sys.exit(1)
    branches = (on[event] or {}).get('branches', [])
    if branches != ['main']:
        print(f"{event}.branches must be exactly ['main'], got {branches}")
        sys.exit(1)
PYEOF
}

@test "top-level permissions grant exactly contents: read (least privilege)" {
  python3 - "$STUB" <<'PYEOF'
import yaml, sys
wf = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
perms = wf.get('permissions', {}) or {}
if perms != {'contents': 'read'}:
    print(f"Top-level permissions must be exactly {{'contents': 'read'}}, got {perms}")
    sys.exit(1)
PYEOF
}

@test "job adds no elevated permissions and forwards no secrets" {
  # A read-only audit inherits the top-level contents: read grant; the job must
  # not widen the effective token (no job-level permissions) or forward secrets.
  python3 - "$STUB" <<'PYEOF'
import yaml, sys
wf = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
job = wf.get('jobs', {}).get('dependency-audit', {}) or {}
if 'permissions' in job:
    print(f"Job must not declare its own permissions (inherits contents: read), got {job['permissions']}")
    sys.exit(1)
if 'secrets' in job:
    print(f"Job must not forward any secrets, got {job['secrets']}")
    sys.exit(1)
PYEOF
}
