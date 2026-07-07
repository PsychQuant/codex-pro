---
name: codex-setup
description: |
  驗證 codex-pro 環境是否就緒 — 檢查 Codex OAuth token、codex-call wrapper、plugin manifest。
  Use when: 使用者輸入 /codex-pro:codex-setup、第一次使用 codex-pro、診斷其他 /codex-pro:* command 失敗時。
  輸出 4 欄 markdown readiness report（Check / Status / Detail / Remediation）。純 read-only — 不修改任何環境或設定。
  Trigger keywords: verify codex-pro environment, check codex setup, codex-pro readiness, codex 環境檢查
allowed-tools:
  - Bash
  - Read
---

# /codex-pro:codex-setup — 環境就緒檢查

驗證 codex-pro plugin 執行所需的環境前提是否就緒，以結構化 markdown 表格回報每項檢查的狀態與修復指引。

## 行為原則

- **純 read-only**：不執行任何 mutating 行為。不 mkdir、不 touch、不裝 codex CLI、不呼叫 `codex login`、不修改 PATH、不寫任何檔案。
- **回報而非修復**：所有「缺失項」只輸出 Remediation 文字告訴使用者該執行什麼，由使用者自行決定是否執行。

## 執行流程

按順序執行以下三項檢查、收集每項結果，最後依「Readiness Report 輸出」一節組裝成 4 欄 markdown 表格回傳給使用者。任何一項檢查腳本都嚴格僅讀取資訊、不修改任何狀態。

### Check 1: OAuth token

執行以下純 read-only Bash（用 `test`、`stat`，不寫檔）：

```bash
if [ -r "$HOME/.codex/auth.json" ]; then
  mode=$(stat -f '%OLp' "$HOME/.codex/auth.json" 2>/dev/null || stat -c '%a' "$HOME/.codex/auth.json" 2>/dev/null)
  echo "readable mode=$mode"
elif [ -e "$HOME/.codex/auth.json" ]; then
  echo "exists_but_not_readable"
else
  echo "missing"
fi
```

依輸出決定該列的 Status / Detail / Remediation：

| 輸出 | Status | Detail | Remediation |
|------|--------|--------|-------------|
| `readable mode=600` | ✓ | ``~/.codex/auth.json` 存在 (mode 600)` | N/A |
| `readable mode=<其他>` | ⚠ | ``~/.codex/auth.json` 存在 (mode <X>)，建議 0600` | `chmod 600 ~/.codex/auth.json` |
| `exists_but_not_readable` | ✗ | `OAuth token 檔存在但目前帳號無讀取權限` | `chmod u+r ~/.codex/auth.json` |
| `missing` | ✗ | `OAuth token 檔（~/.codex/auth.json）不存在` | 執行 `codex login` 完成 ChatGPT OAuth 流程後再試 |

### Check 2: codex-call wrapper PATH

執行以下純 read-only Bash（`command -v` 只查 PATH，不執行 wrapper）：

```bash
if cc_path=$(command -v codex-call 2>/dev/null); then
  echo "found path=$cc_path"
else
  echo "missing"
fi
```

依輸出決定該列的 Status / Detail / Remediation：

| 輸出 | Status | Detail | Remediation |
|------|--------|--------|-------------|
| `found path=<絕對路徑>` | ✓ | `codex-call 可呼叫，位於 <絕對路徑>` | N/A |
| `missing` | ✗ | `codex-call 不在 PATH 中` | 安裝 / 確認 `parallel-ai-agents` plugin 已啟用且其 `bin/` 目錄被 Claude Code 自動加入 PATH（執行 `/plugin list` 確認）|

**注意**：本檢查刻意不寫死 `parallel-ai-agents/bin/codex-call` 絕對路徑（見 design D3）— `codex-call` 應透過 `parallel-ai-agents` plugin 安裝時暴露於 PATH。若路徑解析失敗，根因是 parallel-ai-agents 安裝異常，setup 不越權繞道。

### Check 3: Plugin manifest self-check

執行以下純 read-only Bash 解析 plugin 自身 manifest（`python3` 只 parse JSON、不寫檔）：

