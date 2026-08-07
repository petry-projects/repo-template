#!/usr/bin/env bats
# Behavior & drift guard for the SonarCloud analysis workflow.
#
# .github/workflows/sonarcloud.yml ships verbatim into repos created from
# petry-projects/repo-template (SOURCE OF TRUTH:
# petry-projects/.github/standards/workflows/sonarcloud.yml). Its job name is the
# required `SonarCloud` status check, and the org convention is a first scan that
# is continue-on-error with a SINGLE retry (the analysis endpoint is occasionally
# flaky).
#
# Issue #137 (Fleet Monitor): the workflow's failure rate crossed the 10%
# threshold because the retry fired IMMEDIATELY after the first failure, so a
# transient endpoint blip failed both attempts back-to-back. The fix inserts a
# short backoff between the failed scan and the retry. This guard pins that
# backoff plus the invariants it must not break.

STUB="${BATS_TEST_DIRNAME}/../.github/workflows/sonarcloud.yml"

@test "sonarcloud workflow exists" {
  [ -f "$STUB" ]
}

@test "job name is the required 'SonarCloud' status check" {
  python3 - "$STUB" <<'PYEOF'
import yaml, sys
with open(sys.argv[1], encoding='utf-8') as f:
    wf = yaml.safe_load(f)
job = wf.get('jobs', {}).get('sonarcloud', {})
if job.get('name') != 'SonarCloud':
    print(f"job 'sonarcloud' name must be 'SonarCloud', got {job.get('name')!r}")
    sys.exit(1)
PYEOF
}

@test "first scan is continue-on-error and the retry is gated on its failure" {
  python3 - "$STUB" <<'PYEOF'
import yaml, sys
with open(sys.argv[1], encoding='utf-8') as f:
    wf = yaml.safe_load(f)
steps = wf.get('jobs', {}).get('sonarcloud', {}).get('steps', [])
first = next((s for s in steps if s.get('id') == 'sonar'), None)
if first is None:
    print("no step with id 'sonar' (the first scan) found")
    sys.exit(1)
if first.get('continue-on-error') is not True:
    print("the first scan (id: sonar) must set continue-on-error: true")
    sys.exit(1)
scans = [s for s in steps if 'sonarqube-scan-action' in str(s.get('uses', ''))]
if len(scans) != 2:
    print(f"expected exactly 2 sonarqube-scan-action steps, got {len(scans)}")
    sys.exit(1)
retry = scans[1]
if "steps.sonar.outcome == 'failure'" not in str(retry.get('if', '')):
    print("retry step must be gated on steps.sonar.outcome == 'failure'")
    sys.exit(1)
PYEOF
}

@test "a backoff step waits between the failed scan and the retry (issue #137)" {
  # The whole point of the fix: a transient endpoint blip must not fail both
  # attempts back-to-back. A backoff (sleep) step, gated on the same failure
  # condition, must sit AFTER the first scan and BEFORE the retry.
  python3 - "$STUB" <<'PYEOF'
import yaml, sys, re
with open(sys.argv[1], encoding='utf-8') as f:
    wf = yaml.safe_load(f)
steps = wf.get('jobs', {}).get('sonarcloud', {}).get('steps', [])

def idx(pred):
    return next((i for i, s in enumerate(steps) if pred(s)), None)

first_i = idx(lambda s: s.get('id') == 'sonar')
retry_i = idx(lambda s: s.get('id') != 'sonar'
              and 'sonarqube-scan-action' in str(s.get('uses', '')))
if first_i is None or retry_i is None:
    print("could not locate both the first scan and the retry scan")
    sys.exit(1)

backoff_i = None
for i, s in enumerate(steps):
    run = str(s.get('run', ''))
    if re.search(r'\bsleep\b', run):
        backoff_i = i
        gate = str(s.get('if', ''))
        if "steps.sonar.outcome == 'failure'" not in gate:
            print("backoff step must be gated on steps.sonar.outcome == 'failure' "
                  "so it only runs on the retry path")
            sys.exit(1)
        m = re.search(r'sleep\s+(\d+)', run)
        if not m or int(m.group(1)) != 30:
            print("backoff step must sleep exactly 30 seconds")
            sys.exit(1)
        break

if backoff_i is None:
    print("no backoff (sleep) step found — an immediate retry lands in the same "
          "transient outage window (issue #137)")
    sys.exit(1)
if not (first_i < backoff_i < retry_i):
    print("backoff step must sit AFTER the first scan and BEFORE the retry")
    sys.exit(1)
PYEOF
}

@test "top-level permissions are locked down to {}" {
  grep -q '^permissions: {}' "$STUB" || { echo "Top-level permissions are not locked down to {}"; return 1; }
}

@test "job grants exactly the read scopes the scan needs" {
  python3 - "$STUB" <<'PYEOF'
import yaml, sys
with open(sys.argv[1], encoding='utf-8') as f:
    wf = yaml.safe_load(f)
job = wf.get('jobs', {}).get('sonarcloud', {})
perms = job.get('permissions', {}) or {}
expected = {'contents': 'read', 'pull-requests': 'read'}
if perms != expected:
    print(f"Job permissions must be exactly {expected}, got {perms}")
    sys.exit(1)
PYEOF
}

@test "triggers are push + pull_request to main and checkout uses fetch-depth: 0" {
  python3 - "$STUB" <<'PYEOF'
import yaml, sys
with open(sys.argv[1], encoding='utf-8') as f:
    wf = yaml.safe_load(f)
# PyYAML (YAML 1.1) parses the bare key 'on' as boolean True
on = wf.get(True) or wf.get('on') or {}
allowed_events = {'push', 'pull_request'}
extra_events = {str(k) for k in on.keys()} - allowed_events
if extra_events:
    print(f"trigger set must be exactly {{push, pull_request}}, found extra: {sorted(extra_events)}")
    sys.exit(1)
for event in ('push', 'pull_request'):
    branches = (on.get(event) or {}).get('branches', [])
    if branches != ['main']:
        print(f"{event} must target branches [main], got {branches}")
        sys.exit(1)
steps = wf.get('jobs', {}).get('sonarcloud', {}).get('steps', [])
checkout = next((s for s in steps if 'actions/checkout' in str(s.get('uses', ''))), None)
if checkout is None:
    print("no checkout step found")
    sys.exit(1)
if (checkout.get('with') or {}).get('fetch-depth') != 0:
    print("checkout must set fetch-depth: 0")
    sys.exit(1)
PYEOF
}

@test "every third-party action is pinned to a full-length commit SHA" {
  # Match `uses:` lines (not comments) and require a 40-hex SHA ref.
  while IFS= read -r ref; do
    if ! printf '%s' "$ref" | grep -qE '@[0-9a-f]{40}$'; then
      echo "action ref is not pinned to a 40-char SHA: $ref" >&2
      return 1
    fi
  done < <(grep -oE 'uses:[[:space:]]+[^[:space:]#]+' "$STUB" | awk '{print $2}')
}

@test "stub carries no TODO/FIXME marker (SonarCloud githubactions:S1135 regression guard)" {
  if grep -nE '(TODO|FIXME)' "$STUB"; then
    echo "Error: $STUB still contains a TODO/FIXME marker — SonarCloud S1135 will re-open." >&2
    return 1
  fi
}

@test "ci.yml defines the required secret-scan job" {
  grep -qE '^  secret-scan:' "${BATS_TEST_DIRNAME}/../.github/workflows/ci.yml"
}
