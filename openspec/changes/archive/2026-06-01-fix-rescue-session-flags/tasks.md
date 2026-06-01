## 1. SKILL.md 移除 session flag surface

- [x] 1.1 SKILL.md Step 1 移除 `--resume` / `--fresh` argument parsing 段（對應 Proposed Solution 第 1 點）：刪除 Step 1 內描述「`--resume <session-id>` / `--fresh`（mutually exclusive、`--fresh` 為預設）」與其 session 控制段落；保留 `--context` 與 `--criteria` 解析說明；usage hint 更新為「`/codex-pro:rescue <task description> [--context <path>...] [--criteria <text>]`」不再列 session flags。驗證：grep `--resume` SKILL.md = 0、grep `--fresh` SKILL.md = 0、grep `mutually exclusive` SKILL.md = 0、grep `互斥` SKILL.md = 0。

- [x] 1.2 SKILL.md Step 4 移除 `--session <id>` passthrough（對應 Proposed Solution 第 2 點）：刪除 Step 4 codex-call invocation block 內「`[--session <session-id>]    # 當 --resume <id> 時加`」一行與相關 prose（「`--session <id>`：當 user 給 `--resume <id>` 才傳」項）；codex-call 命令形成只剩 base flags `--output` / `--model` / `--effort` / `--max-time` / `--instructions` / `--prompt-file`。驗證：grep `--session` SKILL.md = 0、grep `session_id` SKILL.md ≥ 1（保留 frontmatter field 描述）。

- [x] 1.3 SKILL.md Step 5 + Result file structure 移除 `resume_from` field（對應 Proposed Solution 第 3 點）：從 Step 5 success case frontmatter 描述移除「`resume_from`: 若使用 `--resume <id>`、記原 session ID；否則不寫此 field」、從「Result file structure（完整契約）」code block 移除 `resume_from: <原 session ID>      # 僅 --resume 時出現` 行；session_id field 描述改為「codex-call 回傳的 session ID（若 HTTP response surface；無則記 `null`）」、不再 imply 任何 continuation capability。驗證：grep `resume_from` SKILL.md = 0；grep `session_id` SKILL.md ≥ 1（仍記錄但不 promise continuation）。

- [x] 1.4 SKILL.md 加「Session continuity flags rejected」描述（對應 Spec 新 scenario「Session continuity flags are not accepted」）：於 SKILL.md 適當位置（建議 Step 1 內最後或一獨立小段）加一句說明「若 user 傳 `--resume` 或 `--fresh` flag，skill 必須 abort 並回報 v0.1.1 移除 session continuity、待 upstream codex-call 加 --session 後再 restore」。驗證：grep `session continuity` SKILL.md ≥ 1、grep `v0.1.1` SKILL.md ≥ 1、grep `upstream` SKILL.md ≥ 1。

- [x] 1.5 SKILL.md 「與 review 的對比」表格更新（對應 cross-reference cleanup）：原表格內 rescue 列「argument 結構」欄位「task description + --context + --criteria + --resume/--fresh」改為「task description + --context + --criteria」、刪除 session 相關 cell；其他列（Mental model / Result file H2 sections / Frontmatter outcome / Fail-fast 類別 / codex-call invocation）不動。驗證：表格內 grep `--resume` = 0、grep `--fresh` = 0、grep `task description.*--context.*--criteria` ≥ 1。

## 2. Test 同步

- [x] 2.1 `tests/rescue.sh` 移除 session-related assertions（對應 Proposed Solution 第 5 點 + Success Criteria「tests/rescue.sh 不再 assert --resume/--fresh/resume_from/mutually exclusive」）：從 rescue.sh 移除以下 4 個 assertion 段 — (a) `session flag '--resume'` 與 `session flag '--fresh'` 兩個 assert_eq / pass-fail block；(b) `Mutually exclusive marker` 的 grep + pass/fail block；(c) frontmatter loop 內 `resume_from` 行（從 for-loop 字串列移除）。保留：frontmatter loop 內 `session_id` 與 `outcome` 等仍有效 field、4 個 fail-fast class assertion、4 個 outcome enum value assertion、3 個 result file section marker assertion。驗證：`bash tests/rescue.sh` 仍 exit 0；assertion 總數從 29 降至 25（±1）；grep `resume_from\|--resume\|--fresh\|mutually exclusive` tests/rescue.sh = 0。

