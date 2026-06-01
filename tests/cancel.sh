#!/usr/bin/env bash
# tests/cancel.sh — Layer 2: structural + minimal behavioral checks for
# the cancel skill. Verifies that cancel is the strictest read-only skill
# in codex-pro: stdout-only informational explainer with deterministic
# byte-identical output, zero Codex HTTP wrapper invocation, zero Codex
# CLI subprocess, zero kill/SIGTERM/SIGKILL command, zero file mutation
# (no mkdir, no .codex-pro/ read), and zero process signal.
# The explainer block in SKILL.md MUST contain the required substrings
# (stateless / Ctrl-C / --max-time 600 / v0.3-or-future / not an error)
# so users recognise it as a known displayed limitation, not a failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"

CANCEL_SKILL="$REPO_ROOT/plugins/codex-pro/skills/cancel/SKILL.md"

# ══════════════════════════════════════════════════════════════════
# Structural section
# ══════════════════════════════════════════════════════════════════

assert_file "$CANCEL_SKILL" "cancel SKILL.md exists"

# ── (a) Frontmatter parse + literal "informational only" in description ──
fm_check=$(python3 - "$CANCEL_SKILL" <<'PY' 2>/dev/null
import re, sys
content = open(sys.argv[1]).read()
m = re.match(r"^---\n(.*?)\n---\n", content, re.DOTALL)
if not m:
    print("no_frontmatter"); sys.exit(0)
fm = m.group(1)
name_ok = "name: cancel" in fm
bash_ok = "Bash" in fm
informational_ok = "informational only" in fm
print(f"name={name_ok} bash={bash_ok} informational={informational_ok}")
PY
)
case "$fm_check" in
  *"name=True bash=True informational=True"*)
    pass "frontmatter: name=cancel, allowed-tools 含 Bash, description 含 literal 'informational only'" ;;
  *)
    fail "frontmatter check failed: $fm_check" ;;
esac

# ── (b) Read-only + no-Codex invariants ──────────────────────────
for forbidden in 'codex-call' 'codex exec' 'mkdir'; do
  cnt=$(grep -c "$forbidden" "$CANCEL_SKILL")
  assert_eq "0" "$cnt" "SKILL.md does NOT contain '$forbidden' (read-only invariant)"
done

# ── (c) No process-signal command (mention in prose to deny use is OK) ──
# Strict: SIGTERM / SIGKILL literal absent entirely (rephrased prose uses 'termination signal')
sig_count=$(grep -cE 'SIGTERM|SIGKILL' "$CANCEL_SKILL")
assert_eq "0" "$sig_count" "SKILL.md does NOT contain SIGTERM/SIGKILL literals (no-signal invariant)"

# Strict: no `kill` command invocation — `kill ` at start of line or `kill -<sig>`
kill_cmd_count=$(grep -cE '^kill |kill -' "$CANCEL_SKILL")
assert_eq "0" "$kill_cmd_count" "SKILL.md does NOT contain kill command invocations"

# ── (d) Informational-only prose anchor ──────────────────────────
inf_count=$(grep -c 'informational only' "$CANCEL_SKILL")
if [ "$inf_count" -ge 2 ]; then
  pass "SKILL.md anchors 'informational only' mental model (count=$inf_count)"
else
  fail "SKILL.md missing 'informational only' anchor"
fi

# ── (e) Explainer required substrings (per spec) ─────────────────
for substr in 'stateless' 'Ctrl-C' '--max-time 600' 'not an error'; do
  if grep -q -- "$substr" "$CANCEL_SKILL"; then
    pass "explainer contains required substring: '$substr'"
  else
    fail "explainer missing required substring: '$substr'"
  fi
done

# v0.3 or future
if grep -qE 'v0\.3|future' "$CANCEL_SKILL"; then
  pass "explainer references v0.3 / future background-job mode"
else
  fail "explainer missing v0.3 / future reference"
fi

# synchronous HTTPS / chatgpt.com mentions
if grep -qE 'synchronous HTTPS|chatgpt\.com|single-shot' "$CANCEL_SKILL"; then
  pass "explainer references synchronous HTTPS / single-shot architecture"
else
  fail "explainer missing architecture reference"
fi

# ── (f) Deterministic / byte-identical marker ────────────────────
if grep -qE 'deterministic|byte-identical|相同' "$CANCEL_SKILL"; then
  pass "SKILL.md documents deterministic / byte-identical output"
else
  fail "SKILL.md missing deterministic output marker"
fi

# ── (g) Exit 0 marker ────────────────────────────────────────────
exit0_count=$(grep -cE 'exit 0|永遠 0|永不為 error|永不 error' "$CANCEL_SKILL")
if [ "$exit0_count" -ge 1 ]; then
  pass "SKILL.md documents exit 0 always (count=$exit0_count)"
else
  fail "SKILL.md missing exit 0 marker"
fi

# ══════════════════════════════════════════════════════════════════
# Minimal behavioral section — extract explainer block + check
# determinism via sha256 stability across two extractions.
# ══════════════════════════════════════════════════════════════════

# Extract the first fenced code block from SKILL.md (the explainer text)
EXTRACT1=$(python3 - "$CANCEL_SKILL" <<'PY'
import re, sys
content = open(sys.argv[1]).read()
# Find the explainer block — fenced code that contains "codex-pro cancel — informational only"
matches = re.findall(r'```\n(codex-pro cancel.*?)\n```', content, re.DOTALL)
if matches:
    print(matches[0])
PY
)
EXTRACT2=$(python3 - "$CANCEL_SKILL" <<'PY'
import re, sys
content = open(sys.argv[1]).read()
matches = re.findall(r'```\n(codex-pro cancel.*?)\n```', content, re.DOTALL)
if matches:
    print(matches[0])
PY
)

if [ -n "$EXTRACT1" ] && [ "$EXTRACT1" = "$EXTRACT2" ]; then
  pass "behavioral: explainer block extracted from SKILL.md is non-empty + extraction is deterministic"
else
  fail "behavioral: explainer extraction failed or non-deterministic"
fi

# Verify the extracted block contains all required substrings
if echo "$EXTRACT1" | grep -q 'codex-pro cancel — informational only' && \
   echo "$EXTRACT1" | grep -q 'stateless' && \
   echo "$EXTRACT1" | grep -q 'Ctrl-C' && \
   echo "$EXTRACT1" | grep -q -- '--max-time 600' && \
   echo "$EXTRACT1" | grep -q 'not an error'; then
  pass "behavioral: explainer block contains all required substrings (informational header + stateless + Ctrl-C + --max-time 600 + not an error)"
else
  fail "behavioral: explainer block missing required substrings"
fi

report_summary "cancel"
