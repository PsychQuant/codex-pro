## Problem

`tests/codex-plugin.sh` 的最後一段把 Codex 的 plugin-creator validator（`$CODEX_HOME/skills/.system/plugin-creator/scripts/validate_plugin.py`）當 release gate。Codex CLI 已不再附帶這支腳本（0.160.1 與 0.171.0 都沒有），所以 `bash tests/run.sh` 在乾淨的 `main` 上必定 exit 1（issue #24）。這個紅燈也讓本機 CI gate（#33）無法通過。

## Root Cause

測試依賴的是一個不在本 repo 控制範圍內、也不在上游公開來源裡的檔案：上游 `openai/skills` 的 `skills/.system/plugin-creator/` 在歷史上從來沒有 `scripts/validate_plugin.py`。CLI 一不附帶它，gate 就失效，而且沒有可以釘版本的替代來源。capability `tests` 的 requirement「Native plugin static contract test」把這個依賴寫成 SHALL。

## Proposed Solution

依維護者的決定（方向 A），改用 repo 自帶的 schema 檢查：

- 新增 `tests/lib/codex_plugin_schema.py`，規則依上游 `openai/skills` 的 `skills/.system/plugin-creator/references/plugin-json-spec.md`，釘在 commit `e940b8a86138adf03972802b990a1dfc57fcbf09`（檔案 sha256 `5d7223255decc44fcb93f3aa80bb17afc1469b2d3c339d65d9473c5c0c54fcdd`）。上游沒有可辨識的授權，所以不複製檔案，只把規則寫進檢查並記錄來源 commit 與雜湊。
- 檢查 `.codex-plugin/plugin.json` 與 `.agents/plugins/marketplace.json` 是否符合上游文件描述的欄位、型別、允許值與路徑規則；文件沒描述的欄位一律失敗。結束碼：0 通過、1 有違規（每條印出欄位）、2 manifest 缺少或不是 JSON。
- `tests/codex-plugin.sh` 移除 validator 段（含 `CODEX_PLUGIN_CREATOR_VALIDATOR` 覆寫），改呼叫新檢查；檢查檔不存在時測試失敗，不跳過。加入負向案例證明檢查會擋下壞掉的 manifest。
- Modified capability：`tests`（requirement「Native plugin static contract test」）。

## Non-Goals

- 不改用 Codex CLI 在隔離的 `CODEX_HOME` 裡載入 plugin 來驗證（方向 B，未驗證其隔離與拒絕行為）。
- 不改 `tests/codex-plugin.sh` 裡 codex-pro 專屬的檢查（名稱、category、policy 值、版本一致性）。
- 不改釘到更新的上游 commit（目前只有這一個 commit 動過該檔）。

## Success Criteria

- `bash tests/run.sh` 在乾淨的 `main` 上 exit 0。
- 負向案例（缺 `name`、`policy.installation` 不在允許值等）讓新檢查以 exit 1 失敗並指出欄位。
- 檢查檔不存在時 `tests/codex-plugin.sh` 回報失敗。
- 本機 CI gate（`idd-ci-gate.sh run --commit HEAD`）exit 0。

## Impact

- Affected code:
  - Modified: tests/codex-plugin.sh, README.md, CHANGELOG.md
  - New: tests/lib/codex_plugin_schema.py
  - Removed: (none)
- Affected specs: openspec/specs/tests/spec.md（Native plugin static contract test）
