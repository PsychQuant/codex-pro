## Context

`marketplace-pivot`（已 archive）落地後 user 直接觀察到兩個問題：skill 觸發名 `/codex-pro-setup:setup` 有 setup 重複，且未來 review / rescue / jobs 不打算各自獨立 sub-plugin。

本 change reverse `marketplace-pivot` 的 D2「sub-plugin 命名規則 codex-pro-<capability>」，改採 **single-plugin within marketplace** 設計：marketplace 殼仍在，但底下只有一個 plugin 也叫 `codex-pro`、所有 capability 都當這個 plugin 的 skill 並存於 `plugins/codex-pro/skills/` 內。

副作用一個：之前 marketplace-pivot 階段刻意 scope out 的「另外兩個 requirement 內 `/codex-pro:setup` namespace drift」自動消化 — 它們已是正確 namespace、不需動。

## Goals / Non-Goals

**Goals:**

- Plugin name 統一為 `codex-pro`（與 marketplace 同名）
- Skill 觸發 namespace 統一為 `/codex-pro:*`、不再含 `-setup-:setup` 重複
- Spec setup 三個 requirement 內 namespace 全 align（含 Plugin local development load 改回，另兩個保持不動）
- CLAUDE.md 與 README.md 反映 single-plugin within marketplace convention
- 確立未來 convention：所有 future capability（review / rescue / jobs）均為 `plugins/codex-pro/skills/<name>/SKILL.md`、不開新 sub-plugin

**Non-Goals:**

- 不發布 marketplace 到 GitHub
- 不引入任何新 capability（review / rescue / jobs 留待後續 change）
- 不變動 SKILL.md body 內容（純隨 parent dir rename 跟著移動）
- 不改動 codex-call discovery / readiness report 格式 / read-only 紀律
- 不修改另外兩個 requirement（Setup command produces structured readiness report、Setup performs no mutating actions）— 它們的 `/codex-pro:setup` 已正確

## Decisions

### D1: 採 single-plugin within marketplace convention

Plugin name = marketplace name = `codex-pro`。Marketplace 殼維持（不退回 root-as-plugin layout），但底下只有單一 plugin。

理由：

- codex-pro 是 single-vendor / single-product，無多 plugin 拆分動機
- Skill 觸發 `/codex-pro:setup`、`/codex-pro:review` 對 user 一致、無 capability 名重複
- 接近 upstream `openai/codex-plugin-cc` 命令名（`/codex:setup` ↔ `/codex-pro:setup`），drop-in 比較對齊
- 退回 root-as-plugin layout 等於 unwind marketplace-pivot 全部 — 過度反復；保留 marketplace 殼讓未來如要拆分仍有空間

Alternatives:

- 維持 marketplace-pivot D2「sub-plugin 命名規則 codex-pro-<capability>」：user 已明確 reverse
- 退回 codex-pro-bootstrap layout（root-as-plugin、無 marketplace.json）：unwind 太多、且 marketplace 殼對 install user 有 value

### D2: Future capability 不開新 sub-plugin

所有 future capability（review、adversarial-review、rescue、status、result、cancel）都是 `plugins/codex-pro/skills/<name>/SKILL.md` 結構、不開 codex-pro-review / codex-pro-rescue 等獨立 sub-plugin。

理由：與 D1 一致；保持 namespace 統一；user 一次跑 `/plugin install codex-pro@codex-pro` 就裝齊全部 capability。

Alternatives:

- Future 加新 capability 時開新 sub-plugin：違反 D1 設定的 single-plugin convention，且 user 已明確全部叫 codex-pro

### D3: File rename 採 mv 而非 mkdir + cp + rm

Plugin directory 從 `plugins/codex-pro-setup/` rename 為 `plugins/codex-pro/`：使用 `mv` 一步完成。

理由：repo 目前未 init git（`git status` 失敗），`git mv` 不適用；mv 是 atomic dir rename、保留 inode 與所有子檔內容。SKILL.md 內容 byte-identical 由 mv 本身保證。

Alternatives:

- mkdir + cp -r + rm -rf：等效但 3 步、出錯時部分狀態存在
- git mv：repo 未 git init 無法使用；若未來 init git 後再做 rename 可考慮

### D4: Spec MODIFIED 採整段複製 + 字串替換

依 spectra instruction，MODIFIED requirement 必須完整複製 entire block 後 edit。

複製來源：當前 main spec `openspec/specs/setup/spec.md` 的 Plugin local development load 整段（即 marketplace-pivot archive 後的版本，含 3 個 scenarios）。

替換規則（在 description + 三個 scenarios 內 global）：

- `codex-pro-setup` → `codex-pro`（plugin name、含 dir path）
- `/codex-pro-setup:` → `/codex-pro:`（skill namespace）
- `plugins/codex-pro-setup/` → `plugins/codex-pro/`（dir path）

不動：scenario 名稱、WHEN/THEN 結構、其他 requirement。

### D5: CLAUDE.md / README.md 同步重寫策略

**CLAUDE.md 重寫範圍**：

