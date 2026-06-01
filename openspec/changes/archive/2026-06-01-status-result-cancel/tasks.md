# Tasks — status-result-cancel

實作 `/codex-pro:status` / `/codex-pro:result` / `/codex-pro:cancel` v0.1 三件套：read-only consumer skills 對應 v0.2 三 producer skill 的 `.codex-pro/*.md` output。Cancel 為 informational no-op（option A 路線）。引入 behavioral runtime test pattern（mktemp fake `.codex-pro/`）解 Layer 2 string-level blind spot。

## 1. status SKILL.md（new）

- [x] 1.1 建立 `plugins/codex-pro/skills/status/SKILL.md` 並寫入 YAML frontmatter（`name: status`、`allowed-tools: [Bash, Read]`、description block 含 trigger keywords `list result files` / `review history` / `過去結果` / `狀態` / `observability` — 為 read-only consumer category 表達 mental model）。驗證 **Status skill registration and argument parsing** 的 "Skill is registered and discoverable" scenario — frontmatter `name` 等於 `status`、`allowed-tools` 含 `Bash` + `Read`。Acceptance: tests/static.sh per-skill frontmatter loop pass + `grep "list result files\|review history\|過去結果\|observability" SKILL.md` 命中。
- [x] 1.2 寫入「行為原則」段：明示「**read-only consumer category** — 無 codex-call、無 codex exec、無 file mutation、無 subprocess for Codex；與 setup 同類、與 review / rescue / adversarial-review producer 對比」+ argument 解析（`--skill <review|rescue|adversarial-review>` 三值合法、其他值 reject + exit 非 0）+ 明示嚴守 read-only 紀律。對應 **Status invocation is read-only with no Codex interaction** 兩 scenarios（無 `codex-call` / 無 `codex exec` / 無 file mutation）+ D6: Read-only category 引入。Acceptance: SKILL body grep `codex-call` 等於 0、grep `codex exec` 等於 0、grep `read-only` ≥ 1。
- [x] 1.3 寫入 Step 1 (Scan `.codex-pro/*.md`)：用 Bash `find .codex-pro -name '*.md'` 或 `ls .codex-pro/*.md`（取決於 zsh / bash 兼容性）、若目錄不存在則 trap not-found；若 `--skill <name>` 給定 filter prefix；產出 sorted-by-filename file list。對應 D2: Heterogeneous frontmatter parse 策略 + D7: 缺漏 / 空 `.codex-pro/` 處理策略 by skill。Acceptance: SKILL body grep `.codex-pro` ≥ 1、grep `find\|ls` ≥ 1。
- [x] 1.4 寫入 Step 2 (Parse frontmatter per file)：用 inline python3 / awk 拆 YAML frontmatter 區段（`---` 包圍）、抽 `target` / `task_description` / `findings_count` / `outcome` / `focus` / `error` / `model` / `effort` field、容忍缺漏（缺者 render `—`）、容忍 malformed YAML（該 row `outcome summary` 顯示 `(unparseable frontmatter)` 不阻塞）。對應 D2 + **Status output is a markdown table of result file frontmatter summary** 的 "Malformed frontmatter in single file does not abort" scenario。Acceptance: SKILL body grep `python3\|awk` ≥ 1、grep `unparseable\|malformed\|—` ≥ 1。
- [x] 1.5 寫入 Step 3 (Emit markdown table)：columns 順序 `filename` / `skill type` / `target / task` / `outcome summary` / `timestamp` / `error`；`skill type` 從 filename prefix 推斷（review-* / rescue-* / adversarial-review-*）、`target / task` 從 frontmatter target 或 task_description（截 50 char）、`outcome summary` 由 skill type 決定字串（review = `<N> findings`、rescue = outcome enum 值、adversarial-review = `4/4 sections`）、`timestamp` 從 filename ISO8601 部分截 `date HH:MM`。對應 D8: Status table format — markdown table + **Status output is a markdown table of result file frontmatter summary** "Populated .codex-pro/ produces a markdown table" + Example block。Acceptance: SKILL body grep `| filename | skill type` ≥ 1（table header）、grep `4/4 sections` ≥ 1、grep `findings\|outcome` ≥ 1。
- [x] 1.6 寫入 Step 4 (Handle missing / empty .codex-pro/) — 對應 D7 + **Status handles missing or empty .codex-pro/ as informational** 兩 scenarios：(a) 目錄不存在 → 印「`.codex-pro/` not yet created — any producer skill creates it on first run」+ exit 0；(b) 空目錄 → 印 `No result files found` + exit 0；(c) 跑成功 → table + exit 0。**Skill 嚴禁 `mkdir -p .codex-pro/`**（read-only 不可 side-effect 建目錄）。Acceptance: SKILL body grep `not yet created` ≥ 1、grep `No result files found` ≥ 1、grep `mkdir` 等於 0。
- [x] 1.7 寫入「與 setup 的對比 + read-only category 定位」段（mental-model 區隔）：明示「status 與 setup 同屬 read-only category、與 review / rescue / adversarial-review 的 mutating producer 對比、與 batch 的 mutating exception 對比」、對應 D6 + 為 future status / result / cancel 三 skill 之 namespace。Acceptance: SKILL body grep `read-only category\|consumer\|setup` ≥ 1。

