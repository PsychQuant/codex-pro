## Why

codex-pro v0.4.0 ship 9 skills、290 Layer 2 assertions、6 archive cycle 累積 SKILL.md-based runtime contract。但 v0.4 producer cycle 暴露一個 **structural blind spot**：tests/review.sh + tests/adversarial-review.sh 內部 implement 了 `collect_review_target` / `collect_adv_review_target` bash function 跑 behavioral fixture — 測試驗的是 test script 自己 implement 的版本、**不是 SKILL.md prose 被 Claude Code 真正解讀執行的版本**。兩邊邏輯若 drift（SKILL.md 寫「64KB」但 Claude 解讀為 65536 byte 與測試假設不同、SKILL.md 描述「post-filter pre-flight」但 Claude 跳過 filter 步驟直接送 empty prompt 等），Layer 2 不會抓。

這是與 rescue v0.1 `--session` 同類風險：v0.1 SKILL.md prose 寫了一個 codex-call 不存在的 flag、Layer 2 全綠 ship、實際 runtime broken。當時補救是 [[feedback-codex-pro-smoke-before-archive]] memory + pre-archive smoke gate（手動跑 1 次 real codex-call）。但 smoke gate 也是「手動 build prompt file 模擬 SKILL.md 意圖」、不是真的觸發 `claude --print` 讓 Claude 讀 SKILL.md 拼出 invocation。

**Real e2e gap**：沒人測「Claude Code 拿 SKILL.md 進來、真的拼出對的 invocation 邏輯、結果檔結構正確」。e2e 補上這個層級。

本 change 引入 **Layer 3 自動化 e2e**（補 Layer 1 static / Layer 2 behavioral 之上）：`tests/e2e.sh` 標準 script 在 fresh `claude --print --plugin-dir` session 觸發 `/codex-pro:<skill>` 跑 real SKILL.md invocation、驗 `.codex-pro/<skill>-<ts>.md` result file 結構與內容。Opt-in（不進 default `tests/run.sh`、因為每跑一個 fixture = 1 codex-call quota + ~50k Claude API tokens + 受 Anthropic API rate limit 干擾）。Pre-release 跑、平時靠 Layer 1+2。

Workflow synthesis (wqfvs53aw) 沒 surface 本 candidate — 因為 critic 焦點在 codex-pro skill 缺漏 / 上游 codex-call 缺漏，沒涵蓋「test infrastructure layer 缺漏」。但 v0.4 apply 過程中 user 問「你有寫完整的 test 嗎」、honest answer 揭露這個 gap、用戶選擇 full Spectra cycle 補。

## What Changes

- 新增 `tests/e2e.sh` 標準 script：
  - Usage: `bash tests/e2e.sh --skill <review|adversarial-review> --scenario <mixed|binary|oversize|empty-repo|all-empty>` （任一 skill × 任一 scenario）
  - Steps:
    1. mktemp + `assert_git_fixture` 建 fixture repo
    2. 依 `--scenario` 寫對應 fixture file（mixed = tracked modified + untracked normal；binary = untracked .png with NUL bytes；oversize = 100KB .log；empty-repo = fresh `git init` + 1 untracked；all-empty = empty repo + binary-only）
    3. cd 進 fixture、跑 `timeout 600 claude --print --plugin-dir <codex-pro plugin path> "/codex-pro:<skill>"`
    4. Verify post-invocation：(a) Claude session exit 0、(b) `.codex-pro/<skill>-<ISO8601>.md` 存在於 fixture、(c) frontmatter 含 expected `target` marker（含 `pre-first-commit` for empty-repo scenario）、(d) success scenario body 含 expected sections (review = `## Summary` + `## Findings`、adversarial-review = 4 mandatory H2 sections each non-empty)、(e) target_invalid scenario frontmatter 含 `error: target_invalid`、`findings_count: 0`、(f) skill 行為驗證 — mixed scenario 結果含 untracked path 字串、binary scenario 含 `### Untracked binaries omitted` heading、oversize scenario 含 `truncated at 64KB` marker
- 新增 `tests/lib/e2e-claude-print.sh` helper：抽 `invoke_skill_via_claude_print` function（接 fixture dir + skill name + scenario、處理 retry on rate limit、return exit code + 路徑指 result file）、跑 `claude --print` 含 retry policy（最多 3 次、exponential backoff 30s / 60s / 120s on `Server is temporarily limiting requests` 字串）。
- 新增 `tests/lib/e2e-fixtures.sh` helper：抽 `e2e_fixture_<scenario>` function（5 個 scenario 各對應一 helper、共用 assert_git_fixture + scenario-specific file content）— DRY pattern 共用於 Layer 2 behavioral 與 Layer 3 e2e。
- 更新 `tests/e2e-checklist.md`：手動 checklist 改為「跑 `bash tests/e2e.sh --skill <name> --scenario <name>` 各 5 × 2 = 10 組合」+ 預估 quota / 時間 / rate limit recovery 操作指引。
- 更新 `tests/run.sh`：**不**自動跑 e2e（quota cost + rate limit flakiness）；header comment 註明 Layer 1+2 = `bash tests/run.sh`、Layer 3 = `bash tests/e2e.sh --skill X --scenario Y` opt-in per release。
- 更新 CLAUDE.md Test section：3 layer 設計表加 Layer 3 row（10 scenarios、opt-in、~10 codex-call quota + ~500k Claude API tokens 預估、pre-release 跑）。
- 更新 README.md Tests 段：列 Layer 3 opt-in 為 release gate。

