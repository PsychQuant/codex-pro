## Problem

issue #24 第 3 輪 verify：整合案例（複製整棵樹、重跑整支 `tests/codex-plugin.sh`）無法證明 gate 自己的失敗會進到結束碼（HIGH），而且依賴 git index、`TMPDIR` 位置、把測試拖到約 29 秒；另有幾條 checker 規則沒有會失敗的測試、欄位名稱沒有跳脫、未預期的錯誤和違規共用 exit 1，spec 的案例表也沒有機制與測試保持一致。

## Root Cause

第 1 輪加入的整合設計用「另一個行程的結束碼」間接證明 gate 有計入失敗，而副本裡同源的其他檢查也會失敗，結束碼因此分不出來源。

## Proposed Solution

- Modified capability：`tests`（requirement「Native plugin static contract test」）。
- gate 改成函式 `run_schema_gate`，在 subshell 以全新的計數器呼叫它（缺檔、exit 1、exit 0 的 checker），斷言 fail 數分別增加 1、1、0；移除整棵樹的副本、巢狀執行與 token。
- checker：非一般識別字的欄位名稱以 JSON 跳脫印出；未預期的錯誤 exit 3。
- 新增的案例補齊每條規則；spec 的案例表必須與測試的案例清單完全一致，由測試檢查。

## Non-Goals

- 不改 checker 的欄位規則（只補測試與錯誤處理）。

## Success Criteria

- `bash tests/codex-plugin.sh` 全部通過，含「spec 的案例表與測試一致」。
- 本機 CI gate exit 0。

## Impact

- Affected code:
  - Modified: tests/codex-plugin.sh, tests/lib/codex_plugin_schema.py, CHANGELOG.md
  - New: (none)
  - Removed: (none)
- Affected specs: openspec/specs/tests/spec.md
