#!/usr/bin/env bash
# tests/review.sh — Layer 2: structural & semantic checks for the review skill.
# Verifies frontmatter, codex-call HTTPS-direct invocation, hard timeout flag,
# fail-fast circuit-breaker discipline, and result-file structure contract.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"

REVIEW_SKILL="$REPO_ROOT/plugins/codex-pro/skills/review/SKILL.md"

assert_file "$REVIEW_SKILL" "review SKILL.md exists"

# ── (a) Frontmatter parse ────────────────────────────────────────
fm_check=$(python3 - "$REVIEW_SKILL" <<'PY' 2>/dev/null
import re, sys
content = open(sys.argv[1]).read()
m = re.match(r"^---\n(.*?)\n---\n", content, re.DOTALL)
if not m:
    print("no_frontmatter"); sys.exit(0)
fm = m.group(1)
name_ok = "name: review" in fm
bash_ok = "Bash" in fm
read_ok = "Read" in fm
print(f"name={name_ok} bash={bash_ok} read={read_ok}")
PY
)
case "$fm_check" in
  *"name=True bash=True read=True"*)
    pass "frontmatter: name=review, allowed-tools 含 Bash + Read" ;;
  *)
    fail "frontmatter check failed: $fm_check" ;;
esac

# ── (b) codex-call invocation (default rule, NOT exception) ──────
cc_count=$(grep -c "codex-call" "$REVIEW_SKILL")
if [ "$cc_count" -ge 1 ]; then
  pass "SKILL.md invokes codex-call (count=$cc_count)"
else
  fail "SKILL.md missing codex-call invocation"
fi

# ── (c) MUST NOT contain codex exec (subprocess form is batch exception) ──
ce_count=$(grep -c "codex exec" "$REVIEW_SKILL")
assert_eq "0" "$ce_count" "SKILL.md does NOT contain 'codex exec' (Design constraint #1 strict adherence)"

# ── (d) Hard timeout flag ────────────────────────────────────────
if grep -q -- '--max-time 600' "$REVIEW_SKILL"; then
  pass "SKILL.md documents --max-time 600 hard timeout"
else
  fail "SKILL.md missing --max-time 600 flag"
fi

# ── (e) Fail-fast three error classes ────────────────────────────
for err in rate_limit oauth_invalid timeout; do
  cnt=$(grep -c "$err" "$REVIEW_SKILL")
  if [ "$cnt" -ge 1 ]; then
    pass "fail-fast error class '$err' present (count=$cnt)"
  else
    fail "fail-fast error class '$err' missing"
  fi
done

# fail-fast / no-retry discipline marker
if grep -qE '不 retry|fail-fast|不會自動 retry|no retry' "$REVIEW_SKILL"; then
  pass "SKILL.md states no-retry / fail-fast discipline"
else
  fail "SKILL.md missing no-retry / fail-fast marker"
fi

# ── (f) Result file structure contract ───────────────────────────
for marker in '.codex-pro/review-' '## Summary' '## Findings' '### Finding'; do
  if grep -q -- "$marker" "$REVIEW_SKILL"; then
    pass "result file marker present: $marker"
  else
    fail "result file marker missing: $marker"
  fi
done

# 6 frontmatter field names must each appear (in body documentation)
for field in target model effort timestamp findings_count error; do
  cnt=$(grep -c "$field" "$REVIEW_SKILL")
  if [ "$cnt" -ge 1 ]; then
    pass "frontmatter field '$field' documented (count=$cnt)"
  else
    fail "frontmatter field '$field' missing"
  fi
done

# ── (g) v0.2 markers — untracked-by-default + binary detection + size cap +
#       empty-repo fallback + target_invalid (per diff-untracked-fix-all-producers)
if grep -q 'v0.2 — untracked-by-default' "$REVIEW_SKILL"; then
  pass "SKILL.md frontmatter contains 'v0.2 — untracked-by-default' marker"
else
  fail "SKILL.md missing 'v0.2 — untracked-by-default' marker"
fi
forbidden_count=$(grep -c -- '--legacy-tracked-only' "$REVIEW_SKILL")
assert_eq "0" "$forbidden_count" "SKILL.md does NOT contain '--legacy-tracked-only' (no opt-out flag, per D2)"
for marker in 'git diff HEAD' 'git ls-files --others --exclude-standard' 'git check-attr binary' '64KB' '512KB' 'truncated at 64KB' 'aggregate size cap' 'pre-first-commit' 'unknown revision' 'Untracked binaries omitted' 'target_invalid'; do
  if grep -q -- "$marker" "$REVIEW_SKILL"; then
    pass "v0.2 marker present: $marker"
  else
    fail "v0.2 marker missing: $marker"
  fi
