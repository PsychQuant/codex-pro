# 2026-07-12 — Default model bump：gpt-5.5 → gpt-5.6-sol（v0.6.0）

## 摘要

上游 GPT 改版後，codex-pro 全套 default model 從 `gpt-5.5` 換至 `gpt-5.6-sol`，plugin 版本 0.5.1 → 0.6.0。實測依據（2026-07-10/12）：codex-call（ChatGPT-account backend-api）路徑上 5.6 世代**僅** `gpt-5.6-sol` 可用（`gpt-5.6` / `gpt-5.3-codex` 皆 HTTP 400）；`codex exec` 路徑需 codex CLI ≥ 0.144。

Issue: PsychQuant/codex-pro#3（已關閉）｜Spectra change: `bump-default-model-gpt56sol`（archived 2026-07-11）｜Commits: `3e190fb`、`ea5f6a8`

## 變更

- **3 個 producer skills**（codex-review / codex-rescue / codex-adversarial-review）：SKILL.md 內嵌 resolver `DEFAULTS["model"]` → `gpt-5.6-sol`；backward-compat 承諾限縮為「已設 profile 者不受影響」（未設 profile 者採用新 default）
- **codex-config**：schema default 表、範例輸出、profile.yaml 範例同步；out-of-scope 註記補 model-escalation 欄位收攤決策
- **codex-batch**：SKILL.md default + `references/script-template.sh` 範例值；troubleshooting 補「`gpt-5.6-sol` 需 codex CLI ≥ 0.144」版本需求（實測 0.142.3 → 400、0.144.1 通過）
- **Tests**：`config.sh` / `adversarial-review.sh` / `status.sh` 斷言與 fixture 同步（RED→GREEN）；`static.sh` 與 `batch.sh` 兩份獨立 template sha256 invariant 重算
- **Specs**：5 個 active openspec specs（review / rescue / adversarial-review / config / batch）normative default 記載更新；5 檔補回檔尾 newline
- **In-flight change 協調**：`harden-producer-heading-reliability` 的 review spec delta 同步 rebase 為 `gpt-5.6-sol`（消滅 archive 時 landing-order 回退 trap）
- **Docs**：README.md / CLAUDE.md 的 default 記載同步
- **版本**：plugin.json 0.5.1 → 0.6.0；marketplace.json 補 version 欄位並同步

## 不變

- `effort: xhigh`、`max_time: 600`（實測 sol 接受，無變更需要）
- Profile override 機制與語意（已設 profile 的使用者行為完全不變）
- `openspec/changes/archive/**` 歷史記載

## 驗證

- `tests/run.sh` 370/370 assertions、10 layers 全綠
- 6-AI ensemble verify（pai-ensemble 2.18.0：4 lens + Devil's Advocate + Codex 跨模型）Aggregate PASS，21 raw findings 全數修復/分流
- Per-ship smoke ×4：3 producer 真 codex-call（heading contract 零漂移）+ 1 次 `codex exec` 路徑 probe
- Tags：`idd-3-baseline`（開案 anchor）、`idd-3-verified`（驗證 snapshot）

## Follow-ups

- #4 review/rescue resolver 缺 no-profile default behavioral 斷言
- #5 specs trace 註解殘留舊 no-prefix skill 路徑
- Cross-repo：PsychQuant/psychquant-claude-plugins#105、PsychQuant/issue-driven-development#251
