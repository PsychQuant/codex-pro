## Context

`codex-pro` 是新 Claude Code plugin，定位為 `openai/codex-plugin-cc` 的進階重寫（vision 見 CLAUDE.md）。本 change 為 greenfield bootstrap — 在 0 source files 的前提下建立最小可運作的 plugin skeleton，並交付 `/codex-pro:setup` 作為第一個可驗證命令。

`/codex-pro:setup` 的功能是「環境就緒檢查」— 使用者跑完能知道：

- Codex OAuth token 檔（`~/.codex/auth.json`）是否存在且可讀
- `parallel-ai-agents` 提供的 `codex-call` wrapper 是否在 PATH 中可呼叫
- Plugin manifest 自身是否可被 Claude Code 正確解析

Setup 本身嚴格不執行任何 mutating 行為（不裝 codex CLI、不寫 auth、不修 PATH）— 純粹回報狀態與修復指引。

## Goals / Non-Goals

**Goals:**

- Plugin 可透過 Claude Code 的 `--plugin-dir` 本地載入機制掛載
- `/codex-pro:setup` 為可觸發的 skill，輸出結構化 readiness report
- Plugin manifest 符合 Claude Code 慣例（與既有 psychquant plugins 對齊）
- SKILL 描述充分到 Claude 在意圖匹配時能自動觸發

**Non-Goals:**

- 不實作任何 review / delegate command（`/codex-pro:review`、`/codex-pro:adversarial-review`、`/codex-pro:rescue` 等）
- 不實作 ensemble orchestration logic
- 不建獨立的 `codex-pro-plugins` marketplace repo（留待第一個 review command 落地後）
- 不抽出 `codex-call` 成獨立 dependency（短期內直接 reference `parallel-ai-agents` 既有 binary）
- 不支援 Windows（macOS only）
- 不寫獨立 README.md（CLAUDE.md 已能擔任入口）
- 不做自動安裝 / 自動修復 — setup 只回報狀態，不執行任何 mutating 行為

## Decisions

### D1: Plugin manifest 採 .claude-plugin/plugin.json

採用 Claude Code 既有的 `.claude-plugin/plugin.json` manifest convention（與 `psychquant-claude-plugins` 既有 plugin 對齊），而非自訂 metadata 檔。內容極簡：`name`、`version`、`description`、`author`。

Alternatives:

- 不放 manifest，僅靠目錄結構：Claude Code 仍能載入，但 `/plugin list` 顯示為 unnamed，影響可發現性。
- 直接放完整 marketplace 結構：本 change 不發佈，過度工程。

### D2: Skill 命名為 setup 對齊命令名後綴

Skill 目錄名 `setup` 對應 `/codex-pro:setup` 命令後綴（plugin 名前綴 `codex-pro` 由 Claude Code 自動加）。SKILL.md 用 YAML frontmatter 含 `name`、`description`、`allowed-tools`，body 寫詳細執行指引。

Alternatives:

- 用 `commands/setup.md` slash command 而非 skill：commands 觸發需顯式輸入完整名稱，skill 可由意圖匹配自動觸發；對 setup 影響不大，但 skill 為後續擴充（如自動 readiness check）更靈活。

### D3: codex-call discovery 走 PATH lookup

setup 用 `command -v codex-call` 探測 wrapper 可呼叫性，而非寫死 `parallel-ai-agents` 內絕對路徑。理由：parallel-ai-agents plugin 安裝時將 `bin/` 加入 PATH，codex-call 應天然可呼叫；寫死路徑會在 user 卸載 / 重組 parallel-ai-agents 時碎裂。

Alternatives:

- 同時嘗試固定 fallback 路徑：若 fallback 可用代表 parallel-ai-agents 安裝異常，遮蓋 setup 的根因偵測能力，且越權繞道違反 D5。

### D4: Readiness report 用 Markdown 表格

報告格式對 user 顯示 markdown 表格，欄位 `Check | Status | Detail | Remediation`。Status 用 ✓ / ✗ / ⚠ 三態。表格後一段總結文字標註 ready 或 N check(s) need attention。

Alternatives:

- 純 JSON：機器可讀但對 user 不友善，且後續 Claude session 仍能解析 markdown 表格。
- 純散文：難掃描、無法 grep。