done

# ══════════════════════════════════════════════════════════════════
# Behavioral runtime section — mktemp + assert_git_fixture fixture
# (D8: 5 scenario covering mixed / binary / oversize / empty-repo /
# all-empty target_invalid post-filter)
# ══════════════════════════════════════════════════════════════════

# Equivalent of SKILL.md Step 1 collection logic, isolated for test.
# Mirrors the contract in plugins/codex-pro/skills/review/SKILL.md.
collect_review_target() {
  # Outputs target body to stdout, error class to file specified by ERROR_FILE
  local per_file_cap=$((64 * 1024))
  local agg_cap=$((512 * 1024))
  local err_file="${ERROR_FILE:-/dev/null}"
  : > "$err_file"

  local diff_out
  diff_out=$(git diff HEAD 2>&1)
  local diff_rc=$?
  local target_marker="diff"
  local diff_body=""
  if [ $diff_rc -eq 128 ] && echo "$diff_out" | grep -qE "unknown revision|ambiguous argument 'HEAD'"; then
    target_marker="diff (pre-first-commit)"
    diff_body=$( { git diff --cached 2>/dev/null; git diff 2>/dev/null; } )
  else
    diff_body="$diff_out"
  fi

  local untracked
  untracked=$(git ls-files --others --exclude-standard 2>/dev/null)

  local body_parts="$diff_body"
  local binary_paths=""
  local omitted_paths=""
  local running=0
  local had_meaningful_content=0
  # diff_body counts as meaningful if it has any non-whitespace
  if [ -n "$(printf '%s' "$diff_body" | LC_ALL=C tr -d '[:space:]')" ]; then
    had_meaningful_content=1
  fi

  local f
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ ! -f "$f" ] && continue
    local binary=0
    if git check-attr binary "$f" 2>/dev/null | grep -q 'binary: set'; then
      binary=1
    elif python3 -c "import sys; sys.exit(0 if b'\x00' in open(sys.argv[1],'rb').read(8192) else 1)" "$f" 2>/dev/null; then
      binary=1
    fi
    if [ "$binary" -eq 1 ]; then
      binary_paths="${binary_paths}${f}"$'\n'
      continue
    fi
    local fsize
    fsize=$(wc -c < "$f" | tr -d ' ')
    if [ $((running + fsize)) -gt "$agg_cap" ] && [ $((running + per_file_cap)) -gt "$agg_cap" ]; then
      omitted_paths="${omitted_paths}${f}"$'\n'
      continue
    fi
    local content
    if [ "$fsize" -gt "$per_file_cap" ]; then
      content=$(head -c $per_file_cap "$f")
      body_parts="${body_parts}"$'\n'"### Untracked file: ${f}"$'\n'"${content}"$'\n'"… [truncated at 64KB of ${fsize} bytes]"$'\n'
      running=$((running + per_file_cap))
      [ -n "$(printf '%s' "$content" | LC_ALL=C tr -d '[:space:]')" ] && had_meaningful_content=1
    else
      content=$(cat "$f")
      body_parts="${body_parts}"$'\n'"### Untracked file: ${f}"$'\n'"${content}"$'\n'
      running=$((running + fsize))
      [ -n "$(printf '%s' "$content" | LC_ALL=C tr -d '[:space:]')" ] && had_meaningful_content=1
    fi
  done <<< "$untracked"

  if [ -n "$binary_paths" ]; then
    body_parts="${body_parts}"$'\n'"### Untracked binaries omitted"$'\n'"${binary_paths}"
  fi
  if [ -n "$omitted_paths" ]; then
    body_parts="${body_parts}"$'\n'"### Untracked files omitted (aggregate size cap)"$'\n'"${omitted_paths}"
  fi

  # Pre-flight target_invalid: zero MEANINGFUL content (binary path lists +
  # omitted path lists are metadata, not reviewable content)
  if [ "$had_meaningful_content" -eq 0 ]; then
    printf 'target_invalid' > "$err_file"
    echo "Error: target body empty after binary and size filtering — verify there are real changes to review (uncommitted tracked changes, or untracked text files within 64KB each)." >&2
    return 2
  fi
  printf 'target=%s\n%s' "$target_marker" "$body_parts"
  return 0
}

