#!/usr/bin/env bash
# tests/run.sh — codex-pro test dispatcher (Layer 1 + Layer 2 only).
# Runs Layer 1 (static.sh) and Layer 2 (per-skill behavioral) sequentially,
# aggregates pass/fail counts, exits non-zero on any failure.
#
# Layer 3 e2e (`tests/e2e.sh`) is OPT-IN and NOT dispatched here — it triggers
# real `claude --print --plugin-dir` sessions, costs ~10 codex-call quota +
# ~500k Claude API tokens for the full 10-combination matrix, and is subject
# to Anthropic API server-side rate-limit flakiness. Run Layer 3 per release
# (release gate), not per commit. See tests/e2e-checklist.md for the
# automated invocation and manual UI flow.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Test-only dispatcher seam. Production runs leave both variables unset and
# continue to execute the canonical layer list from this directory. Regression
# tests may provide an isolated fixture directory + a space-delimited list so
# they can exercise aggregation without recursively launching the full suite.
FIXTURE_LAYER_DIR="${CODEX_PRO_RUN_FIXTURE_DIR:-}"
FIXTURE_LAYER_LIST="${CODEX_PRO_RUN_FIXTURE_LAYERS:-}"
if [ -n "$FIXTURE_LAYER_DIR" ] || [ -n "$FIXTURE_LAYER_LIST" ]; then
  if [ -z "$FIXTURE_LAYER_DIR" ] || [ -z "$FIXTURE_LAYER_LIST" ]; then
    echo "FATAL: CODEX_PRO_RUN_FIXTURE_DIR and CODEX_PRO_RUN_FIXTURE_LAYERS must be set together" >&2
    exit 2
  fi
  if ! FIXTURE_LAYER_DIR="$(cd "$FIXTURE_LAYER_DIR" 2>/dev/null && pwd -P)" \
      || [ -z "$FIXTURE_LAYER_DIR" ] || [ "$FIXTURE_LAYER_DIR" = "/" ]; then
    echo "FATAL: fixture layer directory must resolve to a non-root directory" >&2
    exit 2
  fi
  read -r -a RUN_LAYERS <<< "$FIXTURE_LAYER_LIST"
  if [ "${#RUN_LAYERS[@]}" -eq 0 ]; then
    echo "FATAL: CODEX_PRO_RUN_FIXTURE_LAYERS must name at least one fixture layer" >&2
    exit 2
  fi
  for fixture_layer in "${RUN_LAYERS[@]}"; do
    case "$fixture_layer" in
      ''|*[!A-Za-z0-9_-]*)
        echo "FATAL: unsafe fixture layer name: $fixture_layer" >&2
        exit 2 ;;
    esac
  done
  LAYER_DIR="$FIXTURE_LAYER_DIR"
else
  LAYER_DIR="$SCRIPT_DIR"
  RUN_LAYERS=(
    static
    run-dispatcher
    codex-plugin
    codex-skills-parity
    codex-runtime
    setup
    batch
    review
    rescue
    adversarial-review
    status
    result
    cancel
    config
    visual-xval
  )
fi

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
  local layer_path="$LAYER_DIR/${layer}.sh"
  if [ ! -r "$layer_path" ]; then
    printf '%bFATAL%b: layer script not found: %s\n' "$C_BAD" "$C_RESET" "$layer_path" >&2
    LAYERS_FAIL+=1
    FAILED_LAYERS+=("$layer (missing)")
    return
  fi
  printf '\n%b════ Layer: %s%b\n' "$C_HEAD" "$layer" "$C_RESET"
  local out exit_code=0
  out=$(bash "$layer_path" 2>&1) || exit_code=$?
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
    if [ "$f" -eq 0 ] && [ "$exit_code" -eq 0 ]; then
      LAYERS_PASS+=1
    else
      LAYERS_FAIL+=1
      if [ "$exit_code" -ne 0 ]; then
        FAILED_LAYERS+=("$layer (exit=$exit_code)")
      else
        FAILED_LAYERS+=("$layer")
      fi
    fi
  else
    # Every assertion layer owns a parseable summary contract. Fail closed when
    # it disappears: an empty/truncated test script can otherwise exit 0 and
    # silently turn a missing release gate into a passing layer.
    LAYERS_FAIL+=1
    FAILED_LAYERS+=("$layer (no summary; exit=$exit_code)")
  fi
}

# ── Execute layers ────────────────────────────────────────────────
for layer in "${RUN_LAYERS[@]}"; do
  run_layer "$layer"
done

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
