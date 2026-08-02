#!/usr/bin/env bats
# Drift & compliance regression guard for the pr-auto-review thin caller stub.
#
# .github/workflows/pr-auto-review.yml is a THIN CALLER STUB whose readiness-gate
# logic lives entirely in the central reusable (petry-projects/.github →
# .github/workflows/pr-auto-review-reusable.yml). Its `uses:` channel ref, trigger
# event types, and job `permissions:` block are drift-protected and MUST NOT be
# edited in the caller (see the file's own "AGENTS — READ BEFORE EDITING" banner
# and ci-standards.md → Reusable workflow versioning).
#
# Unlike the other caller stubs, ONE thing IS a per-repo customization point: the
# `workflow_run.workflows` list must name this repo's CI workflow(s). For
# repo-template that workflow is named "CI" (.github/workflows/ci.yml), so the
# shipped value is already correct and carries no outstanding TODO. This guard
# pins that invariant — and, per SonarCloud githubactions:S1135 (issue #98),
# asserts no TODO/FIXME marker lingers in the stub so the finding stays at zero.

STUB="${BATS_TEST_DIRNAME}/../.github/workflows/pr-auto-review.yml"
CI_WORKFLOW="${BATS_TEST_DIRNAME}/../.github/workflows/ci.yml"

@test "pr-auto-review stub exists" {
  [ -f "$STUB" ]
}

@test "stub carries no TODO/FIXME marker (SonarCloud githubactions:S1135 regression guard)" {
  if grep -nE '(TODO|FIXME)' "$STUB"; then
    echo "Error: $STUB still contains a TODO/FIXME marker — SonarCloud S1135 will re-open." >&2
    echo "Complete the task and reword the comment instead of leaving a TODO." >&2
    return 1
  fi
}

@test "workflow_run.workflows names this repo's CI workflow" {
  # The stub gates on the named CI workflow completing; that name must match the
  # `name:` of the repo's actual CI workflow. repo-template ships ci.yml as "CI".
  # Parse YAML semantically so any valid representation (inline or block list) is accepted.
  python3 - "$STUB" "$CI_WORKFLOW" <<'PYEOF'
import yaml, sys
stub = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
ci_wf = yaml.safe_load(open(sys.argv[2], encoding="utf-8"))
# PyYAML (YAML 1.1) parses the bare key 'on' as boolean True
on = stub.get(True) or stub.get('on') or {}
workflows = on.get('workflow_run', {}).get('workflows', [])
if workflows != ['CI']:
    print("workflow_run.workflows does not contain 'CI'")
    sys.exit(1)
if ci_wf.get('name') != 'CI':
    print("ci.yml is not named 'CI' — update the stub's workflows list to match")
    sys.exit(1)
PYEOF
}

@test "uses: ref is pinned to the pr-auto-review/v1-stable channel" {
  # Match the actual `uses:` field (not comments) and anchor the end so a suffix
  # like @pr-auto-review/v1-stable-rogue cannot slip through.
  grep -qE '^\s+uses:\s+petry-projects/\.github/\.github/workflows/pr-auto-review-reusable\.yml@pr-auto-review/v1-stable(\s|$|#)' "$STUB"
}

@test "uses: ref is not repointed to @main, a SHA, or a frozen @vN" {
  if grep -qE 'pr-auto-review-reusable\.yml@(main|[0-9a-f]{7,40}|v[0-9])' "$STUB"; then
    echo "Error: The uses: ref in $STUB is pointed to a forbidden ref (main, SHA, or frozen vN)." >&2
    echo "It must be pinned to the pr-auto-review/v1-stable channel." >&2
    return 1
  fi
}

