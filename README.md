# codex-pro

對 [`openai/codex-plugin-cc`](https://github.com/openai/codex-plugin-cc) 的進階重寫，同時提供 **Codex 原生 plugin** 與 **Claude Code plugin**。兩種安裝方式共用十個 skill、profile 契約與結構化 `.codex-pro/` 結果檔。

`codex-pro` 以具 hard timeout、circuit breaker 與可觀測結果檔的 Swift HTTPS runtime 取代不穩定的 IPC 路徑。0.8.0 起，Codex 原生套件內含已釘選來源與雜湊的 runtime，不需另外安裝 Claude Code 或 `parallel-ai-agents`。

| 使用環境 | 發布入口 | Skill 叫用 |
|---|---|---|
| Codex App／CLI 原生 plugin | repo 根層 `.codex-plugin/plugin.json` | `$codex-setup`、`$codex-review` 等 |
| Codex 專案內 bundle | `.codex/` | `$codex-setup`、`$codex-review` 等 |
| Claude Code plugin | `plugins/codex-pro/` | `/codex-pro:codex-setup`、`/codex-pro:codex-review` 等 |

---

## What it replaces

| 上游（要取代）| codex-pro 對應 |
|---|---|
| `openai/codex-plugin-cc`（單一 plugin、200+ open issues） | `codex-pro` marketplace + 同名 plugin |
| `/codex:setup` | `/codex-pro:codex-setup` — 已落地 |
| `/codex:review` | `/codex-pro:codex-review` — 已落地 v0.4 |
| `/codex:adversarial-review` | `/codex-pro:codex-adversarial-review` — 已落地 v0.3 |
| `/codex:rescue` | `/codex-pro:codex-rescue` — 已落地 v0.2 |
| （無對應） | `/codex-pro:codex-visual-xval` — 已落地 v0.1 |
| `/codex:status` | `/codex-pro:codex-status` — 已落地 v0.1 |
| `/codex:result` | `/codex-pro:codex-result` — 已落地 v0.1 |
| `/codex:cancel` | `/codex-pro:codex-cancel` — 已落地 v0.1（informational only） |
| （無對應）| `/codex-pro:codex-config` — 已落地 v0.1（codex-pro 自有 capability、補 Design constraint #5 profile-based config） |

## Why a marketplace package, not just a single skill

`openai/codex-plugin-cc` 把 review、adversarial-review、rescue、status、result、cancel 打包成單一 plugin — 共用同一條 IPC pipe、同一個 fail mode、同一份 hardcode sandbox profile。一個 capability 壞掉，其他連帶失靈（見 upstream issues [#330](https://github.com/openai/codex-plugin-cc/issues/330)、[#324](https://github.com/openai/codex-plugin-cc/issues/324)、[#306](https://github.com/openai/codex-plugin-cc/issues/306)）。

`codex-pro` 也是 single plugin，但底下每個 skill 走獨立的 architecture discipline（見 [`CLAUDE.md`](./CLAUDE.md) Design constraints）：

- 每個 skill 各自有 circuit breaker
- 各自有獨立的 profile（max-findings、sandbox、model alias）
- producer 共用 `codex-call` runtime（Codex 原生版使用套件內的釘選 snapshot；Claude Code 版維持從 PATH 解析）
- 一個 skill fail 不會把 session 卡死

Marketplace metadata 讓同一份 Git snapshot 可被 Codex CLI／App 或 Claude Code 安裝；本版仍維持 single plugin，沒有新增 MCP server、hook 或 app。

## Skills

所有 capability 的手工來源都是 `plugins/codex-pro/skills/<skill>/SKILL.md`。Claude Code
叫用形如 `/codex-pro:<skill>`；Codex 原生版與專案內 bundle 則叫用 `$codex-*`：

> **Codex 使用者**：同一批 skill 有兩份完整生成 bundle：repo 根層供原生 plugin 安裝，`.codex/` 供專案內探索。兩者都由 `scripts/generate-codex-skills.sh` 從 `plugins/codex-pro/` **單向生成**，漂移由 `tests/codex-skills-parity.sh` 擋下。不要手改根層或 `.codex/` 的 `skills/`、`references/`、`bin/` 與 `.codex-bundle-files`。

| Skill | 狀態 | 用途 |
|---|---|---|
| `setup` | v0.1.0 | 驗證 OAuth、codex-call runtime、plugin manifest 環境是否就緒。**Read-only**，跑其他 skill 前先確認。 |
| `batch` (`/codex-pro:codex-batch`) | v0.1.0 | 用 `codex exec --full-auto` 平行批次處理大型 reference doc 多 chunk（textbook 解題 / 翻譯 / 摘要）。產生 shell script + 跑 subprocess + 寫 output dir，**非 read-only**（與 setup 區別）。本 skill 為 Design constraint #1 的 explicit exception。 |
| `review` (`/codex-pro:codex-review`) | v0.4.0 | Single-oracle read-only review。target 三選一：current uncommitted diff / file path / `--base <ref>` branch comparison。走 codex-call HTTPS direct（**無 subprocess**、嚴守 Design constraint #1，與 batch exception 對比）。結果寫 `.codex-pro/review-<ts>.md`（YAML frontmatter + Summary + Findings）。**v0.2 untracked-by-default**：`--diff` mode 含 `git diff HEAD` + untracked enumeration、binary path-only、per-file 64KB / aggregate 512KB size cap、`diff (pre-first-commit)` fallback。**v0.3 profile-aware**：`--model` / `--effort` / `--max-time` 從 `~/.codex-pro/profile.yaml` + `.codex-pro/profile.yaml` resolve、frontmatter 加 `profile_source`、未設 profile 100% backward compatible（見 `/codex-pro:codex-config`）。**v0.4 heading-hardened**：Step 3 system instructions 改 literal-token 寫法（命名 `## Summary` / `## Findings` H2 + `### Finding N:` H3、"exactly two H2 sections, in this order" + CRITICAL 開頭條款），解 Codex 偶爾漂移必要 heading（issue #1）。Rate limit / OAuth invalid / timeout / **target_invalid** (v0.2 post-filter pre-flight) 4 類走 circuit-breaker fail-fast、不 retry。 |
| `adversarial-review` (`/codex-pro:codex-adversarial-review`) | v0.3.0 | Single-oracle hostile review。Target 三選一同 review：current uncommitted diff / file path / `--base <ref>` branch comparison。走 codex-call HTTPS direct（**無 subprocess**、與 review / rescue 同 Design constraint #1 default rule、與 batch exception 對比、3:1 default vs exception）。結果寫 `.codex-pro/adversarial-review-<ts>.md`（YAML frontmatter 6 必填 + optional `error` + body **4 mandatory H2 sections 各 non-empty**：Assumptions Challenged / Failure Modes / Alternative Approaches / Trade-off Counterarguments）。`--focus <area>` 經 200-char cap + fenced delimiter（`<<<USER_FOCUS_START>>>` / `<<<USER_FOCUS_END>>>`）+ role-protection 防 prompt-injection（解上游 #333）。`--depth shallow\|deep` 控制 adversarial 強度（預設 deep）。**v0.2 untracked-by-default**：`--diff` mode 含 `git diff HEAD` + untracked enumeration、binary path-only、per-file 64KB / aggregate 512KB size cap、`diff (pre-first-commit)` fallback。**v0.3 profile-aware**：`--model` / `--effort` / `--max-time` + `--focus` 未給時用 profile `focus_default`、frontmatter 加 `profile_source`（見 `/codex-pro:codex-config`）。Fail-fast 4 類含 **`target_invalid`** pre-flight class（v0.2 延伸 condition：post binary+size filter empty 也 fire、防空 prompt 浪費 quota）。 |
| `rescue` (`/codex-pro:codex-rescue`) | v0.2.0 | Single-oracle task delegation 給 Codex（與 review 同 default rule、與 batch exception 對比）。argument 三欄：`<task description>` + `--context <path>` (可重複) + `--criteria <text>`。結果寫 `.codex-pro/rescue-<ts>.md`（YAML frontmatter 7 fields + Task Brief + Outcome + Suggested Next Steps）。Fail-fast 4 類含 **task_unclear**（Codex 無法 commit 答案時顯式回報、消除 #324 silent stub）。**v0.1.1 known limitation**：session continuity 已移除（codex-call 尚無 session flag upstream support、待 restore）。**v0.2 profile-aware**：`--model` / `--effort` / `--max-time` 從 profile resolve、frontmatter 加 `profile_source`（見 `/codex-pro:codex-config`）。 |
| `visual-xval` (`/codex-pro:codex-visual-xval`) | v0.1.0 | 視覺交叉驗證：Claude 與 Codex 對同一批圖片各自判讀，Claude 的答案先封存（SHA-256＋時間），Codex 經 `codex-call --image` 盲答。分歧分數量、位置、關係三類，只用放大輪、SAM 2.1 量測、物理約束裁決，不用多數決。需要 parallel-ai-agents 2.24.0 以上的 `codex-call`；SAM 環境首次使用前徵得同意才安裝（約 1 GB）。結果寫 `.codex-pro/visual-xval-<ts>.md`。Fail-fast 6 類含 `runtime_unsupported`、`parse_failed`。 |
| `status` (`/codex-pro:codex-status`) | v0.1.0 | Read-only consumer — 掃 `.codex-pro/*.md` 並輸出 markdown table summary（columns：filename / skill type / target / outcome summary / timestamp / error）、`--skill <review\|rescue\|adversarial-review>` filter、missing/empty `.codex-pro/` 為 informational case（exit 0、不建目錄）。 |
| `result` (`/codex-pro:codex-result`) | v0.1.0 | Read-only consumer — 顯示特定 result file（frontmatter + body verbatim）、三 selection mode 互斥：位置 `<filename>` / `--latest <skill>` / `--latest`（無 arg）；用 filename ISO8601 portion 決定 most recent（不查 mtime / frontmatter timestamp）；fail-fast with `/codex-pro:codex-status` 或 producer skill 之 remediation、不 silent fallback。 |
| `cancel` (`/codex-pro:codex-cancel`) | v0.1.0 | **Informational only** — codex-pro v0.2 為 stateless single-shot、不殺任何 PID、不送 HTTPS；輸出 stateless explainer + 3 條 remediation（Ctrl-C / `--max-time 600` timeout / future v0.3+ background mode）、永遠 exit 0、deterministic byte-identical output；displayed limitation 而非 silent stub。 |
| `config` (`/codex-pro:codex-config`) | v0.1.0 | Read-only consumer — display resolved profile（global `~/.codex-pro/profile.yaml` + project `.codex-pro/profile.yaml` two-layer、field-level merge、project override global）；4-row markdown table（field / resolved value / source）+ 2 行 file 存在性；schema v0.1（4 fields：`model` / `effort` / `max_time` / `focus_default`）；missing field → hardcoded default（gpt-5.6-sol / xhigh / 600 / 空）；零 file mutation、零 Codex 互動。補 Design constraint #5 profile-based config 部分落地。 |

## Review vs adversarial-review — when to use which

`/codex-pro:codex-review` 與 `/codex-pro:codex-adversarial-review` 共用 single-oracle codex-call infrastructure，但 mental model 完全不同：

- **review**：「對既有 code 跑診斷、找 bug」(assessment) — output 是 `## Findings`（findings count 可變、enumerative）
- **adversarial-review**：「對既有 code 或 plan 跑壓力測試、找盲點」(challenge) — output 是 4 個固定 H2 sections 各 non-empty（perspectival，固定四個視角）

Decision table 給 user 一眼對應自己情境：

| 情境 | 用 `/codex-pro:codex-review` | 用 `/codex-pro:codex-adversarial-review` |
|---|---|---|
| 我寫了 code、不確定有沒有 bug | ✓ | ✗（過 hostile） |
| 我設計了方案、想被挑刺 | ✗（assessment 不 challenge） | ✓ |
| Code review 為主、附帶建議 | ✓ | ✗ |
| 想 stress-test trade-off | ✗ | ✓ |
| 找 bug + 想 alternatives | 跑 review 先、有疑慮再跑 adversarial-review | — |
| 需要 ensemble 多角度 | 留 v0.2 review-v2-ensemble | 留 v0.2 |

兩個 skill 命令名不衝突，可同一 session 順跑：先 `/codex-pro:codex-review` 找具體 bug、再 `/codex-pro:codex-adversarial-review` 對設計面壓力測試。

## Read-only vs producer skills — v0.2 起 mental model 轉軸

v0.2 起 codex-pro 把 skill 分四 category 讓使用者一眼看出「跑這個會不會動 disk / 燒 Codex quota」：

- **Read-only category（不耗 quota、不破壞 disk）**：`setup`（環境檢查）+ `status`（list result files）+ `result`（顯示單一 result file）+ `cancel`（informational only）+ `config`（display resolved profile、v0.5 新增）
- **Mutating producer category（會建 `.codex-pro/` + 寫 result file + 一次 Codex HTTP wrapper call）**：`review`（assessment）+ `rescue`（task delegation）+ `adversarial-review`（hostile review）。v0.5 起 profile-aware（讀 `~/.codex-pro/profile.yaml` + project profile 決定 model / effort / max_time / focus_default、read-only 讀取、不寫 profile）
- **Mutating exception category（fan-out shell jobs + 寫 output dir + 大量 quota）**：`batch`（Design constraint #1 explicit exception）

實務 workflow：

1. 安裝後先跑 `/codex-pro:codex-setup` 確認環境（read-only、零成本）
2. 用 producer skill 跑 review / rescue / adversarial-review（each 一次 quota）
3. 用 `/codex-pro:codex-status` 列出累積的 result files（read-only）
4. 用 `/codex-pro:codex-result --latest` 看最近一次 detail（read-only）
5. 想 cancel 跑到一半的 producer call？用 Ctrl-C 或等 `--max-time 600`（`/codex-pro:codex-cancel` 為 informational explainer、解釋為何 v0.2 stateless model 無法真 cancel）

## Codex 原生安裝

### 需求與能力邊界

- Codex App 或支援 `codex plugin` 的 Codex CLI。
- `$codex-review`、`$codex-adversarial-review`、`$codex-rescue`、`$codex-visual-xval` 四個 producer 目前只支援 macOS，並需要 Xcode Command Line Tools 提供的 `swift`。
- `$codex-visual-xval` 另需 Python 3.10 以上的 `python3`（macOS 內建的 `/usr/bin/python3` 是 3.9，太舊時會以 `runtime_unavailable` 寫出結果檔）與 macOS 的 `sips`；SAM 2.1 追蹤是選用的，首次使用前徵得同意才安裝（約 1 GB）。
- producer 使用 Codex CLI 的 ChatGPT OAuth：先跑 `codex login`，確認 `~/.codex/auth.json` 可讀。
- `$codex-status`、`$codex-result`、`$codex-config`、`$codex-cancel` 是純本機 consumer；即使不是 macOS、沒有 Swift 或 producer runtime 不可用，仍可使用。
- `$codex-batch` 是獨立的 fan-out 例外，使用 `codex exec --full-auto` subprocess，不使用套件內的 Swift runtime；本版不承諾其跨平台可攜性。

安裝 self-hosted Git marketplace：

```bash
codex plugin marketplace add PsychQuant/codex-pro --ref main --json
codex plugin marketplace list --json
codex plugin list --marketplace codex-pro --available --json
codex plugin add codex-pro@codex-pro --json
```

`plugin list --marketplace ...` 對尚未設定的名稱可能仍以空陣列、exit 0 回應，所以第二行
的 marketplace listing 是必要驗證，不能只看 exit status。

安裝後請開啟一個**新 task**，先叫用 `$codex-setup`；既有 task 不保證會重新探索剛安裝的 skill。完整驗收步驟見 [`tests/e2e-checklist.md`](./tests/e2e-checklist.md)。

本機開發可直接加入 clone：

```bash
codex plugin marketplace add /absolute/path/to/codex-pro --json
codex plugin add codex-pro@codex-pro --json
```

Git marketplace 更新後，以移除再安裝確保 plugin cache 取用新 snapshot：

```bash
codex plugin marketplace upgrade codex-pro --json
codex plugin remove codex-pro@codex-pro --json
codex plugin add codex-pro@codex-pro --json
```

回復或完整移除時，先移除 plugin，再移除 marketplace；不會刪除專案既有的 `.codex-pro/` 結果檔：

```bash
codex plugin remove codex-pro@codex-pro --json
codex plugin marketplace remove codex-pro --json
```

Codex App 使用者要先在 Terminal 執行 `codex plugin marketplace add
PsychQuant/codex-pro --ref main --json`，完全結束並重啟 App，再從 Plugins Directory 選擇
`codex-pro` marketplace 與同名 plugin 安裝；開新 task 後檢查十個 skill。App 的可見性、
更新與解除安裝仍是發行前的人工 gate。本專案尚未宣稱已進入 OpenAI 官方 plugin
directory；0.8.0 發布後仍須依[官方 plugin 提交流程](https://developers.openai.com/plugins/deploy/submission)
另行完成 directory submission 與審核，實際要求以提交當時的官方文件為準。

## Claude Code 安裝

```text
# 1. 加入 marketplace（從 GitHub）
/plugin marketplace add psychquant/codex-pro

# 2. 安裝 plugin
/plugin install codex-pro@codex-pro

# 3. 跑環境檢查
/codex-pro:codex-setup
```

開發時可直接 clone repo 後跑 `claude --plugin-dir <repo>/plugins/codex-pro`（指 plugin 目錄，不是 marketplace root）。Claude Code 版刻意維持從 PATH 尋找 `codex-call`，不會改用 Codex 原生 bundle 的 runtime。

## Runtime、OAuth 與已知限制

Codex 原生套件分發的 `codex-call` 是從 `PsychQuant/parallel-ai-agents` 釘選的逐位元 snapshot。來源 commit、Git blob、大小與 SHA-256 記錄於 [`codex-call-provenance.json`](./plugins/codex-pro/references/codex-call-provenance.json)，第三方聲明見 [`THIRD_PARTY_NOTICES.md`](./THIRD_PARTY_NOTICES.md)。`bin/codex-pro-call --check` 只做平台、Swift、執行權限與雜湊檢查；它不讀 OAuth、不修改檔案，也不連網。

正常 producer 呼叫不同：runtime 會讀取 `~/.codex/auth.json`；token 即將到期時，會透過 `https://auth.openai.com/oauth/token` 更新憑證，使用 `~/.codex/.token-refresh.lock` 協調並行更新，之後呼叫 `https://chatgpt.com/backend-api/codex/responses`。這是 ChatGPT 的 private／experimental backend surface，並非承諾穩定的公開 API。

釘選 snapshot 也保留上游已知限制：

- [`parallel-ai-agents#28`](https://github.com/PsychQuant/parallel-ai-agents/issues/28)：SSE 的 UTF-8／CJK chunk 邊界與截斷問題。
- [`parallel-ai-agents#35`](https://github.com/PsychQuant/parallel-ai-agents/issues/35)：尚無可依賴的穩定外部 runtime 契約。

本版不修正上述上游問題，也不新增 Linux／Windows producer、改寫 batch、品牌資產、MCP server 或 hook。

## 生成來源與 ownership

手工維護的 skill 與 runtime 來源只在 `plugins/codex-pro/`。無參數執行：

```bash
scripts/generate-codex-skills.sh
```

會同步產生 repo 根層與 `.codex/` 兩個完整 bundle，包含十個 skills、nested resources、shared references、runtime wrapper、runtime snapshot 與 `.codex-bundle-files` inventory。不要直接編輯這些受管產物；修改來源後重生，並以 `bash tests/codex-skills-parity.sh` 檢查漂移。

## Tests

自動與人工測試在 `tests/`：

- **Codex package contract** — `tests/codex-plugin.sh` 驗原生 manifest、repo marketplace、十個 skills、版本與 plugin-creator validator
- **Codex bundle parity** — `tests/codex-skills-parity.sh` 驗兩個完整 bundle、暫存重生、相對連結、ownership 與冪等性
- **Codex runtime** — `tests/codex-runtime.sh` 驗 provenance、wrapper、resolver matrix；`--smoke` 在 macOS 執行真 Swift 離線檢查
- **Layer 1 (static)** — Claude manifest JSON schema、SKILL.md frontmatter、`bash -n`、batch template byte-identical sha256、namespace consistency
- **Layer 2 (behavioral)** — setup isolated env、producer skill collection logic mock + behavioral runtime test、read-only consumer mktemp fixture、batch exception markers
- **Layer 3 (automated e2e, opt-in)** — `bash tests/e2e.sh --skill X --scenario Y`：跑 `claude --print --plugin-dir` 真正觸發 SKILL.md、verify result file 結構與 behavioral marker；6 scenarios × 2 producer skills = 12 組合；release gate（非 commit gate）；約 12 次 codex-call quota + 600k Claude API tokens + 12–36 分鐘；含 Anthropic API rate-limit 自動 retry 3 次 30s／60s／120s backoff
- **Layer 3 (manual)** — `tests/e2e-checklist.md` 同時涵蓋 Codex CLI／App 原生安裝與 Claude Code UI flow

一條命令跑 Layer 1+2：

```
bash tests/run.sh
```

跑完顯示 aggregate「N pass / N fail / N total」與 layer-level pass/fail count；exit 0 表全綠。Layer 3 是人工 markdown checklist，需要在全新 Codex task 或 Claude Code session 親自跑。

也可單獨跑某 layer：`bash tests/static.sh`、`bash tests/setup.sh`、`bash tests/batch.sh`。

## Reference

- **Upstream we replace**: <https://github.com/openai/codex-plugin-cc> — 原 OpenAI codex plugin（200+ open issues 是 codex-pro 設計的反例來源）
- **Runtime provenance**: [`plugins/codex-pro/references/codex-call-provenance.json`](./plugins/codex-pro/references/codex-call-provenance.json) — Codex 原生版分發釘選 snapshot；Claude Code 版維持 PATH 契約
- **設計細節 / design rationale**: see [`CLAUDE.md`](./CLAUDE.md)
- **Spec-driven development**: 走 Spectra SDD — specs 在 `openspec/specs/`、change proposals 在 `openspec/changes/`

## License

MIT
