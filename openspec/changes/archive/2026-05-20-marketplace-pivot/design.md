## Context

前一個 change `codex-pro-bootstrap`（已 archive）在 greenfield 把 codex-pro 當成 single Claude Code plugin — `.claude-plugin/plugin.json` 放在 repo root。但 codex-pro 真實定位是 marketplace（multi-plugin catalog），底下首個 sub-plugin 為 `codex-pro-setup`、未來會擴展 review、rescue 等 siblings。

依官方文檔 plugin-marketplaces.md，marketplace 標準結構：

- `<root>/.claude-plugin/marketplace.json` — catalog manifest
- `<root>/plugins/<plugin-name>/.claude-plugin/plugin.json` — 每個 plugin manifest
- `<root>/plugins/<plugin-name>/skills/` — 每個 plugin 的 skill

當前 layout 阻擋 sibling plugin 加入，且 `setup` capability spec 的 "Plugin local development load" scenarios 寫成單 plugin 的 --plugin-dir 載 codex-pro root 路徑、對 marketplace 結構不適用 — 規範與實際載入路徑脫節。

## Goals / Non-Goals

**Goals:**

- File layout 完全符合 Claude Code marketplace 標準
- spec `setup` 的 Plugin local development load 兩個 scenarios 改寫成 marketplace 載入路徑（或 sub-plugin dev-test 路徑）
- 同時支援 marketplace install 與 sub-plugin dev-test 兩條載入路徑
- CLAUDE.md 反映「codex-pro 自己是 marketplace」並建立 sub-plugin 命名規則

**Non-Goals:**

- 不發布 marketplace 到 GitHub（仍 local dev only）
- 不建第二個 sub-plugin（codex-pro-review、codex-pro-rescue 留待後續 changes）
- 不變動 setup 的 read-only 紀律、readiness report 格式、codex-call PATH discovery 策略（沿用 codex-pro-bootstrap D3、D4、D5）
- 不修改 `Setup performs no mutating actions`、`Setup command produces structured readiness report` 兩個 requirement
- 不改 SKILL.md body 內容（沿用 codex-pro-bootstrap 已驗證之指示）

## Decisions

### D1: marketplace.json 採 minimal schema

只填 required fields（name=codex-pro、owner、plugins）+ description（optional 但加分）。不啟用 metadata.pluginRoot、不啟用 allowCrossMarketplaceDependenciesOn。

理由：第一版只有一個 sub-plugin、minimal 才能 highlight 真正必要欄位。未來 sub-plugin 增多時再評估 pluginRoot 縮寫。

Alternatives:

- 用 metadata.pluginRoot 縮寫 source path：sub-plugin 多時方便，目前只一個無必要。
- 採完整 schema（含 keywords、category、tags 等）：對 local dev marketplace 是 over-spec。

### D2: Sub-plugin 命名規則 codex-pro-<capability>

首個 sub-plugin 命名 `codex-pro-setup`。未來 sub-plugin 依此模式：`codex-pro-review`、`codex-pro-rescue`、`codex-pro-status` 等。

理由：

- marketplace 內每個 sub-plugin 自帶 marketplace name 前綴避免 namespace collision
- Skill 觸發名 `/codex-pro-setup:setup`、`/codex-pro-review:review`，user 一看 trigger 就知道 marketplace 與 sub-plugin
- 與 psychquant-claude-plugins 既有命名實踐方向一致（plugin 名不重複用 marketplace 前綴，但 codex-pro 為了未來易讀採前綴策略）

Alternatives:

- 用 `codex-pro-core` 整合多 skill：違反 single-responsibility、且 marketplace 設計鼓勵多 plugin 拆分。
- 用 `setup`（無前綴）：sub-plugin 沒有 marketplace 識別、skill trigger 變 `/setup:setup` 怪、且擋住未來其他 marketplace 同名 plugin。

### D3: SKILL.md 內容不變、純 file move

`skills/setup/SKILL.md` 內容（frontmatter + 3 個 Check 段落 + readiness report 格式）原樣搬到 `plugins/codex-pro-setup/skills/setup/SKILL.md`，不重寫不改格式。

理由：codex-pro-bootstrap task 3.1 已驗證 SKILL 邏輯在當前環境跑通（三個 Bash check 全 pass）。任何 SKILL 內容改動都會放大此 change 的 risk surface。

