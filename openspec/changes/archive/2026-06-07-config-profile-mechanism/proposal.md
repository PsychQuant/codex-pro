## Why

codex-pro Design constraint #5 (「Profile-based config — `max-findings` / `sandbox` mode / `model` alias / `focus` 全部可在 profile 配置」) 自 v0.1 起明列、但至 v0.4.x 為止仍是 **vapor promise**：每個 producer skill 都 hardcode `gpt-5.5` / `xhigh` / `--max-time 600`、user 沒辦法不改 SKILL.md 就調整。Workflow synthesis (wqfvs53aw) 把 config 排到 candidate #3、定性為「pure downstream、feature-foundational」、且未來 review-v2-ensemble (#5) 與 token-cost-tier-observability (#4) 兩者都隱含假設「profile 機制已存在」— 沒先做 config 就硬做這兩個會各自 invent ad-hoc config plumbing。

User 場景：

- 我這台機器 Codex tier 限額不夠、想 review/rescue/adversarial-review 都改用 `gpt-5.0` 而非 `gpt-5.5` — 沒辦法、要去 SKILL.md 三處改
- 這個 repo 我希望 review 都 `--max-time 1200`（2x default）— 沒辦法
- 我希望 adversarial-review 預設 `--focus security`（這個 repo 是 auth library） — 沒辦法

本 change 引入 **profile-based config mechanism** + 新 `/codex-pro:config` read-only consumer skill：

1. Profile file 兩 layer：`~/.codex-pro/profile.yaml`（global）+ `<project>/.codex-pro/profile.yaml`（per-project，priority 較高）
2. Schema v0.1（4 fields）：`model` / `effort` / `max_time` / `focus_default`
3. Producer skills（review / rescue / adversarial-review）Step 4 改為 **read profile + fall back to hardcoded default if field missing**：existing user（沒 profile）零行為改變、setting profile 的 user 全 producer 一致使用 profile value
4. New `/codex-pro:config` skill 屬 read-only consumer category：display resolved profile（global merged with project）+ 標示每個 field 來源（global / project / hardcoded default）；不寫任何 file、不 codex-call、stdout-only
5. batch skill **不**動：sandbox / model 等 batch-specific 配置與 producer 不同性質、留 future cycle 單獨評估

Plugin bump 0.4.0 → 0.5.0（新 skill + 行為變化）。三 producer 同時升 minor：review v0.2 → v0.3、rescue v0.1.1 → v0.2、adversarial-review v0.2 → v0.3。

## What Changes

- 新增 `/codex-pro:config` skill：`plugins/codex-pro/skills/config/SKILL.md`
  - Read-only consumer category（與 setup / status / result / cancel 同類）
  - Zero-argument invocation（接 argument 也只是 ignore + 印 usage）
  - Profile resolution algorithm：
    1. Load `~/.codex-pro/profile.yaml`（若存在）→ global layer
    2. Load `<project>/.codex-pro/profile.yaml`（若存在；project = cwd）→ project layer
    3. Project layer override global layer per-field
    4. Missing field → hardcoded default（model: `gpt-5.5`、effort: `xhigh`、max_time: `600`、focus_default: `""`）
  - Output: markdown table 列每個 field（filename column 顯示 source path 或 `(default)`）
  - No file mutation、no codex-call、no subprocess for Codex — read-only invariants