## Non-Goals

- 不把 e2e 加進 default `tests/run.sh`（quota cost ~10 codex-call per full run + Anthropic API rate limit flakiness）
- 不取代 Layer 2 behavioral test（兩者 complementary：Layer 2 = test script 自己 implement 邏輯跑 fixture / Layer 3 = Claude 跑 SKILL.md prose 觸發 real invocation；後者抓前者抓不到的 SKILL→runtime drift）
- 不取代 pre-archive smoke（per [[feedback-codex-pro-smoke-before-archive]] memory）— smoke = 手動 1 次 per archive、e2e = automated 10 組合 per release。兩者 different cadence + different verification surface
- 不對 setup / batch / rescue / status / result / cancel 寫 e2e 測試（v0.4 限定 review + adversarial-review、reason：(a) 兩 producer skill 改動最多、blind spot 最關鍵；(b) 其他 skill 是 read-only consumer 或 environment check、Layer 2 behavioral 已涵蓋；rescue 為 task delegation、e2e 需要 LLM 對話對 Codex prompt 為非確定性、e2e verification 困難；batch 為 explicit exception、fan-out 行為 e2e 化代價高且不解 v0.4 driver bug）
- 不引入 LLM output content 驗證（除了「section heading 存在」、「path 字串存在」、「marker 字串存在」這類 structural check）— Codex output 為非確定性、不 assert wording
- 不引入 CI 整合 / GitHub Actions e2e workflow（v0.1 scope）— 本 change 為 local-only opt-in
- 不改變 SKILL.md 任一個（read-only consumer 從 SKILL.md prose 跑 Layer 3 invocation、不 mutate SKILL.md to ease testing）
- 不引入 new runtime dependency（純 Bash + 既有 `claude` CLI + 既有 `assert_git_fixture` + 既有 `codex-call`）
- 不寫 Windows 支援（macOS only 沿用）
- 不擴 e2e 到 `--base <ref>` mode 或 positional file mode（v0.1 限定 `--diff` default mode、reason：v0.4 fix 只動 default `--diff` mode）

## Capabilities

### New Capabilities

- `e2e-tests`: 提供 Layer 3 e2e test infrastructure — `tests/e2e.sh` standalone opt-in script 在 fresh `claude --print --plugin-dir` session 觸發 `/codex-pro:review` 或 `/codex-pro:adversarial-review` 跑 real SKILL.md invocation、5 fixture scenario × 2 skill = 10 組合、每組合 verify result file 結構 + frontmatter marker + behavioral content（untracked path / binary heading / truncation marker）；含 retry policy 處理 Anthropic API rate limit；含 `tests/lib/e2e-claude-print.sh` + `tests/lib/e2e-fixtures.sh` helper；不進 default `tests/run.sh`、pre-release 跑為 release gate。

### Modified Capabilities

(none — 不修任一 producer / consumer skill 的 spec)

## Impact

- Affected specs:
  - New:
    - openspec/specs/e2e-tests/spec.md
- Affected code:
  - New:
    - tests/e2e.sh（main standalone opt-in script）
    - tests/lib/e2e-claude-print.sh（invoke_skill_via_claude_print helper + retry policy）
    - tests/lib/e2e-fixtures.sh（5 scenario fixture helpers）
  - Modified:
    - tests/e2e-checklist.md（Layer 3 procedural checklist 改為跑 e2e.sh、含 quota / 時間 / rate limit 指引）
    - tests/run.sh（header comment 加 Layer 3 opt-in 註明）
    - CLAUDE.md（Tests 段 3 layer 設計表加 Layer 3 row）
    - README.md（Tests 段加 Layer 3 opt-in 描述）
  - Removed: (none)
- Test net delta: 290 Layer 1+2 assertions 不變；Layer 3 e2e 為新 axis、每 pre-release 跑 10 組合（5 scenario × 2 skill）— 不入 aggregate count（不同 cadence）
- Quota budget: 每 full Layer 3 pass ~10 codex-call + ~500k Claude API tokens（pre-release 跑 1-2 次預估 $0.50-$2 + 10 codex quota）
- Cross-repo impact: none（純 codex-pro repo 內）
- Runtime dependency: 無新增；用既有 `claude` CLI（已假設 user 已 install）+ `codex-call`（已假設 PATH）+ `assert_git_fixture`（已存在）
- Cross-cycle discipline impact:
  - **本 change 為 first Layer 3 automated test cycle** — 過去 Layer 3 是 manual checklist；本 change script 化 procedural
  - 不取代 [[feedback-codex-pro-smoke-before-archive]] discipline — smoke gate 仍適用每次 producer skill change archive；e2e 是 pre-release gate（後續 cycle 用 e2e 替代 smoke 待評估、v0.4.x 不 commit）
  - Discipline 配對：Layer 1 static = manifest correctness、Layer 2 behavioral = test script 自 implement 邏輯驗 fixture、Layer 3 e2e = Claude 跑 SKILL.md prose 驗 real invocation；三 layer cumulative coverage、不彼此取代
- Estimated size: **single-cycle**（5 fixture × 2 skill = 10 e2e scenario + 2 helper script + 1 main script + 4 doc update + 1 spec；apply 工作量類似 status-result-cancel triple cycle）
