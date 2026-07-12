#!/usr/bin/env bash
# tests/rescue.sh — Layer 2: structural & semantic checks for the rescue skill.
# Verifies frontmatter, codex-call HTTPS-direct invocation, hard timeout flag,
# fail-fast circuit-breaker discipline (4 classes), result-file structure
# contract (7 frontmatter fields + 3 sections), outcome enum (4 values), and
# v0.1.1 known limitation: session continuity flags (--resume / --fresh /
# resume_from / mutually exclusive) MUST NOT appear in SKILL.md.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"

RESCUE_SKILL="$REPO_ROOT/plugins/codex-pro/skills/codex-rescue/SKILL.md"

assert_file "$RESCUE_SKILL" "rescue SKILL.md exists"

# ── (a) Frontmatter parse ────────────────────────────────────────
fm_check=$(python3 - "$RESCUE_SKILL" <<'PY' 2>/dev/null
import re, sys
content = open(sys.argv[1]).read()
m = re.match(r"^---\n(.*?)\n---\n", content, re.DOTALL)
if not m:
    print("no_frontmatter"); sys.exit(0)
fm = m.group(1)
name_ok = "name: codex-rescue" in fm
bash_ok = "Bash" in fm
read_ok = "Read" in fm
print(f"name={name_ok} bash={bash_ok} read={read_ok}")
PY
)
case "$fm_check" in
  *"name=True bash=True read=True"*)
    pass "frontmatter: name=codex-rescue, allowed-tools 含 Bash + Read" ;;
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

# ── foreground-sync clause (issue #6) ──
fg=$(grep -c "前景同步執行" "${RESCUE_SKILL}")
rb=$(grep -c "run_in_background" "${RESCUE_SKILL}")
if [ "$fg" -ge 1 ] && [ "$rb" -ge 1 ]; then
  pass "SKILL.md documents foreground-sync clause (issue #6)"
else
  fail "SKILL.md missing foreground-sync clause (fg=$fg rb=$rb)"
fi

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

# ── (g) 7 frontmatter field names ────────────────────────────────
for field in task_description session_id model effort timestamp outcome error; do
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

# ── (i) Session continuity removed in v0.1.1 (known limitation) ──
# Consolidated regression guard: NONE of the four session-flag tokens may appear.
forbidden_count=$(grep -cE '\-\-resume|\-\-fresh|resume_from|mutually exclusive' "$RESCUE_SKILL")
assert_eq "0" "$forbidden_count" "SKILL.md contains zero session-continuity tokens (--resume/--fresh/resume_from/mutually exclusive)"

# v0.1.1 known-limitation marker required so users see why session flags are gone
if grep -qE 'session continuity|known limitation' "$RESCUE_SKILL"; then
  pass "SKILL.md documents v0.1.1 session-continuity known limitation"
else
  fail "SKILL.md missing v0.1.1 session-continuity known-limitation marker"
fi

# ══════════════════════════════════════════════════════════════════
# v0.2 profile-aware section (config-profile-mechanism)
# ══════════════════════════════════════════════════════════════════

if grep -q 'v0.2 — profile-aware' "$RESCUE_SKILL"; then
  pass "v0.2 profile-aware marker present in frontmatter"
else
  fail "v0.2 profile-aware marker missing"
fi
for marker in '~/.codex-pro/profile.yaml' '.codex-pro/profile.yaml' 'profile_source'; do
  cnt=$(grep -c -- "$marker" "$RESCUE_SKILL")
  [ "$cnt" -ge 1 ] && pass "profile marker present: $marker (n=$cnt)" \
    || fail "profile marker missing: $marker"
done
if grep -q -- '--model "$MODEL"' "$RESCUE_SKILL"; then
  pass "codex-call uses resolved --model \"\$MODEL\""
else
  fail "codex-call does not use resolved --model"
fi
# session-flag invariant must still hold (v0.1.1 regression guard)
sess=$(grep -cE '\-\-resume|\-\-fresh|\-\-session|resume_from' "$RESCUE_SKILL")
assert_eq "0" "$sess" "session-flag invariant intact after profile change (zero --resume/--fresh/--session/resume_from)"

# ── behavioral: extract rescue resolver + run against fake profile ──
RRES=$(mktemp)
python3 - "$RESCUE_SKILL" "$RRES" <<'PY'
import re, sys
c = open(sys.argv[1]).read()
m = re.search(r"PROFILE_RESOLVED=\$\(python3 - <<'PY'\n(.*?)\nPY\n\)", c, re.DOTALL)
if not m:
    sys.exit("RESOLVER_EXTRACT_FAIL")
open(sys.argv[2], "w").write(m.group(1))
PY
if [ -s "$RRES" ]; then
  pass "behavioral: extracted rescue profile resolver from SKILL.md"
  th=$(mktemp -d); tp=$(mktemp -d)
  mkdir -p "$tp/.codex-pro"; printf 'model: gpt-5.0\neffort: high\n' > "$tp/.codex-pro/profile.yaml"
  out=$(cd "$tp" && HOME="$th" python3 "$RRES" 2>&1)
  # project sets model+effort, no global -> source=project
  if [ "$out" = "gpt-5.0|high|600||project" ]; then
    pass "behavioral: rescue resolver yields gpt-5.0|high|600||project"
  else
    fail "behavioral: rescue resolver wrong output: '$out'"
  fi
  # no-profile: both layers missing -> all hardcoded defaults (issue #4)
  eth=$(mktemp -d); etp=$(mktemp -d)
  out2=$(cd "$etp" && HOME="$eth" python3 "$RRES" 2>&1)
  rm -rf "$eth" "$etp"   # cleanup before assert — no residue if fail aborts (#4 verify F7)
  if [ "$out2" = "gpt-5.6-sol|xhigh|600||default" ]; then
    pass "behavioral: rescue resolver no-profile yields all defaults (gpt-5.6-sol|xhigh|600||default)"
  else
    fail "behavioral: rescue no-profile wrong output: '$out2'"
  fi
  rm -rf "$th" "$tp"
else
  fail "behavioral: could not extract rescue resolver"
fi
rm -f "$RRES"

report_summary "rescue"
