## Why

上一個 change `marketplace-pivot`（已 archive）把 plugin name 從 `codex-pro` 改為 `codex-pro-setup`，sub-plugin 命名規則為 `codex-pro-<capability>`。落地後實際 user 觀察出兩個問題：

1. Skill 觸發名 `/codex-pro-setup:setup` 有 `setup` 重複，看著彆扭
2. 未來 review / rescue / jobs 不打算各自獨立 sub-plugin，而是同一個 plugin `codex-pro` 內多 skill 並存

`codex-pro` 是 single-vendor / single-product marketplace，未來不會引入第三方完全不同設計的 plugin，多 sub-plugin 拆分是過度設計。本 change 把 plugin name 統一改回 `codex-pro`（與 marketplace 同名），所有 capability 都當作此 plugin 的 skill 並存於 `plugins/codex-pro/skills/` 內。

## What Changes

- 把 `plugins/codex-pro-setup/` 目錄重新命名為 `plugins/codex-pro/`
- Sub-plugin manifest `plugin.json` 的 `name` 從 `codex-pro-setup` 改回 `codex-pro`
- `marketplace.json` plugins[0].name 同步改 `codex-pro`、source 改 `./plugins/codex-pro`
- **BREAKING (僅命名空間)**：skill 觸發從 `/codex-pro-setup:setup` 改回 `/codex-pro:setup`
- 修改 `setup` capability 的 Requirement: Plugin local development load — description 與 scenarios 內所有 `codex-pro-setup` plugin 名與 `/codex-pro-setup:*` skill 觸發改回 `codex-pro` 與 `/codex-pro:*`；同時 sub-plugin 路徑 `plugins/codex-pro-setup/` 改為 `plugins/codex-pro/`
- 修改另外兩個 requirement 的 description 與 scenarios — 其中 `/codex-pro:setup` 已是正確 namespace、**不需改動**（drift 在 marketplace-pivot 階段刻意 scope out、此 change 自動消化）
- 更新 `CLAUDE.md`：Marketplace structure 段重寫為 single-plugin convention、Commands surface 表 namespace 統一 `/codex-pro:*`、Sub-plugin 命名規則改為 single-plugin within marketplace convention
- 更新 `README.md`：command 對照表、安裝步驟、sub-plugin 清單的 namespace 與 plugin 名統一回 `codex-pro`

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `setup`: Requirement: Plugin local development load 描述與三個 scenarios 內所有 `codex-pro-setup` plugin 名（含 plugin dir 路徑 `plugins/codex-pro-setup/`）與 `/codex-pro-setup:*` skill 觸發改回 `codex-pro` 與 `/codex-pro:*`。其他兩個 requirement（Setup command produces structured readiness report、Setup performs no mutating actions）內的 `/codex-pro:setup` 已正確，不動。

## Impact

- Affected specs:
  - Modified: `openspec/specs/setup/spec.md`（Plugin local development load entire block）
- Affected code:
  - Renamed: `plugins/codex-pro-setup/` → `plugins/codex-pro/`（含內部所有檔案）
  - Modified:
    - `plugins/codex-pro/.claude-plugin/plugin.json`（`name` → `codex-pro`）
    - `.claude-plugin/marketplace.json`（plugins[0].name 與 source 同步）
    - `CLAUDE.md`（Marketplace structure 段、Commands surface 表、相關段落 namespace 統一）
    - `README.md`（command 對照表、安裝步驟、sub-plugin 清單）
  - Unchanged: `plugins/codex-pro/skills/setup/SKILL.md` 內容（仍 byte-identical，僅隨 parent dir rename location）
- 命名空間 user-observable: `/codex-pro-setup:setup` → `/codex-pro:setup`
- Future convention: 不再拆 sub-plugin、所有 future capability（review / rescue / jobs 等）均為 `plugins/codex-pro/skills/<name>/SKILL.md`
