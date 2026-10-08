#!/usr/bin/env bash
# scripts/generate-codex-skills.sh — 由單一來源產出完整 Codex bundles。
#
# 為什麼需要這支腳本：
#   codex-pro 的 skill 以 Claude Code plugin 格式撰寫（plugins/codex-pro/skills/），
#   使用 Codex coding agent 的協作者讀不到那個命名空間。Codex 探索的專案級路徑是
#   .codex/skills/<name>/SKILL.md（openai/codex repo 自身即用此慣例）。
#
# 為什麼是生成而非手動維護兩份：
#   9 個 skill × 2 份，改一邊忘另一邊只是時間問題。單向生成 + tests/codex-skills-parity.sh
#   的 fresh-regeneration 比對，讓漂移在測試就紅，而不是等 Codex 使用者踩到。
#
# 為什麼不是 symlink：
#   兩種格式實測有內容差異（命名空間前綴、codex-setup 的 Claude-only 檢查），
#   symlink 前提不成立。
#
# 來源是唯一 source of truth，本腳本只讀不改來源。
#
# 用法：
#   scripts/generate-codex-skills.sh                     # 更新 .codex/ 與 repo root
#   scripts/generate-codex-skills.sh --bundle-root <dir> # 更新一個完整 bundle
#   scripts/generate-codex-skills.sh --output <dir>      # 舊版 skill-only 測試介面

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SOURCE_BUNDLE="$REPO_ROOT/plugins/codex-pro"
SOURCE_DIR="$SOURCE_BUNDLE/skills"
MANIFEST="$SCRIPT_DIR/codex-skills.manifest"
RESOURCE_MANIFEST="$SCRIPT_DIR/codex-bundle-resources.manifest"
DEFAULT_CODEX_BUNDLE="$REPO_ROOT/.codex"
INVENTORY_NAME=".codex-bundle-files"
GENERATED_MARKER="GENERATED FILE — DO NOT EDIT"

# ── 輸出目錄解析 ─────────────────────────────────────────────────
# 用具名 --output 而非位置參數。位置參數 + `${1:-default}` 有個安靜的坑：
# 傳入**空字串**時 `:-` 會當成「沒給」而 fallback 到真正的 .codex/skills/ ——
# 呼叫端只要 `mktemp -d` 失敗沒檢查，就會拿 committed 產物當暫存目錄來寫。
# 具名 flag 能把「沒給」與「給了空值」分開，後者是錯誤而非預設。
MODE="default"
DESTINATION=""
while [ $# -gt 0 ]; do
  case "$1" in
    --output)
      [ $# -ge 2 ] || { echo "FATAL: --output requires a directory argument" >&2; exit 2; }
      [ "$MODE" = "default" ] || { echo "FATAL: output modes are mutually exclusive" >&2; exit 2; }
      MODE="output"; DESTINATION="$2"; shift 2 ;;
    --output=*)
      [ "$MODE" = "default" ] || { echo "FATAL: output modes are mutually exclusive" >&2; exit 2; }
      MODE="output"; DESTINATION="${1#--output=}"; shift ;;
    --bundle-root)
      [ $# -ge 2 ] || { echo "FATAL: --bundle-root requires a directory argument" >&2; exit 2; }
      [ "$MODE" = "default" ] || { echo "FATAL: output modes are mutually exclusive" >&2; exit 2; }
      MODE="bundle"; DESTINATION="$2"; shift 2 ;;
    --bundle-root=*)
      [ "$MODE" = "default" ] || { echo "FATAL: output modes are mutually exclusive" >&2; exit 2; }
      MODE="bundle"; DESTINATION="${1#--bundle-root=}"; shift ;;
    -h|--help)
      sed -n '2,28p' "$0"; exit 0 ;;
    *)
      echo "FATAL: unknown argument '$1' (expected --bundle-root <dir> or --output <dir>)" >&2
      exit 2 ;;
  esac
done

if [ "$MODE" != "default" ] && [ -z "$DESTINATION" ]; then
  if [ "$MODE" = "bundle" ]; then flag="--bundle-root"; else flag="--output"; fi
  echo "FATAL: $flag was given an empty value." >&2
  echo "       Refusing to silently fall back to a committed destination." >&2
  exit 2
fi

# 目的地必須先存在或可建立，然後解析成絕對路徑再做安全檢查 ——
# 檢查 `.` 或 `../..` 這種相對寫法沒有意義，要比對的是它實際指到哪。

# 這支腳本會在目的地內 `rm -rf` 孤兒鏡像。目的地若被指到 repo root 或 /，
# 那個迴圈會把 .git/、plugins/、scripts/ 一併當成孤兒刪掉。破壞不可逆，
# 所以在任何刪除發生前先擋住明顯不安全的目的地。

if [ ! -d "$SOURCE_DIR" ]; then
  echo "FATAL: source skills dir missing: $SOURCE_DIR" >&2
  exit 2
fi

if [ ! -r "$MANIFEST" ]; then
  echo "FATAL: expected-skill manifest missing: $MANIFEST" >&2
  exit 2
fi

if [ ! -r "$RESOURCE_MANIFEST" ]; then
  echo "FATAL: bundle resource manifest missing: $RESOURCE_MANIFEST" >&2
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "FATAL: python3 not on PATH" >&2
  exit 2
fi

if ! WORK_ROOT="$(mktemp -d)" || [ -z "$WORK_ROOT" ] || [ ! -d "$WORK_ROOT" ]; then
  echo "FATAL: could not create generator staging directory" >&2
  exit 2
fi
trap 'rm -rf -- "$WORK_ROOT"' EXIT

# ── 預期 skill 集合（顯式契約）─────────────────────────────────
# 不從來源目錄枚舉就好 —— 那樣的話來源少一個 skill 時，generator 與 test 會
# 一起少一個然後全綠。manifest 是外部固定點，讓「集合變了」必須被明講。
declare -a EXPECTED=()
EXPECTED_SKILLS_FILE="$WORK_ROOT/expected-skills"
python3 - "$MANIFEST" > "$EXPECTED_SKILLS_FILE" <<'PY'
from pathlib import Path
import re
import sys

manifest = Path(sys.argv[1])
skills = []
errors = []
safe_name = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
for number, raw in enumerate(manifest.read_text(encoding="utf-8").splitlines(), 1):
    value = raw.split("#", 1)[0].strip()
    if not value:
        continue
    if not safe_name.fullmatch(value):
        errors.append(f"line {number}: unsafe skill name: {value!r}")
    skills.append(value)
if not skills:
    errors.append("manifest lists no skills")
if len(skills) != len(set(skills)):
    errors.append("manifest contains duplicate skill names")
