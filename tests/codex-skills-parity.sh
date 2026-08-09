#!/usr/bin/env bash
# tests/codex-skills-parity.sh — Codex skill transformation + full bundle parity.
#
# codex-pro 的 skill 以 Claude Code plugin 格式撰寫（plugins/codex-pro/skills/），
# 但使用 Codex coding agent 的協作者讀不到那個命名空間。.codex/skills/ 是 Codex
# 實際探索的專案級路徑（openai/codex repo 自身即用此慣例）。
#
# 兩份手動維護必然漂移，所以鏡像由 scripts/generate-codex-skills.sh 單向生成，
# 由本測試擋住漂移。核心是「重新生成到暫存目錄後與 committed 產物逐檔相同」——
# 它同時證明腳本冪等，以及 committed 產物確實是最新來源產生的。從 #10 起，
# parity 不再只比 SKILL.md：根層與 .codex 兩份完整 bundle 的 nested resources、
# shared references、runtime 與 ownership inventory 也都屬於同一契約。
#
# 但那條 snapshot 比對用 generator 自己當 oracle：generator 若開始漏掉
# allowed-tools、或把 glob 前綴寫成 `$*`，重生後兩邊仍然一致而全綠。所以另有一
# 組 transformation contract 檢查，直接斷言轉換規則本身的性質，不經過 generator。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"

SOURCE_BUNDLE="$REPO_ROOT/plugins/codex-pro"
SOURCE_DIR="$SOURCE_BUNDLE/skills"
MIRROR_DIR="$REPO_ROOT/.codex/skills"
DOT_CODEX_BUNDLE="$REPO_ROOT/.codex"
ROOT_BUNDLE="$REPO_ROOT"
GENERATOR="$REPO_ROOT/scripts/generate-codex-skills.sh"
MANIFEST="$REPO_ROOT/scripts/codex-skills.manifest"
RESOURCE_MANIFEST="$REPO_ROOT/scripts/codex-bundle-resources.manifest"
INVENTORY_NAME=".codex-bundle-files"
GENERATED_MARKER="GENERATED FILE — DO NOT EDIT"
CLAUDE_NAMESPACE="/codex-pro:"
CODEX_NAMESPACE_PREFIX='$codex-'

# 這五個路徑是 design 明定的最小完整 bundle。provenance 等其他新資源
# 不在這裡雙寫，而是由 resource manifest 與來源目錄的雙向比對捕捉。
declare -a REQUIRED_RESOURCES=(
  "skills/codex-batch/references/script-template.sh"
  "references/defaults.json"
  "references/profile-contract.md"
  "bin/codex-call"
  "bin/codex-pro-call"
)

# ── Prerequisites ────────────────────────────────────────────────
if ! command -v python3 >/dev/null 2>&1; then
  echo "FATAL: python3 not on PATH (install Xcode Command Line Tools)" >&2
  exit 2
fi

# 所有 cleanup / stale-resource 情境都只能發生在這個已驗證的暫存根目錄。
# 對真實 home 與 / 只執行 fail-before-mutation 的 destination rejection test。
if ! TEST_TMP_ROOT="$(mktemp -d)" || [ -z "$TEST_TMP_ROOT" ] || [ ! -d "$TEST_TMP_ROOT" ]; then
  echo "FATAL: could not create an isolated temporary root for bundle parity" >&2
  exit 2
fi
trap 'rm -rf -- "$TEST_TMP_ROOT"' EXIT

if [ ! -d "$SOURCE_DIR" ]; then
  echo "FATAL: source skills dir missing: $SOURCE_DIR" >&2
  exit 2
fi

assert_file "$GENERATOR" "generator script exists"
assert_file "$MANIFEST" "expected-skill manifest exists"
assert_file "$RESOURCE_MANIFEST" "explicit non-SKILL resource manifest exists"

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

