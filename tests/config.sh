#!/usr/bin/env bash
# tests/config.sh — Layer 2: structural + behavioral runtime checks for the
# config skill. Structural section verifies SKILL.md frontmatter, read-only
# consumer invariants (no Codex HTTP wrapper / subprocess / mkdir literals),
# the v0.1 schema (4 fields + defaults), and the markdown table contract.
# Behavioral section EXTRACTS the inline python3 resolver from SKILL.md and
# runs it against fake-HOME + fake-project fixtures across 5 profile states
# (no-profile / global-only / project-only / mixed / project-overrides-global).
# Extracting the real resolver (rather than re-implementing it) verifies the
# exact code Claude executes — closing the SKILL.md -> runtime drift gap for
# the resolution algorithm itself.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"

CONFIG_SKILL="$REPO_ROOT/plugins/codex-pro/skills/codex-config/SKILL.md"

# ══════════════════════════════════════════════════════════════════
# Structural section
# ══════════════════════════════════════════════════════════════════

assert_file "$CONFIG_SKILL" "config SKILL.md exists"

# ── (a) Frontmatter parse ────────────────────────────────────────
fm_check=$(python3 - "$CONFIG_SKILL" <<'PY' 2>/dev/null
import re, sys
content = open(sys.argv[1]).read()
m = re.match(r"^---\n(.*?)\n---\n", content, re.DOTALL)
if not m:
    print("no_frontmatter"); sys.exit(0)
fm = m.group(1)
name_ok = "name: codex-config" in fm
bash_ok = "Bash" in fm
read_ok = "Read" in fm
keyword_ok = any(k in fm for k in ("profile", "config", "設定", "配置", "which model"))
print(f"name={name_ok} bash={bash_ok} read={read_ok} keyword={keyword_ok}")
PY
)
case "$fm_check" in
  *"name=True bash=True read=True keyword=True"*)
    pass "frontmatter: name=codex-config, allowed-tools has Bash + Read, profile/config keyword present" ;;
  *)
    fail "frontmatter check failed: $fm_check" ;;
esac

# ── (b) Read-only consumer invariants (no Codex / no mkdir) ──────
for forbidden in 'codex-call' 'codex exec' 'mkdir'; do
  cnt=$(grep -c "$forbidden" "$CONFIG_SKILL")
  assert_eq "0" "$cnt" "read-only invariant: SKILL body has zero '$forbidden'"
done

# ── (c) read-only consumer category prose ───────────────────────
rc=$(grep -c 'read-only consumer' "$CONFIG_SKILL")
[ "$rc" -ge 1 ] && pass "SKILL declares read-only consumer category (n=$rc)" \
  || fail "SKILL missing 'read-only consumer' category marker"

# ── (d) v0.1 schema: 4 fields + 4 defaults ──────────────────────
for field in model effort max_time focus_default; do
  cnt=$(grep -c "$field" "$CONFIG_SKILL")
  [ "$cnt" -ge 1 ] && pass "schema field documented: $field (n=$cnt)" \
    || fail "schema field missing: $field"
done
for dflt in 'gpt-5.5' 'xhigh' '600'; do
  cnt=$(grep -c "$dflt" "$CONFIG_SKILL")
  [ "$cnt" -ge 1 ] && pass "hardcoded default documented: $dflt (n=$cnt)" \
    || fail "hardcoded default missing: $dflt"
done

# ── (e) focus_default scoped to adversarial-review only ─────────
if grep -q 'adversarial-review only' "$CONFIG_SKILL"; then
  pass "focus_default scoped to adversarial-review only"
else
  fail "focus_default applicability note missing"
fi

# ── (f) output format markers ───────────────────────────────────
if grep -q 'field | resolved value | source' "$CONFIG_SKILL"; then
  pass "output table column header documented"
else
  fail "output table column header missing"
fi
for marker in '(default)' 'Global profile:' 'Project profile:'; do
  cnt=$(grep -c -- "$marker" "$CONFIG_SKILL")
  [ "$cnt" -ge 1 ] && pass "output marker present: $marker (n=$cnt)" \
    || fail "output marker missing: $marker"
done

# (PyYAML-absence is checked against the EXTRACTED resolver code below — the
#  prose deliberately mentions `import yaml` to explain it is NOT used, so
#  scanning the whole SKILL.md would false-positive.)

# ══════════════════════════════════════════════════════════════════
# Behavioral section — extract the real resolver from SKILL.md and run
# it against 5 profile states using fake HOME + fake project cwd.
# ══════════════════════════════════════════════════════════════════

# Extract the inline python3 resolver block (the one wrapped in `python3 - <<'PY'`)
RESOLVER=$(mktemp)
python3 - "$CONFIG_SKILL" "$RESOLVER" <<'PY'
import re, sys
content = open(sys.argv[1]).read()
m = re.search(r"python3 - <<'PY'\n(.*?)\nPY\n```", content, re.DOTALL)
if not m:
    sys.exit("RESOLVER_EXTRACT_FAIL")
open(sys.argv[2], "w").write(m.group(1))
PY
if [ -s "$RESOLVER" ]; then
  pass "behavioral: extracted inline python3 resolver from SKILL.md"
else
  fail "behavioral: could not extract resolver block from SKILL.md"
fi

