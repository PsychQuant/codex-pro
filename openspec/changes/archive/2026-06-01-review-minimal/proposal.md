## Why

`codex-pro` 目前有 2 個落地 capability（setup、batch）+ tests。下一個對 user 使用率最高的命令是 `/codex-pro:review` — 對標 `openai/codex-plugin-cc` 的 `/codex:review`。

`codex-plugin-cc` 的 review 是其最常用 command 但同時集中暴露了 4 大痛點：subagent stub return (#324)、IPC pipe deadlock (#330)、無 circuit breaker on rate limit (#306)、findings cap hardcode 3 (#298)。

本 change `review-minimal` 落地 review skill v0.1：最小可運作版本，採 `codex-call` HTTPS direct（嚴守 Design constraint #1「No subprocess spawn for Codex」，與 batch 的 explicit exception 形成對比）、結果寫入 structured result file（消除 silent stub 痛點）、支援基本 review target 選擇（file / branch / current uncommitted）。

ensemble pattern（多 reviewer 角色平行）為 v0.2 留作 future change，本 change 為單 oracle review。

## What Changes

- 新增 `/codex-pro:review` skill：`plugins/codex-pro/skills/review/SKILL.md`
- 透過 `codex-call` HTTPS direct（parallel-ai-agents runtime dependency）執行 read-only review，無 subprocess（嚴守 Design constraint #1）
- Review target 三選一：current uncommitted diff / specific file path / branch comparison（例如 `--base main`）
- 收集 codex output 寫入 structured result file（路徑 `.codex-pro/review-<timestamp>.md`），不直接 echo 給 Claude 避免 silent stub failure（消除 #324 痛點）
- Findings 數量無 hardcode 上限（消除 #298 痛點）；report 結構：top-level summary + per-finding 含 file、line、severity、message、suggestion
- 失敗時 circuit breaker：rate limit / OAuth invalid → fail-fast、不 retry、明確錯誤訊息（消除 #306 痛點）
- 更新 CLAUDE.md Commands surface 表 `/codex-pro:review` 從「規劃中」改為「已落地」
- 更新 README.md Skills 表加 review 列
- 擴充 tests/：新 Layer 2 `tests/review.sh` 跑 review skill 結構性檢查（SKILL.md frontmatter、結果檔結構契約、circuit breaker fail-fast 紀律）；tests/run.sh dispatcher 加入 review.sh；tests/static.sh 加入 review SKILL.md frontmatter check

## Capabilities

### New Capabilities

- `review`: 提供 `/codex-pro:review` 命令對 code（file / branch / uncommitted diff）跑 read-only review。透過 `codex-call` HTTPS direct（無 subprocess、嚴守 Design constraint #1）、收集 findings 寫入 structured result file 於 `.codex-pro/review-<timestamp>.md`、findings 數量無上限、rate limit 走 circuit breaker fail-fast、無 silent stub return。本 change 為 v0.1 minimal — 單 oracle review、無 ensemble。

### Modified Capabilities

(none)

## Impact

- Affected specs:
  - New: openspec/specs/review/spec.md
- Affected code:
  - New:
    - plugins/codex-pro/skills/review/SKILL.md
    - tests/review.sh
  - Modified:
    - CLAUDE.md（Commands surface 表：review 從「規劃中」改「已落地」；Marketplace structure 段 skills 子目錄列加 review）
    - README.md（Skills 表新增 review 列、合併 review / adversarial-review 規劃描述為「review v0.1 已落地、adversarial-review 規劃中」）
    - tests/run.sh（dispatcher 加 review layer）
    - tests/static.sh（SKILL.md frontmatter parse loop 涵蓋 review）
  - Removed: (none)
- Runtime dependency: 沿用 `parallel-ai-agents` 的 `codex-call` Swift wrapper（既有依賴，無新增）
- Design constraints: 嚴守 #1（No subprocess spawn for Codex）— review 與 batch 對比，是 default rule 的最佳代表。其他 6 條 constraints（hard timeout、circuit breaker、structured result file、profile-based config、observability、macOS only）也適用本 skill。
- Output side effect: 寫入 `.codex-pro/` 目錄下時間戳記檔（首次跑時自動建立目錄）。**非 read-only**（與 setup 區別），但屬可預期 idempotent write（每次跑都產新檔、不覆蓋）。
