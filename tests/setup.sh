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

if ! SETUP_TMP_PARENT=$(cd "${TMPDIR:-/tmp}" 2>/dev/null && pwd -P) \
    || [ -z "$SETUP_TMP_PARENT" ] || [ "$SETUP_TMP_PARENT" = "/" ]; then
  echo "FATAL: setup tests require a non-root temporary parent directory" >&2
  exit 2
fi
SETUP_TEST_ROOT=""

setup_test_root_is_safe() {
  local candidate="$1" parent base
  [ -n "$candidate" ] || return 1
  parent=$(cd "$(dirname "$candidate")" 2>/dev/null && pwd -P) || return 1
  base=$(basename "$candidate")
  [ "$parent" = "$SETUP_TMP_PARENT" ] || return 1
  case "$base" in
    codex-setup-tests.*) return 0 ;;
    *) return 1 ;;
  esac
}

cleanup_setup_test_root() {
  local candidate="${SETUP_TEST_ROOT:-}"
  [ -n "$candidate" ] || return 0
  if ! setup_test_root_is_safe "$candidate"; then
    printf 'FATAL: refusing unsafe setup test cleanup path: %s\n' "$candidate" >&2
    return 1
  fi
  if [ -e "$candidate" ]; then
    rm -rf -- "$candidate"
  fi
  SETUP_TEST_ROOT=""
}

if ! SETUP_TEST_ROOT=$(mktemp -d "$SETUP_TMP_PARENT/codex-setup-tests.XXXXXX") \
    || [ -z "$SETUP_TEST_ROOT" ] || [ ! -d "$SETUP_TEST_ROOT" ] \
    || ! setup_test_root_is_safe "$SETUP_TEST_ROOT"; then
  echo "FATAL: could not create a safe isolated setup test root" >&2
  exit 2
fi
trap cleanup_setup_test_root EXIT
trap 'exit 130' HUP INT TERM

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

# ── Codex-only runtime resolver check ───────────────────────────
# Mirrors the generated $codex-setup behavior. The Claude source skill keeps
# using codex_call_check and its existing PATH contract.
codex_runtime_check() {
  local skill_dir="$1"
  local bundle_root wrapper output status=0
  bundle_root=$(cd "$skill_dir/../.." 2>/dev/null && pwd -P) || {
    echo "unavailable reason=skill_dir_invalid"
    return
  }
  wrapper="$bundle_root/bin/codex-pro-call"

  if [ ! -L "$wrapper" ] && [ -f "$wrapper" ] && [ -x "$wrapper" ]; then
    output=$("$wrapper" --check 2>&1) || status=$?
    if [ "$status" -eq 0 ]; then
      echo "bundled path=$wrapper $output"
      return
    fi
    case "$output" in
      error=unsupported_platform*|error=swift_missing*)
        echo "unavailable source=bundled $output"
        ;;
      *)
        echo "package_corruption path=$wrapper $output"
        ;;
    esac
    return
  fi

  if [ -e "$bundle_root/.codex-bundle-files" ] \
      || [ -L "$bundle_root/.codex-bundle-files" ] \
      || [ -e "$bundle_root/.codex-plugin/plugin.json" ] \
      || [ -L "$bundle_root/.codex-plugin/plugin.json" ]; then
    echo "package_corruption path=$wrapper error=wrapper_missing_or_not_executable"
    return
  fi

  if cc_path=$(command -v codex-call 2>/dev/null); then
    echo "legacy_path_fallback path=$cc_path"
  else
    echo "unavailable error=runtime_unavailable"
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
export -f oauth_check codex_call_check codex_runtime_check manifest_self_check

# ── Tests ────────────────────────────────────────────────────────

# OAuth missing → "missing"
out=$(with_empty_home bash -c 'oauth_check')
assert_eq "missing" "$out" "OAuth check reports 'missing' under HOME=/nonexistent"

# OAuth present with mode 600
fake_home="$SETUP_TEST_ROOT/fake-home"
mkdir -p "$fake_home/.codex"
printf '{"fake":"token"}\n' > "$fake_home/.codex/auth.json"
chmod 600 "$fake_home/.codex/auth.json"
out=$(HOME="$fake_home" bash -c 'oauth_check')
assert_contains "$out" "readable mode=600" "OAuth check reports readable mode=600 for fake token"

# codex-call PATH stripped → "missing"
out=$(with_path_stripped bash -c 'codex_call_check')
assert_eq "missing" "$out" "codex-call check reports 'missing' under stripped PATH"