# ── 非 SKILL.md 資源集合：外部固定點 ⇄ 來源樹 ────────────────────────
# generator 與 test 若都從相同目錄枚舉，兩邊一起漏檔還是會全綠。
# resource manifest 因此必須是一行一個 bundle-relative 路徑，並與三個
# 可發布來源區（skill-local resources、shared references、bin）雙向相等。
EXPECTED_SKILLS_FILE="$TEST_TMP_ROOT/expected-skills"
DECLARED_RESOURCES_FILE="$TEST_TMP_ROOT/declared-resources"
ACTUAL_SOURCE_RESOURCES_FILE="$TEST_TMP_ROOT/actual-source-resources"
EXPECTED_INVENTORY_FILE="$TEST_TMP_ROOT/expected-inventory"
RESOURCE_MANIFEST_ERROR="$TEST_TMP_ROOT/resource-manifest-error"

printf '%s\n' "${EXPECTED[@]}" | LC_ALL=C sort > "$EXPECTED_SKILLS_FILE"
: > "$DECLARED_RESOURCES_FILE"

if [ -r "$RESOURCE_MANIFEST" ]; then
  if python3 - "$RESOURCE_MANIFEST" > "$DECLARED_RESOURCES_FILE" 2> "$RESOURCE_MANIFEST_ERROR" <<'PY'
from pathlib import PurePosixPath
import sys

manifest = sys.argv[1]
paths = []
errors = []

for number, raw in enumerate(open(manifest, encoding="utf-8"), 1):
    value = raw.split("#", 1)[0].strip()
    if not value:
        continue
    path = PurePosixPath(value)
    parts = value.split("/")
    if path.is_absolute() or value.startswith("~"):
        errors.append(f"line {number}: absolute/home-relative path is forbidden: {value}")
    elif any(part in ("", ".", "..") for part in parts):
        errors.append(f"line {number}: path is not normalized: {value}")
    elif parts[0] not in ("skills", "references", "bin"):
        errors.append(f"line {number}: resource must live under skills/, references/, or bin/: {value}")
    elif value.endswith("/SKILL.md"):
        errors.append(f"line {number}: SKILL.md belongs to the skill manifest, not the resource manifest: {value}")
    paths.append(value)

if paths != sorted(paths):
    errors.append("resource paths are not bytewise sorted")
if len(paths) != len(set(paths)):
    errors.append("resource paths contain duplicates")
if errors:
    sys.stderr.write("; ".join(errors) + "\n")
    raise SystemExit(1)
print(*paths, sep="\n")
PY
  then
    pass "resource manifest paths are normalized, unique, and sorted"
  else
    fail "resource manifest is invalid: $(tr '\n' ';' < "$RESOURCE_MANIFEST_ERROR")"
    : > "$DECLARED_RESOURCES_FILE"
  fi
fi

{
  find "$SOURCE_DIR" -type f ! -name SKILL.md -print
  [ ! -d "$SOURCE_BUNDLE/references" ] || find "$SOURCE_BUNDLE/references" -type f -print
  [ ! -d "$SOURCE_BUNDLE/bin" ] || find "$SOURCE_BUNDLE/bin" -type f -print
} | sed "s#^$SOURCE_BUNDLE/##" | LC_ALL=C sort > "$ACTUAL_SOURCE_RESOURCES_FILE"

assert_eq "$(cat "$ACTUAL_SOURCE_RESOURCES_FILE")" "$(cat "$DECLARED_RESOURCES_FILE")" \
  "resource manifest exactly matches all publishable non-SKILL source files"

for resource in "${REQUIRED_RESOURCES[@]}"; do
  assert_file "$SOURCE_BUNDLE/$resource" "required source resource '$resource' exists"
  if grep -Fqx "$resource" "$DECLARED_RESOURCES_FILE"; then
    pass "resource manifest declares '$resource'"
  else
    fail "resource manifest omits required path '$resource'"
  fi
done

