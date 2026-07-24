#!/usr/bin/env bats
# Compliance regression guard for the .gitignore Standard
# (petry-projects/.github → standards/gitignore-standard.md#managed-block-markers).
#
# Every repo's .gitignore MUST open with the org-managed L1 "secrets baseline"
# block, copied VERBATIM (markers included) from the org /.gitignore. The weekly
# audit (pp_check_gitignore_baseline in scripts/lib/push-protection.sh) locates
# the BEGIN … END markers, extracts the span inclusive of the markers, and
# compares its SHA-256 — trailing-newline tolerant — against the org canonical
# block. Everything BELOW the END marker is the per-repo L2 extension and is
# never inspected.
#
# This guard mirrors that check offline: it pins the canonical span's SHA-256 so
# drift inside the markers is caught in CI rather than only by the weekly audit.
# If the org updates the baseline (and the audit re-flags this repo), re-copy the
# block verbatim from the org /.gitignore and update GITIGNORE_L1_SHA256 below to
# the new digest.

GITIGNORE="${BATS_TEST_DIRNAME}/../.gitignore"

# Canonical marker lines — must match push-protection.sh byte-for-byte.
BEGIN_MARKER='# >>> BEGIN petry-projects secrets baseline (managed by .github — do not edit) >>>'
END_MARKER='# <<< END petry-projects secrets baseline <<<'

# SHA-256 of the org canonical L1 span (BEGIN … END markers inclusive), computed
# the same way pp_check_gitignore_baseline does: extract the span, then
# `printf '%s' "$span" | sha256sum` (command substitution strips the trailing
# newline, so the hash is trailing-newline tolerant).
GITIGNORE_L1_SHA256='1d4a83d95f8ee135aee79215b022dce1ac1cf8e049642ef9e82f1a80b691bc37'

# Extract the L1 secrets-baseline span (markers inclusive) from stdin, mirroring
# pp_extract_baseline_block. Prints nothing and exits non-zero if the block is
# absent or the BEGIN marker has no matching END.
extract_l1_span() {
  tr -d '\r' | awk -v b="$BEGIN_MARKER" -v e="$END_MARKER" '
    $0 == b { inblock = 1 }
    inblock { buf = buf $0 "\n" }
    $0 == e && inblock { printf "%s", buf; found = 1; exit }
    END { if (!found) exit 1 }
  '
}

@test ".gitignore exists at the repo root" {
  [ -f "$GITIGNORE" ]
}

@test ".gitignore contains the BEGIN secrets-baseline marker exactly once" {
  run grep -cxF "$BEGIN_MARKER" "$GITIGNORE"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test ".gitignore contains the END secrets-baseline marker exactly once" {
  run grep -cxF "$END_MARKER" "$GITIGNORE"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "nothing appears above the BEGIN marker (baseline is at the top)" {
  # The BEGIN marker must be the first line of the file — the standard requires
  # "Nothing goes above the BEGIN marker."
  run head -n 1 "$GITIGNORE"
  [ "$output" = "$BEGIN_MARKER" ]
}

@test "L1 secrets-baseline span is byte-identical to the org canonical block" {
  local span actual
  span="$(extract_l1_span < "$GITIGNORE")" || {
    echo "BEGIN … END secrets-baseline block not found in .gitignore"
    return 1
  }
  # Portable hash computation: try sha256sum (Linux), shasum (macOS), openssl (fallback).
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(printf '%s' "$span" | sha256sum | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(printf '%s' "$span" | shasum -a 256 | awk '{print $1}')"
  elif command -v openssl >/dev/null 2>&1; then
    actual="$(printf '%s' "$span" | openssl dgst -sha256 | awk '{print $NF}')"
  else
    echo "No sha256sum / shasum / openssl found — cannot compute hash"
    return 1
  fi
  [ "$actual" = "$GITIGNORE_L1_SHA256" ] || {
    echo "L1 baseline drift: expected $GITIGNORE_L1_SHA256, got $actual"
    echo "Re-copy the block verbatim from the org /.gitignore; never edit inside the markers."
    return 1
  }
}

@test "L2 does not re-ignore a baseline-negated dotenv path" {
  # The baseline ignores the dotenv family but re-allows committed templates via
  # negations (!.env.example, !.env.sample, …). A broad `.env` / `.env.*` line
  # in L2 (below END, evaluated later) would silently re-hide those, violating
  # negation discipline (gitignore-standard.md#negation-discipline).
  local l2
  l2="$(awk -v e="$END_MARKER" 'past { print } $0 == e { past = 1 }' "$GITIGNORE")"
  run grep -Exq '\.env(\..*)?' <<< "$l2"
  [ "$status" -ne 0 ] || {
    echo "L2 re-ignores a dotenv path the baseline negates — remove the broad .env/.env.* line below the END marker."
    return 1
  }
}