if skills != sorted(skills):
    errors.append("skill names are not bytewise sorted")
if errors:
    sys.stderr.write("FATAL: invalid expected-skill manifest: " + "; ".join(errors) + "\n")
    raise SystemExit(3)
print(*skills, sep="\n")
PY
while IFS= read -r line; do
  [ -n "$line" ] && EXPECTED+=("$line")
done < "$EXPECTED_SKILLS_FILE"

if ! output="$(python3 - "$SOURCE_BUNDLE" "$EXPECTED_SKILLS_FILE" 2>&1 <<'PY'
from pathlib import Path
import os
import sys

source_bundle_path = Path(sys.argv[1])
expected = Path(sys.argv[2]).read_text(encoding="utf-8").splitlines()
errors = []

if source_bundle_path.is_symlink():
    errors.append("source bundle root is a symlink")

try:
    source_bundle = source_bundle_path.resolve(strict=True)
except OSError as exc:
    errors.append(f"source bundle cannot be resolved: {exc}")
    source_bundle = source_bundle_path.resolve(strict=False)

skills_root = source_bundle_path / "skills"
if skills_root.is_symlink():
    errors.append("source skills root is a symlink")
if not skills_root.is_dir():
    errors.append("source skills root is not a directory")

for skill in expected:
    skill_dir = skills_root / skill
    document = skill_dir / "SKILL.md"
    if skill_dir.is_symlink():
        errors.append(f"source skill directory is a symlink: {skill}")
        continue
    if not skill_dir.is_dir():
        errors.append(f"source skill directory is missing or not a directory: {skill}")
        continue
    if document.is_symlink():
        errors.append(f"source SKILL.md is a symlink: {skill}/SKILL.md")
        continue
    if not document.is_file():
        errors.append(f"source SKILL.md is missing or not a regular file: {skill}/SKILL.md")
        continue
    try:
        resolved = document.resolve(strict=True)
        with document.open("rb") as handle:
            handle.read(1)
    except OSError as exc:
        errors.append(f"source SKILL.md is unreadable: {skill}/SKILL.md: {exc}")
        continue
    if os.path.commonpath((str(source_bundle), str(resolved))) != str(source_bundle):
        errors.append(f"source SKILL.md escapes source bundle: {skill}/SKILL.md")

if errors:
    sys.stderr.write("; ".join(errors))
    raise SystemExit(1)
PY
)"; then
  echo "FATAL: unsafe source skill: $output" >&2
  echo "       Restore regular in-bundle skill directories and SKILL.md files." >&2
  exit 3
fi

# 來源有、manifest 沒有 → 同樣是錯的（新增 skill 忘了登記，Codex 使用者就叫不出來）。
while IFS= read -r d; do
  name="$(basename "$d")"
  found=0
  for skill in "${EXPECTED[@]}"; do [ "$skill" = "$name" ] && found=1 && break; done
  if [ "$found" -eq 0 ]; then
    echo "FATAL: source skill '$name' is not listed in $MANIFEST." >&2
    echo "       Add it to the manifest (deliberately) so the mirror set stays explicit." >&2
    exit 3
  fi
