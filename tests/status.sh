#!/usr/bin/env bash
# tests/status.sh — Layer 2: structural + behavioral runtime checks for
# the status skill. Structural section verifies SKILL.md frontmatter,
# read-only category prose, absence of Codex HTTP wrapper / subprocess /
# mkdir literals, presence of --skill filter / table header / 4/4 sections
# marker / not-yet-created + No-result-files-found markers. Behavioral
# section uses mktemp + fake .codex-pro/ fixture (D5 behavioral runtime
# test pattern) to exercise actual scan + frontmatter parse + markdown
# table output across the missing / empty / populated states, including
# heterogeneous producer schemas (review / rescue / adversarial-review)
# and a malformed-YAML row.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"

STATUS_SKILL="$REPO_ROOT/plugins/codex-pro/skills/codex-status/SKILL.md"

# ══════════════════════════════════════════════════════════════════
# Structural section
# ══════════════════════════════════════════════════════════════════

assert_file "$STATUS_SKILL" "status SKILL.md exists"

# ── (a) Frontmatter parse ────────────────────────────────────────
fm_check=$(python3 - "$STATUS_SKILL" <<'PY' 2>/dev/null
import re, sys
content = open(sys.argv[1]).read()
m = re.match(r"^---\n(.*?)\n---\n", content, re.DOTALL)
if not m:
    print("no_frontmatter"); sys.exit(0)
fm = m.group(1)
name_ok = "name: codex-status" in fm
bash_ok = "Bash" in fm
read_ok = "Read" in fm
keyword_ok = any(k in fm for k in ("list result files", "review history", "過去結果", "observability", "list .codex-pro"))
bare_generic = "狀態" in fm and "codex 狀態" not in fm  # issue #2 regression guard (issue #4): bare 狀態 must stay out
print(f"name={name_ok} bash={bash_ok} read={read_ok} keyword={keyword_ok} bare={bare_generic}")
PY
)
case "$fm_check" in
  *"name=True bash=True read=True keyword=True bare=False"*)
    pass "frontmatter: name=codex-status, allowed-tools 含 Bash + Read, description 含 mental-model keyword" ;;
  *)
    fail "frontmatter check failed: $fm_check" ;;
esac

# ── (b) Read-only invariants ─────────────────────────────────────
for forbidden in 'codex-call' 'codex exec' 'mkdir'; do
  cnt=$(grep -c "$forbidden" "$STATUS_SKILL")
  assert_eq "0" "$cnt" "SKILL.md does NOT contain '$forbidden' (read-only consumer invariant)"
done

# ── (c) Read-only / consumer prose ───────────────────────────────
ro_count=$(grep -cE 'read-only|consumer' "$STATUS_SKILL")
if [ "$ro_count" -ge 2 ]; then
  pass "SKILL.md documents read-only consumer category (count=$ro_count)"
else
  fail "SKILL.md missing read-only consumer prose"
fi

# ── (d) Argument parsing markers ─────────────────────────────────
skill_count=$(grep -c -- '--skill' "$STATUS_SKILL")
if [ "$skill_count" -ge 1 ]; then
  pass "SKILL.md documents --skill <name> filter (count=$skill_count)"
else
  fail "SKILL.md missing --skill filter documentation"
fi

# ── (e) Markdown table header marker ─────────────────────────────
if grep -q '| filename | skill type' "$STATUS_SKILL"; then
  pass "SKILL.md documents markdown table header"
else
  fail "SKILL.md missing markdown table header"
fi

# ── (f) heterogeneous schema markers ─────────────────────────────
if grep -q '4/4 sections' "$STATUS_SKILL"; then
  pass "SKILL.md documents adversarial-review '4/4 sections' summary"
else
  fail "SKILL.md missing '4/4 sections' marker"
fi

# ── (g) Missing / empty .codex-pro/ informational handling ───────
if grep -q 'not yet created' "$STATUS_SKILL"; then
  pass "SKILL.md documents missing .codex-pro/ informational message"
else
  fail "SKILL.md missing 'not yet created' marker"
fi
if grep -q 'No result files found' "$STATUS_SKILL"; then
  pass "SKILL.md documents empty .codex-pro/ informational message"
else
  fail "SKILL.md missing 'No result files found' marker"
fi

# ── (h) setup comparison + read-only category 定位 ──────────────
if grep -q 'setup' "$STATUS_SKILL"; then
  pass "SKILL.md references setup skill (read-only category sibling)"
else
  fail "SKILL.md missing setup comparison"
fi

# ══════════════════════════════════════════════════════════════════
# Behavioral runtime section (D5: mktemp + fake .codex-pro/ fixture)
# ══════════════════════════════════════════════════════════════════

