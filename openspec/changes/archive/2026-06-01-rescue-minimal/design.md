## Context

`codex-pro` 走完 6 個 archive cycle，已有 setup / batch / review 三個 user-facing capability。`/codex-pro:rescue` 是對齊 codex-plugin-cc 痛點地圖的第 4 個必要 capability — 同時是 #324 subagent stub return 的根因解法。

設計核心：rescue 與 review 共享同一套基礎契約（codex-call HTTPS direct + structured result file + fail-fast circuit breaker），但 **mental model 不同**：review 是「對既有 code 跑診斷、產出 findings」、rescue 是「把待解任務交給 Codex、產出 outcome + 後續建議」。這個差異對應到 result file 結構（review 的 Findings vs rescue 的 Outcome + Next Steps）與 fail-fast 類別（rescue 新增 `task_unclear` 第 4 類）。

延續 review-minimal 已驗證的紀律：
- codex-call HTTPS direct（無 subprocess、嚴守 Design constraint #1）
- 結果寫入 `.codex-pro/` disk file（無 inline echo、消除 #324 silent stub）
- Hard timeout 600s（無 unbound wait）
- Fail-fast 不 retry（消除 #306 token-burn）

新引入：
- `--resume <session-id>` 接續 previous rescue session（v0.1 minimal 走 codex-call session ID 傳遞）
- `--fresh` 顯式新 session（預設行為的明示形式）
- `task_unclear` fail-fast 第 4 類

## Goals / Non-Goals

**Goals:**

- `/codex-pro:rescue` 接 task description（必填）、optional context files（path list）、optional completion criteria（文字描述）
- 透過 codex-call HTTPS direct 跑、**0 個 subprocess spawn 為 codex 用**（嚴守 #1）
- Result file 寫 `.codex-pro/rescue-<ISO8601>.md`，含 frontmatter (6+ fields) + Task Brief + Outcome + Suggested Next Steps 三 section
- Fail-fast 4 類：rate_limit / oauth_invalid / timeout / task_unclear，**不 retry**
- `--resume <id>` 與 `--fresh` flag 支援、session ID 寫進 result file frontmatter
- tests/rescue.sh Layer 2 驗證

**Non-Goals:**

- 不實作 ensemble pattern（多 reviewer 留 v0.2、與 review-v2 同步考慮）
- 不自建 session manager（透過 codex-call 既有 session 機制即可）
- 不實作 background job 排程（user 觸發 → 同步等 → 寫檔回報，無 background queue）
- 不實作 auto-apply Codex 的 suggested changes（user 自己決定是否套用、與 review v0.1 同紀律）
- 不改變 setup / batch / review / tests 既有 spec
- 不引入新 runtime dependency（codex-call 已是現有依賴）
- 不支援 Windows
- 不寫 rescue result 到 git index / commit

## Decisions

### D1: codex-call invocation 沿用 review pattern + 加 session flag

呼叫 `codex-call` 時 base flags 與 review 同：

- `--max-time 600`（10 分鐘 hard timeout、與 review 同）
- `--model gpt-5.5`（codex-pro v0.1 預設）
- `--effort xhigh`（rescue 任務需深度推理）
- `--output <result-file-path>`
- `--instructions <rescue system prompt>`
- `--prompt-file <task brief + context>`

新增 session flag：

- `--session <id>`：當 user 給 `--resume <id>` 時傳遞、接續 previous session
- 不傳 `--session`（預設或 `--fresh`）→ codex-call 開新 session ID、寫進 result file frontmatter

失敗紀律與 review 一致 — 不 retry。

理由：review pattern 已 production-tested（79 assertions、6 個 archived changes 累積信心）、複用降低 surface area 風險。codex-call 的 session flag 是 wrapper 既有功能、不需擴充。

Alternatives:

- 自建 session manager（local JSON 紀錄 session ↔ thread）：v0.1 scope creep、user feedback 後再評估
- 自動 retry 一次：違反 fail-fast、與 review 紀律不一致

### D2: Task delegation 結構 — 三欄輸入

Skill 接 argument 解析三類資訊：

1. **Task description**（必填）：argument 本體或第一個非 flag 段（例 `/codex-pro:rescue 修復 .codex/auth.json TCC 問題`）
2. **Context files**（optional）：`--context <path>`（可多次）→ Read 該檔內容附入 prompt header
3. **Completion criteria**（optional）：`--criteria "<text>"` → 附入 instructions 作為 success rubric