{
  while IFS= read -r skill; do
    [ -n "$skill" ] && printf 'skills/%s/SKILL.md\n' "$skill"
  done < "$EXPECTED_SKILLS_FILE"
  cat "$DECLARED_RESOURCES_FILE"
} | LC_ALL=C sort -u > "$EXPECTED_INVENTORY_FILE"

assert_directory() {
  # assert_directory <path> <msg>
  local path="$1" msg="$2"
  if [ -d "$path" ]; then
    pass "$msg"
  else
    fail "$msg (not a directory: '$path')"
  fi
}

validate_inventory() {
  # validate_inventory <bundle-root> <label>
  local bundle="$1" label="$2" output actual
  actual="$bundle/$INVENTORY_NAME"
  [ -r "$actual" ] || return 0 # 存在性由呼叫端的 assert_file 回報。

  if output="$(python3 - "$bundle" "$actual" "$EXPECTED_INVENTORY_FILE" 2>&1 <<'PY'
from pathlib import Path, PurePosixPath
import os
import sys

bundle = Path(sys.argv[1]).resolve()
inventory = Path(sys.argv[2])
expected_file = Path(sys.argv[3])
paths = inventory.read_text(encoding="utf-8").splitlines()
expected = expected_file.read_text(encoding="utf-8").splitlines()
errors = []

if not paths:
    errors.append("inventory is empty")
if paths != sorted(paths):
    errors.append("inventory is not bytewise sorted")
if len(paths) != len(set(paths)):
    errors.append("inventory contains duplicate paths")
if paths != expected:
    missing = sorted(set(expected) - set(paths))
    extra = sorted(set(paths) - set(expected))
    if missing:
        errors.append("missing generated paths: " + ", ".join(missing))
    if extra:
        errors.append("unexpected generated paths: " + ", ".join(extra))

for value in paths:
    pure = PurePosixPath(value)
    parts = value.split("/")
    if pure.is_absolute() or value.startswith("~") or any(part in ("", ".", "..") for part in parts):
        errors.append(f"unsafe inventory path: {value}")
        continue
    target = bundle.joinpath(*parts)
    try:
        resolved = target.resolve(strict=True)
    except FileNotFoundError:
        errors.append(f"inventory path is missing: {value}")
        continue
    if os.path.commonpath((str(bundle), str(resolved))) != str(bundle):
        errors.append(f"inventory path escapes bundle root: {value}")
    elif not resolved.is_file():
        errors.append(f"inventory path is not a file: {value}")

if errors:
    sys.stderr.write("; ".join(errors))
    raise SystemExit(1)
PY
)"; then
    pass "$label ownership inventory is exact, sorted, safe, and complete"
  else
    fail "$label ownership inventory is invalid: $output"
  fi
}

validate_markdown_links() {
  # validate_markdown_links <bundle-root> <label>
  local bundle="$1" label="$2" output
  if output="$(python3 - "$bundle" "$EXPECTED_SKILLS_FILE" 2>&1 <<'PY'
from pathlib import Path
from urllib.parse import unquote, urlsplit
import os
import re
import sys

bundle = Path(sys.argv[1]).resolve()
expected = Path(sys.argv[2]).read_text(encoding="utf-8").splitlines()
errors = []
link_re = re.compile(r"\[[^\]]*\]\(([^)\s]+)")

for skill in expected:
    document = bundle / "skills" / skill / "SKILL.md"
    if not document.is_file():
        errors.append(f"missing SKILL.md: skills/{skill}/SKILL.md")
        continue
    text = document.read_text(encoding="utf-8")
    for raw in link_re.findall(text):
        value = raw.strip("<>")
        parsed = urlsplit(value)
        if parsed.scheme or parsed.netloc or value.startswith(("/", "#", "~")):
            continue
        relative = unquote(parsed.path)
        target = (document.parent / relative).resolve()
        if os.path.commonpath((str(bundle), str(target))) != str(bundle):
            errors.append(f"skills/{skill}/SKILL.md link escapes bundle: {value}")
        elif not target.exists():
            errors.append(f"skills/{skill}/SKILL.md has missing relative link: {value}")

if errors:
    sys.stderr.write("; ".join(errors))
    raise SystemExit(1)
PY
)"; then
    pass "$label skill-relative Markdown links all resolve inside the bundle"
  else
    fail "$label has broken skill-relative Markdown links: $output"
  fi
}