### D5: Setup 嚴格 read-only

Setup 不執行任何 mutating 行為（不 mkdir、不 touch、不裝 codex CLI、不呼叫 codex login）。所有「缺失項」一律回報 + 提示 user 該執行什麼命令修復。理由：mutating setup 重蹈 `openai/codex-plugin-cc` 的覆轍（user 一開始覺得方便，後續難以 debug 被自動修改的環境）。

Alternatives:

- 提供 `--fix` 旗標自動修復：增加 surface area、引入 mutation 風險，且 codex login 是 user-only 行為（OAuth flow 需 browser），無法真正自動化。

## Implementation Contract

#### Behavior

使用者在 Claude Code 中跑 `/codex-pro:setup`，Claude 觸發 skill 後輸出一份 markdown readiness report，含至少 3 項檢查：

1. Codex OAuth token 檔狀態（`~/.codex/auth.json`）
2. `codex-call` wrapper 在 PATH 中的可呼叫性
3. Plugin self-check：自身 plugin manifest 可被讀取

每項檢查輸出 status / detail / remediation 三欄位。

#### Interface

- Skill 識別符：`setup`
- 對外命令：`/codex-pro:setup`
- 入口檔：`skills/setup/SKILL.md`
- 命令列引數：無
- 副作用：無（read-only）

#### Output shape

Markdown 表格範例：

| Check | Status | Detail | Remediation |
|-------|--------|--------|-------------|
| OAuth token | ✓ / ✗ / ⚠ | 一句現況描述 | 一句修復指引或 N/A |
| codex-call wrapper | ✓ / ✗ / ⚠ | 一句現況描述 | 一句修復指引或 N/A |
| Plugin manifest | ✓ / ✗ / ⚠ | 一句現況描述 | 一句修復指引或 N/A |

表格後一段總結：「All checks passed — codex-pro ready」或「N check(s) need attention — see Remediation column above」。

#### Failure modes

- OAuth token 不存在：Status ✗，Remediation 指示執行 `codex login`（由 codex CLI 提供）。
- OAuth token 存在但 permission 異常：Status ⚠，Remediation 指示 `chmod 600`。
- codex-call 不在 PATH：Status ✗，Remediation 指示安裝 / 確認 parallel-ai-agents plugin。
- plugin.json 解析失敗：Status ✗，Remediation 指示檢查 syntax。

#### Acceptance criteria

- 乾淨 macOS 開發環境下，`claude --plugin-dir` 掛載本 codex-pro 目錄能成功載入 plugin（plugin 名 `codex-pro` 出現在 `/plugin` 清單）
- `/codex-pro:setup` 觸發後輸出至少 3 列檢查的 markdown 表格
- OAuth token 不存在條件下，對應列 Status ✗，Remediation 明確指向 `codex login`
- 所有檢查通過條件下，總結文字含 "ready" 關鍵字

#### Scope boundaries

In scope:

- Plugin manifest（.claude-plugin/plugin.json）
- Skill 入口（skills/setup/SKILL.md）
- Setup 邏輯：read-only 環境檢查、結構化 report 輸出

Out of scope:

- 任何 `/codex-pro:*` 其他 command
- 獨立 marketplace repo 建立
- Auto-install / auto-repair 行為
- Windows 平台支援
- codex-call wrapper 本身的修改（屬 parallel-ai-agents）

## Risks / Trade-offs

- [parallel-ai-agents 為先決安裝] → setup 在 parallel-ai-agents 缺席時會回報 ✗，並指引 user 去裝。隱含的 install order 依賴將記入 CLAUDE.md（已寫 references 段落）與 setup remediation 文字。
- [codex-call 在 PATH 的偵測依賴 parallel-ai-agents 行為穩定] → 若 parallel-ai-agents 改了 bin/ 暴露方式，setup 可能誤報。Mitigation：D3 已把此假設記為 design 決策，未來 parallel-ai-agents 改動時同步審 setup detection。
- [SKILL.md description 太弱導致無法被意圖匹配自動觸發] → setup 以「使用者明確輸入 /codex-pro:setup」為主路徑、意圖匹配為輔。Mitigation：description 寫明用途 + 列出 trigger keyword（如 "verify codex-pro environment"、"check codex setup"）。
