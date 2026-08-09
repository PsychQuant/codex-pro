#!/usr/bin/env bash
# tests/codex-skills-parity.sh — Layer 1: .codex/skills mirror parity (#9).
#
# codex-pro 的 skill 以 Claude Code plugin 格式撰寫（plugins/codex-pro/skills/），
# 但使用 Codex coding agent 的協作者讀不到那個命名空間。.codex/skills/ 是 Codex
# 實際探索的專案級路徑（openai/codex repo 自身即用此慣例）。
#
# 兩份手動維護必然漂移，所以鏡像由 scripts/generate-codex-skills.sh 單向生成，
# 由本測試擋住漂移。核心是「重新生成到暫存目錄後與 committed 產物逐檔相同」——
# 它同時證明腳本冪等，以及 committed 產物確實是最新來源產生的。
#
# 但那條 snapshot 比對用 generator 自己當 oracle：generator 若開始漏掉
# allowed-tools、或把 glob 前綴寫成 `$*`，重生後兩邊仍然一致而全綠。所以另有一
# 組 transformation contract 檢查，直接斷言轉換規則本身的性質，不經過 generator。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"

SOURCE_DIR="$REPO_ROOT/plugins/codex-pro/skills"
MIRROR_DIR="$REPO_ROOT/.codex/skills"
GENERATOR="$REPO_ROOT/scripts/generate-codex-skills.sh"
MANIFEST="$REPO_ROOT/scripts/codex-skills.manifest"
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

assert_file "$GENERATOR" "generator script exists"
assert_file "$MANIFEST" "expected-skill manifest exists"

# ── 預期集合來自 manifest,不是來源目錄 ──────────────────────────
# 從來源目錄枚舉的話,來源少一個 skill 時 generator 與 test 會一起少一個然後
# 全綠 —— 兩邊用同一個枚舉來源就沒有人能發現。manifest 是外部固定點。
declare -a EXPECTED=()
while IFS= read -r line; do
  line="${line%%#*}"
  line="$(printf '%s' "$line" | tr -d '[:space:]')"
  [ -n "$line" ] && EXPECTED+=("$line")
done < "$MANIFEST"

if [ "${#EXPECTED[@]}" -eq 0 ]; then
  fail "manifest lists no skills: $MANIFEST"
else
  pass "manifest lists ${#EXPECTED[@]} expected skills"
fi

# manifest 與來源目錄必須一一對應（雙向）。
for skill in "${EXPECTED[@]}"; do
  assert_file "$SOURCE_DIR/$skill/SKILL.md" "manifest skill '$skill' exists in source"
done
while IFS= read -r d; do
  name="$(basename "$d")"
  found=0
  for skill in "${EXPECTED[@]}"; do [ "$skill" = "$name" ] && found=1 && break; done
  if [ "$found" -eq 0 ]; then
    fail "source skill '$name' is not listed in the manifest"
  fi
