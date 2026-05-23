#!/usr/bin/env bash
# tests/lib/isolate.sh — shared isolation wrappers for codex-pro test layers
# All wrappers run their payload inside a subshell so environment overrides
# do not leak back to the caller.

with_empty_home() {
  # with_empty_home <cmd> [args...] -- runs cmd with HOME=/nonexistent
  ( HOME=/nonexistent "$@" )
}

with_path_stripped() {
  # with_path_stripped <cmd> [args...] -- runs cmd with a minimal PATH
  # that excludes any plugin-managed bin/ directory (e.g., codex-call).
  ( PATH=/usr/bin:/bin "$@" )
}

with_fake_plugin_root() {
  # with_fake_plugin_root <body> -- creates a temp dir, exports
  # CLAUDE_PLUGIN_ROOT pointing at it, evals <body> inside a subshell,
  # then removes the temp dir on exit. <body> is a single string passed
  # to eval; use it for short one-liners or callable function names.
  local body="$1"
  ( set -e
    local tmp
    tmp=$(mktemp -d 2>/dev/null) || { echo "mktemp failed" >&2; return 1; }
    trap 'rm -rf "$tmp"' EXIT
    mkdir -p "$tmp/.claude-plugin"
    export CLAUDE_PLUGIN_ROOT="$tmp"
    eval "$body"
  )
}
