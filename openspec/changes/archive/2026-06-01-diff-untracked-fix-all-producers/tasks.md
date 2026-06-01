# Tasks — diff-untracked-fix-all-producers

修兩 producer skill（review v0.1 → v0.2、adversarial-review v0.1 → v0.2）的 `--diff` mode silent untracked-omission bug；含 9 條 baked-in corrections（binary detection / size cap / empty-repo fallback / target_invalid 延伸 / semver bump / 共用 helper / no opt-out flag / behavioral fixture / MANDATORY smoke）。完成後 codex-pro v0.4。

## 1. tests/lib/assert.sh helper

- [x] 1.1 在 `tests/lib/assert.sh` 加 `assert_git_fixture` helper：`git -C "$dir" init -q`、`git config init.defaultBranch main`、`git config user.email test@codex-pro.local`、`git config user.name "codex-pro test"`。對應 design **D8: Behavioral runtime test fixture pattern**。Acceptance: `bash -n tests/lib/assert.sh` 通過；helper 為 4 行 git config、defensive against cross-machine init.defaultBranch flakiness。

## 2. review SKILL.md modification

- [x] 2.1 [P] 修改 `plugins/codex-pro/skills/review/SKILL.md` 頭部 YAML frontmatter description block：加入 literal substring `v0.2 — untracked-by-default`。對應 spec **Review skill registration and target resolution** "Skill is registered" scenario + design **D7: Semver bump policy**。Acceptance: `grep "v0.2 — untracked-by-default" plugins/codex-pro/skills/review/SKILL.md` ≥ 1。
- [x] 2.2 [P] 修改 review SKILL.md Step 1 default `--diff` mode（與 `git diff` 比較同一段、原 line 36 附近）：替換為 `git diff HEAD` + `git ls-files --others --exclude-standard`；明示「pre-1.0 minor bump 帶 behavior change、v0.2 含 untracked-by-default」。對應 spec **Review skill registration and target resolution** "--diff mode includes both tracked changes and untracked files" scenario + design **D1: Bug 同時存在 review + adversarial-review** + **D2: Default 改 untracked-aware、不加 `--legacy-tracked-only` opt-out flag**。Acceptance: SKILL.md body grep `git diff HEAD` ≥ 1、`git ls-files --others --exclude-standard` ≥ 1、grep 整段「`git diff` (no HEAD)」應已 disappeared（除非為說明舊行為對比）。
- [x] 2.3 [P] 加 review SKILL.md 內 binary detection 段（Step 1 sub-section）：寫明 `git check-attr binary <path>` + NUL-byte sniff (first 8KB) 雙 stage detect、binary file 列在 `### Untracked binaries omitted` heading 不注 content。對應 spec **Review skill registration and target resolution** "Binary untracked file is path-listed without content injection" scenario + design **D3: Binary detection 算法**。Acceptance: SKILL.md body grep `git check-attr binary` ≥ 1、`NUL-byte` 或 `\\x00` 或 `null byte` ≥ 1、`Untracked binaries omitted` ≥ 1。
- [x] 2.4 [P] 加 review SKILL.md 內 size cap 段（Step 1 sub-section）：寫明 per-file 64KB cap + truncate with marker `… [truncated at 64KB of N bytes]`、aggregate 512KB cap + omit with `### Untracked files omitted (aggregate size cap)` heading。對應 spec **Review skill registration and target resolution** "Oversize untracked file is truncated" + "Aggregate size cap omits overflow files" scenarios + design **D4: Size cap policy**。Acceptance: SKILL.md body grep `64KB` ≥ 1、`512KB` ≥ 1、`truncated at 64KB` ≥ 1、`aggregate size cap` ≥ 1。
- [x] 2.5 [P] 加 review SKILL.md 內 empty-repo fallback 段（Step 1 sub-section）：寫明 `git diff HEAD` exit code 128 + stderr match `unknown revision|ambiguous argument 'HEAD'` 雙條件 → degrade `git diff --cached` + working-tree `git diff` + untracked enumeration、frontmatter `target` field 值改 `diff (pre-first-commit)`。對應 spec **Review skill registration and target resolution** "Pre-first-commit repository falls back" scenario + design **D5: Empty-repo (`git diff HEAD` exit 128) fallback**。Acceptance: SKILL.md body grep `pre-first-commit` ≥ 1、`exit 128|exit code 128` ≥ 1、`unknown revision` ≥ 1。
- [x] 2.6 [P] 修改 review SKILL.md Step 5 (Handle exit code) fail-fast 段：原 3 class 加入第 4 class **`target_invalid`**（post-filter empty pre-flight class、與 adversarial-review template 對齊）；對應 frontmatter `error: target_invalid` + `findings_count: 0` + remediation message 指向 user 「verify there are real changes to review (uncommitted tracked changes, or untracked text files within 64KB each)」。對應 spec **Review failures trigger circuit-breaker fail-fast** 新「Target-invalid pre-flight fires when post-filter body is empty」scenario + design **D6: target_invalid pre-flight 延伸 condition**。Acceptance: SKILL.md body grep `target_invalid` ≥ 1、`pre-flight` 或 `pre-filter` ≥ 1。