# Equivalent of SKILL.md scan + parse + emit logic, isolated for test.
# Mirrors the contract in plugins/codex-pro/skills/codex-status/SKILL.md.
run_status() {
  local skill_filter="${1:-}"
  if [ ! -d ".codex-pro" ]; then
    echo ".codex-pro/ not yet created — any producer skill (/codex-pro:codex-review, /codex-pro:codex-rescue, /codex-pro:codex-adversarial-review) creates it on first run."
    return 0
  fi
  if [ -z "$(find .codex-pro -maxdepth 1 -name '*.md' -type f 2>/dev/null)" ]; then
    echo "No result files found in .codex-pro/."
    echo "Run /codex-pro:codex-review, /codex-pro:codex-rescue, or /codex-pro:codex-adversarial-review to produce one."
    return 0
  fi
  if [ -n "$skill_filter" ]; then
    case "$skill_filter" in
      review|rescue|adversarial-review) ;;
      *)
        echo "Error: --skill must be one of: review, rescue, adversarial-review" >&2
        return 2
        ;;
    esac
  fi
  # header
  printf '| filename | skill type | target / task | outcome summary | timestamp | error |\n'
  printf '| --- | --- | --- | --- | --- | --- |\n'
  STATUS_SKILL_FILTER="$skill_filter" python3 <<'PY'
import os, re
sf = os.environ.get('STATUS_SKILL_FILTER', '')
files = sorted(f for f in os.listdir('.codex-pro') if f.endswith('.md'))
if sf:
    files = [f for f in files if f.startswith(sf + '-')]
for fname in files:
    path = os.path.join('.codex-pro', fname)
    if fname.startswith("review-"): skill = "review"
    elif fname.startswith("rescue-"): skill = "rescue"
    elif fname.startswith("adversarial-review-"): skill = "adversarial-review"
    else: skill = "—"
    try:
        content = open(path).read()
        m = re.match(r'^---\n(.*?)\n---\n', content, re.DOTALL)
        if not m:
            print(f"| {fname} | {skill} | — | (unparseable frontmatter) | — | — |")
            continue
        fm = m.group(1)
        target = re.search(r'^target:\s*(.+)$', fm, re.MULTILINE)
        task = re.search(r'^task_description:\s*(.+)$', fm, re.MULTILINE)
        findings = re.search(r'^findings_count:\s*(\d+)', fm, re.MULTILINE)
        outcome = re.search(r'^outcome:\s*(\w+)', fm, re.MULTILINE)
        error = re.search(r'^error:\s*(\w+)', fm, re.MULTILINE)
        target_or_task = (target.group(1).strip() if target else
                          (task.group(1).strip()[:50] if task else "—"))
        if skill == "review": outcome_summary = f"{findings.group(1)} findings" if findings else "—"
        elif skill == "rescue": outcome_summary = outcome.group(1) if outcome else "—"
        elif skill == "adversarial-review": outcome_summary = "4/4 sections"
        else: outcome_summary = "—"
        ts_match = re.search(r'-(\d{8}T\d{6}Z?)', fname)
        ts = ts_match.group(1) if ts_match else "—"
        if ts != "—" and len(ts) >= 13:
            ts = f"{ts[:4]}-{ts[4:6]}-{ts[6:8]} {ts[9:11]}:{ts[11:13]}"
        err = error.group(1) if error else "—"
        print(f"| {fname} | {skill} | {target_or_task} | {outcome_summary} | {ts} | {err} |")
    except Exception:
        print(f"| {fname} | {skill} | — | (unparseable frontmatter) | — | — |")
PY
  return 0
}

# Fixture helper — writes 3 valid producer files + 1 malformed
write_fixture() {
  local dir="$1"
  mkdir -p "$dir/.codex-pro"
  cat > "$dir/.codex-pro/review-20260601T120000Z.md" <<'F'
---
target: diff
findings_count: 5
model: gpt-5.6-sol
effort: xhigh
timestamp: 2026-06-01T12:00:00+08:00
---

# Review
F
  cat > "$dir/.codex-pro/rescue-20260601T123000Z.md" <<'F'
---
task_description: 修復 .codex/auth.json TCC 問題
session_id: null
model: gpt-5.6-sol
effort: xhigh
timestamp: 2026-06-01T12:30:00+08:00
outcome: completed
---

# Rescue
F
  cat > "$dir/.codex-pro/adversarial-review-20260601T130000Z.md" <<'F'
---
target: diff
focus: ""
depth: deep
model: gpt-5.6-sol
effort: xhigh
timestamp: 2026-06-01T13:00:00+08:00
---

# Adversarial Review
F
  cat > "$dir/.codex-pro/review-20260601T140000Z.md" <<'F'
this is not yaml frontmatter at all
no leading triple-dash
F
}

# ── (i) Missing .codex-pro/ — informational + exit 0 ─────────────
TMP_MISSING=$(mktemp -d)
trap 'rm -rf "$TMP_MISSING"' EXIT
( cd "$TMP_MISSING" && out=$(run_status); rc=$?
  echo "$out" | grep -q 'not yet created' && [ "$rc" -eq 0 ] \
    && echo "PASS_MISSING_OK" || echo "FAIL_MISSING out='$out' rc=$rc"
) > "$TMP_MISSING/result"
if grep -q PASS_MISSING_OK "$TMP_MISSING/result"; then
  pass "behavioral: missing .codex-pro/ prints 'not yet created' + exit 0"
