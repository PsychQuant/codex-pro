## Context

codex-pro v0.3.0 ship 後、9 skills landed、234 assertions green、drop-in surface 完成。adversarial-review v0.1 smoke test 揭露 `--diff` mode 漏 untracked file 的 silent correctness bug；completeness critic 查證 review skill 第 36 行有同 pattern — bug 是 structural to producer skill family。

修法不是「換一個 git command」那麼簡單。Workflow synthesis 提出 9 條 baked-in corrections、本 design 整理為 9 個 D-decision，反映以下 architectural tension：

- **untracked default 是 correct semantic 但可能讓 prompt 變更大**：必須引入 binary detection + size cap 維持 prompt safety（D3 + D4）
- **`git diff HEAD` 在 pre-first-commit repo 會 exit 128**：必須 fallback、不可 regress 既有 working code path（D5）
- **本 change 為 producer behavior modification、不能只靠 string-level test**（D8 + D9）：Layer 2 behavioral runtime test 加 fixture scenario、但仍 MANDATORY pre-archive smoke、遵守 [[feedback-codex-pro-smoke-before-archive]] memory 的 producer-skill 紀律
- **同 bug 在兩 skill、必須同時修**：completeness critic 揪出 review/SKILL.md:36；修一漏一會 re-create silent failure（D1）

## Goals / Non-Goals

**Goals:**

- 兩 producer skill (review + adversarial-review) 的 `--diff` default mode 含 untracked file
- Binary file path-only（不注 content）防 prompt 污染
- Per-file 64KB + aggregate 512KB size cap 防 context blow
- Empty-repo (`git diff HEAD` exit 128) fallback 不 regress
- target_invalid pre-flight 延伸 condition（post-filter 仍空 → fire）
- Both skills 從 v0.1 → v0.2（minor bump、behavior change semver discipline）
- Layer 2 behavioral runtime test fixture +5 scenario、MANDATORY pre-archive smoke
- `tests/lib/assert.sh` 加 `assert_git_fixture` helper（cross-machine deterministic git init）
- CLAUDE.md + README.md row update + 行為變化備註

**Non-Goals:**

- 不加 `--legacy-tracked-only` opt-out flag（ossify bug、未來 v0.3 不可逆）
- 不改 codex-call / parallel-ai-agents
- 不改 rescue（無 target 概念）
- 不改 setup / batch / status / result / cancel（無 target 概念）
- 不改 `--focus` / `--depth` flag（與 target collection 解耦）
- 不改 `<file_path>` mode 或 `--base <ref>` mode（只動 default `--diff`）
- 不抽 SKILL.md 內 bash block 為 external library（保持 self-contained）
- 不引入新 runtime dependency
- 不改 fail-fast 4 class 結構（只擴 target_invalid pre-flight 條件）
- 不改 result file frontmatter 7 field（只新增 marker 在 target 值內：如 `target: diff (pre-first-commit)`）
- 不引入 background job mode（refuted candidate）
- 不擴 Constraint #5 profile mechanics（留 future config skill change）

## Decisions

### D1: Bug 同時存在 review + adversarial-review、必須 same-cycle fix

採 **single change 同時修兩 skill**、不採「先修 adversarial-review、review follow-up」的分段策略。

理由：

- Completeness critic 驗證 `plugins/codex-pro/skills/review/SKILL.md` 第 36 行 `git diff` pattern 與 adversarial-review 相同
- Bug 是 structural to producer skill family、不是 adversarial-review-specific
- 分段 fix 會 leave review 在 silent failure 狀態長達一個 cycle、誘導 user 跑 `/codex-pro:review` 拿到 partial result
- DRY：兩 skill Step 1 收 target body 邏輯高度對齊、同 cycle 改 review 一致性更高
- semver discipline 也要求兩 skill 同時 v0.1 → v0.2、避免「review v0.1 行為 vs adversarial-review v0.2 行為」mental load

Alternatives:

