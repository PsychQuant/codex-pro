## Context

issue #2 起於 `/codex-pro:config` 與系統「設定」/ 內建 `/config` 撞名。diagnose + discuss 後 scope 擴大為「全 9 skill 加 `codex-` prefix」的命名慣例變更。

現狀：codex-pro 有 9 個 skill（setup / batch / review / rescue / adversarial-review / status / result / cancel / config），觸發名皆為 bare `/codex-pro:<skill>`。這些名字全部是泛用單字。`openspec/specs/*` 有 per-skill frozen spec，其中 7 個（config / review / rescue / adversarial-review / status / result / cancel）的 registration requirement 明文 pin 了 frontmatter `name:`、invocation、SKILL.md 路徑；config 額外 pin 了 trigger keyword（含 `設定 / 配置`）。live 引用 188 refs（~27 檔）；archive 另有 295 refs（凍結）。

約束：`archive-first` plugin 保護 `openspec/changes/archive/**`；`.spectra.yaml` 啟用 tdd / audit / parallel_tasks / worktree；locale=tw（spec 一律英文）。專案 CLAUDE.md 明訂 namespace 變更走 Spectra，且已有 `consolidate-naming` / `marketplace-pivot` 先例。

## Goals / Non-Goals

**Goals:**
- 9 個 skill 觸發名統一為 `/codex-pro:codex-<skill>`，消除與系統命令的語意撞名。
- 清理各 skill description 的泛用 trigger keyword，消除 Claude auto-select 誤觸（issue #2 的實際痛點）。
- 更新受影響的 live 引用（SKILL.md / docs / tests / 9 個 spec registration requirement），保持家族一致。
- 反轉並重寫 CLAUDE.md 的舊命名慣例，記錄反轉理由。

**Non-Goals:**
- 不改任何 skill 的功能行為（純命名 + keyword，config keyword 場景是唯一「觸發行為」變更）。
- 不提供舊名 alias / deprecation shim（hard cutover）。
- 不 rename `openspec/specs/*` capability 目錄（見決策）。
- 不動 `openspec/changes/archive/**`（凍結）。
- 不新增 skill、不改 profile schema、不碰 in-progress change `harden-producer-heading-reliability` 的功能（僅其 design.md 內 1 個引用字串隨 sweep 更新）。

## Decisions

### 全 9 個 skill 加 codex- prefix（hard cutover、無 alias）
**選擇**：9 個 skill 目錄與 invocation 名全部前綴 `codex-`，舊名直接消失。
**理由**：9 個名字全部泛用（不只 config），一致修全部比特例修 config 乾淨；專案早期、local dev 為主、對外採用低 → 現在斷最省，refs 之後只增不減。接受 `codex-pro:codex-*` 的視覺冗餘作為 distinctiveness 的成本。
**Alternatives**：只 rename config（Minimal）—— discuss 已否決，因其餘 8 名同樣泛用易撞。保留舊名 alias —— 否決，Claude Code skill 為目錄探索、alias 需複製目錄或 symlink，維護成本 > 早期斷裂成本。

### Trigger keyword 清理（與 rename 正交、真正解 auto-select 撞名）
**選擇**：各 SKILL.md description 移除裸泛用詞（`設定 / 配置 / settings / config / status / result` 等），改成 codex-qualified 詞。
**理由**：Claude Code 永遠顯示 namespace，rename 對「Claude 憑 keyword 誤選」幾乎無效；真正防誤觸的是 description 的觸發詞。此步與 rename 獨立，即使不 rename 也該做 —— 是 issue #2 的實際 fix。
**Alternatives**：只靠 rename 防撞 —— 否決，keyword 不動則誤選照舊。

### config 選用 codex-config 而非 codex-profile
**選擇**：config → `codex-config`（機械式 prefix、零特例）。
**理由**：維持「prefix + 現有名」單一規則，全家族可預測；「config」是使用者尋找「設定 codex-pro」的自然詞，具 discovery 價值。真正的去撞名靠 keyword 清理 + namespace，非名稱 token。
**Alternatives**：`codex-profile`（語意更準 —— skill 是 read-only 顯示 profile.yaml、不 configure，且徹底丟掉 `config` token）—— 否決，因它把 config 變成唯一被語意改名的特例，破壞一致規則。此為 discuss 已定案項，記錄備查。

### Spectra capability spec 目錄不改名（Option A、refine discuss 假設 5）
**選擇**：保留 `openspec/specs/*` capability 目錄名不變（`config` / `review` …），只改 spec 內容。
**理由**：Spectra 的 capability 身分 = spec 目錄名。rename 目錄 = REMOVED + ADDED delta、斷 `@trace source:` 連續性、且 archived changes 仍引用舊 capability 名（凍結不可改）。skill↔spec 的 1:1 在邏輯上仍保留（一 skill 一 spec），僅 capability-id 與 invocation-name 解耦一層（如同內部 module 名不隨 CLI 命令改名）。
**⚠ 對 discuss 的 refine**：discuss 假設 5 原文「spec 目錄 lockstep rename」；此決策**細化為「不改目錄、只改內容」**，因 propose 階段才發現 Spectra capability-rename 的實際成本。使用者可於 apply 前 override。
**Alternatives**：lockstep rename 目錄 —— 否決成本如上。