done < <(find "$SOURCE_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

# ── resource manifest 與來源樹必須精確雙向相等 ──────────────────
RESOURCE_MAPPINGS="$WORK_ROOT/resource-mappings"
RESOURCE_SOURCES="$WORK_ROOT/resource-sources"
RESOURCE_PATHS="$WORK_ROOT/resource-publish-paths"
ACTUAL_RESOURCES="$WORK_ROOT/actual-resources"

python3 - "$RESOURCE_MANIFEST" "$SOURCE_BUNDLE" "$RESOURCE_SOURCES" "$RESOURCE_PATHS" \
  "$EXPECTED_SKILLS_FILE" \
  > "$RESOURCE_MAPPINGS" <<'PY'
from pathlib import Path, PurePosixPath
import os
import sys

manifest = Path(sys.argv[1])
source = Path(sys.argv[2]).resolve()
expected_skills = set(Path(sys.argv[5]).read_text(encoding="utf-8").splitlines())
mappings = []
errors = []

for number, raw in enumerate(manifest.read_text(encoding="utf-8").splitlines(), 1):
    value = raw.split("#", 1)[0].strip()
    if not value:
        continue
    fields = value.split()
    if len(fields) == 1:
        source_path = publish_path = fields[0]
    elif len(fields) == 2:
        source_path, publish_path = fields
    else:
        errors.append(
            f"line {number}: expected '<source-path> [publish-path]': {value}"
        )
        continue

    for label, path, allowed_roots in (
        ("source", source_path, ("skills", "references", "runtime")),
        ("publish", publish_path, ("skills", "references", "bin")),
    ):
        pure = PurePosixPath(path)
        parts = path.split("/")
        if pure.is_absolute() or path.startswith("~"):
            errors.append(
                f"line {number}: absolute/home-relative {label} path is forbidden: {path}"
            )
        elif any(part in ("", ".", "..") for part in parts):
            errors.append(f"line {number}: {label} path is not normalized: {path}")
        elif parts[0] not in allowed_roots:
            roots = ", ".join(f"{root}/" for root in allowed_roots)
            errors.append(
                f"line {number}: {label} path must be under {roots}: {path}"
            )
        elif parts[0] == "skills" and (
            len(parts) < 3 or parts[1] not in expected_skills
        ):
            errors.append(
                f"line {number}: {label} skill resource must name a child file "
                f"under an expected skill: {path}"
            )
        elif parts[0] != "skills" and len(parts) < 2:
            errors.append(
                f"line {number}: {label} resource must name a child file: {path}"
            )
        elif path.endswith("/SKILL.md"):
            errors.append(
                f"line {number}: SKILL.md belongs to codex-skills.manifest: {path}"
            )

    target = source.joinpath(*source_path.split("/"))
    try:
        resolved = target.resolve(strict=True)
    except FileNotFoundError:
        errors.append(f"line {number}: source resource is missing: {source_path}")
    else:
        if os.path.commonpath((str(source), str(resolved))) != str(source):
            errors.append(
                f"line {number}: source resource escapes source bundle: {source_path}"
            )
        elif not resolved.is_file():
            errors.append(
                f"line {number}: source resource is not a file: {source_path}"
            )
    mappings.append((source_path, publish_path))

source_paths = [item[0] for item in mappings]
publish_paths = [item[1] for item in mappings]
if publish_paths != sorted(publish_paths):
    errors.append("resource publish paths are not bytewise sorted")
if len(source_paths) != len(set(source_paths)):
    errors.append("resource source paths contain duplicates")
if len(publish_paths) != len(set(publish_paths)):
    errors.append("resource publish paths contain duplicates")
if errors:
    sys.stderr.write("FATAL: invalid bundle resource manifest: " + "; ".join(errors) + "\n")
    raise SystemExit(3)
Path(sys.argv[3]).write_text("".join(f"{path}\n" for path in sorted(source_paths)))
Path(sys.argv[4]).write_text("".join(f"{path}\n" for path in publish_paths))
print(*(f"{source_path}\t{publish_path}" for source_path, publish_path in mappings), sep="\n")
PY

{
  # __pycache__ is bytecode Python leaves next to scripts it imports, not a resource: counting it
  # stopped the generator in the middle of a change (codex-pro#23 verify round 3, L16).
  find "$SOURCE_DIR" -type f ! -name SKILL.md ! -path '*/__pycache__/*' -print
  [ ! -d "$SOURCE_BUNDLE/references" ] || find "$SOURCE_BUNDLE/references" -type f ! -path '*/__pycache__/*' -print
  [ ! -d "$SOURCE_BUNDLE/runtime" ] || find "$SOURCE_BUNDLE/runtime" -type f ! -path '*/__pycache__/*' -print
} | sed "s#^$SOURCE_BUNDLE/##" | LC_ALL=C sort > "$ACTUAL_RESOURCES"

if ! cmp -s "$RESOURCE_SOURCES" "$ACTUAL_RESOURCES"; then
  echo "FATAL: $RESOURCE_MANIFEST does not exactly match publishable non-SKILL source files:" >&2
  diff -u "$RESOURCE_SOURCES" "$ACTUAL_RESOURCES" >&2 || true
  exit 3
fi

EXPECTED_INVENTORY="$WORK_ROOT/expected-inventory"
{
  for skill in "${EXPECTED[@]}"; do printf 'skills/%s/SKILL.md\n' "$skill"; done
  cat "$RESOURCE_PATHS"
} | LC_ALL=C sort -u > "$EXPECTED_INVENTORY"

resolve_destination() {
  python3 - "$1" <<'PY'
from pathlib import Path
import sys

value = sys.argv[1]
if "\n" in value or "\r" in value:
    raise SystemExit(2)
print(Path(value).expanduser().resolve(strict=False))
PY
}

validate_destination() {
  # validate_destination <raw-path> <bundle|output>
  local raw="$1" kind="$2" resolved canonical_home reason
  [ -n "$raw" ] || { echo "FATAL: empty $kind destination" >&2; return 2; }
  resolved="$(resolve_destination "$raw")" || {
    echo "FATAL: could not safely resolve $kind destination '$raw'" >&2
    return 2
  }
  canonical_home="$(resolve_destination "$HOME")" || return 2

  case "$resolved" in
    /)
      echo "FATAL: refusing literal filesystem root '/' as $kind destination" >&2
      return 2 ;;
    "$canonical_home")
      echo "FATAL: refusing current-user home '$resolved' as $kind destination" >&2
      return 2 ;;
  esac

  if [ "$kind" = "output" ] && [ "$resolved" = "$REPO_ROOT" ]; then
    echo "FATAL: refusing repository root as skill-only output destination" >&2
    return 2
  fi
  if [ -e "$resolved" ] && [ ! -d "$resolved" ]; then
    echo "FATAL: $kind destination exists but is not a directory: $resolved" >&2
    return 2
  fi

  # repo root 是刻意的 native bundle；除此特例外，目的地不得是來源或
  # 來源的祖先，也不得落在 .git/scripts/來源裡。
  if ! reason="$(python3 - "$resolved" "$kind" "$REPO_ROOT" "$SOURCE_BUNDLE" "$SCRIPT_DIR" 2>&1 <<'PY'
import os
import sys
from pathlib import Path

dest = os.path.realpath(sys.argv[1])
kind = sys.argv[2]
repo, source, scripts = map(os.path.realpath, sys.argv[3:])
if kind == "bundle" and dest == repo:
    raise SystemExit(0)

cursor = Path(dest)
while not cursor.exists() and cursor != cursor.parent:
    cursor = cursor.parent
if not cursor.is_dir():
    print(f"nearest existing ancestor is not a directory: {cursor}")
    raise SystemExit(1)

def within(path, parent):
    return os.path.commonpath((path, parent)) == parent

if within(source, dest):
    print("destination is an ancestor of the hand-maintained source")
    raise SystemExit(1)
for protected in (source, scripts, os.path.join(repo, ".git")):
    if within(dest, protected):
        print(f"destination is inside protected path {protected}")
        raise SystemExit(1)
PY
)"; then
    echo "FATAL: unsafe $kind destination '$resolved': $reason" >&2
    return 2
  fi

  printf '%s\n' "$resolved"
}

# ── 移除我們自己產生的孤兒鏡像 ───────────────────────────────────
# 只刪「帶 generated marker」的目錄 —— 那些才是本腳本擁有的產物。目的地若還有
# 別人手寫的 skill，本腳本無權處置：既不刪、也不假裝沒看到，直接失敗。
# 全刪 = 壟斷整個 .codex/skills/；靜默略過 = 之後 parity 比對莫名其妙紅。
validate_skill_output_state() {
  # validate_skill_output_state <skills-output-root>
  # Expected skill children are generator write targets even in legacy
  # skill-only mode. Validate the full set before orphan cleanup or writing so
  # one malicious symlink cannot redirect a later SKILL.md write outside root.
  local mirror_dir="$1" output
  if ! output="$(python3 - "$mirror_dir" "$EXPECTED_SKILLS_FILE" 2>&1 <<'PY'
from pathlib import Path
import os
import sys

root = Path(sys.argv[1]).resolve(strict=False)
skills = Path(sys.argv[2]).read_text(encoding="utf-8").splitlines()
errors = []
for skill in skills:
    target = root / skill
    document = target / "SKILL.md"
    if target.is_symlink():
        errors.append(f"expected skill directory is a symlink: {skill}")
        continue
    if target.exists() and not target.is_dir():
        errors.append(f"expected skill target is not a directory: {skill}")
        continue
    if document.is_symlink():
        errors.append(f"expected SKILL.md is a symlink: {skill}/SKILL.md")
    elif document.exists() and not document.is_file():
        errors.append(f"expected SKILL.md is not a regular file: {skill}/SKILL.md")
    for label, path in (("skill directory", target), ("SKILL.md parent", document.parent)):
        resolved = path.resolve(strict=False)
        if os.path.commonpath((str(root), str(resolved))) != str(root):
            errors.append(f"{label} escapes output root: {skill}")
if errors:
    sys.stderr.write("; ".join(errors))
    raise SystemExit(1)
PY
)"; then
    echo "FATAL: unsafe skill-only output state: $output" >&2
    return 3
  fi
}

