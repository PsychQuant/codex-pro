## 1. Rescue skill 入口

- [x] 1.1 建立 `plugins/codex-pro/skills/rescue/SKILL.md`（D5: SKILL.md body 結構 — 與 review 共享 default rule pattern、D2: Task delegation 結構 — 三欄輸入）：產出 SKILL.md，frontmatter 含 `name: rescue`、`description` 一段描述 rescue 用途與三欄輸入（task / context / criteria）、`allowed-tools` 含 Bash 與 Read；body 結構與 review SKILL.md 對齊 — Step 1 解析 argument（task description + `--context` + `--criteria` + `--resume`/`--fresh`）、Step 2 收 prompt（task brief + context file 內容 + completion criteria）、Step 3 build instructions（含 result file output format 規範）、Step 4 呼叫 codex-call、Step 5 處理 exit code。驗證 **Rescue skill registration and argument parsing** — python3 parse YAML frontmatter 顯示 `name=rescue`、`allowed-tools` 含 Bash + Read；body grep `--context` ≥ 1、`--criteria` ≥ 1、`Step 1`/`Step 2`/`Step 3`/`Step 4`/`Step 5` 五段標題各 ≥ 1。

- [x] 1.2 SKILL.md 嚴守 Design constraint #1（D1: codex-call invocation 沿用 review pattern + 加 session flag）：SKILL.md body grep `codex-call` ≥ 1（明示主 invocation、default rule）、grep `codex exec` 等於 0（嚴守 #1、與 batch 對比、與 review 對齊）、grep `--max-time 600` ≥ 1（hard timeout 與 review 同）、grep `--model` 與 `--effort` 各 ≥ 1。驗證 **Rescue invocation uses codex-call HTTPS direct without subprocess for Codex** 兩個 scenarios — `codex-call` 字串存在、`codex exec` 為 0、hard timeout 明示。

- [x] 1.3 SKILL.md 列 fail-fast 4 類含 task_unclear（D4: Fail-fast 4 類（review 3 類 + task_unclear））：SKILL.md body 明確記錄 4 種 error class 與對應 result file frontmatter `error` value — grep `rate_limit` ≥ 1、`oauth_invalid` ≥ 1、`timeout` ≥ 1、`task_unclear` ≥ 1；同時 body 必須含一句明確「不 retry」或 `fail-fast` 語意。驗證 **Rescue failures trigger circuit-breaker fail-fast across four classes** 四個 scenarios — 四個 error class 字串都被 SKILL.md 列為 frontmatter `error` field 可能值；同時 `task_unclear` 是 rescue-specific 第 4 類（review 沒有），明示為「Codex 無法 commit 答案時必須顯式回報」。

- [x] 1.4 SKILL.md 含 `--resume` 與 `--fresh` flag 處理（D1 session flag part 2 + D2 argument parsing）：SKILL.md body grep `--resume` ≥ 1（明示接續 previous session 機制）、grep `--fresh` ≥ 1（明示預設新 session）、grep `session_id` ≥ 1（frontmatter field 提及）、grep `resume_from` ≥ 1（frontmatter field 提及）。SKILL.md body 必須明示「`--resume` 與 `--fresh` mutually exclusive」（grep `mutually exclusive` 或 `互斥` ≥ 1）。驗證 **Rescue skill registration and argument parsing** 的 "Resume flag records original session" 與 "--resume and --fresh are mutually exclusive" scenarios — 兩個 flag 字串與 frontmatter field 字串都在 SKILL body 內。

## 2. Result file 結構契約

- [x] 2.1 SKILL.md body 明示 result file 結構 + 8 frontmatter fields + 4 outcome enum values（D3: Result file 結構 — frontmatter + 三 section）：body grep `.codex-pro/rescue-` ≥ 1（檔案路徑模板）、`## Task Brief` ≥ 1、`## Outcome` ≥ 1、`## Suggested Next Steps` ≥ 1（三 section 模板）；8 個 frontmatter field 字串（`task_description`、`session_id`、`resume_from`、`model`、`effort`、`timestamp`、`outcome`、`error`）各於 body 至少出現 1 次；4 個 outcome enum 值字串（`completed`、`partial`、`unclear`、`requires_external`）各 ≥ 1 次。驗證 **Rescue output is a structured Markdown result file** 三個 scenarios — frontmatter 結構契約、三 section 模板、outcome enum 完整、first run mkdir 紀律全部編碼進 SKILL 指示。

## 3. Layer 2 test

