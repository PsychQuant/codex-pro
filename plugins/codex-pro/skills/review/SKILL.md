---
name: review
description: |
  對 code 跑 read-only Codex review — 接受三種 target：current uncommitted diff（無 argument）、specific file path、或 branch comparison（--base <ref>）。
  v0.2 — untracked-by-default：`--diff` mode 現在含 `git diff HEAD` + untracked file enumeration（v0.1 silent omission bug 已修），含 binary path-only + per-file 64KB / aggregate 512KB size cap + pre-first-commit fallback + target_invalid post-filter pre-flight。
  v0.3 — profile-aware：`--model` / `--effort` / `--max-time` 從 `~/.codex-pro/profile.yaml`（global）+ `.codex-pro/profile.yaml`（project）resolve；未設 profile 時沿用 hardcoded default（gpt-5.5 / xhigh / 600）、100% backward compatible。見 `/codex-pro:config`。
  v0.4 — heading-hardened：Step 3 system instructions 改為 literal-token 寫法（命名 `## Summary` / `## Findings` H2 + `### Finding N:` H3、"exactly two H2 sections, in this order" + CRITICAL 開頭條款），解 Codex 偶爾省略/改寫必要 H2 heading 的漂移（issue #1）；result-file 契約不變。
  透過 codex-call HTTPS direct 執行（無 subprocess），結果寫入 .codex-pro/review-<timestamp>.md 結構化檔案，不直接 inline echo（避免 silent stub failure）。
  Findings 無數量上限。Rate limit / OAuth invalid / timeout / target_invalid（v0.2 第 4 類）走 circuit-breaker fail-fast、不 retry。
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

**Fail-fast 四條件**（v0.2：原 3 class + target_invalid pre-flight、與 adversarial-review template 對齊）：下列四種 failure 觸發 circuit breaker、不 retry：

1. **Rate limit**（HTTP 429 或 output 含 "rate limit"）→ result file frontmatter 寫 `error: rate_limit`、提示等待 Codex tier 限額重置或升級
2. **OAuth invalid**（HTTP 401 或 output 含 "auth"）→ frontmatter 寫 `error: oauth_invalid`、提示跑 /codex-pro:setup 確認 token 狀態
3. **Hard timeout**（超過 --max-time 600 秒）→ frontmatter 寫 `error: timeout`、提示縮小 review target 或檢查 Codex tier
4. **Target invalid**（v0.2 pre-flight class）→ `--diff` mode 在 binary + size filter 後仍 whitespace-only → frontmatter 寫 `error: target_invalid`、`findings_count: 0`、在 codex-call 之前 abort（防空 prompt 燒 quota）

理由：retry 是 `openai/codex-plugin-cc` issue #306 的根因（無限 retry 吃光 Claude token cost）。Review 為 user-initiated、user-observable — fail 後由 user 自己決定 retry 而非 plugin 偷重 spawn。**「不 retry」紀律是 fail-fast circuit breaker 的核心**。

## Step 1: Parse argument

依以下 precedence 解析 review target：

- `--base <ref>`（flag）→ branch comparison：跑 `git diff <ref>...HEAD` 取 diff（v0.1 行為不變）
- 顯式 file path argument（例 `plugins/codex-pro/skills/setup/SKILL.md`）→ Read 該檔內容（v0.1 行為不變）
- 無 argument 或 `--diff`（預設）→ **v0.2 untracked-by-default**：跑 `git diff HEAD` 取 tracked changes + `git ls-files --others --exclude-standard` 列舉 untracked（respect `.gitignore`），再走 binary detect / size cap / pre-first-commit fallback / pre-flight 四道 filter

若 argument 同時含 path 與 `--base`，後者勝（branch 範圍涵蓋 single file）。**`--diff` mode 的 v0.1 行為（`git diff` 不含 untracked）已修為 v0.2 untracked-by-default**（無 opt-out flag、避免固化舊 bug 行為）；本 change 是 minor bump (v0.1 → v0.2)、行為 change 反映在 frontmatter description。

### Step 1.1: Binary file detection

對每個 untracked file 用 **雙 stage binary detect**：

- **Stage 1: `git check-attr binary <path>`** — 用 `.gitattributes` user-defined binary marker；若返回 `binary` 則 path-list 不注 content
- **Stage 2: NUL-byte sniff (first 8KB)** — 讀檔前 8KB（industry convention、grep/file(1) 同等技術）、若含 `\x00` (NUL byte) 則為 binary

