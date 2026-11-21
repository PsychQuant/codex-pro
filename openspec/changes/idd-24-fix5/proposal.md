## Problem

issue #24 第 5 輪 verify：exit 0 的案例用命令替換擷取輸出，只有換行的輸出會被當成「沒有輸出」；`policy.installation`／`policy.authentication` 缺少時印的是「must be one of」而不是「required」；幾個案例沒有斷言舊訊息已消失；gate 計數的 fixture 寫不進去時不會記為失敗；案例表的解析仍放過格式錯的列；exit 3 只檢查了原始碼的形狀。另外「Cross-harness version consistency」在 `idd-24-fix1` 拿掉寫死的 0.9.0 時，一併刪掉了 release notes 要寫明 0.9.0 與 0.8.0 加了什麼的那句。

## Root Cause

前幾輪的測試與訊息沒有涵蓋這些情況；fix1 改寫 requirement 時多刪了一句與 validator 無關的內容。

## Proposed Solution

- Modified capability：`tests`（requirement「Native plugin static contract test」）的案例表加入新案例。
- Modified capability：`codex-native-plugin`（requirement「Cross-harness version consistency」）恢復 0.9.0／0.8.0 release notes 的那句，版本號仍不寫死在一致性規則裡。

## Non-Goals

- 不改其他 requirement。

## Success Criteria

- `bash tests/codex-plugin.sh` 全部通過，含案例表一致性。

## Impact

- Affected code:
  - Modified: tests/codex-plugin.sh, tests/lib/codex_plugin_schema.py, CHANGELOG.md
  - New: (none)
  - Removed: (none)
- Affected specs: openspec/specs/tests/spec.md, openspec/specs/codex-native-plugin/spec.md