- [x] 3.1 建立 `tests/rescue.sh`（D6: tests/rescue.sh + static.sh 自動 cover — Layer 2 部分）：實作 Layer 2 behavioral assertions — (a) SKILL.md frontmatter parse name=rescue、allowed-tools 含 Bash + Read；(b) grep `codex-call` SKILL.md ≥ 1；(c) grep `codex exec` SKILL.md 等於 0；(d) grep `--max-time 600` ≥ 1；(e) grep `rate_limit` / `oauth_invalid` / `timeout` / `task_unclear` 4 個 fail-fast 字串各 ≥ 1；(f) grep `不 retry` 或 `fail-fast` ≥ 1；(g) grep `.codex-pro/rescue-` 與 `## Task Brief` / `## Outcome` / `## Suggested Next Steps` 三段標題各 ≥ 1；(h) grep 8 個 frontmatter field 字串各 ≥ 1；(i) grep 4 個 outcome enum 值各 ≥ 1；(j) grep `--resume` ≥ 1、`--fresh` ≥ 1。寫法與既有 `tests/review.sh` 同 pattern（source lib/assert.sh、用 assert_eq / assert_contains / pass / fail、結尾 report_summary "rescue"）。驗證：`bash tests/rescue.sh` 在乾淨 repo 跑全綠、exit 0。

## 4. Test runner integration

- [x] 4.1 修 `tests/run.sh` dispatcher 加 rescue layer（D6: tests/rescue.sh + static.sh 自動 cover — runner integration 部分）：在現有 `run_layer static` / `run_layer setup` / `run_layer batch` / `run_layer review` 後加 `run_layer rescue`、aggregate summary 反映新 layer。`tests/static.sh` 既有 per-skill namespace loop 與 frontmatter loop 自動 cover rescue 子目錄、無需新 task 改 static.sh。驗證：`bash tests/run.sh` 顯示 5 layers / 5 pass、aggregate assertions count 從 79 增至 ≥ 100（rescue.sh ~22 個 + static auto-cover 4 個 namespace assertion + 4 個 frontmatter assertion ≈ +30）、exit 0。

## 5. Doc 更新

- [x] 5.1 修 `CLAUDE.md` Commands surface 表（D6 namespace consistency 連動）：`/codex-pro:rescue` 列從「規劃中」改「已落地 v0.1」、備註欄改為「走 codex-call HTTPS direct、Design constraint #1 default rule（與 review 同模板、與 batch exception 對比）；task delegation；fail-fast 4 類含 task_unclear」；Marketplace structure 段 skills 子目錄列表加 `rescue/SKILL.md ← 已落地：/codex-pro:rescue v0.1`。驗證：grep `/codex-pro:rescue` CLAUDE.md ≥ 2（一次表格、一次 Marketplace structure 段）；grep `/codex-pro:rescue.*規劃中` 為 0（rescue 不再標規劃中）；SPECTRA block 28 行 byte-identical。

- [x] 5.2 修 `README.md` Skills 表（D6 namespace consistency 連動）：What it replaces 表 `/codex:rescue` 行對應 codex-pro command 改為「`/codex-pro:rescue` — 已落地 v0.1」（原本「規劃中」）；Skills 表新增 `rescue` 列（v0.1、用 codex-call HTTPS direct、寫 result file 到 `.codex-pro/rescue-<ts>.md`、fail-fast 4 類含 task_unclear、`--resume`/`--fresh` flag）。驗證：grep `/codex-pro:rescue` README.md ≥ 2；grep `^| .rescue.` Skills 表 = 1 列。

## 6. 端到端驗收

- [x] 6.1 全綠端到端跑（驗證 **Test runner entry point**（既有）+ 新 rescue layer 整合）：在乾淨 codex-pro repo 跑 `bash tests/run.sh`，確認 exit 0、aggregate summary 顯示 5 layers / 0 fail、assertions count ≥ 100；單跑 `bash tests/rescue.sh` 也 exit 0；`bash tests/static.sh` 仍 exit 0（rescue namespace 與 frontmatter 自動 cover 全 pass）。

- [x] 6.2 namespace consistency end-to-end（驗證 spec **Rescue skill registration and argument parsing** 的 "Skill is registered and discoverable" scenario + D6 namespace check）：grep `/codex-pro-rescue` 於整個 codex-pro repo（排除 archive/、.git/ 等）= 0（無 marketplace-pivot 時代 sub-plugin 命名殘留、除非屬本 change tasks/design 內為描述 invariant 而提及的 self-reference）；grep `/codex-pro:rescue` ≥ 3（至少 CLAUDE.md + README.md + 本 change 的 specs/rescue/spec.md 各 1 次）；`plugins/codex-pro/skills/rescue/SKILL.md` 與 `plugins/codex-pro/skills/rescue/` 目錄存在且結構完整。