`${CLAUDE_PLUGIN_ROOT}` 環境變數的解析在新位置依然成立（Claude Code 對 sub-plugin 也提供此 env var、相對位置 `.claude-plugin/plugin.json` 仍正確）。

### D4: Spec MODIFIED 採整段複製 + 兩 scenarios 改寫

依 spectra instruction，MODIFIED requirement 必須完整複製 entire requirement block 後 edit（包含 description 文字 + 全部 scenarios）。

本 change 重寫範圍：

- Requirement description 文字微調：提到 marketplace catalog 或 sub-plugin 路徑
- Scenario "Plugin name appears in plugin listing"：WHEN/THEN 從 single-plugin --plugin-dir 改為 marketplace add + plugin install 兩段條件（或 sub-plugin dev-test --plugin-dir）
- Scenario "Plugin manifest missing or malformed"：範圍從 root plugin.json 改為 sub-plugin plugin.json
- 不動其他兩 requirement（Setup command produces structured readiness report、Setup performs no mutating actions）

### D5: CLAUDE.md 重寫策略

**保留**（spectra block 與專案 vision 不動）：

- `<!-- SPECTRA:START -->` 至 `<!-- SPECTRA:END -->` 完整保留
- Purpose、Design constraints、References 三段不動

**重寫**：

- 「核心設計差異 vs openai/codex-plugin-cc」表新增「Plugin organization」列（codex-plugin-cc single plugin、codex-pro marketplace + multi sub-plugin）
- 「Commands surface」表 namespace 從 `/codex-pro:*` 改為 `/codex-pro-<capability>:*` 對應 sub-plugin
- 「What this plugin is NOT」標題改為「What this marketplace is NOT」並調整內文
- 新增「Marketplace structure」段：sub-plugin 命名規則 + 目錄佈局範例 + 命名空間策略
- 移除「Marketplace: 獨立 codex-pro-plugins repo」相關描述
- 「與相關 plugin 的關係」表標題改「與相關 marketplace 的關係」

理由：定位變但 vision 不變；維持「5 分鐘內讀完知道是什麼」原則。

### D6: 新增 README.md 為 marketplace 對外入口

新建 `README.md` 於 marketplace root（`codex-pro/README.md`），定位為 GitHub repo 入口與「/plugin marketplace add」user 第一個看到的 surface。內容範圍刻意精簡（短、行銷感為主）：

- 一句話定位：「對標 openai/codex-plugin-cc 的進階重寫，以 marketplace 形式組織多 sub-plugin」
- 替代對照表（subset of CLAUDE.md Commands surface）：原 plugin command → codex-pro 對應 command
- 為何走 marketplace 而非 single plugin 的一段話
- 已落地 sub-plugin 與規劃中 sub-plugin 清單
- 安裝步驟（marketplace add + plugin install）
- Reference 段：**明寫 upstream `openai/codex-plugin-cc` GitHub URL**、parallel-ai-agents 依賴、指 CLAUDE.md 為設計細節

理由：CLAUDE.md 是 AI/collaborator 看的（長、設計細節、繁中），README.md 是 install user 與 GitHub browse user 看的（短、定位、reference）。兩者 audience 不同，混在同一檔反而模糊。README 必須明寫 upstream `openai/codex-plugin-cc` 讓 user 第一眼就知道這是哪個 plugin 的進階版本，避免認知斷層。

Alternatives:

- 把 README 內容塞進 CLAUDE.md 開頭：違反 audience separation、且 CLAUDE.md 已長
- 不寫 README、依 CLAUDE.md：GitHub UI 對 README.md 有 special render、install user 在 repo 入口看不到 CLAUDE.md

## Implementation Contract

#### Behavior

兩種載入路徑都能成功啟用 codex-pro-setup plugin、`/codex-pro-setup:setup` skill 觸發後執行原本 codex-pro-bootstrap 驗證過的 readiness check 行為（OAuth token / codex-call / plugin manifest 三項）並輸出 markdown 表格。

載入路徑 1（marketplace install）：

- 在 Claude Code 中執行 marketplace add 指令指向 codex-pro 目錄
- 接著 plugin install codex-pro-setup 至 codex-pro marketplace

