## 1. Review skill 入口

- [x] 1.1 建立 `plugins/codex-pro/skills/review/SKILL.md`（D5: SKILL.md body 結構與 batch 的對比、D2: Review target 三選一 + auto-detect）：產出 SKILL.md，frontmatter 含 `name: review`、`description` 一段描述 review 用途與 3 種 target、`allowed-tools` 含 Bash 與 Read；body 含「行為原則」段強調走 codex-call HTTPS direct、Step 1 解析 argument（無 arg / `<file>` / `--base <ref>`）、Step 2 收 prompt（git diff 或 Read）、Step 3 build instructions、Step 4 呼叫 codex-call、Step 5 處理 exit code。驗證 **Review skill registration and target resolution** — python3 parse YAML frontmatter 顯示 `name=review`、`allowed-tools` 含 Bash 與 Read；body grep `--base` ≥ 1、`git diff` ≥ 1、`--diff` 提及。

- [x] 1.2 SKILL.md 嚴守 Design constraint #1（D1: codex-call invocation 採 single-shot + hard timeout + no retry）：SKILL.md body grep `codex-call` ≥ 1（明示主 invocation）、grep `codex exec` 為 0（嚴守不 spawn subprocess、與 batch 形成對比）、grep `--max-time 600` ≥ 1（hard timeout flag）、grep `--model` 與 `--effort` 各 ≥ 1。驗證 **Review invocation uses codex-call HTTPS direct without subprocess for Codex** 兩個 scenarios — `codex-call` 字串存在且 `codex exec` 完全不在 review SKILL 內。

- [x] 1.3 SKILL.md 列 fail-fast 三條件（D4: Circuit breaker 紀律 — fail-fast 三條件）：SKILL.md body 明確記錄 3 種 error class 與對應 result file frontmatter `error` value — grep `rate_limit` ≥ 1、`oauth_invalid` ≥ 1、`timeout` ≥ 1；同時 body 必須含一句明確「不 retry」語意（grep `不 retry` 或 `no retry` 或 `fail-fast` ≥ 1）。驗證 **Review failures trigger circuit-breaker fail-fast** 三個 scenarios — 三個 error class 字串都被 SKILL.md 列為 frontmatter `error` field 可能值。

## 2. Result file 結構契約

- [x] 2.1 SKILL.md body 明示 result file 結構（D3: Result file 採 markdown + YAML frontmatter）：body grep `.codex-pro/review-` ≥ 1（檔案路徑模板）、`## Summary` ≥ 1、`## Findings` ≥ 1、`### Finding` ≥ 1（per-finding heading 模板）；6 個 frontmatter field 字串（`target`、`model`、`effort`、`timestamp`、`findings_count`、`error`）各於 SKILL.md body 至少出現 1 次。驗證 **Review output is a structured Markdown result file** 三個 scenarios — frontmatter 結構契約、findings 無上限、first run mkdir 紀律全部編碼進 SKILL 指示。

## 3. Layer 2 test

- [x] 3.1 建立 `tests/review.sh`（D6: tests/review.sh 採 Layer 2 + Layer 1 兩層 cover）：實作 Layer 2 behavioral assertions — (a) SKILL.md frontmatter parse name=review、allowed-tools 含 Bash + Read；(b) grep `codex-call` SKILL.md ≥ 1；(c) grep `codex exec` SKILL.md 等於 0；(d) grep `--max-time 600` ≥ 1；(e) grep `rate_limit` / `oauth_invalid` / `timeout` 各 ≥ 1；(f) grep `.codex-pro/review-` 與 frontmatter 6 個 field 字串各 ≥ 1。寫法與既有 `tests/setup.sh` / `tests/batch.sh` 同 pattern（source lib/assert.sh、用 assert_eq / assert_contains / pass / fail、結尾 report_summary "review"）。驗證：`bash tests/review.sh` 在乾淨 repo 跑全綠、exit 0。

## 4. Test runner + static integration

- [x] 4.1 修 `tests/run.sh` dispatcher 加 review layer（D6: tests/review.sh 採 Layer 2 + Layer 1 兩層 cover）：在現有 `run_layer static` / `run_layer setup` / `run_layer batch` 後加 `run_layer review`、aggregate summary 反映新 layer。驗證：`bash tests/run.sh` 顯示 4 layers / 4 pass、aggregate assertions count 從 47 增至 ≥ 53（review 預計 ~6 個 assertion）、exit 0。

- [x] 4.2 修 `tests/static.sh` 加入 review namespace consistency assertion（D6: Layer 1 namespace check）：在現有 namespace consistency loop 後加 — grep `/codex-pro:review` 於 `CLAUDE.md` ≥ 1、`README.md` ≥ 1、`openspec/specs/review/spec.md`（archive 後存在）或本 change 的 specs/review/spec.md ≥ 1。SKILL.md frontmatter loop 既有 `for skill_dir in plugins/codex-pro/skills/*/` 已自動納入 review 子目錄、無需改 loop logic。驗證：bash tests/static.sh exit 0、assertions count 從 28 增 ~3 個（review namespace 3 個 file 各 1 assertion）。

## 5. Doc 更新

- [x] 5.1 修 `CLAUDE.md` Commands surface 表（D6 namespace consistency 連動）：`/codex-pro:review` 列從「規劃中」改為「已落地」、備註欄改為「走 codex-call HTTPS direct、Design constraint #1 default rule 範例（與 batch exception 對比）」；Marketplace structure 段 skills 子目錄列表加 `review/SKILL.md ← 已落地：/codex-pro:review`。驗證：grep `/codex-pro:review` CLAUDE.md ≥ 2（一次表格、一次 Marketplace structure 段）；grep `規劃中.*review[^-]` 為 0（review 不再標規劃中）；SPECTRA block 28 行 byte-identical。

- [x] 5.2 修 `README.md` Skills 表（D6 namespace consistency 連動）：What it replaces 表 `/codex:review` 行對應 codex-pro command 改為「`/codex-pro:review` — 已落地」（原本是「規劃中」）；Skills 表新增 `review` 列（v0.1、用 codex-call HTTPS direct、寫 result file 到 `.codex-pro/review-<ts>.md`）；保留 `adversarial-review` 為「規劃中」描述。驗證：grep `/codex-pro:review` README.md ≥ 2；grep `^| .review.` Skills 表 = 1 列。

## 6. 端到端驗收

- [x] 6.1 全綠端到端跑（驗證 **Test runner entry point**（既有）+ 新 review layer 整合）：在乾淨 codex-pro repo 跑 `bash tests/run.sh`，確認 exit 0、aggregate summary 顯示 4 layers / 0 fail、assertions count ≥ 53；單跑 `bash tests/review.sh` 也 exit 0；`bash tests/static.sh` 仍 exit 0（review namespace assertion 全 pass）。

- [x] 6.2 namespace consistency end-to-end（驗證 spec **Review skill registration and target resolution** 的 "Skill is registered and discoverable" scenario + D6 namespace check）：grep `/codex-pro-review` 於整個 codex-pro repo（排除 archive/、.git/、node_modules 等）= 0（無 marketplace-pivot 時代 sub-plugin 命名殘留）；grep `/codex-pro:review` ≥ 3（至少 CLAUDE.md + README.md + 本 change 的 specs/review/spec.md 各 1 次）；plugins/codex-pro/skills/review/SKILL.md 與 plugins/codex-pro/skills/review/ 目錄存在且結構完整。
