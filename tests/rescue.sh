#!/usr/bin/env bash
# tests/rescue.sh — Layer 2: structural & semantic checks for the rescue skill.
# Verifies frontmatter, codex-call HTTPS-direct invocation, hard timeout flag,
# fail-fast circuit-breaker discipline (4 classes), result-file structure
# contract (8 frontmatter fields + 3 sections), outcome enum (4 values), and
# session continuity flags (--resume / --fresh).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"

RESCUE_SKILL="$REPO_ROOT/plugins/codex-pro/skills/rescue/SKILL.md"

assert_file "$RESCUE_SKILL" "rescue SKILL.md exists"

# ── (a) Frontmatter parse ────────────────────────────────────────
fm_check=$(python3 - "$RESCUE_SKILL" <<'PY' 2>/dev/null
import re, sys
content = open(sys.argv[1]).read()
m = re.match(r"^---\n(.*?)\n---\n", content, re.DOTALL)
if not m:
    print("no_frontmatter"); sys.exit(0)
fm = m.group(1)
name_ok = "name: rescue" in fm
bash_ok = "Bash" in fm
read_ok = "Read" in fm
print(f"name={name_ok} bash={bash_ok} read={read_ok}")
PY
)
case "$fm_check" in
  *"name=True bash=True read=True"*)
    pass "frontmatter: name=rescue, allowed-tools 含 Bash + Read" ;;
  *)
    fail "frontmatter check failed: $fm_check" ;;
esac

# ── (b) codex-call invocation (default rule, NOT exception) ──────
cc_count=$(grep -c "codex-call" "$RESCUE_SKILL")
if [ "$cc_count" -ge 1 ]; then
  pass "SKILL.md invokes codex-call (count=$cc_count, default rule)"
else
  fail "SKILL.md missing codex-call invocation"
fi

# ── (c) MUST NOT contain codex exec (subprocess form is batch exception) ──
ce_count=$(grep -c "codex exec" "$RESCUE_SKILL")
assert_eq "0" "$ce_count" "SKILL.md does NOT contain 'codex exec' (Design constraint #1 strict adherence, mirroring review)"

# ── (d) Hard timeout flag ────────────────────────────────────────
if grep -q -- '--max-time 600' "$RESCUE_SKILL"; then
  pass "SKILL.md documents --max-time 600 hard timeout"
else
  fail "SKILL.md missing --max-time 600 flag"
fi

# ── (e) Fail-fast 4 error classes (rescue adds task_unclear) ─────
for err in rate_limit oauth_invalid timeout task_unclear; do
  cnt=$(grep -c "$err" "$RESCUE_SKILL")
  if [ "$cnt" -ge 1 ]; then
    pass "fail-fast error class '$err' present (count=$cnt)"
  else
    fail "fail-fast error class '$err' missing"
  fi
done

# fail-fast / no-retry discipline marker
if grep -qE '不 retry|fail-fast|不會自動 retry|no retry' "$RESCUE_SKILL"; then
  pass "SKILL.md states no-retry / fail-fast discipline"
else
  fail "SKILL.md missing no-retry / fail-fast marker"
fi

# ── (f) Result file structure contract (path + 3 sections) ───────
for marker in '.codex-pro/rescue-' '## Task Brief' '## Outcome' '## Suggested Next Steps'; do
  if grep -q -- "$marker" "$RESCUE_SKILL"; then
    pass "result file marker present: $marker"
  else
    fail "result file marker missing: $marker"
  fi
done

# ── (g) 8 frontmatter field names ────────────────────────────────
for field in task_description session_id resume_from model effort timestamp outcome error; do
  cnt=$(grep -c "$field" "$RESCUE_SKILL")
  if [ "$cnt" -ge 1 ]; then
    pass "frontmatter field '$field' documented (count=$cnt)"
  else
    fail "frontmatter field '$field' missing"
  fi
done

# ── (h) 4 outcome enum values ────────────────────────────────────
for outcome_val in completed partial unclear requires_external; do
  cnt=$(grep -c "$outcome_val" "$RESCUE_SKILL")
  if [ "$cnt" -ge 1 ]; then
    pass "outcome enum value '$outcome_val' documented (count=$cnt)"
  else
    fail "outcome enum value '$outcome_val' missing"
  fi
done

# ── (i) Session continuity flags ─────────────────────────────────
for flag in '--resume' '--fresh'; do
  cnt=$(grep -c -- "$flag" "$RESCUE_SKILL")
  if [ "$cnt" -ge 1 ]; then
    pass "session flag '$flag' documented (count=$cnt)"
  else
    fail "session flag '$flag' missing"
  fi
done

# Mutually exclusive marker
if grep -qE 'mutually exclusive|互斥' "$RESCUE_SKILL"; then
  pass "SKILL.md documents --resume / --fresh mutually exclusive"
else
  fail "SKILL.md missing mutually exclusive marker for --resume / --fresh"
fi

report_summary "rescue"
