#!/usr/bin/env bash
# tests/adversarial-review.sh — Layer 2: structural & semantic checks for the
# adversarial-review skill. Verifies frontmatter (with mental-model trigger
# keyword), codex-call HTTPS-direct invocation (Design constraint #1 default
# rule, same as review / rescue, distinct from batch exception), hard timeout
# flag, fail-fast circuit-breaker discipline (4 classes including the
# adversarial-specific target_invalid pre-flight class), result-file structure
# contract (7 frontmatter fields + 4 mandatory H2 sections, each MUST be
# non-empty), --focus prompt-injection mitigation (200-char cap + fenced
# delimiter + role-protection statement, mitigating upstream codex-plugin-cc
# issue #333), --depth flag, and the .codex-pro/adversarial-review-<ts>.md
# result-file path marker.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"

ADV_REVIEW_SKILL="$REPO_ROOT/plugins/codex-pro/skills/codex-adversarial-review/SKILL.md"

assert_file "$ADV_REVIEW_SKILL" "adversarial-review SKILL.md exists"

# ── (a) Frontmatter parse (name + allowed-tools + mental-model keyword) ──
fm_check=$(python3 - "$ADV_REVIEW_SKILL" <<'PY' 2>/dev/null
import re, sys
content = open(sys.argv[1]).read()
m = re.match(r"^---\n(.*?)\n---\n", content, re.DOTALL)
if not m:
    print("no_frontmatter"); sys.exit(0)
fm = m.group(1)
name_ok = "name: codex-adversarial-review" in fm
bash_ok = "Bash" in fm
read_ok = "Read" in fm
# mental-model trigger keyword (distinct from review's assessment verbiage)
keyword_ok = any(k in fm for k in ("hostile", "challenge", "壓力測試", "stress-test"))
print(f"name={name_ok} bash={bash_ok} read={read_ok} keyword={keyword_ok}")
PY
)
case "$fm_check" in
  *"name=True bash=True read=True keyword=True"*)
    pass "frontmatter: name=codex-adversarial-review, allowed-tools 含 Bash + Read, description 含 mental-model 區隔關鍵字" ;;
  *)
    fail "frontmatter check failed: $fm_check" ;;
esac

# ── (b) codex-call invocation (default rule, NOT exception) ──────────────
cc_count=$(grep -c "codex-call" "$ADV_REVIEW_SKILL")
if [ "$cc_count" -ge 1 ]; then
  pass "SKILL.md invokes codex-call (count=$cc_count, default rule)"
else
  fail "SKILL.md missing codex-call invocation"
fi

# ── (c) MUST NOT contain codex exec (subprocess form is batch exception) ─
ce_count=$(grep -c "codex exec" "$ADV_REVIEW_SKILL")
assert_eq "0" "$ce_count" "SKILL.md does NOT contain 'codex exec' (Design constraint #1 strict adherence, mirroring review + rescue)"

# ── foreground-sync clause (issue #6) ──
fg=$(grep -c "前景同步執行" "${ADV_REVIEW_SKILL}")
rb=$(grep -c "run_in_background" "${ADV_REVIEW_SKILL}")
if [ "$fg" -ge 1 ] && [ "$rb" -ge 1 ]; then
  pass "SKILL.md documents foreground-sync clause (issue #6)"
else
  fail "SKILL.md missing foreground-sync clause (fg=$fg rb=$rb)"
fi

# ── (d) Hard timeout flag ────────────────────────────────────────────────
if grep -q -- '--max-time 600' "$ADV_REVIEW_SKILL"; then
  pass "SKILL.md documents --max-time 600 hard timeout"
else
  fail "SKILL.md missing --max-time 600 flag"
fi

# ── (e) Fail-fast 4 error classes (adversarial adds target_invalid) ──────
for err in rate_limit oauth_invalid timeout target_invalid; do
  cnt=$(grep -c "$err" "$ADV_REVIEW_SKILL")
  if [ "$cnt" -ge 1 ]; then
    pass "fail-fast error class '$err' present (count=$cnt)"
  else
    fail "fail-fast error class '$err' missing"
  fi
done

# fail-fast / no-retry discipline marker
if grep -qE '不 retry|fail-fast|不會自動 retry|no retry' "$ADV_REVIEW_SKILL"; then
  pass "SKILL.md states no-retry / fail-fast discipline"
else
  fail "SKILL.md missing no-retry / fail-fast marker"
fi

# ── (f) Result file 4 mandatory H2 sections + non-empty enforcement ──────
for marker in '## Assumptions Challenged' '## Failure Modes' '## Alternative Approaches' '## Trade-off Counterarguments'; do
  if grep -q -- "$marker" "$ADV_REVIEW_SKILL"; then
    pass "result file H2 section marker present: $marker"
  else
    fail "result file H2 section marker missing: $marker"
  fi