- 先 adversarial-review v0.1.1 then review v0.1.1 兩 cycle：誘導 silent failure 一個 cycle、review user 不知道 partial
- review v0.1.x 不變、只升 adversarial-review：行為不一致、user 看 SKILL.md 對比表會疑惑

### D2: Default 改 untracked-aware、不加 `--legacy-tracked-only` opt-out flag

採 **untracked-by-default、無 opt-out flag**、不採「加 flag 讓 user 自選」的 backward-compat 路線。

理由：

- v0.1 行為（漏 untracked）是 **silent correctness bug** 而非 user-facing feature — 沒人會「故意要 untracked 不被 review」
- 加 flag 會 ossify bug、未來 v0.3 想 sunset flag 需 deprecation cycle
- v0.2 minor bump 已明示 behavior change、CHANGELOG / SKILL.md frontmatter description / CLAUDE.md / README.md 都會記錄、user 升級時看得到變化
- pre-1.0 (v0.x) semver convention 接受 minor bump 含 behavior break、不需 major bump
- 真有「我只要 review tracked、不要 untracked」這需求 → user 自己跑 `git stash --include-untracked` 後再 invoke、不需 skill 內 flag

Alternatives:

- 加 `--include-untracked` opt-in flag（默認舊行為）：bug 持續存在、user 不主動加 flag 就繼續 silent failure
- 加 `--legacy-tracked-only` opt-out flag：可 ossify bug、bag of flags 心智成本

### D3: Binary detection 算法（in-scope v0.1）

採 **in-scope binary detection**、不採「v0.1.x defer、v0.2.x 補」的分段策略。

算法：

```
for path in untracked_files:
    # Stage 1: git check-attr (uses .gitattributes if defined)
    if git check-attr binary <path> → "binary":
        binary = True
    else:
        # Stage 2: NUL-byte sniff (first 8KB)
        with open(path, 'rb') as f:
            chunk = f.read(8192)
        binary = (b'\x00' in chunk)
    
    if binary:
        path_only_list.append(path)
    else:
        content_list.append(path)
```

Binary file 列在 prompt 內 `### Untracked binaries omitted` heading 下、只列 path、不注 content。

理由：

- 不做 binary detection 會 silent inject `.png` / `.mp3` / `.swiftpm` cache 進 prompt、Codex 看到 binary blob 後續 review 全失效（**same silent-correctness-failure class as the original bug**）
- defer 到 v0.1.x 等於 ship 一個用 v0.2 binary scenario 會 break 的版本、違反 release-as-correctly 紀律
- `git check-attr` 是 git 原生 path attribute 機制、優先使用 user 已定義的 binary marker；NUL-byte sniff 是 universal fallback、Unix file(1) 同等技術
- 8KB sniff window 是 industry convention（git-blame、grep、file(1) 都用此 ballpark）— 平衡 detection accuracy vs IO cost

Alternatives:

- 純 extension blacklist（`.png` / `.mp4` / ...）：incomplete coverage（`.bin` / `.pyc` / `.swp` / 各種 cache 副檔名 unbounded）、user-defined binary extension 不認得
- 純 NUL-byte sniff、不查 `git check-attr`：忽視 user 已 declare 的 binary marker
- defer binary detection：silent injection 風險、違反 release-as-correctly

### D4: Size cap policy（in-scope v0.1）

採 **per-file 64KB + aggregate 512KB、in-scope v0.1**、不採「無 cap 跑跑看」或「defer v0.1.x」。

算法：

```
per_file_cap = 64 * 1024
aggregate_cap = 512 * 1024
running_total = 0
included = []
truncated = []
omitted = []

for path in content_eligible_files:
    file_size = stat(path).st_size
    if running_total + min(file_size, per_file_cap) > aggregate_cap:
        omitted.append(path)
        continue
    if file_size > per_file_cap:
        content = read_first_n_bytes(path, per_file_cap)
        included.append((path, content, f"… [truncated at 64KB of {file_size} bytes]"))
        running_total += per_file_cap
    else:
        included.append((path, read(path), None))
        running_total += file_size
```

