#!/usr/bin/env bash
# tests/setup.sh — Layer 2: behavioral simulation of the setup skill's
# three checks (OAuth token / codex-call PATH / plugin manifest self-check)
# in isolated environments, plus the read-only discipline verification.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/isolate.sh"

# ── Check 1: OAuth token state ───────────────────────────────────
# Re-implements the body of the SKILL Check 1 so we can drive it under
# isolation. Stays semantically identical to plugins/codex-pro/skills/codex-setup/SKILL.md.
oauth_check() {
  if [ -r "$HOME/.codex/auth.json" ]; then
    local mode
    mode=$(stat -f '%OLp' "$HOME/.codex/auth.json" 2>/dev/null \
        || stat -c '%a' "$HOME/.codex/auth.json" 2>/dev/null)
    echo "readable mode=$mode"
  elif [ -e "$HOME/.codex/auth.json" ]; then
    echo "exists_but_not_readable"
  else
    echo "missing"
  fi
}

# ── Check 2: codex-call wrapper discovery ────────────────────────
codex_call_check() {
  if cc_path=$(command -v codex-call 2>/dev/null); then
    echo "found path=$cc_path"
  else
    echo "missing"
  fi
}

# ── Check 3: plugin manifest self-check ──────────────────────────
manifest_self_check() {
  local plugin_root="${CLAUDE_PLUGIN_ROOT:-$(pwd)}"
  local manifest="$plugin_root/.claude-plugin/plugin.json"
  if [ ! -r "$manifest" ]; then
    echo "not_found path=$manifest"
    return
  fi
  python3 - "$manifest" <<'PY'
import json, sys
path = sys.argv[1]
try:
    d = json.load(open(path))
    print(f"ok name={d.get('name','?')} version={d.get('version','?')} path={path}")
except json.JSONDecodeError as e:
    print(f"parse_error: line {e.lineno} col {e.colno}: {e.msg} (path={path})")
except Exception as e:
    print(f"parse_error: {type(e).__name__}: {e} (path={path})")
PY
}

# Export functions so they survive into subshell wrappers
export -f oauth_check codex_call_check manifest_self_check

# ── Tests ────────────────────────────────────────────────────────

# OAuth missing → "missing"
out=$(with_empty_home bash -c 'oauth_check')
assert_eq "missing" "$out" "OAuth check reports 'missing' under HOME=/nonexistent"

# OAuth present with mode 600
fake_home=$(mktemp -d)
mkdir -p "$fake_home/.codex"
printf '{"fake":"token"}\n' > "$fake_home/.codex/auth.json"
chmod 600 "$fake_home/.codex/auth.json"
out=$(HOME="$fake_home" bash -c 'oauth_check')
assert_contains "$out" "readable mode=600" "OAuth check reports readable mode=600 for fake token"
rm -rf "$fake_home"

# codex-call PATH stripped → "missing"
out=$(with_path_stripped bash -c 'codex_call_check')
assert_eq "missing" "$out" "codex-call check reports 'missing' under stripped PATH"

# codex-call present via fake stub
stub_dir=$(mktemp -d)
cat > "$stub_dir/codex-call" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$stub_dir/codex-call"
out=$(PATH="$stub_dir:/usr/bin:/bin" bash -c 'codex_call_check')
assert_contains "$out" "found path=$stub_dir/codex-call" "codex-call check reports found path for stub"
rm -rf "$stub_dir"

# Manifest self-check with valid manifest
out=$(with_fake_plugin_root '
  printf "{\"name\":\"fake\",\"version\":\"0.1\"}\n" > "$CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json"
  manifest_self_check
')
assert_contains "$out" "ok name=fake" "manifest_self_check reports ok for valid manifest"

# Manifest self-check with corrupted JSON
out=$(with_fake_plugin_root '
  printf "{ this is not valid json\n" > "$CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json"
  manifest_self_check
')
assert_contains "$out" "parse_error" "manifest_self_check reports parse_error for corrupted JSON"
assert_contains "$out" "line " "parse_error message includes line number"

# Manifest self-check with missing manifest file
out=$(with_fake_plugin_root '
  # leave .claude-plugin/ empty — no plugin.json
  manifest_self_check
')
assert_contains "$out" "not_found path=" "manifest_self_check reports not_found when manifest absent"

# ── Read-only discipline ─────────────────────────────────────────
# Running all three checks against the real environment must leave
# ~/.codex/ unchanged. This verifies "Setup performs no mutating actions".
if [ -d "$HOME/.codex" ]; then
  ls_before=$(ls -la "$HOME/.codex" 2>&1)
  # Run real checks in the user's actual environment (no isolation)
  oauth_check >/dev/null
  codex_call_check >/dev/null
  manifest_self_check >/dev/null
  ls_after=$(ls -la "$HOME/.codex" 2>&1)
  if [ "$ls_before" = "$ls_after" ]; then
    pass "~/.codex/ listing unchanged after running all three setup checks (read-only discipline)"
  else
    fail "~/.codex/ listing changed after setup checks — mutation detected"
  fi
else
  pass "~/.codex/ does not exist; read-only discipline vacuously satisfied"
fi

report_summary "setup"
