<!-- SPECTRA:START v1.3.0 -->

# Spectra Instructions

This project uses Spectra for Spec-Driven Development(SDD). Specs live in `openspec/specs/`, change proposals in `openspec/changes/`.

## Use `$spectra-*` skills when:

- An explicitly requested Spectra decision needs structure → `$spectra-discuss`
- User explicitly requests a Spectra change proposal → `$spectra-propose`
- Continue tasks for an identified change → `$spectra-apply`
- Update requirements or plans for an identified change → `$spectra-ingest`
- Check implementation matches artifacts → `$spectra-verify`
- Review implementation quality and logic issues → `$spectra-review`
- Analyze artifact consistency before coding → `$spectra-analyze`
- Audit security sharp edges → `$spectra-audit`
- Check stale changes before resuming → `$spectra-drift`
- Debug a concrete bug systematically → `$spectra-debug`
- Implementation is done → `$spectra-archive`
- Commit only files related to a specific change → `$spectra-commit`

Explicit skill invocation takes precedence. Apply existing authorization within its unchanged scope.

## Workflow

discuss? → propose → apply ⇄ ingest → verify / review → archive

- `discuss` is optional — skip if requirements are clear
- Requirements change mid-work? Plan mode (`/plan`) → `ingest` → resume `apply`

## Parked Changes

Changes can be parked（暫存）— temporarily moved out of `openspec/changes/`. Parked changes won't appear in `spectra list` but can be found with `spectra list --parked`. To restore: `spectra unpark <name>`. The `$spectra-apply` and `$spectra-ingest` skills disclose parking and restore when the named operation is already explicitly requested; respect a known refusal, otherwise ask for missing authorization.

<!-- SPECTRA:END -->

<!-- 以下內容在 SPECTRA 標記之外——標記內的區塊由 `spectra update` 重新生成，
     寫在裡面會被覆寫。 -->

# codex-pro Skills（Codex）

本 repo 的 skill 有一份手工來源與兩份 Codex 生成 bundle：

| 格式 | 路徑 | 叫用 | Ownership |
|---|---|---|---|
| Claude Code plugin／來源 | `plugins/codex-pro/skills/<name>/SKILL.md` | `/codex-pro:<name>` | 手工維護 |
| Codex 專案內 bundle | `.codex/skills/<name>/SKILL.md` | `$<name>` | 生成 |
| Codex 原生 plugin bundle | `skills/<name>/SKILL.md` | `$<name>` | 生成 |

`scripts/generate-codex-skills.sh` 會從 `plugins/codex-pro/` **單向生成** `.codex/`
與 repo 根層的完整 bundle。兩份都包含 `skills/`、`references/`、`bin/` 與
`.codex-bundle-files`；不要手改這些受管產物。修改 `plugins/codex-pro/skills/`、
`plugins/codex-pro/references/` 或 `plugins/codex-pro/runtime/` 後，執行：

```bash
scripts/generate-codex-skills.sh
bash tests/codex-skills-parity.sh
```

## 可用 skill

| Skill | 用途 |
|---|---|
| `$codex-setup` | 驗證 OAuth、codex-call runtime 是否就緒。**先跑這個** |
| `$codex-status` | 掃 `.codex-pro/*.md` 輸出結果摘要表（read-only、最輕量）|
| `$codex-result` | 顯示特定 result 檔（frontmatter + body verbatim）|
| `$codex-review` | 對 uncommitted diff / file / branch 跑 read-only review |
| `$codex-adversarial-review` | 對設計或 code 跑 hostile challenge（找盲點，非找 bug）|
| `$codex-rescue` | 把單一任務委派給 Codex |
| `$codex-batch` | 平行批次處理大型 reference doc |
| `$codex-config` | 顯示解析後的 profile（model / effort / max_time）|
| `$codex-cancel` | Informational only — 目前為 stateless single-shot |

## ⚠️ 執行前提

| 類別 | Skills | Codex 原生版需求／行為 |
|---|---|---|
| Producer | `$codex-review`、`$codex-adversarial-review`、`$codex-rescue` | macOS、可執行的 Swift、`codex login` OAuth；優先使用 bundle 內 `bin/codex-pro-call`，損壞時 fail-closed |
| Consumer | `$codex-status`、`$codex-result`、`$codex-config`、`$codex-cancel` | 純本機讀取；不需要 macOS、Swift 或 runtime |
| 診斷 | `$codex-setup` | 任何平台都可執行；唯讀檢查 OAuth 與 producer readiness，不連網 |
| Batch 例外 | `$codex-batch` | 使用 `codex exec --full-auto` subprocess 並寫 output dir，不使用 bundle 內 Swift runtime |

釘選 runtime 的手工來源位於 `plugins/codex-pro/runtime/`，resource manifest 只在生成
Codex 原生 bundle 時將它映射成 `bin/codex-call` 與 `bin/codex-pro-call`；不需要安裝
Claude Code 或 `parallel-ai-agents`。手工來源刻意不放在 Claude plugin 自動加入 PATH 的
根層 `bin/`。Claude Code 版維持舊契約：producer 從外部 PATH 解析 `codex-call`，不會
改用 Codex bundle。

原生 CLI 安裝：

```bash
codex plugin marketplace add PsychQuant/codex-pro --ref main --json
codex plugin add codex-pro@codex-pro --json
```

安裝後必須開新 task 讓 Codex 重新探索九個 skill，再先跑 `$codex-setup`。完整的安裝、
更新、producer smoke 與回復流程見 `tests/e2e-checklist.md`；runtime 的 OAuth side effect、
private backend 與已知上游限制見 `README.md`。