generate_skill_only() {
  local MIRROR_DIR="$1" out_tmp orphan_list orphan_error d name

validate_skill_output_state "$MIRROR_DIR"

if [ -d "$MIRROR_DIR" ]; then
  orphan_list="$(mktemp "$WORK_ROOT/orphan-list.XXXXXX")"
  orphan_error="$(mktemp "$WORK_ROOT/orphan-error.XXXXXX")"
  if ! python3 - "$MIRROR_DIR" "$EXPECTED_SKILLS_FILE" "$GENERATED_MARKER" \
      > "$orphan_list" 2> "$orphan_error" <<'PY'
from pathlib import Path
import os
import sys

root = Path(sys.argv[1]).resolve(strict=True)
expected = set(Path(sys.argv[2]).read_text(encoding="utf-8").splitlines())
marker = sys.argv[3]
errors = []
orphans = []

with os.scandir(root) as entries:
    for entry in entries:
        if entry.name in expected or not entry.is_dir(follow_symlinks=False):
            continue
        if "\n" in entry.name or "\r" in entry.name:
            errors.append(f"orphan skill name contains a line break: {entry.name!r}")
            continue
        target = Path(entry.path)
        if target.parent.resolve(strict=True) != root:
            errors.append(f"orphan skill is not a direct child: {entry.name!r}")
            continue
        document = target / "SKILL.md"
        if document.is_symlink() or not document.is_file():
            errors.append(f"orphan skill has no regular generated marker file: {entry.name!r}")
            continue
        try:
            with document.open("r", encoding="utf-8", errors="replace") as handle:
                prefix = handle.read(4096)
        except OSError as exc:
            errors.append(f"orphan skill marker is unreadable: {entry.name!r}: {exc}")
            continue
        if marker not in prefix:
            errors.append(f"orphan skill has no generated marker: {entry.name!r}")
            continue
        orphans.append(os.fsencode(entry.path))

if errors:
    sys.stderr.write("; ".join(errors))
    raise SystemExit(1)
for path in sorted(orphans):
    sys.stdout.buffer.write(path + b"\0")
PY
  then
    echo "FATAL: unsafe orphan skill state: $(cat "$orphan_error")" >&2
    return 3
  fi

  while IFS= read -r -d '' d; do
    name="$(basename "$d")"
    echo "→ removing orphan mirror: $name"
    rm -rf -- "$d"
  done < "$orphan_list"
fi

# ── 生成 ─────────────────────────────────────────────────────────
generated=0
for skill in "${EXPECTED[@]}"; do
  src="$SOURCE_DIR/$skill/SKILL.md"
  out_dir="$MIRROR_DIR/$skill"
  mkdir -p -- "$out_dir"
  out_tmp="$(mktemp "$out_dir/.SKILL.md.tmp.XXXXXX")" || {
    echo "FATAL: could not create atomic SKILL.md staging file in $out_dir" >&2
    return 3
  }

  if ! SKILL_NAME="$skill" python3 - "$src" "$out_tmp" <<'PY'
import os, re, sys

src_path, out_path = sys.argv[1], sys.argv[2]
skill = os.environ["SKILL_NAME"]
text = open(src_path, encoding="utf-8").read()


def fatal(msg):
    sys.stderr.write(f"FATAL [{skill}]: {msg}\n")
    sys.exit(3)


def sub_exact(pattern, repl, count, why, flags=0):
    """替換並斷言命中次數。

    只驗「有沒有改到東西」是不夠的 —— 來源新增了第二處同樣的東西時，舊的那處
    仍然命中，檢查就通過了，而新的那處靜默留在產物裡。所以每條規則都要說出
    自己預期命中幾次，數量不符即失敗。
    """
    global text
    new, n = re.subn(pattern, lambda _: repl, text, flags=flags)
    if n != count:
        fatal(f"{why}: expected {count} match(es), got {n}. Source structure changed; "
              f"update the rule in scripts/generate-codex-skills.sh.")
    text = new


# ── 命名空間改寫 ──────────────────────────────────────────────
# Claude Code 用 /<plugin>:<skill>，Codex 用 $<skill>。這是兩個 harness 的
# 命令語法差異，不是內容差異——其餘散文一字不動。
#
# glob 形式先處理，且**不能**併進具名的 regex。`/codex-pro:*` 若走 `$\1` 會
# 產出 `$*` —— 那既不是 Codex 的 skill 命名空間，還會被讀成 shell 的 `$*`。
# 本 repo 的 skill 一律有 codex- 前綴，所以 glob 的正確對應是 `$codex-*`。
text = text.replace("/codex-pro:*", "$codex-*")
text = re.sub(r"/codex-pro:([a-z0-9-]+)", r"$\1", text)

if "/codex-pro:" in text:
    fatal("Claude namespace '/codex-pro:' still present after rewrite.")

# ── Codex runtime resolver ────────────────────────────────────
# 一般 skill shell 沒有穩定的 plugin-root 環境變數。Codex 會在載入 skill 時
# 告知 active SKILL.md 的絕對路徑，所以生成版從那個位置往上兩層取得 bundle。
# 有 native marker 時 runtime 損壞必須 fail-closed；只有舊式無 marker 鏡像才
# 能保留 PATH 相容路徑。
PRODUCER_SKILLS = {
    "codex-review",
    "codex-adversarial-review",
    "codex-rescue",
}
# visual-xval (#23) sends every request from scripts/xval.py, which reads the runtime
# from files in its run directory. Those files are written inside the resolver's own
# code block: a later block starts a fresh shell and would not see its variables.
RUN_DIR_PRODUCER_SKILLS = {
    "codex-visual-xval",
}

if skill in PRODUCER_SKILLS or skill in RUN_DIR_PRODUCER_SKILLS:
    PRODUCER_RUNTIME_SECTION = r"""### Step 4.2: Resolve bundled Codex runtime

Codex 載入本 skill 時會提供 active `SKILL.md` 的絕對路徑。先以該實際路徑的
目錄設定 `SKILL_DIR`；不得從目前工作目錄猜測。接著以前景、同步方式執行：

```bash
BUNDLE_ROOT="$(cd "$SKILL_DIR/../.." && pwd -P)"
CODEX_CALL="$BUNDLE_ROOT/bin/codex-pro-call"
CODEX_RUNTIME_SOURCE="bundled"
CODEX_RUNTIME_ERROR=""
CODEX_RUNTIME_DETAIL=""

if [ ! -L "$BUNDLE_ROOT/bin" ] && [ -d "$BUNDLE_ROOT/bin" ] && [ ! -L "$CODEX_CALL" ] && [ -f "$CODEX_CALL" ] && [ -x "$CODEX_CALL" ]; then
  CODEX_RUNTIME_STATUS=0
  CODEX_RUNTIME_CHECK=$("$CODEX_CALL" --check 2>&1) || CODEX_RUNTIME_STATUS=$?
  if [ "$CODEX_RUNTIME_STATUS" -ne 0 ]; then
    CODEX_RUNTIME_DETAIL="$CODEX_RUNTIME_CHECK"
    case "$CODEX_RUNTIME_CHECK" in
      error=unsupported_platform*|error=swift_missing*)
        CODEX_RUNTIME_ERROR="runtime_unavailable"
        ;;
      error=runtime_missing*|error=runtime_not_executable*|error=hash_mismatch*)
        CODEX_RUNTIME_ERROR="package_corruption"
        ;;
      *)
        CODEX_RUNTIME_ERROR="runtime_unavailable"
        ;;
    esac
  fi
elif [ -e "$BUNDLE_ROOT/.codex-plugin/plugin.json" ] \
    || [ -L "$BUNDLE_ROOT/.codex-plugin/plugin.json" ] \
    || [ -e "$BUNDLE_ROOT/.codex-bundle-files" ] \
    || [ -L "$BUNDLE_ROOT/.codex-bundle-files" ]; then
  CODEX_RUNTIME_ERROR="package_corruption"
  CODEX_RUNTIME_DETAIL="wrapper_missing_or_not_executable path=$CODEX_CALL"
elif legacy_codex_call=$(command -v codex-call 2>/dev/null); then
  CODEX_CALL="$legacy_codex_call"
  CODEX_RUNTIME_SOURCE="legacy PATH fallback"
  printf 'warning=legacy_path_fallback runtime=%s\n' "$CODEX_CALL" >&2
else
  CODEX_RUNTIME_ERROR="runtime_unavailable"
  CODEX_RUNTIME_DETAIL="no_bundled_or_legacy_runtime remediation=run_codex_setup"
fi

if [ -n "$CODEX_RUNTIME_ERROR" ]; then
  printf 'error=%s detail=%s\n' "$CODEX_RUNTIME_ERROR" "$CODEX_RUNTIME_DETAIL" >&2
fi
```

若 bundled wrapper 回報 `unsupported_platform` 或 `swift_missing`，producer 在讀取
OAuth 或連網前停止；`$codex-status`、`$codex-result`、`$codex-config` 與
`$codex-cancel` 仍可使用。含 native manifest 或 ownership inventory 的 bundle
若缺 wrapper，必須回報 `error=package_corruption`，不得改走 PATH。

若 `CODEX_RUNTIME_ERROR` 非空，不得執行 `$CODEX_CALL`、讀取 OAuth 或存取網路；
直接進入 Step 5，照該 skill 的既有 result schema 寫入結構化 failure result。
`package_corruption` 與 `runtime_unavailable` 都不 retry。

### Step 4.3: codex-call invocation"""

    if skill in RUN_DIR_PRODUCER_SKILLS:
        runtime_files = (
            "\nprintf '%s\\n' \"$CODEX_RUNTIME_ERROR\" \"$CODEX_RUNTIME_DETAIL\" > \"$RUN/runtime_error.txt\""
            "\nif [ -z \"$CODEX_RUNTIME_ERROR\" ]; then"
            "\n  printf '%s\\n' \"$CODEX_CALL\" > \"$RUN/runtime.txt\""
            "\nfi"
        )
        anchor = "\n```\n\n若 bundled wrapper"
        if PRODUCER_RUNTIME_SECTION.count(anchor) != 1:
            fatal("run-dir producer: resolver block end not found")
        sub_exact(r"### Step 4\.2: codex-call invocation",
                  PRODUCER_RUNTIME_SECTION.replace(anchor, runtime_files + anchor), 1,
                  "run-dir producer invocation heading")
        sub_exact(r"```bash\nprintf '%s\\n' \"\$\{CODEX_RUNTIME_ERROR:-\}\".*?```\n\n", "", 1,
                  "run-dir producer: source runtime-file block", flags=re.DOTALL)
        if 'CODEX_CALL="$(command -v codex-call)"' in text:
            fatal("run-dir producer: the source PATH lookup of codex-call remains in the native skill")
    else:
        sub_exact(r"### Step 4\.2: codex-call invocation", PRODUCER_RUNTIME_SECTION, 1,
                  "producer invocation heading")
        old_invocation = "codex-call \\\n"
        new_invocation = 'if [ -z "$CODEX_RUNTIME_ERROR" ]; then\n  "$CODEX_CALL" \\\n'
        if text.count(old_invocation) != 1:
            fatal("producer command: expected exactly one bare codex-call invocation")
        text = text.replace(old_invocation, new_invocation)
        invocation_start = text.index(new_invocation)
        invocation_end = text.find("\n```", invocation_start)
        if invocation_end < 0:
            fatal("producer command: closing code fence not found")
        text = text[:invocation_end] + "\nfi" + text[invocation_end:]

    if skill == "codex-rescue":
        runtime_failure_rows = """| native preflight：套件缺檔、不可執行或 hash mismatch | `package_corruption` | unclear | 「codex-pro 套件損壞。重新安裝 plugin。**不會自動 retry**。」 |
| native preflight：unsupported platform、缺 Swift 或 runtime unavailable | `runtime_unavailable` | unclear | 「Producer runtime 不可用。跑 $codex-setup 查看 remediation；consumer skills 仍可使用。**不會自動 retry**。」 |"""
    elif skill == "codex-adversarial-review":
        runtime_failure_rows = """| native preflight：套件缺檔、不可執行或 hash mismatch | `package_corruption` | 「codex-pro 套件損壞。重新安裝 plugin。**不會自動 retry**。」 |
| native preflight：unsupported platform、缺 Swift 或 runtime unavailable | `runtime_unavailable` | 「Producer runtime 不可用。跑 $codex-setup 查看 remediation；consumer skills 仍可使用。**不會自動 retry**。」 |"""
    else:
        runtime_failure_rows = """| native preflight：套件缺檔、不可執行或 hash mismatch | `package_corruption` | 「codex-pro 套件損壞。重新安裝 plugin。**不會自動 retry**。」 |
| native preflight：unsupported platform、缺 Swift 或 runtime unavailable | `runtime_unavailable` | 「Producer runtime 不可用。跑 $codex-setup 查看 remediation；consumer skills 仍可使用。**不會自動 retry**。」 |"""

    runtime_failure_contract = """

native preflight failure 的 result body 必須另寫一行
`Runtime preflight detail: <sanitized detail>`，其值來自 `$CODEX_RUNTIME_DETAIL`。
寫入前把 CR／LF／TAB 改為空白、移除其他 control characters，並截到 500 個字元；
不得把未清理或未截斷的 detail 放進 YAML frontmatter。
"""
    if skill in RUN_DIR_PRODUCER_SKILLS:
        # visual-xval's result file shows no text from outside xval (#23 verify round 9): the
        # runtime check's detail stays in the run directory, and the line says where.
        runtime_failure_contract = """

native preflight failure 的 result body 另寫一行 `Runtime preflight detail:`，但不帶 detail 本身：
`$CODEX_RUNTIME_DETAIL` 是 runtime 檢查自己的文字，只留在 run 目錄的 `runtime_error.txt`（跑過 `ask` 時也在
`error.json`），這一行只說它保存在哪裡；它也不得放進 YAML frontmatter。跳過 `ask` 時，`result` 從
`runtime_error.txt` 的第一行取錯誤類別寫進 frontmatter（只取類別）。
"""
    sub_exact(r"(?=\n\n\*\*所有 failure 仍寫 result file\*\*)",
              "\n" + runtime_failure_rows + runtime_failure_contract, 1,
              "producer native preflight failure rows")
    text, error_enum_count = re.subn(
        r"error: <([^>\n]+)>",
        lambda match: (
            f"error: <{match.group(1)} | runtime_unavailable | package_corruption>"
        ),
        text,
    )
    if error_enum_count != 1:
        fatal("producer result error enum: expected exactly one frontmatter example")

# codex-setup 需要完整替換 Claude Code 的 PATH／manifest 檢查與報表，來源檔則
# 完全維持原契約。生成版的 wrapper --check 只做平台、Swift、mode 與 hash 驗證，
# 不執行 snapshot、不讀 OAuth、不連網。
if skill == "codex-setup":
    SETUP_RUNTIME_SECTION = r"""### Check 2: Codex producer runtime

Codex 載入本 skill 時會提供 active `SKILL.md` 的絕對路徑。先以該實際路徑的
目錄設定 `SKILL_DIR`，不得從目前工作目錄推測，再執行以下純 read-only Bash：

```bash
BUNDLE_ROOT="$(cd "$SKILL_DIR/../.." && pwd -P)"
wrapper="$BUNDLE_ROOT/bin/codex-pro-call"

if [ ! -L "$BUNDLE_ROOT/bin" ] && [ -d "$BUNDLE_ROOT/bin" ] && [ ! -L "$wrapper" ] && [ -f "$wrapper" ] && [ -x "$wrapper" ]; then
  wrapper_status=0
  wrapper_output=$("$wrapper" --check 2>&1) || wrapper_status=$?
  if [ "$wrapper_status" -eq 0 ]; then
    echo "bundled path=$wrapper $wrapper_output"
  else
    case "$wrapper_output" in
      error=unsupported_platform*|error=swift_missing*)
        echo "unavailable source=bundled $wrapper_output"
        ;;
      *)
        echo "package corruption source=bundled $wrapper_output"
        ;;
    esac
  fi
elif [ -e "$BUNDLE_ROOT/.codex-plugin/plugin.json" ] \
    || [ -L "$BUNDLE_ROOT/.codex-plugin/plugin.json" ] \
    || [ -e "$BUNDLE_ROOT/.codex-bundle-files" ] \
    || [ -L "$BUNDLE_ROOT/.codex-bundle-files" ]; then
  echo "package corruption path=$wrapper error=wrapper_missing_or_not_executable"
elif legacy_codex_call=$(command -v codex-call 2>/dev/null); then
  echo "legacy PATH fallback path=$legacy_codex_call"
else
  echo "unavailable error=runtime_unavailable"
fi
```

`--check` 不執行 runtime snapshot、不讀取或修改 OAuth，也不存取網路。依輸出判定：

| 輸出 | Producer Status | Detail | Remediation |
|------|-----------------|--------|-------------|
| `bundled path=... ok runtime=...` | ✓ | bundled runtime、Swift 與 SHA-256 完整 | N/A |
| `legacy PATH fallback path=...` | ⚠ | 舊式無 marker 鏡像透過 PATH 相容 | 更新或重新安裝 codex-pro 原生 plugin |
| `package corruption ...` | ✗ | 原生套件缺檔、權限或完整性驗證失敗 | 重新安裝 codex-pro plugin；不得改走 PATH |
| `unavailable ... error=unsupported_platform` | ✗ | producer 僅支援 macOS | consumer skills 仍可使用 |
| `unavailable ... error=swift_missing` | ✗ | 找不到可執行的 Swift compiler | 安裝或修復 Xcode Command Line Tools |
| `unavailable error=runtime_unavailable` | ✗ | 無 bundled runtime，也無 legacy PATH 相容路徑 | 更新或重新安裝 codex-pro |

> **Claude Code 專用 manifest self-check 已由 Codex bundle 完整性檢查取代。**
>
> producer（review、adversarial-review、rescue、visual-xval）需要 macOS 與 Xcode Command Line
> Tools Swift；consumer（`$codex-status`、`$codex-result`、`$codex-config`、
> `$codex-cancel`）只讀本機檔案，在 producer unavailable 時仍可使用。
"""

    SETUP_REPORT_SECTION = """## Readiness Report 輸出

兩項檢查完成後，把 OAuth、producer runtime 與 consumer availability 組裝成 4 欄
markdown 表格直接回傳給使用者：

```
| Check | Status | Detail | Remediation |
|-------|--------|--------|-------------|
| OAuth token | <Check 1 Status> | <Check 1 Detail> | <Check 1 Remediation 或 N/A> |
| Producer runtime | <Check 2 Producer Status> | <Check 2 Detail> | <Check 2 Remediation 或 N/A> |
| Consumer skills | ✓ | `$codex-status`、`$codex-result`、`$codex-config`、`$codex-cancel` 可使用 | N/A |
```

表格後空一行，依以下規則輸出總結句：

- OAuth 與 Producer runtime 皆為 ✓ → `All checks passed — codex-pro ready.`
- Producer runtime 為 ✗ 或 ⚠ → 明確回報 producer unavailable 或 degraded，並再次列出仍可使用的四個 consumer skills。
- OAuth 為 ✗ 或 ⚠ → 只回報 remediation，不執行 `codex login` 或變更權限。
"""

    sub_exact(r"檢查 Codex OAuth token、codex-call wrapper、plugin manifest。",
              "檢查 Codex OAuth token、bundled producer runtime，並分別回報 consumer skills。",
              1, "setup description")
    sub_exact(r"按順序執行以下三項檢查", "按順序執行以下兩項檢查", 1,
              "setup execution-flow count")
    sub_exact(r"### Check 2: codex-call wrapper PATH\n.*?(?=\n## Readiness Report 輸出)",
              SETUP_RUNTIME_SECTION, 1, "setup runtime and manifest sections",
              flags=re.DOTALL)
    sub_exact(r"## Readiness Report 輸出\n.*?(?=\n## 結束時的約束)",
              SETUP_REPORT_SECTION, 1, "setup readiness report", flags=re.DOTALL)

    for token in ("CLAUDE_PLUGIN_ROOT", ".claude-plugin", "/plugin update",
                  "CODEX_PLUGIN_ROOT", "CODEX_SKILL_ROOT", "CODEX_HOME",
                  "~/.codex/plugins/cache", "三項", "<Check 3"):
        if token in text:
            fatal(f"unsupported resolver residue '{token}' remains in generated setup")
    for token in ("SKILL_DIR", "BUNDLE_ROOT", "bin/codex-pro-call", "--check",
                  "legacy PATH fallback", "package corruption", "unsupported_platform",
                  "swift_missing", "$codex-status", "$codex-result", "$codex-config",
                  "$codex-cancel"):
        if token not in text:
            fatal(f"generated setup contract is missing '{token}'")

# ── generated marker ─────────────────────────────────────────
# 插在 frontmatter 之後、body 之前——frontmatter 前加註解會破壞 YAML 解析。
marker = (
    "<!-- GENERATED FILE — DO NOT EDIT.\n"
    f"     Source: plugins/codex-pro/skills/{skill}/SKILL.md\n"
    "     Regenerate: scripts/generate-codex-skills.sh\n"
    "     Drift is caught by tests/codex-skills-parity.sh -->\n"
)

# 行錨定，不是 `text.split("---\n", 2)`。後者比對的是任意子字串，所以某個欄位
# 的值只要以三個 dash 結尾（`description: foo---`），就會被當成 frontmatter 的
# 結束位置，marker 插進 YAML 中間。用 \A 與行首錨點讓分隔線只能是「獨立一行」。
m = re.match(r"\A---\n(.*?\n)---\n", text, flags=re.DOTALL)
if not m:
    fatal(f"{src_path} has no parseable frontmatter (expected leading '---' line).")

text = "---\n" + m.group(1) + "---\n" + marker + text[m.end():]

open(out_path, "w", encoding="utf-8").write(text)
PY
  then
    rm -f -- "$out_tmp"
    return 3
  fi
  chmod 0644 "$out_tmp"
  mv -f -- "$out_tmp" "$out_dir/SKILL.md"

  generated=$((generated + 1))
done

echo "✓ generated $generated Codex skill mirror(s) → ${MIRROR_DIR#"$REPO_ROOT"/}"
}

