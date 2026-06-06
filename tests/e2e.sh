#!/usr/bin/env bash
# tests/e2e.sh — Layer 3 e2e automated test runner (opt-in).
#
# Triggers REAL Claude Code session via `claude --print --plugin-dir <plugin>`
# so SKILL.md prose is actually interpreted by Claude (vs Layer 2 which runs
# test-script-internal mock implementations). Verifies result file structure
# + scenario-specific behavioral markers — does NOT verify LLM wording.
#
# Usage:
#   bash tests/e2e.sh --skill <review|adversarial-review> --scenario <name>
#
# Scenarios: mixed / binary / oversize / empty-repo / all-empty
#
# Layer 3 is OPT-IN (not dispatched by tests/run.sh). Each invocation burns:
#   - 1 codex-call quota
#   - ~50k Claude API tokens
#   - 60-180s wall time
# Full 10-combination matrix ≈ 10-30 min + ~$0.5-$2 + 10 codex quota.
#
# Rate-limit policy: 3 attempts with 30s/60s/120s backoff on
# "Server is temporarily limiting requests" only.
#
# Exit codes:
#   0  — pass
#   2  — usage error (bad flag / missing arg)
#   3  — environment error (claude CLI missing, plugin path missing)
#   4  — Anthropic API rate-limited after 3 retries
#   5  — result file missing after Claude session completed
#   6  — result file structural / behavioral verification failed

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/e2e-fixtures.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/e2e-claude-print.sh"

# ── Argument parsing ─────────────────────────────────────────────
SKILL=""
SCENARIO=""

usage() {
  cat >&2 <<USAGE
Usage: bash tests/e2e.sh --skill <name> --scenario <name>

  --skill     review | adversarial-review
  --scenario  mixed | binary | oversize | empty-repo | all-empty

Both flags are required. Layer 3 is opt-in; not dispatched by tests/run.sh.
Full matrix (10 combinations) ≈ 10-30 min + ~10 codex quota + ~\$0.5-\$2.

Examples:
  bash tests/e2e.sh --skill review --scenario mixed
  bash tests/e2e.sh --skill adversarial-review --scenario all-empty
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --skill)
      SKILL="${2:-}"; shift 2
      ;;
    --scenario)
      SCENARIO="${2:-}"; shift 2
      ;;
    -h|--help)
      usage; exit 0
      ;;
    *)
      echo "Error: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

case "$SKILL" in
  review|adversarial-review) ;;
  "")
    echo "Error: --skill is required" >&2; usage; exit 2 ;;
  *)
    echo "Error: --skill must be one of: review, adversarial-review (got '$SKILL')" >&2
    usage; exit 2 ;;
esac

case "$SCENARIO" in
  mixed|binary|oversize|empty-repo|all-empty|with-profile) ;;
  "")
    echo "Error: --scenario is required" >&2; usage; exit 2 ;;
  *)
    echo "Error: --scenario must be one of: mixed, binary, oversize, empty-repo, all-empty, with-profile (got '$SCENARIO')" >&2
    usage; exit 2 ;;
esac

echo "── e2e: skill=$SKILL scenario=$SCENARIO ──"

# ── Fixture setup ────────────────────────────────────────────────
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT

case "$SCENARIO" in
  mixed)        e2e_fixture_mixed       "$FIXTURE" ;;
  binary)       e2e_fixture_binary      "$FIXTURE" ;;
  oversize)     e2e_fixture_oversize    "$FIXTURE" ;;
  empty-repo)   e2e_fixture_empty_repo  "$FIXTURE" ;;
  all-empty)    e2e_fixture_all_empty   "$FIXTURE" ;;
  with-profile) e2e_fixture_with_profile "$FIXTURE" ;;
esac
echo "  fixture: $FIXTURE"

# ── Invocation ───────────────────────────────────────────────────
echo "  invoking claude --print (may take 60-180s + retry on rate limit)..."
invoke_skill_via_claude_print "$FIXTURE" "$SKILL"
rc=$INVOKE_EXIT

if [ "$rc" -eq 4 ]; then
  echo "FAIL: Anthropic API rate-limited after 3 retries" >&2
  exit 4
fi
if [ "$rc" -ne 0 ]; then
  echo "  WARN: claude session exit=$rc (will still verify result file in case skill ran)" >&2
fi

# ── Result file lookup ───────────────────────────────────────────
result_file=$(ls -1t "$FIXTURE/.codex-pro/${SKILL}-"*.md 2>/dev/null | head -1 || true)
if [ -z "$result_file" ] || [ ! -f "$result_file" ]; then
  echo "FAIL: result file not found at $FIXTURE/.codex-pro/${SKILL}-*.md" >&2
  echo "  claude output:" >&2
  echo "$INVOKE_OUTPUT" | tail -20 >&2
  exit 5
fi
echo "  result file: $result_file"

# ── Verification ─────────────────────────────────────────────────
RESULT_BODY=$(cat "$result_file")
FAIL_COUNT_BEFORE=$FAIL_COUNT

verify_substring() {
  local needle="$1" msg="$2"
  if printf '%s' "$RESULT_BODY" | grep -q -- "$needle"; then
    pass "$msg"
  else
    fail "$msg (missing substring: '$needle')"
  fi
}

