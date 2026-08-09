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
NATIVE_RESCUE_SKILL="$REPO_ROOT/skills/codex-rescue/SKILL.md"

assert_file "$RESCUE_SKILL" "rescue SKILL.md exists"
assert_file "$NATIVE_RESCUE_SKILL" "native rescue SKILL.md exists"

# ── Native runtime preflight must still produce the rescue result contract ──
native_preflight_check=$(python3 - "$NATIVE_RESCUE_SKILL" <<'PY'
import re
import sys

text = open(sys.argv[1], encoding="utf-8").read()
match = re.search(
    r"### Step 4\.2: Resolve bundled Codex runtime\n(.*?)\n## Step 5: Handle exit code",
    text,
    re.DOTALL,
)
if not match:
    print("resolver=missing")
    raise SystemExit(0)
resolver = match.group(1)
step5 = text[match.end():]

resolver_blocks = re.findall(r"```(?:bash)?\n(.*?)\n```", resolver, re.DOTALL)
resolver_block = resolver_blocks[0] if resolver_blocks else ""


def resolver_has_no_exit(block: str) -> bool:
    return re.search(
        r"(?<![A-Za-z0-9_])exit(?![A-Za-z0-9_])", block
    ) is None


def wrapper_success_condition_is_safe(condition: str) -> bool:
    normalized = " ".join(condition.replace("\\\n", " ").split())
    if "||" in normalized:
        return False
    predicates = [part.strip() for part in normalized.split("&&")]
    required = {
        '[ ! -L "$BUNDLE_ROOT/bin" ]',
        '[ -d "$BUNDLE_ROOT/bin" ]',
        '[ ! -L "$CODEX_CALL" ]',
        '[ -f "$CODEX_CALL" ]',
        '[ -x "$CODEX_CALL" ]',
    }
    return required.issubset(predicates) and all(
        re.fullmatch(r"\[ .+ \]", predicate) is not None
        for predicate in predicates
    )


def invocation_block_guarded(block: str) -> bool:
    guard = re.fullmatch(
        r'if \[ -z "\$CODEX_RUNTIME_ERROR" \]; then\n(?P<body>.*?)\nfi',
        block.strip(),
        re.DOTALL,
    )
    if not guard:
        return False
    body = guard.group("body")
    return (
        body.count('"$CODEX_CALL"') == 1
        and re.search(r'^[ \t]+"\$CODEX_CALL"[ \t]+\\$', body, re.MULTILINE)
        is not None
    )


invocation_section = re.search(
    r"### Step 4\.3: codex-call invocation\n(.*?)\n## Step 5: Handle exit code",
    text,
    re.DOTALL,
)
invocation_blocks = (
    re.findall(r"```(?:bash)?\n(.*?)\n```", invocation_section.group(1), re.DOTALL)
    if invocation_section
    else []
)
call_blocks = [block for block in invocation_blocks if '"$CODEX_CALL"' in block]
invocation_block = call_blocks[0] if len(call_blocks) == 1 else ""
guard_scope = invocation_block_guarded(invocation_block)
guard_match = re.fullmatch(
    r'if \[ -z "\$CODEX_RUNTIME_ERROR" \]; then\n(?P<body>.*?)\nfi',
    invocation_block.strip(),
    re.DOTALL,
)
mutated_block = (
    'if [ -z "$CODEX_RUNTIME_ERROR" ]; then\nfi\n' + guard_match.group("body")
    if guard_match
    else invocation_block
)
detail_contract = all(
    token in step5
    for token in (
        "Runtime preflight detail:",
        "$CODEX_RUNTIME_DETAIL",
        "CR／LF／TAB",
        "control characters",
        "500 個字元",
        "不得把未清理或未截斷的 detail 放進 YAML frontmatter",
    )
)
wrapper_success_match = re.search(
    r'if (?P<condition>.*?)\s*;\s*then\n\s*CODEX_RUNTIME_STATUS=0',
    resolver,
    re.DOTALL,
)
wrapper_success_condition = (
    wrapper_success_match.group("condition") if wrapper_success_match else ""
)
mutated_wrapper_condition = re.sub(
    r"\s*&&\s*", " || ", wrapper_success_condition, count=1
)
mutated_exit_block = resolver_block + "\nexit 2"
checks = {
    "resolver": "present",
    "error_var": str('CODEX_RUNTIME_ERROR=""' in resolver).lower(),
    "detail_var": str('CODEX_RUNTIME_DETAIL=""' in resolver).lower(),
    "no_direct_exit": str(resolver_has_no_exit(resolver_block)).lower(),
    "exit_mutation_rejected": str(
        resolver_has_no_exit(resolver_block)
        and not resolver_has_no_exit(mutated_exit_block)
    ).lower(),
    "wrapper_and_condition": str(
        wrapper_success_condition_is_safe(wrapper_success_condition)
    ).lower(),
    "wrapper_or_mutation_rejected": str(
        wrapper_success_condition_is_safe(wrapper_success_condition)
        and not wrapper_success_condition_is_safe(mutated_wrapper_condition)
    ).lower(),
    "broken_markers": str(
        '[ -L "$BUNDLE_ROOT/.codex-plugin/plugin.json" ]' in resolver
        and '[ -L "$BUNDLE_ROOT/.codex-bundle-files" ]' in resolver
    ).lower(),
    "skip_invocation": str('if [ -z "$CODEX_RUNTIME_ERROR" ]' in resolver).lower(),
    "guard_scope": str(guard_scope).lower(),
    "guard_mutation_rejected": str(not invocation_block_guarded(mutated_block)).lower(),
    "runtime_unavailable": str("runtime_unavailable" in step5).lower(),
    "package_corruption": str("package_corruption" in step5).lower(),
    "result_enum": str(bool(re.search(
        r"error: <[^>]*runtime_unavailable[^>]*package_corruption[^>]*>", step5
    ))).lower(),
    "detail_contract": str(detail_contract).lower(),
    "native_no_retry": str(all(
        token in step5
        for token in ("package_corruption", "runtime_unavailable", "所有 failure 都不 retry")
    )).lower(),
    "result_path": str(".codex-pro/rescue-" in text).lower(),
    "all_failures": str("所有 failure 仍寫 result file" in text).lower(),
}
print(" ".join(f"{key}={value}" for key, value in checks.items()))
PY
)
case "$native_preflight_check" in
  *"resolver=present error_var=true detail_var=true no_direct_exit=true exit_mutation_rejected=true wrapper_and_condition=true wrapper_or_mutation_rejected=true broken_markers=true skip_invocation=true guard_scope=true guard_mutation_rejected=true runtime_unavailable=true package_corruption=true result_enum=true detail_contract=true native_no_retry=true result_path=true all_failures=true"*)
    pass "native rescue preflight maps failures and preserves structured result output" ;;
  *)
    fail "native rescue preflight/result contract incomplete: $native_preflight_check" ;;
esac

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