Truncated file 行尾加 `… [truncated at 64KB of N bytes]` marker；omitted file 列在 `### Untracked files omitted (aggregate size cap)` 段、不注 content。

理由：

- 不做 size cap 會 silent blow Codex context window — un-gitignored `node_modules` / `.swiftpm` cache 動輒 MB 級、prompt 一次性 inflate 到 Codex token limit、real review content 被 truncate 但 user 不知
- 64KB 是「一個正常人類寫的 .swift / .ts / .py 檔上限」approximation（per Anthropic / OpenAI 公開的 token budget 經驗、64KB ≈ 16k token、單檔合理上限）
- 512KB aggregate cap 是「對 codex-call typical xhigh prompt 留 head-room」approximation
- defer 到 v0.1.x 等於 v0.2 binary case 修了但 size case 仍 silent — partial fix re-creates same class

Alternatives:

- per-file 32KB / aggregate 256KB：太保守、正常 multi-file diff 會被切掉
- per-file 256KB / aggregate 2MB：太大、單檔 256KB 不像 source code、可能是 generated / minified file 也被注 content
- 用 frontmatter `max_target_size_kb` 讓 user 設：v0.1 不擴 profile（D6 Non-Goals）、且大多 user 不知道該設多少

### D5: Empty-repo (`git diff HEAD` exit 128) fallback

採 **detect exit 128 + stderr match `unknown revision|ambiguous argument 'HEAD'` → degrade fallback**。

算法：

```bash
diff_out=$(git diff HEAD 2>&1)
diff_rc=$?
if [ $diff_rc -eq 128 ] && echo "$diff_out" | grep -qE "unknown revision|ambiguous argument 'HEAD'"; then
    # Empty repo - no HEAD commit yet
    cached_diff=$(git diff --cached 2>/dev/null)
    workingtree_diff=$(git diff 2>/dev/null)
    target_body="$cached_diff\n$workingtree_diff\n$(enumerate_untracked)"
    target_marker="diff (pre-first-commit)"
else
    target_body="$diff_out\n$(enumerate_untracked)"
    target_marker="diff"
fi
```

Frontmatter `target` field 寫入 marker（`diff` 或 `diff (pre-first-commit)`）。

理由：

- pre-first-commit repo 是 legitimate working state（`git init` 後尚未 commit 任何 file）— 本 change 不可 regress 此 path、否則 user 第一次跑 codex-pro 在 fresh repo 就直接 fail
- exit 128 + stderr message 雙條件 match 比單看 exit code 更穩固（exit 128 可能因其他原因如 corrupt repo）
- Fallback 用 `--cached` 抓 staged content（user 已 `git add` 但尚未 commit）+ `git diff` 抓 working-tree（無 HEAD 比較時 `git diff` 顯示 working-tree vs index 而非 vs HEAD）+ untracked enumeration
- `target` field 明示 `pre-first-commit` 為 frontmatter level user-visible marker、result file 後可追溯為何特殊 codepath

Alternatives:

- 純檢 exit code：不夠 specific、exit 128 可能 corrupt repo
- 不 fallback、let `git diff HEAD` 錯誤 propagate 為 target_invalid：regress 既有 working path（user pre-first-commit 跑 review 之前是 work 的、之後 break）

### D6: target_invalid pre-flight 延伸 condition

採 **post-filter empty 也 fire target_invalid**、不採「有 untracked 就一定 valid」的退讓。

延伸 condition：

```
target_invalid fire when:
  (a) git diff HEAD 結果空 (含 fallback 後也空) AND
  (b) 含 binary 與 size filter 後、untracked enumeration 空 AND
  (c) 整個合併 target body 是 whitespace-only
```

理由：

- adversarial-review v0.1 spec 已明示 target_invalid 為 **pre-flight class**、防止把空 prompt 送進去燒 Codex quota
- 加入 untracked 後新增 failure mode：「user 跑 `/codex-pro:adversarial-review` 在純 binary untracked file repo（如純 image asset folder）」— 過了 filter 後 prompt 仍空、必須 fire target_invalid
- 不延伸條件 = 退讓「有 untracked 就一定 valid」會違反原 spec target_invalid 紀律、再造 silent empty-prompt bug
- review 原 spec 無此 pre-flight class、本 change 同時為 review 引入 target_invalid（與 adversarial-review template 對齊）