- Marketplace structure 段：sub-plugin layout 範例 dir 名 `codex-pro-setup/` 改 `codex-pro/`、移除 future sub-plugin（`codex-pro-review/` 等）改為「`plugins/codex-pro/skills/review/`、`plugins/codex-pro/skills/rescue/` 等」
- Sub-plugin 命名規則段重寫：強調 single-plugin within marketplace convention、所有 future capability 都當 plugin codex-pro 的 skill 並存
- Commands surface 表 namespace 全改 `/codex-pro:*`、移除「對應 sub-plugin」欄位（reduced to: upstream command / codex-pro command / 備註）
- 安裝 / dev-test 路徑段 sub-plugin path 從 `plugins/codex-pro-setup/` 改 `plugins/codex-pro/`

**README.md 重寫範圍**：

- What it replaces 表 namespace 全 `/codex-pro:*`
- Sub-plugins 表標題改「Skills」（不再是 sub-plugins 多列）、列已落地 setup 與 future skills（review / rescue / jobs-*）
- Install 段命令對 plugin name codex-pro

理由：兩個 doc 都要反映 D1 + D2 的單 plugin convention；audience 不同但內容方向一致。

## Implementation Contract

#### Behavior

Marketplace install 與 sub-plugin dev-test 兩條路徑都能成功啟用 `codex-pro` plugin、`/codex-pro:setup` skill 觸發後執行三項 readiness check 行為（與 codex-pro-bootstrap、marketplace-pivot 已驗證之 SKILL 邏輯相同），輸出 markdown 表格 + ready 摘要。

載入路徑 1（marketplace install）：

- `/plugin marketplace add` 指向 codex-pro 目錄
- `/plugin install codex-pro@codex-pro`（plugin name 與 marketplace name 同名）

載入路徑 2（dev test）：

- `claude --plugin-dir <codex-pro>/plugins/codex-pro`（指 sub-plugin 目錄）

#### Interface

- Marketplace identifier: `codex-pro`（不變）
- Plugin identifier: `codex-pro`（從 `codex-pro-setup` 改）
- Skill 觸發: `/codex-pro:setup`（從 `/codex-pro-setup:setup` 改）
- Plugin directory: `plugins/codex-pro/`（從 `plugins/codex-pro-setup/` 改）
- Skill path: `plugins/codex-pro/skills/setup/SKILL.md`

#### File operations contract

執行三項 file operations：

1. rename directory: `plugins/codex-pro-setup/` → `plugins/codex-pro/`（一步 mv，內部子檔內容不變）
2. Edit `plugins/codex-pro/.claude-plugin/plugin.json` 內 `"name": "codex-pro-setup"` → `"name": "codex-pro"`、其他欄位逐字保留
3. Edit `.claude-plugin/marketplace.json` 內 plugins[0].name 與 plugins[0].source 同步：`codex-pro-setup` → `codex-pro` 與 `./plugins/codex-pro-setup` → `./plugins/codex-pro`

#### Failure modes

- mv 失敗（permission / 跨檔案系統）：marketplace add 找不到 sub-plugin → 整個改動會明顯 broken、user 立即發現
- marketplace.json 與 plugin.json name 不對齊：marketplace add 跳過該 plugin、`/plugin` listing 不出現 → 立即可見

#### Acceptance criteria

- `plugins/codex-pro-setup/` 不再存在；`plugins/codex-pro/` 存在且結構完整（`.claude-plugin/plugin.json` + `skills/setup/SKILL.md`）
- `plugins/codex-pro/.claude-plugin/plugin.json` 內 `name` 為 `codex-pro`
- `.claude-plugin/marketplace.json` plugins[0].name 為 `codex-pro`、source 為 `./plugins/codex-pro`
- Sub-plugin dev-test 路徑：`CLAUDE_PLUGIN_ROOT=/Users/che/Developer/codex-pro/plugins/codex-pro` 跑 setup 三項 check 全 ✓
- main spec 內 `/codex-pro-setup` 與 `plugins/codex-pro-setup` 字串均不再出現；`/codex-pro:setup` 出現 ≥ 7 次（3 requirement + scenarios）
- CLAUDE.md 與 README.md 內 `/codex-pro-setup` 字串均不再出現

#### Scope boundaries

In scope:

- Plugin directory rename
- Plugin manifest name 字串改
- Marketplace catalog plugins[0] 同步
- Spec setup MODIFIED Plugin local development load 整段
- CLAUDE.md Marketplace structure / Commands surface / Sub-plugin 命名規則段重寫
- README.md What it replaces / Sub-plugins / Install 段同步

Out of scope:

- 任何新 capability 實作
- SKILL.md body 修改
- 其他兩個 requirement 內容變動
- codex-call discovery / readiness report 格式變動
- Marketplace 發佈 / GitHub publish

## Risks / Trade-offs

- [User 心智已 update 到 `/codex-pro-setup:setup`、再切回 `/codex-pro:setup` 是第二次 BREAKING namespace 改動] → codex-pro 仍只在 dev 階段、無對外 user。Mitigation: 本 change 後在 CLAUDE.md/README 明寫此為「最終 namespace」、再無下次 reverse 計畫。
- [Single-plugin convention 阻擋 future 加完全不同設計 plugin] → user 已明確同意（marketplace 殼仍在、極端情況可未來再 propose 新 sub-plugin）。Mitigation: marketplace.json schema 仍支援多 plugin，convention 是 social 而非 hard constraint。
- [Spec MODIFIED 必須整段複製、replace 易漏 occurrence] → 三項替換規則機械化、用 sed -i 或 python 統一處理可避免漏字。Mitigation: tasks 中明列驗證步驟（grep 確認舊字串完全消除）。
