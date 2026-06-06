# Tasks — config-profile-mechanism

實作 codex-pro v0.5：新 `/codex-pro:config` skill（read-only consumer、display resolved profile）+ 3 producer skill（review / rescue / adversarial-review）Step 4 改為 profile-aware。Plugin bump 0.4.0 → 0.5.0。100% backward compatible — 無 profile 時行為與 v0.4 identical。

## 1. config SKILL.md（new）

- [x] 1.1 建立 `plugins/codex-pro/skills/config/SKILL.md` YAML frontmatter（`name: config`、`allowed-tools: [Bash, Read]`、description 含 trigger keywords `profile` / `config` / 設定 / 配置 / `which model` — read-only consumer mental model）。對應 spec **Config skill registration with zero-argument display** "Skill is registered" scenario。Acceptance: tests/static.sh per-skill frontmatter loop pass + grep `profile\|config\|設定\|配置` SKILL.md ≥ 1。
- [x] 1.2 寫入「行為原則 + read-only consumer category」段：明示 4 invariants（無 codex-call / 無 codex exec / 無 file mutation / 不建 ~/.codex-pro/ 或 .codex-pro/）+ 與 setup / status / result / cancel 同 category 對比 + 與 producer / batch 對比。對應 spec **Config invocation is read-only consumer with no Codex interaction** + design **D7: Read-only consumer category invariants enforced**。Acceptance: SKILL body grep `codex-call` = 0、`codex exec` = 0、`mkdir` = 0、`read-only consumer` ≥ 1。
- [x] 1.3 寫入 Step 1 (Resolution algorithm)：明示兩 layer load 順序（global `~/.codex-pro/profile.yaml` → project `<cwd>/.codex-pro/profile.yaml`）+ field-level merge + project override global + missing → hardcoded default + lazy resolution per-invocation。對應 spec **Config profile resolution algorithm — two-layer with project priority** 5 scenarios + design **D1: Two-layer profile (global + project) with project priority, field-level merge** + **D3: Profile resolution algorithm — load global → load project → field merge → hardcoded fallback**。Acceptance: SKILL body grep `~/.codex-pro/profile.yaml` ≥ 1、`.codex-pro/profile.yaml` ≥ 1、`global` + `project` 各 ≥ 1、`默認\|default` ≥ 1。
- [x] 1.4 寫入 Step 2 (Schema v0.1 — 4 fields)：列出 4 field（`model` / `effort` / `max_time` / `focus_default`）+ 各自 type + hardcoded default + which producers use it。對應 spec **Config v0.1 schema is exactly 4 fields** + design **D2: Schema v0.1 = 4 fields**。Acceptance: SKILL body grep 4 field name 各 ≥ 1、grep `gpt-5.5` / `xhigh` / `600` 各 ≥ 1、grep `focus_default` 加 `adversarial-review only` 描述 ≥ 1。
- [x] 1.5 寫入 Step 3 (Output format)：markdown table 4 row + 2 informational line for global / project file 存在性。對應 spec **Zero-argument invocation displays resolved profile** + **Output table has exactly 4 rows in canonical order** scenarios + design **D5: /codex-pro:config skill display semantics**。Acceptance: SKILL body grep `| field | resolved value | source |` ≥ 1、`(default)` ≥ 1、`Global profile:` ≥ 1、`Project profile:` ≥ 1。
- [x] 1.6 寫入 Step 4 (Inline python3 resolution)：完整 inline `python3` block 用 regex YAML parse（避免依賴 PyYAML）+ DEFAULTS map + load helper + merge + sources mapping + table emit。對應 spec **Malformed YAML silently falls back** + **Unknown profile field is silently ignored** scenarios + design **D3 + D4**。Acceptance: SKILL body grep `python3` ≥ 1、`yaml.safe_load` = 0（不依賴 PyYAML）、regex 形式如 `^model:\s*` ≥ 1。
- [x] 1.7 寫入「與 setup / status / result / cancel 的對比」段：4 read-only consumer skill 對比表（Mental model / Argument / Output / File ops）。對應 spec + design **D7**。Acceptance: SKILL body含對比表 + grep `setup` / `status` / `result` / `cancel` 各 ≥ 1。

## 2. tests/config.sh（new）

