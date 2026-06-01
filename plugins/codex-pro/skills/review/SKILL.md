---
name: review
description: |
  對 code 跑 read-only Codex review — 接受三種 target：current uncommitted diff（無 argument）、specific file path、或 branch comparison（--base <ref>）。
  透過 codex-call HTTPS direct 執行（無 subprocess），結果寫入 .codex-pro/review-<timestamp>.md 結構化檔案，不直接 inline echo（避免 silent stub failure）。
  Findings 無數量上限。Rate limit / OAuth invalid / timeout 走 circuit-breaker fail-fast、不 retry。
  Use when: 使用者輸入 /codex-pro:review、或 review uncommitted changes、code review 在 commit 前。
  Trigger keywords: codex review, review code, review changes, review branch, review uncommitted
allowed-tools:
  - Bash
  - Read
---

# /codex-pro:review — Read-only Codex Review (v0.1 single oracle)

對 code 跑 single-oracle read-only review，產出結構化 findings 寫入 disk 檔案。本 skill 是 codex-pro 的第 3 個 capability，v0.1 為 minimal — 單一 reviewer、無 ensemble（多 reviewer 角色平行留 v0.2）。

## 行為原則

本 skill 嚴守 codex-pro **Design constraint #1**「No subprocess spawn for Codex — 一律走 codex-call HTTPS direct」。Review 為 single-shot codex call、不像 batch 需 fan-out parallel job control。因此 review 是 constraint #1 的 **default rule 代表**（與 batch 的 explicit exception 形成明顯對比）。

**Fail-fast 三條件**：下列三種 codex-call failure 觸發 circuit breaker、不 retry：

1. **Rate limit**（HTTP 429 或 output 含 "rate limit"）→ result file frontmatter 寫 `error: rate_limit`、提示等待 Codex tier 限額重置或升級
2. **OAuth invalid**（HTTP 401 或 output 含 "auth"）→ frontmatter 寫 `error: oauth_invalid`、提示跑 /codex-pro:setup 確認 token 狀態
3. **Hard timeout**（超過 --max-time 600 秒）→ frontmatter 寫 `error: timeout`、提示縮小 review target 或檢查 Codex tier

理由：retry 是 `openai/codex-plugin-cc` issue #306 的根因（無限 retry 吃光 Claude token cost）。Review 為 user-initiated、user-observable — fail 後由 user 自己決定 retry 而非 plugin 偷重 spawn。**「不 retry」紀律是 fail-fast circuit breaker 的核心**。

## Step 1: Parse argument

依以下 precedence 解析 review target：

- `--base <ref>`（flag）→ branch comparison：跑 `git diff <ref>...HEAD` 取 diff
- 顯式 file path argument（例 `plugins/codex-pro/skills/setup/SKILL.md`）→ Read 該檔內容
- 無 argument 或 `--diff`（預設）→ uncommitted diff：跑 `git diff` 取工作樹 diff

若 argument 同時含 path 與 `--base`，後者勝（branch 範圍涵蓋 single file）。若無 argument 且 `git diff` 為空（無 uncommitted changes）、abort 並提示 user 三種 target 形式。

## Step 2: Collect prompt

依 Step 1 結果取得 review 標的內容：

- diff target：將 `git diff` 或 `git diff <ref>...HEAD` 的 stdout 作為 prompt 主體
- file target：用 Read tool 讀整檔內容作為 prompt 主體（建議搭配檔案路徑 metadata 寫入 prompt header）

Prompt 主體交 Step 3 包裝 system instructions。

## Step 3: Build instructions

System instructions 內容（會傳給 codex-call 的 `--instructions` flag）：

```
You are a senior code reviewer. Review the following <diff | file | branch comparison>.

Output requirements:
- Begin with a one-paragraph Summary of overall assessment.
- Follow with a Findings list. Each finding MUST use the heading format
  "Finding N: <severity> — <file>:<line>" where severity is one of
  critical / high / medium / low / info.
- Each finding's body MUST contain a concise message describing the issue,
  followed by a single line starting with "**Suggestion:**" with concrete remediation.
- No findings cap — report ALL material issues you observe.
- Output format is Markdown. Do NOT wrap in code fences.
```

