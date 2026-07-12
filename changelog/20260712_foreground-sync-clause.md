# 2026-07-12 — Producer skills 前景同步執行條款（issue #6）

## 摘要

三個 producer SKILL.md（codex-review / codex-rescue / codex-adversarial-review）的 Step 4.2 加入**前景同步執行條款**：codex-call 嚴禁 `run_in_background` 及任何背景化，result file 寫入完成前 task 未完成。修復 `claude --print` 單輪下 agent 自行背景化 codex-call 導致 result file 孤兒的 flake（issue #1 的 12-combo matrix 2/12 + recheck 連續複現；上游 #324 silent-stub 的變體）。

Issue: PsychQuant/codex-pro#6｜Commit: `2dfd62a`｜Complexity: Plan（硬閘 — 單一條款散佈 6 檔，EnterPlanMode approved）

## 變更

- 3 producer SKILL.md：Step 4.2「嚴禁 spawn codex CLI」規則後插入統一的前景同步條款（literal-token 命令式 — issue #1 實證此寫法有效）
- tests/{review,rescue,adversarial-review}.sh：各加 1 條條款存在性斷言（RED→GREEN，斷言 377 → 380）

## 驗證

- RED 確認 ×3 → GREEN 後 `tests/run.sh` 全綠
- **Live 驗證**：adversarial-review/mixed（原 matrix 失敗 combo）條款後 exit 0、4 heading hard 斷言全過 — 條款有效性實證
- binary combo 本輪被帳號 session limit 擋（skill 未執行、與本 fix 正交）— quota 重置後補跑
- Codex 跨模型 quick verify 排程中（429 quota 重置後）

## 誠實邊界

條款是 prompt-level 約束、遵循 probabilistic；上游 harness 的「`--print` 單輪 + 背景 job 生命週期」結構性風險不在本 repo scope（記於 diagnosis Residue）。
