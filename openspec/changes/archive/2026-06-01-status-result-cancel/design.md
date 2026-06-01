## Context

codex-pro v0.2.0 ship 三個 producer skill 後、`.codex-pro/` 目錄累積三類 heterogeneous frontmatter schema 的 result file：

- `review-*.md`：frontmatter `target` / `findings_count` / `model` / `effort` / `timestamp` / optional `error`、body `## Summary` + `## Findings`
- `rescue-*.md`：frontmatter `task_description` / `session_id` / `model` / `effort` / `timestamp` / `outcome` enum / optional `error`、body `## Task Brief` + `## Outcome` + `## Suggested Next Steps`
- `adversarial-review-*.md`：frontmatter `target` / `focus` / `depth` / `model` / `effort` / `timestamp` / optional `error`、body 4 fixed H2 sections each non-empty

User 目前只能手動 `ls .codex-pro/ | sort -r | head` + `cat`。本 change 三 skill 是這些 producer output 的 read-only consumer surface。

三個 skill 的 architectural 共性：
- 純 Bash + Read tool、無 codex-call、無 subprocess for Codex
- Read-only file ops（不 mutate disk、stdout only）
- Layer 2 可全 runtime 驗證（mktemp 假 .codex-pro/ + write fake result + invoke + verify）
- 與 setup（環境檢查）同屬 codex-pro read-only category

Cancel 的特殊性：不能真 cancel（v0.2 stateless）、不能 silent stub（會變 #324 重演）、不能 SIGTERM 騙 user（是 jobs-status refuted 同樣的 observability lie）。Option A 路線：實作為 **informational read-only no-op** — 顯式輸出限制 + 三條 remediation、exit 0、displayed limitation 而非 silent stub。

## Goals / Non-Goals

**Goals:**

- 三個 skill 各自獨立 SKILL.md + spec + tests Layer 2 script、與 v0.2 5 個 skill 同 architectural 規模
- Status 提供 frontmatter table summary（markdown table format、columns 對齊 heterogeneous frontmatter）+ `--skill <name>` filter
- Result 提供三種 selection mode：位置 `<filename>` / `--latest <skill>` / `--latest`（無 arg）
- Cancel 為 informational no-op、明確 explainer + 3 條 remediation、exit 0
- Heterogeneous frontmatter parse：三類 producer schema 並存於同一 `.codex-pro/`、status / result 透明處理差異
- Behavioral runtime test pattern：tests/status.sh + tests/result.sh 用 mktemp 假 `.codex-pro/` 跑真 skill 邏輯、不靠 SKILL.md prose grep
- Missing / empty `.codex-pro/` 為 informational case 而非 error（status 友善印、cancel no-op、result 引導跑 status）
- 解 [[feedback-codex-pro-smoke-before-archive]] memory 的 Layer 2 string-level blind spot — 本 change 的 read-only 三 skill 可全 Layer 2 runtime 驗、無 Layer 3 smoke gap

**Non-Goals:**

- 不實作 real cancel（無 PID 可殺、無 upstream cancel API）
- 不引入 background job mode 給 codex-call
- 不修改任一 v0.2 producer skill spec / SKILL.md
- 不改變 result file 寫入格式
- 不支援 date range / outcome enum / target prefix 過濾
- 不實作 token / cost / tier observability
- 不解析 body 內容做 statistics
- 不 cache / index result files
- 不支援 multi-project `.codex-pro/`
- 不對 producer file 做 schema validation / migration
- 不發 background notification
- 不破 codex-plugin-cc drop-in 命令名（命名固定為 status / result / cancel、與上游一致）
- 不引入新 runtime dependency
- 不 Windows 支援

## Decisions

### D1: 三個獨立 skill vs 單一 skill 子命令

採 **三個獨立 SKILL.md**（與 v0.2 6 skill 一致 architecture）、不採「單一 `/codex-pro:jobs` skill + status / result / cancel subcommand」。

理由：