## 3. adversarial-review SKILL.md modification

- [x] 3.1 [P] 修改 `plugins/codex-pro/skills/adversarial-review/SKILL.md` 頭部 YAML frontmatter description：加入 literal substring `v0.2 — untracked-by-default`（與既有 hostile/challenge keyword 並存）。對應 spec **Adversarial-review skill registration and argument parsing** "Skill is registered" scenario。Acceptance: `grep "v0.2 — untracked-by-default" plugins/codex-pro/skills/adversarial-review/SKILL.md` ≥ 1。
- [x] 3.2 [P] 修改 adversarial-review SKILL.md Step 1 default `--diff` mode：替換為 `git diff HEAD` + `git ls-files --others --exclude-standard`；保留 file path mode 與 `--base <ref>` mode 不動（只改 default `--diff`）。對應 spec **Adversarial-review skill registration and argument parsing** "--diff mode includes both tracked changes and untracked files" scenario + design **D1** + **D2**。Acceptance: SKILL.md body grep `git diff HEAD` ≥ 1、`git ls-files --others --exclude-standard` ≥ 1。
- [x] 3.3 [P] 加 adversarial-review SKILL.md 內 binary detection 段（與 2.3 review 同 architecture、文字可同）。對應 spec **Adversarial-review skill registration and argument parsing** "Binary untracked file is path-listed without content injection" scenario + design **D3**。Acceptance: SKILL.md body grep `git check-attr binary` ≥ 1、`NUL-byte` 或 `\\x00` ≥ 1、`Untracked binaries omitted` ≥ 1。
- [x] 3.4 [P] 加 adversarial-review SKILL.md 內 size cap 段（與 2.4 同 architecture）。對應 spec **Adversarial-review skill registration and argument parsing** "Oversize untracked file is truncated" + "Aggregate size cap" scenarios + design **D4**。Acceptance: SKILL.md body grep `64KB` ≥ 1、`512KB` ≥ 1、`truncated at 64KB` ≥ 1、`aggregate size cap` ≥ 1。
- [x] 3.5 [P] 加 adversarial-review SKILL.md 內 empty-repo fallback 段（與 2.5 同 architecture）。對應 spec **Adversarial-review skill registration and argument parsing** "Pre-first-commit repository falls back" scenario + design **D5**。Acceptance: SKILL.md body grep `pre-first-commit` ≥ 1、`exit 128` ≥ 1、`unknown revision` ≥ 1。
- [x] 3.6 [P] 修改 adversarial-review SKILL.md Step 5 fail-fast `target_invalid` 段：明示 v0.2 post-filter condition 延伸（binary + size filter 後仍空才 fire）、remediation message 提醒 user 「target body 為空 after binary/size filtering」。對應 spec **Adversarial-review failures trigger circuit-breaker fail-fast across four classes** "Target-invalid pre-flight aborts before codex-call (v0.2 post-filter condition)" scenario + design **D6**。Acceptance: SKILL.md body grep `post-filter|after binary` ≥ 1（明示新 condition、與 v0.1 raw-emptiness 區隔）。