## 2. result SKILL.md（new）

- [x] 2.1 建立 `plugins/codex-pro/skills/result/SKILL.md` 並寫入 YAML frontmatter（`name: result`、`allowed-tools: [Bash, Read]`、description block 含 trigger keywords `show result file` / `display review` / `顯示結果` / `看完整` / `detail` — 與 status 區隔（list vs detail mental model））。驗證 **Result skill registration and selection-mode argument parsing** "Skill is registered and discoverable" scenario。Acceptance: tests/static.sh per-skill frontmatter loop pass + `grep "show result\|顯示結果\|看完整\|detail" SKILL.md` 命中。
- [x] 2.2 寫入「行為原則」段：read-only consumer category 紀律（同 status、與 setup 同類）+ 三 selection mode 列出（positional filename / `--latest <skill>` / `--latest` 無 arg）+ 明示 mutex（同時提供位置 + `--latest` reject）+ 嚴守不 mutate。對應 **Result invocation is read-only with no Codex interaction** + D6。Acceptance: SKILL body grep `codex-call` 等於 0、grep `codex exec` 等於 0、grep `read-only\|consumer` ≥ 1。
- [x] 2.3 寫入 Step 1 (Parse argument & 三 mode)：mode (a) 位置 `<filename>` 完整檔名（不含 path）、mode (b) `--latest <skill>` 三 producer name 之一、mode (c) `--latest` 無 arg（全 producer 最新）；若同時提供 (a) + (b/c)、印 usage hint + exit 非 0。對應 **Result skill registration and selection-mode argument parsing** 三 selection scenarios + "Conflicting arguments are rejected" scenario。Acceptance: SKILL body grep `--latest` ≥ 3（三 mode 都提）、grep `mutually exclusive\|mutex\|互斥` ≥ 1。
- [x] 2.4 寫入 Step 2 (Selection logic 用 filename lexical order)：mode (b/c) 邏輯為 `ls .codex-pro/<prefix-or-all>*.md | sort -r | head -1`；明示「lexical filename = ISO8601 timestamp source of truth、不用 frontmatter timestamp 也不用 filesystem mtime」。對應 D3: --latest selection logic — frontmatter timestamp vs filesystem mtime + **Result selection uses filename lexical order as the timestamp authority** 兩 scenarios（lexical = ISO8601、mtime 不諮詢）。Acceptance: SKILL body grep `lexical\|sort` ≥ 1、grep `mtime` ≥ 1（明示不用、文字 reference）、grep `ISO8601\|timestamp` ≥ 1。
- [x] 2.5 寫入 Step 3 (Display file content)：用 Read tool 拿 file 完整內容、印到 stdout（frontmatter + body 全顯）；exit 0 if file resolvable。Acceptance: SKILL body grep `Read\|cat` ≥ 1（file display 機制）+ grep `stdout` ≥ 1。
- [x] 2.6 寫入 Step 4 (Fail-fast remediation)：4 種 unresolvable cases — (a) `.codex-pro/` missing → 引導跑任一 producer skill、(b) `.codex-pro/` empty → 同 (a)、(c) 位置 filename 不存在 → 引導跑 `/codex-pro:status` 看可用清單、(d) `--latest <skill>` 零 match → 引導跑 `/codex-pro:<skill>`；exit 非 0；**嚴禁 silent fallback（不抓最近 review 假裝是 adversarial-review）**。對應 **Result fails fast with remediation when target is unresolvable** 三 scenarios。Acceptance: SKILL body grep `/codex-pro:status` ≥ 1、grep `silent\|fallback\|顯式` ≥ 1。

