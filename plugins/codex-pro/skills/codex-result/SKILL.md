---
name: codex-result
description: |
  顯示 .codex-pro/ 內特定 producer result file 的完整內容（frontmatter + body）。Read-only consumer category — 純檔案讀取、無 Codex HTTP wrapper 呼叫、無 subprocess、無 file mutation。
  與 status（list 性質）區隔 — result 是 detail 性質、檢視單一 result 的完整 markdown 內容。三 selection mode：(a) 位置 <filename> / (b) --latest <skill> / (c) --latest 無 arg。
  Selection 決勝權為 filename lexical order（filename ISO8601 prefix 是 producer 寫檔時 atomic 決定的時序 source of truth、不諮詢 filesystem mtime、也不諮詢 frontmatter timestamp field）。
  Fail-fast with remediation：file 不存在 / .codex-pro/ 不存在 / --latest <skill> 零 match 皆 abort 非 0、不 silent fallback。
  Trigger keywords: show codex result file, display codex review output, 顯示 codex 結果, 看 codex 完整輸出, codex result detail, codex-pro result, --latest
allowed-tools:
  - Bash
  - Read
---

# /codex-pro:codex-result — Display Specific Result File (v0.1 read-only consumer)

顯示 `.codex-pro/` 內特定 producer result file 的完整內容（frontmatter + body 全顯）。本 skill 是 codex-pro 第 8 個 user-facing capability、屬 **read-only consumer category**（與 status / cancel / setup 同類）。

## 行為原則

本 skill 嚴守 codex-pro **read-only consumer category** 紀律：

- **無 Codex HTTP wrapper 呼叫**：不送 HTTPS request、不耗 Codex quota
- **無 Codex CLI subprocess**：完全不 spawn 任何 codex 相關 subprocess（與 batch 的 mutating exception 對比）
- **無 file mutation**：不寫任何 file、不建立目錄、stdout-only
- **三 selection mode 互斥（mutex / 互斥）**：位置 `<filename>` / `--latest <skill>` / `--latest` 無 arg 三者擇一；同時提供 (a)+(b) 或 (a)+(c) 必 reject
- **Fail-fast 紀律**：file 不存在 / 目錄不存在 / `--latest <skill>` 零 match 都 exit 非 0 + remediation 訊息、**不 silent fallback**（不抓最近 review 假裝是 adversarial-review）

與 review / rescue / adversarial-review 的 mutating producer 對比、與 setup（read-only environment check）+ status（read-only list） + cancel（read-only informational）同屬 read-only category — read-only consumer category 的 list + detail + informational 三件套之一。

## Step 1: Parse argument & 三 selection mode

解析 argument 為三種 mode（互斥 / mutually exclusive）：

- **Mode (a) 位置 `<filename>`**：完整檔名（不含 path prefix、不含 `.codex-pro/`）、例 `review-20260601T120000Z.md`
- **Mode (b) `--latest <skill>`**：`<skill>` 必為 `review` / `rescue` / `adversarial-review` 三者之一、拿該 producer 最近一次 result
- **Mode (c) `--latest` 無 arg**：拿全 producer 最近一次 result（不限 skill type）

```bash
case "$@" in
  *--latest*--latest*) ;; # ok, single --latest
esac

# Mutex check: 位置 filename + --latest 同時提供 → reject
if [ -n "$POSITIONAL_FILE" ] && [ -n "$LATEST_FLAG_SET" ]; then
  echo "Error: selection modes are mutually exclusive (互斥)." >&2
  echo "Choose one: <filename> | --latest <skill> | --latest" >&2
  exit 2
fi

# Enum check (mode b): <skill> 必為三 producer 之一 — fail-fast reject，
# 防止非法值（如 codex-review 帶前綴形）流進 glob 產生誤導性的零 match 訊息
case "${LATEST_SKILL:-}" in
  review|rescue|adversarial-review|"") ;;  # "" = mode (c) --latest 無 arg
  *)
    echo "Error: --latest <skill> must be one of: review | rescue | adversarial-review" >&2
    echo "  (got: '$LATEST_SKILL' — use the bare producer name, not codex-<name>)" >&2
    exit 2
    ;;
esac
```

## Step 2: Selection logic — filename lexical order

`--latest` mode 的 selection 用 **filename lexical order** 決定 most recent。filename ISO8601 timestamp prefix（producer 寫檔時 atomic 決定）= 時序 source of truth：