- [x] 2.1 [P] 建立 `tests/config.sh` 骨架：source `lib/assert.sh`、`assert_file "$CONFIG_SKILL"`、structural 5 條（frontmatter parse、`codex-call` = 0、`codex exec` = 0、`mkdir` = 0、`read-only consumer` ≥ 1）。對應 spec **Config invocation is read-only consumer with no Codex interaction** 2 scenarios。Acceptance: 5 條 structural assertion 全綠。
- [x] 2.2 [P] 加 v0.1 schema marker assertions：grep 4 field name + 4 default value + `focus_default.*adversarial-review` 描述 + table column header。對應 spec **Config v0.1 schema is exactly 4 fields** + **Zero-argument invocation displays resolved profile**。Acceptance: ~10 條 structural assertion 全綠。
- [x] 2.3 [P] 加 behavioral fixture helper `with_fake_profile(global_yaml, project_yaml)`：mktemp HOME + TMP_PROJ、export HOME 指 fake、cd 進 project tmp、write profile YAML files、return function ready for invocation。對應 design **D8: Test fixture pattern — fake `~/.codex-pro/` via tmp HOME**。Acceptance: helper function 定義 + trap cleanup。
- [x] 2.4 [P] 加 5 behavioral scenarios per D8：(1) no-profile → 4 default + 2 (does not exist) lines；(2) global-only `{model: gpt-5.0}` → model=global、others=default；(3) project-only `{max_time: 1200}` → max_time=project；(4) mixed (global model + project max_time) → mixed-source frontmatter aggregate；(5) project-overrides-global (both set model, different) → project wins. 每 scenario invoke `bash tests/config.sh` 或 inline equivalent + verify stdout markdown table 內容。Acceptance: 5 scenario × ~3 assertion = ~15 條 behavioral assertion 全綠。

## 3. review SKILL.md modification

- [x] 3.1 [P] 修改 `plugins/codex-pro/skills/review/SKILL.md` frontmatter description：加入 literal substring `v0.3 — profile-aware`（並存於既有 `v0.2 — untracked-by-default`）。對應 spec **SKILL.md frontmatter announces v0.3 — profile-aware** scenario + design **D2**。Acceptance: `grep "v0.3 — profile-aware" plugins/codex-pro/skills/review/SKILL.md` ≥ 1。
- [x] 3.2 [P] 修改 review SKILL.md Step 4 codex-call invocation：在 codex-call command 之前加 inline `python3` block resolve profile（D4 pseudocode）+ shell-var expansion 替代 hardcoded value（`--model "$MODEL"` 等）。對應 spec **Review invocation uses codex-call HTTPS direct without subprocess for Codex** "Producer reads profile via inline python3 before codex-call" + "codex-call invocation includes hard timeout flag (default 600)" scenarios + design **D4: Producer skill Step 4 modification — read profile + pass resolved value to codex-call**。Acceptance: SKILL body grep `python3` ≥ 1、`~/.codex-pro/profile.yaml` ≥ 1、`.codex-pro/profile.yaml` ≥ 1、`--model "$MODEL"\|--model \$MODEL` ≥ 1、`--max-time "$MAX_TIME"\|--max-time \$MAX_TIME` ≥ 1、`gpt-5.5` ≥ 1（fallback）。
- [x] 3.3 [P] 修改 review SKILL.md Step 5（Handle exit code）result file frontmatter：加 optional `profile_source` field + 描述 4-enum 邏輯（default/global/project/mixed）+ 明示 v0.2 result file 沒此 field 屬 valid（forward-compat）。對應 spec **Review output is a structured Markdown result file** "profile_source frontmatter field reflects resolution source" scenario + design **D6**。Acceptance: SKILL body grep `profile_source` ≥ 1、4 enum 值 (`default` / `global` / `project` / `mixed`) 各 ≥ 1、`backward compat\|v0.2.*valid\|optional` ≥ 1。

## 4. rescue SKILL.md modification

- [x] 4.1 [P] 修改 `plugins/codex-pro/skills/rescue/SKILL.md` frontmatter description：加入 literal substring `v0.2 — profile-aware`。對應 spec **SKILL.md frontmatter announces v0.2 — profile-aware** scenario。Acceptance: `grep "v0.2 — profile-aware" plugins/codex-pro/skills/rescue/SKILL.md` ≥ 1。
- [x] 4.2 [P] 修改 rescue SKILL.md Step 4 codex-call invocation：同 review 3.2 pattern + 確認**不**含 `--resume` / `--fresh` / `--session` 字串（v0.1.1 fix invariant 持續）。對應 spec **Rescue invocation uses codex-call HTTPS direct without subprocess for Codex** "Producer reads profile via inline python3 before codex-call" + "codex-call invocation includes hard timeout flag (default 600)" scenarios（含 MUST NOT reference `--resume` / `--fresh` 子句）+ design **D4**。Acceptance: SKILL body grep `python3` ≥ 1、profile path 兩條 ≥ 1、`--resume` = 0、`--fresh` = 0、`--session` = 0。
- [x] 4.3 [P] 修改 rescue SKILL.md Step 5 result file frontmatter：加 optional `profile_source` field 描述（同 review 3.3）+ 持續記 `resume_from` 已從 v0.1.1 移除（不重 introduce）。對應 spec **Rescue output is a structured Markdown result file** updated 描述。Acceptance: SKILL body grep `profile_source` ≥ 1、`resume_from` = 0（持續移除）。