## 3. cancel SKILL.md（new）

- [x] 3.1 建立 `plugins/codex-pro/skills/cancel/SKILL.md` 並寫入 YAML frontmatter（`name: cancel`、`allowed-tools: [Bash]`、**description block 必含 literal substring `informational only`** 作為 mental-model anchor）。驗證 **Cancel skill registration with zero-argument acceptance** "Skill is registered and discoverable" scenario。Acceptance: tests/static.sh per-skill frontmatter loop pass + `grep "informational only" SKILL.md` ≥ 1（description 必含）。
- [x] 3.2 寫入「行為原則 + 無 PID kill + 無 disk mutation」段：明示 4 條紀律 — 無 `codex-call` 呼叫、無 `codex exec`、無 `kill` / `SIGTERM` / `SIGKILL` 任何 signal、無 file mutation（不建 .codex-pro/、不寫任何檔）+ 為 stdout-only informational skill；任何 argument 印 usage hint 但仍 exit 0（cancel 永不為 error）。對應 **Cancel is an informational read-only no-op** 兩 scenarios + D4: Cancel 為 informational read-only no-op 的契約 + **Cancel skill registration with zero-argument acceptance** "Argument is rejected with usage but still exit 0" scenario。Acceptance: SKILL body grep `codex-call` 等於 0、grep `codex exec` 等於 0、grep -E `^kill |kill -|SIGTERM|SIGKILL` 等於 0（mention 在 prose 可、command 不可）、grep `mkdir` 等於 0、grep `informational` ≥ 1。
- [x] 3.3 寫入 explainer + 3 remediation 段（**byte-identical output every invocation**）：explainer 含 `stateless` / `single-shot` / `synchronous HTTPS` / `chatgpt.com/backend-api`；3 remediation lines — (1) `Ctrl-C` in Claude Code session、(2) wait for `--max-time 600` hard timeout、(3) future codex-pro `v0.3` background job mode；closing sentence literal `This message is not an error. exit 0.`；output deterministic（同 invocation 永遠同 output）。對應 **Cancel output contains the stateless-explainer plus three remediation lines** 兩 scenarios（含 substring + byte-identical）+ D4。Acceptance: SKILL body grep `stateless` ≥ 1、`Ctrl-C` ≥ 1、`--max-time 600` ≥ 1、`v0.3\|future` ≥ 1、`not an error` ≥ 1、`deterministic\|byte-identical\|相同` ≥ 1。

## 4. tests/status.sh（new、behavioral runtime test pattern）