# codex-call present via fake stub
stub_dir="$SETUP_TEST_ROOT/path-stub"
mkdir -p "$stub_dir"
cat > "$stub_dir/codex-call" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$stub_dir/codex-call"
out=$(PATH="$stub_dir:/usr/bin:/bin" bash -c 'codex_call_check')
assert_contains "$out" "found path=$stub_dir/codex-call" "codex-call check reports found path for stub"

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

# ── Codex bundled resolver matrix ───────────────────────────────
resolver_root="$SETUP_TEST_ROOT/resolver"
bundle_root="$resolver_root/native bundle"
skill_dir="$bundle_root/skills/codex-setup"
mkdir -p "$skill_dir" "$bundle_root/bin"
bundle_root=$(cd "$bundle_root" && pwd -P)
skill_dir="$bundle_root/skills/codex-setup"

# A wrapper inside a path containing spaces is preferred and checked.
cat > "$bundle_root/bin/codex-pro-call" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "--check" ]; then
  printf 'ok runtime=%s sha256=fixture swift=fixture\n' "$0"
  exit 0
fi
exit 99
STUB
chmod +x "$bundle_root/bin/codex-pro-call"
out=$(codex_runtime_check "$skill_dir")
assert_contains "$out" "bundled path=$bundle_root/bin/codex-pro-call" "Codex resolver prefers bundled wrapper from active skill path"
assert_contains "$out" "ok runtime=" "Codex resolver invokes wrapper --check"

# Unsupported platform and missing Swift are producer limitations, not
# package-corruption reports.
cat > "$bundle_root/bin/codex-pro-call" <<'STUB'
#!/usr/bin/env bash
printf 'error=unsupported_platform actual=Linux\n'
exit 2
STUB
chmod +x "$bundle_root/bin/codex-pro-call"
out=$(codex_runtime_check "$skill_dir")
assert_contains "$out" "unavailable source=bundled error=unsupported_platform" "unsupported platform is reported as producer unavailable"

cat > "$bundle_root/bin/codex-pro-call" <<'STUB'
#!/usr/bin/env bash
printf 'error=swift_missing\n'
exit 2
STUB
chmod +x "$bundle_root/bin/codex-pro-call"
out=$(codex_runtime_check "$skill_dir")
assert_contains "$out" "unavailable source=bundled error=swift_missing" "missing Swift is reported as producer unavailable"

# A native marker makes missing bundled runtime fail closed even when PATH has
# a tempting codex-call. The stub writes a marker if it is ever invoked.
rm -f "$bundle_root/bin/codex-pro-call"
mkdir -p "$bundle_root/.codex-plugin" "$resolver_root/path-stub"
printf '{}\n' > "$bundle_root/.codex-plugin/plugin.json"
cat > "$resolver_root/path-stub/codex-call" <<'STUB'
#!/usr/bin/env bash
printf invoked > "$PATH_STUB_MARKER"
STUB
chmod +x "$resolver_root/path-stub/codex-call"
path_stub_marker="$resolver_root/path-stub-invoked"
out=$(PATH_STUB_MARKER="$path_stub_marker" PATH="$resolver_root/path-stub:/usr/bin:/bin" \
  codex_runtime_check "$skill_dir")
assert_contains "$out" "package_corruption" "native marker makes missing wrapper fail closed"
assert_no_file "$path_stub_marker" "native corruption does not invoke PATH codex-call"

# A wrapper symlink is not an in-bundle regular executable, even when its
# external target exits 0. Native package state must reject it before either
# reporting READY or reopening the legacy PATH fallback.
symlink_wrapper_target="$resolver_root/external-codex-pro-call"
symlink_wrapper_marker="$resolver_root/symlink-wrapper-invoked"
cat > "$symlink_wrapper_target" <<'STUB'
#!/usr/bin/env bash
printf invoked > "$SYMLINK_WRAPPER_MARKER"
exit 0
STUB
chmod +x "$symlink_wrapper_target"
ln -s "$symlink_wrapper_target" "$bundle_root/bin/codex-pro-call"
out=$(SYMLINK_WRAPPER_MARKER="$symlink_wrapper_marker" \
  PATH="$resolver_root/path-stub:/usr/bin:/bin" codex_runtime_check "$skill_dir")
assert_contains "$out" "package_corruption" \
  "bundled wrapper symlink is classified as package corruption"
case "$out" in
  *"bundled path="*|*"legacy_path_fallback"*)
    fail "bundled wrapper symlink is never reported READY or as legacy fallback" ;;
  *)
    pass "bundled wrapper symlink is never reported READY or as legacy fallback" ;;