Alternatives:

- 不延伸、只看 raw git diff 是否空：post-filter 空就成 silent failure
- 把 target_invalid 改 informational warning（不 abort）：違反「fail-fast circuit breaker」紀律

### D7: Semver bump policy（minor、無 opt-out flag）

採 **adversarial-review v0.1 → v0.2、review v0.1 → v0.2** 同 cycle minor bump、無 opt-out flag。

理由：

- 兩 skill 行為 modify（target 結果集從只 tracked 變含 untracked）= behavior change
- Pre-1.0 (v0.x) semver convention：minor bump 表 behavior change（major bump 留 v1.0+ 用、避免 v2.0 / v3.0 心智成本太早）
- 兩 skill 必須同 version、避免 user 對 review/SKILL.md 看 v0.2、adversarial-review/SKILL.md 看 v0.1.1 mental load
- D2 已決定 no opt-out flag、semver 同方向
- plugin.json 本身 0.3.0 → 0.4.0（aggregate codex-pro plugin minor bump、含此 behavior change）

Alternatives:

- v0.1.0 → v0.1.1 patch bump：patch 應該是「bug fix 不改行為」，本 change 改行為（添加 untracked）= 不是 pure patch
- 只 bump adversarial-review：D1 已論證兩 skill 必須同 cycle 改
- 大 bump 兩 skill 各自 v1.0：太早升 v1.0、後續還有未交付 behavior（profile config、token observability）

### D8: Behavioral runtime test fixture pattern

採 **mktemp + `git init` + content fixture matrix** behavioral runtime test，5 scenario：

1. **mixed**: modified tracked + untracked normal file → 兩類都進 target body
2. **binary**: untracked `.png` (NUL byte 前 8KB) + untracked normal `.txt` → png path-listed 不注 content、txt 注 content
3. **oversize**: untracked 100KB file → 64KB truncate + marker
4. **empty-repo**: `git init` 無 commit + 一個 untracked file → fallback path + frontmatter `target: diff (pre-first-commit)`
5. **all-empty**: empty repo + 一個 100KB untracked binary（被 binary + size filter 都過濾） → target_invalid fire

`tests/lib/assert.sh` 加 helper `assert_git_fixture`：

```bash
assert_git_fixture() {
  local dir="$1"
  git -C "$dir" init -q
  git -C "$dir" config init.defaultBranch main
  git -C "$dir" config user.email "test@codex-pro.local"
  git -C "$dir" config user.name "codex-pro test"
}
```

理由：

- D5 behavioral runtime test pattern（從 status-result-cancel cycle establish）已 prove 可抓真實 design bug、不靠 SKILL.md grep
- 5 scenario coverage 對應 5 個 baked-in correction（D3 binary / D4 size / D5 fallback / D6 pre-flight / D2 default）
- `assert_git_fixture` helper 解 cross-machine determinism：`git init` 預設 branch name 跟 maintainer 機器 `init.defaultBranch` config 連動、test fixture 顯式設 main 防 flakiness
- 但 5 scenario behavioral test 仍 **不能取代 real codex-call smoke**（rescue v0.1.1 教訓：Layer 2 不 invoke codex-call）— 故 D9

Alternatives:

- 不寫 fixture、純 SKILL.md grep：抓不到 binary detection / size cap / fallback 邏輯實際 work
- fixture 寫死 6 個 scenario（含 base case happy path）：base case Layer 2 已 cover、不重複

### D9: Mandatory pre-archive smoke gate

採 **本 change 在 archive 前 MANDATORY 跑 real codex-call** on mixed-state fixture repo、不採「Layer 2 behavioral 已 cover 可以跳過 smoke」。

理由：