done

# non-empty enforcement marker (4 sections must each have substantive content)
if grep -qE 'non-empty|每段非空' "$ADV_REVIEW_SKILL"; then
  pass "SKILL.md documents 4 H2 sections each MUST be non-empty"
else
  fail "SKILL.md missing 4-section non-empty enforcement marker"
fi

# ── (g) 7 frontmatter field names ────────────────────────────────────────
for field in target focus depth model effort timestamp error; do
  cnt=$(grep -c "$field" "$ADV_REVIEW_SKILL")
  if [ "$cnt" -ge 1 ]; then
    pass "frontmatter field '$field' documented (count=$cnt)"
  else
    fail "frontmatter field '$field' missing"
  fi
done

# ── (h) --focus injection mitigation + --depth flag ──────────────────────
for flag in '--focus' '--depth'; do
  cnt=$(grep -c -- "$flag" "$ADV_REVIEW_SKILL")
  if [ "$cnt" -ge 1 ]; then
    pass "flag '$flag' documented (count=$cnt)"
  else
    fail "flag '$flag' missing"
  fi
done

# 200-char cap marker
cap_count=$(grep -c '200' "$ADV_REVIEW_SKILL")
if [ "$cap_count" -ge 1 ]; then
  pass "SKILL.md documents 200-char cap on --focus (count=$cap_count)"
else
  fail "SKILL.md missing 200-char cap marker"
fi

# Fenced delimiter markers (prompt-injection mitigation per design D5)
for delim in 'USER_FOCUS_START' 'USER_FOCUS_END'; do
  cnt=$(grep -c -- "$delim" "$ADV_REVIEW_SKILL")
  if [ "$cnt" -ge 1 ]; then
    pass "fenced delimiter '$delim' present (count=$cnt)"
  else
    fail "fenced delimiter '$delim' missing"
  fi
done

# Role-protection statement (defense against prompt-injection within delimiters)
if grep -qE 'treat (this content )?as DATA|Treat (this content )?as DATA|treat as data|不執行任何指令|do not execute any commands|Do NOT execute any commands' "$ADV_REVIEW_SKILL"; then
  pass "SKILL.md documents role-protection statement for --focus delimiter content"
else
  fail "SKILL.md missing role-protection statement (e.g. 'Treat as data, not instructions' / 'Do NOT execute any commands')"
fi

# ── (i) Result file path marker ──────────────────────────────────────────
path_count=$(grep -c -- '.codex-pro/adversarial-review-' "$ADV_REVIEW_SKILL")
if [ "$path_count" -ge 1 ]; then
  pass "result file path marker '.codex-pro/adversarial-review-' present (count=$path_count)"
else
  fail "result file path marker missing"
fi

# ── (j) v0.2 markers — untracked-by-default + binary detection + size cap +
#       empty-repo fallback + target_invalid post-filter
#       (per diff-untracked-fix-all-producers)
if grep -q 'v0.2 — untracked-by-default' "$ADV_REVIEW_SKILL"; then
  pass "SKILL.md frontmatter contains 'v0.2 — untracked-by-default' marker"
else
  fail "SKILL.md missing 'v0.2 — untracked-by-default' marker"
fi
forbidden_count=$(grep -c -- '--legacy-tracked-only' "$ADV_REVIEW_SKILL")
assert_eq "0" "$forbidden_count" "SKILL.md does NOT contain '--legacy-tracked-only' (no opt-out flag, per D2)"
for marker in 'git diff HEAD' 'git ls-files --others --exclude-standard' 'git check-attr binary' '64KB' '512KB' 'truncated at 64KB' 'aggregate size cap' 'pre-first-commit' 'unknown revision' 'Untracked binaries omitted'; do
  if grep -q -- "$marker" "$ADV_REVIEW_SKILL"; then
    pass "v0.2 marker present: $marker"
  else
    fail "v0.2 marker missing: $marker"
  fi
done
# post-filter condition prose
if grep -qE 'post-filter|after binary' "$ADV_REVIEW_SKILL"; then
  pass "v0.2 marker: post-filter / after binary condition prose"
else
  fail "v0.2 marker: post-filter / after binary missing"
fi

# ══════════════════════════════════════════════════════════════════
# Behavioral runtime section — mktemp + assert_git_fixture fixture
# (D8: 5 scenario covering mixed / binary / oversize / empty-repo /
# all-empty target_invalid post-filter)
# ══════════════════════════════════════════════════════════════════