assert_bundle_contract() {
  # assert_bundle_contract <bundle-root> <label>
  local bundle="$1" label="$2" actual_skills resource

  assert_directory "$bundle/skills" "$label contains skills/"
  assert_directory "$bundle/references" "$label contains references/"
  assert_directory "$bundle/bin" "$label contains bin/"
  assert_file "$bundle/$INVENTORY_NAME" "$label contains $INVENTORY_NAME"

  if [ -d "$bundle/skills" ]; then
    actual_skills="$(find "$bundle/skills" -mindepth 1 -maxdepth 1 -type d -print | sed 's#.*/##' | LC_ALL=C sort)"
  else
    actual_skills=""
  fi
  assert_eq "$(cat "$EXPECTED_SKILLS_FILE")" "$actual_skills" "$label contains exactly the explicit nine skill directories"

  while IFS= read -r resource; do
    [ -n "$resource" ] || continue
    assert_file "$bundle/$resource" "$label contains manifest resource '$resource'"
    if [ -r "$SOURCE_BUNDLE/$resource" ] && [ -r "$bundle/$resource" ]; then
      if cmp -s "$SOURCE_BUNDLE/$resource" "$bundle/$resource"; then
        pass "$label resource '$resource' is byte-identical to source"
      else
        fail "$label resource '$resource' differs from its hand-maintained source"
      fi
    fi
  done < "$DECLARED_RESOURCES_FILE"

  # manifest 尚未存在時仍要精確指出已知缺口，不能因 declared set 為空而跳過。
  for resource in "${REQUIRED_RESOURCES[@]}"; do
    assert_file "$bundle/$resource" "$label contains required resource '$resource'"
  done

  validate_inventory "$bundle" "$label"
  validate_markdown_links "$bundle" "$label"
}

compare_bundle_files() {
  # compare_bundle_files <expected-bundle> <actual-bundle> <label>
  local expected_bundle="$1" actual_bundle="$2" label="$3" path mismatches=0

  if [ -r "$expected_bundle/$INVENTORY_NAME" ] && [ -r "$actual_bundle/$INVENTORY_NAME" ]; then
    if cmp -s "$expected_bundle/$INVENTORY_NAME" "$actual_bundle/$INVENTORY_NAME"; then
      pass "$label ownership inventories are byte-identical"
    else
      fail "$label ownership inventories differ"
    fi
  fi

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if [ ! -r "$expected_bundle/$path" ] || [ ! -r "$actual_bundle/$path" ]; then
      fail "$label cannot compare missing generated path '$path'"
      mismatches=$((mismatches + 1))
    elif ! cmp -s "$expected_bundle/$path" "$actual_bundle/$path"; then
      fail "$label generated path differs: $path"
      mismatches=$((mismatches + 1))
    fi
  done < "$EXPECTED_INVENTORY_FILE"

  [ "$mismatches" -ne 0 ] || pass "$label all inventory-owned files are byte-identical"
}

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
# Claude Code 版保留 PATH 與專用 manifest self-check；Codex 生成版改從 active
# SKILL.md 定位 bundled runtime，並以 native markers 判斷套件完整性。
SETUP_MIRROR="$MIRROR_DIR/codex-setup/SKILL.md"
if [ -r "$SETUP_MIRROR" ]; then
  # 掃描列表只放 Codex 生成版不得依賴的 Claude-only token 與過期報表契約。
  for token in "CLAUDE_PLUGIN_ROOT" ".claude-plugin" "/plugin update" "三項" "<Check 3"; do
    if grep -qF "$token" "$SETUP_MIRROR"; then
      fail "codex-setup mirror still references Claude-only '$token'"
    else
      pass "codex-setup mirror has no '$token' residue"
    fi
  done

  # Codex 本身有原生 plugin manifest；這裡只是不沿用 Claude Code 專用 self-check。
  if grep -qF "Claude Code 專用 manifest self-check 已由 Codex bundle 完整性檢查取代" "$SETUP_MIRROR"; then
    pass "codex-setup mirror explains the native bundle integrity replacement"
  else
    fail "codex-setup mirror does not explain its native bundle integrity check"
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

