# Tasks — harden-producer-heading-reliability

review Step 3 instructions 改為 literal-token 寫法（v0.3→v0.4）+ e2e heading 檢查 conditional promotion（warn→hard）。對應 GitHub issue #1；adversarial-review SKILL.md 零改動。TDD 順序：先寫 Layer 2 斷言（RED）再改 SKILL.md（GREEN）。

## 1. Layer 2 測試先行（RED）

- [x] 1.1 在 tests/review.sh 追加 heading-hardening 斷言區塊：grep `plugins/codex-pro/skills/review/SKILL.md` 的 Step 3 instructions 必含 literal `## Summary`、`## Findings`、`exactly two H2 sections`、`### Finding N:` 四個 token，並 grep frontmatter description 含 `v0.4 — heading-hardened`。對應 review delta spec「Review system instructions name literal heading tokens」兩個 static scenario + MODIFIED invocation 的 v0.4 marker scenario。Acceptance: 新斷言先 FAIL（RED — SKILL.md 尚未改寫），既有斷言不受影響。

## 2. review SKILL.md 改寫（GREEN）

- [x] 2.1 改寫 review SKILL.md Step 3 instructions 為 design.md「Implementation Contract」內的目標文字：literal `## Summary` / `## Findings` 行 + `exactly two H2 sections, in this order` + CRITICAL 開頭條款 + literal H3 `### Finding N: <severity> — <file>:<line>`；移除 prose-noun-only 描述（"Begin with a one-paragraph Summary" / "Follow with a Findings list"）。不加 one-shot 範例（design D1）。Acceptance: 1.1 的四個 token 斷言轉 PASS。
- [x] 2.2 review SKILL.md frontmatter description 加 literal 字樣 `v0.4 — heading-hardened`（與既有 `v0.2 — untracked-by-default`、`v0.3 — profile-aware` 並存）。Acceptance: 1.1 的 v0.4 marker 斷言轉 PASS。
- [x] 2.3 跑 `bash tests/run.sh` 確認 Layer 1+2 全綠（含 1.1 新斷言與全部既有 363 斷言）。Acceptance: aggregate summary 0 fail、exit 0。

## 3. e2e 實證觀察 gate（design D3）

- [ ] 3.1 跑一次完整 Layer 3 e2e matrix：`bash tests/e2e.sh` 全部 12 combos（2 producer skill × 各自 scenario），統計 heading 類 ⚠ warn 行數（review `## Summary`+`## Findings` × mixed/binary/oversize/empty-repo/with-profile、adversarial-review 4 section）。把觀察結果（warn 數、哪個 combo、哪個 heading）逐字記錄在本檔此 task 下方與 commit message。Acceptance: matrix 跑完、觀察證據已記錄（不論綠或 miss）。
- [ ] 3.2 Conditional promotion — 依 3.1 結果二擇一執行並勾選：(a) heading warn 數 = 0 → 把 tests/e2e.sh 內 heading 檢查的 `verify_substring_warn` 呼叫（review 2 處 + adversarial-review 迴圈 1 處）改為 `verify_substring`，並更新 `verify_substring_warn` helper 上方註解（說明 heading 已 promote、warn helper 保留給未來 best-effort 用途或移除 dead code）；(b) heading warn 數 > 0 → tests/e2e.sh 不動（維持 warn），跑 /spectra-ingest 把 e2e-tests delta spec 的「Heading assertion strength」段修正為 warn 維持狀態 + 記錄觀察證據，promotion 留待後續 change。Acceptance: 兩分支擇一完成且證據可追溯。
- [ ] 3.3 （僅 3.2 走 (a) 分支時）promotion 後重跑 2 個受影響 e2e combo（`--skill review --scenario mixed` + `--skill adversarial-review --scenario mixed`）確認 hard 斷言 PASS、exit 0。Acceptance: 兩 combo 全綠；若走 (b) 分支則此 task 標記 N/A 並在 task 下方註明。

## 4. 版本與文件同步

- [x] 4.1（已於先前 session 完成 — 0.5.1 ship 含 heading-hardened description；後續 #3 再 bump 0.6.0，超額滿足）[P] plugins/codex-pro/.claude-plugin/plugin.json version `0.5.0` → `0.5.1`、description 提及 heading-hardened；.claude-plugin/marketplace.json 對應 entry 同步 `0.5.1`。Acceptance: 兩檔 version 欄一致為 0.5.1、`bash tests/static.sh` manifest 斷言綠。
- [x] 4.2（已於先前 session 完成 — CLAUDE.md/README review 條目均載 v0.4 heading-hardened，2026-07-12 驗證）[P] CLAUDE.md Commands surface 表 review 列更新為 v0.4（heading-hardened 描述）+ Marketplace structure 註解同步；README.md Skills table review 版本同步。Acceptance: grep CLAUDE.md 與 README.md 各含 `v0.4` 於 review 條目、Layer 1 namespace-consistency 斷言綠。

## 5. Pre-archive 驗證

- [ ] 5.1 MANDATORY producer smoke（per feedback-codex-pro-smoke-before-archive）：從改寫後的 SKILL.md Step 3 抽出真實 instructions 文字、在 git fixture（含 tracked 修改 + untracked 檔）上組 prompt、跑一次真 codex-call（profile 解析照 Step 4.1 真實 resolver），斷言 exit 0 + result 含 `## Summary`、`## Findings`、`### Finding 1:` 三個 literal token。Acceptance: smoke 全綠；若 codex-call 401 → 提示 user `codex login` 後重跑（不得跳過、不得以 Layer 2 代替）。
- [ ] 5.2 最終 `bash tests/run.sh` 全綠 + git status 檢查只含本 change 預期檔案（plugins/codex-pro/skills/review/SKILL.md、tests/review.sh、tests/e2e.sh（若 promote）、plugin.json、marketplace.json、CLAUDE.md、README.md、openspec/）。Acceptance: 0 fail、無 scope 外檔案異動。
