---
name: codex-visual-xval
description: |
  兩個模型對同一批圖片各自判讀、用程式比對、只用第三種證據裁決分歧（visual cross-validation）。
  Claude 先依封閉物體清單逐格作答並封存（SHA-256＋時間），Codex 再透過 codex-call --image 盲答；
  比對分成數量、位置、關係三類分歧，分歧只用放大輪、SAM 2.1 追蹤量測、物理約束裁決，不用多數決。
  結果寫入 .codex-pro/visual-xval-<timestamp>.md 結構化檔案。
  需要支援 --image 的 codex-call（parallel-ai-agents 2.24.0 以上）；SAM 2.1 為內建步驟，首次使用前徵得同意才安裝（約 1 GB）。
  Fail-fast：rate_limit / oauth_invalid / timeout / target_invalid / runtime_unsupported / parse_failed，**不 retry**。
  Use when: 使用者輸入 /codex-pro:codex-visual-xval、要從圖片或影格下判斷而且要求準確（例如替訓練影片評分前核對判讀）、
  要兩個 AI 用視覺互相核對、懷疑自己看錯圖。
  Trigger keywords: codex visual cross-validation, visual xval, 視覺交叉驗證, 兩個 AI 看圖核對, check my image reading with codex
allowed-tools:
  - Bash
  - Read
  - Write
  - AskUserQuestion
---

# /codex-pro:codex-visual-xval — 視覺交叉驗證

單一模型從圖片下判斷會看錯而不自知。本 skill 讓 Claude 與 Codex 對同一批圖片**各自獨立**作答，
用確定性程式找出分歧，再用**第三種證據**裁決。兩個模型一致不代表正確；本 skill 找的是分歧，
不是證明判讀準確。

## 行為原則

- **Design constraint #1**：所有對 Codex 的請求只經 `codex-call`（HTTPS direct），不 spawn `codex` CLI。
  本 skill 的請求全部由 `scripts/xval.py ask` 發出，它從 run 目錄的 `runtime.txt` 讀 runtime 路徑。
- **Design constraint #2**：`codex-call` 以 profile 的 `--max-time` 為 hard timeout，前景同步執行。
- **Design constraint #3／#4**：fail-fast、不 retry，每次 run 都寫結構化結果檔。
- **盲答**：給 Codex 的請求只含圖片（中性檔名 `f01.png`…）、詞彙表與 schema，不含 Claude 的任何答案。
  看得到 Codex 答案的步驟只印出計數與編號，不印答案值。
- **不用多數決、不讓一方遷就另一方**：分歧只有三種結局 `resolved_claude`、`resolved_codex`、`unverifiable`。

**Fail-fast 類別**（全部寫結果檔、全部不 retry）：

1. `rate_limit`、`oauth_invalid`、`timeout`：由 `codex-call` 的錯誤訊息判定
2. `target_invalid`：沒有圖片、圖片讀不到、詞彙表的關係詞沒有量化門檻、Claude 的答案不合 schema
3. `runtime_unsupported`：`codex-call --help` 沒有列出 `--image`（舊版會把不認得的旗標當成 prompt 吞掉）
4. `parse_failed`：Codex 的回覆不是符合 schema 的 JSON

## Step 1: Parse arguments

```
/codex-pro:codex-visual-xval <image>... --vocab <vocab.json> [--claude-answers <claims.json>] [--sequence]
```

- `<image>...`：要判讀的圖片（PNG／JPEG／WebP／GIF，單張 20 MB 以內）。依給定順序編為 `f01`、`f02`…
- `--vocab`：詞彙表，格式見 `references/vocab-format.md`。關係詞必須有量化定義（例如 `distance_pct < 5`）。
- `--claude-answers`：已經寫好的 Claude 答案。沒給就由執行本 skill 的 Claude 在 Step 3 作答。
- `--sequence`：圖片是**同一支影片依時間排序的影格**。只有這時才跑 SAM 追蹤。

以本 skill 的目錄設定 `SKILL_DIR`（Claude Code 會在載入時顯示 base directory；不得從目前工作目錄猜），
並建立 run 目錄：

```bash
SKILL_DIR="<本 skill 的 base directory>"
RUN=".codex-pro/visual-xval-run-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$RUN"
```

## Step 2: 送出前的隱私提醒

