---
name: codex-rescue
description: |
  把難題交給 Codex 處理（task delegation）。接收 task description + optional context files (--context) + optional completion criteria (--criteria)，包成 prompt 交 codex-call HTTPS direct 跑（無 subprocess），結果寫入 .codex-pro/rescue-<timestamp>.md 結構化檔案。
  v0.1.1 stateless only — session continuity 暫已移除（known limitation，待 upstream codex-call 加 session support 後 restore）。
  v0.2 — profile-aware：`--model` / `--effort` / `--max-time` 從 `~/.codex-pro/profile.yaml`（global）+ `.codex-pro/profile.yaml`（project）resolve；未設 profile 時沿用 hardcoded default（gpt-5.6-sol / xhigh / 600）；已設 profile 者 100% backward compatible。見 `/codex-pro:codex-config`。
  Fail-fast 4 類：rate_limit / oauth_invalid / timeout / task_unclear（Codex 無法 commit 答案時的 rescue-specific 第 4 類）。**不 retry**。
  Use when: 使用者輸入 /codex-pro:codex-rescue、需要把 hard problem 交給 Codex 解、debug / refactor / 解 bug 卡住 fallback。
  Trigger keywords: codex rescue, delegate to codex, rescue task, ask codex
allowed-tools:
  - Bash
  - Read
---

# /codex-pro:codex-rescue — Task Delegation to Codex (v0.1 single oracle)

把 user 指定的 task 交給 Codex 處理、收集 outcome 寫入 disk 檔案。本 skill 是 codex-pro 的第 4 個 user-facing capability，v0.1 為 minimal — 單一 oracle delegation、無 ensemble（多 reviewer 角色平行留 v0.2）。

## 行為原則

本 skill 嚴守 codex-pro **Design constraint #1**「No subprocess spawn for Codex — 一律走 codex-call HTTPS direct」。Rescue 為 single-shot task delegation、與 review 同屬 constraint #1 的 **default rule 範例**（與 batch 的 explicit exception 形成明顯對比）。

**Fail-fast 4 條件**：下列四種 failure 觸發 circuit breaker、不 retry：

1. **Rate limit**（HTTP 429 或 output 含 "rate limit"）→ result file frontmatter 寫 `error: rate_limit`、提示等待 Codex tier 限額重置
2. **OAuth invalid**（HTTP 401 或 output 含 "auth"）→ frontmatter 寫 `error: oauth_invalid`、提示跑 /codex-pro:codex-setup 確認 token 狀態
3. **Hard timeout**（超過 --max-time 600 秒）→ frontmatter 寫 `error: timeout`、提示縮小 task scope 或拆細
4. **Task unclear**（Codex 自我回報 outcome `unclear` 或無法 commit 答案）→ frontmatter 寫 `error: task_unclear`、`outcome: unclear`、提示補 `--criteria` 或拆細 task。**這條是 rescue-specific 第 4 類**（review 沒有）— 把「Codex 不知道答案」變成 first-class 顯式 state、消除 `openai/codex-plugin-cc` issue #324 silent stub return 痛點

理由：retry 是 `openai/codex-plugin-cc` issue #306 的根因（無限 retry 吃光 Claude token cost）。Rescue 為 user-initiated、user-observable — fail 後由 user 自己決定是否重 invoke 而非 plugin 偷重 spawn。**「不 retry」紀律是 fail-fast circuit breaker 的核心**。

## Step 1: Parse argument

解析 argument 為三欄輸入：

- **Task description**（必填）：所有非 flag 段落合併成 task brief
- **`--context <path>`**（optional、可多次重複）：Read 該檔內容、附入 prompt header 作為額外 context
- **`--criteria <text>`**（optional）：附入 instructions 作為 success rubric（completion criteria）

若 task description 為空（純 flag 或空 argument）→ abort 並提示 usage：`/codex-pro:codex-rescue <task description> [--context <path>...] [--criteria <text>]`。

**Session continuity 已於 v0.1.1 移除**（known limitation）：本 skill 不再接受 session continuity flag。若 user 傳入任何 session-related flag、skill 必須 abort 並回報「session continuity removed in v0.1.1 — 待 upstream `codex-call` 加 session flag support 後 restore」。Rescue 在 v0.1.1 永遠 stateless — 每次 invoke 都是新的 codex-call HTTPS 呼叫，rescue v0.1 documented session flags 是 broken promise（codex-call 從未支援 session flag）、本版本顯式移除。

## Step 2: Collect prompt

依 Step 1 解析結果包裝 prompt 主體：

- Task brief 直接作為 prompt 第一段
- 每個 `--context <path>` 用 Read tool 拿內容、附入 prompt 作為 `### Context: <path>` block
- 若有 `--criteria`、附入 instructions 作為 success rubric（不在 prompt 主體、在 instructions）

Prompt 主體寫入暫存檔交 Step 4 傳 codex-call 的 `--prompt-file`。

## Step 3: Build instructions

System instructions（傳 codex-call 的 `--instructions` flag）內容：

