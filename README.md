# codex-pro

對 [`openai/codex-plugin-cc`](https://github.com/openai/codex-plugin-cc) 的進階重寫，以 **Claude Code marketplace** 殼包一個與之同名的 plugin `codex-pro`。

`codex-pro` 用 ensemble pattern + 自家 Swift HTTPS runtime（透過 `parallel-ai-agents` 的 `codex-call` wrapper）取代上游 single-plugin 架構，從根本解決 IPC deadlock、subagent stub、無限 retry、零 observability 等系統性痛點。

---

## What it replaces

| 上游（要取代）| codex-pro 對應 |
|---|---|
| `openai/codex-plugin-cc`（單一 plugin、200+ open issues） | `codex-pro` marketplace + 同名 plugin |
| `/codex:setup` | `/codex-pro:setup` — 已落地 |
| `/codex:review` | `/codex-pro:review` — 已落地 v0.3 |
| `/codex:adversarial-review` | `/codex-pro:adversarial-review` — 已落地 v0.3 |
| `/codex:rescue` | `/codex-pro:rescue` — 已落地 v0.2 |
| `/codex:status` | `/codex-pro:status` — 已落地 v0.1 |
| `/codex:result` | `/codex-pro:result` — 已落地 v0.1 |
| `/codex:cancel` | `/codex-pro:cancel` — 已落地 v0.1（informational only） |
| （無對應）| `/codex-pro:config` — 已落地 v0.1（codex-pro 自有 capability、補 Design constraint #5 profile-based config） |

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
| `review` (`/codex-pro:review`) | v0.3.0 | Single-oracle read-only review。target 三選一：current uncommitted diff / file path / `--base <ref>` branch comparison。走 codex-call HTTPS direct（**無 subprocess**、嚴守 Design constraint #1，與 batch exception 對比）。結果寫 `.codex-pro/review-<ts>.md`（YAML frontmatter + Summary + Findings）。**v0.2 untracked-by-default**：`--diff` mode 含 `git diff HEAD` + untracked enumeration、binary path-only、per-file 64KB / aggregate 512KB size cap、`diff (pre-first-commit)` fallback。**v0.3 profile-aware**：`--model` / `--effort` / `--max-time` 從 `~/.codex-pro/profile.yaml` + `.codex-pro/profile.yaml` resolve、frontmatter 加 `profile_source`、未設 profile 100% backward compatible（見 `/codex-pro:config`）。Rate limit / OAuth invalid / timeout / **target_invalid** (v0.2 post-filter pre-flight) 4 類走 circuit-breaker fail-fast、不 retry。 |
| `adversarial-review` (`/codex-pro:adversarial-review`) | v0.3.0 | Single-oracle hostile review。Target 三選一同 review：current uncommitted diff / file path / `--base <ref>` branch comparison。走 codex-call HTTPS direct（**無 subprocess**、與 review / rescue 同 Design constraint #1 default rule、與 batch exception 對比、3:1 default vs exception）。結果寫 `.codex-pro/adversarial-review-<ts>.md`（YAML frontmatter 6 必填 + optional `error` + body **4 mandatory H2 sections 各 non-empty**：Assumptions Challenged / Failure Modes / Alternative Approaches / Trade-off Counterarguments）。`--focus <area>` 經 200-char cap + fenced delimiter（`<<<USER_FOCUS_START>>>` / `<<<USER_FOCUS_END>>>`）+ role-protection 防 prompt-injection（解上游 #333）。`--depth shallow\|deep` 控制 adversarial 強度（預設 deep）。**v0.2 untracked-by-default**：`--diff` mode 含 `git diff HEAD` + untracked enumeration、binary path-only、per-file 64KB / aggregate 512KB size cap、`diff (pre-first-commit)` fallback。**v0.3 profile-aware**：`--model` / `--effort` / `--max-time` + `--focus` 未給時用 profile `focus_default`、frontmatter 加 `profile_source`（見 `/codex-pro:config`）。Fail-fast 4 類含 **`target_invalid`** pre-flight class（v0.2 延伸 condition：post binary+size filter empty 也 fire、防空 prompt 浪費 quota）。 |
| `rescue` (`/codex-pro:rescue`) | v0.2.0 | Single-oracle task delegation 給 Codex（與 review 同 default rule、與 batch exception 對比）。argument 三欄：`<task description>` + `--context <path>` (可重複) + `--criteria <text>`。結果寫 `.codex-pro/rescue-<ts>.md`（YAML frontmatter 7 fields + Task Brief + Outcome + Suggested Next Steps）。Fail-fast 4 類含 **task_unclear**（Codex 無法 commit 答案時顯式回報、消除 #324 silent stub）。**v0.1.1 known limitation**：session continuity 已移除（codex-call 尚無 session flag upstream support、待 restore）。**v0.2 profile-aware**：`--model` / `--effort` / `--max-time` 從 profile resolve、frontmatter 加 `profile_source`（見 `/codex-pro:config`）。 |
| `status` (`/codex-pro:status`) | v0.1.0 | Read-only consumer — 掃 `.codex-pro/*.md` 並輸出 markdown table summary（columns：filename / skill type / target / outcome summary / timestamp / error）、`--skill <review\|rescue\|adversarial-review>` filter、missing/empty `.codex-pro/` 為 informational case（exit 0、不建目錄）。 |
| `result` (`/codex-pro:result`) | v0.1.0 | Read-only consumer — 顯示特定 result file（frontmatter + body verbatim）、三 selection mode 互斥：位置 `<filename>` / `--latest <skill>` / `--latest`（無 arg）；用 filename ISO8601 portion 決定 most recent（不查 mtime / frontmatter timestamp）；fail-fast with `/codex-pro:status` 或 producer skill 之 remediation、不 silent fallback。 |
| `cancel` (`/codex-pro:cancel`) | v0.1.0 | **Informational only** — codex-pro v0.2 為 stateless single-shot、不殺任何 PID、不送 HTTPS；輸出 stateless explainer + 3 條 remediation（Ctrl-C / `--max-time 600` timeout / future v0.3+ background mode）、永遠 exit 0、deterministic byte-identical output；displayed limitation 而非 silent stub。 |
| `config` (`/codex-pro:config`) | v0.1.0 | Read-only consumer — display resolved profile（global `~/.codex-pro/profile.yaml` + project `.codex-pro/profile.yaml` two-layer、field-level merge、project override global）；4-row markdown table（field / resolved value / source）+ 2 行 file 存在性；schema v0.1（4 fields：`model` / `effort` / `max_time` / `focus_default`）；missing field → hardcoded default（gpt-5.5 / xhigh / 600 / 空）；零 file mutation、零 Codex 互動。補 Design constraint #5 profile-based config 部分落地。 |

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

## Read-only vs producer skills — v0.2 起 mental model 轉軸

v0.2 起 codex-pro 把 skill 分四 category 讓使用者一眼看出「跑這個會不會動 disk / 燒 Codex quota」：

- **Read-only category（不耗 quota、不破壞 disk）**：`setup`（環境檢查）+ `status`（list result files）+ `result`（顯示單一 result file）+ `cancel`（informational only）+ `config`（display resolved profile、v0.5 新增）
- **Mutating producer category（會建 `.codex-pro/` + 寫 result file + 一次 Codex HTTP wrapper call）**：`review`（assessment）+ `rescue`（task delegation）+ `adversarial-review`（hostile review）。v0.5 起 profile-aware（讀 `~/.codex-pro/profile.yaml` + project profile 決定 model / effort / max_time / focus_default、read-only 讀取、不寫 profile）
- **Mutating exception category（fan-out shell jobs + 寫 output dir + 大量 quota）**：`batch`（Design constraint #1 explicit exception）

實務 workflow：

1. 安裝後先跑 `/codex-pro:setup` 確認環境（read-only、零成本）
2. 用 producer skill 跑 review / rescue / adversarial-review（each 一次 quota）
3. 用 `/codex-pro:status` 列出累積的 result files（read-only）
4. 用 `/codex-pro:result --latest` 看最近一次 detail（read-only）
5. 想 cancel 跑到一半的 producer call？用 Ctrl-C 或等 `--max-time 600`（`/codex-pro:cancel` 為 informational explainer、解釋為何 v0.2 stateless model 無法真 cancel）

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
- **Layer 2 (behavioral)** — setup isolated env、producer skill collection logic mock + behavioral runtime test、read-only consumer mktemp fixture、batch exception markers
- **Layer 3 (automated e2e, opt-in)** — `bash tests/e2e.sh --skill X --scenario Y`：跑 `claude --print --plugin-dir` 真正觸發 SKILL.md、verify result file 結構與 behavioral marker；5 scenario × 2 producer skill = 10 組合；release gate（非 commit gate）；~10 codex-call quota + ~500k Claude API tokens + 10-30min；含 Anthropic API rate-limit 自動 retry 3 次 30s/60s/120s backoff
- **Layer 3 (manual)** — `tests/e2e-checklist.md` 含 plugin install UI flow 手動 checklist

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
