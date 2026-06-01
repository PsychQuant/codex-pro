## Why

`codex-pro` v0.1 已有 setup / batch / review 三個 user-facing capability + tests meta-capability。下一個對齊 codex-plugin-cc 痛點地圖的 capability 是 `/codex-pro:rescue` — **把難題交給 Codex 處理**（task delegation）、與 review（read-only assessment）形成 mental model 對比。

`codex-plugin-cc` 的 `/codex:rescue` 是其最尷尬的痛點集中地：subagent stub return (#324) — Claude 看到 Codex 「貌似」回了結果但實際是 placeholder string、user 以為 task 完成、實際沒做。這是 silent failure 最危險形態。

本 change `rescue-minimal` 落地 rescue skill v0.1：採與 review 同 design pattern（codex-call HTTPS direct + structured result file + fail-fast 紀律），把「Codex 是否真的 process 了 task」變成 result file 可審計的硬契約。沿用 codex-pro Design constraint #1（No subprocess spawn）— rescue 與 review 同屬 default rule，與 batch exception 形成對照。

`--resume <session-id>` 與 `--fresh` flag 為 v0.1 必備（codex-plugin-cc rescue 的核心 UX、不可省）但實作走 minimal：v0.1 透過 codex-call 的 `--session` 與默認新 session 即可，不另建 session manager。

## What Changes

- 新增 `/codex-pro:rescue` skill：`plugins/codex-pro/skills/rescue/SKILL.md`
- 透過 `codex-call` HTTPS direct（parallel-ai-agents runtime dependency）執行 task delegation，**無 subprocess for Codex**（嚴守 Design constraint #1、沿用 review 紀律）
- Task delegation 結構：user 提供「task description + 可選 context file paths + 可選 completion criteria」、skill 包成 instructions 傳 codex-call
- 收集 codex output 寫入 structured result file（`.codex-pro/rescue-<ISO8601-timestamp>.md`），不直接 inline echo 給 Claude（**消除 #324 silent stub 痛點**）
- Result file 結構：YAML frontmatter + Body 含 `## Task Brief` + `## Outcome` + `## Suggested Next Steps` 三 section
- 失敗時 circuit breaker：rate limit / OAuth invalid / hard timeout 沿用 review 三類；新增第 4 類 `task_unclear`（task description 過於模糊、Codex 在 frontmatter `outcome: unclear` 回報）→ fail-fast、不 retry
- 支援 `--resume <session-id>` 與 `--fresh` flag（v0.1 minimal：rec resume 走 codex-call 的 session ID 傳遞、fresh 是預設、無 session manager 自建）
- 更新 CLAUDE.md Commands surface 表 `/codex-pro:rescue` 從「規劃中」改「已落地」
- 更新 README.md Skills 表加 rescue 列
- 擴充 tests/：新 Layer 2 `tests/rescue.sh`（跑 SKILL.md frontmatter、codex-call 主 invocation、`codex exec` 為 0、fail-fast 4 類、result file 結構契約、resume/fresh flag 文件化檢查）；tests/run.sh dispatcher 加 rescue layer；tests/static.sh 既有 per-skill namespace loop 自動 cover

## Capabilities

### New Capabilities

- `rescue`: 提供 `/codex-pro:rescue` 命令把 user 指定 task 交給 Codex 處理（task delegation）。透過 `codex-call` HTTPS direct（無 subprocess、嚴守 Design constraint #1）、收集 outcome 寫入 structured result file 於 `.codex-pro/rescue-<timestamp>.md`、result file 含 task brief + outcome + suggested next steps 三段、rate limit / OAuth invalid / timeout / task_unclear 四類走 circuit breaker fail-fast、無 silent stub return。支援 `--resume <session-id>` 接續 previous rescue thread、`--fresh` 開新 session。本 change 為 v0.1 minimal — 單 oracle delegation、無 ensemble。

### Modified Capabilities

(none)

## Impact

- Affected specs:
  - New: openspec/specs/rescue/spec.md
- Affected code:
  - New:
    - plugins/codex-pro/skills/rescue/SKILL.md
    - tests/rescue.sh
  - Modified:
    - CLAUDE.md（Commands surface 表 rescue 從規劃中→已落地；Marketplace structure 段 skills 子目錄列加 rescue）
    - README.md（Skills 表加 rescue 列）
    - tests/run.sh（dispatcher 加 review layer 後加 rescue layer）
    - tests/static.sh（既有 per-skill namespace loop 自動 cover rescue、無需改 loop logic；但要驗 rescue 三個 namespace 位置都 pass）
  - Removed: (none)
- Runtime dependency: 沿用 `parallel-ai-agents` 的 `codex-call` Swift wrapper（既有依賴，無新增）
- Design constraints: 嚴守 #1（No subprocess spawn for Codex）— rescue 與 review 同屬 default rule 範例。其他 6 條 constraints 也適用本 skill。
- Output side effect: 寫入 `.codex-pro/` 目錄下時間戳記檔（首次跑時自動建立目錄）。**非 read-only**、與 review 同屬 mutating-write skill 但與 batch（產生 shell script + spawn subprocess）有別。
