## 1. Marketplace catalog 建立

- [x] 1.1 建立 marketplace.json（D1: marketplace.json 採 minimal schema）：產出 `.claude-plugin/marketplace.json` 含 `name=codex-pro`、`owner`、`description`、`plugins` 陣列；陣列第一條為 `codex-pro-setup` 條目，`source` 設為 `./plugins/codex-pro-setup`、`description` 一句話描述。驗證方式：用 python3 解析 `.claude-plugin/marketplace.json` 成功，且 `name` 為 `codex-pro`、`plugins[0].name` 為 `codex-pro-setup`、`plugins[0].source` 為 `./plugins/codex-pro-setup`。

## 2. Sub-plugin 重組

- [x] 2.1 建立 sub-plugin 目錄骨架（D2: Sub-plugin 命名規則 codex-pro-<capability>）：建立 `plugins/codex-pro-setup/.claude-plugin/` 與 `plugins/codex-pro-setup/skills/setup/` 兩個子目錄。驗證方式：用 ls 確認兩目錄存在且為空（搬移在 task 2.2、2.3 進行）。
- [x] 2.2 搬 plugin manifest 並改 name（D3: SKILL.md 內容不變、純 file move 的姊妹動作；對 manifest 走 D2 命名）：把 `.claude-plugin/plugin.json` 從 root 搬到 `plugins/codex-pro-setup/.claude-plugin/plugin.json`，**並把 `name` 欄位內容從 `codex-pro` 改為 `codex-pro-setup`**、其他欄位（version、description、author、license、keywords）逐字保留。驗證方式：用 python3 解析新位置 manifest 顯示 `name=codex-pro-setup`、且 `version`/`description`/`author` 與原 root manifest 相同；root `.claude-plugin/plugin.json` 不再存在。
- [x] 2.3 搬 SKILL.md 內容不變（D3: SKILL.md 內容不變、純 file move）：把 `skills/setup/SKILL.md` 從 root 搬到 `plugins/codex-pro-setup/skills/setup/SKILL.md`，內容 byte-identical 不改任何字元。驗證方式：搬移前後 sha256sum 對 SKILL.md 內容一致；新位置存在、root `skills/setup/SKILL.md` 不再存在。
- [x] 2.4 清理空目錄：移除 root 的 `skills/` 目錄（搬完應已空）。驗證方式：ls codex-pro root 不再看到 `skills/` 條目；root `.claude-plugin/` 仍存在但僅含 `marketplace.json`。

## 3. CLAUDE.md 更新

- [x] 3.1 改寫 CLAUDE.md（D5: CLAUDE.md 重寫策略）：保留 `<!-- SPECTRA:START --> ... <!-- SPECTRA:END -->` block、Purpose、Design constraints、References 三段不動；重寫「核心設計差異 vs openai/codex-plugin-cc」表新增 Plugin organization 列、「Commands surface」表的 namespace 從 `/codex-pro:*` 改為 `/codex-pro-<capability>:*` 並更新對照、「What this plugin is NOT」標題改為「What this marketplace is NOT」並調整內文、新增「Marketplace structure」段（含 sub-plugin 命名規則 + 目錄佈局範例）、移除「Marketplace: 獨立 codex-pro-plugins repo」相關描述。驗證方式：grep `marketplace` CLAUDE.md 出現次數 ≥ 5；grep `/codex-pro:setup`（含結尾冒號 setup）不再出現；Spectra block byte-identical。

## 4. Spec delta 完整性

- [x] 4.1 確認 spec delta 完整性（D4: Spec MODIFIED 採整段複製 + 兩 scenarios 改寫）：人工 review `openspec/changes/marketplace-pivot/specs/setup/spec.md`，確認 Requirement: **Plugin local development load** 完整 entire block（description + 所有 scenarios）被複製進 `## MODIFIED Requirements` 段；description 文字微調提到 marketplace catalog 與 sub-plugin 命名規則；scenarios 含三個（marketplace install / sub-plugin dev-test / sub-plugin manifest missing 或 malformed）；spec delta 內 `### Requirement:` 標題與 main spec 該 requirement 標題逐字一致。驗證方式：把 spec delta 內 requirement 標題用 grep 與 `openspec/specs/setup/spec.md` 對照、確認標題相同；spectra analyze 對本 change 不報 Coverage 缺漏。

## 5. 端到端驗收

- [x] 5.1 marketplace install 路徑端到端（驗證 **Plugin local development load** 的 marketplace install scenario）：在新 Claude Code session 跑 `/plugin marketplace add /Users/che/Developer/codex-pro` 再跑 `/plugin install codex-pro-setup@codex-pro`。驗證方式：`/plugin` 命令清單顯示 `codex-pro` marketplace、其下含 `codex-pro-setup` 條目；輸入 `/codex-pro-setup:setup` 可觸發 skill。
- [x] 5.2 sub-plugin dev-test 路徑端到端（驗證 **Plugin local development load** 的 sub-plugin dev-test scenario + 沿用之 read-only 紀律）：在新 Claude Code session 跑 `claude --plugin-dir /Users/che/Developer/codex-pro/plugins/codex-pro-setup`，輸入 `/codex-pro-setup:setup` 觸發 skill。驗證方式：skill 輸出 3 列 markdown 表格 + 摘要含 `ready`；setup 跑完 ls -la ~/.codex/ 前後 diff exit 0（沿用 codex-pro-bootstrap 已驗證之 Setup performs no mutating actions）。

## 6. Marketplace 對外 README

- [x] 6.1 建立 marketplace root README.md（D6: 新增 README.md 為 marketplace 對外入口）：產出 `codex-pro/README.md`，內容含定位段（標明本 marketplace 對標 openai/codex-plugin-cc）、command 替代對照表 subset、為何 marketplace 而非 single plugin 段落、已落地與規劃中 sub-plugin 清單、安裝步驟（marketplace add + plugin install）、Reference 段明寫 upstream `openai/codex-plugin-cc` GitHub URL 與 parallel-ai-agents runtime 依賴、指向 CLAUDE.md 為設計細節。驗證方式：README.md 內 grep `openai/codex-plugin-cc` 出現 ≥ 1 次、grep `parallel-ai-agents` ≥ 1 次、grep `codex-pro-setup` ≥ 1 次、grep `marketplace add` ≥ 1 次。