若 task description 為空、abort 並提示「`/codex-pro:rescue <task description> [--context <path>...] [--criteria <text>]` [--resume <id>] [--fresh]`」usage hint。

理由：對齊 codex-plugin-cc rescue 的 mental model — task delegation 比 review 多了「what does done look like」的語意需求。Completion criteria 顯式化幫 Codex 自我驗收、降低 outcome unclear 機率。

Alternatives:

- 不接 completion criteria（只接 task）：rescue 任務難明確收尾、增加 task_unclear 機率
- 把 context 限制為單檔：限制 user 想交 multi-file context 場景的 ergonomic

### D3: Result file 結構 — frontmatter + 三 section

寫入 `.codex-pro/rescue-<ISO8601-timestamp>.md`。結構（完整 literal sample 見 spec.md「Rescue output is a structured Markdown result file」requirement）：

- **YAML frontmatter（8 個 field）**：`task_description`（user 提供的 task brief 截斷至 200 char）、`session_id`（codex-call 回傳的 session ID）、`resume_from`（若 `--resume` 提供，記原 session ID）、`model`（gpt-5.5）、`effort`（xhigh）、`timestamp`（ISO8601 含時區）、`outcome`（codex 回的結論分類）、optional `error`（fail-fast 時填入 4 類之一）
- **Body H1**：`Codex Rescue — <task-brief excerpt>`
- **Body 三 section**：
  - `## Task Brief`：user 提供的完整 task description + context files 摘要
  - `## Outcome`：Codex 的解法說明（可含 code block、解釋、reasoning trace）
  - `## Suggested Next Steps`：列出可選後續行動（user 自己決定是否套用）

`outcome` frontmatter field 採枚舉：`completed`（Codex 給了 actionable solution）、`partial`（部分解、需 user follow-up）、`unclear`（task 描述過模糊、Codex 無法 commit 答案）、`requires_external`（需 user 提供額外資訊才能 proceed）。`unclear` 同時觸發 `error: task_unclear` 走 fail-fast。

`.codex-pro/` 目錄首次跑時 skill 自動 `mkdir -p`（與 review 同模板）。檔名用 ISO8601 timestamp 避免 collision。

理由：

- 三 section 結構對應 task delegation 的自然流程（input → output → followup）
- `outcome` 分類比 review 的 findings_count 更語意化、user 一眼判斷 rescue 是否成功
- `requires_external` 是 codex-plugin-cc rescue 漏洞 — Codex 卡在「需要 user 提供 X」但默默回 stub；本 design 強制這狀況顯式化

Alternatives:

- 只用兩 section（Outcome 與 Suggestions 合併）：對複雜 rescue 結果可讀性差
- outcome 不分類（純自由文字）：失去 fail-fast `task_unclear` 的編碼依據

### D4: Fail-fast 4 類（review 3 類 + task_unclear）

下列四種錯誤觸發 fail-fast（不 retry、result file frontmatter 寫 `error` field、`outcome: unclear` 或對應 error class）：

1. **Rate limit**（HTTP 429 / output 含 "rate limit"）→ `error: rate_limit`、訊息建議等限額重置
2. **OAuth invalid**（HTTP 401 / output 含 "auth"）→ `error: oauth_invalid`、訊息引導 /codex-pro:setup
3. **Hard timeout**（>600s）→ `error: timeout`、訊息建議縮小 task scope 或拆 sub-task
4. **Task unclear**（Codex output 顯示 outcome `unclear`，或顯式拒絕 commit answer）→ `error: task_unclear`、訊息建議 user 補 completion criteria 或拆細 task

所有 fail-fast case 仍寫 result file（frontmatter `error` + outcome `unclear` + body 空或單行 description）。

理由：第 4 類 `task_unclear` 是 rescue-specific、與 review 差異化。它把 codex-plugin-cc rescue 的 silent stub 痛點（#324）從「Codex 假裝有答案」轉成「Codex 明示說不知道」、user 一看 result file frontmatter 即明白要補資訊。

Alternatives:

- 不引入 task_unclear、退回 review 3 類：silent stub 痛點無編碼依據、紀律 weak
- task_unclear 觸發自動 retry with refined prompt：違反 fail-fast、user 應主動補 context 而非 plugin 偷做

### D5: SKILL.md body 結構 — 與 review 共享 default rule pattern

SKILL.md 結構與 review SKILL.md 對齊（複用心智模型）：

1. **行為原則**段：強調走 codex-call HTTPS direct（與 review 同 default rule）、列出 fail-fast 4 類、明示「不 retry」
2. **Step 1: Parse argument**：判斷 task description + optional --context + --criteria + --resume/--fresh
3. **Step 2: Collect prompt**：包裝 task description + context file 內容 + completion criteria（若有）
4. **Step 3: Build instructions**：載入 rescue system prompt（含「output format：## Task Brief / ## Outcome / ## Suggested Next Steps + frontmatter outcome enum」要求）
5. **Step 4: Invoke codex-call**：傳 base flags + 可選 `--session <id>` (when `--resume`)
6. **Step 5: Handle exit code**：success → 寫 frontmatter + 顯示 result file path；failure → 4 類 error class 處理