## 3. Spec delta 完整性

- [x] 3.1 確認 spec delta 完整性（對應 Success Criteria 內 spec 移除兩 scenarios 點）：人工 review `openspec/changes/fix-rescue-session-flags/specs/rescue/spec.md`，確認 `## MODIFIED Requirements` 區段含兩個完整 requirement block（`Rescue skill registration and argument parsing` 與 `Rescue output is a structured Markdown result file`）；requirement 1 內：description 不再含「`--resume` / `--fresh`」flag 字串、不含「mutually-exclusive pair」phrasing；4 個 scenarios 含原 3 個（Skill is registered / Task description parsed / Empty task aborts）+ 1 新 scenario「Session continuity flags are not accepted」；requirement 3 內：description 移除「optional `resume_from` field」phrasing、移除「Resume flag records original session」scenario；3 個 scenarios（Success case / Example / First run mkdir）保留。驗證：grep `Resume flag records` delta spec = 0、grep `mutually-exclusive` delta spec = 0、grep `Session continuity flags are not accepted` delta spec = 1；`spectra analyze fix-rescue-session-flags` Coverage 全 Clean。

## 4. Doc 更新

- [x] 4.1 `CLAUDE.md` Commands surface 與 Marketplace structure 段移除 session flag 提及（對應 Success Criteria「CLAUDE.md 不再 mention --resume/--fresh」）：Commands surface 表 `/codex-pro:rescue` 列備註欄內若有「`--resume`/`--fresh`」字串移除、加一段 known-limitation 註記（建議：「v0.1.1 移除 session continuity；待 codex-call --session upstream support 後 restore」）；Marketplace structure 段 skills 子目錄列表 rescue 行若有 `--resume` 等字串同步移除。驗證：grep `--resume` CLAUDE.md = 0、grep `--fresh` CLAUDE.md = 0；grep `known limitation\|session continuity` CLAUDE.md ≥ 1；SPECTRA block 28 行 byte-identical。

- [x] 4.2 `README.md` Skills 表與 What it replaces 表移除 session flag 提及（對應 Success Criteria「README.md 不再 mention --resume/--fresh」）：Skills 表 `rescue` 列移除「`--resume <session-id>` / `--fresh` flag」描述、加一段「v0.1.1: session continuity 已移除（codex-call 尚無 --session）」註記；What it replaces 表 `/codex:rescue` 對應「`/codex-pro:rescue` — 已落地 v0.1」改為「— 已落地 v0.1.1」反映 bug fix 版本。驗證：grep `--resume` README.md = 0、grep `--fresh` README.md = 0；grep `v0.1.1\|session continuity` README.md ≥ 1。

## 5. 端到端驗收

- [x] 5.1 全綠端到端跑（對應 Success Criteria「`bash tests/run.sh` 完成 0 failures、assertion 總數 ~111 ±2、5 layers 全綠」）：在乾淨 codex-pro repo 跑 `bash tests/run.sh`，確認 exit 0、aggregate summary 顯示 5 layers / 0 fail、assertions count 落在 111 ±2（115 - 4 session-related + 0~2 known-limitation doc-assertion 預估）；`bash tests/rescue.sh` 獨立 exit 0；`bash tests/static.sh` 仍 exit 0（per-skill namespace assertion 自動 cover rescue 不受影響）。同時驗證 SKILL.md 與 spec delta 一致：grep `--resume` 整個 codex-pro repo（排除 archive/）= 0 except self-referential mentions（task description / proposal Root Cause / 描述紀律 anchor 等）；對 commit 前的 git diff 跑 `git diff --stat` 確認改動限於 SKILL.md / tests/rescue.sh / CLAUDE.md / README.md 四檔加 archive artifact。