- 命名 drop-in 表面與 codex-plugin-cc 對齊（`/codex:status` / `:result` / `:cancel` 三個獨立命令、本身就是三個 namespace）、user 轉場零成本
- 與 v0.2 「每 capability 一個 skill」convention 一致、新 skill 加入無 special-case
- 三 skill mental model 差異足夠大（status = 列表 / result = 顯示單一 / cancel = informational）、合併為單 skill 子命令會增加 learning surface
- 測試 layering 模型自然 fit：每 skill 一個 Layer 2 script、與 review / rescue / adversarial-review 同模板

Alternatives:

- 單一 `/codex-pro:jobs` skill + `--mode status|result|cancel`：違反 codex-plugin-cc drop-in 命名表面、user 還是要學 `--mode` 語法、且 cancel 與 status/result 邏輯太異質
- 將 status + result 合成 `/codex-pro:results` 一個 skill（list + detail 同 namespace）：失去 drop-in 對標、且 cancel 變孤兒命名
- 將 cancel 完全 drop（v0.2 不提供）：違反 drop-in 完整性 goal、user 看到 `/codex:cancel` 對應 codex-pro 空白會疑惑為什麼

### D2: Heterogeneous frontmatter parse 策略

採 **lazy-tolerant inline python3 YAML parse + 缺漏 field 顯示 `—`**、不採嚴格 schema validation。

理由：

- 三類 producer schema field 集合不一致（review 有 `findings_count`、rescue 有 `outcome` enum、adversarial-review 有 `focus` + `depth`）、強行統一不 natural
- Status table 用 union 欄位（filename / skill type / target / outcome summary / timestamp / error）、缺漏顯示 `—` 或空字串、user 一眼看出哪 skill 產出哪欄位
- `skill type` 從 filename prefix 推斷（review-*.md → review、rescue-*.md → rescue、adversarial-review-*.md → adversarial-review）、不依賴 frontmatter `kind` field（producer 也沒寫此 field）
- `outcome summary` 欄位語意 by-skill：review = `findings_count` integer、rescue = `outcome` enum 值、adversarial-review = 4 section non-empty count（如 `4/4 sections`）
- 嚴格 schema validation 會：(a) 阻塞 producer schema 演進（如 rescue v0.1.1 移除 `resume_from`、consumer 不應壞掉）、(b) 對 user 不友善（看不懂為何結果檔被拒）

Alternatives:

- 嚴格 JSON Schema 驗證每類 frontmatter：增加 spec coupling、producer 升版要同步改 consumer schema
- 統一 producer-side 加 `kind: review|rescue|adversarial-review` field：違反 Non-Goals 「不修 producer」
- 純檔名 sort + cat：失去 frontmatter summary 價值、user 還是要自己看

### D3: `--latest` selection logic — frontmatter timestamp vs filesystem mtime

採 **filename ISO8601 timestamp prefix lexical sort**（filename 即是時序 source of truth）、不採 frontmatter `timestamp` field 或 filesystem `mtime`。

理由：

- 三類 producer skill 寫檔時 filename pattern 統一為 `<skill>-<ISO8601-with-Z-or-offset>.md`、lexical sort = 時序 sort、O(N) scan + 字串比較、無 YAML parse 成本
- Filesystem `mtime` 易受 `git mv` / `touch` / backup tool 污染、不可信
- Frontmatter `timestamp` field 三類 producer 都有但需 YAML parse、且 user copy 檔案到別資料夾後 frontmatter 仍 stick、可能與 filename mismatch
- Filename 是 producer 寫檔時 atomic 決定、最接近 ground truth

`--latest <skill>`：filter prefix 後再 lexical max。
`--latest` 無 arg：全 prefix lexical max。
Tied timestamps（極端 case 同秒多檔）：filename 完整字串 lexical max（次序 deterministic 即可、不需 stable sort）。

Alternatives:

- Frontmatter timestamp：需 YAML parse、慢、且 user 改檔可能 mismatch
- Filesystem mtime：不可信、被 backup / sync tool 污染
- 同時驗證 filename + frontmatter timestamp 一致：增加複雜度且 v0.1 不需要

### D4: Cancel 為 informational read-only no-op 的契約

`/codex-pro:cancel` 輸出格式：