理由：與 review 同 pattern 降低未來維護者學習成本。SKILL.md 內**不含 `codex exec` 字串**（嚴守 #1、與 batch 對比、與 review 對齊）。

Alternatives:

- 抽共用「rescue + review base pattern」到單一 helper：v0.1 scope creep、且 SKILL.md 是 LLM 看的 markdown 不是程式碼、無法簡單抽 helper
- rescue body 完全自由結構：失去與 review 的對比、新 reviewer 要 onboard 兩種 SKILL pattern

### D6: tests/rescue.sh + static.sh 自動 cover

Layer 2 (`tests/rescue.sh`) 跑 ~18 個 assertion（與 review.sh 規模相近、結構複用）：

1. SKILL.md frontmatter parse — name=rescue、allowed-tools 含 Bash + Read
2. SKILL.md body grep `codex-call` ≥ 1（default rule、不是 exception）
3. SKILL.md body grep `codex exec` 等於 0（嚴守 #1）
4. SKILL.md body grep `--max-time 600` ≥ 1
5. SKILL.md body grep 4 個 fail-fast error class 字串各 ≥ 1（rate_limit、oauth_invalid、timeout、task_unclear）
6. SKILL.md body grep `不 retry` 或 `fail-fast` ≥ 1
7. SKILL.md body grep `.codex-pro/rescue-` ≥ 1
8. SKILL.md body grep `## Task Brief` / `## Outcome` / `## Suggested Next Steps` 各 ≥ 1
9. SKILL.md body grep 8 個 frontmatter field 字串各 ≥ 1（task_description、session_id、resume_from、model、effort、timestamp、outcome、error）
10. SKILL.md body grep `--resume` 與 `--fresh` 各 ≥ 1
11. SKILL.md body grep `outcome enum` 4 個值字串各 ≥ 1（completed、partial、unclear、requires_external）

Layer 1 (`tests/static.sh` 既有 frontmatter loop)：rescue SKILL.md 自動納入 既有 for-loop（loops through `plugins/codex-pro/skills/*/`），自動驗 frontmatter 結構。

Layer 1 (`tests/static.sh` 既有 per-skill namespace loop)：rescue namespace 自動納入 `/codex-pro:rescue` 在 CLAUDE.md + README.md + spec 各驗一次。

`tests/run.sh` dispatcher 在現有 static / setup / batch / review 後加 rescue layer。

理由：與 review 同模板、test 紀律可預測。Per-skill namespace loop 從 review-minimal 引入後已自動 cover 新 skill、不需改 test code。

Alternatives:

- 不寫 rescue.sh、純靠 static 自動 cover：失去 rescue-specific invariants（task_unclear、--resume、outcome enum）的編碼
- 把 outcome enum 假設與 fail-fast 4 類合併進 review.sh：違反 layer split

## Implementation Contract

#### Behavior

User 在 Claude Code 中跑 `/codex-pro:rescue <task description> [--context <path>...] [--criteria <text>] [--resume <session-id>] [--fresh]`。Skill 觸發後：

1. 解析 argument 判定 task description + optional flags
2. 收集 prompt（task brief + context file 內容 + completion criteria）
3. 呼叫 `codex-call --output .codex-pro/rescue-<ISO8601>.md`（**無 subprocess 為 codex**）含 base flags + 可選 `--session <id>`
4. 成功：回報 result file path + outcome classification（completed / partial / unclear / requires_external）+ session_id（讓 user 後續可 --resume）
5. 失敗：result file frontmatter 寫 4 類 error 之一、**不 retry**

#### Interface

- Skill identifier: `rescue`
- 觸發名: `/codex-pro:rescue`
- 入口檔: `plugins/codex-pro/skills/rescue/SKILL.md`
- Argument:
  - `<task description>`（位置參數、必填）
  - `--context <path>`（可多次重複）
  - `--criteria <text>`
  - `--resume <session-id>` 與 `--fresh`（mutually exclusive、後者為預設）
- 副作用: 建 `.codex-pro/` 目錄（首次）、寫入 `.codex-pro/rescue-<timestamp>.md`（**非 read-only**、idempotent — 每次跑產新檔）

#### Result file contract

YAML frontmatter required fields：

- `task_description`: user 提供 task brief（截至 200 char）
- `session_id`: codex-call 回傳的 session ID（鬼接 --resume）
- `resume_from`: 若 `--resume <id>` 提供、記原 session ID；否則不出現
- `model`: 預設 `gpt-5.5`
- `effort`: 預設 `xhigh`
- `timestamp`: ISO8601 含時區
- `outcome`: 枚舉值 `completed` / `partial` / `unclear` / `requires_external`
- `error`（optional）: `rate_limit` / `oauth_invalid` / `timeout` / `task_unclear`（fail-fast 時必填）