validate_bundle_state() {
  # 所有驗證都在 cleanup 前完成。這個函式只讀 bundle 的明確 marker /
  # inventory，不枚舉 repo root 的其他內容。
  local bundle="$1" prior="$2" skill subtree output

  for subtree in skills references bin; do
    if [ -L "$bundle/$subtree" ]; then
      echo "FATAL: bundle subtree must not be a symlink: $bundle/$subtree" >&2
      return 3
    elif [ -e "$bundle/$subtree" ] && [ ! -d "$bundle/$subtree" ]; then
      echo "FATAL: bundle subtree must be a directory: $bundle/$subtree" >&2
      return 3
    fi
  done

  for skill in "${EXPECTED[@]}"; do
    if [ -e "$bundle/skills/$skill" ] || [ -L "$bundle/skills/$skill" ]; then
      if [ -L "$bundle/skills/$skill" ] || [ ! -d "$bundle/skills/$skill" ] || \
         [ -L "$bundle/skills/$skill/SKILL.md" ] || \
         [ ! -f "$bundle/skills/$skill/SKILL.md" ] || \
         ! grep -qF "$GENERATED_MARKER" "$bundle/skills/$skill/SKILL.md"; then
        echo "FATAL: refusing to replace non-generated skill directory: $bundle/skills/$skill" >&2
        return 3
      fi
    fi
  done

  : > "$prior"
  if [ -e "$bundle/$INVENTORY_NAME" ] || [ -L "$bundle/$INVENTORY_NAME" ]; then
    if [ -L "$bundle/$INVENTORY_NAME" ] || [ ! -f "$bundle/$INVENTORY_NAME" ]; then
      echo "FATAL: bundle inventory must be a regular file: $bundle/$INVENTORY_NAME" >&2
      return 3
    fi
    if ! output="$(python3 - "$bundle" "$bundle/$INVENTORY_NAME" 2>&1 > "$prior" <<'PY'
from pathlib import Path, PurePosixPath
import os
import sys

bundle = Path(sys.argv[1]).resolve()
inventory = Path(sys.argv[2])
paths = inventory.read_text(encoding="utf-8").splitlines()
errors = []

if paths != sorted(paths):
    errors.append("inventory is not bytewise sorted")
if len(paths) != len(set(paths)):
    errors.append("inventory contains duplicate paths")
for value in paths:
    pure = PurePosixPath(value)
    parts = value.split("/")
    if pure.is_absolute() or value.startswith("~") or any(part in ("", ".", "..") for part in parts):
        errors.append(f"unsafe inventory path: {value}")
        continue
    if parts[0] not in ("skills", "references", "bin") or len(parts) < 2:
        errors.append(f"inventory path is outside generated subtrees: {value}")
        continue
    target = bundle.joinpath(*parts)
    parent = target.parent
    resolved_parent = parent.resolve(strict=False)
    if resolved_parent != parent:
        errors.append(f"unsafe inventory parent contains a symbolic link: {value}")
        continue
    resolved = target.resolve(strict=False)
    if os.path.commonpath((str(bundle), str(resolved))) != str(bundle):
        errors.append(f"inventory path escapes bundle root: {value}")
    elif target.exists() and target.is_dir():
        errors.append(f"inventory path unexpectedly names a directory: {value}")

if errors:
    sys.stderr.write("; ".join(errors))
    raise SystemExit(1)
print(*paths, sep="\n")
PY
)"; then
      echo "FATAL: unsafe prior ownership inventory: $output" >&2
      return 3
    fi
  fi

  # 新資源的 parent 若經 symlink 跳出 bundle，cp/mkdir 也可能寫到外部；
  # 在任何刪除或寫入前一次檢查所有目標。
  if ! output="$(python3 - "$bundle" "$EXPECTED_INVENTORY" 2>&1 <<'PY'