- 本 change 為 **producer skill behavior modification** — 改的是 SKILL.md Step 1 / Step 5 的 Bash 邏輯、Layer 2 不 invoke codex-call（避免 quota burn）、無法驗 prompt body 實際送到 Codex 的內容是否符合預期
- rescue v0.1.1 教訓明確：Layer 2 全綠不代表 runtime 對 — `--session` flag bug 在 115/115 green 下 ship、就是因為 producer skill 沒過 smoke gate
- [[feedback-codex-pro-smoke-before-archive]] memory 明示「producer skill modification 一定要 smoke before archive」
- Status-result-cancel 三 skill 屬 read-only consumer、Layer 2 behavioral 已涵蓋 runtime；本 change 不同類、不可援用其「不需 smoke」結論
- Smoke 內容：mktemp 建 fixture repo（mixed-state：tracked modified + untracked text + untracked binary `.png` + untracked oversize 100KB）、跑 `/codex-pro:adversarial-review --diff` 與 `/codex-pro:review --diff`、verify：(a) exit 0、(b) 4 H2 section non-empty (adversarial-review) 或 result file 結構正確 (review)、(c) target body 含至少一個 untracked file path、(d) binary path 列在 `Untracked binaries omitted` 段但無 content、(e) oversize file 含 `truncated at 64KB` marker
- 兩 skill 各跑一次 smoke = 2 次 Codex quota call、合理成本

Alternatives:

- 跳過 smoke、信 Layer 2 behavioral：違反 producer-skill discipline、bypass [[feedback-codex-pro-smoke-before-archive]]
- 只 smoke 一個 skill：另一個 skill 未驗、bug 可能只在另一個出現
- Smoke 三個 repo state（empty / fully-untracked / mixed）：太多、quota 成本高、選 mixed 為代表 case 即可

## Implementation Contract

#### Behavior

User 在 Claude Code 跑 `/codex-pro:adversarial-review` 或 `/codex-pro:review`（無 target argument 或 `--diff`）→ skill Step 1 收 target body：
1. 跑 `git diff HEAD`（pre-first-commit fallback 為 D5）
2. 列舉 untracked file（`git ls-files --others --exclude-standard`）
3. 對 untracked file：binary detection → path-list 或 content-eligible 分流（D3）
4. content-eligible file：size cap filter（D4）→ included / truncated / omitted 三分流
5. 合併 diff + included content + truncated content（含 marker）+ binary path list + omitted path list 為 target body
6. target_invalid pre-flight：合併後 whitespace-only → abort（D6）

#### Interface

- `/codex-pro:adversarial-review`：identifier `adversarial-review`、SKILL.md path 不變、frontmatter version v0.1 → v0.2
- `/codex-pro:review`：identifier `review`、SKILL.md path 不變、frontmatter version v0.1 → v0.2
- 兩 SKILL.md Step 1 「target three modes」第一條 default `--diff` mode 文字更新含 untracked semantics

#### Frontmatter changes

- `target` field 值：`diff` 或 `diff (pre-first-commit)` 兩種 marker
- 其他 field 不變

#### Result file body changes

包含三新段 (在 target body 區段內、不是 Codex output 區)：

- `### Untracked binaries omitted`（若有 binary）
- `### Untracked files omitted (aggregate size cap)`（若有 omitted）
- 注 content 的 untracked file 用 `### Untracked file: <path>` heading 標示（與 git diff 段區隔）

#### Failure modes

- target_invalid 延伸：post-filter empty → abort（D6）
- Empty repo 不 abort、走 fallback（D5）
- Binary file IO error（permission denied / 突然消失）→ 該 file skip + 加入 omitted list、不阻塞其他 file

#### Acceptance criteria