```
codex-pro cancel — informational only

codex-pro v0.2 is single-shot stateless: each /codex-pro:review / :rescue /
:adversarial-review invocation is a synchronous HTTPS round-trip to codex-call,
with no background job, no persistent PID, and no upstream cancel API on
chatgpt.com/backend-api. There is nothing for /codex-pro:cancel to terminate.

If you need to abort a running invocation, choose one:

  1. Press Ctrl-C in the Claude Code session — Claude aborts the bash call
     that runs codex-call.
  2. Wait for the --max-time 600 hard timeout (10 minutes). The invocation
     will fail-fast with frontmatter `error: timeout`.
  3. Future codex-pro v0.3+ may add a background job mode; if so, this skill
     will be re-implemented to actually cancel a job. Until then, this is a
     displayed limitation.

This message is not an error. exit 0.
```

Exit 0、無 stderr、無 disk mutation、無 PID kill、無 HTTPS。

理由：

- 顯式列出三條 remediation = user 自助力強、與 silent stub（#324）對比明確
- Exit 0 因為「displayed limitation」非「failure」、避免 user shell script `set -e` 因 cancel 跳 trap
- 不接受任何 argument（無 PID input、無 job ID input）— 任何 arg 印 usage 提示 + exit 0
- Cancel 為 codex-pro test 套件第一個 0-codex-call skill（純 stdout）、Layer 2 全 runtime 驗為 trivial（assert exit 0 + stdout 含 explainer keywords）

Alternatives:

- Cancel 完全 drop：違反 drop-in 完整性 goal
- Cancel 是 silent no-op（無 output、exit 0）：使用者敲 `/codex-pro:cancel` 看不到回應、會以為 hung
- Cancel 寫 result file `.codex-pro/cancel-<ts>.md`：違反 「不 mutate disk」原則、且檔內無 codex output 是 noise
- Cancel exit 非 0（如 exit 1 表示 "no-op"）：違反 Unix convention（exit 1 是 error）

### D5: Behavioral runtime test pattern（mktemp + fake .codex-pro/）

tests/status.sh / tests/result.sh 用以下 pattern 跑 runtime 驗證：

1. `mktemp -d` 建 temp dir
2. 在 temp dir 內 `mkdir .codex-pro/`
3. Write 3-5 fake result files、frontmatter 涵蓋三類 producer schema
4. `cd "$TMPDIR" && <invoke skill logic>`、capture stdout + exit code
5. assert stdout 含特定 column header / row / count
6. trap EXIT 自動 `rm -rf "$TMPDIR"`