## 4. tests/review.sh extension

- [x] 4.1 [P] 修改 `tests/review.sh` structural 區段：加 `v0.2 — untracked-by-default` 字串 assertion；加 forbidden `--legacy-tracked-only` (count = 0) assertion（per D2）；加新文字 marker assertion（`git diff HEAD` / `git check-attr binary` / `64KB` / `512KB` / `pre-first-commit` / `Untracked binaries omitted` / `aggregate size cap` / `target_invalid` 各 ≥ 1）。Acceptance: structural 區段約 +10 assertion 全綠。
- [x] 4.2 [P] 加 `tests/review.sh` behavioral runtime fixture：source `lib/assert.sh`、定義 fixture helper 用 `assert_git_fixture` 建 temp dir + 5 scenario 對應 D8。Acceptance: helper 定義 + 5 fixture（mixed / binary / oversize / empty-repo / all-empty）皆能在 cd "$dir" 後跑得起來。
- [x] 4.3 [P] 加 tests/review.sh behavioral scenario「mixed」：fixture 含 1 modified tracked + 1 untracked normal text、跑 review Step 1 collect logic、assert target body 含 modified diff AND `### Untracked file:` heading + 文本內容。Acceptance: 約 4 assertion（diff present + untracked path present + content present + 整段 non-empty）。
- [x] 4.4 [P] 加 tests/review.sh behavioral scenario「binary」：fixture 含 1 untracked normal text + 1 untracked `.png` (NUL byte 前 8KB)、跑 collect logic、assert `### Untracked binaries omitted` 段含 .png path 但無 content injection。Acceptance: 約 3 assertion（heading present + path present + content absent）。
- [x] 4.5 [P] 加 tests/review.sh behavioral scenario「oversize」：fixture 含 1 untracked 100KB text、跑 collect logic、assert content 前 64KB included、`… [truncated at 64KB of 102400 bytes]` marker 出現。Acceptance: 約 3 assertion（content 含前 64KB + marker present + 整段 size cap 後 ≤ 64KB + marker）。
- [x] 4.6 [P] 加 tests/review.sh behavioral scenario「empty-repo」：fixture 用 `assert_git_fixture` 建 fresh git init repo + 1 untracked file、跑 collect logic、assert exit 0、frontmatter `target: diff (pre-first-commit)` marker 出現。Acceptance: 約 3 assertion（exit 0 + `target:` 值正確 + 整段 non-empty）。
- [x] 4.7 [P] 加 tests/review.sh behavioral scenario「all-empty」：fixture 含 empty repo + 1 untracked 100KB `.png`（被 binary + size filter 都過濾）、跑 collect logic、assert `target_invalid` 觸發、frontmatter `error: target_invalid` 出現、exit 非 0 + remediation message。Acceptance: 約 3 assertion（target_invalid present + exit 非 0 + remediation 字串）。

## 5. tests/adversarial-review.sh extension