第一個請求送出之前，告訴使用者：**這些圖片會送到 OpenAI**。畫面上若有不該離開本機的內容（姓名標籤、
評分表、人臉），要先遮蓋。本 skill 不替使用者判斷哪些內容該遮。使用者表示要先遮蓋時，停在這裡。

## Step 3: 建立 run、Claude 作答、封存

```bash
python3 "$SKILL_DIR/scripts/xval.py" init --run "$RUN" --vocab <vocab.json> [--sequence] <image>...
```

Claude 依序用 Read 看 `$RUN/frames/f01.png`…，依詞彙表與 `references/claim-schema.md` 逐格作答，
寫成 `$RUN/claude.json`（有 `--claude-answers` 就複製該檔）。**作答時不得看任何 Codex 的輸出。**
寫完立刻封存，之後不得再改：

```bash
python3 "$SKILL_DIR/scripts/xval.py" seal --run "$RUN"
```

## Step 4: Invoke codex-call

### Step 4.1: Resolve profile

讀 `~/.codex-pro/profile.yaml`（global）與 `.codex-pro/profile.yaml`（project，優先），缺的欄位用
hardcoded default（`gpt-5.6-sol` / `xhigh` / `600`，鏡像 [`references/defaults.json`](../../references/defaults.json)）：

```bash
PROFILE_RESOLVED=$(python3 - <<'PY'
import os, re
DEFAULTS = {"model": "gpt-5.6-sol", "effort": "xhigh", "max_time": 600}
def parse(path):
    if not os.path.exists(path):
        return {}
    out = {}
    for line in open(path).read().splitlines():
        m = re.match(r'^(\w+):\s*(.*)$', line)
        if m:
            v = m.group(2).strip()
            out[m.group(1)] = v[1:-1] if len(v) > 1 and v[0] == v[-1] and v[0] in "\"'" else v
    return out
g = parse(os.path.expanduser("~/.codex-pro/profile.yaml"))
p = parse(".codex-pro/profile.yaml")
resolved, sources = {}, set()
for f, d in DEFAULTS.items():
    v, s = (p[f], "project") if f in p else ((g[f], "global") if f in g else (d, "default"))
    if f == "max_time":
        try: v = int(v)
        except (ValueError, TypeError): v, s = d, "default"
    resolved[f] = v; sources.add(s)
ps = "mixed" if {"project", "global"} <= sources else ("project" if "project" in sources else ("global" if "global" in sources else "default"))
print(f'{resolved["model"]}|{resolved["effort"]}|{resolved["max_time"]}|{ps}')
PY
)
IFS='|' read -r MODEL EFFORT MAX_TIME PROFILE_SOURCE <<< "$PROFILE_RESOLVED"
```

### Step 4.2: codex-call invocation

解析 runtime 並寫進 run 目錄，然後送出第一輪（全部圖片，用 `--image` 逐張帶入）：

```bash
printf '%s\n' "${CODEX_RUNTIME_ERROR:-}" "${CODEX_RUNTIME_DETAIL:-}" > "$RUN/runtime_error.txt"
CODEX_CALL="$(command -v codex-call)"
printf '%s\n' "$CODEX_CALL" > "$RUN/runtime.txt"
```

```bash
python3 "$SKILL_DIR/scripts/xval.py" ask --run "$RUN" --round 1 \
  --model "$MODEL" --effort "$EFFORT" --max-time "$MAX_TIME"
```

`xval.py ask` 依序：讀 `runtime_error.txt`（有錯就停）、確認 runtime 存在、確認 `codex-call --help`
列出 `--image`（沒有就 `runtime_unsupported`，**不送任何請求**）、送出請求、驗證回覆。它只印出狀態，
Codex 的答案寫在 `$RUN/codex.json`。

**codex-call MUST 前景同步執行（foreground, synchronous）**：嚴禁 `run_in_background`、`&`、nohup。
結果檔寫完之前本 task 未完成。

## Step 5: Handle exit code

`xval.py` 任何一步以 exit 5 結束，代表 run 停止；stdout 與 `$RUN/error.json` 都有 `error` 與 `detail`。
照下表回報，然後直接跳到 Step 9 寫結果檔：