```
You are a senior engineer rescuing a task. Read the task brief and any context files.
Produce output in three Markdown sections under H2 headings:

## Task Brief
Restate the task in your own words to confirm understanding.

## Outcome
The actual solution / analysis / implementation. Use code blocks where needed.
Set outcome enum based on result:
- "completed" — actionable solution given
- "partial" — partial solution, user follow-up needed
- "unclear" — task description too vague to commit answer
- "requires_external" — need user to provide additional information

## Suggested Next Steps
Listed follow-up actions. User decides whether to apply.

Completion criteria (if supplied): <success rubric>

Important: If task is unclear or you cannot commit an answer, DO NOT stub.
Instead output outcome=unclear with explicit reason. Honest "I don't know"
is better than a silent stub answer.
```

## Step 4: Invoke codex-call

### Step 4.1: Resolve profile (v0.2 profile-aware)

在呼叫 codex-call 之前、先 resolve profile。讀 `~/.codex-pro/profile.yaml`（global layer）+ `.codex-pro/profile.yaml`（project layer、優先於 global）、missing field fall back hardcoded default（`gpt-5.6-sol` / `xhigh` / `600`）。未設 profile 時採用現行 hardcoded default（自 model-default bump 起為 gpt-5.6-sol，issue #3 裁決）；已設 profile 的 override 行為與 v0.1.1 identical（100% backward compatible for profile users）。Inline `python3` regex YAML parse、不依賴 PyYAML：

```bash
PROFILE_RESOLVED=$(python3 - <<'PY'
import os, re
DEFAULTS = {"model": "gpt-5.6-sol", "effort": "xhigh", "max_time": 600, "focus_default": ""}
def parse(path):
    if not os.path.exists(path):
        return {}
    try:
        txt = open(path).read()
    except Exception:
        return {}
    out = {}
    for line in txt.splitlines():
        m = re.match(r'^(\w+):\s*(.*)$', line)
        if not m: continue
        k, v = m.group(1), m.group(2).strip()
        if (v.startswith('"') and v.endswith('"')) or (v.startswith("'") and v.endswith("'")):
            v = v[1:-1]
        out[k] = v
    return out
g = parse(os.path.expanduser("~/.codex-pro/profile.yaml"))
p = parse(".codex-pro/profile.yaml")
resolved, sources = {}, {}
for f, d in DEFAULTS.items():
    if f in p: v, s = p[f], "project"
    elif f in g: v, s = g[f], "global"
    else: v, s = d, "default"
    if f == "max_time":
        try: v = int(v)
        except (ValueError, TypeError): v, s = d, "default"
    resolved[f], sources[f] = v, s
# rescue uses model / effort / max_time (focus_default ignored)
RELEVANT = ["model", "effort", "max_time"]
rel = {sources[f] for f in RELEVANT}
if "project" in rel:
    ps = "mixed" if "global" in rel else "project"
elif "global" in rel:
    ps = "global"
else:
    ps = "default"
print(f'{resolved["model"]}|{resolved["effort"]}|{resolved["max_time"]}|{resolved.get("focus_default","")}|{ps}')
PY
)
IFS='|' read -r MODEL EFFORT MAX_TIME FOCUS_DEFAULT PROFILE_SOURCE <<< "$PROFILE_RESOLVED"
```

`$MODEL` / `$EFFORT` / `$MAX_TIME` 為 resolved value（profile 或 default）；`$PROFILE_SOURCE` 為 aggregate enum（`default` / `global` / `project` / `mixed`）供 Step 5 frontmatter。rescue 不使用 `$FOCUS_DEFAULT`（focus_default 僅 adversarial-review 用）。

### Step 4.2: codex-call invocation

呼叫 `codex-call` 寫結果到 `.codex-pro/rescue-<ISO8601-timestamp>.md`（首次跑 skill 需 `mkdir -p .codex-pro/`）：

```
codex-call \
  --output .codex-pro/rescue-<timestamp>.md \
  --model "$MODEL" \
  --effort "$EFFORT" \
  --max-time "$MAX_TIME" \
  --instructions "<Step 3 system instructions>" \
  --prompt-file <Step 2 prompt 暫存檔>
```

關鍵 flag：

- `--max-time "$MAX_TIME"`：hard timeout（profile `max_time` 或 default `600`、與 review 同）、超過即 fail-fast 為 `timeout`
- `--model "$MODEL"`：profile `model` 或 default `gpt-5.6-sol`
- `--effort "$EFFORT"`：profile `effort` 或 default `xhigh`（rescue 任務需深度推理）
- `--output <path>`：codex-call 直接寫 markdown 到該路徑（不 echo stdout）

**Skill 嚴禁 spawn `codex` CLI**。所有 rescue 必經 `codex-call` HTTPS direct（與 review 同 default rule）。rescue v0.1.1 起 stateless only — **不傳任何 session-continuity flag**（codex-call 無 session flag upstream support、見 frontmatter v0.1.1 known limitation）。若未來 future skill 想 spawn subprocess，須在 design.md 明列 explicit exception（如 batch skill）並於 SKILL body 明文標記。