# ── 兩份 committed 完整 bundle ───────────────────────────────────
# .codex/ 是 repo-local Codex bundle；repo root 同時是 marketplace 安裝的
# native plugin payload。兩者都必須完整，不能再只有前者的 SKILL.md。
assert_bundle_contract "$DOT_CODEX_BUNDLE" ".codex bundle"
assert_bundle_contract "$ROOT_BUNDLE" "repository-root bundle"
compare_bundle_files "$DOT_CODEX_BUNDLE" "$ROOT_BUNDLE" "committed bundle parity"

# ── 核心：現存鏡像 == 重新生成的結果 ─────────────────────────────
# 這條同時證明兩件事：腳本冪等，且落在 repo 裡的產物確實是最新來源產生的。
# 任何人改了來源卻忘了重跑，或直接手改生成檔，這裡就會紅。
#
# 生成到暫存目錄再比對，不動 committed 產物——用 git status 判斷會在「產物尚未
# 提交」的首次執行必然誤報，等於在最該通過的時刻是紅的。
if [ -x "$GENERATOR" ]; then
  # mktemp 失敗時 tmp_out 會是空字串。generator 現在對空的 --output 值是 fatal
  # 而非 fallback,但呼叫端自己也要擋 —— 兩層都擋才不會有人改了其中一邊就破功。
  tmp_out="$TEST_TMP_ROOT/skill-only"
  if ! mkdir -p -- "$tmp_out"; then
    fail "could not create a temporary directory for fresh regeneration"
  else
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

      skill_only_count="$(find "$tmp_out" -type f -name SKILL.md | wc -l | tr -d '[:space:]')"
      assert_eq "${#EXPECTED[@]}" "$skill_only_count" "legacy --output still writes exactly nine SKILL.md files"
      assert_no_file "$tmp_out/$INVENTORY_NAME" "legacy --output remains skill-only (no bundle inventory)"
    else
      fail "generator exited non-zero when writing to a temp dir"
    fi
  fi
else
  fail "generator not executable: $GENERATOR"
fi

