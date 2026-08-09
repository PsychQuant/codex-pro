#!/usr/bin/env bash
# tests/run-dispatcher.sh — regression for dispatcher exit-status handling.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DISPATCHER="$SCRIPT_DIR/run.sh"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"

if ! DISPATCHER_TMP_PARENT=$(cd "${TMPDIR:-/tmp}" 2>/dev/null && pwd -P) \
    || [ -z "$DISPATCHER_TMP_PARENT" ] || [ "$DISPATCHER_TMP_PARENT" = "/" ]; then
  echo "FATAL: dispatcher regression requires a non-root temporary parent" >&2
  exit 2
fi
DISPATCHER_TEST_ROOT=""

dispatcher_test_root_is_safe() {
  local candidate="$1" parent base
  [ -n "$candidate" ] || return 1
  parent=$(cd "$(dirname "$candidate")" 2>/dev/null && pwd -P) || return 1
  base=$(basename "$candidate")
  [ "$parent" = "$DISPATCHER_TMP_PARENT" ] || return 1
  case "$base" in
    codex-run-dispatcher-tests.*) return 0 ;;
    *) return 1 ;;
  esac
}

cleanup_dispatcher_test_root() {
  local candidate="${DISPATCHER_TEST_ROOT:-}"
  [ -n "$candidate" ] || return 0
  if ! dispatcher_test_root_is_safe "$candidate"; then
    printf 'FATAL: refusing unsafe dispatcher fixture cleanup path: %s\n' "$candidate" >&2
    return 1
  fi
  if [ -e "$candidate" ]; then
    rm -rf -- "$candidate"
  fi
  DISPATCHER_TEST_ROOT=""
}

if ! DISPATCHER_TEST_ROOT=$(mktemp -d \
    "$DISPATCHER_TMP_PARENT/codex-run-dispatcher-tests.XXXXXX") \
    || [ -z "$DISPATCHER_TEST_ROOT" ] || [ ! -d "$DISPATCHER_TEST_ROOT" ] \
    || ! dispatcher_test_root_is_safe "$DISPATCHER_TEST_ROOT"; then
  echo "FATAL: could not create a safe dispatcher fixture root" >&2
  exit 2
fi
trap cleanup_dispatcher_test_root EXIT
trap 'exit 130' HUP INT TERM

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'echo "fixture fatal: no summary" >&2' \
  'exit 17' \
  > "$DISPATCHER_TEST_ROOT/fatal-no-summary.sh"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "fixture summary: 1 pass / 0 fail / 1 total\n"' \
  'exit 23' \
  > "$DISPATCHER_TEST_ROOT/passing-summary-nonzero.sh"

run_fixture_case() {
  local layer="$1" expected_exit="$2" label="$3" status=0 output
  output=$(CODEX_PRO_RUN_FIXTURE_DIR="$DISPATCHER_TEST_ROOT" \
    CODEX_PRO_RUN_FIXTURE_LAYERS="$layer" \
    bash "$DISPATCHER" 2>&1) || status=$?

  if [ "$status" -ne 0 ]; then
    pass "$label makes dispatcher aggregate exit non-zero"
  else
    fail "$label makes dispatcher aggregate exit non-zero (actual=0; false-green)"
  fi
  assert_contains "$output" "exit=$expected_exit" \
    "$label preserves the original layer exit status"
  assert_contains "$output" "Layers:     0 pass / 1 fail" \
    "$label counts the fixture as a failed layer"
}

run_fixture_case fatal-no-summary 17 "fatal layer without summary"
run_fixture_case passing-summary-nonzero 23 "zero-failure summary followed by non-zero exit"

if ! cleanup_dispatcher_test_root; then
  fail "dispatcher regression cleans only its validated temporary root"
fi
trap - EXIT HUP INT TERM

report_summary "run-dispatcher"
exit $?