## Step 5: Handle exit code

依 codex-call exit code 與 stdout/stderr 內容決定 result file 構造：

**Success（exit 0）**：

- codex-call 已將 rescue markdown 寫入 `--output` 指定路徑
- skill 額外於 result file 開頭 prepend YAML frontmatter：
  - `task_description`: user 提供的 task brief（截斷至 200 char）
  - `session_id`: codex-call HTTP response 若 surface 任何 session/conversation identifier 則記入；無則記 `null`。**本 field 不 promise continuation capability**（v0.1.1 known limitation：codex-call 尚無 session flag upstream support）
  - `model`: `$MODEL`（Step 4.1 resolved value、profile 或 default `gpt-5.6-sol`）
  - `effort`: `$EFFORT`（Step 4.1 resolved value、profile 或 default `xhigh`）
  - `timestamp`: ISO8601 含時區（例 `2026-06-01T10:30:48+08:00`）
  - `outcome`: 解析 body H2 outcome 段、抽出 enum 值（`completed` / `partial` / `unclear` / `requires_external`）
  - `profile_source`: `$PROFILE_SOURCE`（v0.2 新增 optional field、aggregate enum `default` / `global` / `project` / `mixed`）。**v0.1.1 result file 沒此 field 屬 valid frontmatter**（forward-compat、`/codex-pro:codex-status` 與 `/codex-pro:codex-result` 容忍 missing `profile_source`）
  - `error`: 不寫（success 不出現此 field）
- 回報 user：result file 路徑 + outcome 分類

**Failure（exit non-zero 或 outcome unclear）**：

依 stderr / output 或 outcome 判定 error class、寫 result file frontmatter `error` field、body 空或單行 error description：

| 來源 stderr/output / outcome | frontmatter `error` 值 | frontmatter `outcome` 值 | 回報訊息 |
|---|---|---|---|
| `rate limit` / `429` | `rate_limit` | （延用 codex output 或 unclear） | 「Codex 限額耗盡。等限額重置後重 invoke。**不會自動 retry**。」 |
| `auth` / `401` / `unauthorized` | `oauth_invalid` | unclear | 「OAuth token 失效。跑 /codex-pro:codex-setup 確認 ~/.codex/auth.json 狀態並重 login。」 |
| timeout / >600 秒 | `timeout` | unclear | 「Rescue 超過 10 分鐘 hard timeout。考慮縮小 task scope（用 --context 限縮範圍、加 --criteria 收斂）或拆細 task。」 |
| outcome `unclear`（Codex 自報） | `task_unclear` | unclear | 「Codex 無法 commit 答案 — task description 可能過模糊或需更多 context。建議補 `--criteria <成功標準>` 或拆 task 為更具體 sub-task。**不會 silent stub**。」 |

**所有 failure 仍寫 result file**（讓 user 有 trace、frontmatter `error` field 可觀察 fail mode 頻率）、**所有 failure 都不 retry**（fail-fast circuit-breaker 紀律、避免 #306 token-burn 與 #324 silent stub）。

## Result file structure（完整契約）

```
---
task_description: <user 提供 task brief 截至 200 char>
session_id: <codex-call response 若 surface 則記、否則 null>
model: <$MODEL resolved>          # profile 或 default gpt-5.6-sol
effort: <$EFFORT resolved>        # profile 或 default xhigh
timestamp: 2026-06-01T10:30:48+08:00
outcome: <completed | partial | unclear | requires_external>
profile_source: <default | global | project | mixed>  # v0.2 新增 optional; v0.1.1 file 無此 field 屬 valid
error: <rate_limit | oauth_invalid | timeout | task_unclear>  # 僅 fail-fast 時出現
---

# Codex Rescue — <task brief 截斷>

## Task Brief

<user 提供的完整 task description + --context 檔案清單摘要>

## Outcome

<Codex 的解法 / 分析 / 實作（可含 code block、解釋、reasoning trace）>

## Suggested Next Steps

- <follow-up action 1>
- <follow-up action 2>
- ...
```

Fail-fast case：保留 frontmatter + 空 body 或單行 `Rescue aborted: <error description>`。

## 與 review 的對比

| 面向 | `/codex-pro:codex-review` v0.1 | `/codex-pro:codex-rescue` v0.1 |
|---|---|---|
| Mental model | 對既有 code 跑診斷 | 把待解 task 交給 Codex |
| Argument 結構 | target 三選一（diff / file / --base） | task description + --context + --criteria |
| Result file H2 sections | `## Summary` / `## Findings` | `## Task Brief` / `## Outcome` / `## Suggested Next Steps` |
| Frontmatter outcome | findings_count (整數、無上限) | outcome enum (4 值) |
| Fail-fast 類別 | 3 類 (rate_limit / oauth_invalid / timeout) | **4 類**（rescue 加 `task_unclear`） |
| codex-call invocation | HTTPS direct、無 subprocess | HTTPS direct、無 subprocess（**同 default rule**） |

兩 skill 共享 Design constraint #1 default rule pattern — 與 batch 的 explicit exception 形成主軸對比。
