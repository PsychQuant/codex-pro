## Context

`codex-pro` 已 stable 為 marketplace 殼 + 同名 single plugin，內含 `setup` skill（read-only 環境檢查、走 codex-call HTTPS direct）。Phase 1 探索識別 codex-batch plugin（在 psychquant-claude-plugins）是當前 `/Users/che/Developer/` 底下唯一可以搬進 codex-pro 的 codex-calling plugin：

- 它整個 plugin 都是 codex 工具（不像 lean-prover 只一 skill 跟 codex 有關）
- 它是 Claude Code 端 plugin（不像 psychquant-codex-plugins 是 Codex CLI 端）
- 它的 fan-out parallel execution 機制需要 shell-level subprocess 控制 — 這跟 codex-pro 既有 Design constraint #1（No subprocess spawn for Codex）形式上衝突，但 batch 場景的 N-fan-out parallel job 本質就是 shell job control 適用情境

本 change 將 codex-batch 的 commands/codex-batch.md 從 slash command 轉型為 codex-pro 的 batch skill，並把 references/script-template.sh 逐字搬入；原 plugin 刪除以維持 single source of truth。

## Goals / Non-Goals

**Goals:**

- `/codex-pro:batch` 可由 skill 觸發、行為與原 codex-batch slash command 一致
- references/script-template.sh 完全保留（byte-identical），舊 user 的腳本仍可用
- 原 psychquant-claude-plugins 的 codex-batch plugin 整個刪除（包含 marketplace.json entry 同步），避免雙源飄移
- Design constraint #1 維持原文，batch 透過 explicit exception 標示 — 其他 skill 仍嚴守 HTTPS direct
- CLAUDE.md 與 README.md 反映新增 skill

**Non-Goals:**

- 不重寫 batch 邏輯為 codex-call HTTPS direct（fan-out subprocess control 重寫成本太高、且改造另開 change 處理）
- 不動 psychquant-codex-plugins 內的 codex-batch plugin（Codex CLI 端 marketplace）
- 不動 parallel-ai-agents（codex-pro runtime dependency）
- 不動 lean-prover/codex-prove-assist
- 不發布 codex-pro 到 GitHub
- 不變更 setup skill 行為與 readiness report 格式

## Decisions

### D1: Command → Skill 轉型策略

原 codex-batch 是 Claude Code slash command（`commands/codex-batch.md`），現需轉為 skill（`plugins/codex-pro/skills/batch/SKILL.md`）。Frontmatter 差異：

- 新增 `name: batch`（skill 必填、command 不需）
- `description` 直接搬（原已是 Claude Code 慣例多行描述）
- `argument-hint` 直接搬
- `allowed-tools` 直接搬

Body 改動最小：trigger 句改提及 `/codex-pro:batch`（原為 `/codex:batch`-style），其他指令邏輯逐字保留。

理由：command 與 skill 在 Claude Code 內機制差異最小（兩者都是 markdown + frontmatter），多一 `name` field 即可變 skill。重寫 body 會引入 regression 風險。

Alternatives:

- 完全重寫為 skill 流程：對 batch 場景無附加價值、增加 PR 風險面
- 保留 command form：但 codex-pro 既定走 skill-based convention（與 setup skill 一致）

### D2: References sha256-identical copy

`references/script-template.sh` 從 source plugin 搬到 `plugins/codex-pro/skills/batch/references/script-template.sh`，byte-identical 不改字元。驗證：搬移前後 sha256sum 一致。

理由：script-template.sh 是 batch 腳本骨架（含 codex exec parallel 邏輯），任何字元改動都可能影響行為。逐字搬是最 robust。

Alternatives:

- 順手 reformatting / lint：增加 regression 風險、scope creep
- 不搬、SKILL.md 內 inline：references file 設計初衷是「可由 user 客製、不污染 skill body」、inline 破壞此邏輯

### D3: Design constraint #1 採 explicit exception 標示