- [x] 5.1 [P] 修改 `tests/adversarial-review.sh` structural 區段：加 `v0.2 — untracked-by-default` 字串 assertion；forbidden `--legacy-tracked-only` (count = 0)；新文字 marker assertion 同 4.1（`git diff HEAD` / `git check-attr binary` / `64KB` / `512KB` / `pre-first-commit` / `Untracked binaries omitted` / `aggregate size cap` 各 ≥ 1）。Acceptance: structural 區段約 +10 assertion 全綠。
- [x] 5.2 [P] 加 `tests/adversarial-review.sh` behavioral runtime fixture：reuse `assert_git_fixture` helper + 同 4.2 5 scenario fixture pattern。Acceptance: helper 定義 + 5 fixture 皆能跑。
- [x] 5.3 [P] 加 tests/adversarial-review.sh behavioral scenario「mixed」（與 4.3 同）。Acceptance: 約 4 assertion 全綠。
- [x] 5.4 [P] 加 tests/adversarial-review.sh behavioral scenario「binary」（與 4.4 同）。Acceptance: 約 3 assertion 全綠。
- [x] 5.5 [P] 加 tests/adversarial-review.sh behavioral scenario「oversize」（與 4.5 同）。Acceptance: 約 3 assertion 全綠。
- [x] 5.6 [P] 加 tests/adversarial-review.sh behavioral scenario「empty-repo」（與 4.6 同）。Acceptance: 約 3 assertion 全綠。
- [x] 5.7 [P] 加 tests/adversarial-review.sh behavioral scenario「all-empty」（與 4.7 同）。Acceptance: 約 3 assertion 全綠。

## 6. CLAUDE.md + README.md update

- [x] 6.1 修改 `CLAUDE.md` Commands surface 表 `/codex-pro:review` row：version 改 v0.2、備註欄加「v0.2 含 untracked-by-default、binary path-only / size cap (64KB per-file / 512KB aggregate)、empty-repo fallback (`diff (pre-first-commit)` marker)、target_invalid pre-flight 延伸至 post-binary-and-size-filter empty」。Acceptance: `grep "/codex-pro:review.*v0.2" CLAUDE.md` 命中、grep `untracked-by-default` ≥ 1。
- [x] 6.2 修改 CLAUDE.md Commands surface 表 `/codex-pro:adversarial-review` row：version 改 v0.2、備註欄加同 6.1 句子（適 adversarial-review context、與既有 4 H2 section + --focus + --depth 描述共存）。Acceptance: `grep "/codex-pro:adversarial-review.*v0.2" CLAUDE.md` 命中。
- [x] 6.3 修改 CLAUDE.md Marketplace structure 段 skills 子目錄列表 `review/SKILL.md` 與 `adversarial-review/SKILL.md` 兩 row：標 v0.2 + untracked-by-default。Acceptance: grep `review/SKILL.md.*v0.2` + `adversarial-review/SKILL.md.*v0.2` 各 ≥ 1。
- [x] 6.4 修改 `README.md` Skills 表 review row 與 adversarial-review row：標 v0.2 + 加 untracked-by-default 描述（含 binary / size / fallback markers）。Acceptance: README 內 `review.*v0.2` + `adversarial-review.*v0.2` 各 ≥ 1。
- [x] 6.5 修改 README.md What it replaces 表 `/codex:review` 與 `/codex:adversarial-review` 兩 row：標 v0.2。Acceptance: 兩 row 各含 `v0.2`。

## 7. plugin.json bump

- [x] 7.1 修改 `plugins/codex-pro/.claude-plugin/plugin.json`：version 0.3.0 → 0.4.0；description 更新為 「v0.4: review + adversarial-review v0.1 → v0.2 — untracked-by-default in --diff mode, with binary path-only / per-file 64KB / aggregate 512KB size cap / pre-first-commit fallback / target_invalid post-filter pre-flight」；keywords 加 `untracked-by-default`、`v0.2`。Acceptance: `python3 -c "import json; print(json.load(open('plugins/codex-pro/.claude-plugin/plugin.json'))['version'])"` 印 `0.4.0`、keywords 含 `untracked-by-default`。

## 8. Layer 1+2 整合驗證

- [x] 8.1 跑 `bash tests/run.sh` 整套：9 layers all green、aggregate ~280 assertions（234 + 46）、exit 0。Acceptance: `bash tests/run.sh; echo $?` 印 0；輸出末段 `All layers passed.`。

## 9. Pre-archive smoke (MANDATORY per [[feedback-codex-pro-smoke-before-archive]])