- 兩 SKILL.md Step 1 含 `git diff HEAD` + `git ls-files --others --exclude-standard`、`git check-attr binary`、`64KB` + `512KB`、`pre-first-commit`
- 兩 SKILL.md frontmatter description 含 `v0.2 — untracked-by-default`
- tests/review.sh + tests/adversarial-review.sh 各 +~20 assertion 含 5 fixture scenario
- tests/lib/assert.sh 含 `assert_git_fixture` helper
- `bash tests/run.sh` aggregate ~280 / 0 fail / 9 layers green
- Pre-archive smoke：兩 skill 各跑一次 mixed-state fixture、exit 0、target body 含至少一個 untracked path、binary path-only、oversize truncated marker
- CLAUDE.md + README.md row 更新 v0.2 + 行為變化備註
- 4 spec MODIFIED（review req 1 + 4、adversarial-review req 1 + 4）含新 scenario

#### Scope boundaries

In scope:
- 兩 producer skill Step 1 + Step 5 modification
- 兩 spec MODIFIED 各 2 requirement
- behavioral runtime test +5 scenario each skill
- `assert_git_fixture` helper
- CLAUDE.md + README.md row update
- plugin.json bump 0.3.0 → 0.4.0
- MANDATORY pre-archive smoke

Out of scope:
- rescue / setup / batch / status / result / cancel
- codex-call wrapper / parallel-ai-agents
- `--legacy-tracked-only` opt-out flag
- profile config mechanism (Constraint #5)
- token / cost observability (Constraint #6)
- background job mode
- multi-repo .codex-pro/

## Risks / Trade-offs

- [Binary detection NUL-byte sniff misclassifies edge cases] → 罕見 text file 含 NUL byte (e.g., UTF-16 encoded `.txt`) 會被 misdetect 為 binary。Mitigation: 8KB sniff window 是 industry convention、UTF-16 雖含 NUL 但 `git check-attr` 通常先檢查 `.gitattributes` 已 declare（user-controllable override）；real-world misdetect rate < 0.1%、可接受
- [64KB per-file cap 對 generated documentation 太緊] → user 跑 review on一個 100KB generated `.md` documentation file 會 truncate。Mitigation: v0.2 minimal、user 真需要可手動 `git stash --include-untracked` 然後用 `git stash show -p` 出 diff、或下個 cycle 加 profile config let user 設 per-file cap
- [Aggregate 512KB cap 在 monorepo 大 PR 太緊] → 跨檔大改 review 會碰 aggregate cap、omitted file list 變長。Mitigation: monorepo 大 PR 用 `--base <ref>` mode 而非 `--diff` 預設、那 mode 不適用本 size cap（已 explicit non-goal、不動 `--base` mode）
- [smoke gate 雙 skill 各跑一次 = 2 次 Codex quota] → 每次 archive 燒 2 次 xhigh effort call。Mitigation: 與 review v0.1 / rescue v0.1.1 / adversarial-review v0.1 smoke cost 同量級、屬 release 紀律 acceptable cost；rescue v0.1 broken-session ship 教訓比 smoke 成本高得多
- [`assert_git_fixture` helper 增加 tests/lib 維護面] → 多一個共用函式、未來改要 cross-check 跨多個 test。Mitigation: helper trivial（4 行 git config）、改機率低；單純 init.defaultBranch 統一已解 cross-machine flakiness 大頭
- [empty-repo fallback 邏輯增加 Step 1 複雜度] → Bash exit code 檢測 + stderr match 增加 SKILL.md prose 長度。Mitigation: fallback 是 documented edge case、SKILL.md prose 明示 + Layer 2 fixture scenario 4 覆蓋、未來 regression 容易抓
- [兩 skill 同時改、blast radius 增加] → 一個 change 改兩 producer、若 bug 同時 affect 兩 skill。Mitigation: D1 已論證分段策略反而 leave silent failure、同 cycle 改 safer because Layer 2 fixture 同時驗兩 skill；pre-archive smoke 兩 skill 各跑一次 catch any divergence
- [pre-1.0 minor bump policy 是否 user 真懂] → user 看 v0.1 → v0.2 是否認知 behavior change。Mitigation: CHANGELOG / SKILL.md frontmatter description / CLAUDE.md / README.md 四處明示 v0.2 untracked-by-default、user 升級走 `/plugin marketplace update` 後重新 `setup` 看 frontmatter 會看到
