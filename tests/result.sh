#!/usr/bin/env bash
# tests/result.sh — Layer 2: structural + behavioral runtime checks for
# the result skill. Structural section verifies SKILL.md frontmatter,
# read-only consumer invariants (no Codex HTTP wrapper / subprocess /
# mkdir literals), three-mode selection prose (positional / --latest /
# --latest <skill>), mutex marker, lexical-order discipline (D3:
# filename = ISO8601 timestamp authority; mtime irrelevant), and
# fail-fast remediation references. Behavioral section uses mktemp +
# fake .codex-pro/ fixture (D5) to exercise the three selection modes,
# mutex argument rejection, lexical-vs-mtime independence, and four
# fail-fast cases including missing directory + unknown filename +
# zero-match --latest <skill> + conflicting arguments.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"

RESULT_SKILL="$REPO_ROOT/plugins/codex-pro/skills/result/SKILL.md"

# ══════════════════════════════════════════════════════════════════
# Structural section
# ══════════════════════════════════════════════════════════════════

assert_file "$RESULT_SKILL" "result SKILL.md exists"

# ── (a) Frontmatter parse ────────────────────────────────────────
fm_check=$(python3 - "$RESULT_SKILL" <<'PY' 2>/dev/null
import re, sys
content = open(sys.argv[1]).read()
m = re.match(r"^---\n(.*?)\n---\n", content, re.DOTALL)
if not m:
    print("no_frontmatter"); sys.exit(0)
fm = m.group(1)
name_ok = "name: result" in fm
bash_ok = "Bash" in fm
read_ok = "Read" in fm
keyword_ok = any(k in fm for k in ("show result", "顯示結果", "看完整", "detail", "display review"))
print(f"name={name_ok} bash={bash_ok} read={read_ok} keyword={keyword_ok}")
PY
)
case "$fm_check" in
  *"name=True bash=True read=True keyword=True"*)
    pass "frontmatter: name=result, allowed-tools 含 Bash + Read, description 含 mental-model keyword" ;;
  *)
    fail "frontmatter check failed: $fm_check" ;;
esac

# ── (b) Read-only invariants ─────────────────────────────────────
for forbidden in 'codex-call' 'codex exec' 'mkdir'; do
  cnt=$(grep -c "$forbidden" "$RESULT_SKILL")
  assert_eq "0" "$cnt" "SKILL.md does NOT contain '$forbidden' (read-only consumer invariant)"
done

# ── (c) Read-only / consumer prose ───────────────────────────────
ro_count=$(grep -cE 'read-only|consumer' "$RESULT_SKILL")
if [ "$ro_count" -ge 2 ]; then
  pass "SKILL.md documents read-only consumer category (count=$ro_count)"
else
  fail "SKILL.md missing read-only consumer prose"
fi

# ── (d) Three selection modes ────────────────────────────────────
latest_count=$(grep -c -- '--latest' "$RESULT_SKILL")
if [ "$latest_count" -ge 3 ]; then
  pass "SKILL.md documents --latest in three selection modes (count=$latest_count)"
else
  fail "SKILL.md --latest count $latest_count < 3"
fi

# ── (e) Mutex marker ─────────────────────────────────────────────
if grep -qE 'mutually exclusive|mutex|互斥' "$RESULT_SKILL"; then
  pass "SKILL.md documents three modes mutually exclusive"
else
  fail "SKILL.md missing mutex marker for selection modes"
fi

# ── (f) Lexical order discipline + mtime non-consult ─────────────
if grep -qE 'lexical|sort' "$RESULT_SKILL"; then
  pass "SKILL.md documents lexical filename order as authority"
else
  fail "SKILL.md missing lexical-order marker"
fi
if grep -q 'mtime' "$RESULT_SKILL"; then
  pass "SKILL.md explicitly references mtime (to deny its use)"
else
  fail "SKILL.md missing mtime non-consult reference"
fi
if grep -qE 'ISO8601|timestamp' "$RESULT_SKILL"; then
  pass "SKILL.md references ISO8601 timestamp source-of-truth"
else
  fail "SKILL.md missing ISO8601 marker"
fi

# ── (g) Fail-fast remediation references ─────────────────────────
if grep -q '/codex-pro:status' "$RESULT_SKILL"; then
  pass "SKILL.md fail-fast remediation references /codex-pro:status"
else
  fail "SKILL.md missing /codex-pro:status remediation reference"