- [x] 9.1 跑 real codex-call smoke on mixed-state fixture for `/codex-pro:adversarial-review`：mktemp + `assert_git_fixture` 建 fixture repo（含 tracked modified `.swift` + untracked normal `.txt` + untracked binary `.png` (NUL byte) + untracked 100KB oversize `.log`）、cd 進去、invoke real codex-call（用 SKILL.md 規範的 `--instructions` + `--prompt-file` + `--max-time 600` + `--model gpt-5.5` + `--effort xhigh`）、verify (a) exit 0、(b) 4 H2 section 各 non-empty、(c) target body 含 untracked `.txt` path、(d) binary `.png` 列在 `Untracked binaries omitted` 段、(e) oversize `.log` 含 `truncated at 64KB` marker。對應 design **D9: Mandatory pre-archive smoke gate**。Acceptance: smoke 全綠、result file 落地、5 條 condition 全 satisfy。
- [x] 9.2 跑 real codex-call smoke on mixed-state fixture for `/codex-pro:review`：同 9.1 fixture、invoke real codex-call、verify (a) exit 0、(b) result file 結構正確 (frontmatter + ## Summary + ## Findings)、(c) target body 含 untracked `.txt` path、(d) binary path-only、(e) oversize truncated marker。Acceptance: smoke 全綠、result file 落地、5 條 condition 全 satisfy。

## Coverage map

本 change task → spec requirement → design decision 對應（analyzer 用此區段 cross-check；勿因美觀刪除）。

### Spec requirements covered

**review spec:**
- **Review skill registration and target resolution** → tasks 2.1, 2.2, 2.3, 2.4, 2.5（SKILL.md frontmatter v0.2 + Step 1 untracked + binary + size + fallback）
- **Review failures trigger circuit-breaker fail-fast** → task 2.6（Step 5 加 target_invalid class）

**adversarial-review spec:**
- **Adversarial-review skill registration and argument parsing** → tasks 3.1, 3.2, 3.3, 3.4, 3.5（同 review 結構）
- **Adversarial-review failures trigger circuit-breaker fail-fast across four classes** → task 3.6（Step 5 target_invalid post-filter condition 延伸）

### Design decisions covered

- **D1: Bug 同時存在 review + adversarial-review、必須 same-cycle fix** → tasks 2.2 + 3.2（兩 SKILL.md 同 cycle 改）
- **D2: Default 改 untracked-aware、不加 `--legacy-tracked-only` opt-out flag** → tasks 2.2 + 3.2 + 4.1 + 5.1（SKILL.md 不加 flag、tests 加 forbidden check）
- **D3: Binary detection 算法（in-scope v0.1）** → tasks 2.3 + 3.3 + 4.4 + 5.4（SKILL.md prose + test fixture）
- **D4: Size cap policy（in-scope v0.1）** → tasks 2.4 + 3.4 + 4.5 + 5.5（SKILL.md prose + test fixture）
- **D5: Empty-repo (`git diff HEAD` exit 128) fallback** → tasks 2.5 + 3.5 + 4.6 + 5.6（SKILL.md prose + test fixture）
- **D6: target_invalid pre-flight 延伸 condition** → tasks 2.6 + 3.6 + 4.7 + 5.7（SKILL.md prose + test fixture）
- **D7: Semver bump policy（minor、無 opt-out flag）** → tasks 2.1 + 3.1 + 6.1 + 6.2 + 6.3 + 6.4 + 6.5 + 7.1（兩 SKILL.md frontmatter + CLAUDE.md + README.md + plugin.json bump）
- **D8: Behavioral runtime test fixture pattern** → tasks 1.1 + 4.2-4.7 + 5.2-5.7（assert_git_fixture helper + 5 scenario 各 skill）
- **D9: Mandatory pre-archive smoke gate** → tasks 9.1 + 9.2（兩 skill 各跑 real codex-call on mixed-state fixture）
