## Problem

`openspec/specs/codex-native-plugin/spec.md` 的 requirement「Native Codex plugin manifest」仍有 scenario「Plugin validator accepts the manifest」，要求用 Codex plugin validator 驗證 repo root；而 `idd-24-pinned-plugin-schema` 已讓 `tests` 規定測試 SHALL NOT 使用該 validator。兩個 capability 互相矛盾。同一條 requirement 還把 version 寫死成 `0.9.0`，repo 實際是 0.11.0（issue #24 第 1 輪 verify 的 finding 1）。

## Root Cause

`idd-24-pinned-plugin-schema` 只改了 `tests` capability，沒有改另一份同樣提到 validator 的 living spec；version 的寫死是更早就有的漂移。

## Proposed Solution

- Modified capability：`codex-native-plugin`（requirement「Native Codex plugin manifest」）。
- validator scenario 改為：repo 自帶、釘在上游 commit 的 schema 檢查 `tests/lib/codex_plugin_schema.py` 接受這份 manifest。
- `version` 不再寫死，改為 strict SemVer，且與另外兩份發布 manifest 的版本一致（由 `tests/codex-plugin.sh` 的版本一致性檢查負責）。

## Non-Goals

- 不改 `codex-native-plugin` 其他 requirement 的行為；「Cross-harness version consistency」只拿掉寫死的 `0.9.0`（三份 manifest 版本一致的規則不變）。不改 `tests` capability（已在上一個 change 改過）。

## Success Criteria

- `grep -n "plugin validator" openspec/specs/codex-native-plugin/spec.md` 沒有輸出。
- `bash tests/codex-plugin.sh` 全部通過。

## Impact

- Affected code:
  - Modified: tests/codex-plugin.sh, tests/lib/codex_plugin_schema.py
  - New: (none)
  - Removed: (none)
- Affected specs: openspec/specs/codex-native-plugin/spec.md