### Spec delta 只涵蓋 registration requirement、其餘 invocation 字串機械 sweep
**選擇**：9 個 spec delta 各 MODIFY 該 skill 的 registration requirement（name / invocation / path pin；config 額外含 keyword 場景）。其餘 requirement 的 scenario 內 invocation 字串屬 illustrative，於 apply 期隨全域機械 sweep 一併更新。
**理由**：registration requirement 是唯一 normative 的命名 contract；把每個 spec 的全部 requirement 都 reproduce 成 delta（~1500 行近重複）對純 rename 不成比例且易 typo。
**Alternatives**：全 requirement reproduce delta —— 否決，體量與錯誤風險過高。完全不碰 spec scenario 字串 —— 否決，留下 spec 內部 stale 引用。

### Archive 凍結、不參與 rename
**選擇**：`openspec/changes/archive/**`（295 refs）一律不動。
**理由**：歷史記錄當時真相 + `archive-first` 保護。機械 sweep 必須排除 archive 路徑。
**Alternatives**：全掃 481 refs —— 否決，破壞歷史 + 觸發保護 hook。

### CLAUDE.md 命名慣例反轉並記錄理由
**選擇**：改寫 CLAUDE.md 現有「`/codex-pro:<skill>` bare-name、final convention、無 reverse 計畫」段，改為 `codex-` prefix 慣例，並在同段誠實註記「為何反轉」。
**理由**：舊慣例是 premature 的「final」宣告；反轉需留痕，避免未來讀者困惑。
**Alternatives**：不改 CLAUDE.md —— 否決，慣例文件與實際不符會誤導 future skill authors。

## Implementation Contract

**Behavior（使用者可觀察）**：
- 9 個 skill 只能以 `/codex-pro:codex-<skill>` 觸發；舊名 `/codex-pro:<skill>` 不再存在。
- 使用者詢問系統「設定」時，Claude 不再 auto-select `codex-config`（description 已無泛用觸發詞）。

**Interface / data shape**：
- 每個 skill 目錄：`plugins/codex-pro/skills/codex-<skill>/SKILL.md`。
- 每個 SKILL.md frontmatter `name:` = `codex-<skill>`。
- 每個對應 spec 的 registration requirement：name/invocation/path 均為 codex-prefixed；config 的 keyword 場景不再要求含 `設定 / 配置`。

**Failure modes**：
- `bash tests/run.sh` 必須全綠（Layer 1 static 的 namespace consistency grep 須更新為 codex-prefixed 期望值，否則會 fail）。
- e2e 走 `claude --print --plugin-dir` 觸發新名；`tests/e2e-checklist.md` scenario 名同步。

**Acceptance criteria**：
- `bash tests/run.sh` exit 0、aggregate 全綠。
- `grep -rn '/codex-pro:<bare-name>'`（排除 archive）對 9 個舊裸名應為零命中（live 檔案）。
- 9 個 `plugins/codex-pro/skills/codex-*/SKILL.md` 存在且 frontmatter name 正確。
- config description 不含裸 `設定 / 配置 / settings / config` 觸發詞。

**Scope boundaries**：
- **In scope**：9 skill 目錄改名、9 SKILL.md（name + keyword + 交叉引用）、188 個 live `/codex-pro:` 引用、9 個 spec registration delta、CLAUDE.md 慣例段、README、tests（static/result/status/e2e-checklist/e2e-claude-print）、specs/tests + specs/e2e-tests 的 skill 名引用、harden-producer-heading-reliability/design.md 的 1 個引用字串。
- **Out of scope**：archive/**、spec capability 目錄改名、任何功能行為變更、alias/shim、profile schema。
- **內部 artifact 識別碼維持 bare 名**（scope boundary）：result-file 檔名 prefix（`review-` / `rescue-` / `adversarial-review-`）與 status/result 的 `--skill` enum 值綁定 producer 輸出邏輯；因本變更「不改 producer 輸出」，這些**維持 bare producer 名**（與 invocation-name 解耦，同 Option A 精神）。已知副作用：`/codex-pro:codex-status --skill review`（skill 名 codex-status 但 filter token bare review）—— 可留待未來「內部一致性」follow-up 對齊。

## Risks / Trade-offs

- [漏改某個 live 交叉引用 → 家族不一致] → mitigation：`tests/static.sh` namespace consistency grep 更新為 codex-prefixed 期望；apply 後 grep 舊裸名零命中作 acceptance gate。
- [機械 sweep 誤觸 archive → 破壞歷史記錄] → mitigation：所有 sweep 命令顯式 `grep -v 'openspec/changes/archive/'`；`archive-first` hook 為第二道防線。
- [spec scenario 字串 sweep 造成 Spectra drift 疑慮] → mitigation：registration requirement 走正式 delta；scenario 字串屬 illustrative、sweep 為 rename 的一致性收尾，非新 contract，記錄於本決策。
- [`codex-pro:codex-*` 冗餘未來被嫌] → mitigation：已知取捨、換取 distinctiveness；早期定案。
- [Option A 與 discuss 假設 5 字面不符] → mitigation：本 design 明記 refine + 使用者 apply 前可 override。

## Migration Plan

Hard cutover，單一 change 內完成。Rollback = `git revert` 該 change 的 commits（worktree 隔離、未 merge 前直接棄 branch）。無資料遷移、無外部相依。

## Open Questions

- **spec 目錄是否真的不改名（Option A）**：已於決策採 Option A 並標為 refine discuss 假設 5，待使用者 apply 前最終確認；若堅持 lockstep rename，需改採 REMOVED+ADDED delta 策略、成本上升。
- 其餘（config 名、keyword 政策、hard cutover）discuss 已定案，無 open。
