#!/usr/bin/env bash
# tests/codex-runtime.sh — Offline contract tests for the vendored Codex
# runtime, its provenance, wrapper preflight, and release smoke gate.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"

PINNED_COMMIT="6fc6883ef1d655f5f782a97accc0a5adacc76226"
PINNED_BLOB="c2418f5c0a0a3d092859d6252d2910c460dee981"
PINNED_BYTES="25329"
PINNED_SHA256="fa80364b2159f3df4f2d9a27c885a7b50e510bf52933abaa79564945bedb6af0"
PINNED_SOURCE_PATH="plugins/parallel-ai-agents/bin/codex-call"
PINNED_RAW_URL="https://raw.githubusercontent.com/PsychQuant/parallel-ai-agents/$PINNED_COMMIT/$PINNED_SOURCE_PATH"

SOURCE_RUNTIME="$REPO_ROOT/plugins/codex-pro/bin/codex-call"
SOURCE_WRAPPER="$REPO_ROOT/plugins/codex-pro/bin/codex-pro-call"
SOURCE_PROVENANCE="$REPO_ROOT/plugins/codex-pro/references/codex-call-provenance.json"
TEST_MODE="${1:-full}"

case "$TEST_MODE" in
  full|--source-only|--smoke) ;;
  *) echo "FATAL: unknown test option: $TEST_MODE" >&2; exit 2 ;;
esac

assert_prefix() {
  local actual="$1" expected="$2" msg="$3"
  case "$actual" in
    "$expected"*) pass "$msg" ;;
    *) fail "$msg (expected prefix='$expected', actual='$actual')" ;;
  esac
}

file_mode() {
  stat -f '%OLp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null
}

assert_runtime_fingerprint() {
  local path="$1" label="$2"
  if [ ! -f "$path" ]; then
    fail "$label exists (missing: '$path')"
    return
  fi

  assert_sha256 "$path" "$PINNED_SHA256" "$label matches pinned SHA-256"
  assert_eq "$PINNED_BYTES" "$(wc -c < "$path" | tr -d ' ')" "$label matches pinned byte count"
  if [ -x "$path" ]; then
    pass "$label is executable"
  else
    fail "$label is executable (mode=$(file_mode "$path" 2>/dev/null || printf unknown))"
  fi
}

# ── Pinned source and generated copies ───────────────────────────
assert_runtime_fingerprint "$SOURCE_RUNTIME" "source runtime"
if [ "$TEST_MODE" != "--source-only" ]; then
  assert_runtime_fingerprint "$REPO_ROOT/bin/codex-call" "root bundle runtime"
  assert_runtime_fingerprint "$REPO_ROOT/.codex/bin/codex-call" ".codex bundle runtime"
fi

wrapper_paths=("$SOURCE_WRAPPER")
provenance_paths=("$SOURCE_PROVENANCE")
if [ "$TEST_MODE" != "--source-only" ]; then
  wrapper_paths+=("$REPO_ROOT/bin/codex-pro-call" "$REPO_ROOT/.codex/bin/codex-pro-call")
  provenance_paths+=(
    "$REPO_ROOT/references/codex-call-provenance.json"
    "$REPO_ROOT/.codex/references/codex-call-provenance.json"
  )
fi

for wrapper_path in "${wrapper_paths[@]}"; do
  assert_file "$wrapper_path" "runtime wrapper exists: ${wrapper_path#"$REPO_ROOT"/}"
  if [ -e "$wrapper_path" ] && [ ! -x "$wrapper_path" ]; then
    fail "runtime wrapper is executable: ${wrapper_path#"$REPO_ROOT"/}"
  elif [ -x "$wrapper_path" ]; then
    pass "runtime wrapper is executable: ${wrapper_path#"$REPO_ROOT"/}"
  fi
done

for provenance_path in "${provenance_paths[@]}"; do
  assert_file "$provenance_path" "runtime provenance exists: ${provenance_path#"$REPO_ROOT"/}"
done

if [ -r "$SOURCE_PROVENANCE" ]; then
  provenance_summary=$(python3 - "$SOURCE_PROVENANCE" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)

issues = ",".join(str(value) for value in data.get("known_upstream_issues", []))
for key in ("repository", "path", "commit", "blob", "raw_url", "bytes", "mode", "sha256", "license"):
    print(f"{key}={data.get(key, '')}")