from pathlib import Path
import os
import sys

bundle = Path(sys.argv[1]).resolve()
errors = []
for value in Path(sys.argv[2]).read_text(encoding="utf-8").splitlines():
    target = bundle.joinpath(*value.split("/"))
    parent = target.parent
    resolved_parent = parent.resolve(strict=False)
    if resolved_parent != parent:
        errors.append(f"generated target parent contains a symbolic link: {value}")
    elif os.path.commonpath((str(bundle), str(resolved_parent))) != str(bundle):
        errors.append(f"generated target parent escapes bundle: {value}")
    elif not value.startswith("skills/") and target.exists() and target.is_dir():
        errors.append(f"generated resource target is a directory: {value}")
if errors:
    sys.stderr.write("; ".join(errors))
    raise SystemExit(1)
PY
)"; then
    echo "FATAL: unsafe generated target: $output" >&2
    return 3
  fi
}

stage_complete_bundle() {
  local stage="$1" source_resource publish_resource
  mkdir -p -- "$stage/skills" "$stage/references" "$stage/bin"
  generate_skill_only "$stage/skills" >/dev/null

  while IFS=$'\t' read -r source_resource publish_resource; do
    [ -n "$source_resource" ] && [ -n "$publish_resource" ] || continue
    mkdir -p -- "$(dirname "$stage/$publish_resource")"
    cp -p -- "$SOURCE_BUNDLE/$source_resource" "$stage/$publish_resource"
  done < "$RESOURCE_MAPPINGS"
  validate_staged_bundle "$stage"
  cp -- "$EXPECTED_INVENTORY" "$stage/$INVENTORY_NAME"
}