@test "job skips secret-less Dependabot pull_request events" {
  # Dependabot `pull_request` events run with a read-only token and NO access to
  # org secrets, so `secrets.GH_PAT_DON_PETRY || secrets.GH_PAT_WORKFLOWS`
  # resolves empty, the reusable's GH_TOKEN is blank, and every gh call exits 4
  # (the sole failure mode behind fleet-monitor issue #121). Readiness for those
  # PRs is still evaluated on the secret-bearing workflow_run / check_suite events,
  # so the job MUST carry an `if:` guard that skips Dependabot pull_request runs
  # (yielding a `skipped` — not `failure` — conclusion). The guard must be scoped
  # to the pull_request event so workflow_run / check_suite runs (whose actor can
  # also be dependabot[bot]) still execute.
  python3 - "$STUB" <<'PYEOF'
import re, yaml, sys
with open(sys.argv[1], encoding='utf-8') as f:
    wf = yaml.safe_load(f)
job = wf.get('jobs', {}).get('pr-auto-review', {})
cond = job.get('if')
if not cond:
    print("job pr-auto-review has no `if:` guard — Dependabot pull_request runs will fail")
    sys.exit(1)
cond = str(cond)
# Require !=  (not ==) so a reversed guard does not pass: anchors to 'pull_request' with
# surrounding quotes so 'pull_request_review' (still containing the substring) cannot slip through.
if not re.search(r"github\.event_name\s*!=\s*['\"]pull_request['\"]", cond):
    print(f"`if:` guard must use github.event_name != 'pull_request': {cond!r}")
    sys.exit(1)
# Require !=  so a guard that skips all PRs (== dependabot) cannot satisfy this check.
if not re.search(r"github\.actor\s*!=\s*['\"]dependabot\[bot\]['\"]", cond):
    print(f"`if:` guard must use github.actor != 'dependabot[bot]': {cond!r}")
    sys.exit(1)
# Require || (OR) so normal pull_request runs are never skipped by an AND guard.
if '||' not in cond:
    print(f"`if:` guard must use || so normal pull_request runs still execute: {cond!r}")
    sys.exit(1)
PYEOF
}

@test "all four trigger events are present" {
  python3 - "$STUB" <<'PYEOF'
import yaml, sys
wf = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
# PyYAML (YAML 1.1) parses the bare key 'on' as boolean True
on = wf.get(True) or wf.get('on') or {}
required = {
    'workflow_run':        {'completed'},
    'check_suite':         {'completed'},
    'pull_request_review': {'submitted', 'dismissed'},
    'pull_request':        {'opened', 'reopened', 'synchronize', 'ready_for_review'},
}
for event, expected_types in required.items():
    if event not in on:
        print(f"Missing trigger event: {event}")
        sys.exit(1)
    actual = set((on[event] or {}).get('types', []))
    if actual != expected_types:
        print(f"{event} types must be exactly {sorted(expected_types)}, got {sorted(actual)}")
        sys.exit(1)
PYEOF
}

@test "top-level permissions are locked down to {}" {
  grep -q '^permissions: {}' "$STUB" || { echo "Top-level permissions are not locked down to {}"; return 1; }
}

@test "job grants exactly the read scopes the reusable needs and forwards the named secret" {
  # Parse the job permissions via YAML to reject any extra scopes (e.g. contents: write)
  # that would silently broaden the reusable's effective token.
  python3 - "$STUB" <<'PYEOF'
import yaml, sys
wf = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
job = wf.get('jobs', {}).get('pr-auto-review', {})
perms = job.get('permissions', {}) or {}
expected = {'pull-requests': 'read', 'checks': 'read', 'actions': 'read'}
if perms != expected:
    print(f"Job permissions must be exactly {expected}")
    print(f"Got: {perms}")
    sys.exit(1)
secrets = job.get('secrets', {}) or {}
expected_secret = '${{ secrets.GH_PAT_DON_PETRY || secrets.GH_PAT_WORKFLOWS }}'
if secrets.get('GH_PAT_WORKFLOWS') != expected_secret:
    print("GH_PAT_WORKFLOWS secret forwarding is incorrect")
    sys.exit(1)
PYEOF
}