# Extracted resolver must NOT depend on PyYAML (python3 stdlib has no yaml)
yz=$(grep -c 'yaml.safe_load\|import yaml' "$RESOLVER")
assert_eq "0" "$yz" "resolver code does not depend on PyYAML (import yaml absent)"

# run_resolver <global_yaml_or_empty> <project_yaml_or_empty> -> sets RESOLVER_OUT
run_resolver() {
  local global_yaml="$1" project_yaml="$2"
  local th tp
  th=$(mktemp -d); tp=$(mktemp -d)
  if [ -n "$global_yaml" ]; then
    mkdir -p "$th/.codex-pro"; printf '%s' "$global_yaml" > "$th/.codex-pro/profile.yaml"
  fi
  if [ -n "$project_yaml" ]; then
    mkdir -p "$tp/.codex-pro"; printf '%s' "$project_yaml" > "$tp/.codex-pro/profile.yaml"
  fi
  RESOLVER_OUT=$(cd "$tp" && HOME="$th" python3 "$RESOLVER" 2>&1)
  rm -rf "$th" "$tp"
}

# ── Scenario 1: no profile → all defaults + both "does not exist" ──
run_resolver "" ""
echo "$RESOLVER_OUT" | grep -qE '^\| model +\| gpt-5.5 +\| \(default\) +\|' \
  && pass "no-profile: model=gpt-5.5 (default)" || fail "no-profile: model row wrong: $RESOLVER_OUT"
echo "$RESOLVER_OUT" | grep -qE '^\| max_time +\| 600 +\| \(default\) +\|' \
  && pass "no-profile: max_time=600 (default)" || fail "no-profile: max_time row wrong"
echo "$RESOLVER_OUT" | grep -q 'Global profile:  ~/.codex-pro/profile.yaml (does not exist)' \
  && pass "no-profile: global file reported as not existing" || fail "no-profile: global existence wrong"
echo "$RESOLVER_OUT" | grep -q 'Project profile: .codex-pro/profile.yaml (does not exist)' \
  && pass "no-profile: project file reported as not existing" || fail "no-profile: project existence wrong"

# ── Scenario 2: global-only {model: gpt-5.0} → model=global, rest default ──
run_resolver $'model: gpt-5.0\n' ""
echo "$RESOLVER_OUT" | grep -qE '^\| model +\| gpt-5.0 +\| global +\|' \
  && pass "global-only: model=gpt-5.0 source=global" || fail "global-only: model row wrong: $RESOLVER_OUT"
echo "$RESOLVER_OUT" | grep -qE '^\| effort +\| xhigh +\| \(default\) +\|' \
  && pass "global-only: effort still default" || fail "global-only: effort row wrong"

# ── Scenario 3: project-only {max_time: 1200} → max_time=project, rest default ──
run_resolver "" $'max_time: 1200\n'
echo "$RESOLVER_OUT" | grep -qE '^\| max_time +\| 1200 +\| project +\|' \
  && pass "project-only: max_time=1200 source=project" || fail "project-only: max_time row wrong: $RESOLVER_OUT"
echo "$RESOLVER_OUT" | grep -qE '^\| model +\| gpt-5.5 +\| \(default\) +\|' \
  && pass "project-only: model still default" || fail "project-only: model row wrong"

# ── Scenario 4: mixed (global model + project max_time) ──
run_resolver $'model: gpt-5.0\n' $'max_time: 900\n'
echo "$RESOLVER_OUT" | grep -qE '^\| model +\| gpt-5.0 +\| global +\|' \
  && pass "mixed: model from global" || fail "mixed: model row wrong: $RESOLVER_OUT"
echo "$RESOLVER_OUT" | grep -qE '^\| max_time +\| 900 +\| project +\|' \
  && pass "mixed: max_time from project" || fail "mixed: max_time row wrong"

# ── Scenario 5: project overrides global for same field ──
run_resolver $'model: gpt-5.0\n' $'model: gpt-4.5\n'
echo "$RESOLVER_OUT" | grep -qE '^\| model +\| gpt-4.5 +\| project +\|' \
  && pass "override: project model wins over global" || fail "override: model row wrong: $RESOLVER_OUT"

# ── Scenario 6 (robustness): malformed YAML + unknown field silently tolerated ──
run_resolver "" $'this is not valid: : yaml\nfuture_field: foo\nmodel: gpt-5.0\n'
# malformed lines ignored; model still parsed; unknown field not surfaced as a row
echo "$RESOLVER_OUT" | grep -qE '^\| model +\| gpt-5.0 +\| project +\|' \
  && pass "robustness: valid field parsed despite malformed/unknown lines" || fail "robustness: model row wrong: $RESOLVER_OUT"
echo "$RESOLVER_OUT" | grep -q 'future_field' \
  && fail "robustness: unknown field leaked into output table" || pass "robustness: unknown field silently ignored"
rowcount=$(echo "$RESOLVER_OUT" | grep -cE '^\| (model|effort|max_time|focus_default) ')
assert_eq "4" "$rowcount" "robustness: exactly 4 schema rows emitted"

# ── Scenario 7 (type coercion): max_time non-int → falls back to default ──
run_resolver "" $'max_time: abc\n'
echo "$RESOLVER_OUT" | grep -qE '^\| max_time +\| 600 +\| \(default\) +\|' \
  && pass "type-coercion: max_time=abc falls back to 600 (default)" || fail "type-coercion: max_time row wrong: $RESOLVER_OUT"

rm -f "$RESOLVER"

report_summary "config"
