## Why

`codex-pro` v0.1 has 5 capabilities live (setup / batch / tests / review / rescue), with 7 archive cycles + a pending `fix-rescue-session-flags` bug fix in propose pipeline. `/codex-pro:adversarial-review` is the next user-facing capability — the third member of the review-family alongside review (assessment) and the future ensemble v2 (multi-reviewer consensus).

Selected as next propose by an ultracode multi-agent workflow (4 design briefs + 8 adversarial skeptics + 1 synthesis, 13 agents / 916k tokens). The workflow ranked 4 candidates:
- #1 adversarial-review — single codex-call, no subprocess, low risk, spec-amendable skeptic objections (this change)
- #2 status-result-cancel — blocked on producer frontmatter schema not yet dogfooded
- #3 review-v2-ensemble — blocked on `codex-call --session` missing upstream
- #4 jobs-status — refuted on Constraint #1 violation + observability lie (SIGTERM on local PID does not cancel chatgpt.com upstream)

Mental model: **assessment vs challenge**. review reports findings ("here is what I found"); adversarial-review pressure-tests assumptions and proposes alternatives ("here is what could go wrong / what you missed"). The two skills share single-oracle codex-call infrastructure but differ in system prompt and result file body sections.

Upstream codex-plugin-cc has `/codex:adversarial-review` (痛點 #333 focus-text re-tokenization bug). codex-pro adversarial-review v0.1 mitigates by passing `--focus` text via fenced delimiter + length cap (≤200 chars), preventing the prompt-injection pattern that breaks upstream.

Two corrections baked in from the workflow's adversarial verification:
1. **fail-fast classes match review template count (4) including `oauth_invalid`** — the design brief originally dropped oauth_invalid which would cause unclassified HTTP 401 errors when `~/.codex/auth.json` is expired. Restoring it aligns with the codex-pro fail-fast template (review has 3, rescue has 4 = review + task_unclear, adversarial-review has 4 = review's 3 + target_invalid pre-flight class).
2. **section non-empty requirement instead of misleading "uncapped findings" claim** — the original brief mirror-claimed review's #298 uncapped-findings fix, but adversarial-review's output is 4 fixed section headings (not repeating Finding N items), so "uncapped" is a category error. Spec instead requires each of the 4 sections to be non-empty (the Codex output cannot return a single empty section as a stub).

## What Changes

- 新增 `/codex-pro:adversarial-review` skill：`plugins/codex-pro/skills/adversarial-review/SKILL.md`
- 透過 `codex-call` HTTPS direct（parallel-ai-agents runtime dependency）執行 read-only adversarial review，無 subprocess（嚴守 Design constraint #1 default rule，與 batch exception 對比；與 review + rescue 同模板）
- Review target 三選一：current uncommitted diff / specific file path / branch comparison (`--base <ref>`) — 與 review 對齊
- 新增 `--focus <area>` flag：可指定壓力測試焦點（如 `security` / `perf` / `design` / `data-loss` / `race-conditions`），text 經 200-char cap + fenced delimiter wrap 後注入 instructions（防 #333 prompt-injection）
- 新增 `--depth shallow|deep` flag：shallow = 表層 challenge、deep = 深度反駁含 alternatives；預設 deep
- 結果寫入 structured result file（`.codex-pro/adversarial-review-<ISO8601-timestamp>.md`），不直接 echo
- Result file 結構：YAML frontmatter (7 fields) + body 4 H2 sections：`## Assumptions Challenged` / `## Failure Modes` / `## Alternative Approaches` / `## Trade-off Counterarguments`，每節必須 non-empty
- 失敗 4 類 fail-fast：`rate_limit` / `oauth_invalid` / `timeout`（沿用 review）+ `target_invalid`（adversarial-review 特有 pre-flight class，覆蓋 target 無法解析 / 不可讀 / zero-byte / whitespace-only）
- 更新 CLAUDE.md Commands surface 表 `/codex-pro:adversarial-review` 從「規劃中」改「已落地」
- 更新 README.md Skills 表加 adversarial-review 列、加 review vs adversarial-review decision table（解 Risk #1 mental-model overlap）
- 擴充 tests/：新 Layer 2 `tests/adversarial-review.sh`（~30 assertions：SKILL.md frontmatter、codex-call invocation、`codex exec = 0`、`--max-time 600`、4 fail-fast classes、4 body section markers、--focus + --depth 與 200-char cap、focus-injection mitigation prose）；tests/run.sh dispatcher 加 adversarial-review layer

## Capabilities

### New Capabilities

- `adversarial-review`: 提供 `/codex-pro:adversarial-review` 命令對 code（file / branch / uncommitted diff）跑 single-oracle hostile reviewer pass。透過 `codex-call` HTTPS direct（無 subprocess、嚴守 Design constraint #1）、收集 challenges 寫入 structured result file 於 `.codex-pro/adversarial-review-<timestamp>.md`、body 4 H2 sections 每段 non-empty、rate_limit / oauth_invalid / timeout / target_invalid 四類走 circuit breaker fail-fast、`--focus <area>` flag 經 200-char cap + delimiter wrap 防 prompt-injection（解 upstream #333）。本 change 為 v0.1 minimal — 單 oracle adversarial pass、無 ensemble panel。

### Modified Capabilities

(none)

## Impact

- Affected specs:
  - New: openspec/specs/adversarial-review/spec.md
- Affected code:
  - New:
    - plugins/codex-pro/skills/adversarial-review/SKILL.md
    - tests/adversarial-review.sh
  - Modified:
    - CLAUDE.md（Commands surface 表 adversarial-review 從規劃中→已落地；Marketplace structure 段 skills 子目錄列表加 adversarial-review；新增 review vs adversarial-review decision table 段）
    - README.md（Skills 表新增 adversarial-review 列；review/adversarial-review 區別說明）
    - tests/run.sh（dispatcher 加 adversarial-review layer）
  - Removed: (none)
- Runtime dependency: 沿用 `parallel-ai-agents` 的 `codex-call` Swift wrapper（既有依賴，無新增）
- Design constraints: 嚴守 #1（No subprocess spawn for Codex）— adversarial-review 與 review / rescue 同屬 default rule，與 batch exception 形成 3:1 default vs exception 對比。其他 6 條 constraints 也適用本 skill。
- Output side effect: 寫入 `.codex-pro/` 目錄下時間戳記檔（首次跑時自動建立目錄）。**非 read-only**、與 review / rescue 同屬 mutating-write skill。
- Test net delta: 115 → ~145 assertions（adversarial-review.sh ~30 + tests/static.sh auto-cover 7-8 個 namespace + frontmatter loops）。
- Cross-repo impact: none（不動 parallel-ai-agents、不動 PsychQuant org 其他 repo）。
- Mental-model risk mitigated: 新增 review vs adversarial-review decision table 於 CLAUDE.md + README.md，明示「review = 你不知道 code 哪裡有問題 → 我幫你找；adversarial-review = 你有 design plan、想被攻擊 → 我幫你壓測」。