else
  fail "behavioral: missing .codex-pro/ check failed ($(cat "$TMP_MISSING/result"))"
fi

# ── (j) Empty .codex-pro/ — informational + exit 0 ──────────────
TMP_EMPTY=$(mktemp -d)
mkdir -p "$TMP_EMPTY/.codex-pro"
( cd "$TMP_EMPTY" && out=$(run_status); rc=$?
  echo "$out" | grep -q 'No result files found' && [ "$rc" -eq 0 ] \
    && echo "PASS_EMPTY_OK" || echo "FAIL_EMPTY out='$out' rc=$rc"
) > "$TMP_EMPTY/result"
if grep -q PASS_EMPTY_OK "$TMP_EMPTY/result"; then
  pass "behavioral: empty .codex-pro/ prints 'No result files found' + exit 0"
else
  fail "behavioral: empty .codex-pro/ check failed ($(cat "$TMP_EMPTY/result"))"
fi
rm -rf "$TMP_EMPTY"

# ── (k) Populated .codex-pro/ — markdown table + 3 producer rows + malformed handling ──
TMP_POP=$(mktemp -d)
write_fixture "$TMP_POP"
POP_OUT=$(cd "$TMP_POP" && run_status)
POP_RC=$?
if echo "$POP_OUT" | grep -q '| filename | skill type'; then
  pass "behavioral: populated .codex-pro/ emits markdown table header"
else
  fail "behavioral: populated .codex-pro/ missing table header"
fi
review_rows=$(echo "$POP_OUT" | grep -c 'review-20260601T120000Z.md')
rescue_rows=$(echo "$POP_OUT" | grep -c 'rescue-20260601T123000Z.md')
adv_rows=$(echo "$POP_OUT" | grep -c 'adversarial-review-20260601T130000Z.md')
if [ "$review_rows" -eq 1 ] && [ "$rescue_rows" -eq 1 ] && [ "$adv_rows" -eq 1 ]; then
  pass "behavioral: populated .codex-pro/ shows one row per valid producer file"
else
  fail "behavioral: producer rows: review=$review_rows rescue=$rescue_rows adversarial=$adv_rows"
fi
if echo "$POP_OUT" | grep -q '(unparseable frontmatter)'; then
  pass "behavioral: malformed YAML file renders as '(unparseable frontmatter)'"
else
  fail "behavioral: malformed YAML row missing"
fi
if echo "$POP_OUT" | grep -q '4/4 sections'; then
  pass "behavioral: adversarial-review row shows '4/4 sections' outcome summary"
else
  fail "behavioral: '4/4 sections' summary missing"
fi
if echo "$POP_OUT" | grep -q '5 findings'; then
  pass "behavioral: review row shows '5 findings' outcome summary"
else
  fail "behavioral: '5 findings' summary missing"
fi
if echo "$POP_OUT" | grep -q 'completed'; then
  pass "behavioral: rescue row shows 'completed' outcome enum"
else
  fail "behavioral: 'completed' outcome missing"
fi
[ "$POP_RC" -eq 0 ] && pass "behavioral: populated .codex-pro/ exit 0" \
  || fail "behavioral: populated .codex-pro/ exit non-zero (rc=$POP_RC)"

# ── (l) --skill filter behavioral test ───────────────────────────
FILTER_OUT=$(cd "$TMP_POP" && run_status rescue)
FILTER_RC=$?
if echo "$FILTER_OUT" | grep -q 'rescue-20260601T123000Z.md' && \
   ! echo "$FILTER_OUT" | grep -q 'review-20260601T120000Z.md' && \
   ! echo "$FILTER_OUT" | grep -q 'adversarial-review-20260601T130000Z.md'; then
  pass "behavioral: --skill rescue filters to rescue rows only"
else
  fail "behavioral: --skill rescue filter incorrect"
fi
[ "$FILTER_RC" -eq 0 ] && pass "behavioral: --skill rescue exit 0" \
  || fail "behavioral: --skill rescue exit non-zero (rc=$FILTER_RC)"

# Invalid --skill value
INVALID_OUT=$(cd "$TMP_POP" && run_status bogus 2>&1)
INVALID_RC=$?
if echo "$INVALID_OUT" | grep -q 'must be one of: review, rescue, adversarial-review' && [ "$INVALID_RC" -eq 2 ]; then
  pass "behavioral: invalid --skill value rejected with usage hint + exit 2"
else
  fail "behavioral: invalid --skill value handling wrong (out='$INVALID_OUT' rc=$INVALID_RC)"
fi

rm -rf "$TMP_POP"

report_summary "status"