載入路徑 2（sub-plugin dev test）：

- 啟動 Claude Code 時用 --plugin-dir flag 指向 codex-pro/plugins/codex-pro-setup（不是 codex-pro root）

#### Interface

- Marketplace identifier: `codex-pro`
- 首個 sub-plugin identifier: `codex-pro-setup`
- Skill 觸發: `/codex-pro-setup:setup`
- Marketplace catalog path: `.claude-plugin/marketplace.json`
- Sub-plugin manifest path: `plugins/codex-pro-setup/.claude-plugin/plugin.json`
- Sub-plugin skill path: `plugins/codex-pro-setup/skills/setup/SKILL.md`

#### File operations contract

執行三項 file operations（atomic — 出錯時可手動 revert）：

1. 把 `.claude-plugin/plugin.json` 從 root 搬到 `plugins/codex-pro-setup/.claude-plugin/plugin.json`，並把內容裡的 `"name": "codex-pro"` 改為 `"name": "codex-pro-setup"`、保留其他欄位
2. 把 `skills/setup/SKILL.md` 從 root 搬到 `plugins/codex-pro-setup/skills/setup/SKILL.md`（內容完全不變）
3. 新建 `.claude-plugin/marketplace.json` 於 root，內容含 name=codex-pro / owner / plugins[]（list 含一個條目指向 sub-plugin）
4. 清理空目錄：原 `skills/` 移除（若搬完已空）

#### Failure modes

- marketplace.json schema 不符 Claude Code 要求 → 啟動載 marketplace add 失敗，error 訊息會顯示
- plugin.json `name` 與目錄名不一致 → skill namespace 觸發失效（觸發名跟預期不一致）
- Sub-plugin manifest 缺欄位 → marketplace add 載入時跳過該 plugin

#### Acceptance criteria

- 路徑 1（marketplace install）：marketplace add 後 `/plugin` 命令清單顯示 `codex-pro` marketplace 含 `codex-pro-setup` 條目
- 路徑 2（sub-plugin dev test）：sub-plugin --plugin-dir 載入後 `/codex-pro-setup:setup` 可被觸發
- 任一路徑成功觸發 setup 後：輸出 3 列 markdown 表格 + 「ready」摘要（沿用 codex-pro-bootstrap 已驗證）
- 觸發後 `~/.codex/` 內容未變動（Setup performs no mutating actions 沿用）

#### Scope boundaries

In scope:

- `.claude-plugin/marketplace.json` 新建
- `plugins/codex-pro-setup/` 子目錄建立 + 接收 plugin.json 與 SKILL.md
- 清理 root 舊位置 + 空 skills/
- CLAUDE.md 段落改寫
- spec setup 的 Plugin local development load 兩個 scenarios 改寫

Out of scope:

- 任何其他 sub-plugin（codex-pro-review、codex-pro-rescue 等）
- spec setup 其他兩個 requirement 的修改
- Marketplace publish 到 GitHub 或外部分發
- 變動 codex-call PATH discovery、readiness report 格式、read-only 原則
- 修改 SKILL.md body 內容（包含 Check decision tables）

## Risks / Trade-offs

- [User 心智已習慣 `/codex-pro:setup` 預期觸發名] → 切到 `/codex-pro-setup:setup` 是 BREAKING namespace change。Mitigation: codex-pro 目前無對外發布、無 install user；CLAUDE.md 與 spec 明確記命名規則避免再次 drift。
- [Marketplace dev-test 比 single plugin 多一步] → user dev test 路徑增加。Mitigation: 文件並列兩種路徑（marketplace add 與 sub-plugin --plugin-dir），dev iterate 用後者較快。
- [Spec MODIFIED 容易漏複製 entire block] → MODIFIED 必須含 full requirement 文字（per spectra instruction）；若漏複製 scenarios，archive 時主 spec 會遺失行為描述。Mitigation: 寫 spec delta 時從 main spec setup/spec.md 直接複製 Requirement: Plugin local development load 完整區塊後再 edit scenarios。
- [skills/ 空目錄殘留] → 搬移後若 root skills/ 內無檔但目錄存在，會在 repo 留 cruft。Mitigation: 完成 file move 後 rmdir 空目錄並 verify。
