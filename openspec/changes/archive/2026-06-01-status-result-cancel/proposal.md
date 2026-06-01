## Why

codex-pro v0.2.0 ship 了三個 producer skill（review v0.1 / rescue v0.1.1 / adversarial-review v0.1），三者都把結果寫入 `.codex-pro/<skill>-<ISO8601-timestamp>.md` 結構化 disk 檔案、frontmatter schema 各自不同但都遵守 YAML frontmatter + Markdown body 的契約。這些 result file 是 producer 端 dogfood 的成熟產物 — 但目前 user 必須手動 `ls .codex-pro/`、`cat <file>` 才能查看 / 比對 / 找最近一次 review。Triple skill `status / result / cancel` 為 codex-plugin-cc drop-in surface 的最後三個未落地 command、selected as workflow #2 next pick from 2026-06-01 ultracode synthesis（#1 adversarial-review 已 ship、#3 review-v2-ensemble blocked on upstream codex-call session flag、#4 jobs-status refuted on Constraint #1 violation）。

本 change ship triple consumer surface 完成 codex-plugin-cc drop-in 對標的最後三 row。三個 skill 都是 **read-only file ops、無 codex-call invocation**、與 setup（read-only env check）同屬 codex-pro 的 read-only category（vs review / rescue / adversarial-review 的 mutating-write producer category、vs batch 的 codex exec exception）。

Cancel 在 codex-pro stateless single-shot 模型下無法真正 cancel — codex-call 是同步 HTTPS round-trip、無 background job、無 PID 可殺、無 upstream chatgpt.com cancel API；workflow #4 jobs-status 被 refuted 的同樣理由也適用 cancel。但因為 codex-plugin-cc 上游有 `/codex:cancel` row、drop-in 命名表面完整為使用者轉場降低成本、本 change 把 `/codex-pro:cancel` 實作為 **informational read-only no-op** — 不偷偷 SIGTERM 任何 PID、不假裝能 cancel、而是顯式輸出「codex-pro v0.2 stateless — 請 Ctrl-C 未完成的 call / 等 --max-time 600 timeout / 未來若推 background job mode 再 restore real cancel」並提供 remediation 提示。Cancel 為「displayed limitation」而非「silent stub」、消除 observability lie 的同時維持 drop-in 命令完整性。

## What Changes

- 新增 `/codex-pro:status` skill：`plugins/codex-pro/skills/status/SKILL.md`
  - 掃 `.codex-pro/*.md`、parse frontmatter、輸出 table 格式 summary（columns：`filename` / `skill type`（review / rescue / adversarial-review）/ `target` / `outcome 或 findings_count 或 4-section status` / `timestamp` / `error`（若有））
  - 支援 `--skill <review|rescue|adversarial-review>` filter（v0.1 minimal、只 by skill type）
  - Empty `.codex-pro/` → 印「No result files found（過去未跑過 review / rescue / adversarial-review）」、不 abort
  - `.codex-pro/` 目錄不存在 → 印「`.codex-pro/` not yet created（任一 producer skill 首次跑會建）」、不 abort、exit 0（read-only friendly）
- 新增 `/codex-pro:result` skill：`plugins/codex-pro/skills/result/SKILL.md`
  - 顯示特定 result file 完整內容（frontmatter + body）
  - 三種 selection mode：(a) 位置參數 `<filename>` 完整檔名（不含 path）、(b) `--latest <skill>` 拿該 skill 最近一次 result file、(c) `--latest` 無 arg 拿全 producer 最近一次
  - File 不存在 / `.codex-pro/` 不存在 → 印錯誤訊息引導跑 status 或 producer skill、exit 非 0、不 silent fallback
- 新增 `/codex-pro:cancel` skill：`plugins/codex-pro/skills/cancel/SKILL.md`
  - **Informational read-only no-op**（不殺 PID、不送 HTTPS、不 mutate disk）
  - 輸出 explainer：「codex-pro v0.2 為 stateless single-shot 模型、codex-call 無 background job、無法 cancel 已送出的 HTTPS request」
  - 列三條 remediation：(1) Ctrl-C 未完成的 codex-call invocation、(2) 等 `--max-time 600` hard timeout、(3) 等 v0.3+ 若推 background job mode 再 restore real cancel
  - Exit 0（不是 error、是 displayed limitation）
- 三 skill 都 **read-only**（無 codex-call、無 subprocess for Codex、無 file mutation 除 stdout）、嚴守 Design constraint #1 trivial adherence（沒 codex 互動）
- 三 skill 同屬 codex-pro 的 **read-only category**（與 setup 同類、與 review / rescue / adversarial-review 的 mutating producer 對比）
- 擴充 `tests/`：新 3 個 Layer 2 script `tests/status.sh` / `tests/result.sh` / `tests/cancel.sh`；tests/run.sh dispatcher 加 3 個 layer（6→9 layers）
- 更新 CLAUDE.md Commands surface 表 `/codex-pro:status` / `:result` / `:cancel` 從「規劃中」改「已落地 v0.1」、Marketplace structure skills 子目錄列表加 3 行
- 更新 README.md What it replaces 表 + Skills 表加 3 row
- 引入新 test 模式：**behavioral runtime test**（用 mktemp 建 fake `.codex-pro/` + write fake result files + invoke skill + verify output）—— 解 [[feedback-codex-pro-smoke-before-archive]] memory 紀律的 Layer 2 string-level blind spot（status/result 是 read-only file ops、可以在 Layer 2 全 runtime 驗、不耗 Codex quota）

## Non-Goals

