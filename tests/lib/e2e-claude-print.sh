#!/usr/bin/env bash
# tests/lib/e2e-claude-print.sh — Claude --print invocation with rate-limit retry.
#
# Exports: invoke_skill_via_claude_print(fixture_dir, skill_name)
#   → sets globals:
#       INVOKE_EXIT     — exit code from `claude --print` (0 = success)
#       INVOKE_OUTPUT   — captured stdout+stderr
#
# Retry policy (D4): up to 3 attempts; only retry on Anthropic API server-side
# throttle (substring "Server is temporarily limiting requests"); exponential
# backoff 30s / 60s / 120s. Codex-call internal fail-fast (rate_limit /
# oauth_invalid / timeout / target_invalid) is NOT retried — it produces a
# valid result file and the e2e treats it as scenario-specific.

if [ -n "${E2E_CLAUDE_PRINT_LOADED:-}" ]; then
  return 0
fi
E2E_CLAUDE_PRINT_LOADED=1

# Derive codex-pro plugin path from this script's location (D2: not hardcoded).
# This file lives at tests/lib/e2e-claude-print.sh; plugin lives at
# plugins/codex-pro/ relative to the repo root.
_e2e_derive_plugin_path() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "$script_dir/../../plugins/codex-pro" && pwd
}

invoke_skill_via_claude_print() {
  local fixture_dir="$1"
  local skill_name="$2"
  local plugin_path
  plugin_path="$(_e2e_derive_plugin_path)"

  if [ ! -d "$plugin_path" ]; then
    echo "ERROR: codex-pro plugin path not found: $plugin_path" >&2
    INVOKE_EXIT=3
    INVOKE_OUTPUT=""
    return 3
  fi
  if ! command -v claude >/dev/null 2>&1; then
    echo "ERROR: 'claude' CLI not in PATH" >&2
    INVOKE_EXIT=3
    INVOKE_OUTPUT=""
    return 3
  fi

  local attempt
  for attempt in 1 2 3; do
    INVOKE_OUTPUT=$(cd "$fixture_dir" && timeout 600 claude --print \
      --plugin-dir "$plugin_path" \
      "/codex-pro:codex-${skill_name}" 2>&1)   # rename-aware (#5): skill trigger is codex-<name>; result-file prefix stays bare <name>
    INVOKE_EXIT=$?

    # Only retry on Anthropic API server-side throttle. Other failures
    # (codex-call rate_limit, oauth_invalid, timeout, target_invalid) are
    # SKILL-internal fail-fast and are valid e2e results.
    if echo "$INVOKE_OUTPUT" | grep -q 'Server is temporarily limiting requests'; then
      if [ "$attempt" -lt 3 ]; then
        local backoff=$((30 * (1 << (attempt - 1))))   # 30s, 60s, 120s
        echo "  [rate limit] attempt $attempt — sleeping ${backoff}s before retry" >&2
        sleep "$backoff"
        continue
      else
        echo "  [rate limit] all 3 attempts throttled" >&2
        INVOKE_EXIT=4
        return 4
      fi
    fi
    # Either success or a non-throttle failure — exit the loop
    break
  done
  return "$INVOKE_EXIT"
}