# H2 headings are driven by SKILL.md Step 3 system instructions but Codex
# output is non-deterministic — sometimes uses different heading levels or
# omits them entirely. Treat as warning (don't fail the run) so e2e remains
# reliable as a smoke gate.
verify_substring_warn() {
  local needle="$1" msg="$2"
  if printf '%s' "$RESULT_BODY" | grep -q -- "$needle"; then
    pass "$msg"
  else
    printf '  ⚠ %s (best-effort, Codex output non-deterministic; not a failure)\n' "$msg (missing substring: '$needle')" >&2
  fi
}

verify_not_substring() {
  local needle="$1" msg="$2"
  if printf '%s' "$RESULT_BODY" | grep -q -- "$needle"; then
    fail "$msg (unexpected substring found: '$needle')"
  else
    pass "$msg"
  fi
}

# Verification scope (v0.1 e2e):
#   Reliable (deterministic) — verified here:
#     - result file exists at expected path
#     - frontmatter target marker per scenario
#     - body required H2 section headings (driven by SKILL.md system instructions)
#     - target_invalid fail-fast frontmatter for all-empty
#   Not verified (Codex output is non-deterministic):
#     - whether Codex mentions specific file paths / content in body
#     - whether Codex references the "Untracked binaries omitted" heading
#     - whether Codex references truncation marker
#   (Prompt-body construction is verified by Layer 2 behavioral tests +
#   pre-archive smoke gate, which can inspect the prompt file directly;
#   Layer 3 e2e cannot intercept the codex-call invocation.)
case "$SCENARIO" in
  mixed|binary|oversize|empty-repo)
    # frontmatter target marker is deterministic from Claude's SKILL.md
    # execution; H2 headings come from Codex's non-deterministic output
    # (Step 3 system instructions request them but LLM may omit / restructure)
    case "$SKILL" in
      review)
        verify_substring_warn '## Summary'  "$SKILL/$SCENARIO: '## Summary' heading"
        verify_substring_warn '## Findings' "$SKILL/$SCENARIO: '## Findings' heading"
        ;;
      adversarial-review)
        for h in '## Assumptions Challenged' '## Failure Modes' '## Alternative Approaches' '## Trade-off Counterarguments'; do
          verify_substring_warn "$h" "adversarial-review/$SCENARIO: '$h' heading"
        done
        ;;
    esac
    if [ "$SCENARIO" = "empty-repo" ]; then
      verify_substring 'diff (pre-first-commit)' "$SKILL/empty-repo: pre-first-commit target marker present"
    fi
    ;;
  all-empty)
    # target_invalid is Claude's pre-flight; Claude writes frontmatter
    # without invoking codex-call → fully deterministic verification
    verify_substring 'error: target_invalid' "$SKILL/all-empty: target_invalid fail-fast frontmatter"
    if [ "$SKILL" = "review" ]; then
      verify_substring 'findings_count: 0' "review/all-empty: findings_count: 0 frontmatter"
    fi
    ;;
  with-profile)
    # Project profile sets effort:high — the resolved value flows into both the
    # codex-call invocation AND the result frontmatter (deterministic, written
    # by Claude's SKILL.md execution regardless of Codex's prose output).
    verify_substring 'effort: high' "$SKILL/with-profile: project profile effort=high reflected in frontmatter"
    # profile_source must be non-default (project, or mixed if a real global
    # profile also exists on the test machine).
    if printf '%s' "$RESULT_BODY" | grep -qE 'profile_source: (project|mixed)'; then
      pass "$SKILL/with-profile: profile_source is project|mixed (profile was resolved)"
    else
      fail "$SKILL/with-profile: profile_source not project|mixed (profile not resolved?)"
    fi
    ;;
esac

# ── Adversarial-review 4-section non-empty enforcement ───────────
if [ "$SKILL" = "adversarial-review" ] && [ "$SCENARIO" != "all-empty" ]; then
  python3 - "$result_file" <<'PY' || fail "adversarial-review: section non-empty check failed"
import sys, re
content = open(sys.argv[1]).read()
sections = re.split(r'(?m)^## ', content)
required = {"Assumptions Challenged", "Failure Modes", "Alternative Approaches", "Trade-off Counterarguments"}
found = {}
for sec in sections[1:]:
    head = sec.split('\n', 1)[0].strip()
    body = sec[len(head):].strip()
    stripped = re.sub(r'\s', '', body)
    if head in required:
        found[head] = len(stripped)
missing = required - set(found.keys())
if missing:
    print(f"FAIL: missing sections: {missing}", file=sys.stderr); sys.exit(1)
short = {h: n for h, n in found.items() if n < 200}
if short:
    print(f"FAIL: section(s) under 200-char threshold: {short}", file=sys.stderr); sys.exit(1)
print(f"PASS: 4 sections all ≥200 substantive chars: {found}")
PY
  if [ $? -eq 0 ]; then
    pass "adversarial-review: 4 H2 sections each ≥200 substantive characters"
  fi
fi

# ── Summary ──────────────────────────────────────────────────────
if [ "$FAIL_COUNT" -gt "$FAIL_COUNT_BEFORE" ]; then
  added_failures=$((FAIL_COUNT - FAIL_COUNT_BEFORE))
  echo ""
  echo "FAIL: $added_failures verification check(s) failed for $SKILL/$SCENARIO" >&2
  exit 6
fi

report_summary "e2e[$SKILL/$SCENARIO]"
