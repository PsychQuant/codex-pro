## Why

前一個 change（`codex-pro-bootstrap`，已 archive）把 codex-pro 設定為 single Claude Code plugin —`plugin.json` 放在 repo root 的 `.claude-plugin/`。但根據官方文檔（https://code.claude.com/docs/en/plugin-marketplaces.md），`codex-pro` 正確的定位是 marketplace（catalog 容器），底下會放多個 sub-plugin（首個為 `codex-pro-setup`，未來會擴展 `codex-pro-review`、`codex-pro-rescue` 等）。當前 layout 阻擋未來 sibling plugin 的加入，且 `setup` capability spec 內的 "Plugin local development load" scenarios 用 `claude --plugin-dir <codex-pro root>` 載入路徑、對 marketplace 結構不適用 — spec 規範與實際載入路徑脫節。

## What Changes

- 新增 `.claude-plugin/marketplace.json` catalog manifest，列出 `codex-pro-setup` 為首個 sub-plugin
- 把 `.claude-plugin/plugin.json` 從 repo root 搬到 `plugins/codex-pro-setup/.claude-plugin/plugin.json`，並改 `name` 從 `codex-pro` 為 `codex-pro-setup`
- 把 `skills/setup/SKILL.md` 從 repo root 搬到 `plugins/codex-pro-setup/skills/setup/SKILL.md`
- **BREAKING (僅命名空間)**：skill 觸發從預期的 `/codex-pro:setup` 變為 `/codex-pro-setup:setup`（plugin 名 = skill namespace prefix）
- 更新 `CLAUDE.md`：移除「Marketplace: 獨立 `codex-pro-plugins` repo」段落、重寫定位為「codex-pro 自己是 marketplace」、加入 sub-plugin 命名規則
- 修改 `setup` capability spec 的 Requirement: Plugin local development load 的 scenarios，改為 marketplace add + plugin install 載入路徑（或 sub-plugin `--plugin-dir` dev test 路徑）

## Capabilities

### New Capabilities

(none — marketplace.json 是 catalog manifest、非 user-observable behavior，不另立 capability)

### Modified Capabilities

- `setup`: Requirement: Plugin local development load 的 scenarios 改寫 — 從 single plugin `claude --plugin-dir <codex-pro root>` 路徑，改為 marketplace 載入（`/plugin marketplace add` + `/plugin install codex-pro-setup@codex-pro`）或 sub-plugin dev test（`claude --plugin-dir <codex-pro>/plugins/codex-pro-setup`）。Plugin manifest 期望的 `name` 從 `codex-pro` 改為 `codex-pro-setup`。其他兩個 requirement（"Setup command produces structured readiness report"、"Setup performs no mutating actions"）行為不變。

## Impact

- Affected specs:
  - Modified: `openspec/specs/setup/spec.md`（Requirement: Plugin local development load 兩個 scenarios 重寫）
- Affected code:
  - New:
    - `.claude-plugin/marketplace.json`
    - `plugins/codex-pro-setup/.claude-plugin/plugin.json`
    - `plugins/codex-pro-setup/skills/setup/SKILL.md`
  - Moved（內容微改）：
    - `.claude-plugin/plugin.json` 內容 (name 改 `codex-pro-setup`) 落到 `plugins/codex-pro-setup/.claude-plugin/plugin.json`
    - `skills/setup/SKILL.md` 內容（不變）落到 `plugins/codex-pro-setup/skills/setup/SKILL.md`
  - Modified:
    - `CLAUDE.md`（定位段落、Architecture 表、Commands surface 命名空間、References 段落）
  - Removed:
    - `.claude-plugin/plugin.json`（原 root 位置；內容搬到 plugins/ 內後 root 不留）
    - `skills/setup/SKILL.md`（原 root 位置）
    - `skills/`（空目錄移除）
- 命名空間 user-observable 影響: skill 觸發名變化 `/codex-pro:setup` → `/codex-pro-setup:setup`
- Dependencies: 無變動（parallel-ai-agents codex-call wrapper 仍是 runtime 依賴）
