## Why

`codex-pro` 是 `openai/codex-plugin-cc` 的進階重寫（見 CLAUDE.md），目前處於 greenfield 狀態 — 0 source files、無 plugin manifest、無 entry skill。任何後續 command（review、rescue、status 等）都依賴一個基本工作條件：使用者環境必須有可用的 Codex OAuth token 與 `codex-call` runtime。本 change 建立最小可運作的 plugin skeleton，並提供 `/codex-pro:setup` 命令讓使用者驗證環境是否就緒，作為後續所有 `/codex-pro:*` command 的前置條件。

## What Changes

- 建立 Claude Code plugin skeleton：plugin manifest、`skills/` 目錄結構、本地 dev-test 入口
- 新增 `/codex-pro:setup` skill：檢查 Codex OAuth token 檔（`~/.codex/auth.json`）存在且可讀、檢查 `parallel-ai-agents/bin/codex-call` wrapper 可呼叫、回報結構化 readiness report（含每項檢查的 pass/fail/remediation 提示）
- 文件化本地 dev-test 流程：以 `claude --plugin-dir` 直接掛載本地目錄測試，無需發布 marketplace

## Capabilities

### New Capabilities

- `setup`: 提供 `/codex-pro:setup` 命令，掃描使用者環境是否具備執行後續 `/codex-pro:*` command 的前置條件（OAuth token 檔、codex-call runtime），並回報結構化 readiness report（每項檢查含 pass/fail 與修復指引）。

### Modified Capabilities

(none)

## Impact

- Affected specs:
  - New: openspec/specs/setup/spec.md
- Affected code:
  - New:
    - .claude-plugin/plugin.json
    - skills/setup/SKILL.md
  - Modified: (none)
  - Removed: (none)
- Dependencies:
  - Runtime depends on existing `parallel-ai-agents/bin/codex-call` Swift wrapper（不複製、不打包，僅 reference 既有 PATH 入口）
  - Dev test 依賴 Claude Code 本身的 `--plugin-dir` 載入機制