fi
if grep -qE 'silent|fallback|顯式' "$RESULT_SKILL"; then
  pass "SKILL.md documents no-silent-fallback discipline"
else
  fail "SKILL.md missing silent fallback prohibition"
fi

# ══════════════════════════════════════════════════════════════════
# Behavioral runtime section (D5: mktemp + fake .codex-pro/ fixture)
# ══════════════════════════════════════════════════════════════════

run_result() {
  local pos_file="" latest_flag="" latest_skill=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --latest)
        latest_flag=1
        if [ -n "${2:-}" ] && [[ "$2" != --* ]]; then
          latest_skill="$2"; shift
        fi
        ;;
      --*)
        echo "Error: unknown flag $1" >&2
        return 2
        ;;
      *)
        pos_file="$1"
        ;;
    esac
    shift
  done
  if [ -n "$pos_file" ] && [ -n "$latest_flag" ]; then
    echo "Error: selection modes are mutually exclusive (互斥)." >&2
    echo "Choose one: <filename> | --latest <skill> | --latest" >&2
    return 2
  fi
  if [ ! -d ".codex-pro" ]; then
    echo "Error: .codex-pro/ not yet created — run /codex-pro:review, /codex-pro:rescue, or /codex-pro:adversarial-review first." >&2
    return 2
  fi
  local target=""
  if [ -n "$pos_file" ]; then
    target=".codex-pro/$pos_file"
  elif [ -n "$latest_skill" ]; then
    target=$(find .codex-pro -maxdepth 1 -name "${latest_skill}-*.md" -type f 2>/dev/null | sort | tail -1)
  else
    # Cross-prefix latest — sort by ISO8601 timestamp portion of filename
    target=$(find .codex-pro -maxdepth 1 -name '*.md' -type f 2>/dev/null | python3 -c "
import sys, re
files = sys.stdin.read().splitlines()
def key(p):
    m = re.search(r'(\d{8}T\d{6}Z?)', p)
    return m.group(1) if m else ''
files = [f for f in files if key(f)]
print(sorted(files, key=key)[-1] if files else '')
")
  fi
  if [ -z "$target" ] || [ ! -f "$target" ]; then
    if [ -n "$pos_file" ]; then
      echo "Error: File not found in .codex-pro/. Run /codex-pro:status to list available files." >&2
    elif [ -n "$latest_skill" ]; then
      echo "Error: No ${latest_skill} result files in .codex-pro/. Run /codex-pro:${latest_skill} to produce one." >&2
    else
      echo "Error: No result files in .codex-pro/. Run any producer skill to create one." >&2
    fi
    return 2
  fi
  cat "$target"
  return 0
}

# Fixture — 5 files: 2 review (different timestamps), 1 rescue, 1 adversarial, 0 in some cases
write_fixture() {
  local dir="$1"
  mkdir -p "$dir/.codex-pro"
  cat > "$dir/.codex-pro/review-20260601T120000Z.md" <<'F'
---
target: diff
findings_count: 2
---

# Review 1
F
  cat > "$dir/.codex-pro/review-20260601T133000Z.md" <<'F'
---
target: diff
findings_count: 5
---

# Review 2 (later)
F
  cat > "$dir/.codex-pro/rescue-20260601T130000Z.md" <<'F'
---
task_description: test rescue
outcome: completed
---

# Rescue
F
  cat > "$dir/.codex-pro/adversarial-review-20260601T140000Z.md" <<'F'
---
target: diff
focus: ""
depth: deep
---

# Adversarial Review
F
}

# ── (h) Positional filename selection ────────────────────────────
TMP_POS=$(mktemp -d)
write_fixture "$TMP_POS"
POS_OUT=$(cd "$TMP_POS" && run_result review-20260601T120000Z.md)
POS_RC=$?
if echo "$POS_OUT" | grep -q '# Review 1' && [ "$POS_RC" -eq 0 ]; then
  pass "behavioral: positional <filename> displays specific file"
else
  fail "behavioral: positional <filename> failed (rc=$POS_RC out='$POS_OUT')"
fi

# ── (i) --latest <skill> lexical order ───────────────────────────
LATEST_REVIEW_OUT=$(cd "$TMP_POS" && run_result --latest review)
LATEST_REVIEW_RC=$?
if echo "$LATEST_REVIEW_OUT" | grep -q '# Review 2 (later)' && [ "$LATEST_REVIEW_RC" -eq 0 ]; then
  pass "behavioral: --latest review picks lexical-newest review (20260601T133000Z)"