對應 SKILL.md 內可 invoke 的 logic：SKILL.md 用 inline Bash heredoc 寫實際 parse / display 邏輯、tests/*.sh 直接 source 或 invoke。

理由：

- 解 [[feedback-codex-pro-smoke-before-archive]] memory 的 Layer 2 string-level blind spot
- read-only file ops 不耗 Codex quota、可以全 runtime 驗
- 與 setup.sh 的 fake `HOME` + 剝離 PATH 思路一致（環境 isolation）、本 change 把 isolation 從 env 推到 cwd
- Future producer skill 改 frontmatter field（如 review v0.2 加新欄位）、status/result spec scenarios 用 fake fixture 立即抓出 regression

Alternatives:

- 純 SKILL.md prose grep（rescue.sh 模式）：本 change 的價值之一是升級 test pattern、退回 grep 浪費機會
- Real `.codex-pro/` 跑 producer skill 後驗：耗 Codex quota（違反 fast-cheap Layer 2 紀律）
- Mock 整個 file system：過 heavy、mktemp 是標準 POSIX、零依賴

### D6: Read-only category 引入

CLAUDE.md / README.md 新增「Read-only consumer skills」分類軸、明示三 skill 與 setup 同類：

| Category | Skills | 屬性 |
|---|---|---|
| Read-only environment | setup | 環境檢查、無 disk mutation、無 codex 互動 |
| **Read-only consumer**（本 change 新增）| status / result / cancel | 讀 `.codex-pro/` producer output、無 disk mutation、無 codex 互動 |
| Mutating producer | review / rescue / adversarial-review | 寫 `.codex-pro/<skill>-<ts>.md`、走 codex-call HTTPS direct、Design constraint #1 default rule |
| Mutating exception | batch | `codex exec --full-auto` 平行批次、Design constraint #1 explicit exception |

理由：

- v0.3 之後 read-only 與 mutating 比例會繼續分化、category 軸先 establish
- 「No codex 互動」明示三 skill 與 setup 同類、為 future skill design 提供 affordance reference
- 與既有 review/rescue/adversarial-review 對比 mutating producer category、強化 mental model 清晰度

### D7: 缺漏 / 空 `.codex-pro/` 處理策略 by skill

| Skill | `.codex-pro/` missing | `.codex-pro/` empty |
|---|---|---|
| status | 印「`.codex-pro/` not yet created — any producer skill creates it on first run」+ exit 0 | 印「No result files found」+ exit 0 |
| result | 印 error「`.codex-pro/` not yet created — run `/codex-pro:review` / `:rescue` / `:adversarial-review` first」+ exit 非 0 | 印 error「No result files in `.codex-pro/`」+ exit 非 0 |
| cancel | 不檢查（cancel 無 file dependency）— 直接印 explainer + exit 0 | 同上 |

理由：

- Status 為 list 性質、無 file 為「就是無紀錄」非 error
- Result 為 detail 性質、無 file 為「找不到指定 target」屬 error、且要 remediation 提示 user 跑 producer
- Cancel 與 `.codex-pro/` 解耦、不檢查保持 informational 純度

Alternatives:

- 三 skill 都 exit 0：result 在 file 不存在 case 違反 Unix convention（user shell script 預期 exit 非 0 觸發 fallback）
- 三 skill 都檢查 `.codex-pro/` 並 exit 非 0：cancel 失去 informational 屬性、變 error skill

### D8: Status table format — markdown table

採 **markdown table**（pipe-separated、column-aligned），不採 JSON / plain text / CSV。

理由：

- Claude Code REPL 內 user 一眼看（markdown render）
- 列數少（v0.1 預期 < 50 row）、不需 pagination
- 可直接 copy 進其他 markdown 文檔（dogfooding 紀錄）
- 與 codex-pro 既有 SKILL.md / spec / proposal 文檔風格一致

Alternatives:

- JSON：scriptable 但 user 在 REPL 看不直觀、需要 jq 二次 parse
- Plain text columns：較簡潔但對齊靠 padding hack、heterogeneous data 看不出 schema 差異
- CSV：不對 REPL friendly

## Implementation Contract

#### Behavior

User 在 Claude Code 中跑三 skill 任一：

- `/codex-pro:status [--skill <review|rescue|adversarial-review>]` → 掃 `.codex-pro/*.md`、parse frontmatter、輸出 markdown table
- `/codex-pro:result <filename> | --latest [<skill>] | --latest` → 顯示特定 result file frontmatter + body
- `/codex-pro:cancel` → 印 informational explainer + 3 remediation、exit 0

#### Interface

三 skill identifier:

- `status` / 觸發名 `/codex-pro:status` / 入口 `plugins/codex-pro/skills/status/SKILL.md`
- `result` / 觸發名 `/codex-pro:result` / 入口 `plugins/codex-pro/skills/result/SKILL.md`
- `cancel` / 觸發名 `/codex-pro:cancel` / 入口 `plugins/codex-pro/skills/cancel/SKILL.md`

Arguments:

- status: `[--skill <name>]`（optional）
- result: `[<filename>] | [--latest [<skill>]]`（mutex）
- cancel: 不接受 argument（含 flag 印 usage + exit 0）

副作用：三 skill 全 read-only、無 file mutation、stdout only。

#### Heterogeneous frontmatter table columns

Status output 採以下 markdown table columns（heterogeneous union）：

| filename | skill type | target / task | outcome summary | timestamp | error |

- `skill type`: 從 filename prefix 推斷
- `target / task`：review / adversarial-review 用 frontmatter `target`、rescue 用 `task_description`（截斷至 50 char）
- `outcome summary`：review = `findings_count` int、rescue = `outcome` enum 值、adversarial-review = `4/4 sections` 字串
- `timestamp`：filename ISO8601 部分（截短至 date + HH:MM 顯示）
- `error`：frontmatter `error` field 若有（rate_limit / oauth_invalid / timeout / task_unclear / target_invalid 之一）

#### Failure modes

- status：`.codex-pro/` missing → friendly print + exit 0；malformed YAML in single file → 該 row 顯示「（unparseable frontmatter）」、繼續其他 row、exit 0
- result：`<filename>` 不存在 → error + remediation + exit 非 0；`--latest <skill>` 無對應 skill file → error + remediation + exit 非 0；`<filename>` 與 `--latest` 同時提供 → usage + exit 非 0
- cancel：任何 argument → usage + exit 0（informational）

#### Acceptance criteria

- 三 skill 在 Claude Code 內可 by skill 觸發
- 三 SKILL.md 不含 `codex exec` 字串、不含 `codex-call` 字串（純 file ops、無 codex 互動、嚴守 read-only）
- tests/status.sh + tests/result.sh + tests/cancel.sh 各自 Layer 2 全綠
- aggregate `bash tests/run.sh` 從 149 上升至 ~200（±5）、9 layers all green、exit 0
- CLAUDE.md + README.md namespace consistency 涵蓋三新 skill
- 三 skill 各自 frontmatter loop 在 tests/static.sh 自動 cover

#### Scope boundaries

In scope:

- 三 SKILL.md + 三 spec + 三 tests/*.sh Layer 2 script
- tests/run.sh dispatcher 加三 layer
- CLAUDE.md / README.md 更新（Commands surface + Marketplace structure + 新 Read-only category 段）
- behavioral runtime test pattern（mktemp + fake .codex-pro/ fixture）

Out of scope:

- 修改 v0.2 5 producer skill（任一）
- codex-call wrapper 修改
- background job mode / real cancel
- token / cost / tier observability
- result file 寫入 schema 改變
- Windows 支援
- multi-project `.codex-pro/`
- date range / outcome enum filter

## Risks / Trade-offs

- [Cancel 為 displayed limitation 仍可能讓 user 失望] → user 期待真 cancel 但拿到 explainer。Mitigation: SKILL.md description trigger keyword 明示「informational only」、CLAUDE.md / README.md Commands surface 表 cancel 行備註「displayed limitation — v0.2 stateless」、user 一眼知道為什麼；3 條 remediation 提供 actionable next step、不留 user 卡死。
- [Heterogeneous frontmatter 在 future producer schema 演進時 status 可能漏新 field] → 如 review v0.2 加 `severity_breakdown` field、status table column 不會顯示。Mitigation: v0.1 minimal 只列 union 必要欄位、future producer 升版時於 status spec 加 new column；缺漏 field 顯示 `—` 不破 status 跑、user 用 result 看完整 detail；test fixture 涵蓋三 schema、producer 加新 field 時 test 不會誤 fail。
- [Filename ISO8601 sort 假設 producer 永遠寫 ISO8601 prefix] → 若 future producer 改 filename pattern（如改 epoch milliseconds prefix），`--latest` 邏輯壞掉。Mitigation: 三 v0.2 producer SKILL.md 都明寫 `<skill>-<ISO8601-timestamp>.md` pattern、本 change spec 把該 pattern 列為 contract assumption；future producer 改 pattern 必走 spec change cycle、本 change 不獨力承擔 pattern stability。
- [Behavioral runtime test pattern 增加 Layer 2 maintenance cost] → mktemp fixture + invoke + stdout assertion 比純 grep 重。Mitigation: 三 read-only skill 為「最適合 runtime test」case（無 Codex quota / 無 external call / 無 disk persistence outside mktemp）；producer skill 仍維持 grep + smoke-before-archive pattern；test pattern 投資為 read-only category 限定、不傳染 producer category。
- [Triple skill 在 Marketplace 看起來像「灌水」三 skill 但都 trivial] → cancel 尤其 trivial（純 print）。Mitigation: 三 skill mental model 差異足夠（list / detail / informational）、user 確實需要三 namespace；單一 jobs skill + subcommand 反而增加 learning surface（D1 already discussed）；codex-plugin-cc drop-in 表面要求三 row、為 user 轉場降低成本。
- [Read-only category 引入可能讓 future skill 分類爭議多] → 如 v0.3 加 `/codex-pro:doctor` 既檢查環境（read-only）也修配置（mutating），歸哪類？Mitigation: 採「主屬性歸類」原則、配 secondary tag；v0.3 真出爭議時走 design 一輪、本 change v0.1 兩類已足夠。