# ── Fixture writer ───────────────────────────────────────────────
write_fixture_mixed() {
  local dir="$1"
  assert_git_fixture "$dir"
  ( cd "$dir" && echo "initial line" > tracked.txt && git add tracked.txt && git -c gc.auto=0 commit -q -m initial )
  ( cd "$dir" && echo "modified line" >> tracked.txt )
  ( cd "$dir" && echo "fresh content" > untracked_normal.txt )
}

write_fixture_binary() {
  local dir="$1"
  assert_git_fixture "$dir"
  ( cd "$dir" && echo "text content" > untracked_text.txt )
  ( cd "$dir" && printf '\x89PNG\r\n\x1a\n\x00\x00binary data' > untracked_image.png )
}

write_fixture_oversize() {
  local dir="$1"
  assert_git_fixture "$dir"
  ( cd "$dir" && python3 -c "open('big.log','w').write('a' * 100000)" )
}

write_fixture_empty_repo() {
  local dir="$1"
  assert_git_fixture "$dir"
  ( cd "$dir" && echo "fresh untracked" > only_file.txt )
  # No commits at all — pre-first-commit state
}

write_fixture_all_empty() {
  local dir="$1"
  assert_git_fixture "$dir"
  # Only an untracked binary that fails binary detect
  ( cd "$dir" && printf '\x00\x00\x00\x00binary' > only_binary.bin )
}

# ── (h) Behavioral scenario: mixed (modified tracked + untracked text) ──
TMP=$(mktemp -d)
write_fixture_mixed "$TMP"
ERROR_FILE="$TMP/err"
OUT=$(cd "$TMP" && collect_review_target)
RC=$?
if [ "$RC" -eq 0 ]; then
  pass "behavioral mixed: collect exit 0"
else
  fail "behavioral mixed: collect exit non-zero (rc=$RC)"
fi
if echo "$OUT" | grep -q '+modified line'; then
  pass "behavioral mixed: tracked diff present in target body"
else
  fail "behavioral mixed: tracked diff missing"
fi
if echo "$OUT" | grep -qE '### Untracked file: \.?/?untracked_normal\.txt'; then
  pass "behavioral mixed: untracked file path heading present"
else
  fail "behavioral mixed: untracked path heading missing"
fi
if echo "$OUT" | grep -q 'fresh content'; then
  pass "behavioral mixed: untracked file content injected"
else
  fail "behavioral mixed: untracked content missing"
fi
rm -rf "$TMP"

# ── (i) Behavioral scenario: binary (.png with NUL bytes) ──
TMP=$(mktemp -d)
write_fixture_binary "$TMP"
ERROR_FILE="$TMP/err"
OUT=$(cd "$TMP" && collect_review_target)
RC=$?
[ "$RC" -eq 0 ] && pass "behavioral binary: collect exit 0" || fail "behavioral binary: exit non-zero"
if echo "$OUT" | grep -q '### Untracked binaries omitted'; then
  pass "behavioral binary: 'Untracked binaries omitted' section present"
else
  fail "behavioral binary: omit section missing"
fi
if echo "$OUT" | grep -q 'untracked_image.png'; then
  pass "behavioral binary: png path listed"
else
  fail "behavioral binary: png path missing"
fi
# Binary content (literal "binary data") must NOT appear in body
if echo "$OUT" | grep -q 'binary data'; then
  fail "behavioral binary: binary content injected (should be path-only)"
else
  pass "behavioral binary: content NOT injected (path-only)"
fi
rm -rf "$TMP"

# ── (j) Behavioral scenario: oversize (>64KB) ──
TMP=$(mktemp -d)
write_fixture_oversize "$TMP"
ERROR_FILE="$TMP/err"
OUT=$(cd "$TMP" && collect_review_target)
RC=$?
[ "$RC" -eq 0 ] && pass "behavioral oversize: collect exit 0" || fail "behavioral oversize: exit non-zero"
if echo "$OUT" | grep -q 'truncated at 64KB of 100000 bytes'; then
  pass "behavioral oversize: truncation marker with byte count present"
else
  fail "behavioral oversize: truncation marker missing"
fi
rm -rf "$TMP"