- 修改 review v0.2 → v0.3 SKILL.md Step 4：codex-call invocation 改為從 profile resolve `--model` / `--effort` / `--max-time` value；missing field → hardcoded default；result file frontmatter 加 `profile_source` field（e.g. `project` / `global` / `default`、per-field 或 aggregate）
- 修改 rescue v0.1.1 → v0.2 SKILL.md Step 4：同 review 模式
- 修改 adversarial-review v0.2 → v0.3 SKILL.md Step 4：同 + 加 `focus_default` profile field（user 無 `--focus <area>` arg 時改用 profile `focus_default`、profile 也無 → 沿用 v0.2 `(no focus area supplied)` placeholder）
- 修改 3 producer spec（review / rescue / adversarial-review）：MODIFIED Step 4 invocation requirement、加 profile-resolution scenario；frontmatter requirement 加 `profile_source` field（optional、不出現於 v0.x 舊 result file）
- 新增 `tests/config.sh` Layer 2：structural（frontmatter / read-only invariants / no codex interaction）+ behavioral runtime（mktemp + fake `~/.codex-pro/` + fake project `.codex-pro/profile.yaml` × multiple combination 驗 resolution）
- 修改 `tests/review.sh` + `tests/rescue.sh` + `tests/adversarial-review.sh`：加 v0.3 / v0.2 marker check + profile resolution behavioral scenario（mock profile.yaml + verify resolved invocation includes correct flag value）
- 修改 `tests/run.sh`：加 `run_layer config`
- 修改 `tests/e2e.sh` + `tests/lib/e2e-fixtures.sh`：加 1 new scenario `with-profile`（fake project profile sets `max_time: 900`、e2e verify Codex invocation reflects profile）— v0.1 minimal、其他 4 scenario 不動
- 更新 CLAUDE.md Commands surface 表：加 `/codex-pro:config` row、3 producer skill rows update version；Read-only consumer category 表加 config row
- 更新 README.md What it replaces 表（無 upstream `/codex:config` row、本 row 顯式標 「codex-pro 自有 capability、不對標 codex-plugin-cc」）+ Skills table 加 config row + 3 producer version update
- 更新 plugin.json 0.4.0 → 0.5.0、description / keywords 反映 profile mechanism
- 不改 setup / status / result / cancel / batch（4 category 中 batch 留 future cycle、其他 4 read-only skill 與 profile 無交集）
- 不改 fail-fast 4 class 結構、不改 result file H2 section 結構

## Non-Goals

- 不改 batch skill（sandbox / model 等 batch-specific 配置與 producer 性質不同、留 future cycle）
- 不引入 `max_findings` config field（Constraint #5 列出此 field、但會 conflict review v0.1 spec 「findings_count with no upper bound」承諾、scope 大、留 v0.2 評估）
- 不引入 retry/backoff config（fail-fast circuit-breaker 紀律是 architectural invariant、不該 user-tunable）
- 不引入 timeout-per-skill override（global `max_time` 即可、per-skill 增 schema 複雜度無 v0.1 必要）
- 不引入 profile schema version（v0.1 隱式 v1、未來改 schema 再加 `version:` field）
- 不引入 profile validation skill（schema 驗證可 inline 在 `/codex-pro:config` 內、不需獨立 skill）
- 不引入 profile inheritance（如 base profile + override）— 兩 layer (global + project) 已足
- 不引入 environment variable override（如 `CODEX_PRO_MODEL=gpt-5.0`）— v0.1 minimal
- 不引入 multi-profile（如 named profiles `dev` / `prod`）— v0.1 minimal
- 不寫 profile schema 為 JSON Schema spec（用 prose 描述 + python3 inline parse、與 codex-pro 其他 YAML 處理一致）
- 不引入 profile encryption / secret store（profile 不含 secrets、只含 config 值）
- 不對 setup skill 加 profile-check step（setup 是純環境檢查、profile resolution 屬 producer 跑時 lazy）
- 不寫 GUI / interactive profile edit（user 用文字編輯器改 YAML、CLI 顯示 only）

## Capabilities

### New Capabilities

- `config`: 提供 `/codex-pro:config` 命令 display resolved profile（global `~/.codex-pro/profile.yaml` merged with project `<project>/.codex-pro/profile.yaml`）。Read-only consumer category — 純檔案讀取、無 codex-call、無 file mutation、stdout-only markdown table。Schema v0.1（4 fields）：`model` / `effort` / `max_time` / `focus_default`。Missing field falls back to hardcoded default（gpt-5.5 / xhigh / 600 / 空字串）。Output table 標示每 field 來源（global / project / default）。

### Modified Capabilities