```bash
plugin_root="${CLAUDE_PLUGIN_ROOT:-$(pwd)}"
manifest="$plugin_root/.claude-plugin/plugin.json"

if [ ! -r "$manifest" ]; then
  echo "not_found path=$manifest"
else
  python3 - "$manifest" <<'PY'
import json, sys
path = sys.argv[1]
try:
    d = json.load(open(path))
    print(f"ok name={d.get('name','?')} version={d.get('version','?')} path={path}")
except json.JSONDecodeError as e:
    print(f"parse_error: line {e.lineno} col {e.colno}: {e.msg} (path={path})")
except Exception as e:
    print(f"parse_error: {type(e).__name__}: {e} (path={path})")
PY
fi
```

依輸出決定該列的 Status / Detail / Remediation：

| 輸出 | Status | Detail | Remediation |
|------|--------|--------|-------------|
| `ok name=codex-pro version=<v> path=...` | ✓ | `.claude-plugin/plugin.json` 解析成功（`codex-pro` v<v>） | N/A |
| `ok name=<其他>` | ⚠ | manifest 解析成功但 name 非 `codex-pro` | 確認 plugin 安裝來源是否正確 |
| `not_found path=...` | ✗ | 找不到 manifest（`.claude-plugin/plugin.json`） | 確認 plugin 目錄結構完整、重新安裝 plugin |
| `parse_error: ...` | ✗ | 顯示 parse error 訊息（含行列號）| 檢查 manifest JSON syntax；若 plugin 由 marketplace 安裝，重新跑 `/plugin update codex-pro` |

## Readiness Report 輸出

三項檢查完成後，把每項的 Status / Detail / Remediation 組裝成 4 欄 markdown 表格直接回傳給使用者：

```
| Check | Status | Detail | Remediation |
|-------|--------|--------|-------------|
| OAuth token | <Check 1 Status> | <Check 1 Detail> | <Check 1 Remediation 或 N/A> |
| codex-call wrapper | <Check 2 Status> | <Check 2 Detail> | <Check 2 Remediation 或 N/A> |
| Plugin manifest | <Check 3 Status> | <Check 3 Detail> | <Check 3 Remediation 或 N/A> |
```

表格後空一行，依以下規則輸出總結句：

- 三項 Status 皆為 ✓ → `All checks passed — codex-pro ready.`
- 有任何 ✗ 或 ⚠ → `N check(s) need attention — see Remediation column above.`（其中 N = 非 ✓ 的列數）

### 完整輸出範例（全綠路徑）

```
| Check | Status | Detail | Remediation |
|-------|--------|--------|-------------|
| OAuth token | ✓ | `~/.codex/auth.json` 存在 (mode 600) | N/A |
| codex-call wrapper | ✓ | codex-call 可呼叫，位於 /Users/<user>/.claude/plugins/cache/.../bin/codex-call | N/A |
| Plugin manifest | ✓ | `.claude-plugin/plugin.json` 解析成功（codex-pro v0.1.0） | N/A |

All checks passed — codex-pro ready.
```

### 完整輸出範例（缺 OAuth token）

```
| Check | Status | Detail | Remediation |
|-------|--------|--------|-------------|
| OAuth token | ✗ | OAuth token 檔（~/.codex/auth.json）不存在 | 執行 `codex login` 完成 ChatGPT OAuth 流程後再試 |
| codex-call wrapper | ✓ | codex-call 可呼叫，位於 /Users/<user>/.../bin/codex-call | N/A |
| Plugin manifest | ✓ | `.claude-plugin/plugin.json` 解析成功（codex-pro v0.1.0） | N/A |

1 check(s) need attention — see Remediation column above.
```

## 結束時的約束

不論結果如何，**絕對不要**：

- 替使用者執行 `codex login`、`chmod`、`npm install` 或任何修復步驟
- 寫入、修改、刪除任何檔案（含 `~/.codex/`、`PATH`、plugin 內檔）
- 嘗試重新安裝任何相依 plugin

使用者讀完 readiness report 後自行決定下一步。
