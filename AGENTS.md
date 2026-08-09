<!-- SPECTRA:START v1.0.2 -->

# Spectra Instructions

This project uses Spectra for Spec-Driven Development(SDD). Specs live in `openspec/specs/`, change proposals in `openspec/changes/`.

## Use `$spectra-*` skills when:

- A discussion needs structure before coding → `$spectra-discuss`
- User wants to plan, propose, or design a change → `$spectra-propose`
- Tasks are ready to implement → `$spectra-apply`
- There's an in-progress change to continue → `$spectra-ingest`
- User asks about specs or how something works → `$spectra-ask`
- Implementation is done → `$spectra-archive`
- Commit only files related to a specific change → `$spectra-commit`

## Workflow

discuss? → propose → apply ⇄ ingest → archive

- `discuss` is optional — skip if requirements are clear
- Requirements change mid-work? `ingest` → resume `apply`

## Parked Changes

Changes can be parked（暫存）— temporarily moved out of `openspec/changes/`. Parked changes won't appear in `spectra list` but can be found with `spectra list --parked`. To restore: `spectra unpark <name>`. The `$spectra-apply` and `$spectra-ingest` skills handle parked changes automatically.

<!-- SPECTRA:END -->

<!-- 以下內容在 SPECTRA 標記之外——標記內的區塊由 `spectra update` 重新生成，
     寫在裡面會被覆寫。 -->

# codex-pro Skills（Codex）

本 repo 的 skill 同時以兩種格式存在：

| 格式 | 路徑 | 叫用 |
|---|---|---|
| Claude Code plugin | `plugins/codex-pro/skills/<name>/SKILL.md` | `/codex-pro:<name>` |
| **Codex（本檔適用）** | `.codex/skills/<name>/SKILL.md` | `$<name>` |

`.codex/` 那份由 `scripts/generate-codex-skills.sh` 從 plugin 版**單向生成**，
漂移由 `tests/codex-skills-parity.sh` 擋下。**不要手改 `.codex/skills/` 下的檔案** ——
改來源後重跑生成腳本。

## 可用 skill

| Skill | 用途 |
|---|---|
| `$codex-setup` | 驗證 OAuth、codex-call runtime 是否就緒。**先跑這個** |
| `$codex-status` | 掃 `.codex-pro/*.md` 輸出結果摘要表（read-only、最輕量）|
| `$codex-result` | 顯示特定 result 檔（frontmatter + body verbatim）|
| `$codex-review` | 對 uncommitted diff / file / branch 跑 read-only review |
| `$codex-adversarial-review` | 對設計或 code 跑 hostile challenge（找盲點，非找 bug）|
| `$codex-rescue` | 把單一任務委派給 Codex |
| `$codex-batch` | 平行批次處理大型 reference doc |
| `$codex-config` | 顯示解析後的 profile（model / effort / max_time）|
| `$codex-cancel` | Informational only — 目前為 stateless single-shot |

## ⚠️ 執行前提

這些 skill 依賴 `bin/codex-call`，而該執行檔目前**經由 `parallel-ai-agents` 這個
Claude Code plugin 分發**。沒有安裝 Claude Code 的機器上不存在該檔案 —— skill
叫得出來，但執行會失敗。

獨立取得路徑尚未提供，追蹤於
[#9](https://github.com/PsychQuant/codex-pro/issues/9) 第 2 項與
[parallel-ai-agents#35](https://github.com/PsychQuant/parallel-ai-agents/issues/35)。