Binary file 列在 prompt body 內 `### Untracked binaries omitted` heading 下、**只列 path、不注 content**（防 `.png in node_modules` 注入污染 prompt）。

### Step 1.2: Size cap

對非 binary、untracked 的 content-eligible file 套兩道 size cap：

- **Per-file cap 64KB**：超過 truncate、行尾加 marker `… [truncated at 64KB of N bytes]`（N 為原檔 size）
- **Aggregate cap 512KB**：合併所有 included content 後超過 cap、剩餘 file 列在 `### Untracked files omitted (aggregate size cap)` heading 下、**只列 path、不注 content**

理由：未 cap 會 silent 把 un-gitignored `node_modules` / `.swiftpm` cache（動輒 MB 級）灌進 Codex context、real review content 被 truncate 但 user 不知。64KB 是「正常 source file 上限」approximation（≈16k token），512KB 是「給 codex-call xhigh prompt 留 head-room」approximation。

### Step 1.3: Pre-first-commit (empty-repo) fallback

`git diff HEAD` 在 pre-first-commit repo（無任何 commit）會 exit 128 + stderr `unknown revision 'HEAD'` 或 `ambiguous argument 'HEAD'`。偵測雙條件：

```bash
diff_out=$(git diff HEAD 2>&1)
diff_rc=$?
if [ $diff_rc -eq 128 ] && echo "$diff_out" | grep -qE "unknown revision|ambiguous argument 'HEAD'"; then
    # Pre-first-commit: degrade fallback path
    cached_diff=$(git diff --cached 2>/dev/null)        # staged content
    workingtree_diff=$(git diff 2>/dev/null)            # working-tree vs index
    untracked=$(git ls-files --others --exclude-standard)
    target_marker="diff (pre-first-commit)"
fi
```

Frontmatter `target` field 值改為 `diff (pre-first-commit)`（明示 fallback codepath、result file 後可追溯）。

### Step 1.4: target_invalid pre-flight

合併 (a) `git diff HEAD`（或 fallback path）+ (b) 過 binary filter 與 size cap filter 後的 untracked content + (c) binary path-list section + (d) omitted path-list section、若整段 target body 為 whitespace-only → 觸發第 4 fail-fast class `target_invalid`、在 codex-call 之前 abort（防止把空 prompt 送進去燒 Codex quota、見 Step 5）。

實務情境：repo 只有 binary untracked file（純 image asset folder）、或所有 untracked 都 > 64KB binary、或合併後仍空 → 過 pre-flight 紀律守住。

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
- Produce output in exactly two H2 sections, in this order:
  ## Summary
  ## Findings
- CRITICAL: the output MUST begin with the literal line "## Summary"
  (one paragraph overall assessment), followed by the literal line "## Findings".
- Under "## Findings", each finding MUST use the literal H3 heading format
  "### Finding N: <severity> — <file>:<line>" where severity is one of
  critical / high / medium / low / info.
- Each finding's body MUST contain a concise message describing the issue,
  followed by a single line starting with "**Suggestion:**" with concrete remediation.