validate_staged_bundle() {
  # The ownership inventory is a claim about regular files, not merely a list
  # supplied by the same manifest that drove staging. Enumerate the staged tree
  # independently so a malformed publish path cannot turn a directory into an
  # inventory entry or smuggle an undeclared descendant into the bundle.
  local stage="$1" output
  if ! output="$(python3 - "$stage" "$EXPECTED_INVENTORY" 2>&1 <<'PY'
from pathlib import Path
import sys

stage = Path(sys.argv[1])
expected = set(Path(sys.argv[2]).read_text(encoding="utf-8").splitlines())
actual = set()
errors = []

for root_name in ("skills", "references", "bin"):
    root = stage / root_name
    for path in root.rglob("*"):
        relative = path.relative_to(stage).as_posix()
        if path.is_symlink():
            errors.append(f"staged generated path is a symlink: {relative}")
        elif path.is_file():
            actual.add(relative)
        elif not path.is_dir():
            errors.append(f"staged generated path is not a regular file: {relative}")

missing = sorted(expected - actual)
extra = sorted(actual - expected)
if missing:
    errors.append("missing staged generated files: " + ", ".join(missing))
if extra:
    errors.append("unexpected staged generated files: " + ", ".join(extra))

for value in sorted(expected):
    target = stage.joinpath(*value.split("/"))
    if target.exists() and (target.is_symlink() or not target.is_file()):
        errors.append(f"staged inventory path is not a regular file: {value}")

if errors:
    sys.stderr.write("; ".join(errors))
    raise SystemExit(1)
PY
)"; then
    echo "FATAL: staged bundle does not exactly match ownership inventory: $output" >&2
    return 3
  fi
}

