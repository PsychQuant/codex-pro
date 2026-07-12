<!-- SPECTRA:START v1.0.2 -->

# Spectra Instructions

This project uses Spectra for Spec-Driven Development(SDD). Specs live in `openspec/specs/`, change proposals in `openspec/changes/`.

## Use `/spectra-*` skills when:

- A discussion needs structure before coding → `/spectra-discuss`
- User wants to plan, propose, or design a change → `/spectra-propose`
- Tasks are ready to implement → `/spectra-apply`
- There's an in-progress change to continue → `/spectra-ingest`
- User asks about specs or how something works → `/spectra-ask`
- Implementation is done → `/spectra-archive`
- Commit only files related to a specific change → `/spectra-commit`

## Workflow

discuss? → propose → apply ⇄ ingest → archive

- `discuss` is optional — skip if requirements are clear
- Requirements change mid-work? Plan mode → `ingest` → resume `apply`

## Parked Changes

Changes can be parked（暫存）— temporarily moved out of `openspec/changes/`. Parked changes won't appear in `spectra list` but can be found with `spectra list --parked`. To restore: `spectra unpark <name>`. The `/spectra-apply` and `/spectra-ingest` skills handle parked changes automatically.

<!-- SPECTRA:END -->

---

# codex-pro — Claude Code Marketplace（進階版）

## Purpose

對 [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc) 的進階重寫。
原 plugin 有 200+ open issues，系統性痛點集中在四類：

- **Delegate silent fail** — subagent 回 stub、large prompt 被 silently rejected、IPC pipe deadlock（#324、#308、#330）
- **無 circuit breaker** — rate limit 後無限 retry，吃光 Claude token（#306）
- **Hardcode 不可配置** — max-findings 寫死 3、sandbox 寫死 workspace-write（#298、#304）
- **零 observability** — token / cost / quota / tier 完全不可見

`codex-pro` 用 ensemble pattern + 自家 Swift HTTPS runtime 從架構層解決這些問題，對外維持 drop-in 相容的 command 介面。**codex-pro 是一個 Claude Code marketplace 殼，底下永遠只有一個與之同名的 plugin `codex-pro`，所有 capability 都當作此 plugin 的 skill 並存於 `plugins/codex-pro/skills/` 內**。

## What this marketplace is NOT

- **不是 codex-plugin-cc 的 fork / patch** — 是 architectural redesign，code 完全不共享
- **不是 multi-plugin marketplace** — marketplace 殼仍在以保留發布結構，但 single-vendor / single-product 設計下底下只有一個 plugin（與 marketplace 同名為 `codex-pro`）；未來所有 capability 直接加為此 plugin 的 skill
- **不是 parallel-ai-agents 的子集** — 它呼叫 `parallel-ai-agents/bin/codex-call`，但 ensemble logic、command surface、circuit breaker 都獨立
- **不是 OpenAI 官方** — 與 `openai/codex-plugin-cc` 無關，是自家對標版本

## 核心設計差異 vs openai/codex-plugin-cc

| 面向 | codex-plugin-cc | codex-pro |
|------|----------------|-----------|
| Plugin organization | single plugin（root `.claude-plugin/plugin.json`） | marketplace 殼 + 同名 single plugin（多 skill 並存） |
| Delegate pattern | 1-on-1 single-shot（Claude → Codex） | N-on-N ensemble（4 Claude teammates + N Codex 角色） |
| Codex 呼叫 | `spawn('codex', ['exec', ...])` + JSONL pipe | Swift `codex-call` 直連 `chatgpt.com/backend-api`，無 subprocess |
| Hang / timeout | IPC pipe 易 deadlock（#330） | `URLSession + DispatchSemaphore` hard timeout |
| Silent failure | subagent 回 stub（#324）、rate limit 無限 retry（#306） | 強制 structured result file；rate limit 鎖 session（circuit breaker） |
| Observability | 看不到 cost / quota / tier | 每 session 顯示 token usage、Codex tier、quota 預警 |
| Configurability | max-findings、sandbox、model alias hardcode | Profile-based 全可配置 |
| Steerable | adversarial-review focus text 有 bug（#333） | Ensemble 每角色 prompt 獨立、focus 可指定 |
| 平台 | 號稱 cross-platform，Windows 一堆 bug | 初期 macOS only，不背 Windows IPC 包袱 |