- 不實作 real cancel（無 PID 可殺、無 upstream cancel API、無 background job state to terminate）
- 不引入 background job mode 給 codex-call（v0.2 stateless 模型不變、未來 v0.3+ 評估）
- 不修改任一 v0.2 producer skill（review v0.1 / rescue v0.1.1 / adversarial-review v0.1 spec 全不動）
- 不改變 result file 寫入 schema（三 consumer skill 只讀、不改 producer）
- 不支援 date range / focus area / outcome enum 過濾（v0.1 minimal、只 `--skill <name>` 過濾）
- 不實作 token / cost / Codex tier observability（codex-call 目前不 surface 這些 field、屬 future codex-call 升級 + v0.3+ scope）
- 不解析 result file body 內容做 statistics / aggregate（純 frontmatter summary + verbatim body display）
- 不 cache / index result files（每次跑 status / result 都重新掃 `.codex-pro/`、保持 single source of truth）
- 不支援 multi-project `.codex-pro/`（cwd 模式、unlike `~/.codex/` global config）
- 不對 result file 做 schema validation / migration（producer 是 trusted、heterogeneous frontmatter accept-as-is）
- 不發 background notification / Telegram / system tray（read-only CLI surface）

## Capabilities

### New Capabilities

- `status`: 提供 `/codex-pro:status` 命令、掃 `.codex-pro/*.md` 並輸出 frontmatter table summary（columns：filename / skill type / target / outcome / timestamp / error），支援 `--skill <name>` filter；read-only file ops、無 codex-call 互動、Layer 2 可 runtime 驗證；empty / missing `.codex-pro/` 為 informational 而非 error。
- `result`: 提供 `/codex-pro:result` 命令、顯示特定 result file 完整內容（frontmatter + body），三種 selection mode：位置 `<filename>` / `--latest <skill>` / `--latest` 無 arg；read-only file ops、unknown file abort with remediation 提示。
- `cancel`: 提供 `/codex-pro:cancel` 命令為 informational read-only no-op、不殺 PID、不送 HTTPS、不 mutate disk；輸出 explainer 段落（為何 codex-pro stateless 不能 cancel）+ 3 條 remediation（Ctrl-C / wait timeout / future background mode）；exit 0；displayed limitation 而非 silent stub。

### Modified Capabilities

(none)

## Impact

- Affected specs:
  - New:
    - openspec/specs/status/spec.md
    - openspec/specs/result/spec.md
    - openspec/specs/cancel/spec.md
- Affected code:
  - New:
    - plugins/codex-pro/skills/status/SKILL.md
    - plugins/codex-pro/skills/result/SKILL.md
    - plugins/codex-pro/skills/cancel/SKILL.md
    - tests/status.sh（behavioral runtime test、mktemp fake .codex-pro/）
    - tests/result.sh（behavioral runtime test、mktemp fake .codex-pro/ + selection mode coverage）
    - tests/cancel.sh（structural test、SKILL.md prose + exit 0 + no-codex-exec invariant）
  - Modified:
    - CLAUDE.md（Commands surface 表三 row：status / result / cancel 從「規劃中」改「已落地 v0.1」+ 備註欄；Marketplace structure 段 skills 子目錄列表加 3 行；新增 read-only category 段落明示 status / result / cancel 與 setup 同屬 read-only）
    - README.md（What it replaces 表三 row；Skills 表三 row；新增「Read-only vs producer skills」說明段）
    - tests/run.sh（dispatcher 6→9 layers）
  - Removed: (none)
- Runtime dependency: 無新增依賴（不用 codex-call、不 spawn subprocess、純 Bash + Read tool）
- Design constraints:
  - #1（No subprocess for Codex）trivially adhered（沒 codex 互動）
  - #2（hard timeout）不適用（read-only file ops 無 long-running call）
  - #3（circuit breaker on rate limit）不適用（沒 codex-call）
  - #4（structured result file）不適用（這三 skill 是 consumer 而非 producer）
  - #5（profile-based config）—— status 的 `--skill <filter>` flag 是輕量 config、未來可擴 profile
  - #6（observability default ON）—— status 本身就是 observability surface；result file 是 detail-level observability surface；cancel 為 informational display
  - #7（macOS only）—— 沿用
- Output side effect: 三 skill 全 read-only、無 file mutation、無 disk write、stdout only
- Test net delta: 149 → ~200（+~17 assertions / skill × 3 = ~51；含 static.sh per-skill loop auto-cover ~9 個 namespace consistency × 3 skill）
- Cross-repo impact: none（不動 parallel-ai-agents、不動 PsychQuant org 其他 repo）
- Cross-skill impact:
  - **codex-pro test design 升級**：本 change 引入 behavioral runtime test（用 mktemp + fake .codex-pro/ + write fake result file + invoke skill + verify stdout/exit），是 Layer 2 第一次跑「實際 invoke skill 邏輯」而非只 grep SKILL.md prose。本 pattern 解 [[feedback-codex-pro-smoke-before-archive]] memory 紀律的 string-level blind spot
  - **mental-model 區隔**：三 skill 屬 read-only category、與 setup 並列；CLAUDE.md / README.md 引入「Read-only consumer skills」分類軸區隔 v0.2 三 producer skill（review/rescue/adversarial-review）+ 1 exception（batch）
- 完成本 change 後：codex-pro 對標 codex-plugin-cc drop-in surface 達 100%（7 個 command 全落地：setup ✓ + batch（無對應、是 codex-pro 自有）+ review ✓ + adversarial-review ✓ + rescue ✓ + status ✓ + result ✓ + cancel ✓）