```bash
case "$SELECT_MODE" in
  positional)
    TARGET=".codex-pro/$POSITIONAL_FILE"
    ;;
  latest_skill)
    # --latest <skill>: filter by prefix, then lexical max
    # （單一 prefix 內、lexical sort = ISO8601 chronological sort）
    TARGET=$(ls .codex-pro/${LATEST_SKILL}-*.md 2>/dev/null | sort | tail -1)
    ;;
  latest_all)
    # --latest no arg: 跨 prefix 用 filename 內 ISO8601 portion 排序、不是 lexical of full filename
    # （prefix `adversarial-review-` < `rescue-` < `review-` 會讓 review 永遠勝出、不反映時序）
    TARGET=$(ls .codex-pro/*.md 2>/dev/null | python3 -c "
import sys, re
files = sys.stdin.read().splitlines()
def key(p):
    m = re.search(r'(\d{8}T\d{6}Z?)', p)
    return m.group(1) if m else ''
files = [f for f in files if key(f)]
print(sorted(files, key=key)[-1] if files else '')
")
    ;;
esac
```

**明示不諮詢**：

- **不用 frontmatter `timestamp` field**：需 YAML parse 慢、且 user copy 檔案到別處後 frontmatter 仍 stick、可能與 filename mismatch
- **不用 filesystem `mtime`**：易受 `git mv` / `touch` / backup tool 污染、不可信

排序語意：

- **`--latest <skill>` mode**：filename lexical sort = ISO8601 chronological sort（prefix 固定、`<skill>-YYYYMMDDTHHMMSSZ.md` pattern 內字串比較 = 時序比較）
- **`--latest` 無 arg mode**：跨 prefix 時不能用 full-filename lexical（會 prefix-biased），改 **extract ISO8601 portion 比較** — 這仍是 filename 為 source of truth（不諮詢 mtime / frontmatter），只是排序鍵改用 filename 內的 timestamp substring

## Step 3: Display file content

用 Read tool 拿完整 file 內容、印到 stdout（含 YAML frontmatter + Markdown body 全部、不重排不過濾）：

```bash
if [ -f "$TARGET" ]; then
  cat "$TARGET"
  exit 0
fi
```

Display = verbatim、無過濾、無排版改變、stdout-only。

## Step 4: Fail-fast with remediation

4 種 unresolvable case、每種都 exit 非 0 + remediation 訊息：

| Case | Remediation message |
|---|---|
| `.codex-pro/` 不存在 | 「`.codex-pro/` not yet created — run /codex-pro:codex-review, /codex-pro:codex-rescue, or /codex-pro:codex-adversarial-review to produce a result file first.」 |
| `.codex-pro/` 空（無 *.md） | 同上 |
| 位置 `<filename>` 不存在於 `.codex-pro/` | 「File not found in .codex-pro/. Run /codex-pro:codex-status to list available files.」 |
| `--latest <skill>` 零 match | 「No <skill> result files in .codex-pro/. Run /codex-pro:codex-<skill> to produce one.」 |

**嚴禁 silent fallback**：例如 `--latest adversarial-review` 找不到時、絕不抓最近 review 假裝是 adversarial-review。所有 unresolvable case 顯式 abort + 引導 user 走正確 producer skill。

```bash
if [ ! -d ".codex-pro" ]; then
  echo "Error: .codex-pro/ not yet created — run /codex-pro:codex-review, /codex-pro:codex-rescue, or /codex-pro:codex-adversarial-review first." >&2
  exit 2
fi

if [ -z "$TARGET" ] || [ ! -f "$TARGET" ]; then
  case "$SELECT_MODE" in
    positional) echo "Error: File not found in .codex-pro/. Run /codex-pro:codex-status to list available files." >&2 ;;
    latest_skill) echo "Error: No ${LATEST_SKILL} result files in .codex-pro/. Run /codex-pro:codex-${LATEST_SKILL} to produce one." >&2 ;;
    latest_all) echo "Error: No result files in .codex-pro/. Run any producer skill to create one." >&2 ;;
  esac
  exit 2
fi
```

## Result file path examples

| Command | Selects |
|---|---|
| `/codex-pro:codex-result review-20260601T120000Z.md` | 位置 filename mode — 顯示該檔 |
| `/codex-pro:codex-result --latest review` | 最近一次 review run |
| `/codex-pro:codex-result --latest rescue` | 最近一次 rescue run |
| `/codex-pro:codex-result --latest adversarial-review` | 最近一次 adversarial-review run |
| `/codex-pro:codex-result --latest` | 全 producer 最近一次（含任一 skill type） |

## 與 status / cancel 的對比

| 面向 | `/codex-pro:codex-status` | `/codex-pro:codex-result` | `/codex-pro:codex-cancel` |
|---|---|---|---|
| Mental model | list summary | detail display | informational only |
| Argument | optional `--skill <name>` | 位置 / `--latest [<skill>]` 三 mode | 零 argument |
| Output | markdown table | verbatim file content | static explainer + 3 remediation |
| Missing `.codex-pro/` | informational (exit 0) | fail-fast (exit 非 0) | 不檢查（cancel 無檔依賴）|
| 性質 | aggregate observability | single-file detail | stateless limitation explainer |

三 skill 同屬 codex-pro **read-only consumer category** — 與 setup（read-only environment）+ review/rescue/adversarial-review（mutating producer）+ batch（mutating exception）區隔。