- [x] 4.1 [P] 建立 `tests/status.sh` 骨架（仿 tests/rescue.sh 結構 + 新 mktemp fixture）：source `lib/assert.sh`、定義 `STATUS_SKILL` 變數、`assert_file "$STATUS_SKILL"` + structural assertions（frontmatter parse、`codex-call` = 0、`codex exec` = 0、`mkdir` = 0、`read-only\|consumer` ≥ 1）；結尾 `report_summary "status"`。對應 D5: Behavioral runtime test pattern + **Status invocation is read-only with no Codex interaction** 兩 scenarios。Acceptance: `bash -n tests/status.sh` 通過；structural section 約 8-10 assertion。
- [x] 4.2 [P] 加 behavioral runtime fixture：定義 helper function `make_fixture_codex_pro_dir()` — `mktemp -d` 建 temp dir、`mkdir "$TMPDIR/.codex-pro"`、寫 3 個 fake result file（一個 review、一個 rescue、一個 adversarial-review）涵蓋三類 frontmatter schema、寫一個 malformed YAML 第 4 檔；trap EXIT `rm -rf "$TMPDIR"`。對應 D5。Acceptance: helper function 定義 + 3 fake file 寫入 + trap cleanup。
- [x] 4.3 [P] 加 missing / empty `.codex-pro/` behavioral test：cd 進 empty mktemp dir（無 `.codex-pro/`）跑 status 邏輯（從 SKILL.md extract 或重複實作）、assert stdout 含 `not yet created`、exit 0；然後 mkdir 空 `.codex-pro/` + 重跑、assert stdout 含 `No result files found`、exit 0。對應 D7 + **Status handles missing or empty .codex-pro/ as informational** 兩 scenarios。Acceptance: 4 條 assertion（兩種 case × stdout + exit code）。
- [x] 4.4 [P] 加 populated `.codex-pro/` behavioral test：用 4.2 fixture、cd 進 temp dir、跑 status 邏輯、assert stdout 含 markdown table header `| filename | skill type`、含 3 row（review / rescue / adversarial-review）、第 4 行 malformed 顯示 `(unparseable frontmatter)`、exit 0。對應 D2 + **Status output is a markdown table of result file frontmatter summary** "Populated .codex-pro/" + "Malformed frontmatter" scenarios。Acceptance: ~6 條 assertion（table header + 3 row + malformed handling + exit）。
- [x] 4.5 [P] 加 `--skill` filter behavioral test：用 4.2 fixture、跑 `status --skill rescue`、assert stdout 只含 rescue row（不含 review / adversarial-review）；跑 `status --skill bogus`、assert exit 非 0 + stdout 含 usage hint with 三 valid value 字串。對應 **Status skill registration and argument parsing** "Invalid --skill value is rejected" scenario。Acceptance: ~4 條 assertion（filter 正確 + invalid 拒絕 + exit code）。

## 5. tests/result.sh（new、behavioral runtime test pattern）

- [x] 5.1 [P] 建立 `tests/result.sh` 骨架（同 status.sh pattern）：source assert.sh、`assert_file "$RESULT_SKILL"`、structural assertions（frontmatter parse、`codex-call` = 0、`codex exec` = 0、`mkdir` = 0、三 selection mode keywords 各 ≥ 1）；結尾 `report_summary "result"`。對應 **Result invocation is read-only with no Codex interaction** 兩 scenarios。Acceptance: `bash -n tests/result.sh` 通過；structural 約 8-10 assertion。
- [x] 5.2 [P] 加 behavioral runtime fixture：reuse status.sh 的 `make_fixture_codex_pro_dir()`（從 `lib/` extract 或 inline 重複）— 3 個 fake file 涵蓋三 producer schema + 額外 2 個 review file（不同 timestamp）測 lexical sort。Acceptance: 5 fake file 寫入 + trap cleanup。
- [x] 5.3 [P] 加 positional filename selection behavioral test：cd 進 fixture dir、跑 `result review-20260601T120000Z.md`、assert stdout 含該檔完整內容、exit 0；跑 `result bogus.md`、assert stdout 含 `/codex-pro:status` remediation 字串、exit 非 0。對應 **Result skill registration and selection-mode argument parsing** "Positional filename selects" + **Result fails fast with remediation when target is unresolvable** "Unknown filename" scenarios。Acceptance: ~4 條 assertion。
- [x] 5.4 [P] 加 `--latest <skill>` lexical order behavioral test：用 fixture 跑 `result --latest review`（fixture 含 2 個 review timestamp）、assert 抓較晚的 ISO8601、exit 0；跑 `result --latest adversarial-review`（fixture 僅 1 個 adv-review）、assert 抓該檔、exit 0；額外用 `touch` 倒推 fixture 第一個 rescue file 的 mtime、跑 `result --latest`（無 arg、全 producer 最新）、assert lexical-newest 被選（mtime 不諮詢）。對應 D3 + **Result selection uses filename lexical order as the timestamp authority** 兩 scenarios（lexical / mtime-irrelevance）。Acceptance: ~5 條 assertion。
- [x] 5.5 [P] 加 mutex argument & missing remediation behavioral test：跑 `result review-X.md --latest`、assert exit 非 0 + stdout 含 "mutually exclusive" or "互斥"；rm -rf temp .codex-pro/ 後跑 `result --latest`、assert 含 producer creation remediation、exit 非 0；跑 `result --latest adversarial-review` against 僅 review files 的 fixture、assert 含 `/codex-pro:adversarial-review` remediation、exit 非 0。對應 **Result skill registration and selection-mode argument parsing** "Conflicting arguments" + **Result fails fast with remediation when target is unresolvable** "Missing .codex-pro/" + "--latest <skill> with zero matches" scenarios。Acceptance: ~6 條 assertion。