## 5. adversarial-review SKILL.md modification

- [x] 5.1 [P] 修改 `plugins/codex-pro/skills/adversarial-review/SKILL.md` frontmatter description：加入 literal substring `v0.3 — profile-aware`（並存於既有 `v0.2 — untracked-by-default`）。Acceptance: `grep "v0.3 — profile-aware" plugins/codex-pro/skills/adversarial-review/SKILL.md` ≥ 1。
- [x] 5.2 [P] 修改 adversarial-review SKILL.md Step 4 codex-call invocation：同 review 3.2 pattern + 額外 resolve `focus_default` + Step 3 instructions `<<<USER_FOCUS_START>>>` block content fallback chain（user `--focus <area>` > profile `focus_default` > `(no focus area supplied)`）。對應 spec **Adversarial-review invocation uses codex-call HTTPS direct without subprocess for Codex** "focus_default profile field is used when --focus argument is absent" + "Producer reads profile via inline python3 before codex-call" scenarios + design **D2: Schema v0.1 = 4 fields (model / effort / max_time / focus_default)** focus_default 描述 + design **D4**。Acceptance: SKILL body grep `python3` ≥ 1、`focus_default` ≥ 1、`(no focus area supplied)` ≥ 1（既有）+ 新 fallback 描述明示「user arg > profile > placeholder」≥ 1。
- [x] 5.3 [P] 修改 adversarial-review SKILL.md Step 5 result file frontmatter：加 optional `profile_source` field 描述（同 review 3.3）+ 確認既有「4 mandatory H2 sections each non-empty」屬性不變。對應 spec **Adversarial-review output is a structured Markdown result file with four mandatory non-empty sections** "profile_source frontmatter field reflects resolution source" + "Success case writes structured result file with all four sections non-empty" scenarios + design **D6: Frontmatter `profile_source` field — optional, aggregate enum**。Acceptance: SKILL body grep `profile_source` ≥ 1、4 enum 值 各 ≥ 1。

## 6. tests/review.sh + tests/rescue.sh + tests/adversarial-review.sh extension

- [x] 6.1 [P] 修改 `tests/review.sh` structural：加 `v0.3 — profile-aware` marker assertion + profile python3 pattern assertion（grep `python3` SKILL.md ≥ 1、profile path ≥ 1、`--model "$MODEL"` 或等價 ≥ 1）+ `profile_source` ≥ 1。對應 spec **Producer reads profile via inline python3 before codex-call** + **profile_source frontmatter field**。Acceptance: ~5 條新 assertion 全綠。
- [x] 6.2 [P] 加 `tests/review.sh` behavioral profile scenario：用 D8 fake HOME + fake project profile（`{model: gpt-5.0}`）跑 review collection logic mock + assert SKILL.md 內 documented invocation 套用 `model=gpt-5.0`（或 Layer 2 grep-pattern verify「documented invocation grammar matches profile-aware shape」）。對應 spec **Producer reads profile via inline python3 before codex-call** scenario。Acceptance: ~3 條 behavioral assertion 全綠。
- [x] 6.3 [P] 修改 `tests/rescue.sh` 同 6.1 + 6.2 pattern（標 v0.2 + profile-aware；focus_default 不適用 rescue）。Acceptance: ~6 條新 assertion 全綠 + rescue.sh 仍維持「--resume / --fresh = 0」invariant。
- [x] 6.4 [P] 修改 `tests/adversarial-review.sh` 同 6.1 + 6.2 pattern + 額外 focus_default fallback chain scenario（fake profile `{focus_default: security}` + 無 user `--focus` arg + assert SKILL body documented invocation 套用 profile focus）。對應 spec **focus_default profile field is used when --focus argument is absent**。Acceptance: ~8 條新 assertion 全綠。

## 7. tests/run.sh dispatcher

- [x] 7.1 修改 `tests/run.sh` Execute layers 區塊 在 `run_layer cancel` 之後加 `run_layer config`。Acceptance: `bash tests/run.sh` 後輸出含 `════ Layer: config` 段；aggregate 從 ~293 升至 ~370（±10）；exit 0。