prepare_complete_bundle() {
  local bundle="$1" index="$2" stage prior
  stage="$WORK_ROOT/stage-$index"
  prior="$WORK_ROOT/prior-$index"
  stage_complete_bundle "$stage"
  validate_bundle_state "$bundle" "$prior"
}

apply_prepared_bundle() {
  local bundle="$1" index="$2" stage prior resource old target skill inventory_tmp
  stage="$WORK_ROOT/stage-$index"
  prior="$WORK_ROOT/prior-$index"

  # 從這裡才開始 mutation。每一個刪除目標都來自「舊 inventory - 新
  # inventory」，或是已以 generated marker 驗證的 expected skill。
  mkdir -p -- "$bundle/skills" "$bundle/references" "$bundle/bin"

  while IFS= read -r old; do
    [ -n "$old" ] || continue
    grep -Fqx "$old" "$EXPECTED_INVENTORY" && continue
    target="$bundle/$old"
    if [ -e "$target" ] || [ -L "$target" ]; then
      if [ -d "$target" ] && [ ! -L "$target" ]; then
        echo "FATAL: prior inventory path unexpectedly became a directory: $old" >&2
        return 3
      fi
      rm -f -- "$target"
    fi
  done < "$prior"

  for skill in "${EXPECTED[@]}"; do
    target="$bundle/skills/$skill"
    if [ -e "$target" ]; then rm -rf -- "$target"; fi
    mv -- "$stage/skills/$skill" "$target"
  done

  while IFS= read -r resource; do
    [ -n "$resource" ] || continue
    case "$resource" in skills/*) continue ;; esac
    target="$bundle/$resource"
    mkdir -p -- "$(dirname "$target")"
    if [ -e "$target" ] || [ -L "$target" ]; then
      [ ! -d "$target" ] || { echo "FATAL: generated resource target is a directory: $resource" >&2; return 3; }
      rm -f -- "$target"
    fi
    cp -p -- "$stage/$resource" "$target"
  done < "$RESOURCE_PATHS"

  inventory_tmp="$(mktemp "$bundle/.codex-bundle-files.tmp.XXXXXX")"
  cp -- "$stage/$INVENTORY_NAME" "$inventory_tmp"
  mv -f -- "$inventory_tmp" "$bundle/$INVENTORY_NAME"
  echo "✓ generated complete Codex bundle → $bundle"
}

# ── 目的地在所有 source / manifest 檢查完成後才解析，並在任何
# cleanup 前一次全部驗證。無參數的兩個 committed destinations 也先同時驗證。
case "$MODE" in
  output)
    OUTPUT_DIR="$(validate_destination "$DESTINATION" output)"
    validate_skill_output_state "$OUTPUT_DIR"
    mkdir -p -- "$OUTPUT_DIR"
    generate_skill_only "$OUTPUT_DIR"
    ;;
  bundle)
    BUNDLE_DIR="$(validate_destination "$DESTINATION" bundle)"
    prepare_complete_bundle "$BUNDLE_DIR" 1
    apply_prepared_bundle "$BUNDLE_DIR" 1
    ;;
  default)
    CODEX_BUNDLE_DIR="$(validate_destination "$DEFAULT_CODEX_BUNDLE" bundle)"
    ROOT_BUNDLE_DIR="$(validate_destination "$REPO_ROOT" bundle)"
    prepare_complete_bundle "$CODEX_BUNDLE_DIR" 1
    prepare_complete_bundle "$ROOT_BUNDLE_DIR" 2
    apply_prepared_bundle "$CODEX_BUNDLE_DIR" 1
    apply_prepared_bundle "$ROOT_BUNDLE_DIR" 2
    ;;
esac