# ── (k) Behavioral scenario: empty-repo (no HEAD) ──
TMP=$(mktemp -d)
write_fixture_empty_repo "$TMP"
ERROR_FILE="$TMP/err"
OUT=$(cd "$TMP" && collect_review_target)
RC=$?
[ "$RC" -eq 0 ] && pass "behavioral empty-repo: collect exit 0" || fail "behavioral empty-repo: exit non-zero (rc=$RC)"
if echo "$OUT" | grep -q 'target=diff (pre-first-commit)'; then
  pass "behavioral empty-repo: target marker 'diff (pre-first-commit)' present"
else
  fail "behavioral empty-repo: target marker missing"
fi
if echo "$OUT" | grep -q 'fresh untracked'; then
  pass "behavioral empty-repo: untracked content collected via fallback path"
else
  fail "behavioral empty-repo: untracked content missing in fallback"
fi
rm -rf "$TMP"

# ── (l) Behavioral scenario: all-empty (binary-only repo → target_invalid) ──
TMP=$(mktemp -d)
write_fixture_all_empty "$TMP"
ERROR_FILE="$TMP/err"
OUT=$(cd "$TMP" && collect_review_target 2>/dev/null)
RC=$?
if [ "$RC" -eq 2 ]; then
  pass "behavioral all-empty: collect exit 2 (target_invalid fail-fast)"
else
  fail "behavioral all-empty: expected exit 2, got $RC"
fi
if [ -f "$ERROR_FILE" ] && grep -q 'target_invalid' "$ERROR_FILE"; then
  pass "behavioral all-empty: error class 'target_invalid' recorded"
else
  fail "behavioral all-empty: target_invalid marker missing in ERROR_FILE"
fi
rm -rf "$TMP"

# ══════════════════════════════════════════════════════════════════
# v0.3 profile-aware section (config-profile-mechanism)
# ══════════════════════════════════════════════════════════════════

# ── structural: v0.3 marker + profile-aware invocation grammar ──
if grep -q 'v0.3 — profile-aware' "$REVIEW_SKILL"; then
  pass "v0.3 profile-aware marker present in frontmatter"
else
  fail "v0.3 profile-aware marker missing"
fi
for marker in '~/.codex-pro/profile.yaml' '.codex-pro/profile.yaml' 'profile_source'; do
  cnt=$(grep -c -- "$marker" "$REVIEW_SKILL")
  [ "$cnt" -ge 1 ] && pass "profile marker present: $marker (n=$cnt)" \
    || fail "profile marker missing: $marker"
done
if grep -q -- '--model "$MODEL"' "$REVIEW_SKILL"; then
  pass "codex-call uses resolved --model \"\$MODEL\""
else
  fail "codex-call does not use resolved --model"
fi
if grep -q -- '--max-time "$MAX_TIME"' "$REVIEW_SKILL"; then
  pass "codex-call uses resolved --max-time \"\$MAX_TIME\""
else
  fail "codex-call does not use resolved --max-time"
fi
# default 600 must still be documented as the fallback
if grep -q '600' "$REVIEW_SKILL"; then
  pass "hardcoded default 600 still documented as fallback"
else
  fail "hardcoded default 600 missing"
fi

# ── behavioral: extract the producer resolver, run it against a fake profile ──
RRES=$(mktemp)
python3 - "$REVIEW_SKILL" "$RRES" <<'PY'
import re, sys
c = open(sys.argv[1]).read()
m = re.search(r"PROFILE_RESOLVED=\$\(python3 - <<'PY'\n(.*?)\nPY\n\)", c, re.DOTALL)
if not m:
    sys.exit("RESOLVER_EXTRACT_FAIL")
open(sys.argv[2], "w").write(m.group(1))
PY
if [ -s "$RRES" ]; then
  pass "behavioral: extracted review profile resolver from SKILL.md"
  th=$(mktemp -d); tp=$(mktemp -d)
  mkdir -p "$th/.codex-pro"; printf 'model: gpt-5.0\n' > "$th/.codex-pro/profile.yaml"
  mkdir -p "$tp/.codex-pro"; printf 'max_time: 1200\n' > "$tp/.codex-pro/profile.yaml"
  out=$(cd "$tp" && HOME="$th" python3 "$RRES" 2>&1)
  # expected: model=gpt-5.0 (global) max_time=1200 (project) -> source=mixed
  if [ "$out" = "gpt-5.0|xhigh|1200||mixed" ]; then
    pass "behavioral: review resolver yields gpt-5.0|xhigh|1200||mixed"
  else
    fail "behavioral: review resolver wrong output: '$out'"
  fi
  rm -rf "$th" "$tp"
else
  fail "behavioral: could not extract review resolver"
fi
rm -f "$RRES"

report_summary "review"