print(f"issues={issues}")
PY
  )
  assert_contains "$provenance_summary" "repository=https://github.com/PsychQuant/parallel-ai-agents" "provenance records upstream repository"
  assert_contains "$provenance_summary" "path=$PINNED_SOURCE_PATH" "provenance records upstream path"
  assert_contains "$provenance_summary" "commit=$PINNED_COMMIT" "provenance records immutable commit"
  assert_contains "$provenance_summary" "blob=$PINNED_BLOB" "provenance records Git blob"
  assert_contains "$provenance_summary" "raw_url=$PINNED_RAW_URL" "provenance raw URL is commit-pinned"
  assert_contains "$provenance_summary" "bytes=$PINNED_BYTES" "provenance records byte count"
  assert_contains "$provenance_summary" "mode=100755" "provenance records executable Git mode"
  assert_contains "$provenance_summary" "sha256=$PINNED_SHA256" "provenance records SHA-256"
  assert_contains "$provenance_summary" "license=MIT" "provenance records MIT license"
  assert_contains "$provenance_summary" "issues=28,35" "provenance records known upstream issues"
  case "$provenance_summary" in
    *'/main/'*|*'ref=main'*) fail "provenance does not use mutable main" ;;
    *) pass "provenance does not use mutable main" ;;
  esac
fi

assert_file "$REPO_ROOT/THIRD_PARTY_NOTICES.md" "third-party notice exists"
if [ -r "$REPO_ROOT/THIRD_PARTY_NOTICES.md" ]; then
  notice=$(<"$REPO_ROOT/THIRD_PARTY_NOTICES.md")
  assert_contains "$notice" "parallel-ai-agents" "third-party notice names upstream project"
  assert_contains "$notice" "$PINNED_COMMIT" "third-party notice names pinned commit"
  assert_contains "$notice" "MIT" "third-party notice names upstream license"
fi

# ── Wrapper static interface ─────────────────────────────────────
if [ -r "$SOURCE_WRAPPER" ]; then
  wrapper_source=$(<"$SOURCE_WRAPPER")
  assert_contains "$wrapper_source" "$PINNED_SHA256" "wrapper pins the recorded runtime hash"
  assert_contains "$wrapper_source" 'dirname "$0"' "wrapper derives its directory from \$0"
  assert_contains "$wrapper_source" 'exec "$RUNTIME_PATH" "$@"' "wrapper passes the original argument vector with exec"
  for error_class in unsupported_platform swift_missing runtime_missing runtime_not_executable hash_mismatch; do
    assert_contains "$wrapper_source" "error=$error_class" "wrapper declares error class: $error_class"
  done
fi

# ── Generated producer resolver contract ────────────────────────
for producer_skill in codex-review codex-adversarial-review codex-rescue; do
  producer_path="$REPO_ROOT/.codex/skills/$producer_skill/SKILL.md"
  assert_file "$producer_path" "generated producer exists: $producer_skill"
  if [ ! -r "$producer_path" ]; then
    continue
  fi

  producer_body=$(<"$producer_path")
  for required_text in \
    'SKILL_DIR' \
    'BUNDLE_ROOT' \
    'bin/codex-pro-call' \
    '.codex-bundle-files' \
    '.codex-plugin/plugin.json' \
    'error=package_corruption' \
    'legacy PATH fallback' \
    'command -v codex-call' \
    '"$CODEX_CALL" \'; do
    assert_contains "$producer_body" "$required_text" "$producer_skill runtime resolver contains: $required_text"
  done

  for forbidden_text in \
    'CLAUDE_PLUGIN_ROOT' \
    'CODEX_PLUGIN_ROOT' \
    'CODEX_SKILL_ROOT' \
    'CODEX_HOME' \
    '~/.codex/plugins/cache'; do
    case "$producer_body" in
      *"$forbidden_text"*) fail "$producer_skill does not depend on $forbidden_text" ;;
      *) pass "$producer_skill does not depend on $forbidden_text" ;;
    esac
  done

  if grep -q '^codex-call \\' "$producer_path"; then
    fail "$producer_skill has no bare codex-call invocation"
  else
    pass "$producer_skill has no bare codex-call invocation"
  fi
done

