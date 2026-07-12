# 2026-07-12 — Heading 斷言 promotion + 12-combo e2e matrix（issue #1 完結）

## 摘要

`harden-producer-heading-reliability` Spectra change 完結（issue #1，開案 2026-06-11）：12-combo Layer 3 e2e matrix 於 gpt-5.6-sol 觀測 heading warn = 0，e2e heading 檢查依 conditional promotion 條款由 warn 升 **hard 斷言**。Change 已 archive，delta 合入 e2e-tests + review specs。

Commits: `def10e8`、`c5c6448`、`a3b463d`｜Tag: `idd-1-verified`｜Sister: #6

## 變更

- **tests/e2e.sh**：3 個 heading 檢查點 `verify_substring_warn` → `verify_substring`（review `## Summary`/`## Findings` + adversarial 4-section 迴圈）；註解記錄證據範圍（10/10 observable combos — codex verify 抓到的精度修正）
- **openspec**：change archive；e2e-tests spec「Heading assertion strength」+ review spec 合入 promotion 後狀態
- **tasks.md 誠實記錄**：3.3 標 `[~]`（adversarial live recheck 被 #6 阻擋，heading 證據引 matrix）；4.1/4.2 補勾（早已 ship 的版本/docs 工作）

## 驗證

- 12-combo matrix：10/12 exit 0、heading warn 0；2 個 adversarial combo 失敗於正交的背景執行孤兒問題 → **#6**（producer skills 需明文 codex-call 前景同步執行）
- Promotion recheck：review/mixed hard 斷言 live 綠
- Task 5.1 mandatory smoke：真實 Step 3 instructions + git fixture + 真 codex-call，`## Summary`/`## Findings`/`### Finding 1:` 三 literal tokens 全中
- Codex quick verify（promotion diff）：3 OK + 1 註解精度 finding（已修）
- `tests/run.sh` 全綠

## Follow-ups

- #6 producer skills codex-call 前景同步執行條款（修復後補 adversarial combo live 證據）