## 6. tests/cancel.sh（new、structural-only + minimal behavioral）

- [x] 6.1 [P] 建立 `tests/cancel.sh` 骨架：source assert.sh、`assert_file "$CANCEL_SKILL"`、structural assertions — frontmatter `name: cancel`、`allowed-tools` 含 `Bash`、description 含 literal `informational only`；body grep `codex-call` = 0、`codex exec` = 0、`mkdir` = 0；body grep -E `^kill |kill -|SIGTERM|SIGKILL` = 0（command 形式禁、prose 形式 OK）；結尾 `report_summary "cancel"`。對應 **Cancel skill registration with zero-argument acceptance** + **Cancel is an informational read-only no-op** 兩 scenarios + D4。Acceptance: ~8 條 assertion 全綠。
- [x] 6.2 [P] 加 explainer substring assertions：body grep `stateless` ≥ 1、`single-shot\|synchronous HTTPS` ≥ 1、`Ctrl-C` ≥ 1、`--max-time 600` ≥ 1、`v0.3\|future` ≥ 1、`not an error` ≥ 1、`deterministic\|byte-identical\|相同` ≥ 1。對應 **Cancel output contains the stateless-explainer plus three remediation lines** 兩 scenarios + D4。Acceptance: ~7 條 substring assertion 全綠。
- [x] 6.3 [P] 加 minimal behavioral test（deterministic output）：定義 expected explainer string 或 sha256 hash、若 SKILL.md 用 heredoc/printf 寫死 explainer block、extract 該 block 兩次 sha256 比對、assert byte-identical。對應 **Cancel output contains the stateless-explainer plus three remediation lines** "Output is deterministic" scenario。Acceptance: ~2 條 assertion（extract + sha256 equality）。可選擇較簡單的「explainer block exists in SKILL.md」structural check 等價、若 behavioral extract 困難。

## 7. tests/run.sh dispatcher 整合 + tests/lib (optional)

- [x] 7.1 修改 `tests/run.sh` Execute layers 區塊在 `run_layer adversarial-review` 之後加三行 `run_layer status` / `run_layer result` / `run_layer cancel`。Acceptance: `bash tests/run.sh` 後輸出含三新 layer header；aggregate 從 149 升至 ~200（±5）；exit 0。
- [x] 7.2 [可選] 若 status.sh 與 result.sh 的 `make_fixture_codex_pro_dir()` helper 重複嚴重、抽到 `tests/lib/fixture.sh`、source 即可；否則 keep inline。Acceptance: 若抽出、status.sh + result.sh source `lib/fixture.sh`、helper 只定義一次、整體 assertion 不變。

## 8. tests/static.sh per-skill loop 驗證（純執行驗證、無 code change）

- [x] 8.1 跑 `bash tests/static.sh` 確認三 skill 自動被 per-skill frontmatter + namespace consistency loop 涵蓋；若任一 assertion fail、回到對應 1.x / 2.x / 3.x SKILL.md 對齊。Acceptance: tests/static.sh 整體 0 fail；三 skill 名稱在 namespace consistency grep 結果裡至少出現於 SKILL.md + spec.md + tests/<skill>.sh + tests/run.sh + CLAUDE.md + README.md 六處。