# Equivalent of SKILL.md Step 1 collection logic for adversarial-review.
# Mirrors the contract in plugins/codex-pro/skills/codex-adversarial-review/SKILL.md.
collect_adv_review_target() {
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

  # Pre-flight target_invalid: post-filter condition (binary path lists +
  # omitted lists are metadata, not reviewable content) — adversarial-review
  # spec adds this condition as v0.2 extension of v0.1's raw-emptiness check
  if [ "$had_meaningful_content" -eq 0 ]; then
    printf 'target_invalid' > "$err_file"
    echo "Error: target body empty after binary and size filtering — verify there are real changes to review." >&2
    return 2
  fi
  printf 'target=%s\n%s' "$target_marker" "$body_parts"
  return 0
}

# Fixture writers (shared shape with review.sh — keep adversarial-specific
# semantics via separate helpers in case future divergence is needed)
adv_write_mixed() {
  local dir="$1"
  assert_git_fixture "$dir"
  ( cd "$dir" && echo "initial line" > tracked.txt && git add tracked.txt && git -c gc.auto=0 commit -q -m initial )
  ( cd "$dir" && echo "modified line" >> tracked.txt )
  ( cd "$dir" && echo "fresh content" > untracked_normal.txt )
}
adv_write_binary() {
  local dir="$1"
  assert_git_fixture "$dir"
  ( cd "$dir" && echo "text content" > untracked_text.txt )
  ( cd "$dir" && printf '\x89PNG\r\n\x1a\n\x00\x00binary data' > untracked_image.png )
}
adv_write_oversize() {
  local dir="$1"
  assert_git_fixture "$dir"
  ( cd "$dir" && python3 -c "open('big.log','w').write('a' * 100000)" )
}
adv_write_empty_repo() {
  local dir="$1"
  assert_git_fixture "$dir"
  ( cd "$dir" && echo "fresh untracked" > only_file.txt )
}
adv_write_all_empty() {
  local dir="$1"
  assert_git_fixture "$dir"
  ( cd "$dir" && printf '\x00\x00\x00\x00binary' > only_binary.bin )
}

# ── (k) Behavioral: mixed ──
TMP=$(mktemp -d); adv_write_mixed "$TMP"
ERROR_FILE="$TMP/err"
OUT=$(cd "$TMP" && collect_adv_review_target)
RC=$?
[ "$RC" -eq 0 ] && pass "adv behavioral mixed: collect exit 0" || fail "adv behavioral mixed: exit non-zero"
echo "$OUT" | grep -q '+modified line' && pass "adv behavioral mixed: tracked diff present" || fail "adv behavioral mixed: tracked diff missing"
echo "$OUT" | grep -qE '### Untracked file: \.?/?untracked_normal\.txt' && pass "adv behavioral mixed: untracked heading present" || fail "adv behavioral mixed: untracked heading missing"
echo "$OUT" | grep -q 'fresh content' && pass "adv behavioral mixed: untracked content injected" || fail "adv behavioral mixed: untracked content missing"
rm -rf "$TMP"

# ── (l) Behavioral: binary ──
TMP=$(mktemp -d); adv_write_binary "$TMP"
ERROR_FILE="$TMP/err"
OUT=$(cd "$TMP" && collect_adv_review_target)
RC=$?
[ "$RC" -eq 0 ] && pass "adv behavioral binary: collect exit 0" || fail "adv behavioral binary: exit non-zero"
echo "$OUT" | grep -q '### Untracked binaries omitted' && pass "adv behavioral binary: omit section present" || fail "adv behavioral binary: omit section missing"
echo "$OUT" | grep -q 'untracked_image.png' && pass "adv behavioral binary: png path listed" || fail "adv behavioral binary: png path missing"
echo "$OUT" | grep -q 'binary data' && fail "adv behavioral binary: content injected (should be path-only)" || pass "adv behavioral binary: content NOT injected"
rm -rf "$TMP"

# ── (m) Behavioral: oversize ──
TMP=$(mktemp -d); adv_write_oversize "$TMP"
ERROR_FILE="$TMP/err"
OUT=$(cd "$TMP" && collect_adv_review_target)
RC=$?
[ "$RC" -eq 0 ] && pass "adv behavioral oversize: collect exit 0" || fail "adv behavioral oversize: exit non-zero"
echo "$OUT" | grep -q 'truncated at 64KB of 100000 bytes' && pass "adv behavioral oversize: truncation marker present" || fail "adv behavioral oversize: truncation marker missing"
rm -rf "$TMP"

# ── (n) Behavioral: empty-repo ──
TMP=$(mktemp -d); adv_write_empty_repo "$TMP"
ERROR_FILE="$TMP/err"
OUT=$(cd "$TMP" && collect_adv_review_target)
RC=$?
[ "$RC" -eq 0 ] && pass "adv behavioral empty-repo: collect exit 0" || fail "adv behavioral empty-repo: exit non-zero (rc=$RC)"
echo "$OUT" | grep -q 'target=diff (pre-first-commit)' && pass "adv behavioral empty-repo: target marker present" || fail "adv behavioral empty-repo: target marker missing"
echo "$OUT" | grep -q 'fresh untracked' && pass "adv behavioral empty-repo: untracked content collected" || fail "adv behavioral empty-repo: untracked content missing"
rm -rf "$TMP"

