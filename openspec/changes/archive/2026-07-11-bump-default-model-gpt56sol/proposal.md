## Why

上游 GPT lineup 大改版後，codex-pro 全套 skill 的 hardcoded model default（`gpt-5.5`）落後一個世代。實測（2026-07-10，PsychQuant/codex-pro#3）確認：codex-call 所走的 ChatGPT-account backend-api 路徑上，`gpt-5.6` 與 `gpt-5.3-codex` 皆被 HTTP 400 拒絕，5.6 世代**僅 `gpt-5.6-sol` 可用**（且接受 `--effort xhigh`）；`gpt-5.5` 仍可用，但依上游 deprecation policy（GA ≥6 個月、specialized variants ≥3 個月通知）存在退役風險 — 一旦退役，3 個 producer skills + batch 對未設 profile 的使用者整批故障（P0）。

## What Changes

- 3 個 producer skills（review / rescue / adversarial-review）SKILL.md 內嵌 resolver 的 `DEFAULTS["model"]`：`gpt-5.5` → `gpt-5.6-sol`，含 frontmatter 版本說明、Step 說明、result-file 範例同步
- `codex-config` SKILL.md：schema default 表、resolved-profile 範例輸出、profile.yaml 範例同步
- `codex-batch` SKILL.md 的 default model 記載 + `references/script-template.sh` 的 `__MODEL__` 範例值（同步 `tests/static.sh` 的 template sha256 hardcoded invariant）
- 3 個 test 檔的 default 斷言 / fixture：`tests/config.sh`、`tests/adversarial-review.sh`、`tests/status.sh`（`tests/rescue.sh` 無 `gpt-5.5` 佔用，僅作回歸驗證），加上 `tests/static.sh` 的 template sha256 invariant 重算
- 5 個 active specs（review / rescue / adversarial-review / config / batch）的 normative default 記載
- `README.md` / `CLAUDE.md` 的 default 記載
- Per-ship smoke gate：真 codex-call 驗證 `gpt-5.6-sol` 下 heading contract（`## Summary` / `## Findings` literal tokens、adversarial 4-H2）不漂移
- 已設 profile 的使用者行為不變（profile override 語意不動，100% backward compatible）

## Non-Goals

- **不加 profile escalation 欄位**（issue #3 裁決收攤：default 已是此路徑頂級可用 model，escalation 目標不存在；未來 lineup 真有多階再開新 issue）
- **不動 `effort`（`xhigh`）與 `max_time`（600）default**（實測 `xhigh` 被 `gpt-5.6-sol` 接受，無變更需要）
- **不動 `openspec/changes/archive/` 內任何歷史記載**（審計軌跡）
- **不處理 cross-repo sister issues**（PsychQuant/psychquant-claude-plugins#105 的 codex-call binary default、PsychQuant/issue-driven-development#251 的 idd-verify/idd-route hardcode — 各自走各自 repo 的流程）
- **不改 codex-call binary 本身**（codex-pro 是 consumer，一律顯式傳 `--model`）
- **拒絕的替代方案**：(a) default 改 `gpt-5.6` — 實測 400 不可行；(b) 維持 `gpt-5.5` + escalation 欄位 — deprecation 風險僅延後、escalation 目標不存在

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `review`: profile 未設時的 model default 由 `gpt-5.5` 改為 `gpt-5.6-sol`
- `rescue`: 同上
- `adversarial-review`: 同上
- `config`: schema v0.1 的 `model` field default 記載由 `gpt-5.5` 改為 `gpt-5.6-sol`
- `batch`: 互動蒐集階段的 model default 記載由 `gpt-5.5` 改為 `gpt-5.6-sol`

## Impact

- Affected specs: `review`、`rescue`、`adversarial-review`、`config`、`batch`（皆 modified，無新 capability）
- Affected code:
  - Modified:
    - plugins/codex-pro/skills/codex-review/SKILL.md
    - plugins/codex-pro/skills/codex-rescue/SKILL.md
    - plugins/codex-pro/skills/codex-adversarial-review/SKILL.md
    - plugins/codex-pro/skills/codex-config/SKILL.md
    - plugins/codex-pro/skills/codex-batch/SKILL.md
    - plugins/codex-pro/skills/codex-batch/references/script-template.sh
    - tests/static.sh
    - tests/batch.sh
    - tests/config.sh
    - tests/adversarial-review.sh
    - tests/status.sh
    - README.md
    - CLAUDE.md
  - New: (none)
  - Removed: (none)
- 協調注意：未歸檔 change `harden-producer-heading-reliability` 的 spec delta 內含 `gpt-5.5` 字樣；本 change 不觸碰該 delta，若該 change 先 archive 則其合入 spec 的內容由本 change 的 delta 覆蓋順序處理（後 archive 者以當時 spec 現狀為基準重驗）
