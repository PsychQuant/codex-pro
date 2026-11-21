## Problem

issue #24 第 4 輪 verify：不可讀 manifest 的案例在 root 下會誤報、沒有合法 prerelease／build 版本的正向案例、object 與 array 型別規則沒有會失敗的案例、exit 0 的案例不檢查輸出、超長整數的結束碼隨 Python 版本而異，另有幾處訊息與 docstring 不準確。spec 的案例表要跟著新增的案例更新。

## Root Cause

前幾輪的案例沒有涵蓋這些規則與邊界；整數解析沿用 Python 內建的位數限制。

## Proposed Solution

- Modified capability：`tests`（requirement「Native plugin static contract test」）。
- 案例表加入新案例；scenario 說明表裡 exit 0 的列是規則邊界上的合法輸入，必須 exit 0 且不印任何輸出。

## Non-Goals

- 不改 checker 的欄位規則。

## Success Criteria

- `bash tests/codex-plugin.sh` 全部通過，含案例表一致性。

## Impact

- Affected code:
  - Modified: tests/codex-plugin.sh, tests/lib/codex_plugin_schema.py, CHANGELOG.md
  - New: (none)
  - Removed: (none)
- Affected specs: openspec/specs/tests/spec.md
