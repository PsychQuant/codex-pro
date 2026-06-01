# codex-pro

對 [`openai/codex-plugin-cc`](https://github.com/openai/codex-plugin-cc) 的進階重寫，以 **Claude Code marketplace** 殼包一個與之同名的 plugin `codex-pro`。

`codex-pro` 用 ensemble pattern + 自家 Swift HTTPS runtime（透過 `parallel-ai-agents` 的 `codex-call` wrapper）取代上游 single-plugin 架構，從根本解決 IPC deadlock、subagent stub、無限 retry、零 observability 等系統性痛點。

---

## What it replaces

| 上游（要取代）| codex-pro 對應 |
|---|---|
| `openai/codex-plugin-cc`（單一 plugin、200+ open issues） | `codex-pro` marketplace + 同名 plugin |
| `/codex:setup` | `/codex-pro:setup` — 已落地 |
| `/codex:review` | `/codex-pro:review` — 已落地 v0.1 |
| `/codex:adversarial-review` | `/codex-pro:adversarial-review` — 已落地 v0.1 |
| `/codex:rescue` | `/codex-pro:rescue` — 已落地 v0.1.1 |
| `/codex:status` / `/codex:result` / `/codex:cancel` | `/codex-pro:status` / `:result` / `:cancel` — 規劃中 |

## Why a marketplace shell, not just a single plugin

`openai/codex-plugin-cc` 把 review、adversarial-review、rescue、status、result、cancel 打包成單一 plugin — 共用同一條 IPC pipe、同一個 fail mode、同一份 hardcode sandbox profile。一個 capability 壞掉，其他連帶失靈（見 upstream issues [#330](https://github.com/openai/codex-plugin-cc/issues/330)、[#324](https://github.com/openai/codex-plugin-cc/issues/324)、[#306](https://github.com/openai/codex-plugin-cc/issues/306)）。

`codex-pro` 也是 single plugin，但底下每個 skill 走獨立的 architecture discipline（見 [`CLAUDE.md`](./CLAUDE.md) Design constraints）：

- 每個 skill 各自有 circuit breaker
- 各自有獨立的 profile（max-findings、sandbox、model alias）
- 共用 `parallel-ai-agents/bin/codex-call` runtime（無 subprocess、hard timeout、HTTPS direct）
- 一個 skill fail 不會把 session 卡死

Marketplace 殼存在的理由是給未來「對外發布到 GitHub + `/plugin marketplace add`」鋪好基礎結構，不是當前需要拆分多 plugin。

## Skills

所有 capability 都是 `plugins/codex-pro/skills/<skill>/SKILL.md` 結構，skill 觸發名統一形如 `/codex-pro:<skill>`：

| Skill | 狀態 | 用途 |
|---|---|---|
| `setup` | v0.1.0 | 驗證 OAuth、codex-call runtime、plugin manifest 環境是否就緒。**Read-only**，跑其他 skill 前先確認。 |
| `batch` (`/codex-pro:batch`) | v0.1.0 | 用 `codex exec --full-auto` 平行批次處理大型 reference doc 多 chunk（textbook 解題 / 翻譯 / 摘要）。產生 shell script + 跑 subprocess + 寫 output dir，**非 read-only**（與 setup 區別）。本 skill 為 Design constraint #1 的 explicit exception。 |
| `review` (`/codex-pro:review`) | v0.1.0 | Single-oracle read-only review。target 三選一：current uncommitted diff / file path / `--base <ref>` branch comparison。走 codex-call HTTPS direct（**無 subprocess**、嚴守 Design constraint #1，與 batch exception 對比）。結果寫 `.codex-pro/review-<ts>.md`（YAML frontmatter + Summary + Findings）。Rate limit / OAuth invalid / timeout 走 circuit-breaker fail-fast、不 retry。 |
| `adversarial-review` (`/codex-pro:adversarial-review`) | v0.1.0 | Single-oracle hostile review。Target 三選一同 review：current uncommitted diff / file path / `--base <ref>` branch comparison。走 codex-call HTTPS direct（**無 subprocess**、與 review / rescue 同 Design constraint #1 default rule、與 batch exception 對比、3:1 default vs exception）。結果寫 `.codex-pro/adversarial-review-<ts>.md`（YAML frontmatter 6 必填 + optional `error` + body **4 mandatory H2 sections 各 non-empty**：Assumptions Challenged / Failure Modes / Alternative Approaches / Trade-off Counterarguments）。`--focus <area>` 經 200-char cap + fenced delimiter（`<<<USER_FOCUS_START>>>` / `<<<USER_FOCUS_END>>>`）+ role-protection 防 prompt-injection（解上游 #333）。`--depth shallow\|deep` 控制 adversarial 強度（預設 deep）。Fail-fast 4 類含 **`target_invalid`** pre-flight class（target 解析後為空 / unreadable / zero-byte / whitespace-only 時 abort、防止把空 prompt 送進 codex 浪費 quota）。 |
| `rescue` (`/codex-pro:rescue`) | v0.1.1 | Single-oracle task delegation 給 Codex（與 review 同 default rule、與 batch exception 對比）。argument 三欄：`<task description>` + `--context <path>` (可重複) + `--criteria <text>`。結果寫 `.codex-pro/rescue-<ts>.md`（YAML frontmatter 7 fields + Task Brief + Outcome + Suggested Next Steps）。Fail-fast 4 類含 **task_unclear**（Codex 無法 commit 答案時顯式回報、消除 #324 silent stub）。**v0.1.1 known limitation**：session continuity 已移除（codex-call 尚無 session flag upstream support、待 restore）。 |
| `status` / `result` / `cancel` | 規劃中 | Background job 管理（含 token / cost / tier 觀測） |

## Review vs adversarial-review — when to use which

`/codex-pro:review` 與 `/codex-pro:adversarial-review` 共用 single-oracle codex-call infrastructure，但 mental model 完全不同：

- **review**：「對既有 code 跑診斷、找 bug」(assessment) — output 是 `## Findings`（findings count 可變、enumerative）
- **adversarial-review**：「對既有 code 或 plan 跑壓力測試、找盲點」(challenge) — output 是 4 個固定 H2 sections 各 non-empty（perspectival，固定四個視角）

Decision table 給 user 一眼對應自己情境：

| 情境 | 用 `/codex-pro:review` | 用 `/codex-pro:adversarial-review` |
|---|---|---|
| 我寫了 code、不確定有沒有 bug | ✓ | ✗（過 hostile） |
| 我設計了方案、想被挑刺 | ✗（assessment 不 challenge） | ✓ |
| Code review 為主、附帶建議 | ✓ | ✗ |
| 想 stress-test trade-off | ✗ | ✓ |
| 找 bug + 想 alternatives | 跑 review 先、有疑慮再跑 adversarial-review | — |
| 需要 ensemble 多角度 | 留 v0.2 review-v2-ensemble | 留 v0.2 |

兩個 skill 命令名不衝突，可同一 session 順跑：先 `/codex-pro:review` 找具體 bug、再 `/codex-pro:adversarial-review` 對設計面壓力測試。

## Install

```
# 1. 加入 marketplace（從 GitHub）
/plugin marketplace add psychquant/codex-pro

# 2. 安裝 plugin（marketplace 名與 plugin 名同為 codex-pro）
/plugin install codex-pro@codex-pro

# 3. 跑環境檢查
/codex-pro:setup
```

開發 / iterate 時可直接 clone repo 後跑 `claude --plugin-dir <repo>/plugins/codex-pro`（指 plugin 目錄、不是 marketplace root）。

## Tests

三層 test scenarios 在 `tests/`：

- **Layer 1 (static)** — manifest JSON schema、SKILL.md frontmatter、`bash -n`、batch template byte-identical sha256、namespace consistency
- **Layer 2 (behavioral)** — setup 三 check 在 isolated env 重跑（fake HOME / 剝離 PATH / mktemp fake plugin root）、read-only 紀律驗證、batch SKILL exception 標記 + template parallel orchestration markers
- **Layer 3 (manual)** — `tests/e2e-checklist.md` 含 12 條手動 UI 確認步驟

一條命令跑 Layer 1+2：

```
bash tests/run.sh
```

跑完顯示 aggregate「N pass / N fail / N total」與 layer-level pass/fail count；exit 0 表全綠。Layer 3 是手動 markdown checklist，需要在 fresh Claude Code session 親自跑。

也可單獨跑某 layer：`bash tests/static.sh`、`bash tests/setup.sh`、`bash tests/batch.sh`。

## Reference

- **Upstream we replace**: <https://github.com/openai/codex-plugin-cc> — 原 OpenAI codex plugin（200+ open issues 是 codex-pro 設計的反例來源）
- **Runtime dependency**: `parallel-ai-agents`（屬 `psychquant-claude-plugins` marketplace）— 提供 `codex-call` Swift wrapper，直連 `chatgpt.com/backend-api`、避開 `codex exec` subprocess（這是 upstream IPC deadlock 的根因）
- **設計細節 / design rationale**: see [`CLAUDE.md`](./CLAUDE.md)
- **Spec-driven development**: 走 Spectra SDD — specs 在 `openspec/specs/`、change proposals 在 `openspec/changes/`

## License

MIT