esac
assert_no_file "$symlink_wrapper_marker" \
  "bundled wrapper symlink target is rejected before execution"
rm -f "$bundle_root/bin/codex-pro-call" "$symlink_wrapper_target" \
  "$symlink_wrapper_marker"

# A broken marker symlink is still package state. It must not disappear under
# test -e semantics and silently reopen the legacy PATH fallback.
rm -f "$bundle_root/.codex-plugin/plugin.json"
ln -s "$resolver_root/missing-native-marker" "$bundle_root/.codex-plugin/plugin.json"
out=$(PATH="$resolver_root/path-stub:/usr/bin:/bin" codex_runtime_check "$skill_dir")
assert_contains "$out" "package_corruption" "broken native marker symlink still fails closed"
rm -rf "$bundle_root/.codex-plugin"

# Inventory is also a native/generated marker and must fail closed.
printf 'bin/codex-pro-call\n' > "$bundle_root/.codex-bundle-files"
out=$(PATH="$resolver_root/path-stub:/usr/bin:/bin" codex_runtime_check "$skill_dir")
assert_contains "$out" "package_corruption" "bundle inventory makes missing wrapper fail closed"

# Search permission makes test -x true for a directory on POSIX. The wrapper
# must be a regular executable file, not merely an executable path.
mkdir "$bundle_root/bin/codex-pro-call"
out=$(PATH="$resolver_root/path-stub:/usr/bin:/bin" codex_runtime_check "$skill_dir")
assert_contains "$out" "error=wrapper_missing_or_not_executable" \
  "wrapper directory is classified before execution as package corruption"
rm -rf "$bundle_root/bin/codex-pro-call"

# Only an unmarked legacy mirror may use PATH compatibility.
rm -f "$bundle_root/.codex-bundle-files"
out=$(PATH="$resolver_root/path-stub:/usr/bin:/bin" codex_runtime_check "$skill_dir")
assert_contains "$out" "legacy_path_fallback path=$resolver_root/path-stub/codex-call" "unmarked legacy mirror uses explicit PATH fallback"

out=$(PATH="/usr/bin:/bin" codex_runtime_check "$skill_dir")
assert_contains "$out" "unavailable error=runtime_unavailable" "resolver reports unavailable when no bundled or PATH runtime exists"

# ── Generated Codex setup contract ──────────────────────────────
generated_setup="$REPO_ROOT/.codex/skills/codex-setup/SKILL.md"
assert_file "$generated_setup" "generated Codex setup skill exists"
if [ -r "$generated_setup" ]; then
  generated_body=$(<"$generated_setup")
  for required_text in \
    'SKILL_DIR' \
    'BUNDLE_ROOT' \
    'bin/codex-pro-call' \
    '[ ! -L "$wrapper" ] && [ -f "$wrapper" ] && [ -x "$wrapper" ]' \
    '[ -L "$BUNDLE_ROOT/.codex-plugin/plugin.json" ]' \
    '[ -L "$BUNDLE_ROOT/.codex-bundle-files" ]' \
    '--check' \
    'bundled' \
    'legacy PATH fallback' \
    'package corruption' \
    'unsupported_platform' \
    'swift_missing' \
    'macOS' \
    'Xcode Command Line Tools' \
    '$codex-status' \
    '$codex-result' \
    '$codex-config' \
    '$codex-cancel'; do
    assert_contains "$generated_body" "$required_text" "generated setup documents/runtime-resolves: $required_text"
  done

  for forbidden_text in \
    'CLAUDE_PLUGIN_ROOT' \
    'CODEX_PLUGIN_ROOT' \
    'CODEX_SKILL_ROOT' \
    'CODEX_HOME' \
    '~/.codex/plugins/cache'; do
    case "$generated_body" in
      *"$forbidden_text"*) fail "generated setup does not depend on $forbidden_text" ;;
      *) pass "generated setup does not depend on $forbidden_text" ;;
    esac
  done
fi

# The hand-maintained Claude skill deliberately retains its own PATH and
# .claude-plugin checks; only generated Codex content changes resolution.
source_setup="$REPO_ROOT/plugins/codex-pro/skills/codex-setup/SKILL.md"
source_body=$(<"$source_setup")
assert_contains "$source_body" 'command -v codex-call' "Claude source setup retains PATH runtime lookup"
assert_contains "$source_body" '.claude-plugin/plugin.json' "Claude source setup retains Claude manifest self-check"

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
