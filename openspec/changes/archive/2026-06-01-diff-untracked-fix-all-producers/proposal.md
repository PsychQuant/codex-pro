## Problem

`/codex-pro:adversarial-review --diff` 與 `/codex-pro:review` 預設模式（無 target argument 或 `--diff`）都用 `git diff` 抓 uncommitted changes 當作 target — 但 `git diff` **不包含 untracked file**。當 user 處於「剛建新檔尚未 commit」的開發狀態（codex-pro 自家 workflow 高頻情境：新 skill 落地時 SKILL.md / tests/*.sh / openspec/changes/* 全是 untracked），target body 會 silently 遺漏這些檔案、Codex 只看到部分 changes、產出 partial 或 misleading 的 review / adversarial findings。

本 bug 由 adversarial-review v0.1 smoke test 自己揭露：跑 `/codex-pro:adversarial-review` 時、Codex 第一段 `## Assumptions Challenged` 就指出「這 diff 純文檔聲稱已落地、不含對應 SKILL.md / test 改動」— 因為 SKILL.md 確實是 untracked、git diff 看不到。

Completeness critic（workflow synthesis 階段）查證 `plugins/codex-pro/skills/review/SKILL.md` 第 36 行有與 adversarial-review 同樣的 `git diff` pattern — bug 是 **structural to producer skill family**，不是 adversarial-review-specific。修一個漏一個會 re-create silent failure。

## Root Cause

兩 producer skill 的 Step 1 (Parse argument / Target resolution) 預設 mode 用 `git diff`（無 `HEAD`）— bash convention 是 `git diff` 比較 **index vs working tree** 的 tracked file 差異、untracked file 完全 invisible：

- `plugins/codex-pro/skills/adversarial-review/SKILL.md` Step 1 第一條：「無 argument 或 `--diff`：跑 `git diff` 拿 uncommitted changes 作為 target」
- `plugins/codex-pro/skills/review/SKILL.md` Step 1（同 line pattern）

正確 semantics 應該是「**所有 uncommitted changes 含 untracked**」、對應 `git diff HEAD` + `git ls-files --others --exclude-standard` 列舉 untracked file。

兩 producer skill spec 內 "Target resolution" 相關 scenario 都未明示「是否含 untracked」、為 unspecified behavior — 本 change 顯式 specify。

## Proposed Solution

**修兩 producer skill Step 1 target collection 邏輯**、用共用 helper 維持 DRY：

1. **Step 1 替換 `git diff` 為 `git diff HEAD` + 列舉 untracked**：
   - `git diff HEAD` 比較 working tree vs HEAD commit、含 staged + unstaged 的 tracked changes
   - `git ls-files --others --exclude-standard` 列舉 untracked file（已尊重 `.gitignore`）
   - 兩者結果合併成 target body

2. **Binary file detection（v0.1 必收）**：避免 `.png` 等 binary content 注入 prompt 污染 Codex
   - 對每個 untracked file 跑 `git check-attr binary <path>` + NUL-byte sniff（前 8KB）
   - Binary file 列在 `### Untracked binaries omitted` 段、**只列 path、不注 content**

3. **Size cap（v0.1 必收）**：防 un-gitignored `node_modules` / `.swiftpm` cache blow Codex context
   - **Per-file cap 64KB**：超過 truncate 並加 `… [truncated at 64KB of N bytes]` marker
   - **Aggregate cap 512KB**：超過時剩餘 file 列在 `### Untracked files omitted (aggregate size cap)` 段、不注 content

4. **Empty-repo fallback**：pre-first-commit repo 跑 `git diff HEAD` 會 exit 128（unknown revision `HEAD`）
   - 偵測 exit code 128 + stderr `unknown revision|ambiguous argument 'HEAD'`
   - Degrade 為 `git diff --cached`（staged）+ working-tree diff + untracked enumeration
   - Frontmatter 標記 `target: diff (pre-first-commit)`

5. **target_invalid pre-flight 延伸**：合併 diff + untracked + binary filter + size filter 後若 body 仍 whitespace-only → fire `target_invalid`（保留 adversarial-review 既有 pre-flight 紀律、不為了「support untracked」而退讓空 prompt safety）

6. **共用 helper**：實作為 plugins/codex-pro/skills/{review,adversarial-review}/SKILL.md Step 1 共用的 collection 邏輯（兩 skill 各自 inline、不抽 external lib／保持 SKILL.md self-contained read-only-by-Claude 屬性、但 prose + bash block 高度對齊讓 future regression 容易抓）

7. **Semver bump**：本 change 改 producer 行為（target 結果集從只 tracked 變含 untracked）— 對既有 user 為 behavior change、minor bump
   - adversarial-review v0.1 → v0.2
   - review v0.1 → v0.2
   - **不**加 `--legacy-tracked-only` opt-out flag（會 ossify bug）

8. **Layer 2 test fixture 擴 5 條 scenario**（D5 behavioral runtime test pattern）：
   - mixed modified + untracked repo state → 兩類都進 target
   - untracked binary file → path-listed 不注 content
   - untracked oversize file → truncated with marker
   - empty-repo fallback → 不 crash、frontmatter 標記
   - all-empty (含 untracked filter 後仍空) → target_invalid fire

9. **Pre-archive smoke MANDATORY**（per [[feedback-codex-pro-smoke-before-archive]] memory）：跑 real codex-call on mixed-state repo（uncommitted tracked + untracked + binary + oversize）、assert 4 H2 section non-empty + target body 含 untracked path。本 change 為 producer skill behavior modification、不可只靠 Layer 2 grep + structural

## Non-Goals

- 不加 `--legacy-tracked-only` opt-out flag（會固化 bug、未來 v0.3 不可逆）
- 不改 codex-call wrapper / 上游 parallel-ai-agents（純 SKILL.md / spec / tests 修改、無 cross-repo dep）
- 不改 rescue skill（rescue 無 target 概念、不適用本 bug）
- 不改 setup / batch / status / result / cancel（不是 producer、無 target 概念）
- 不引入新 runtime dependency（純 git + bash）
- 不支援 multi-repo `.codex-pro/`（cwd 模式不變）
- 不抽 SKILL.md 內 bash block 為 external library（保持 SKILL.md self-contained read-only-by-Claude 屬性、user 看 SKILL.md 就能跑、無 hidden import）
- 不改 file path 模式（仍 `.codex-pro/<skill>-<ISO8601>.md`）
- 不改 fail-fast 4 class 結構（仍 rate_limit / oauth_invalid / timeout / target_invalid；只擴 target_invalid pre-flight 條件）
- 不改 `--focus` / `--depth` flag（與 target collection 解耦）
- 不改 review / adversarial-review 的 `<file_path>` mode 或 `--base <ref>` mode（只動 default `--diff` mode）

## Success Criteria

- `plugins/codex-pro/skills/adversarial-review/SKILL.md` Step 1 第一條 default mode 文字含「`git diff HEAD` + `git ls-files --others --exclude-standard`」、不再單獨提及 `git diff`（除非為了解釋舊行為對比）。Verify by grep。
- `plugins/codex-pro/skills/review/SKILL.md` 同樣替換。
- 兩 SKILL.md Step 1 body 含 binary detection 文字（`git check-attr binary` 或 `NUL-byte sniff`）、size cap 文字（`64KB` + `512KB` 或同義）、empty-repo fallback 文字（`pre-first-commit` 或 `exit 128`）。
- 兩 SKILL.md Step 5 (Handle exit code) `target_invalid` pre-flight 描述含「after binary / size filter」延伸條件。
- 兩 SKILL.md frontmatter description 含 v0.2 marker（如 `v0.2 — untracked-by-default`）。
- `openspec/specs/adversarial-review/spec.md` Requirement 1（"Adversarial-review skill registration and argument parsing"）MODIFIED 含新 "untracked file handling" scenario + "binary file path-only" scenario + "size cap" scenario + "empty-repo fallback" scenario；Requirement 4（"... fail-fast across four classes"）MODIFIED target_invalid scenario 延伸 condition。
- `openspec/specs/review/spec.md` Requirement 1（"Review skill registration and target resolution"）同樣 MODIFIED；Requirement 4 同樣 MODIFIED。
- `tests/review.sh` + `tests/adversarial-review.sh` 加 5 條新 behavioral runtime fixture scenario（mixed / binary / oversize / empty-repo / all-empty）— 用 mktemp + `git init` 假 repo。
- `bash tests/run.sh` 後 9 layers all green、aggregate ~280 assertions（234 + ~46 新測試、含 review + adversarial-review fixture scenario 各 +~20、static.sh per-skill loop 自動 cover）。
- Pre-archive smoke：手動跑 real codex-call on mixed-state fixture repo、assert 4 section non-empty + target body 含至少一個 untracked file path。
- CLAUDE.md Commands surface 表 review + adversarial-review 行更新 version 至 v0.2、加備註「v0.2 含 untracked-by-default + binary/size guard + empty-repo fallback」。
- README.md Skills 表 review + adversarial-review row 同樣更新 v0.2 + 註記行為變化。
- `tests/lib/assert.sh` 新增 helper `assert_git_fixture`（git init + config init.defaultBranch main + user.email/name baked into fixture setup）為 cross-machine determinism。

## Impact

- Affected specs:
  - Modified:
    - openspec/specs/adversarial-review/spec.md（Requirement 1 + Requirement 4 MODIFIED）
    - openspec/specs/review/spec.md（Requirement 1 + Requirement 4 MODIFIED）
- Affected code:
  - Modified:
    - plugins/codex-pro/skills/adversarial-review/SKILL.md（Step 1 + Step 5 + frontmatter description v0.2）
    - plugins/codex-pro/skills/review/SKILL.md（Step 1 + Step 5 + frontmatter description v0.2）
    - tests/adversarial-review.sh（+~20 assertion，behavioral fixture 5 scenario + structural verify v0.2 markers）
    - tests/review.sh（+~20 assertion，同上）
    - tests/lib/assert.sh（+ `assert_git_fixture` helper）
    - CLAUDE.md（Commands surface 表 review + adversarial-review row v0.2 + 行為變化備註）
    - README.md（Skills 表 review + adversarial-review row v0.2 + 行為變化備註）
  - New: (none — 共用 helper inline 進 SKILL.md、不抽 lib)
  - Removed: (none)
- Test net delta: 234 → ~280（+~46：review.sh + adversarial-review.sh 各 +~20 含 5 fixture scenario + structural v0.2 marker、static.sh per-skill loop 自動 cover 各 skill 不變）
- Cross-repo impact: none（不動 parallel-ai-agents、不動 codex-call）
- Runtime dependency: 無新增（純 git + bash + python3 frontmatter parse）
- Design constraints:
  - #1 (No subprocess for Codex)：純 Bash target collection、無 codex 互動、trivially adhered
  - #4 (Structured result file)：不變
  - #5 (Profile-based config)：不擴 profile 機制（留 future config skill change）
  - #6 (Observability)：target_invalid pre-flight 延伸條件、user-visible 為 "skill aborted because untracked-after-filter-is-still-empty"、honest displayed limitation
  - #7 (macOS only)：沿用
- Cross-cycle discipline impact: 本 change 為 producer behavior modification、**MANDATORY smoke before archive**（per [[feedback-codex-pro-smoke-before-archive]] memory）。Layer 2 behavioral runtime test 加 5 scenario、但仍不能取代 real codex-call smoke（rescue v0.1.1 教訓：Layer 2 grep / behavioral test 不 invoke codex-call、無法抓 runtime drift）
- Estimated size: **single-cycle**（非 quick-fix）— 兩 SKILL.md 改 Step 1 + Step 5、兩 spec MODIFIED 各 2 requirement、兩 test 加 ~20 assertion 含 5 fixture scenario、CLAUDE.md / README.md 各 2 row update、加 helper、mandatory smoke。比 fix-rescue-session-flags 大、與 status-result-cancel triple skill set 同量級
