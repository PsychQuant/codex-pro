## Why

`/codex-pro:config` 的 skill 名稱 `config` 與系統「設定」/ 內建 `/config` 語意撞名（issue #2）。根因有二：名稱 token 泛用、以及 SKILL.md description 的 trigger keyword 含 `設定 / 配置 / settings / config` 導致 Claude 在無關情境 auto-select 此 skill。進一步發現 9 個 skill 名（setup / status / review / result / cancel / config / batch 等）全部是泛用單字、同樣易與其他 plugin 或系統命令撞 —— 趁專案早期（local dev 為主、對外採用低）一次統一為 `codex-` prefix 命名慣例，成本最低（refs 之後只會更多）。

## What Changes

- **9 個 skill 全部加 `codex-` prefix**（**BREAKING** — invocation 名全變、無 alias、hard cutover）。對照：setup→codex-setup、batch→codex-batch、review→codex-review、rescue→codex-rescue、adversarial-review→codex-adversarial-review、status→codex-status、result→codex-result、cancel→codex-cancel、config→codex-config。
- **Trigger keyword 清理**（真正解 issue #2 auto-select 撞名的一步、與 rename 正交）：各 SKILL.md description 去掉裸泛用詞（`設定 / 配置 / settings / config` 等），改成 codex-qualified 詞（如 codex profile、codex config、which model）。config spec 的 keyword 場景同步收斂 —— 這是本變更中唯一含「觸發行為」contract 變更的 spec。
- **9 個 skill spec 的 registration requirement 更新**：`name` field、invocation、SKILL.md 路徑改為 codex-prefixed。
- **CLAUDE.md 命名慣例段改寫**：反轉現有「所有 skill 觸發名統一形如 `/codex-pro:<skill>` bare-name、此為 final naming convention、無下次 reverse 計畫」，改為 `codex-` prefix 慣例，並誠實記錄「為何反轉」。
- **Spectra capability spec 目錄名不變**（Option A、細節見 design.md）：只改 spec 內容，不 rename `openspec/specs/*` 目錄，以保留 `@trace` 連續性與 archived changes 的引用正確性。
- **Archive 凍結**：`openspec/changes/archive/**`（295 refs）一律不動 —— 歷史記錄 + archive-first 保護。

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `config`: registration requirement 的 name/invocation/path 改為 codex-config；trigger-keyword 場景移除 `設定 / 配置` 泛用詞（唯一含觸發行為變更的 spec）
- `review`: registration requirement 改為 codex-review
- `rescue`: registration requirement 改為 codex-rescue
- `adversarial-review`: registration requirement 改為 codex-adversarial-review
- `setup`: registration requirement 改為 codex-setup
- `status`: registration requirement 改為 codex-status
- `result`: registration requirement 改為 codex-result
- `cancel`: registration requirement 改為 codex-cancel
- `batch`: registration requirement 改為 codex-batch

## Impact

- Affected specs: config / review / rescue / adversarial-review / setup / status / result / cancel / batch（9 個 registration requirement；config 額外含 keyword 場景）
- Affected code:
  - Modified:
    - plugins/codex-pro/skills（9 個 skill 子目錄改名為 codex-prefixed，含各 SKILL.md 的 name field、description keyword、skill 間交叉引用）
    - CLAUDE.md
    - README.md
    - plugins/codex-pro/.claude-plugin/plugin.json
    - tests/static.sh
    - tests/result.sh
    - tests/status.sh
    - tests/e2e-checklist.md
    - tests/lib/e2e-claude-print.sh
    - openspec/specs（9 個 skill spec 的 registration requirement 經 delta 更新；其餘 scenario invocation 字串經機械 sweep）
    - openspec/specs/tests/spec.md
    - openspec/specs/e2e-tests/spec.md
    - openspec/changes/harden-producer-heading-reliability/design.md
  - New: (none)
  - Removed: (none — 目錄改名非刪除；archive 不動)
