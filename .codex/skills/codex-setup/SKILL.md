---
name: codex-setup
description: |
  驗證 codex-pro 環境是否就緒 — 檢查 Codex OAuth token、bundled producer runtime，並分別回報 consumer skills。
  Use when: 使用者輸入 $codex-setup、第一次使用 codex-pro、診斷其他 $codex-* command 失敗時。
  輸出 4 欄 markdown readiness report（Check / Status / Detail / Remediation）。純 read-only — 不修改任何環境或設定。
  Trigger keywords: verify codex-pro environment, check codex setup, codex-pro readiness, codex 環境檢查
allowed-tools:
  - Bash
  - Read
---
<!-- GENERATED FILE — DO NOT EDIT.
     Source: plugins/codex-pro/skills/codex-setup/SKILL.md
     Regenerate: scripts/generate-codex-skills.sh
     Drift is caught by tests/codex-skills-parity.sh -->

# $codex-setup — 環境就緒檢查

驗證 codex-pro plugin 執行所需的環境前提是否就緒，以結構化 markdown 表格回報每項檢查的狀態與修復指引。

## 行為原則

- **純 read-only**：不執行任何 mutating 行為。不 mkdir、不 touch、不裝 codex CLI、不呼叫 `codex login`、不修改 PATH、不寫任何檔案。
- **回報而非修復**：所有「缺失項」只輸出 Remediation 文字告訴使用者該執行什麼，由使用者自行決定是否執行。

## 執行流程

按順序執行以下兩項檢查、收集每項結果，最後依「Readiness Report 輸出」一節組裝成 4 欄 markdown 表格回傳給使用者。任何一項檢查腳本都嚴格僅讀取資訊、不修改任何狀態。

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

### Check 2: Codex producer runtime

Codex 載入本 skill 時會提供 active `SKILL.md` 的絕對路徑。先以該實際路徑的
目錄設定 `SKILL_DIR`，不得從目前工作目錄推測，再執行以下純 read-only Bash：

```bash
BUNDLE_ROOT="$(cd "$SKILL_DIR/../.." && pwd -P)"
wrapper="$BUNDLE_ROOT/bin/codex-pro-call"

if [ -f "$wrapper" ] && [ -x "$wrapper" ]; then
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
> producer（review、adversarial-review、rescue）需要 macOS 與 Xcode Command Line
> Tools Swift；consumer（`$codex-status`、`$codex-result`、`$codex-config`、
> `$codex-cancel`）只讀本機檔案，在 producer unavailable 時仍可使用。

## Readiness Report 輸出

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

## 結束時的約束

不論結果如何，**絕對不要**：

- 替使用者執行 `codex login`、`chmod`、`npm install` 或任何修復步驟
- 寫入、修改、刪除任何檔案（含 `~/.codex/`、`PATH`、plugin 內檔）
- 嘗試重新安裝任何相依 plugin

使用者讀完 readiness report 後自行決定下一步。