# Build a controlled Darwin fixture. The wrapper copy receives a fixture-only
# expected hash; the committed wrapper remains pinned to the real snapshot.
make_wrapper_fixture() {
  local fixture_root="$1" runtime_body="$2"
  mkdir -p "$fixture_root/bin" "$fixture_root/stubs"
  printf '%s\n' "$runtime_body" > "$fixture_root/bin/codex-call"
  chmod +x "$fixture_root/bin/codex-call"

  local fixture_sha
  fixture_sha=$(shasum -a 256 "$fixture_root/bin/codex-call" | awk '{print $1}')
  sed "s/$PINNED_SHA256/$fixture_sha/g" "$SOURCE_WRAPPER" > "$fixture_root/bin/codex-pro-call"
  chmod +x "$fixture_root/bin/codex-pro-call"

  ln -s "$(command -v bash)" "$fixture_root/stubs/bash"
  for tool in dirname shasum awk head; do
    if command -v "$tool" >/dev/null 2>&1; then
      ln -s "$(command -v "$tool")" "$fixture_root/stubs/$tool"
    fi
  done
  printf '#!/bin/sh\nprintf "Darwin\\n"\n' > "$fixture_root/stubs/uname"
  printf '#!/bin/sh\nprintf "Swift version fixture\\n"\n' > "$fixture_root/stubs/swift"
  chmod +x "$fixture_root/stubs/uname" "$fixture_root/stubs/swift"
}

run_wrapper_capture() {
  local wrapper="$1" fixture_path="$2"
  shift 2
  local status=0 output
  output=$(PATH="$fixture_path" "$wrapper" "$@" 2>&1) || status=$?
  printf '%s\n%s\n' "$status" "$output"
}

if ! RUNTIME_TMP_PARENT=$(cd "${TMPDIR:-/tmp}" 2>/dev/null && pwd -P) \
    || [ -z "$RUNTIME_TMP_PARENT" ] || [ "$RUNTIME_TMP_PARENT" = "/" ]; then
  echo "FATAL: runtime matrix requires a non-root temporary parent directory" >&2
  exit 2
fi
RUNTIME_MATRIX_ROOT=""

runtime_matrix_root_is_safe() {
  local candidate="$1" parent base
  [ -n "$candidate" ] || return 1
  parent=$(cd "$(dirname "$candidate")" 2>/dev/null && pwd -P) || return 1
  base=$(basename "$candidate")
  [ "$parent" = "$RUNTIME_TMP_PARENT" ] || return 1
  case "$base" in
    codex-runtime-matrix.*) return 0 ;;
    *) return 1 ;;
  esac
}

cleanup_runtime_matrix() {
  local candidate="${RUNTIME_MATRIX_ROOT:-}"
  [ -n "$candidate" ] || return 0
  if ! runtime_matrix_root_is_safe "$candidate"; then
    printf 'FATAL: refusing unsafe runtime matrix cleanup path: %s\n' "$candidate" >&2
    return 1
  fi
  if [ -e "$candidate" ]; then
    rm -rf -- "$candidate"
  fi
  RUNTIME_MATRIX_ROOT=""
}

# ── Wrapper controlled matrix (offline; no OAuth or network) ─────
if [ -x "$SOURCE_WRAPPER" ]; then
  matrix_root=""
  if ! matrix_root=$(mktemp -d "$RUNTIME_TMP_PARENT/codex-runtime-matrix.XXXXXX") \
      || [ -z "$matrix_root" ] || [ ! -d "$matrix_root" ] \
      || ! runtime_matrix_root_is_safe "$matrix_root"; then
    fail "wrapper controlled matrix creates an isolated temporary root"
  else
    RUNTIME_MATRIX_ROOT="$matrix_root"
    trap cleanup_runtime_matrix EXIT
    trap 'exit 130' HUP INT TERM
    pass "wrapper controlled matrix creates an isolated temporary root"

  # Unsupported platform stops before Swift/runtime checks.
  mkdir -p "$matrix_root/linux-stubs"
  ln -s "$(command -v bash)" "$matrix_root/linux-stubs/bash"
  if command -v dirname >/dev/null 2>&1; then
    ln -s "$(command -v dirname)" "$matrix_root/linux-stubs/dirname"
  fi
  printf '#!/bin/sh\nprintf "Linux\\n"\n' > "$matrix_root/linux-stubs/uname"
  chmod +x "$matrix_root/linux-stubs/uname"
  unsupported=$(run_wrapper_capture "$SOURCE_WRAPPER" "$matrix_root/linux-stubs" --check)
  unsupported_status=$(printf '%s\n' "$unsupported" | sed -n '1p')
  unsupported_output=$(printf '%s\n' "$unsupported" | sed '1d')
  if [ "$unsupported_status" -ne 0 ]; then
    pass "unsupported platform exits non-zero"
  else
    fail "unsupported platform exits non-zero"
  fi
  assert_prefix "$unsupported_output" "error=unsupported_platform" "unsupported platform is machine-readable"

  fixture="$matrix_root/path with spaces"
  make_wrapper_fixture "$fixture" '#!/usr/bin/env bash