## 8. tests/e2e.sh + tests/lib/e2e-fixtures.sh extension

- [x] 8.1 [P] 修改 `tests/lib/e2e-fixtures.sh` 加 `e2e_fixture_with_profile(dir)` helper：用 `assert_git_fixture` + 寫 fake project `.codex-pro/profile.yaml: {max_time: 900}` + 寫 1 untracked text file（避免 target_invalid）+ 不寫 global profile（這個 scenario 測 project-only override）。Acceptance: helper function 定義 + invokable。
- [x] 8.2 [P] 修改 `tests/e2e.sh` 加 `with-profile` scenario 到 `--scenario` allowlist + case dispatch invoke fixture + verify result file frontmatter `profile_source: project`（all-empty scenario pattern 對應、deterministic）。對應 design **D8 Layer 3 e2e with-profile scenario**。Acceptance: `bash tests/e2e.sh --skill X --scenario with-profile` 為 review + adversarial-review 兩 skill 可 invoke、verify pass on real codex-call run（real run 留 task 12.1 smoke 階段）。
- [x] 8.3 [P] 更新 `tests/e2e-checklist.md` 加 `with-profile` 在 5+1 scenario list + 12 combinations 命令範例 + quota budget 從 ~10 升 ~12 codex-call 預估。Acceptance: `grep "with-profile" tests/e2e-checklist.md` ≥ 1、12 命令各 ≥ 1。

## 9. CLAUDE.md update

- [x] 9.1 修改 `CLAUDE.md` Commands surface 表：加 row `/codex-pro:config` — 已落地 v0.1（read-only consumer — display resolved profile、global + project two-layer、4 field schema v0.1：model / effort / max_time / focus_default）+ 3 producer skill row version update（review v0.2 → v0.3、rescue v0.1.1 → v0.2、adversarial-review v0.2 → v0.3、備註欄加 v0.x 「profile-aware」）。Acceptance: `grep "/codex-pro:config.*v0.1" CLAUDE.md` 命中 + `grep "review.*v0.3" CLAUDE.md` 命中 + `grep "rescue.*v0.2[^.]" CLAUDE.md` 命中 + `grep "adversarial-review.*v0.3" CLAUDE.md` 命中。
- [x] 9.2 修改 CLAUDE.md Marketplace structure 段 skills 子目錄列表：在 `cancel/SKILL.md` 之後加 `config/SKILL.md ← 已落地 v0.1（read-only consumer — display resolved profile）`。Acceptance: `grep "config/SKILL.md" CLAUDE.md` 命中。
- [x] 9.3 修改 CLAUDE.md「Read-only consumer skills（status / result / cancel）」段標題改為「Read-only consumer skills（status / result / cancel / config）」+ 段內表加 config row（屬 read-only consumer category）。對應 design **D7**。Acceptance: `grep "Read-only consumer.*config" CLAUDE.md` 命中。
- [x] 9.4 修改 CLAUDE.md「Design constraints（implementation 期必守）」段 #5 條：原文「Profile-based config — `max-findings` / `sandbox` mode / `model` alias / `focus` 全部可在 profile 配置」加備註「v0.5 部分落地：model / effort / max_time / focus_default 4 fields；max_findings + sandbox 留 future cycle」。Acceptance: `grep "v0.5.*部分落地\|partial" CLAUDE.md` 命中 in Design constraints section。

## 10. README.md update

- [x] 10.1 修改 `README.md` What it replaces 表：加 row `(無對應) | /codex-pro:config — 已落地 v0.1`（codex-plugin-cc 無 `/codex:config` 對應、本 row 顯式為 codex-pro 自有 capability）。Acceptance: `grep "/codex-pro:config" README.md` 命中 + 該 row 包含 `已落地 v0.1` 或 `v0.1.0`。
- [x] 10.2 修改 README.md Skills table：加 row `config (/codex-pro:config) | v0.1.0 | Read-only consumer — display resolved profile（global ~/.codex-pro/profile.yaml + project <cwd>/.codex-pro/profile.yaml two-layer、field-level merge、4 field schema：model / effort / max_time / focus_default）。Hardcoded defaults backward compat。`+ 3 producer row version update。Acceptance: `grep "config.*v0.1.0" README.md` 命中 + 3 producer row 各更新到 v0.3/v0.2/v0.3。
- [x] 10.3 修改 README.md「Read-only vs producer skills」段 list：read-only category list 加 config。Acceptance: 該段 list 含 `config`。

## 11. plugin.json bump

