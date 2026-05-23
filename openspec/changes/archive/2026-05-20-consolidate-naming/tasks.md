## 1. Plugin directory rename

- [x] 1.1 rename plugin directory + 改 manifest name（D3: File rename 採 mv 而非 mkdir + cp + rm、D1: 採 single-plugin within marketplace convention）：把 `plugins/codex-pro-setup/` 一步 mv 為 `plugins/codex-pro/`、Edit `plugins/codex-pro/.claude-plugin/plugin.json` 內 `name` 從 `codex-pro-setup` 改回 `codex-pro`，其他欄位（version、description、author、license、keywords）逐字保留。驗證方式：`plugins/codex-pro-setup/` 不再存在、`plugins/codex-pro/` 結構完整含 `.claude-plugin/plugin.json` 與 `skills/setup/SKILL.md`；python3 parse manifest 顯示 `name=codex-pro`。

## 2. Marketplace catalog sync

- [x] 2.1 同步 marketplace.json plugins[0]（D1: 採 single-plugin within marketplace convention）：Edit `.claude-plugin/marketplace.json` plugins[0].name 從 `codex-pro-setup` 改 `codex-pro`、plugins[0].source 從 `./plugins/codex-pro-setup` 改 `./plugins/codex-pro`。驗證方式：python3 parse marketplace.json 顯示 plugins[0].name = `codex-pro`、plugins[0].source = `./plugins/codex-pro`、與 sub-plugin manifest 的 name 一致。

## 3. Spec delta 完整性

- [x] 3.1 確認 spec delta 完整性（D4: Spec MODIFIED 採整段複製 + 字串替換）：人工 review `openspec/changes/consolidate-naming/specs/setup/spec.md`，確認 Requirement: **Plugin local development load** 完整 entire block 已複製、description 含 marketplace catalog 與 sub-plugin 命名說明、3 個 scenarios 內所有 `codex-pro-setup` 與 `plugins/codex-pro-setup` 字串均改為 `codex-pro` 與 `plugins/codex-pro`、`/codex-pro-setup` 不再出現於 delta spec。驗證方式：在 delta spec 跑 grep `codex-pro-setup` 結果為 0 行；spectra analyze 不報 Coverage 缺漏。

## 4. Doc 更新

- [x] 4.1 改寫 CLAUDE.md（D5: CLAUDE.md / README.md 同步重寫策略、D2: Future capability 不開新 sub-plugin）：保留 SPECTRA block、Purpose、Design constraints、References 三段不動；重寫 Marketplace structure 段（dir 名 `codex-pro-setup/` 改 `codex-pro/`、移除 future sub-plugin 例如 `codex-pro-review/` 改為 single plugin 多 skill 範例）、Sub-plugin 命名規則段改寫為 single-plugin within marketplace convention（強調未來 capability 都歸 plugin codex-pro 下 skill）、Commands surface 表 namespace 全改 `/codex-pro:*`、移除「對應 sub-plugin」欄位、安裝路徑改 `plugins/codex-pro`。驗證方式：grep `/codex-pro-setup` CLAUDE.md 為 0 次、grep `/codex-pro:setup` ≥ 1 次、grep `codex-pro-setup` 為 0 次、SPECTRA block 28 行 byte-identical。
- [x] 4.2 改寫 README.md（D5: CLAUDE.md / README.md 同步重寫策略）：What it replaces 對照表 namespace 全改 `/codex-pro:*`；Sub-plugins 表標題改 `Skills` 並列已落地 setup 與 future skills（review / rescue / jobs-*）作為 `plugins/codex-pro/skills/*/` 結構；Install 段命令使用 `codex-pro@codex-pro`（plugin 名 = marketplace 名同名）。驗證方式：grep `/codex-pro-setup` README.md 為 0 次、grep `/codex-pro:setup` ≥ 1 次、grep `codex-pro@codex-pro` ≥ 1 次。

## 5. 端到端驗收

- [x] 5.1 marketplace install 路徑端到端 simulation（驗證 **Plugin local development load** 的 marketplace install scenario）：用 python3 解析 `.claude-plugin/marketplace.json`、resolve sub-plugin source path（`./plugins/codex-pro`）、parse sub-plugin manifest、verify SKILL.md frontmatter 含 `name: setup`。驗證方式：所有解析成功、marketplace name = `codex-pro`、plugin name = `codex-pro`、source 指向實存目錄、skill 觸發推導為 `/codex-pro:setup`。
- [x] 5.2 sub-plugin dev-test 路徑端到端 simulation（驗證 **Plugin local development load** 的 sub-plugin dev-test scenario + 沿用 read-only 紀律）：以 `CLAUDE_PLUGIN_ROOT=/Users/che/Developer/codex-pro/plugins/codex-pro` 跑 3 個 Check（OAuth token / codex-call PATH / Plugin manifest self-check），確認 manifest self-check 顯示 `name=codex-pro v0.1.0` path 指向新位置。同步驗證 read-only — `ls -la ~/.codex/` 前後 diff exit 0（沿用 codex-pro-bootstrap 已驗證之 Setup performs no mutating actions）。