printf "%s\\n" "$@" > "$CAPTURE_PATH"
exit "${RUNTIME_EXIT:-0}"'
  capture_path="$matrix_root/received-arguments"
  status=0
  PATH="$fixture/stubs" CAPTURE_PATH="$capture_path" RUNTIME_EXIT=37 \
    "$fixture/bin/codex-pro-call" "first" "two words" "--flag=value" >/dev/null 2>&1 || status=$?
  assert_eq "37" "$status" "wrapper preserves runtime exit status"
  if [ -r "$capture_path" ]; then
    received=$(<"$capture_path")
    assert_eq $'first\ntwo words\n--flag=value' "$received" "wrapper preserves ordered arguments exactly once"
  else
    fail "wrapper invokes fixture runtime exactly once (capture missing)"
  fi

  rm -f "$fixture/bin/codex-call"
  missing=$(run_wrapper_capture "$fixture/bin/codex-pro-call" "$fixture/stubs" --check)
  assert_prefix "$(printf '%s\n' "$missing" | sed '1d')" "error=runtime_missing" "missing runtime is machine-readable"

  printf '#!/bin/sh\nexit 0\n' > "$fixture/bin/codex-call"
  chmod 644 "$fixture/bin/codex-call"
  not_executable=$(run_wrapper_capture "$fixture/bin/codex-pro-call" "$fixture/stubs" --check)
  assert_prefix "$(printf '%s\n' "$not_executable" | sed '1d')" "error=runtime_not_executable" "non-executable runtime is machine-readable"

  chmod +x "$fixture/bin/codex-call"
  hash_mismatch=$(run_wrapper_capture "$fixture/bin/codex-pro-call" "$fixture/stubs" --check)
  assert_prefix "$(printf '%s\n' "$hash_mismatch" | sed '1d')" "error=hash_mismatch" "runtime hash mismatch is machine-readable"

  # Darwin with no Swift in the controlled PATH.
  no_swift="$matrix_root/no-swift"
  mkdir -p "$no_swift"
  ln -s "$(command -v bash)" "$no_swift/bash"
  if command -v dirname >/dev/null 2>&1; then
    ln -s "$(command -v dirname)" "$no_swift/dirname"
  fi
  printf '#!/bin/sh\nprintf "Darwin\\n"\n' > "$no_swift/uname"
  chmod +x "$no_swift/uname"
  swift_missing=$(run_wrapper_capture "$SOURCE_WRAPPER" "$no_swift" --check)
  assert_prefix "$(printf '%s\n' "$swift_missing" | sed '1d')" "error=swift_missing" "missing Swift is machine-readable"

    if ! cleanup_runtime_matrix; then
      fail "wrapper controlled matrix cleans only its validated temporary root"
    fi
    trap - EXIT HUP INT TERM
  fi
else
  fail "wrapper controlled matrix runs (source wrapper unavailable)"
fi

# ── macOS offline release smoke ──────────────────────────────────
run_macos_smoke() {
  local executed=0 status=0 output
  if [ "$(uname -s)" != "Darwin" ]; then
    fail "macOS runtime smoke unavailable: error=unsupported_platform"
    return
  fi

  executed=$((executed + 1))
  output=$(swift --version 2>&1) || status=$?
  if [ "$status" -eq 0 ] && [ -n "$output" ]; then
    pass "macOS smoke executes swift --version"
  else
    fail "macOS smoke executes swift --version (exit=$status)"
  fi

  executed=$((executed + 1))
  status=0
  output=$("$REPO_ROOT/bin/codex-pro-call" --check 2>&1) || status=$?
  if [ "$status" -eq 0 ]; then
    assert_prefix "$output" "ok runtime=" "macOS smoke executes generated wrapper --check"
  else
    fail "macOS smoke executes generated wrapper --check (exit=$status output='$output')"
  fi

  executed=$((executed + 1))
  status=0
  output=$("$REPO_ROOT/bin/codex-call" \
    --selftest-error-extract '{"error":{"message":"offline self-test"}}' 2>&1) || status=$?
  if [ "$status" -eq 0 ]; then
    assert_eq "offline self-test" "$output" "macOS smoke executes vendored runtime offline self-test"
  else
    fail "macOS smoke executes vendored runtime offline self-test (exit=$status)"
  fi

  if [ "$executed" -gt 0 ]; then
    pass "macOS runtime smoke did not silently skip all checks"
  else
    fail "macOS runtime smoke executed zero checks"
  fi
}

[ "$TEST_MODE" != "--smoke" ] || run_macos_smoke

report_summary "codex-runtime"