- [x] 11.1 修改 `plugins/codex-pro/.claude-plugin/plugin.json`：version 0.4.0 → 0.5.0；description 加「v0.5: adds /codex-pro:config (read-only consumer, profile-based config mechanism); review v0.3 / rescue v0.2 / adversarial-review v0.3 become profile-aware (model / effort / max_time / focus_default per ~/.codex-pro/profile.yaml or project .codex-pro/profile.yaml; hardcoded defaults backward compat)」；keywords 加 `profile-aware`、`config-profile`、`v0.5`。Acceptance: `python3 -c "import json; print(json.load(open('plugins/codex-pro/.claude-plugin/plugin.json'))['version'])"` 印 `0.5.0`、keywords 含 `profile-aware`。

## 12. 整合驗證 + smoke gates

- [x] 12.1 跑 `bash tests/run.sh` 整套：10 layers green、aggregate ~370 assertions、exit 0。Acceptance: `bash tests/run.sh; echo $?` 印 0；輸出末段 `All layers passed.`。
- [x] 12.2 [smoke MANDATORY per [[feedback-codex-pro-smoke-before-archive]]] 跑 real codex-call smoke on profile-set fixture for `/codex-pro:review`：mktemp HOME + project + write project profile `{max_time: 1200}` + tracked modified file + invoke real codex-call、verify (a) exit 0、(b) result file 落地 with frontmatter `max_time: 1200`（profile 生效）+ `profile_source: project`。對應 design **D4 + D6**。Acceptance: smoke 全綠、profile value 反映 codex-call invocation。
- [x] 12.3 [smoke MANDATORY] 跑 real codex-call smoke for `/codex-pro:rescue` on profile-set fixture（global profile `{model: gpt-5.0}` + task description）+ verify result file frontmatter `model: gpt-5.0` + `profile_source: global`。Acceptance: smoke 全綠。
- [x] 12.4 [smoke MANDATORY] 跑 real codex-call smoke for `/codex-pro:adversarial-review` on profile-set fixture（project profile `{focus_default: security}` + 無 `--focus` arg）+ verify result file frontmatter `focus: security`（focus_default 被 promote）+ `profile_source: project`。Acceptance: smoke 全綠。

## Coverage map

本 change task → spec requirement → design decision 對應（analyzer 用此區段 cross-check；勿因美觀刪除）。

### Spec requirements covered

**config spec:**
- **Config skill registration with zero-argument display** → tasks 1.1, 1.7
- **Config invocation is read-only consumer with no Codex interaction** → tasks 1.2, 2.1
- **Config profile resolution algorithm — two-layer with project priority** → tasks 1.3, 1.6, 2.4
- **Config v0.1 schema is exactly 4 fields** → tasks 1.4, 1.5, 2.2

**review spec MODIFIED:**
- **Review invocation uses codex-call HTTPS direct without subprocess for Codex** → tasks 3.1, 3.2, 6.1
- **Review output is a structured Markdown result file** → tasks 3.3, 6.1, 12.2

**rescue spec MODIFIED:**
- **Rescue invocation uses codex-call HTTPS direct without subprocess for Codex** → tasks 4.1, 4.2, 6.3
- **Rescue output is a structured Markdown result file** → tasks 4.3, 6.3, 12.3

**adversarial-review spec MODIFIED:**
- **Adversarial-review invocation uses codex-call HTTPS direct without subprocess for Codex** → tasks 5.1, 5.2, 6.4, 12.4
- **Adversarial-review output is a structured Markdown result file with four mandatory non-empty sections** → tasks 5.3, 6.4

### Design decisions covered

- **D1: Two-layer profile (global + project) with project priority, field-level merge** → tasks 1.3, 2.3, 2.4
- **D2: Schema v0.1 = 4 fields (model / effort / max_time / focus_default)** → tasks 1.4, 2.2, 11.1
- **D3: Profile resolution algorithm — load global → load project → field merge → hardcoded fallback** → tasks 1.3, 1.6, 2.4
- **D4: Producer skill Step 4 modification — read profile + pass resolved value to codex-call** → tasks 3.2, 4.2, 5.2, 6.1, 6.3, 6.4
- **D5: `/codex-pro:config` skill display semantics — 4-row markdown table with per-field source** → tasks 1.5, 2.2
- **D6: Frontmatter `profile_source` field — optional, aggregate enum** → tasks 3.3, 4.3, 5.3
- **D7: Read-only consumer category invariants enforced** → tasks 1.2, 1.7, 2.1, 9.3
- **D8: Test fixture pattern — fake `~/.codex-pro/` via tmp HOME** → tasks 2.3, 2.4, 6.2, 8.1, 8.2
