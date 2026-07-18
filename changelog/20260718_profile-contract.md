# 2026-07-18 — EXTERNAL-CONSUMER CONTRACT 官方化（v0.7.0）

## 摘要

首個外部 consumer（`issue-driven-dev`#264：IDD 刪 vendored codex-call、治理完全依賴 codex-pro）出現，依 pai#20 前例把治理層凍結為對外契約。

Issue: PsychQuant/codex-pro#7（已結案）｜Commit: `98c1b59`

## 變更

- 新 `references/profile-contract.md` — STABLE 契約：profile.yaml 兩層路徑 + per-field 優先序 + 欄位 schema + semver 規則；executable 明文排除（歸 pai，design D3）
- 新 `references/defaults.json` — 機器可讀 single source（`gpt-5.6-sol` / `xhigh` / `600`）；之後 model 換代只改此檔
- 5 個 skill prose 表加鏡像註記；resolver 讀檔化留 follow-up
- 0.6.2 → 0.7.0
