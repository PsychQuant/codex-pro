## Why

codex-pro 走完 4 個 archive cycle（codex-pro-bootstrap → marketplace-pivot → consolidate-naming → add-batch-skill），目前有 2 個 capability（setup / batch）但**零 automated test**。所有「驗證」都靠 apply phase 的 inline Bash simulation 一次性手動跑、不持久化。

實際痛點：

- 後續 refactor / namespace 微調沒有 regression net
- spec 與實際 file 結構是否一致只能靠 `spectra analyze` 在 propose 階段抓（apply 階段已部署的文件無法檢測）
- batch template 的 byte-identical sha256 紀律仰賴口頭約定、無自動 enforcement
- Cross-skill 共用紀律（namespace 一致、Design constraint #1 exception list）若漂移無告警

引入 test 場景把這些「manual verify」變成「跑 `tests/run.sh` 自動驗」，並把 `Design constraint #1` 的 explicit exception 紀律編碼為 assertion。

## What Changes

- 新增 `tests/` 目錄於 codex-pro root，含 3 個 layer + 共用 lib：
  - **Layer 1 static**: `tests/static.sh` — JSON schema parse（marketplace.json / plugin.json）、SKILL.md frontmatter parse、`bash -n` syntax check、namespace consistency grep、known-good sha256 enforcement
  - **Layer 2 behavioral**: `tests/setup.sh` 與 `tests/batch.sh` — setup 三 check 在 isolated env（fake `HOME`、剝離 `PATH`、mktemp fake plugin root）跑、batch template 完整性與 codex exec invocation 結構驗證
  - **Layer 3 manual**: `tests/e2e-checklist.md` — 手動 e2e 流程（claude --plugin-dir + skill 觸發確認）
- `tests/run.sh` — dispatcher 跑 Layer 1+2，回報 pass/fail count
- `tests/lib/assert.sh` — 共用 assertion helper（`assert_eq`、`assert_contains`、`assert_file`、`assert_sha256`、`assert_exit`、`fail`、`pass`）
- `tests/lib/isolate.sh` — 共用 isolation helper（sub-shell wrappers for `HOME=/nonexistent`、`PATH=` 剝離、mktemp fake plugin root）
- 更新 CLAUDE.md 加 Development workflow 一段「跑 tests/run.sh 前置」
- 更新 README.md 加 "Tests" 段提及 `bash tests/run.sh`

## Capabilities

### New Capabilities

- `tests`: 提供自動化驗證 codex-pro 結構與行為的 test scenarios。涵蓋 (a) Layer 1 static — manifest schema、SKILL frontmatter、shell syntax、namespace consistency、template byte-identical sha256；(b) Layer 2 behavioral — setup 三 check 在 isolated env 重跑、batch template 完整性與 codex exec invocation 結構驗證；(c) Layer 3 manual — e2e checklist。Runner 為 pure Bash + `tests/lib/` 共用 helper，不引入外部 framework（無 bats / pytest 依賴）。

### Modified Capabilities

(none)

## Impact

- Affected specs:
  - New: openspec/specs/tests/spec.md
- Affected code:
  - New:
    - tests/run.sh
    - tests/static.sh
    - tests/setup.sh
    - tests/batch.sh
    - tests/e2e-checklist.md
    - tests/lib/assert.sh
    - tests/lib/isolate.sh
  - Modified:
    - CLAUDE.md（Development workflow 段加「實作後跑 tests/run.sh」）
    - README.md（新增 Tests 段）
  - Removed: (none)
- Out of scope（不動）:
  - 不引入 bats / pytest 等 framework
  - 不寫 GitHub Actions CI（local dev 為主、user manual run）
  - 不自動化 e2e TUI（claude --plugin-dir + 模擬輸入過於脆弱）
  - 不變更現有 setup / batch SKILL.md 行為
  - 不修改 spec setup 或 spec batch 內任何 requirement
