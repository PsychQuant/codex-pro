## Context

`codex-pro` v0.1.0 已發布到 PsychQuant/codex-pro，含 setup + batch 兩個 capability。本 change 落地 `review` skill v0.1 作為第 3 個 capability，對標 `openai/codex-plugin-cc` 的 `/codex:review` 最常用命令。

設計核心：嚴守 codex-pro Design constraint #1「No subprocess spawn for Codex — 一律走 codex-call HTTPS direct」。Review 是 single-shot codex call、不像 batch 需要 fan-out parallel job control，所以是 constraint #1 的 default rule 最直接代表。透過此 skill 同時消除 codex-plugin-cc 的 4 大 review-related 痛點：
- subagent stub return (#324) → 走 codex-call + structured result file
- IPC pipe deadlock (#330) → 無 subprocess、純 HTTPS
- 無 circuit breaker (#306) → rate limit fail-fast、不 retry
- findings cap hardcode 3 (#298) → 無上限、所有 findings 全收

Ensemble pattern（多 reviewer 角色平行）為 v0.2 留作 future change，本 v0.1 為單 oracle review。

## Goals / Non-Goals

**Goals:**

- `/codex-pro:review` 可由 skill 觸發，支援 3 種 review target：current uncommitted diff、specific file path、branch comparison (`--base <ref>`)
- Review 透過 `codex-call` HTTPS direct 跑，**0 個 subprocess spawn 為 codex 用**
- Codex output 寫入 structured result file（`.codex-pro/review-<timestamp>.md`），不直接 echo
- Findings 結構：top-level summary + per-finding {file, line, severity, message, suggestion}
- Rate limit / OAuth invalid → fail-fast、明確錯誤訊息、不 retry
- 沿用 `codex-pro` 既有 7 條 Design constraints（特別是 #1 No subprocess、#3 Circuit breaker、#4 Structured result file）
- tests/review.sh 新 Layer 2 驗證 review skill 結構正確性 + circuit breaker 紀律

**Non-Goals:**

- 不實作 ensemble pattern（多 reviewer 平行）— 留 v0.2
- 不實作 `/codex-pro:adversarial-review` — 規劃中、另開 change
- 不發 GitHub Action / CI / 任何 background 持續 review
- 不改變 codex-pro v0.1.0 既有 4 個 archived changes 的 spec
- 不改變 setup / batch skill 行為
- 不引入新 runtime dependency（codex-call 已是現有依賴）
- 不支援 Windows
- 不寫 review result 到 git index / commit（純 disk file 給 user 看）
- 不對 review 結果做 auto-fix / auto-apply suggestion（user 自己決定）

## Decisions

### D1: codex-call invocation 採 single-shot + hard timeout + no retry

呼叫 `codex-call` 時：
- `--max-time 600`（10 分鐘 hard timeout，per parallel-ai-agents/CLAUDE.md 既有約定）
- `--model gpt-5.5`（codex-pro v0.1 預設）
- `--effort xhigh`（review 任務需要深度推理）
- `--output <result-file-path>`
- `--instructions` 載入 review system prompt
- `--prompt-file` 載入 diff / file content as prompt

失敗時不 retry：
- Rate limit (HTTP 429)：codex-call exit non-zero → skill report fail + remediation message
- OAuth invalid：codex-call exit non-zero → skill 提示 user 跑 `/codex-pro:setup` 確認環境
- Network error / hard timeout：fail-fast、不 retry

理由：retry 是 codex-plugin-cc #306 的根因（無限循環 cost 失控）。Review 任務是 user-initiated、user-observable — fail 後 user 自己決定是否再跑、由 user 提供 retry consent，而非 plugin 偷偷重 spawn。

Alternatives:

- 自動 retry 一次：違反 circuit breaker 紀律、且 review 失敗 ≠ transient（rate limit 通常持續分鐘級）
- Exponential backoff：增加複雜度、user 仍要等、且 review 完整 fail 也許比一直等更好

### D2: Review target 三選一 + auto-detect

Skill 接受三種 review target，由 argument 形式區分：

- 無 argument 或 `--diff`：跑 `git diff` 拿 uncommitted changes 作 prompt 輸入
- File path argument（例 `plugins/codex-pro/skills/setup/SKILL.md`）：用 Read 拿該檔內容
- `--base <ref>` flag（例 `--base main`）：跑 `git diff <ref>...HEAD` 拿 branch diff

Auto-detect 順序：argument 顯式 flag > 顯式 path > 預設 uncommitted diff。若 argument 同時含 path + `--base`，後者勝（branch comparison 範圍涵蓋 path）。

理由：對齊 `codex-plugin-cc` 的 `/codex:review` argument 約定（drop-in 相容）；user 從 codex-plugin-cc 切過來不用重學。

Alternatives:

- 強制必填 argument：對「我剛 stage 完想 review」最常見場景增加 friction
- 用 sub-command（`/codex-pro:review file <path>`、`/codex-pro:review branch <ref>`）：增加 namespace、與 codex-plugin-cc 不對齊

### D3: Result file 採 markdown + YAML frontmatter

寫入 `.codex-pro/review-<ISO8601-timestamp>.md`。結構（完整 literal sample 見 spec.md 的「Review output is a structured Markdown result file」requirement）：

- **YAML frontmatter**（6 個 field）：`target`（`diff` / `file:<path>` / `branch:<ref>`）、`model`（預設 `gpt-5.5`）、`effort`（預設 `xhigh`）、`timestamp`（ISO8601 含時區，例如 `2026-05-26T10:11:20+08:00`）、`findings_count`（整數、fail-fast 為 0）、optional `error`（`rate_limit` / `oauth_invalid` / `timeout`）
- **Body H1**：`Codex Review — <target descriptor>`
- **Body 兩個 H2 section**：`Summary`（codex 一段話 overall assessment）與 `Findings`
- **Findings 內每筆**：用 H3 heading「`Finding <N>: <severity> — <file>:<line>`」開頭，緊接 message 段落，再緊接 `**Suggestion:**` 一行帶建議

`.codex-pro/` 目錄首次跑時 skill 自動 `mkdir -p`。檔名用 ISO8601 timestamp（含時區）避免 collision、且可按時間排序。

理由：

- Markdown 對 user 可讀、對 LLM 可解析、且 codex-call `--output` 直接寫成 markdown 是現成 capability
- Frontmatter 把 metadata 與內容分離、未來 jobs-status 可從 frontmatter 列 review 歷史
- Per-finding 用 H3 + severity + file:line 結構讓 grep / parse 都方便

Alternatives:

- JSON：機器友好但 user 直接讀痛苦；要再轉 markdown 多一步
- Plain text：失去結構、無法 grep findings_count

### D4: Circuit breaker 紀律 — fail-fast 三條件

下列三種錯誤觸發 fail-fast（skill exit non-zero、寫 error 訊息到 result file frontmatter `error:` field、不 retry）：

1. **Rate limit**（codex-call exit non-zero 含 "rate limit" 或 HTTP 429 訊息）：result file frontmatter 寫 `error: rate_limit`、訊息含「等待 Codex tier 限額重置或升級 tier」
2. **OAuth invalid**（codex-call exit non-zero 含 "auth" 或 401）：frontmatter 寫 `error: oauth_invalid`、訊息含「跑 /codex-pro:setup 確認 OAuth token 狀態」
3. **Hard timeout**（超過 `--max-time 600`）：frontmatter 寫 `error: timeout`、訊息含「review target 過大或 codex tier slow、考慮縮小範圍重跑」

所有 fail-fast case 仍寫 result file（讓 user 有 trace）、但 frontmatter 標明 error type 且 body 空（無 findings）。

理由：紀錄失敗本身 = circuit breaker observable state、便於 jobs-status 列 history 看 success rate。

Alternatives:

- 失敗不寫 result file：失敗成 invisible、user 不知道剛剛 review 有跑沒跑
- 把 error 寫進 frontmatter 但 body 寫 stub findings：違反「無 silent stub」紀律

### D5: SKILL.md body 結構與 batch 的對比

SKILL.md 強調 review 嚴守 Design constraint #1（與 batch 是 exception 形成 contrast）。body 結構：

1. **行為原則**段：強調「走 codex-call HTTPS direct、無 subprocess、嚴守 Design constraint #1」、明確列出 fail-fast 三條件
2. **Step 1: Parse argument**：判斷 target（diff / file / branch）
3. **Step 2: Collect prompt**：用 Bash `git diff` 或 Read tool 取得 review 標的內容
4. **Step 3: Build instructions**：載入 review system prompt（內含 「output findings as markdown sections with severity」格式要求）
5. **Step 4: Invoke codex-call**：含 `--max-time 600 --model gpt-5.5 --effort xhigh --output .codex-pro/review-<ts>.md`
6. **Step 5: Handle exit code**：success → 顯示 result file path 與 findings count；fail → 寫 frontmatter error 並回報 fail-fast reason

理由：與 batch SKILL.md 的「explicit exception」段落形成明顯對比 — review SKILL.md 內無 "exception" 字眼，反而強調 strict adherence。Future skill 加入時看 batch vs review 一眼分得清「我屬於 default rule（review pattern）還是 explicit exception（batch pattern）」。

Alternatives:

- 跟 batch 用同 SKILL 模板：模糊 default vs exception 邊界、未來 reviewer 容易誤援引 exception

### D6: tests/review.sh 採 Layer 2 + Layer 1 兩層 cover

Layer 2 (`tests/review.sh`) 跑 5+ behavioral assertions：
1. SKILL.md frontmatter `name: review`、`allowed-tools` 含 Bash + Read
2. SKILL.md body 明示 codex-call 為主要 invocation（grep `codex-call` ≥ 1）
3. SKILL.md body 明示 fail-fast 三條件（grep `rate_limit` / `oauth_invalid` / `timeout` 各 ≥ 1）
4. SKILL.md body **不**含 `codex exec` 字串（嚴守 Design constraint #1，與 batch 對比）
5. SKILL.md body 含 result file 路徑模板 `.codex-pro/review-`

Layer 1 (`tests/static.sh` 既有 frontmatter loop)：review SKILL.md 自動納入既有 for-loop（loops through `plugins/codex-pro/skills/*/`），自動驗 frontmatter 結構。

Layer 1 (`tests/static.sh` 新增 namespace consistency check)：grep `/codex-pro:review` 至少出現在 CLAUDE.md Commands surface 表 + README.md Skills 表 + spec。

`tests/run.sh` dispatcher 在現有 static / setup / batch 後加 review layer。

理由：跟 setup / batch 同 Layer 2 pattern（per-skill 結構性 + 行為性 grep）。Static 在既有 loop 自動 cover、不需特殊改動。

Alternatives:

- 不寫 review.sh、只靠 static.sh frontmatter loop：失去「fail-fast 紀律 grep」與「無 codex exec 字串」這兩條重要 invariant 的編碼
- 把 review-specific assertion 塞 static.sh：違反 layer split（Layer 1 純結構、Layer 2 行為）

## Implementation Contract

#### Behavior

User 在 Claude Code 中跑 `/codex-pro:review`（可選 argument：file path / `--base <ref>` / 無 argument 走 uncommitted diff）。Skill 觸發後：

1. 解析 argument 判定 review target
2. 收集 prompt（git diff 或 file content）
3. 呼叫 `codex-call --output .codex-pro/review-<ISO8601>.md` 跑 HTTPS direct（**無 subprocess 為 codex**）
4. 成功：回報 result file path + findings count
5. 失敗：result file frontmatter 寫 error type、回報 remediation message、**不 retry**

#### Interface

- Skill identifier: `review`
- 觸發名: `/codex-pro:review`
- 入口檔: `plugins/codex-pro/skills/review/SKILL.md`
- Argument: 無 / `<file-path>` / `--base <ref>`
- 副作用: 建 `.codex-pro/` 目錄（若不存在）、寫入 `.codex-pro/review-<timestamp>.md`（非 read-only、但 idempotent — 每次跑產新檔）

#### Result file contract

YAML frontmatter required fields：
- `target`: `diff` 或 `file:<path>` 或 `branch:<ref>`
- `model`: 預設 `gpt-5.5`
- `effort`: 預設 `xhigh`
- `timestamp`: ISO8601（含時區）
- `findings_count`: 整數（fail-fast case 為 0）
- `error`（optional）: `rate_limit` / `oauth_invalid` / `timeout`（fail-fast 時必填）

Body（success case）：
- `## Summary`：one-paragraph overall assessment
- `## Findings`：每 finding 一個 `### Finding N: <severity> — <file>:<line>` block，含 message + `**Suggestion:**` line

Body（fail-fast case）：空 body 或單行 error description。

#### Failure modes

- codex-call exit non-zero 含 "rate limit" / HTTP 429 → frontmatter `error: rate_limit`、不 retry
- codex-call exit non-zero 含 "auth" / 401 → frontmatter `error: oauth_invalid`、訊息引導 /codex-pro:setup
- codex-call 超過 `--max-time 600` → frontmatter `error: timeout`、訊息引導縮小 review 範圍
- `.codex-pro/` mkdir 失敗（permission）→ skill abort、不寫 result file、回報 disk permission 問題
- git diff 為空（無 uncommitted changes）→ skill abort、訊息「無 review target、傳 file path 或 --base」

#### Acceptance criteria

- `/codex-pro:review` 在 Claude Code 內可由 skill 觸發
- 跑成功時：`.codex-pro/review-<timestamp>.md` 存在、含 YAML frontmatter + Summary + Findings
- 跑失敗（fail-fast 三種 case）：result file 仍存在、frontmatter `error` field 標明 type、`findings_count: 0`
- SKILL.md 不含 `codex exec` 字串（嚴守 Design constraint #1）
- SKILL.md 含 `codex-call` 字串 ≥ 1
- tests/run.sh 加 review.sh 後仍全綠（assertions count 從 47 增加 ~5 個）
- CLAUDE.md / README.md namespace consistency 仍 pass（無 `/codex-pro-review-*` 舊 namespace、`/codex-pro:review` 出現於 Commands surface / Skills 表）

#### Scope boundaries

In scope:

- 新建 review skill: `plugins/codex-pro/skills/review/SKILL.md`
- 新建 Layer 2 test: `tests/review.sh`
- 修改 tests/run.sh dispatcher 加 review layer
- 修改 CLAUDE.md Commands surface 表（review 從規劃中改已落地）
- 修改 README.md Skills 表
- 新 spec: `openspec/specs/review/spec.md`

Out of scope:

- ensemble pattern / adversarial-review（v0.2 / 另開 change）
- jobs-status / jobs-cancel（後續 capability）
- 任何 setup / batch / tests 既有 spec 修改
- codex-call wrapper 自身修改（屬 parallel-ai-agents）
- Windows 支援
- Auto-fix / auto-apply review suggestion

## Risks / Trade-offs

- [Result file 累積在 .codex-pro/] → user 跑多次後目錄充滿歷史 review 檔。Mitigation: 不在本 change 處理 cleanup（YAGNI、user 可手動 rm；future jobs-status capability 可加 retention policy）。`.codex-pro/` 該加進 `.gitignore` 避免不小心 commit review log。
- [findings_count 無上限 cost 風險] → 大 PR review 可能 codex 回幾十條 findings、token cost 高。Mitigation: hard timeout 600s 限制 codex 推理時間、間接限制 output size；user 可用 `--base` 縮小 scope。
- [fail-fast 不 retry vs upstream rate limit transient] → user 撞 rate limit 後要手動 retry。Mitigation: error message 明確 + jobs-status capability future 可加「last fail timestamp」幫助 user 判斷何時可重 retry。
- [git diff 為空時 skill abort 可能違反 user 直覺] → user 跑 `/codex-pro:review` 但忘了 stage / commit，預期 review 但得到 abort。Mitigation: abort 訊息明確列三種 target 選項，user 一看就知怎麼補。