## 9. CLAUDE.md 更新

- [x] 9.1 修改 Commands surface 表三行：`/codex:status` / `:result` / `:cancel` 對應行從「規劃中」改「已落地 v0.1」、備註欄改成：(a) status：「read-only consumer — 掃 `.codex-pro/*.md` + markdown table summary、`--skill <name>` filter、missing/empty 為 informational」；(b) result：「read-only consumer — 顯示特定 result file、三 selection mode（位置 / `--latest <skill>` / `--latest`）、fail-fast with remediation」；(c) cancel：「**informational only** — codex-pro v0.2 stateless、無 PID 可殺、列 3 remediation（Ctrl-C / `--max-time 600` timeout / future v0.3 background mode）、exit 0」。Acceptance: `grep "/codex-pro:status" CLAUDE.md` 命中且不含「規劃中」、result + cancel 同樣驗證。
- [x] 9.2 修改 Marketplace structure 段 skills 子目錄列表：在 `adversarial-review/SKILL.md` 條目後新增 3 行 `status/SKILL.md` / `result/SKILL.md` / `cancel/SKILL.md` 各標「已落地 v0.1（read-only consumer / informational only for cancel）」；同時移除 `jobs-status/jobs-result/jobs-cancel/  ← 未來` 行（已實作、不再屬未來）。Acceptance: `grep -E "status/SKILL\.md|result/SKILL\.md|cancel/SKILL\.md" CLAUDE.md` 命中三行；`grep "jobs-status" CLAUDE.md` 等於 0（殘留清掃）。
- [x] 9.3 在 CLAUDE.md「Review vs adversarial-review decision table」段後新增「Read-only consumer skills（status / result / cancel）」獨立小節 — 對應 D6: Read-only category 引入 — 含四 category 軸表格（Read-only environment = setup / Read-only consumer = status + result + cancel / Mutating producer = review + rescue + adversarial-review / Mutating exception = batch）+ 一段 prose 說明 v0.3 future skill 如何 fit 進 category。Acceptance: `grep "Read-only consumer\|Read-only category" CLAUDE.md` 命中、且該段含四 category 軸表格（≥ 4 row 各列 category 名稱）。

## 10. README.md 更新

- [x] 10.1 修改 What it replaces 表三行：`/codex:status` / `:result` / `:cancel` 對應行從「規劃中」改 status + result 為「已落地 v0.1」、cancel 為「已落地 v0.1（informational only）」。Acceptance: `grep "/codex-pro:status" README.md` 命中且不含「規劃中」、其他兩個同。
- [x] 10.2 修改 Skills 表：原 `status` / `result` / `cancel` 合併行（「規劃中 | Background job 管理（含 token / cost / tier 觀測）」）拆成三 row + 改 v0.1.0：(a) status：「Read-only consumer — 掃 `.codex-pro/*.md` 並輸出 markdown table summary（filename / skill type / target / outcome summary / timestamp / error）、`--skill <name>` filter、missing/empty 為 informational」；(b) result：「Read-only consumer — 顯示特定 result file（frontmatter + body）、三 selection mode（位置 filename / `--latest <skill>` / `--latest` 無 arg）、用 filename lexical order 決定 most recent（不查 mtime / frontmatter）、fail-fast with `/codex-pro:status` 或 producer skill 之 remediation」；(c) cancel：「**Informational only** — codex-pro v0.2 為 stateless single-shot、不殺任何 PID、不送 HTTPS；輸出 stateless explainer + 3 條 remediation（Ctrl-C / `--max-time 600` timeout / future v0.3+ background mode）、exit 0、deterministic byte-identical output；displayed limitation 而非 silent stub」。Acceptance: `grep "v0.1.0" README.md` 在三 row 各命中、cancel 行含 `Informational only` 字串、status row 含 `--skill` 字串。
- [x] 10.3 在 README.md Skills 表後（既有「Review vs adversarial-review — when to use which」段之後）新增「Read-only vs producer skills」小節 — 對應 D6 — 含 prose 說明 v0.2 起 codex-pro 分成 read-only category（setup + status + result + cancel）與 producer category（review + rescue + adversarial-review + batch exception）兩軸、為 user 區隔「我跑這 skill 會不會動 disk / 燒 quota」mental model。Acceptance: `grep "Read-only vs producer\|read-only category\|consumer skills" README.md` 命中、含一段 prose ≥ 50 字。