- `review`: Step 4 codex-call invocation 改為 profile-aware — `--model` / `--effort` / `--max-time` value 從 profile resolve、missing field 沿用 hardcoded default。Result file frontmatter 加 optional `profile_source` field（per-field 或 aggregate）。Version bump v0.2 → v0.3（minor、user-visible behavior change for profile-setters）。
- `rescue`: 同 review pattern — Step 4 profile-aware、frontmatter 加 `profile_source`。Version bump v0.1.1 → v0.2（minor）。
- `adversarial-review`: Step 4 profile-aware 同 + 加 `focus_default` field：user 無 `--focus <area>` arg 時改用 profile `focus_default`、profile 也無 → 沿用 v0.2 `(no focus area supplied)` placeholder。Version bump v0.2 → v0.3（minor）。

## Impact

- Affected specs:
  - New:
    - openspec/specs/config/spec.md
  - Modified:
    - openspec/specs/review/spec.md（Step 4 invocation requirement + frontmatter requirement）
    - openspec/specs/rescue/spec.md（Step 4）
    - openspec/specs/adversarial-review/spec.md（Step 4 + focus resolution）
- Affected code:
  - New:
    - plugins/codex-pro/skills/config/SKILL.md
    - tests/config.sh（Layer 2 structural + behavioral）
  - Modified:
    - plugins/codex-pro/skills/review/SKILL.md（Step 4 profile read + frontmatter）
    - plugins/codex-pro/skills/rescue/SKILL.md（Step 4 profile read + frontmatter）
    - plugins/codex-pro/skills/adversarial-review/SKILL.md（Step 4 profile read + focus_default + frontmatter）
    - tests/review.sh（v0.3 marker + profile behavioral scenario）
    - tests/rescue.sh（v0.2 marker + profile behavioral scenario）
    - tests/adversarial-review.sh（v0.3 marker + profile + focus_default behavioral scenario）
    - tests/run.sh（dispatcher 加 `run_layer config`）
    - tests/e2e.sh + tests/lib/e2e-fixtures.sh（加 `with-profile` 新 scenario）
    - CLAUDE.md（Commands surface 表加 config row + 3 producer row version update、Read-only consumer category 表加 config row、Constraint #5 從「vapor」改「v0.5 ship」備註）
    - README.md（Skills table 加 config row + 3 producer row version update、Read-only vs producer 段 mention config）
    - plugins/codex-pro/.claude-plugin/plugin.json（0.4.0 → 0.5.0、description / keywords）
  - Removed: (none)
- Test net delta: 293 Layer 1+2 → ~370（+~75：config.sh ~25 + 3 producer +~10 each + e2e with-profile scenario auto-cover via static.sh per-skill loop ~10）
- Layer 3 e2e net delta: 10 combinations → 12 combinations（5 scenario + with-profile = 6 scenario × 2 producer skill；config skill 不在 e2e scope、v0.1 minimal）
- Quota budget impact (Layer 3): +20% per full pass（12 vs 10 combinations）
- Cross-repo impact: none（純 codex-pro repo 內、不動 parallel-ai-agents）
- Runtime dependency: 無新增；用既有 `python3` YAML parse + Bash file IO
- Plugin bump: 0.4.0 → 0.5.0（minor、new skill + behavior change for profile-setters）
- Cross-cycle discipline impact:
  - 3 producer skill change：MANDATORY pre-archive smoke gate（per [[feedback-codex-pro-smoke-before-archive]]）— 至少跑 1 real codex-call per producer 在 profile-set fixture 上、verify profile value 透 codex-call invocation
  - Layer 3 e2e `with-profile` scenario 為 v0.1 minimal validation；不取代 smoke
- Backward compatibility: 100% — user 沒 profile 時 producer 跑與 v0.4 identical；setting profile 為 opt-in
- Forward compatibility note: result file frontmatter `profile_source` field 為 v0.5 新增 optional field、v0.4 result file 沒此 field 屬 valid frontmatter；下游 `/codex-pro:status` / `/codex-pro:result` 需容忍 missing `profile_source`（不 break for v0.4 result file 讀取）
- Estimated size: **single-cycle but substantial** — 1 new SKILL + 3 producer SKILL.md modification + 4 spec change + 5 test file modification + 4 doc update + plugin bump；比 diff-untracked-fix（2 producer）大、與 status-result-cancel triple skill set 同量級