else
  fail "behavioral: --latest review selection wrong (out='$LATEST_REVIEW_OUT')"
fi

LATEST_ADV_OUT=$(cd "$TMP_POS" && run_result --latest adversarial-review)
LATEST_ADV_RC=$?
if echo "$LATEST_ADV_OUT" | grep -q '# Adversarial Review' && [ "$LATEST_ADV_RC" -eq 0 ]; then
  pass "behavioral: --latest adversarial-review picks the adversarial-review file"
else
  fail "behavioral: --latest adversarial-review wrong (out='$LATEST_ADV_OUT')"
fi

# ── (j) --latest (no arg) selects lexical max across producers ───
# Touch rescue to earlier mtime — selection should still pick adversarial (lexical max)
touch -t 202001010000 "$TMP_POS/.codex-pro/adversarial-review-20260601T140000Z.md" 2>/dev/null || true
LATEST_ALL_OUT=$(cd "$TMP_POS" && run_result --latest)
LATEST_ALL_RC=$?
# adversarial-review-20260601T140000Z.md is lexically max regardless of mtime
if echo "$LATEST_ALL_OUT" | grep -q '# Adversarial Review' && [ "$LATEST_ALL_RC" -eq 0 ]; then
  pass "behavioral: --latest (no arg) uses lexical filename order, ignores mtime"
else
  fail "behavioral: --latest (no arg) wrong (out='$LATEST_ALL_OUT')"
fi

# ── (k) Mutex argument rejection ─────────────────────────────────
MUTEX_OUT=$(cd "$TMP_POS" && run_result review-20260601T120000Z.md --latest 2>&1)
MUTEX_RC=$?
if echo "$MUTEX_OUT" | grep -qE 'mutually exclusive|互斥' && [ "$MUTEX_RC" -eq 2 ]; then
  pass "behavioral: positional + --latest rejected as mutually exclusive (exit 2)"
else
  fail "behavioral: mutex check failed (rc=$MUTEX_RC out='$MUTEX_OUT')"
fi

# ── (l) Unknown filename fail-fast with status remediation ───────
UNKNOWN_OUT=$(cd "$TMP_POS" && run_result bogus-20260601T120000Z.md 2>&1)
UNKNOWN_RC=$?
if echo "$UNKNOWN_OUT" | grep -q '/codex-pro:status' && [ "$UNKNOWN_RC" -eq 2 ]; then
  pass "behavioral: unknown filename fails fast with /codex-pro:status remediation"
else
  fail "behavioral: unknown filename handling wrong (rc=$UNKNOWN_RC out='$UNKNOWN_OUT')"
fi

# ── (m) --latest <skill> zero match fail-fast with producer remediation ──
# Remove all adversarial-review files to make --latest adversarial-review zero-match
rm -f "$TMP_POS/.codex-pro/adversarial-review-"*.md
ZERO_OUT=$(cd "$TMP_POS" && run_result --latest adversarial-review 2>&1)
ZERO_RC=$?
if echo "$ZERO_OUT" | grep -q '/codex-pro:adversarial-review' && [ "$ZERO_RC" -eq 2 ]; then
  pass "behavioral: --latest <skill> zero-match references producer skill in remediation"
else
  fail "behavioral: zero-match handling wrong (rc=$ZERO_RC out='$ZERO_OUT')"
fi
rm -rf "$TMP_POS"

# ── (n) Missing .codex-pro/ fail-fast with producer remediation ──
TMP_MISS=$(mktemp -d)
MISS_OUT=$(cd "$TMP_MISS" && run_result --latest 2>&1)
MISS_RC=$?
if echo "$MISS_OUT" | grep -q 'not yet created' && [ "$MISS_RC" -eq 2 ]; then
  pass "behavioral: missing .codex-pro/ fails fast with producer creation remediation"
else
  fail "behavioral: missing .codex-pro/ handling wrong (rc=$MISS_RC out='$MISS_OUT')"
fi
# Verify directory was NOT created (read-only invariant)
if [ ! -d "$TMP_MISS/.codex-pro" ]; then
  pass "behavioral: skill did NOT create .codex-pro/ on missing directory"
else
  fail "behavioral: skill incorrectly created .codex-pro/"
fi
rm -rf "$TMP_MISS"

report_summary "result"