`codex-pro` 既有 Design constraint #1「No subprocess spawn for Codex — 一律走 codex-call HTTPS direct」是針對 single-shot codex call 設計（針對 upstream codex-plugin-cc 的 #330 IPC pipe deadlock 痛點）。Batch 場景不同：fan-out N 條 codex exec 並用 shell `&` parallel + `wait` monitor，是 shell job control 的天然用法。

決策：constraint 第 1 條文字不修改、不重寫；在 batch skill 的 SKILL.md 與 design.md 明確標示為 single exception，並描述適用範圍：

- batch skill 內 spawn `codex exec --full-auto` 為合法
- 其他 skill（setup、未來 review/rescue/status/result/cancel）仍嚴守 HTTPS direct
- 此 exception 範圍是「explicit allowed list」（明列 batch），不是「default」（其他不在 list 內就是違反）

理由：Constraint 的原意是「防 single-shot pipe deadlock」，batch 的 fan-out parallel 是不同類別問題（subprocess 已 detach、不阻塞 main process）。重寫 constraint 反而模糊原意；用 exception 表達更 surgical。

Alternatives:

- 重寫 constraint：constraint 範疇變模糊、未來他 skill 容易越界
- 用 codex-call 重寫 batch：fan-out N URLSession parallel + queue 管理工程量大，scope creep

### D4: 原 plugin 採 hard delete

psychquant-claude-plugins 內的整個 codex-batch plugin（含 .claude-plugin/、commands/、references/、CHANGELOG.md）採 hard delete，並同步移除 marketplace.json 內 codex-batch entry（如有列）。理由：user 已 explicit 確認 single source of truth、且 user 是該 marketplace 唯一 user、deprecation pointer 屬不必要 cruft。

Alternatives:

- 留 deprecation pointer（commands/codex-batch.md 改為一行「請裝 codex-pro@codex-pro 用 /codex-pro:batch」）：增加 cruft、雙源狀態混淆
- 不刪：違反 single source of truth、未來雙邊 diverge 風險

### D5: 外部 marketplace 與 codex-pro 的清理同步

刪除 psychquant-claude-plugins 內的 codex-batch plugin 需要：

1. 刪除 plugin 目錄整體
2. 從該 marketplace 的 marketplace.json 移除 codex-batch entry（若有列）
3. 同步 marketplace（用 `/plugin-tools:plugin-update` 或手動）

本 change 的 task 範圍涵蓋 step 1 與 step 2；step 3 屬 user 後續 marketplace 同步行為、不強制納入 task。

理由：plugin.json 與 marketplace.json 對齊 = single source of truth 的硬約束；marketplace cache reload 是 user 端機制，task 內 simulate 困難。

## Implementation Contract

#### Behavior

User 在 Claude Code 中（已安裝 codex-pro plugin）輸入 `/codex-pro:batch [task description]`，Claude 觸發 batch skill。Skill 與 user 互動收集：

- Reference file（large doc：textbook .tex / paper PDF text / 大型 spec 等）
- Chunks（chapter numbers / file list / section IDs）
- Prompt template（每 chunk 怎麼 prompt codex）
- Output directory（per-chunk result 寫哪）
- Model（default gpt-5.5）
- Reasoning effort（default xhigh）

然後產生 shell script（base 自 references/script-template.sh），跑 codex exec 對每 chunk 平行（`&` background + `wait` monitor）、輸出寫入 output dir、回報 progress。

行為與原 codex-batch slash command 完全相同（D1 採最小化轉型）。

#### Interface

- Skill identifier: `batch`
- 觸發名: `/codex-pro:batch`
- 入口檔: `plugins/codex-pro/skills/batch/SKILL.md`
- References: `plugins/codex-pro/skills/batch/references/script-template.sh`
- argument-hint: 沿用 `[task description]`
- 副作用: 寫 shell script、跑 codex exec subprocess、寫 output dir 內檔案（**有 mutating side effect**，與 setup skill 的 read-only 紀律不同）

