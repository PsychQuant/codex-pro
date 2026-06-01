#!/usr/bin/env bash
# tests/lib/assert.sh — shared assertion helpers for codex-pro test layers
# Source this file; it exposes assert_* / pass / fail / report_summary
# and maintains the global PASS_COUNT / FAIL_COUNT counters.

PASS_COUNT=${PASS_COUNT:-0}
FAIL_COUNT=${FAIL_COUNT:-0}

# Colours (skipped if stdout is not a tty)
if [ -t 1 ]; then
  C_PASS='\033[0;32m'
  C_FAIL='\033[0;31m'
  C_DIM='\033[2m'
  C_RESET='\033[0m'
else
  C_PASS='' C_FAIL='' C_DIM='' C_RESET=''
fi

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf '%b  ✓%b %s\n' "$C_PASS" "$C_RESET" "${1:-pass}"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf '%b  ✗%b %s\n' "$C_FAIL" "$C_RESET" "${1:-fail}"
}

assert_eq() {
  # assert_eq <expected> <actual> <msg>
  local expected="$1" actual="$2" msg="${3:-assert_eq}"
  if [ "$expected" = "$actual" ]; then
    pass "$msg"
  else
    fail "$msg (expected='$expected', actual='$actual')"
  fi
}

assert_contains() {
  # assert_contains <haystack> <needle> <msg>
  local haystack="$1" needle="$2" msg="${3:-assert_contains}"
  case "$haystack" in
    *"$needle"*) pass "$msg" ;;
    *) fail "$msg (haystack did not contain '$needle')" ;;
  esac
}

assert_file() {
  # assert_file <path> <msg>
  local path="$1" msg="${2:-assert_file $1}"
  if [ -r "$path" ]; then
    pass "$msg"
  else
    fail "$msg (not readable: '$path')"
  fi
}

assert_no_file() {
  # assert_no_file <path> <msg>
  local path="$1" msg="${2:-assert_no_file $1}"
  if [ ! -e "$path" ]; then
    pass "$msg"
  else
    fail "$msg (unexpectedly exists: '$path')"
  fi
}

assert_sha256() {
  # assert_sha256 <path> <expected_hex> <msg>
  local path="$1" expected="$2" msg="${3:-assert_sha256 $1}"
  if [ ! -r "$path" ]; then
    fail "$msg (file not readable: '$path')"
    return
  fi
  local actual
  actual=$(shasum -a 256 "$path" | awk '{print $1}')
  if [ "$actual" = "$expected" ]; then
    pass "$msg"
  else
    fail "$msg (expected=$expected actual=$actual)"
  fi
}

assert_exit() {
  # assert_exit <expected_code> <cmd...> -- runs cmd in a subshell, checks exit
  local expected="$1"
  shift
  local msg="assert_exit $expected: $*"
  local actual=0
  ( "$@" ) >/dev/null 2>&1 || actual=$?
  if [ "$actual" = "$expected" ]; then
    pass "$msg"
  else
    fail "$msg (expected=$expected actual=$actual)"
  fi
}

assert_git_fixture() {
  # assert_git_fixture <dir>
  # Initialize a deterministic fixture git repo at <dir> for behavioral tests.
  # Bakes init.defaultBranch + user identity so tests don't pick up maintainer
  # machine's global git config (cross-machine determinism).
  local dir="$1"
  git -C "$dir" init -q
  git -C "$dir" config init.defaultBranch main
  git -C "$dir" config user.email "test@codex-pro.local"
  git -C "$dir" config user.name "codex-pro test"
}

report_summary() {
  # report_summary <label?>
  local label="${1:-tests}"
  local total=$((PASS_COUNT + FAIL_COUNT))
  printf '\n%b────%b %s summary: %d pass / %d fail / %d total\n' \
    "$C_DIM" "$C_RESET" "$label" "$PASS_COUNT" "$FAIL_COUNT" "$total"
  [ "$FAIL_COUNT" -eq 0 ]
}