## 11. 整合驗證 + smoke

- [x] 11.1 跑 `bash tests/run.sh` 整套 Layer 1+2：9 layers 全綠（static / setup / batch / review / rescue / adversarial-review / status / result / cancel）、aggregate 總 assertion 數約 200（±5）、exit 0。Acceptance: `bash tests/run.sh; echo $?` 印 0；輸出末段 `All layers passed.`。
- [x] 11.2 [smoke] 依 [[feedback-codex-pro-smoke-before-archive]] memory 紀律 — 本 change 三 skill 都是 read-only file ops、無 codex-call、**Layer 2 behavioral test 已涵蓋 runtime 邏輯**、不需 real codex-call smoke（智 saving 一次 Codex quota call）。仍可選擇手動跑：跑一次任一 producer 產生 fixture file 後手動 invoke `/codex-pro:status` / `/codex-pro:result --latest` / `/codex-pro:cancel`、確認三 skill UX 符合 spec。Acceptance: Layer 2 全綠即可、smoke optional；若跑 smoke、result.codex-pro/status output 含 table、cancel output 含 explainer + 3 remediation。

## Coverage map

本 change 的 task → spec requirement → design decision 對應（analyzer 用本段交叉檢核 requirement 名稱與 design 標題的文字 reference；勿因美觀刪除）。

### Spec requirements covered

**status spec:**
- **Status skill registration and argument parsing** → tasks 1.1, 1.3
- **Status invocation is read-only with no Codex interaction** → tasks 1.2, 1.6（mkdir = 0）
- **Status output is a markdown table of result file frontmatter summary** → tasks 1.4, 1.5
- **Status handles missing or empty .codex-pro/ as informational** → task 1.6

**result spec:**
- **Result skill registration and selection-mode argument parsing** → tasks 2.1, 2.3
- **Result invocation is read-only with no Codex interaction** → task 2.2
- **Result selection uses filename lexical order as the timestamp authority** → task 2.4
- **Result fails fast with remediation when target is unresolvable** → task 2.6

**cancel spec:**
- **Cancel skill registration with zero-argument acceptance** → task 3.1
- **Cancel is an informational read-only no-op** → task 3.2
- **Cancel output contains the stateless-explainer plus three remediation lines** → task 3.3

### Design decisions covered

- **D1: 三個獨立 skill vs 單一 skill 子命令** → tasks 1.1 + 2.1 + 3.1（三獨立 SKILL.md 目錄結構）
- **D2: Heterogeneous frontmatter parse 策略** → tasks 1.3 + 1.4 + 1.5（filename prefix 推 skill type、tolerant YAML parse、union 欄位）
- **D3: `--latest` selection logic — frontmatter timestamp vs filesystem mtime** → task 2.4（lexical filename = ISO8601 authority、mtime 不諮詢）
- **D4: Cancel 為 informational read-only no-op 的契約** → tasks 3.2 + 3.3（no PID kill、no disk mutation、exit 0、deterministic）
- **D5: Behavioral runtime test pattern（mktemp + fake .codex-pro/）** → tasks 4.1-4.5 + 5.1-5.5（mktemp fixture + 三 producer schema fake + invoke + assert stdout）
- **D6: Read-only category 引入** → tasks 1.2 + 1.7 + 2.2 + 9.3 + 10.3（SKILL.md mental-model 區隔 + CLAUDE.md/README.md 四 category 軸表格）
- **D7: 缺漏 / 空 .codex-pro/ 處理策略 by skill** → tasks 1.6 + 2.6 + 4.3 + 5.5（status 友善 / result fail-fast / cancel 不檢查）
- **D8: Status table format — markdown table** → tasks 1.5 + 4.4（columns 順序 + markdown table 渲染）