#### File operations contract

執行四項 file operations：

1. 建立目錄: `plugins/codex-pro/skills/batch/.claude-plugin/`（如 references 結構需要）與 `plugins/codex-pro/skills/batch/references/`
2. 新建 SKILL.md（自原 codex-batch/commands/codex-batch.md 轉型，frontmatter 含 `name: batch`，body 中 trigger 句改 `/codex-pro:batch`）
3. 搬 script-template.sh：cp source → dest，sha256sum 兩端比對一致
4. 刪除 source plugin: psychquant-claude-plugins 內整個 codex-batch 目錄（用 rm -rf 等價操作）；若 marketplace.json 內有 codex-batch entry，從 plugins[] 移除

#### Failure modes

- SKILL.md frontmatter 結構錯誤 → Claude Code 載入失敗、skill 不出現於 `/help`
- script-template.sh 搬移時 sha256 不一致 → task 驗證 fail、必須 redo
- source plugin 刪除失敗（permission） → marketplace 狀態 inconsistent
- marketplace.json 同步漏掉 entry → user 跑 `/plugin marketplace update` 後仍見 codex-batch 條目、嘗試 install 失敗

#### Acceptance criteria

- `plugins/codex-pro/skills/batch/SKILL.md` 存在，frontmatter `name: batch`、description 與 source codex-batch.md 沿用
- `plugins/codex-pro/skills/batch/references/script-template.sh` 存在，sha256 與 source 一致
- 外部：psychquant-claude-plugins 內 codex-batch 目錄不存在
- 外部：psychquant-claude-plugins 的 marketplace.json 內 plugins[] 已無 codex-batch entry
- codex-pro CLAUDE.md 的 Commands surface 表新增 `/codex-pro:batch` 列
- codex-pro README.md 的 Skills 表新增 `batch` 列
- new spec `openspec/specs/batch/spec.md` 建立（archive 階段 sync 至 main spec）

#### Scope boundaries

In scope:

- 新建 batch skill 兩個 artifact（SKILL.md + script-template.sh）
- 刪除 psychquant-claude-plugins 內 codex-batch plugin 目錄
- 同步該 marketplace 的 marketplace.json plugins[]（如有列 codex-batch）
- CLAUDE.md Commands surface 表更新
- README.md Skills 表更新
- 新 spec batch 建立（ADDED Requirements）

Out of scope:

- psychquant-codex-plugins 內 codex-batch plugin
- parallel-ai-agents 任何檔案
- lean-prover 任何檔案
- 重寫 batch 邏輯（subprocess vs HTTPS direct 改造）
- codex-pro Design constraint #1 文字修改
- setup skill 任何變動
- marketplace cache reload（user 端操作）

## Risks / Trade-offs

- [SKILL.md trigger 句中 `/codex-pro:batch` 與 description 行為描述不一致] → 若 description 仍寫舊命令 `/codex:batch`，Claude 意圖匹配可能誤觸發。Mitigation: D1 規定 description 沿用、但 trigger 句明確改名；task 內 grep 驗證。
- [batch 為 Design constraint #1 的 explicit exception，未來其他 skill 可能援引此先例越界] → 未來 review/rescue 等 skill propose 時若以 batch 為 precedent 主張 subprocess，會破壞 constraint 紀律。Mitigation: D3 明列「exception 為 explicit allowed list」、其他 skill 屬 default deny；CLAUDE.md / spec 在 batch capability 內描述此例外為 batch-specific。
- [psychquant-claude-plugins 內 codex-batch 刪除 + marketplace.json 同步是 cross-repo 動作] → 若漏一步、marketplace 狀態斷裂、user 端 `/plugin update` 可能顯示衝突。Mitigation: task 4 與 task 5 強制 grep 驗證該 plugin 已不存在於 plugin dir 與 marketplace.json plugins[]。