## Marketplace structure

```
codex-pro/                                ← marketplace root（自身為 catalog）
├── .claude-plugin/
│   └── marketplace.json                  ← catalog manifest（plugins[] 永遠只列一個 codex-pro plugin）
├── plugins/
│   └── codex-pro/                        ← 唯一 plugin，與 marketplace 同名
│       ├── .claude-plugin/plugin.json    ← name: codex-pro
│       └── skills/
│           ├── codex-setup/SKILL.md            ← 已落地：/codex-pro:codex-setup（read-only 環境檢查）
│           ├── codex-batch/SKILL.md            ← 已落地：/codex-pro:codex-batch（codex exec 平行批次；Design constraint #1 的 explicit exception）
│           ├── codex-review/SKILL.md           ← 已落地：/codex-pro:codex-review v0.4（codex-call HTTPS direct、Design constraint #1 default rule；v0.2 untracked-by-default + binary path-only + 64KB/512KB size cap + pre-first-commit fallback + target_invalid post-filter pre-flight；v0.3 profile-aware model/effort/max_time + profile_source；v0.4 heading-hardened：Step 3 instructions literal-token 化（`## Summary`/`## Findings` H2 + `### Finding N:` H3 + "exactly two H2 sections" + CRITICAL 開頭條款），issue #1）
│           ├── codex-rescue/SKILL.md           ← 已落地：/codex-pro:codex-rescue v0.2（codex-call HTTPS direct、Design constraint #1 default rule；task delegation；fail-fast 4 類含 task_unclear；session continuity 為 known limitation、待 upstream codex-call 加 session support；v0.2 profile-aware model/effort/max_time + profile_source）
│           ├── codex-adversarial-review/SKILL.md ← 已落地 v0.3（hostile review、4 mandatory H2 sections 各 non-empty、fail-fast 4 類含 target_invalid pre-flight；v0.2 untracked-by-default + binary path-only + 64KB/512KB size cap + pre-first-commit fallback；--focus 200-char cap + fenced delimiter 防 #333、--depth shallow|deep；v0.3 profile-aware model/effort/max_time + focus_default fallback + profile_source）
│           ├── codex-status/SKILL.md            ← 已落地 v0.1（read-only consumer — 掃 .codex-pro/*.md + markdown table summary、--skill filter）
│           ├── codex-result/SKILL.md            ← 已落地 v0.1（read-only consumer — 顯示特定 result file、三 selection mode）
│           ├── codex-cancel/SKILL.md            ← 已落地 v0.1（informational only — stateless explainer + 3 remediation、永遠 exit 0）
│           └── codex-config/SKILL.md            ← 已落地 v0.1（read-only consumer — display resolved profile、global + project two-layer、4 field schema：model / effort / max_time / focus_default）
├── openspec/                             ← Spectra SDD 工件
├── README.md                             ← marketplace 對外入口（install user）
└── CLAUDE.md                             ← AI / collaborator 設計指引
```

### Single-plugin within marketplace convention

- Marketplace name = plugin name = `codex-pro`。安裝命令採 `/plugin install codex-pro@codex-pro` 形式（marketplace name 與 plugin name 同名）
- Plugin name = skill namespace prefix，**且每個 skill 的 `name:` 一律再帶 `codex-` 前綴**。所有 skill 觸發名統一形如 `/codex-pro:codex-<skill>`（例如 `/codex-pro:codex-setup`、`/codex-pro:codex-review`、`/codex-pro:codex-config`）。namespace prefix（`codex-pro:`）擋 slug 字面撞名，`codex-` skill 前綴進一步讓每個 skill 名 distinctive、與系統命令（如 `/config`／「設定」）語意隔離
- **所有 future capability 直接加為 `plugins/codex-pro/skills/codex-<skill-name>/SKILL.md`（目錄名與 `name:` 皆帶 `codex-` 前綴），不開新 sub-plugin**。理由：codex-pro 是 single-vendor / single-product，跨 capability 共用 namespace 對 user 一致、無 capability 名重複
- **命名慣例演進紀錄**：本段先前訂「所有 skill 觸發名統一形如 `/codex-pro:<skill>`… 此為 final naming convention，無下次 reverse 計畫」（無 `codex-` skill 前綴）。`rename-skills-codex-prefix`（issue #2）**明文反轉**該慣例 —— 起因是裸 skill 名（尤其 `config`）與系統「設定」／內建 `/config` 語意撞名、trigger keyword 過度泛用導致 Claude 誤選；全 9 skill 加 `codex-` 前綴 + 收斂各 description 的 trigger keyword 一併解決。此為當前 convention；「final」措辭已作廢，未來若再有結構性命名調整仍走 Spectra change 誠實記錄

### 安裝 / dev-test 路徑

- **正規 install**：先 `/plugin marketplace add <codex-pro 路徑或 GitHub repo>`，再 `/plugin install codex-pro@codex-pro`
- **Plugin dev test**：`claude --plugin-dir <codex-pro>/plugins/codex-pro`（指 plugin 目錄、不是 marketplace root）

## 與相關 marketplace 的關係

| Marketplace / Plugin | 關係 | 用途 |
|---|---|---|
| [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc) | 對標、要超越 | 痛點來源、design 反例 |
| `psychquant/parallel-ai-agents`（plugin） | **runtime dependency** | 提供 `bin/codex-call` Swift wrapper |
| `psychquant/codex-batch`（plugin） | sibling | 給 Codex CLI 端用的 plugin（不是 Claude Code 端） |

`parallel-ai-agents/CLAUDE.md` 已記載 `codex-call` 的技術選擇理由（為什麼是 Swift script、為什麼不是 Python、為什麼不走 subprocess）— 那份是 source of truth，本專案不複述。

## Design constraints（implementation 期必守）

1. **No subprocess spawn for Codex** — 一律走 `codex-call` HTTPS direct（防 #330 deadlock）
2. **Hard timeout mandatory** — 任何 Codex call 必須有 `DispatchSemaphore` 或等價 timeout，無 unbound wait
3. **Circuit breaker on rate limit** — 一次 rate limit fail 後鎖 session、persist degraded state，禁止 same-session retry（防 #306）
4. **Structured result file** — Codex output 一律寫進 disk 結構化檔案，禁止 silent stub return（防 #324）
5. **Profile-based config** — `max-findings`、`sandbox` mode、`model` alias、`focus` 全部可在 profile 配置。**v0.5 部分落地**：`model` / `effort` / `max_time` / `focus_default` 4 fields 經 `~/.codex-pro/profile.yaml`（global）+ `.codex-pro/profile.yaml`（project）two-layer 配置、`/codex-pro:codex-config` 顯示 resolved profile、producer skills（review / rescue / adversarial-review）read profile 決定 codex-call flags；`max_findings`（會 conflict review uncapped findings 承諾）+ `sandbox`（batch-specific）留 future cycle
6. **Observability default ON** — token usage、cost estimate、Codex tier 對 user visible，無 opt-in
7. **macOS only（初期）** — Windows IPC 包袱大、用戶不需，明確不支援

## Commands surface（drop-in 對照）

| codex-plugin-cc command | codex-pro command | 備註 |
|---|---|---|
| `/codex:setup` | `/codex-pro:codex-setup` — 已落地 | 檢查 `~/.codex/auth.json` 與 `codex-call` 在 PATH，純 read-only |
| （無對應）| `/codex-pro:codex-batch` — 已落地 | `codex exec --full-auto` 平行批次處理大型 reference doc 多 chunk（textbook 解題 / 翻譯 / 摘要）；**Design constraint #1 的 explicit exception**（fan-out shell job control，非 single-shot pipe）；mutating（產生 shell script + 寫 output dir）|
| `/codex:review` | `/codex-pro:codex-review` — 已落地 v0.4 | 走 codex-call HTTPS direct、Design constraint #1 default rule 範例（與 batch exception 對比）；結果寫 `.codex-pro/review-<ts>.md`；fail-fast 4 類含 v0.2 `target_invalid` pre-flight；**v0.2 untracked-by-default**：`--diff` mode 含 `git diff HEAD` + untracked enumeration、binary path-only、per-file 64KB / aggregate 512KB size cap、`diff (pre-first-commit)` fallback、target_invalid post-filter pre-flight；**v0.3 profile-aware**：`--model` / `--effort` / `--max-time` 從 `~/.codex-pro/profile.yaml` + `.codex-pro/profile.yaml` resolve、frontmatter 加 `profile_source`、未設 profile 100% backward compatible（見 `/codex-pro:codex-config`）；**v0.4 heading-hardened**：Step 3 system instructions 改 literal-token 寫法（命名 `## Summary` / `## Findings` H2 + `### Finding N:` H3、"exactly two H2 sections, in this order" + CRITICAL 開頭條款），解 Codex 偶爾漂移必要 heading（issue #1）；e2e heading 檢查依觀察 gate conditional 由 warn 升 hard|
| `/codex:adversarial-review` | `/codex-pro:codex-adversarial-review` — 已落地 v0.3 | 走 codex-call HTTPS direct、Design constraint #1 default rule（與 review / rescue 同模板、與 batch exception 對比、3:1 default vs exception）；single-oracle hostile reviewer pass；結果寫 `.codex-pro/adversarial-review-<ts>.md` 含 4 mandatory H2 sections（Assumptions Challenged / Failure Modes / Alternative Approaches / Trade-off Counterarguments）各 non-empty；fail-fast 4 類含 adversarial-specific **`target_invalid`** pre-flight class（防空 prompt 浪費 quota、v0.2 延伸 condition：post binary+size filter empty）；**v0.2 untracked-by-default**：`--diff` mode 含 `git diff HEAD` + untracked enumeration、binary path-only、per-file 64KB / aggregate 512KB size cap、`diff (pre-first-commit)` fallback；`--focus <area>` 經 200-char cap + fenced delimiter（`<<<USER_FOCUS_START>>>` / `<<<USER_FOCUS_END>>>`）+ role-protection 防 prompt-injection（解上游 #333）；`--depth shallow\|deep` 控制 adversarial 強度（預設 deep）；**v0.3 profile-aware**：`--model` / `--effort` / `--max-time` + `--focus` 未給時用 profile `focus_default`、frontmatter 加 `profile_source`（見 `/codex-pro:codex-config`）|
| `/codex:rescue` | `/codex-pro:codex-rescue` — 已落地 v0.2 | 走 codex-call HTTPS direct、Design constraint #1 default rule（與 review 同模板、與 batch exception 對比）；task delegation；fail-fast 4 類含 task_unclear；結果寫 `.codex-pro/rescue-<ts>.md`；**known limitation**：session continuity 暫已移除（codex-call 尚無 session flag upstream support、待 restore）；**v0.2 profile-aware**：`--model` / `--effort` / `--max-time` 從 profile resolve、frontmatter 加 `profile_source`（見 `/codex-pro:codex-config`）|
| `/codex:status` | `/codex-pro:codex-status` — 已落地 v0.1 | Read-only consumer — 掃 `.codex-pro/*.md` + markdown table summary（columns：filename / skill type / target / outcome summary / timestamp / error）、`--skill <review\|rescue\|adversarial-review>` filter、missing/empty `.codex-pro/` 為 informational case（exit 0、不建目錄） |
| `/codex:result` | `/codex-pro:codex-result` — 已落地 v0.1 | Read-only consumer — 顯示特定 result file（frontmatter + body verbatim）、三 selection mode 互斥：位置 `<filename>` / `--latest <skill>` / `--latest`（無 arg）；用 filename ISO8601 portion 決定 most recent（不查 mtime / frontmatter timestamp）；fail-fast with `/codex-pro:codex-status` 或 producer skill 之 remediation、不 silent fallback |
| `/codex:cancel` | `/codex-pro:codex-cancel` — 已落地 v0.1 | **informational only** — codex-pro v0.2 為 stateless single-shot、無 background job、無 PID 可殺、無 upstream cancel API；輸出 deterministic explainer + 3 remediation（Ctrl-C / `--max-time 600` timeout / future v0.3+ background mode）；零 file ops、零 process signal、永遠 exit 0；displayed limitation 而非 silent stub |
| （無對應）| `/codex-pro:codex-config` — 已落地 v0.1 | Read-only consumer — display resolved profile（global `~/.codex-pro/profile.yaml` + project `.codex-pro/profile.yaml` two-layer、field-level merge、project override global）；4-row markdown table（field / resolved value / source）+ 2 行 file 存在性；schema v0.1（4 fields：`model` / `effort` / `max_time` / `focus_default`）；missing field → hardcoded default（gpt-5.6-sol / xhigh / 600 / 空）；零 file mutation、零 Codex 互動；codex-plugin-cc 無對應（codex-pro 自有 capability、補 Design constraint #5）|

codex-pro 與 codex-plugin-cc 的命令名不衝突，可同時安裝做 A/B 比較。

## Review vs adversarial-review — when to use which

`/codex-pro:codex-review` 與 `/codex-pro:codex-adversarial-review` 共用 single-oracle codex-call infrastructure、但 mental model 不同：review 找 bug（assessment）、adversarial-review 找盲點（challenge）。Decision table 給 user 一眼對應自己情境：

| 情境 | 用 `/codex-pro:codex-review` | 用 `/codex-pro:codex-adversarial-review` |
|---|---|---|
| 我寫了 code、不確定有沒有 bug | ✓ | ✗（過 hostile） |
| 我設計了方案、想被挑刺 | ✗（assessment 不 challenge） | ✓ |
| Code review 為主、附帶建議 | ✓ | ✗ |
| 想 stress-test trade-off | ✗ | ✓ |
| 找 bug + 想 alternatives | 跑 review 先、有疑慮再跑 adversarial-review | — |
| 需要 ensemble 多角度 | 留 v0.2 review-v2-ensemble | 留 v0.2 |

兩個 skill 的 output 結構也反映 mental model 差異 — review 的 `## Findings` 是 enumerative（findings count 可變），adversarial-review 的 4 H2 sections（Assumptions Challenged / Failure Modes / Alternative Approaches / Trade-off Counterarguments）是 perspectival（固定四個視角、每段 non-empty）。

## Read-only consumer skills（status / result / cancel / config）— v0.2 起 mental model 轉軸

v0.2 起 codex-pro 把 skill 分四 category：

| Category | Skills | 屬性 |
|---|---|---|
| **Read-only environment** | setup | 環境檢查、無 disk mutation、無 Codex 互動 |
| **Read-only consumer**（v0.2 新增、v0.5 加 config）| status / result / cancel / config | 讀 `.codex-pro/` producer output 或 `~/.codex-pro/` + `.codex-pro/` profile（cancel 不讀）、無 disk mutation、無 Codex 互動 |
| **Mutating producer** | review / rescue / adversarial-review | 寫 `.codex-pro/<skill>-<ts>.md`、走 Codex HTTP wrapper、Design constraint #1 default rule；v0.5 起 profile-aware（讀 profile 決定 model/effort/max_time/focus_default、但仍不寫 profile）|
| **Mutating exception** | batch | `codex exec --full-auto` 平行批次、Design constraint #1 explicit exception |

User 一眼看出「我跑這 skill 會不會動 disk / 燒 Codex quota」— 是 mental model 必備 affordance：

- Read-only category（5 skill：setup + status + result + cancel + config）跑都安全、不耗 quota、不破壞既有 disk 狀態
- Producer category（3 skill）會建 `.codex-pro/` + 寫 result file + 燒 quota（一次 codex-call）；v0.5 起額外讀 profile（read-only）決定 codex-call flags
- Exception（batch）會 fan-out shell jobs + 寫 output dir + 燒大量 quota

Future skill design：先決定 category 再寫 SKILL.md、prevent 散亂的 skill 屬性蔓延。如 v0.3 可能加 `/codex-pro:doctor` 既檢查環境（read-only）也修配置（mutating）— 走 design 一輪歸主屬性類、配 secondary tag。

## Development workflow

本專案走 Spectra SDD（見上方 Spectra block）。實作節奏：

1. 每個新 skill（屬 `plugins/codex-pro/skills/<skill-name>/`）用 `/spectra-propose <change-name>` 開 change proposal
2. 用 `/spectra-apply` 實作
3. 實作 / 變更 SKILL 或 manifest 後跑 `bash tests/run.sh`，確認 Layer 1+2 全綠再 `/spectra-archive`
4. 重大 namespace / spec 變更（過去 marketplace-pivot、consolidate-naming 級的）archive 後手動跑 `tests/e2e-checklist.md`
5. 本 marketplace 目前以 local dev 為主；對外發布（push 到 GitHub 並廣告）留待主要 skill（setup / review / rescue）穩定後再評估
6. `codex-call` runtime 短期內直接 reference `parallel-ai-agents` 的 PATH-exposed binary；穩定後再評估抽成獨立 dependency

## Tests

三層 test scenarios（見 `tests/` 目錄）：

| Layer | Entry | 內容 | 自動化 | 跑 cadence |
|---|---|---|---|---|
| 1 static | `bash tests/static.sh` | manifest JSON schema、SKILL.md frontmatter、`bash -n`、batch template sha256（hardcoded invariant）、namespace consistency grep | 全自動 | per commit |
| 2 behavioral | `bash tests/setup.sh` + 各 skill `.sh` + `lib/assert.sh` | setup isolated env、producer skill collection logic mock + fixture、read-only consumer behavioral runtime test、batch exception markers | 全自動 | per commit |
| 3 e2e (automated) | `bash tests/e2e.sh --skill X --scenario Y` | 跑 `claude --print --plugin-dir` 真正觸發 SKILL.md、5 scenario × 2 producer skill = 10 組合、result file 結構 + behavioral marker verify | 全自動 **opt-in**（不入 `tests/run.sh`）| per release（~10 codex-call quota + ~500k Claude tokens + 10-30min + retry policy on rate limit） |
| 3 manual | `tests/e2e-checklist.md` | plugin install UI flow、marketplace add / install / setup 觸發 + 輸出比對 | 手動 checklist | per release |

一條命令跑 Layer 1+2：

```
bash tests/run.sh
```

跑完顯示 aggregate「N pass / N fail / N total」與 layer-level pass/fail count、exit 0 表全綠。詳見 [openspec/specs/tests/spec.md](openspec/specs/tests/spec.md)。

## References

- 原 plugin: <https://github.com/openai/codex-plugin-cc>
- Claude Code 官方文檔：
  - Plugins: <https://code.claude.com/docs/en/plugins.md>
  - Plugin marketplaces: <https://code.claude.com/docs/en/plugin-marketplaces.md>
- 關鍵 issues 作為 design 反例：
  - [#330](https://github.com/openai/codex-plugin-cc/issues/330) IPC pipe deadlock
  - [#324](https://github.com/openai/codex-plugin-cc/issues/324) subagent stub return
  - [#306](https://github.com/openai/codex-plugin-cc/issues/306) rate limit 無限 retry
  - [#298](https://github.com/openai/codex-plugin-cc/issues/298) max-findings hardcode
  - [#304](https://github.com/openai/codex-plugin-cc/issues/304) sandbox hardcode
- `codex-call` 設計理由：`psychquant-claude-plugins/plugins/parallel-ai-agents/CLAUDE.md` § "bin/codex-call"