## Step 4: Invoke codex-call

呼叫 `codex-call` 寫結果到 `.codex-pro/review-<ISO8601-timestamp>.md`（首次跑 skill 需 `mkdir -p .codex-pro/`）：

```
codex-call \
  --output .codex-pro/review-<timestamp>.md \
  --model gpt-5.5 \
  --effort xhigh \
  --max-time 600 \
  --instructions "<Step 3 system instructions>" \
  --prompt-file <Step 2 prompt 寫入的暫存檔>
```

關鍵 flag：

- `--max-time 600`：10 分鐘 hard timeout、超過即 fail-fast 為 timeout
- `--model gpt-5.5`：codex-pro v0.1 預設 model
- `--effort xhigh`：review 任務需深度推理
- `--output <path>`：codex-call 直接寫 markdown 到該路徑（不 echo stdout）

**Skill 嚴禁 spawn `codex` CLI**。所有 review 必經 `codex-call` HTTPS direct。若未來 future skill 想 spawn subprocess，須在 design.md 明列 explicit exception（如 batch skill）並於 SKILL body 明文標記。

## Step 5: Handle exit code

依 codex-call exit code 與 stdout/stderr 內容決定 result file 構造：

**Success（exit 0）**：

- codex-call 已將 review markdown 寫入 `--output` 指定路徑
- skill 額外於 result file 開頭 prepend YAML frontmatter（6 個 field）：
  - `target`: `diff` 或 `file:<path>` 或 `branch:<ref>`
  - `model`: `gpt-5.5`（與 Step 4 一致）
  - `effort`: `xhigh`（與 Step 4 一致）
  - `timestamp`: ISO8601 含時區（例 `2026-06-01T08:30:48+08:00`）
  - `findings_count`: 解析 body 內 `### Finding N:` heading 數量
  - `error`: 不寫（success 不出現此 field）
- 回報 user：result file 路徑 + findings count

**Failure（exit non-zero）**：

依 stderr / output 內容判定 error class、寫 result file frontmatter `error` field、`findings_count: 0`、body 空或單行 error description：

| stderr/output 含 | frontmatter `error` 值 | 回報訊息 |
|---|---|---|
| `rate limit` / `429` | `rate_limit` | 「Codex 限額耗盡。等待限額重置或升級 tier 後重 retry。**不會自動 retry**。」 |
| `auth` / `401` / `unauthorized` | `oauth_invalid` | 「OAuth token 失效。跑 /codex-pro:setup 確認 ~/.codex/auth.json 狀態並重 login。」 |
| timeout / >600 秒 | `timeout` | 「Review 超過 10 分鐘 hard timeout。考慮縮小 review target（如 `--base` 指更近 ref、改 review 單檔），或檢查 Codex tier 處理速度。」 |

**所有 failure 仍寫 result file**（讓 user 有 trace、可從 frontmatter `error` field 觀察 fail mode 頻率）、**所有 failure 都不 retry**（fail-fast circuit-breaker 紀律、避免 #306 token-burn）。

## Result file structure（完整契約）

```
---
target: <diff | file:<path> | branch:<ref>>
model: gpt-5.5
effort: xhigh
timestamp: 2026-06-01T08:30:48+08:00
findings_count: <N>
error: <rate_limit | oauth_invalid | timeout>  # 僅 fail-fast 時出現
---

# Codex Review — <target descriptor>

## Summary

<one-paragraph overall assessment from Codex>

## Findings

### Finding 1: <severity> — <file>:<line>

<message>

**Suggestion:** <suggestion>

### Finding 2: <severity> — <file>:<line>

...
```

Fail-fast case：保留 frontmatter + 空 body 或單行 `Review aborted: <error description>`。