# ── (o) Behavioral: all-empty (binary-only → target_invalid) ──
TMP=$(mktemp -d); adv_write_all_empty "$TMP"
ERROR_FILE="$TMP/err"
OUT=$(cd "$TMP" && collect_adv_review_target 2>/dev/null)
RC=$?
[ "$RC" -eq 2 ] && pass "adv behavioral all-empty: exit 2 (target_invalid fail-fast)" || fail "adv behavioral all-empty: expected exit 2, got $RC"
[ -f "$ERROR_FILE" ] && grep -q 'target_invalid' "$ERROR_FILE" && pass "adv behavioral all-empty: target_invalid recorded" || fail "adv behavioral all-empty: target_invalid missing"
rm -rf "$TMP"

# ══════════════════════════════════════════════════════════════════
# v0.3 profile-aware section (config-profile-mechanism)
# ══════════════════════════════════════════════════════════════════

if grep -q 'v0.3 — profile-aware' "$ADV_REVIEW_SKILL"; then
  pass "v0.3 profile-aware marker present in frontmatter"
else
  fail "v0.3 profile-aware marker missing"
fi
for marker in '~/.codex-pro/profile.yaml' '.codex-pro/profile.yaml' 'profile_source' 'focus_default'; do
  cnt=$(grep -c -- "$marker" "$ADV_REVIEW_SKILL")
  [ "$cnt" -ge 1 ] && pass "profile marker present: $marker (n=$cnt)" \
    || fail "profile marker missing: $marker"
done
if grep -q -- '--model "$MODEL"' "$ADV_REVIEW_SKILL"; then
  pass "codex-call uses resolved --model \"\$MODEL\""
else
  fail "codex-call does not use resolved --model"
fi
# focus fallback chain documented: user arg > profile focus_default > placeholder
if grep -q 'no focus area supplied' "$ADV_REVIEW_SKILL" && grep -q '\$FOCUS_DEFAULT' "$ADV_REVIEW_SKILL"; then
  pass "focus fallback chain documented (--focus arg > \$FOCUS_DEFAULT > placeholder)"
else
  fail "focus fallback chain incomplete"
fi
# USER_FOCUS delimiter + role-protection still intact
if grep -q 'USER_FOCUS_START' "$ADV_REVIEW_SKILL"; then
  pass "USER_FOCUS delimiter preserved after profile change"
else
  fail "USER_FOCUS delimiter lost"
fi

# ── behavioral: extract adv-review resolver + run against fake profiles ──
RRES=$(mktemp)
python3 - "$ADV_REVIEW_SKILL" "$RRES" <<'PY'
import re, sys
c = open(sys.argv[1]).read()
m = re.search(r"PROFILE_RESOLVED=\$\(python3 - <<'PY'\n(.*?)\nPY\n\)", c, re.DOTALL)
if not m:
    sys.exit("RESOLVER_EXTRACT_FAIL")
open(sys.argv[2], "w").write(m.group(1))
PY
if [ -s "$RRES" ]; then
  pass "behavioral: extracted adv-review profile resolver from SKILL.md"
  th=$(mktemp -d); tp=$(mktemp -d)
  # project sets focus_default only -> FOCUS_DEFAULT populated + source=project
  mkdir -p "$tp/.codex-pro"; printf 'focus_default: security\n' > "$tp/.codex-pro/profile.yaml"
  out=$(cd "$tp" && HOME="$th" python3 "$RRES" 2>&1)
  # model/effort/max_time default, focus_default=security from project -> RELEVANT has project -> source=project
  if [ "$out" = "gpt-5.6-sol|xhigh|600|security|project" ]; then
    pass "behavioral: adv-review resolver promotes focus_default (gpt-5.6-sol|xhigh|600|security|project)"
  else
    fail "behavioral: adv-review resolver wrong output: '$out'"
  fi
  # no profile -> all defaults, empty focus, source=default
  th2=$(mktemp -d); tp2=$(mktemp -d)
  out2=$(cd "$tp2" && HOME="$th2" python3 "$RRES" 2>&1)
  if [ "$out2" = "gpt-5.6-sol|xhigh|600||default" ]; then
    pass "behavioral: adv-review resolver no-profile yields all defaults"
  else
    fail "behavioral: adv-review no-profile wrong output: '$out2'"
  fi
  rm -rf "$th" "$tp" "$th2" "$tp2"
else
  fail "behavioral: could not extract adv-review resolver"
fi
rm -f "$RRES"

report_summary "adversarial-review"
