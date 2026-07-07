## 1. Skill 目錄與 name field rename（決策：全 9 個 skill 加 codex- prefix（hard cutover、無 alias）；config 選用 codex-config 而非 codex-profile）

- [x] 1.1 用 `git mv` 把 9 個 skill 目錄 `plugins/codex-pro/skills/<name>` 改名為 `plugins/codex-pro/skills/codex-<name>` 並更新每個 `SKILL.md` frontmatter `name:` 欄位，一次履行以下 9 個 registration requirement 的 name / invocation / path 更新：`Plugin local development load`（setup → codex-setup）、`Batch skill registration and parameter collection`（batch → codex-batch）、`Review skill registration and target resolution`（review → codex-review）、`Rescue skill registration and argument parsing`（rescue → codex-rescue）、`Adversarial-review skill registration and argument parsing`（adversarial-review → codex-adversarial-review）、`Status skill registration and argument parsing`（status → codex-status）、`Result skill registration and selection-mode argument parsing`（result → codex-result）、`Cancel skill registration with zero-argument acceptance`（cancel → codex-cancel）、`Config skill registration with zero-argument display`（config → codex-config，非 codex-profile）。行為：9 個 codex- 前綴目錄存在、無舊裸名目錄、每個 SKILL.md `name` 為 codex-<name>。驗證：`ls plugins/codex-pro/skills/` 列出 9 個 codex- 前綴目錄；`grep -h '^name:' plugins/codex-pro/skills/codex-*/SKILL.md` 全部為 codex-<name>。

## 2. Trigger keyword 清理（與 rename 正交、真正解 auto-select 撞名）

- [x] 2.1 依決策「Trigger keyword 清理（與 rename 正交、真正解 auto-select 撞名）」清理各 SKILL.md `description` 的裸泛用 trigger keyword，改成 codex-qualified 詞：`codex-config` 移除 `設定` / `配置` / `settings` / `config`（改 `codex profile` / `codex config` / `which model`）、`codex-status` 移除 `狀態`、`codex-result` 移除 `顯示結果`。行為：使用者詢問系統「設定」時 Claude 不再 auto-select `codex-config`。驗證：`codex-config/SKILL.md` 的 `description` 區塊不含裸 `設定` / `配置`，符合 `Config skill registration with zero-argument display` registration scenario 的「MUST NOT contain 設定/配置」assertion。

## 3. Live 交叉引用機械 sweep（決策：Spec delta 只涵蓋 registration requirement、其餘 invocation 字串機械 sweep；Archive 凍結、不參與 rename）

- [x] 3.1 依決策「Spec delta 只涵蓋 registration requirement、其餘 invocation 字串機械 sweep」sweep 全部 live `/codex-pro:<bare-name>` invocation 字串為 `/codex-pro:codex-<name>`，涵蓋：9 個 SKILL.md 的 skill 間交叉引用、`README.md`、`plugins/codex-pro/.claude-plugin/plugin.json` prose、`openspec/specs/*/spec.md` 各 spec 的非 registration scenario prose、`openspec/specs/tests/spec.md`、`openspec/specs/e2e-tests/spec.md`、`openspec/changes/harden-producer-heading-reliability/design.md`。所有 sweep 命令 **MUST** 顯式 `grep -v 'openspec/changes/archive/'`（決策：Archive 凍結、不參與 rename）。**不改** result-file prefix 與 status/result 的 `--skill` enum（bare producer 識別碼）。行為：live 檔案無舊裸 skill 名 invocation、archive 未被觸及。驗證：`grep -rn '/codex-pro:\(setup\|batch\|review\|rescue\|adversarial-review\|status\|result\|cancel\|config\)\b' .`（排除 archive）零命中。

## 4. CLAUDE.md 命名慣例反轉並記錄理由

- [x] 4.1 依決策「CLAUDE.md 命名慣例反轉並記錄理由」改寫 `CLAUDE.md` 命名慣例段（現「所有 skill 觸發名統一形如 `/codex-pro:<skill>` bare-name、此為 final naming convention、無下次 reverse 計畫」）為 `codex-` prefix 慣例並記錄「為何反轉」；同步 CLAUDE.md 的 marketplace structure 說明與 commands surface 對照表 skill 名為 codex-prefixed。行為：CLAUDE.md 描述的慣例與實際 codex-prefixed skill 一致、含反轉理由。驗證：`grep 'final naming convention'` 舊句已不存在；commands surface 表列 codex-prefixed 名。

## 5. Tests 更新與 acceptance gate（決策：Spectra capability spec 目錄不改名（Option A、refine discuss 假設 5））

- [x] 5.1 更新 tests 期望值：`tests/static.sh` 的 namespace consistency grep 改期望 codex-prefixed skill 名、`tests/result.sh` / `tests/status.sh` 內引用的 skill 名、`tests/e2e-checklist.md` scenario、`tests/lib/e2e-claude-print.sh`。行為：test 期望值與 codex-prefixed skill 一致。驗證：`bash tests/run.sh` exit 0、aggregate 全綠。
- [x] 5.2 執行三項 acceptance gate 並確認決策「Spectra capability spec 目錄不改名（Option A、refine discuss 假設 5）」落實：(a) `bash tests/run.sh` exit 0 全綠；(b) `grep -rn '/codex-pro:\(setup\|batch\|review\|rescue\|adversarial-review\|status\|result\|cancel\|config\)\b'`（排除 archive）零命中；(c) 9 個 `plugins/codex-pro/skills/codex-*/SKILL.md` 皆存在。行為：整個 rename 一致、無 stale 引用、archive 未被觸及、`openspec/specs/` 目錄名未改。驗證：三項 gate 全過；`git status` 確認 `openspec/changes/archive/` 與 `openspec/specs/` 目錄名無改動。

## 6. Spectra artifact 一致性驗證

- [x] 6.1 跑 `spectra validate rename-skills-codex-prefix` 與 `spectra analyze rename-skills-codex-prefix --json` 確認 change artifacts 一致、無 Critical/Warning。行為：change 通過 Spectra 驗證。驗證：`spectra validate` exit 0。