done < <(find "$SOURCE_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

# ── 每個預期 skill 都有鏡像,且轉換性質成立 ──────────────────────
for skill in "${EXPECTED[@]}"; do
  src="$SOURCE_DIR/$skill/SKILL.md"
  mirror="$MIRROR_DIR/$skill/SKILL.md"

  assert_file "$mirror" "mirror exists for '$skill'"
  [ -r "$mirror" ] || continue

  # name 欄位必須與來源一致——轉換不得改動 skill 的識別。
  src_name=$(awk '/^---$/{c++; next} c==1 && /^name:/{sub(/^name:[[:space:]]*/,""); print; exit}' "$src")
  mir_name=$(awk '/^---$/{c++; next} c==1 && /^name:/{sub(/^name:[[:space:]]*/,""); print; exit}' "$mirror")
  assert_eq "$src_name" "$mir_name" "'$skill' name field preserved"
  assert_eq "$skill" "$mir_name" "'$skill' name field matches its directory"

  # frontmatter 欄位一律保留（含 allowed-tools）。保留最多是被 Codex 忽略,
  # 移除則在 Codex 其實支援時等於放寬權限 —— 取安全側。這條直接比對欄位集合,
  # 不經過 generator,所以 generator 日後開始刪欄位時這裡會紅。
  src_keys=$(awk '/^---$/{c++; next} c==1 && /^[a-zA-Z][a-zA-Z0-9_-]*:/{sub(/:.*/,""); print}' "$src" | sort | tr '\n' ' ')
  mir_keys=$(awk '/^---$/{c++; next} c==1 && /^[a-zA-Z][a-zA-Z0-9_-]*:/{sub(/:.*/,""); print}' "$mirror" | sort | tr '\n' ' ')
  assert_eq "$src_keys" "$mir_keys" "'$skill' frontmatter keys preserved"

  # frontmatter 必須仍是合法 YAML（marker 插錯位置最典型的後果就是壞掉的 YAML）。
  python3 - "$mirror" <<'PY' >/dev/null 2>&1 && pass "'$skill' frontmatter still parses as a YAML block" || fail "'$skill' frontmatter is malformed (marker inserted in the wrong place?)"
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
m = re.match(r"\A---\n(.*?\n)---\n", t, flags=re.DOTALL)
sys.exit(0 if m and "name:" in m.group(1) else 1)
PY

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

  # glob 形式（`/codex-pro:*`）若走具名 regex 會變成 `$*` —— 既不是 Codex 的
  # skill 命名空間,又會被讀成 shell 的 `$*`。正確對應是 `$codex-*`。
  if grep -qF '$*' "$mirror"; then
    fail "'$skill' mirror contains bare '\$*' (glob prefix mis-rewritten; want '\$codex-*')"
  else
    pass "'$skill' mirror has no bare '\$*' glob artifact"
  fi

  # generated-marker 是防手改的唯一提示——沒有它，下一個人會直接編輯生成檔。
  assert_contains "$(cat "$mirror")" "$GENERATED_MARKER" "'$skill' mirror carries generated marker"
done

# ── codex-setup 的具名特例 ───────────────────────────────────────
# CLAUDE_PLUGIN_ROOT 只在 Claude Code plugin 執行期存在,Codex 下該檢查不適用。
# 但只拿掉那段 bash 不夠:description、「三項檢查」、報表列、兩個範例都還指著
# 一個不會執行的檢查,agent 只能自己編值填進去。整份契約必須一起收斂成兩項。
SETUP_MIRROR="$MIRROR_DIR/codex-setup/SKILL.md"
if [ -r "$SETUP_MIRROR" ]; then
  # 掃描列表只放「會被 agent 當成可執行事實」的 token:環境變數、必然不存在的
  # 路徑、Claude-only 命令、過期的計數契約、指向已移除檢查的報表佔位符。
  # 刻意不含「Plugin manifest」這個詞本身 —— 下面那條「不適用聲明必須在」的
  # 檢查所要求的文字就得叫出它的名字,解釋一件事的缺席不能不提它。
  for token in "CLAUDE_PLUGIN_ROOT" ".claude-plugin" "/plugin update" "三項" "<Check 3"; do
    if grep -qF "$token" "$SETUP_MIRROR"; then
      fail "codex-setup mirror still references Claude-only '$token'"
    else
      pass "codex-setup mirror has no '$token' residue"
    fi
  done

  # 只檢查「變數不見了」是不夠的 —— generator 若直接把整段刪掉也會通過,
  # 而使用者會看到一個沒有解釋的缺口。明確聲明必須在。
  if grep -qF "Plugin manifest 檢查在 Codex 環境不適用" "$SETUP_MIRROR"; then
    pass "codex-setup mirror carries the explicit not-applicable notice"
  else
    fail "codex-setup mirror lacks the not-applicable notice (silently dropped?)"
  fi

  if grep -qF "兩項" "$SETUP_MIRROR"; then
    pass "codex-setup mirror's report contract says two checks"
  else
    fail "codex-setup mirror does not state the two-check contract"
  fi
fi

# ── 無我們擁有的孤兒鏡像 ─────────────────────────────────────────
# 來源刪掉某個 skill 時，鏡像若不同步刪除就會留下一個叫得出但已廢棄的命令。
# 只管「帶 generated marker」的目錄 —— 別人手寫放進 .codex/skills/ 的 skill
# 不是本專案的產物,本測試無權對它有意見。
if [ -d "$MIRROR_DIR" ]; then
  orphans=0
  while IFS= read -r d; do
    name="$(basename "$d")"
    expected=0
    for skill in "${EXPECTED[@]}"; do [ "$skill" = "$name" ] && expected=1 && break; done
    [ "$expected" -eq 1 ] && continue
    if [ -f "$d/SKILL.md" ] && grep -qF "$GENERATED_MARKER" "$d/SKILL.md"; then
      fail "orphan generated mirror '$name' is not in the manifest"
      orphans=$((orphans + 1))
    fi
  done < <(find "$MIRROR_DIR" -mindepth 1 -maxdepth 1 -type d | sort)
  [ "$orphans" -eq 0 ] && pass "no orphan generated mirrors"
fi

# ── 核心：現存鏡像 == 重新生成的結果 ─────────────────────────────
# 這條同時證明兩件事：腳本冪等，且落在 repo 裡的產物確實是最新來源產生的。
# 任何人改了來源卻忘了重跑，或直接手改生成檔，這裡就會紅。
#
# 生成到暫存目錄再比對，不動 committed 產物——用 git status 判斷會在「產物尚未
# 提交」的首次執行必然誤報，等於在最該通過的時刻是紅的。
if [ -x "$GENERATOR" ]; then
  # mktemp 失敗時 tmp_out 會是空字串。generator 現在對空的 --output 值是 fatal
  # 而非 fallback,但呼叫端自己也要擋 —— 兩層都擋才不會有人改了其中一邊就破功。
  if ! tmp_out="$(mktemp -d)" || [ -z "$tmp_out" ] || [ ! -d "$tmp_out" ]; then
    fail "could not create a temporary directory for fresh regeneration"
  else
    trap 'rm -rf -- "$tmp_out"' EXIT

    if "$GENERATOR" --output "$tmp_out" >/dev/null 2>&1; then
      # 逐 skill 比對而非整樹 diff -r：整樹比對會把「別人手寫放在
      # .codex/skills/ 的 skill」判成差異,等於宣稱這個目錄只能有我們的東西。
      mismatched=0
      for skill in "${EXPECTED[@]}"; do
        if ! diff -q "$MIRROR_DIR/$skill/SKILL.md" "$tmp_out/$skill/SKILL.md" >/dev/null 2>&1; then
          fail "'$skill' mirror differs from fresh regeneration — run $GENERATOR and commit"
          diff -u "$MIRROR_DIR/$skill/SKILL.md" "$tmp_out/$skill/SKILL.md" >&2 || true
          mismatched=$((mismatched + 1))
        fi
      done
      if [ "$mismatched" -eq 0 ]; then
        pass "all mirrors match a fresh regeneration (not stale)"
      fi

      # 冪等：對同一個**非空**目錄再跑一次,結果必須不變。上面那次是寫進空目錄,
      # 證明不了「重複執行不會累積殘留」（舊檔沒清、孤兒沒刪都屬這類）。
      if "$GENERATOR" --output "$tmp_out" >/dev/null 2>&1; then
        rerun_ok=1
        for skill in "${EXPECTED[@]}"; do
          diff -q "$MIRROR_DIR/$skill/SKILL.md" "$tmp_out/$skill/SKILL.md" >/dev/null 2>&1 || rerun_ok=0
        done
        if [ "$rerun_ok" -eq 1 ]; then
          pass "generator is idempotent (second run over a non-empty dir is a no-op)"
        else
          fail "generator is not idempotent — second run changed the output"
        fi
      else
        fail "generator exited non-zero on a second run over a non-empty dir"
      fi
    else
      fail "generator exited non-zero when writing to a temp dir"
    fi
  fi
else
  fail "generator not executable: $GENERATOR"
fi

# ── 拒絕不安全的輸出目的地 ───────────────────────────────────────
# generator 會在輸出目錄內 rm -rf 孤兒。目的地被指到 repo root 時,那個迴圈會
# 把 .git/、plugins/、scripts/ 一併當孤兒 —— 破壞不可逆,所以必須擋在刪除之前。
if [ -x "$GENERATOR" ]; then
  if "$GENERATOR" --output "$REPO_ROOT" >/dev/null 2>&1; then
    fail "generator accepted the repo root as output dir (would rm -rf real content)"
  else
    pass "generator refuses the repo root as output dir"
  fi

  if "$GENERATOR" --output "" >/dev/null 2>&1; then
    fail "generator accepted an empty --output value (would silently write to .codex/skills)"
  else
    pass "generator refuses an empty --output value"
  fi
fi

# ── Summary ─────────────────────────────────────────────────────
report_summary "codex-skills-parity"
exit_code=$?
exit "$exit_code"