| `error` 值 | 回報訊息 |
|---|---|
| `rate_limit` | 「Codex 限額耗盡。等待重置後再跑。**不會自動 retry**。」 |
| `oauth_invalid` | 「OAuth token 失效。跑 /codex-pro:codex-setup。」 |
| `timeout` | 「超過 hard timeout。減少圖片張數，或檢查 Codex tier。」 |
| `target_invalid` | 「輸入不合格：<detail>。沒有送出請求。」 |
| `runtime_unsupported` | 「codex-call 不支援 --image。更新 parallel-ai-agents 到 2.24.0 以上。沒有送出請求。」 |
| `parse_failed` | 「Codex 的回覆不是符合 schema 的 JSON。**不會自動 retry**。」 |

**所有 failure 仍寫 result file**，**所有 failure 都不 retry**。

## Step 6: 比對

```bash
python3 "$SKILL_DIR/scripts/xval.py" compare --run "$RUN"
```

先重算封存的 SHA-256（被改過就標 `seal_broken`，但照樣比對），再逐格比對。只印出一致率與分歧的
編號、影格、類型。**此時不要讀 `$RUN/codex.json` 與 `$RUN/comparison.json` 的內容**，放大輪要用。

沒有分歧就跳到 Step 9。

## Step 7: 放大輪

```bash
python3 "$SKILL_DIR/scripts/xval.py" crops --run "$RUN"
```

每個分歧裁出一張放大 2 倍的圖（`$RUN/crops/z01.png`…）並附一個問題。Claude 用 Read 看每張裁切圖，
**只依裁切圖**回答，不參考自己先前的答案，寫成 `$RUN/zoom_claude.json`（`{"d1": <答案>, …}`；位置題
是裁切圖內的百分比 `{"x_pct", "y_pct"}`），然後封存並送給 Codex：

```bash
python3 "$SKILL_DIR/scripts/xval.py" seal --run "$RUN" --zoom
python3 "$SKILL_DIR/scripts/xval.py" ask --run "$RUN" --round zoom \
  --model "$MODEL" --effort "$EFFORT" --max-time "$MAX_TIME"
```

放大輪的請求只帶裁切圖與問題，不帶任何一方先前的答案。

## Step 8: SAM 證據

```bash
python3 "$SKILL_DIR/scripts/xval.py" sam --run "$RUN"
```

- `not_applicable`：圖片不是同一支影片的連續影格（沒有 `--sequence`）。跳過。
- `not_installed`：先跑 `bash "$SKILL_DIR/scripts/sam_env.sh" install`，把它印出的下載量（約 1 GB）告訴使用者，
  **用 AskUserQuestion 取得同意**後才跑 `install --yes`，再重跑本步。使用者拒絕就照樣往下走，需要 SAM
  的分歧會是 `unverifiable`。
- `ok`：兩邊一致的影格當錨點，每段一致影格各自錨定；兩物件遮罩 IoU > 0.5 的格不當證據。

## Step 9: 裁決與結果檔

```bash
python3 "$SKILL_DIR/scripts/xval.py" adjudicate --run "$RUN"
python3 "$SKILL_DIR/scripts/xval.py" result --run "$RUN" \
  --model "$MODEL" --effort "$EFFORT" --profile-source "$PROFILE_SOURCE"
```

run 停在 Step 5 時也要跑 `result`（它讀 `$RUN/error.json`）。回報使用者結果檔路徑、一致率與各裁決的數量。

## Result file structure（完整契約）

```
---
skill: visual-xval
target: <N images | N images (sequence)>
model: <$MODEL resolved>
effort: <$EFFORT resolved>
profile_source: <default | global | project | mixed>
timestamp: 2026-10-07T08:30:48+08:00
n_images: <N>
n_claims: <frames Claude answered>
agreement_rate: <0–1>
claude_answers_sha256: <hex>
sealed_at: <ISO8601 with offset>
seal_broken: <true | false>
sam_status: <ok | not_installed | not_applicable | no_anchor | failed | not_run>
error: <rate_limit | oauth_invalid | timeout | target_invalid | runtime_unsupported | parse_failed>  # 僅失敗時出現
---

# Visual cross-validation — <target>

## Agreement
## Disagreements
## SAM evidence
## Seal
## Limitations
```

各段依序：一致率與分歧摘要、逐筆分歧的類型與裁決及證據、SAM 狀態（錨點、塌陷格數）、封存驗證、限制
（必須寫明兩個模型一致不代表正確）。
