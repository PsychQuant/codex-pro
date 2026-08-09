#!/usr/bin/env bash
# scripts/generate-codex-skills.sh — 由 Claude plugin skill 產出 Codex 鏡像（#9）。
#
# 為什麼需要這支腳本：
#   codex-pro 的 skill 以 Claude Code plugin 格式撰寫（plugins/codex-pro/skills/），
#   使用 Codex coding agent 的協作者讀不到那個命名空間。Codex 探索的專案級路徑是
#   .codex/skills/<name>/SKILL.md（openai/codex repo 自身即用此慣例）。
#
# 為什麼是生成而非手動維護兩份：
#   9 個 skill × 2 份，改一邊忘另一邊只是時間問題。單向生成 + tests/codex-skills-parity.sh
#   的 git-diff 空檢查，讓漂移在 CI 就紅，而不是等 Codex 使用者踩到。
#
# 為什麼不是 symlink：
#   兩種格式實測有內容差異（命名空間前綴、codex-setup 的 Claude-only 檢查），
#   symlink 前提不成立。
#
# 來源是唯一 source of truth，本腳本只讀不改來源。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SOURCE_DIR="$REPO_ROOT/plugins/codex-pro/skills"

# 輸出目錄可覆寫，讓 parity test 能生成到暫存目錄再比對，而不必動到 committed
# 產物。若寫死輸出，測試就只能靠 git status 判斷漂移——那在「產物尚未提交」的
# 首次執行必然誤報，等於在最該通過的時刻是紅的。
MIRROR_DIR="${1:-$REPO_ROOT/.codex/skills}"

if [ ! -d "$SOURCE_DIR" ]; then
  echo "FATAL: source skills dir missing: $SOURCE_DIR" >&2
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "FATAL: python3 not on PATH" >&2
  exit 2
fi

mkdir -p "$MIRROR_DIR"

# 先移除孤兒鏡像：來源刪掉的 skill 若留著鏡像，Codex 使用者會叫出一個已廢棄的命令。
if [ -d "$MIRROR_DIR" ]; then
  while IFS= read -r d; do
    name="$(basename "$d")"
    if [ ! -d "$SOURCE_DIR/$name" ]; then
      echo "→ removing orphan mirror: $name"
      rm -rf "$d"
    fi
  done < <(find "$MIRROR_DIR" -mindepth 1 -maxdepth 1 -type d | sort)
fi

generated=0
while IFS= read -r skill_dir; do
  skill="$(basename "$skill_dir")"
  src="$skill_dir/SKILL.md"
  [ -r "$src" ] || { echo "⚠ skipping '$skill' (no readable SKILL.md)" >&2; continue; }

  out_dir="$MIRROR_DIR/$skill"
  mkdir -p "$out_dir"

  SKILL_NAME="$skill" python3 - "$src" "$out_dir/SKILL.md" <<'PY'
import os, re, sys

src_path, out_path = sys.argv[1], sys.argv[2]
skill = os.environ["SKILL_NAME"]
text = open(src_path, encoding="utf-8").read()

# ── 命名空間改寫 ──────────────────────────────────────────────
# Claude Code 用 /<plugin>:<skill>，Codex 用 $<skill>。這是兩個 harness 的
# 命令語法差異，不是內容差異——其餘散文一字不動。
#
# 交替分支涵蓋 glob 形式（`/codex-pro:*`，用於「其他 X command」這類泛指）。
# 只寫 [a-z0-9-]+ 會漏掉它，留下一個看不出錯但指向不存在命名空間的殘留。
text = re.sub(r"/codex-pro:([a-z0-9-]+|\*)", r"$\1", text)

# ── codex-setup 具名特例 ──────────────────────────────────────
# CLAUDE_PLUGIN_ROOT 只在 Claude Code plugin 執行期存在。Codex 環境下
# `${CLAUDE_PLUGIN_ROOT:-$(pwd)}` 會 fallback 到 cwd，然後去讀一個在 Codex 下
# 必然不存在的 .claude-plugin/plugin.json，回報誤導性的 not_found ——
# 看起來像「安裝壞了」，實際上是這個檢查在此環境本就不適用。
# 換成明確聲明，而不是讓它靜默失敗。
#
# 這是全檔唯一需要人工判斷的內容差異；其餘皆機械轉換。
if skill == "codex-setup":
    before = text
    text = re.sub(
        r"```bash\nplugin_root=\"\$\{CLAUDE_PLUGIN_ROOT:-\$\(pwd\)\}\".*?\n```",
        "> **此檢查在 Codex 環境不適用。**\n"
        ">\n"
        "> 原始檢查讀 `.claude-plugin/plugin.json` 驗證 Claude Code plugin manifest。\n"
        "> Codex 沒有 plugin manifest 這個概念，該檔案必然不存在——執行它只會得到\n"
        "> 誤導性的 `not_found`，看起來像安裝壞了。\n"
        ">\n"
        "> Codex 環境請改以 Check 1（OAuth）與 Check 2（codex-call runtime）判斷就緒狀態。",
        text,
        flags=re.DOTALL,
    )
    if text == before:
        # 來源結構改了而特例沒跟上——寧可失敗也不要靜默產出一個帶
        # Claude-only 環境變數的 Codex skill。
        sys.stderr.write(
            "FATAL: codex-setup special case did not match; source structure changed.\n"
            "       Update the regex in scripts/generate-codex-skills.sh.\n"
        )
        sys.exit(3)

# ── generated marker ─────────────────────────────────────────
# 插在 frontmatter 之後、body 之前——frontmatter 前加註解會破壞 YAML 解析。
marker = (
    "<!-- GENERATED FILE — DO NOT EDIT.\n"
    f"     Source: plugins/codex-pro/skills/{skill}/SKILL.md\n"
    "     Regenerate: scripts/generate-codex-skills.sh\n"
    "     Drift is caught by tests/codex-skills-parity.sh -->\n"
)

parts = text.split("---\n", 2)
if len(parts) >= 3 and parts[0] == "":
    text = "---\n" + parts[1] + "---\n" + marker + parts[2]
else:
    sys.stderr.write(f"FATAL: {src_path} has no parseable frontmatter\n")
    sys.exit(3)

open(out_path, "w", encoding="utf-8").write(text)
PY

  generated=$((generated + 1))
done < <(find "$SOURCE_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

echo "✓ generated $generated Codex skill mirror(s) → ${MIRROR_DIR#"$REPO_ROOT"/}"