Body（success / partial / requires_external case）：

- `## Task Brief`：user input 完整重述
- `## Outcome`：Codex 的解法、解釋或 reasoning
- `## Suggested Next Steps`：列出 follow-up 行動

Body（fail-fast case）：空或單行 error description。

#### Failure modes

- `codex-call` exit non-zero 含 "rate limit" / 429 → frontmatter `error: rate_limit`、不 retry
- `codex-call` exit non-zero 含 "auth" / 401 → frontmatter `error: oauth_invalid`、訊息引導 /codex-pro:setup
- `codex-call` 超過 --max-time 600 → frontmatter `error: timeout`、訊息引導 task scope 縮小
- Codex output 顯示 outcome unclear → frontmatter `error: task_unclear`、outcome `unclear`、訊息引導補 completion criteria
- `.codex-pro/` mkdir 失敗（permission）→ abort、不寫 result file、回報 disk permission 問題
- Task description 為空 → abort、提示 usage hint

#### Acceptance criteria

- `/codex-pro:rescue <task>` 在 Claude Code 內可由 skill 觸發
- 跑成功時：`.codex-pro/rescue-<timestamp>.md` 存在、含 8 個 required frontmatter fields + 三 section body
- 跑失敗（fail-fast 4 種 case）：result file 仍存在、frontmatter `error` 與 `outcome` 對應、不 retry
- SKILL.md 不含 `codex exec` 字串（嚴守 Design constraint #1、與 batch 對比）
- SKILL.md 含 `codex-call` ≥ 1、`--max-time 600` ≥ 1、`--resume` ≥ 1、`--fresh` ≥ 1
- tests/run.sh 加 rescue.sh 後仍全綠（aggregate assertions 從 79 上升 ~18+5 = 102 左右）
- CLAUDE.md / README.md namespace consistency 仍 pass（新 `/codex-pro:rescue` 出現於 Commands surface 與 Skills 表）

#### Scope boundaries

In scope:

- 新建 rescue skill: `plugins/codex-pro/skills/rescue/SKILL.md`
- 新建 Layer 2 test: `tests/rescue.sh`
- 修改 tests/run.sh dispatcher 加 rescue layer
- 修改 CLAUDE.md Commands surface 表（rescue 從規劃中改已落地）
- 修改 README.md Skills 表
- 新 spec: `openspec/specs/rescue/spec.md`

Out of scope:

- ensemble pattern / multi-reviewer rescue（留 v0.2）
- 自建 session manager（v0.1 走 codex-call 既有機制）
- background queue / async rescue job（v0.1 為同步）
- Auto-apply Codex suggested changes（user 決定）
- 任何 setup / batch / review / tests 既有 spec 修改
- codex-call wrapper 自身修改（屬 parallel-ai-agents）
- Windows 支援

## Risks / Trade-offs

- [Result file 累積在 .codex-pro/] → user 跑多次後目錄充滿 review 與 rescue 歷史檔。Mitigation: 不在本 change 處理 cleanup（YAGNI、與 review 同處理；future jobs-status 加 retention policy）。`.codex-pro/` 該已在 `.gitignore` 或加進去。
- [task_unclear 第 4 類錯誤分類仰賴 Codex 自我判斷] → Codex 可能 confident wrong（誤判 task 為 completed 但其實沒解）。Mitigation: completion criteria flag 強化 Codex 自我驗收、且 result file outcome enum 與 body 必須對齊（test 可加 assertion，但 v0.1 留 manual review）。
- [`--resume` flag 依賴 codex-call session 機制] → 若 parallel-ai-agents 升級 codex-call 改 session API，rescue --resume 行為破。Mitigation: SKILL.md 明白 reference codex-call 文件、tests/rescue.sh 抓 flag 字串而非實際跑（rescue 行為層測試屬手動）。
- [task description 解析的 argument 形式可能模糊（user 寫 `--resume xyz` 在 task 中間）] → SKILL.md Step 1 需明確 parser 規則：所有 `--flag value` 對先抽出、剩餘合為 task description。Mitigation: SKILL body 列範例 + tests 驗 SKILL 含「argument parsing」段落 grep。
- [與 review v0.1 模板高度共享] → 未來 review / rescue 同步演化需手動同步兩處 SKILL.md。Mitigation: design.md D5 明列共享原則、tests 內 namespace 與 codex-call 主 invocation 紀律 assertion 在 review.sh + rescue.sh 各自編碼、drift 立即可見。
