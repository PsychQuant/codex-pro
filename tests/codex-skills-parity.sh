#!/usr/bin/env bash
# tests/codex-skills-parity.sh — Layer 1: .codex/skills mirror parity (#9).
#
# codex-pro 的 skill 以 Claude Code plugin 格式撰寫（plugins/codex-pro/skills/），
# 但使用 Codex coding agent 的協作者讀不到那個命名空間。.codex/skills/ 是 Codex
# 實際探索的專案級路徑（openai/codex repo 自身即用此慣例）。
#
# 兩份手動維護必然漂移，所以鏡像由 scripts/generate-codex-skills.sh 單向生成，
# 由本測試擋住漂移。最關鍵的一條是「重跑生成腳本後 git diff 為空」——它同時證明
# 腳本冪等，以及 committed 產物確實是最新來源產生的。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"

SOURCE_DIR="$REPO_ROOT/plugins/codex-pro/skills"
MIRROR_DIR="$REPO_ROOT/.codex/skills"
GENERATOR="$REPO_ROOT/scripts/generate-codex-skills.sh"
GENERATED_MARKER="GENERATED FILE — DO NOT EDIT"
CLAUDE_NAMESPACE="/codex-pro:"
CODEX_NAMESPACE_PREFIX='$codex-'

# ── Prerequisites ────────────────────────────────────────────────
if ! command -v python3 >/dev/null 2>&1; then
  echo "FATAL: python3 not on PATH (install Xcode Command Line Tools)" >&2
  exit 2
fi

if [ ! -d "$SOURCE_DIR" ]; then
  echo "FATAL: source skills dir missing: $SOURCE_DIR" >&2
  exit 2
fi

# ── Generator exists ─────────────────────────────────────────────
assert_file "$GENERATOR" "generator script exists"

# ── Every source skill has a mirror ──────────────────────────────
declare -a SOURCE_SKILLS=()
while IFS= read -r d; do
  SOURCE_SKILLS+=("$(basename "$d")")
done < <(find "$SOURCE_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

if [ "${#SOURCE_SKILLS[@]}" -eq 0 ]; then
  fail "no source skills found under $SOURCE_DIR"
else
  pass "found ${#SOURCE_SKILLS[@]} source skills"
fi

for skill in "${SOURCE_SKILLS[@]}"; do
  src="$SOURCE_DIR/$skill/SKILL.md"
  mirror="$MIRROR_DIR/$skill/SKILL.md"

  assert_file "$mirror" "mirror exists for '$skill'"
  [ -r "$mirror" ] || continue

  # name 欄位必須與來源一致——轉換不得改動 skill 的識別。
  src_name=$(awk '/^---$/{c++; next} c==1 && /^name:/{sub(/^name:[[:space:]]*/,""); print; exit}' "$src")
  mir_name=$(awk '/^---$/{c++; next} c==1 && /^name:/{sub(/^name:[[:space:]]*/,""); print; exit}' "$mirror")
  assert_eq "$src_name" "$mir_name" "'$skill' name field preserved"

  # 前綴必須改寫乾淨——殘留一處，Codex 使用者就會照著打一個不存在的命令。
  if grep -qF "$CLAUDE_NAMESPACE" "$mirror"; then
    fail "'$skill' mirror still contains Claude namespace '$CLAUDE_NAMESPACE'"
  else
    pass "'$skill' mirror has no Claude namespace residue"
  fi

  if grep -qF "$CODEX_NAMESPACE_PREFIX" "$mirror"; then
    pass "'$skill' mirror uses Codex namespace '${CODEX_NAMESPACE_PREFIX}*'"
  else
    fail "'$skill' mirror has no '${CODEX_NAMESPACE_PREFIX}*' reference"
  fi

  # generated-marker 是防手改的唯一提示——沒有它，下一個人會直接編輯生成檔。
  assert_contains "$(cat "$mirror")" "$GENERATED_MARKER" "'$skill' mirror carries generated marker"
done

# ── codex-setup 的具名特例 ───────────────────────────────────────
# CLAUDE_PLUGIN_ROOT 只在 Claude Code plugin 執行期存在。Codex 環境下該變數不存在，
# 原本的 `${CLAUDE_PLUGIN_ROOT:-$(pwd)}` fallback 會去讀一個必不存在的 manifest，
# 回報誤導性的 not_found。生成版必須換成明確的「不適用」聲明。
SETUP_MIRROR="$MIRROR_DIR/codex-setup/SKILL.md"
if [ -r "$SETUP_MIRROR" ]; then
  if grep -qF "CLAUDE_PLUGIN_ROOT" "$SETUP_MIRROR"; then
    fail "codex-setup mirror still references CLAUDE_PLUGIN_ROOT (Claude-only env var)"
  else
    pass "codex-setup mirror has no CLAUDE_PLUGIN_ROOT reference"
  fi
fi

# ── 無孤兒鏡像 ───────────────────────────────────────────────────
# 來源刪掉某個 skill 時，鏡像若不同步刪除就會留下一個叫得出但已廢棄的命令。
if [ -d "$MIRROR_DIR" ]; then
  while IFS= read -r d; do
    name="$(basename "$d")"
    if [ ! -d "$SOURCE_DIR/$name" ]; then
      fail "orphan mirror '$name' has no source under plugins/codex-pro/skills/"
    fi
  done < <(find "$MIRROR_DIR" -mindepth 1 -maxdepth 1 -type d | sort)
  pass "no orphan mirrors"
fi

# ── 核心：現存鏡像 == 重新生成的結果 ─────────────────────────────
# 這條同時證明兩件事：腳本冪等，且落在 repo 裡的產物確實是最新來源產生的。
# 任何人改了來源卻忘了重跑，或直接手改生成檔，這裡就會紅。
#
# 生成到暫存目錄再比對，不動 committed 產物——用 git status 判斷會在「產物尚未
# 提交」的首次執行必然誤報，等於在最該通過的時刻是紅的。
if [ -x "$GENERATOR" ]; then
  tmp_out="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp_out'" EXIT

  if "$GENERATOR" "$tmp_out" >/dev/null 2>&1; then
    if diff -r "$MIRROR_DIR" "$tmp_out" >/dev/null 2>&1; then
      pass "mirrors match a fresh regeneration (idempotent, not stale)"
    else
      fail "mirrors differ from fresh regeneration — run $GENERATOR and commit the result"
      diff -rq "$MIRROR_DIR" "$tmp_out" >&2 || true
    fi
  else
    fail "generator exited non-zero when writing to a temp dir"
  fi
else
  fail "generator not executable: $GENERATOR"
fi

# ── Summary ─────────────────────────────────────────────────────
report_summary "codex-skills-parity"
exit_code=$?
exit "$exit_code"
