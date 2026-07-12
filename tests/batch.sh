#!/usr/bin/env bash
# tests/batch.sh — Layer 2: structural & semantic checks for the batch skill.
# Verifies the explicit-exception markers in SKILL.md and the parallel
# orchestration markers inside the bundled script-template.sh, plus the
# byte-identical sha256 (independent of the static layer check).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"

BATCH_SKILL="$REPO_ROOT/plugins/codex-pro/skills/codex-batch/SKILL.md"
BATCH_TEMPLATE="$REPO_ROOT/plugins/codex-pro/skills/codex-batch/references/script-template.sh"
BATCH_TEMPLATE_SHA256="f545501897697c9d914d77cda2f19d83a58863904e7fc8fc4055443fb1982b78"

assert_file "$BATCH_SKILL" "batch SKILL.md exists"
assert_file "$BATCH_TEMPLATE" "batch script-template.sh exists"

# ── SKILL.md explicit-exception markers ──────────────────────────
ex_count=$(grep -c -i "exception" "$BATCH_SKILL" 2>/dev/null || true)
con_count=$(grep -c -i "constraint" "$BATCH_SKILL" 2>/dev/null || true)
[ -z "$ex_count" ] && ex_count=0
[ -z "$con_count" ] && con_count=0
if [ "$ex_count" -ge 1 ]; then
  pass "SKILL.md contains 'exception' (count=$ex_count)"
else
  fail "SKILL.md missing 'exception' marker"
fi
if [ "$con_count" -ge 1 ]; then
  pass "SKILL.md contains 'constraint' (count=$con_count)"
else
  fail "SKILL.md missing 'constraint' marker"
fi
if grep -q "Design constraint #1" "$BATCH_SKILL"; then
  pass "SKILL.md explicitly names 'Design constraint #1'"
else
  fail "SKILL.md does not name 'Design constraint #1'"
fi

# ── script-template.sh: codex invocation ─────────────────────────
# Accept either the literal `codex exec` or the variable expansion
# `"$CODEX" exec` — both are semantically equivalent to "spawn codex
# exec" per the upstream codex-batch design.
if grep -E -q '("\$CODEX" exec|codex exec)' "$BATCH_TEMPLATE"; then
  pass "script-template invokes codex exec (literal or via \$CODEX)"
else
  fail "script-template missing codex exec invocation"
fi

if grep -q -- '--full-auto' "$BATCH_TEMPLATE"; then
  pass "script-template uses --full-auto flag"
else
  fail "script-template missing --full-auto flag"
fi

# ── script-template.sh: parallel orchestration markers ──────────
# Background job spawning ('&' at end of a command line)
if grep -E -q '[^&]& *$' "$BATCH_TEMPLATE"; then
  pass "script-template contains background job marker '&'"
else
  fail "script-template missing background job marker '&'"
fi

# wait — synchronisation
if grep -E -q '^\s*wait\s*$' "$BATCH_TEMPLATE"; then
  pass "script-template contains 'wait' synchronisation"
else
  fail "script-template missing 'wait' synchronisation"
fi

# ── Byte-identical sha256 (independent verification) ────────────
assert_sha256 "$BATCH_TEMPLATE" "$BATCH_TEMPLATE_SHA256" "batch template sha256 (independent of static layer)"

report_summary "batch"
