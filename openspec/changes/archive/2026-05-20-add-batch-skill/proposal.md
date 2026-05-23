## Why

`codex-pro` 已 stable 為 marketplace 殼 + 同名 single plugin（內含 `setup` 一個 skill）。使用者要把 `/Users/che/Developer/` 底下「呼叫 codex」的 plugin 集中到 codex-pro，避免散落 psychquant-claude-plugins 各處。

Phase 1 探索後候選收斂到三個（codex-batch / parallel-ai-agents / lean-prover/codex-prove-assist），user 已決定處置方式 — 此 change 範圍僅 **codex-batch 的單一遷移**。

`codex-batch` plugin（位於 psychquant-claude-plugins）的 commands/codex-batch.md 是「跑 codex exec --full-auto 平行批次處理大型 reference doc 多個 chunk」的 slash command（典型 use case：textbook 各章節獨立 codex 解題、各章翻譯、各 section summary）。將它搬入 codex-pro 作為 `batch` skill 後：

- 命令 `/codex-pro:batch` 與既有 `/codex-pro:setup` 同 namespace，user 一處看齊
- 原 codex-batch plugin 刪除避免雙源飄移

## What Changes

- 新增 codex-pro 內 `batch` skill：`plugins/codex-pro/skills/batch/SKILL.md` 承載原 codex-batch slash command 的指令邏輯，frontmatter 設 `name: batch`、`description` 沿用、`allowed-tools` 沿用、`argument-hint` 沿用；trigger 段微改提及 `/codex-pro:batch`
- 新增 `plugins/codex-pro/skills/batch/references/script-template.sh`：byte-identical 從 source 搬
- **刪除**整個 psychquant-claude-plugins 內的 codex-batch plugin（含 .claude-plugin/、commands/、references/、CHANGELOG.md）；同步將該 marketplace 的 marketplace.json 內 codex-batch entry 移除（若有列）
- 更新 codex-pro 的 CLAUDE.md：Commands surface 表加 `/codex-pro:batch` 列
- 更新 codex-pro 的 README.md：Skills 表加 `batch` 列

## Capabilities

### New Capabilities

- `batch`: 提供 `/codex-pro:batch` 命令，使用 `codex exec --full-auto` 平行批次處理大型 reference doc 的多個 chunk。Skill 收集 user 參數（reference file、chunks、prompt template、output dir、model、reasoning effort），產生 shell script、parallel execute、monitor progress。

### Modified Capabilities

(none)

## Impact

- Affected specs:
  - New: openspec/specs/batch/spec.md
- Affected code:
  - New:
    - plugins/codex-pro/skills/batch/SKILL.md
    - plugins/codex-pro/skills/batch/references/script-template.sh
  - Modified:
    - CLAUDE.md（Commands surface 表加 `/codex-pro:batch`）
    - README.md（Skills 表加 batch）
  - Removed（外部 repo）:
    - psychquant-claude-plugins 內整個 codex-batch plugin（含其 .claude-plugin/、commands/、references/、CHANGELOG.md；以及 marketplace 的 marketplace.json 內對應 entry）
- Design constraints exception:
  - codex-pro 既有 Design constraint #1（No subprocess spawn for Codex）對 batch 為 **explicit exception** — batch 的 fan-out parallel job orchestration 本質需要 shell-level subprocess 控制（用 `&` parallel job、shell-level monitor）；其他 skill（setup、未來 review/rescue 等）仍嚴守 HTTPS direct。Design.md 將記載此 exception 的範圍與理由。
- Out of scope（不動）:
  - psychquant-codex-plugins 內的 codex-batch plugin（Codex CLI 端 marketplace、不同生態系）
  - parallel-ai-agents 整個 plugin（codex-pro 的 runtime dependency、不搬）
  - lean-prover 內的 codex-prove-assist skill（屬 lean-prover 的 Lean theorem proving capability、不搬）