- No findings cap — report ALL material issues you observe.
- Output format is Markdown. Do NOT wrap in code fences.
```

## Step 4: Invoke codex-call

### Step 4.1: Resolve profile (v0.3 profile-aware)

在呼叫 codex-call 之前、先 resolve profile。讀 `~/.codex-pro/profile.yaml`（global layer）+ `.codex-pro/profile.yaml`（project layer、優先於 global）、missing field fall back hardcoded default（`gpt-5.5` / `xhigh` / `600`）。未設 profile 時行為與 v0.2 identical（100% backward compatible）。Inline `python3` regex YAML parse、不依賴 PyYAML：

```bash
PROFILE_RESOLVED=$(python3 - <<'PY'
import os, re
DEFAULTS = {"model": "gpt-5.5", "effort": "xhigh", "max_time": 600, "focus_default": ""}
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
# review uses model / effort / max_time (focus_default ignored)
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

`$MODEL` / `$EFFORT` / `$MAX_TIME` 為 resolved value（profile 或 default）；`$PROFILE_SOURCE` 為 aggregate enum（`default` / `global` / `project` / `mixed`）供 Step 5 frontmatter。review 不使用 `$FOCUS_DEFAULT`。

### Step 4.2: codex-call invocation

呼叫 `codex-call` 寫結果到 `.codex-pro/review-<ISO8601-timestamp>.md`（首次跑 skill 需 `mkdir -p .codex-pro/`）：

```
codex-call \
  --output .codex-pro/review-<timestamp>.md \
  --model "$MODEL" \
  --effort "$EFFORT" \
  --max-time "$MAX_TIME" \
  --instructions "<Step 3 system instructions>" \
  --prompt-file <Step 2 prompt 寫入的暫存檔>
```

關鍵 flag：

- `--max-time "$MAX_TIME"`：hard timeout（profile `max_time` 或 default `600`）、超過即 fail-fast 為 timeout
- `--model "$MODEL"`：profile `model` 或 default `gpt-5.5`
- `--effort "$EFFORT"`：profile `effort` 或 default `xhigh`（review 任務需深度推理）
- `--output <path>`：codex-call 直接寫 markdown 到該路徑（不 echo stdout）

**Skill 嚴禁 spawn `codex` CLI**。所有 review 必經 `codex-call` HTTPS direct。若未來 future skill 想 spawn subprocess，須在 design.md 明列 explicit exception（如 batch skill）並於 SKILL body 明文標記。

## Step 5: Handle exit code

依 codex-call exit code 與 stdout/stderr 內容決定 result file 構造：

**Success（exit 0）**：

- codex-call 已將 review markdown 寫入 `--output` 指定路徑
- skill 額外於 result file 開頭 prepend YAML frontmatter：
  - `target`: `diff` / `diff (pre-first-commit)` / `file:<path>` / `branch:<ref>`
  - `model`: `$MODEL`（Step 4.1 resolved value、profile 或 default `gpt-5.5`）
  - `effort`: `$EFFORT`（Step 4.1 resolved value、profile 或 default `xhigh`）
  - `timestamp`: ISO8601 含時區（例 `2026-06-01T08:30:48+08:00`）
  - `findings_count`: 解析 body 內 `### Finding N:` heading 數量
  - `profile_source`: `$PROFILE_SOURCE`（v0.3 新增 optional field、aggregate enum `default` / `global` / `project` / `mixed`）。**v0.2 result file 沒此 field 屬 valid frontmatter**（forward-compat、`/codex-pro:status` 與 `/codex-pro:result` 容忍 missing `profile_source`）
  - `error`: 不寫（success 不出現此 field）
- 回報 user：result file 路徑 + findings count

**Failure（exit non-zero 或 pre-flight target_invalid）**：

依 stderr / output / pre-flight 判定 error class、寫 result file frontmatter `error` field、`findings_count: 0`、body 空或單行 error description：

| 來源 stderr/output / pre-flight | frontmatter `error` 值 | 回報訊息 |
|---|---|---|
| `rate limit` / `429` | `rate_limit` | 「Codex 限額耗盡。等待限額重置或升級 tier 後重 retry。**不會自動 retry**。」 |
| `auth` / `401` / `unauthorized` | `oauth_invalid` | 「OAuth token 失效。跑 /codex-pro:setup 確認 ~/.codex/auth.json 狀態並重 login。」 |
| timeout / >600 秒 | `timeout` | 「Review 超過 10 分鐘 hard timeout。考慮縮小 review target（如 `--base` 指更近 ref、改 review 單檔），或檢查 Codex tier 處理速度。」 |
| pre-flight：`--diff` mode 過 binary + size filter 後 body 仍 whitespace-only（v0.2 第 4 類）| `target_invalid` | 「Target body 為空 after binary 與 size filter — verify there are real changes to review (uncommitted tracked changes, or untracked text files within 64KB each)。**不會自動 retry**、也不會發送空 prompt 給 Codex。」 |

**所有 failure 仍寫 result file**（讓 user 有 trace、可從 frontmatter `error` field 觀察 fail mode 頻率）、**所有 failure 都不 retry**（fail-fast circuit-breaker 紀律、避免 #306 token-burn）。**target_invalid 為 pre-flight class**（在 codex-call 之前 abort、保留 0 quota cost）、不像前 3 class 需 Codex round-trip 才知道。

## Result file structure（完整契約）

```
---
target: <diff | diff (pre-first-commit) | file:<path> | branch:<ref>>
model: <$MODEL resolved>          # profile 或 default gpt-5.5
effort: <$EFFORT resolved>        # profile 或 default xhigh
timestamp: 2026-06-01T08:30:48+08:00
findings_count: <N>
profile_source: <default | global | project | mixed>  # v0.3 新增 optional; v0.2 file 無此 field 屬 valid
error: <rate_limit | oauth_invalid | timeout | target_invalid>  # 僅 fail-fast 時出現
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