# ── 完整 --bundle-root：fresh parity、bounded cleanup、冪等 ───────────
if [ -x "$GENERATOR" ]; then
  FULL_BUNDLE="$TEST_TMP_ROOT/full bundle"
  if "$GENERATOR" --bundle-root "$FULL_BUNDLE" >/dev/null 2>&1; then
    pass "generator accepts --bundle-root for a path containing spaces"
    assert_bundle_contract "$FULL_BUNDLE" "fresh complete bundle"
    compare_bundle_files "$FULL_BUNDLE" "$DOT_CODEX_BUNDLE" "fresh bundle vs .codex"
    compare_bundle_files "$FULL_BUNDLE" "$ROOT_BUNDLE" "fresh bundle vs repository root"

    # 前一版 inventory 有、新 manifest 沒有，代表資源已從 generator 契約移除。
    # inventory 外另放一份檔案，重生後必須原封不動。
    if [ -r "$FULL_BUNDLE/$INVENTORY_NAME" ]; then
      mkdir -p -- "$FULL_BUNDLE/notes" "$FULL_BUNDLE/references" \
        "$FULL_BUNDLE/skills/codex-batch/references"
      printf '%s\n' 'keep-this-byte-for-byte' > "$FULL_BUNDLE/notes/unowned.txt"
      printf '%s\n' 'retired shared resource' > "$FULL_BUNDLE/references/retired-generated.txt"
      printf '%s\n' 'retired nested resource' > \
        "$FULL_BUNDLE/skills/codex-batch/references/retired-template.sh"
      {
        cat "$FULL_BUNDLE/$INVENTORY_NAME"
        printf '%s\n' \
          'references/retired-generated.txt' \
          'skills/codex-batch/references/retired-template.sh'
      } | LC_ALL=C sort -u > "$TEST_TMP_ROOT/prior-inventory"
      mv "$TEST_TMP_ROOT/prior-inventory" "$FULL_BUNDLE/$INVENTORY_NAME"

      if "$GENERATOR" --bundle-root "$FULL_BUNDLE" >/dev/null 2>&1; then
        assert_no_file "$FULL_BUNDLE/references/retired-generated.txt" \
          "rerun removes a stale shared resource owned by the prior inventory"
        assert_no_file "$FULL_BUNDLE/skills/codex-batch/references/retired-template.sh" \
          "rerun replaces an owned skill directory and removes stale nested resources"
        if [ "$(cat "$FULL_BUNDLE/notes/unowned.txt" 2>/dev/null)" = 'keep-this-byte-for-byte' ]; then
          pass "rerun preserves an unrelated file outside generated ownership"
        else
          fail "rerun changed or removed an unrelated file outside generated ownership"
        fi

        IDEMPOTENT_SNAPSHOT="$TEST_TMP_ROOT/idempotent snapshot"
        mkdir -p -- "$IDEMPOTENT_SNAPSHOT"
        cp -R "$FULL_BUNDLE/." "$IDEMPOTENT_SNAPSHOT/"
        if "$GENERATOR" --bundle-root "$FULL_BUNDLE" >/dev/null 2>&1; then
          if diff -r "$IDEMPOTENT_SNAPSHOT" "$FULL_BUNDLE" >/dev/null 2>&1; then
            pass "full bundle generation is byte-for-byte idempotent"
          else
            fail "full bundle generation changes files on an identical second run"
          fi
        else
          fail "generator exits non-zero on an identical second --bundle-root run"
        fi
      else
        fail "generator exits non-zero while cleaning a prior ownership inventory"
      fi
    else
      fail "ownership cleanup could not be exercised because the fresh inventory is missing"
    fi
  else
    fail "generator lacks a working --bundle-root complete-bundle interface"
  fi
fi

# ── 拒絕不安全的輸出目的地 ───────────────────────────────────────
# generator 會在輸出目錄內 rm -rf 孤兒。目的地被指到 repo root 時,那個迴圈會
# 把 .git/、plugins/、scripts/ 一併當孤兒 —— 破壞不可逆,所以必須擋在刪除之前。
if [ -x "$GENERATOR" ]; then
  assert_bundle_destination_rejected() {
    local raw="$1" expected_class="$2" label="$3" status=0 output
    output=$("$GENERATOR" --bundle-root "$raw" 2>&1) || status=$?
    if [ "$status" -eq 0 ]; then
      fail "generator refuses $label as a complete-bundle destination"
      return
    fi
    pass "generator refuses $label as a complete-bundle destination"
    assert_contains "$output" "$expected_class" \
      "generator names the rejected $label destination class"
  }

  assert_bundle_destination_rejected "/" "literal filesystem root" "filesystem root"

  if [ -n "${HOME:-}" ] && [ -d "$HOME" ]; then
    assert_bundle_destination_rejected "$HOME" "current-user home" "current-user home"
  else
    fail "generator current-user home rejection test has a resolvable HOME"
  fi

  assert_bundle_destination_rejected "" "--bundle-root was given an empty value" \
    "empty --bundle-root value"

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
