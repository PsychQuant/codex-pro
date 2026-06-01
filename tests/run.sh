#!/usr/bin/env bash
# tests/run.sh — codex-pro test dispatcher.
# Runs Layer 1 (static.sh) and Layer 2 (setup.sh + batch.sh) sequentially,
# aggregates pass/fail counts from each layer, and exits non-zero if any
# layer reported a failure. Layer 3 is the manual e2e checklist
# (tests/e2e-checklist.md) and is NOT executed here.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Prerequisites ─────────────────────────────────────────────────
if ! command -v python3 >/dev/null 2>&1; then
  echo "FATAL: python3 not on PATH (install Xcode Command Line Tools)" >&2
  exit 2
fi

if [ -t 1 ]; then
  C_HEAD='\033[1;36m'
  C_OK='\033[0;32m'
  C_BAD='\033[0;31m'
  C_RESET='\033[0m'
else
  C_HEAD='' C_OK='' C_BAD='' C_RESET=''
fi

# ── Layer runner ──────────────────────────────────────────────────
declare -i TOTAL_PASS=0 TOTAL_FAIL=0
declare -i LAYERS_PASS=0 LAYERS_FAIL=0
declare -a FAILED_LAYERS=()

run_layer() {
  local layer="$1"
  local layer_path="$SCRIPT_DIR/${layer}.sh"
  if [ ! -r "$layer_path" ]; then
    printf '%bFATAL%b: layer script not found: %s\n' "$C_BAD" "$C_RESET" "$layer_path" >&2
    LAYERS_FAIL+=1
    FAILED_LAYERS+=("$layer (missing)")
    return
  fi
  printf '\n%b════ Layer: %s%b\n' "$C_HEAD" "$layer" "$C_RESET"
  local out
  out=$(bash "$layer_path" 2>&1) || true
  local exit_code=$?
  printf '%s\n' "$out"
  # Parse "summary: N pass / N fail / N total" (strip ANSI colour codes first)
  local summary_line
  summary_line=$(printf '%s\n' "$out" | sed 's/\x1b\[[0-9;]*m//g' | grep -E 'summary: [0-9]+ pass / [0-9]+ fail' | tail -1)
  if [ -n "$summary_line" ]; then
    local p f
    p=$(printf '%s\n' "$summary_line" | sed -E 's/.*summary: ([0-9]+) pass.*/\1/')
    f=$(printf '%s\n' "$summary_line" | sed -E 's/.*pass \/ ([0-9]+) fail.*/\1/')
    TOTAL_PASS=$((TOTAL_PASS + p))
    TOTAL_FAIL=$((TOTAL_FAIL + f))
    if [ "$f" -eq 0 ]; then
      LAYERS_PASS+=1
    else
      LAYERS_FAIL+=1
      FAILED_LAYERS+=("$layer")
    fi
  else
    # No summary parsed — fall back to exit code (defensive)
    if [ "$exit_code" -eq 0 ]; then
      LAYERS_PASS+=1
    else
      LAYERS_FAIL+=1
      FAILED_LAYERS+=("$layer (no summary; exit=$exit_code)")
    fi
  fi
}

# ── Execute layers ────────────────────────────────────────────────
run_layer static
run_layer setup
run_layer batch
run_layer review
run_layer rescue

# ── Aggregate summary ─────────────────────────────────────────────
printf '\n%b════ run.sh aggregate summary%b\n' "$C_HEAD" "$C_RESET"
printf '  Assertions: %d pass / %d fail / %d total\n' "$TOTAL_PASS" "$TOTAL_FAIL" "$((TOTAL_PASS + TOTAL_FAIL))"
printf '  Layers:     %d pass / %d fail\n' "$LAYERS_PASS" "$LAYERS_FAIL"

if [ "$LAYERS_FAIL" -eq 0 ] && [ "$TOTAL_FAIL" -eq 0 ]; then
  printf '\n%b✓ All layers passed.%b Manual e2e checklist: tests/e2e-checklist.md\n' "$C_OK" "$C_RESET"
  exit 0
else
  printf '\n%b✗ Failures in layers:%b %s\n' "$C_BAD" "$C_RESET" "${FAILED_LAYERS[*]:-none}"
  exit 1
fi
