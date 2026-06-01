#!/usr/bin/env bash
# tests/review.sh — Layer 2: structural & semantic checks for the review skill.
# Verifies frontmatter, codex-call HTTPS-direct invocation, hard timeout flag,
# fail-fast circuit-breaker discipline, and result-file structure contract.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"

REVIEW_SKILL="$REPO_ROOT/plugins/codex-pro/skills/review/SKILL.md"

assert_file "$REVIEW_SKILL" "review SKILL.md exists"

# ── (a) Frontmatter parse ────────────────────────────────────────
fm_check=$(python3 - "$REVIEW_SKILL" <<'PY' 2>/dev/null
import re, sys
content = open(sys.argv[1]).read()
m = re.match(r"^---\n(.*?)\n---\n", content, re.DOTALL)
if not m:
    print("no_frontmatter"); sys.exit(0)
fm = m.group(1)
name_ok = "name: review" in fm
bash_ok = "Bash" in fm
read_ok = "Read" in fm
print(f"name={name_ok} bash={bash_ok} read={read_ok}")
PY
)
case "$fm_check" in
  *"name=True bash=True read=True"*)
    pass "frontmatter: name=review, allowed-tools 含 Bash + Read" ;;
  *)
    fail "frontmatter check failed: $fm_check" ;;
esac

# ── (b) codex-call invocation (default rule, NOT exception) ──────
cc_count=$(grep -c "codex-call" "$REVIEW_SKILL")
if [ "$cc_count" -ge 1 ]; then
  pass "SKILL.md invokes codex-call (count=$cc_count)"
else
  fail "SKILL.md missing codex-call invocation"
fi

# ── (c) MUST NOT contain codex exec (subprocess form is batch exception) ──
ce_count=$(grep -c "codex exec" "$REVIEW_SKILL")
assert_eq "0" "$ce_count" "SKILL.md does NOT contain 'codex exec' (Design constraint #1 strict adherence)"

# ── (d) Hard timeout flag ────────────────────────────────────────
if grep -q -- '--max-time 600' "$REVIEW_SKILL"; then
  pass "SKILL.md documents --max-time 600 hard timeout"
else
  fail "SKILL.md missing --max-time 600 flag"
fi

# ── (e) Fail-fast three error classes ────────────────────────────
for err in rate_limit oauth_invalid timeout; do
  cnt=$(grep -c "$err" "$REVIEW_SKILL")
  if [ "$cnt" -ge 1 ]; then
    pass "fail-fast error class '$err' present (count=$cnt)"
  else
    fail "fail-fast error class '$err' missing"
  fi
done

# fail-fast / no-retry discipline marker
if grep -qE '不 retry|fail-fast|不會自動 retry|no retry' "$REVIEW_SKILL"; then
  pass "SKILL.md states no-retry / fail-fast discipline"
else
  fail "SKILL.md missing no-retry / fail-fast marker"
fi

# ── (f) Result file structure contract ───────────────────────────
for marker in '.codex-pro/review-' '## Summary' '## Findings' '### Finding'; do
  if grep -q -- "$marker" "$REVIEW_SKILL"; then
    pass "result file marker present: $marker"
  else
    fail "result file marker missing: $marker"
  fi
done

# 6 frontmatter field names must each appear (in body documentation)
for field in target model effort timestamp findings_count error; do
  cnt=$(grep -c "$field" "$REVIEW_SKILL")
  if [ "$cnt" -ge 1 ]; then
    pass "frontmatter field '$field' documented (count=$cnt)"
  else
    fail "frontmatter field '$field' missing"
  fi
done

report_summary "review"
