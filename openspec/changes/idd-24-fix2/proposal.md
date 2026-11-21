## Problem

`openspec/specs/tests/spec.md` 的 requirement「Native plugin static contract test」落後於實際測試的行為（issue #24 第 2 輪 verify 的 finding 7）：沒寫 exit 64（用法錯誤）與「合法 JSON 但不是 object 時 exit 1」；scenario 說違規時 exit 1，但它自己的 Example 表裡有 exit 2 的列；表只列了 17 種變更，測試實際跑的更多；也沒寫整合案例。

## Root Cause

`idd-24-fix1` 只改了 `codex-native-plugin`，第 1、2 輪修正加進 checker 與測試的行為沒有回寫到 `tests` capability。

## Proposed Solution

- Modified capability：`tests`（requirement「Native plugin static contract test」）。
- 結束碼寫成 0／1／2／64，合法 JSON 但不是 object 屬於 exit 1；重複的 key、NaN、Infinity、超過解析深度都屬於「不是 JSON」（exit 2）。
- scenario 分成「違反規則 → exit 1」與「缺檔或不是 JSON → exit 2」。
- Example 表改成列出測試實際跑的每一個案例（由測試的案例清單產生）。
- 新增整合案例的 scenario：未修改的副本 exit 0；壞 manifest 或缺檢查檔的副本 exit 非 0 且印出 gate 自己的失敗行；沒有 git work tree 時改為複製整棵樹。

## Non-Goals

- 不改 checker 的規則本身（第 2 輪修正已在測試與 checker 裡）。

## Success Criteria

- spec 的 Example 表與 `tests/codex-plugin.sh` 的案例清單一致。
- `bash tests/codex-plugin.sh` 全部通過。

## Impact

- Affected code:
  - Modified: tests/codex-plugin.sh, tests/lib/codex_plugin_schema.py
  - New: (none)
  - Removed: (none)
- Affected specs: openspec/specs/tests/spec.md
