## Context

codex-pro v0.4.0 ship 6 archive cycles 累積的 test pyramid：

- **Layer 1 (static)** — `tests/static.sh` manifest schema + per-skill frontmatter loop + namespace consistency grep；55 assertions、純 grep / JSON parse、不 invoke 任何 binary
- **Layer 2 (behavioral)** — `tests/<skill>.sh` 各層、structural grep + (read-only consumer skills) behavioral runtime test (mktemp + fake `.codex-pro/`) 或 (producer skills) collection logic re-implementation；290 assertions cross 9 layers、跑 git / python3 / 不 invoke codex-call
- **Layer 3 (manual)** — `tests/e2e-checklist.md` 文字 checklist；目前 ≥12 條手動驗證、無 automation

過去 rescue v0.1 broken-`--session` flag 的教訓導致 [[feedback-codex-pro-smoke-before-archive]] memory + pre-archive smoke gate（producer skill change archive 前手動 1 次 real codex-call）。但 smoke 不解兩個 gap：

1. **Smoke 是手動 build prompt file**：我 cat 出 instructions 自己拼 prompt、跑 codex-call、不真正觸發「Claude 讀 SKILL.md 跑 invocation」流程
2. **Smoke 只 1 次 per archive**：覆蓋 1 個 scenario（typically mixed-state）— binary / oversize / empty-repo / all-empty target_invalid 等都沒覆蓋

v0.4 user 質疑「test 完整嗎」、答案是「Layer 1+2 全綠但 SKILL.md→runtime drift 仍可能」。本 change 引入 **Layer 3 automated e2e** 直接 invoke `claude --print --plugin-dir` 跑 SKILL.md prose、補 drift 風險的 architectural blind spot。

預先驗證的 dry run 證實 mechanism 可用：`claude --print --plugin-dir <codex-pro plugin path> "/codex-pro:review"` 在 <15s 完成 session start + skill resolution；trivial prompt return OK。Rate limit hit on first real attempt — 必須 build retry policy。

## Goals / Non-Goals

**Goals:**

- `tests/e2e.sh` standalone opt-in script、fresh `claude --print` invocation、5 fixture scenario × 2 skill = 10 組合
- Verification surface：result file 結構（path + frontmatter + body section heading）+ behavioral content marker（untracked path / binary heading / truncation marker / target_invalid frontmatter error）
- Retry policy 處理 Anthropic API server-side rate limit（觀察過 `Server is temporarily limiting requests` 訊息）
- Helper 模組化：`tests/lib/e2e-claude-print.sh`（invocation + retry）+ `tests/lib/e2e-fixtures.sh`（5 scenario 各一 helper、DRY 共用於 Layer 2 + Layer 3）
- 不進 default `tests/run.sh`、opt-in per pre-release
- CLAUDE.md + README.md + tests/e2e-checklist.md 更新 reflect Layer 3 layer 與 opt-in 性質
- Quota budget documented：每 full Layer 3 ~10 codex-call + ~500k Claude API tokens

**Non-Goals:**

- 不加 CI / GitHub Actions automation
- 不對 setup / batch / rescue / status / result / cancel 寫 e2e（限定 review + adversarial-review）
- 不擴 `--base <ref>` 或 positional file mode（限定 default `--diff` mode）
- 不 LLM output content 驗證（除 structural marker）
- 不取代 Layer 2 behavioral test 或 pre-archive smoke
- 不引入 new runtime dependency
- 不 Windows 支援
- 不改 SKILL.md（read-only consumer of SKILL.md prose）
- 不改 result file schema / 不改 producer skill 行為
- 不引入 Codex tier / quota observability（留 future config skill change）
- 不 cache e2e results between runs（每次 fresh fixture + fresh claude session）

## Decisions

### D1: Layer 3 為 opt-in script 而非 default `tests/run.sh` extension

採 **`bash tests/e2e.sh` standalone opt-in**、不採「加入 `tests/run.sh` 作第 10 layer」。

理由：

- **Quota cost**：每 full 10 組合 = 10 codex-call invocation = ~10 quota burn + Claude API ~500k tokens（按 Claude Code session startup 50k + skill execution 30k 估）；default `tests/run.sh` 跑 30s 變 3min+ 不可接受
- **Rate limit flakiness**：Anthropic API 偶 server-side throttle、`tests/run.sh` CI 跑會頻繁紅；opt-in 讓 user retry
- **Pre-release cadence**：Layer 3 用於 release gate、不是 commit gate；與 Layer 1+2 不同 cadence、不應 entangle
- **Test infrastructure parallel discipline**：past archive cycle 也是 manual smoke per archive、`tests/run.sh` 仍 fast，相同 pattern 沿用到 Layer 3
- **Failure semantics 不同**：Layer 1+2 fail 意味 SKILL 結構 / 邏輯壞；Layer 3 fail 可能是 SKILL drift / Claude 行為改變 / API throttle — 分流避免 false-positive 蓋過 true failure

Alternatives:

- 加進 `tests/run.sh` 預設跑：上述五點都 fail
- 環境變數 `E2E=1 bash tests/run.sh` toggle：可、但 conventions 上 standalone script clearer
- 完全靠 `tests/e2e-checklist.md` manual：不 scriptable、無 retry policy 整合、unverifiable
- CI cron 跑 e2e：v0.1 scope 外、無 GitHub Actions setup

### D2: `claude --print --plugin-dir` 為 invocation mechanism

採 **`claude --print --plugin-dir <plugin path> "/codex-pro:<skill>"`**、不採 stdin / Claude SDK programmatic invocation。

理由：

- `claude --print` 是官方 non-interactive flag、無 session daemon 殘留
- `--plugin-dir <path>` 直接 load plugin、不需 marketplace install（本機開發友善）
- prompt 直接 trigger skill via `/codex-pro:<skill>` namespace syntax — Claude Code skill router 自動 resolve
- stdout 為 Claude response markdown、可 parse 但本 e2e 不靠 stdout content（靠 result file）
- exit code 為 Claude session exit、true 0 = session normal exit、非 0 = error
- Dry run 已 verify：`<15s` startup + skill load + trivial prompt return

Alternatives:

- SDK programmatic invocation：增加 runtime dependency（Anthropic SDK）、本 change non-goal
- Marketplace installed plugin：要求 user 跑 `/plugin marketplace update` + `/plugin update`、e2e setup 變繁瑣；`--plugin-dir` 直接指 repo path 更 dev-friendly
- `claude` interactive mode + expect script：fragile、interactive prompts 變化會 break

### D3: Fixture matrix — 5 scenario × 2 skill = 10 組合

採 **5 scenario × 2 skill = 10 組合**、與 Layer 2 behavioral fixture 1-to-1 對應、不擴 fixture count。

Scenarios（同 v0.4 design D8）：

1. **mixed** — tracked modified + untracked normal text → 兩類都進 target body、success
2. **binary** — untracked .png (NUL bytes) + untracked text → binary path-listed 不注 content、text 注、success
3. **oversize** — untracked 100KB .log → 64KB truncated with marker、success
4. **empty-repo** — fresh `git init` + 1 untracked → fallback path、`target: diff (pre-first-commit)` marker
5. **all-empty** — empty repo + binary-only → target_invalid post-filter pre-flight fire、frontmatter `error: target_invalid`

Skills：`review`、`adversarial-review`。

理由：

- 1-to-1 對應 Layer 2 behavioral scenario — 同 fixture state、不同 verification layer（Layer 2 跑 test-script-internal logic、Layer 3 跑 Claude-reads-SKILL real logic）
- 兩者比對 = drift 偵測機制：若同 fixture 在 Layer 2 PASS 但 Layer 3 FAIL，表示 SKILL.md prose 不對 / Claude misinterpret / codex-call 行為改變、必查
- 不擴新 scenario（v0.1 minimal）：edge case 留 future cycle（spaces in filename / symlinks / submodules / gitignore interaction / permission errors / large file count）
- 2 producer skill 為 v0.4 fix 範圍、其他 skill blind spot 較低（read-only consumer 已 Layer 2 behavioral 涵蓋、rescue / batch 不在 v0.4 scope）

Alternatives:

- 只 5 scenario × 1 skill = 5 組合：少抓 cross-skill SKILL.md 一致性 drift
- 擴 7-10 scenario：未來 cycle 加、v0.1 不必
- Random fixture 生成：non-deterministic、debugging 困難

### D4: Retry policy on Anthropic API rate limit

採 **exponential backoff、最多 3 次 retry、only retry on `Server is temporarily limiting requests` substring match**、不採 unconditional retry。

Algorithm：

```bash
for attempt in 1 2 3; do
  out=$(timeout 600 claude --print --plugin-dir "$PLUGIN" "/codex-pro:$SKILL" 2>&1)
  rc=$?
  if echo "$out" | grep -q 'Server is temporarily limiting requests'; then
    backoff=$((30 * 2 ** (attempt - 1)))  # 30s, 60s, 120s
    echo "Rate limit hit on attempt $attempt — sleeping ${backoff}s before retry"
    sleep $backoff
    continue
  fi
  break
done
```

理由：

- Anthropic server-side throttle 是 **transient** condition、retry 預期解決
- Exponential backoff 30s / 60s / 120s = 3.5min total worst case、acceptable for opt-in pre-release
- 3 次 retry cap 避免無限 loop（與 fail-fast 紀律一致）
- Only retry on specific message — 其他 error（session error / SKILL.md typo / codex-call quota exhausted）should fail immediately、unconditional retry 會 mask 真 bug
- Codex quota exhausted（rate_limit / `error: rate_limit`）為**真實 quota** failure、由 codex-call 內部 fail-fast 處理、e2e 觀察為 result file 出現 `error: rate_limit` frontmatter、不該 retry

Alternatives:

- Unconditional retry：mask real failure
- 5+ retry attempts：太慢、user 應自己 retry full run
- Linear backoff 30s constant：throttle 解除時間不固定、exponential 更 robust
- Retry-After header parsing：Anthropic 不 standard 化 header、`Server is temporarily limiting` substring 較穩

### D5: Quota budget per ship documented

採 **per full Layer 3 = 10 codex-call quota + ~500k Claude API tokens、documented in CLAUDE.md + tests/e2e-checklist.md**、不採 silent cost。

預估：

- 10 組合 × 1 codex-call/組合 = 10 codex-call invocation = ~10 Codex tier quota burn（xhigh effort、6-8KB output）
- 10 組合 × ~50k Claude API token/組合 = ~500k Claude API tokens（按 Claude Code session startup 30k + skill execution 20k 估）
- 預估時間：10 × 60-180s = 10-30min full run
- 預估 cost：~$0.50-$2.00 Claude API + 10 codex quota（depends tier）

理由：

- User 跑 Layer 3 前看得到 cost、做 informed decision
- Pre-release cadence（1-2 次 per release）可 absorb cost、不像 commit cadence 無法承受
- Documentation 是 displayed limitation discipline 的一部分（與 cancel skill informational only 同心智）
- 若未來 cost 結構改變（codex-call 改 model、Claude API 改 pricing），文檔 inline 更新

Alternatives:

- 不列 cost：silent burn、user 跑 1 次才知道
- 列為 `~$N` 估算：估算過細未來 outdated
- 引入 quota counter / pre-check：v0.1 scope 外

### D6: Verification surface — result file structure + behavioral marker、不驗 LLM content

採 **驗 result file 結構（path + frontmatter field + body H2 heading）+ behavioral marker（untracked path 字串 / `### Untracked binaries omitted` heading / `truncated at 64KB` marker / `error: target_invalid`）**、不驗 LLM 自由文本內容。

驗證 matrix（per scenario × skill）：

| Scenario | review verify | adversarial-review verify |
|---|---|---|
| mixed | result file 存在、`## Summary` + `## Findings`、`### Untracked file:` 段含 fixture untracked path | result file 存在、4 H2 各 non-empty (paragraph chars > 200)、target body 含 fixture untracked path |
| binary | result file 存在、`### Untracked binaries omitted` heading + .png path 列、binary content 不出現 | 同 + 4 H2 non-empty |
| oversize | result file 存在、`truncated at 64KB of 100000 bytes` marker、`### Findings` 存在 | 同 + 4 H2 non-empty |
| empty-repo | result file 存在、frontmatter `target: diff (pre-first-commit)`、untracked content 進 body | 同 |
| all-empty | result file 存在、frontmatter `error: target_invalid` + `findings_count: 0`（review） | 同（adversarial 用 `error: target_invalid`）|

理由：

- LLM output 是 non-deterministic — 驗 wording 會 flaky、無法 reproduce
- Structural marker（heading / frontmatter field / fixture path）是 deterministic — Claude must produce them per SKILL.md spec
- behavioral marker（`### Untracked binaries omitted` heading / `truncated at 64KB` marker）是 SKILL.md prose 明示產出、Claude 跟 prose 走應該 produce、Layer 3 確認 Claude 真的 follow
- target_invalid frontmatter 是 v0.2 第 4 fail-fast class、必須出現於 fixture 5 (all-empty) — 驗 Claude 真的 pre-flight + abort
- Body section heading（`## Summary` / `## Findings` for review、4 H2 for adversarial）是 Step 3 system instructions 規範、Claude 必 produce
- Paragraph length cutoff（200 chars）為 "section non-empty" 的 quantitative threshold、避免 stub answer

Alternatives:

- 驗 LLM output 完整一致：flaky、impossible
- 不驗 behavioral marker、只驗 file 存在：失去 v0.4 fix 驗證價值
- 驗 fingerprint hash of result file：Codex output non-deterministic、永遠 fail

### D7: cwd handling — invoke from fixture dir, accept session reset

採 **`cd "$FIXTURE_DIR" && claude --print ...` 從 fixture cwd 啟動、接受 post-exit shell hook 把 cwd reset 回 project root**、不採額外 cwd 管理。

理由：

- Dry run 觀察：`cd "$FIX" && claude --print ...` 之後 shell 顯示 "Shell cwd was reset to /Users/che/Developer/codex-pro"（user-defined hook）
- Claude session 本身內部 cwd = 啟動時 inherit 的 dir（`$FIX`）— Bash tool / Read tool 都從那 dir 跑
- Skill 在 fixture cwd 跑 `git diff HEAD` / `git ls-files`、寫 result file 進 `.codex-pro/`、全 fixture-local
- 父 shell 被 hook reset 不影響 session 內部 cwd
- 驗 result file 用 `$FIX/.codex-pro/<skill>-*.md` 絕對路徑、不受 reset 影響

Alternatives:

- 用 `claude --add-dir "$FIX" --print ...` 不 cd：unclear 是否 claude 用 default cwd 跑 git commands；hooks 可能仍 reset
- 用 `bash -c "cd $FIX && claude --print ..."` 包：cwd reset 同樣行為
- 用 sub-shell `(cd "$FIX" && claude --print ...)`：sub-shell cwd 隔離、但 inner 行為相同

### D8: Boundary with Layer 2 behavioral test — complementary, not replacement

採 **Layer 2 behavioral + Layer 3 e2e cumulative coverage**、不採「Layer 3 取代 Layer 2」。

Layer 對比：

| Aspect | Layer 2 behavioral | Layer 3 e2e |
|---|---|---|
| What it runs | test script 自 implement 的 collection function | Claude 解讀 SKILL.md prose 拼出 invocation |
| When it runs | every `bash tests/run.sh`（commit gate） | opt-in per release（release gate） |
| Cost | <2s + 0 quota | 10-30min + 10 quota + $0.5-$2 |
| Catches | logic bug in test's mock invocation | SKILL.md prose ambiguity, Claude misinterpretation, codex-call behavior change |
| Misses | SKILL.md→runtime drift | flaky on API rate limit, expensive |

Cross-layer verification：若 Layer 2 PASS + Layer 3 FAIL → 表示 test 的 mock implementation 與 SKILL.md prose 不一致 / Claude misinterpret prose → 必查 SKILL.md。若 Layer 2 FAIL + Layer 3 PASS → 不太可能（test mock implementation 錯）。若 兩 layer 都 PASS → high confidence。

理由：

- 兩 layer 不同 verification surface、不能取代
- Cost / cadence 不同、自然分流
- Drift detection 機制 valuable — comparing assertions across layer 找 ambiguity
- Mock implementation in Layer 2 不必精確 follow SKILL.md prose、目的是驗 spec 邏輯；Layer 3 才驗 prose itself

Alternatives:

- Layer 3 取代 Layer 2：太慢、無法每 commit 跑、CI velocity drop
- 不寫 Layer 3：v0.4 user 已點明此 gap、必補
- 把 Layer 2 也改成 Claude-driven：cost / 速度 / flakiness 都升至 Layer 3 量級

## Implementation Contract

#### Behavior

User 在 codex-pro repo root 跑 `bash tests/e2e.sh --skill <name> --scenario <name>` →

1. Parse `--skill` （必 `review` 或 `adversarial-review`）
2. Parse `--scenario` （必 `mixed` / `binary` / `oversize` / `empty-repo` / `all-empty` 之一）
3. mktemp + `assert_git_fixture` + `e2e_fixture_<scenario>` 建 fixture repo
4. `invoke_skill_via_claude_print "$FIXTURE_DIR" "$SKILL"` → 跑 `claude --print --plugin-dir <codex-pro plugin path> "/codex-pro:$SKILL"`、含 D4 retry policy
5. Verify `.codex-pro/<skill>-<ISO8601>.md` 存在 + 結構（D6 verification matrix）
6. 印 summary：scenario / skill / pass-fail / result file path
7. Exit 0 = pass、非 0 = fail

#### Interface

- `tests/e2e.sh` — standalone script、`--skill` + `--scenario` required、無 default、unknown value reject + usage hint
- `tests/lib/e2e-claude-print.sh` — exports function `invoke_skill_via_claude_print(fixture_dir, skill_name)` → returns `(exit_code, result_file_path)`
- `tests/lib/e2e-fixtures.sh` — exports `e2e_fixture_mixed(dir)`、`e2e_fixture_binary(dir)`、`e2e_fixture_oversize(dir)`、`e2e_fixture_empty_repo(dir)`、`e2e_fixture_all_empty(dir)`、各自共用 `assert_git_fixture`

#### Failure modes

- Unknown `--skill` 或 `--scenario` value → usage hint + exit 2
- Both `--skill` 和 `--scenario` 都缺 → 印 usage + exit 2
- `claude` CLI 不在 PATH → fail + exit 3
- `--plugin-dir` 指 path 不存在 → fail + exit 3
- Anthropic API rate limit 3 次 retry 後仍 throttle → fail + exit 4
- Codex-call rate limit / oauth invalid / timeout → 觀察為 result file 的 `error:` frontmatter、e2e PASS for the scenario "fail-fast was triggered"（驗 fail-fast 路徑作為 valid result）
- Result file 不存在 → fail + exit 5
- Result file 結構 verification fail → 印 missing marker + exit 6

#### Acceptance criteria

- `tests/e2e.sh` 可獨立跑、accept `--skill <name> --scenario <name>` flag
- 10 組合（5 scenario × 2 skill）皆可 invoke、verify 結果
- 5 scenario fixture 邏輯與 Layer 2 behavioral fixture 對應一致（同 fixture state）
- Retry policy on `Server is temporarily limiting requests` substring match
- `tests/run.sh` header comment 註明 Layer 3 opt-in
- `tests/e2e-checklist.md` 更新為 script invocation 指引
- CLAUDE.md + README.md 加 Layer 3 描述含 quota / 時間 / opt-in

#### Scope boundaries

In scope:

- tests/e2e.sh + 2 helper scripts
- 5 scenario × 2 skill verification matrix
- Retry policy on Anthropic API throttle
- Docs (tests/e2e-checklist.md / CLAUDE.md / README.md / tests/run.sh header)

Out of scope:

- 其他 skill（setup / batch / rescue / status / result / cancel）的 e2e
- `--base <ref>` / positional file mode 的 e2e
- CI / GitHub Actions automation
- LLM content / wording 驗證
- Codex tier / quota observability
- 改任一 SKILL.md / 改 producer 行為
- Pre-archive smoke gate 改變

## Risks / Trade-offs

- [Anthropic API rate limit makes Layer 3 flaky] → opt-in 跑時可能 throttle。Mitigation: D4 exponential backoff 30s/60s/120s 最多 3 次 retry、不過跑會 fail clear；user 可手動 wait 後重試；不入 default `tests/run.sh` 不會 block commit。
- [10 組合 cost ~$0.50-$2 + 10 codex quota] → 每 pre-release 跑 cost。Mitigation: D5 documented、user informed decision；release cadence 預估 1-2 次 per release; cost 與 SKILL→runtime drift 預防價值對比 acceptable
- [Claude --print session cwd reset by user hook] → 觀察到 hook reset cwd 回 project root。Mitigation: D7 從 fixture cwd 啟動 claude、session 內部繼承 fixture cwd 不受 hook 影響；用絕對路徑 `$FIX/.codex-pro/` 驗 result file 不受影響。
- [Verification depends on Claude correctly resolving `/codex-pro:<skill>` namespace] → 若 Claude session 找不到 skill 或 resolve 錯 → e2e fail。Mitigation: dry run 已 verify `--plugin-dir <plugin path>` 可正確 load skill；若未來 Claude Code skill resolution 行為改變、e2e 將 fail clearly 而非 silent pass
- [5 scenario fixture 與 Layer 2 fixture overlap、未來 sync 維護成本] → Layer 2 fixture 改、Layer 3 fixture 必同步、雙倍維護。Mitigation: D3 提出 `tests/lib/e2e-fixtures.sh` 共用 helper 為 single source of truth、Layer 2 改為 source 該 helper（v0.2 scope、不 v0.1 強制；v0.1 接受 1 次 copy-paste 同步）
- [Smoke gate vs e2e overlap、未來決定 deprecate smoke gate？] → e2e 涵蓋 smoke 大部分驗證 surface + 自動化。Mitigation: 本 change Non-Goals 明示不取代 smoke、評估留 future cycle；smoke 為 archive-per-cycle、e2e 為 release-per-cycle、不同 cadence；待 e2e 穩定 3-4 cycle 再評估 deprecate smoke 紀律
- [Codex quota 突發耗盡 mid-run] → 跑 5 組合後 codex quota exhausted、後 5 組合都 fail with `error: rate_limit`。Mitigation: 接受 partial pass、checklist 明示 user 可分 day 跑、cumulative pass 算 release gate clear；codex tier 紀律由 user 自管
- [Plugin discovery via `--plugin-dir` 限本機 codex-pro repo path] → e2e.sh 要硬編 plugin path 或從 env 拿。Mitigation: 用 repo relative path `$REPO_ROOT/plugins/codex-pro` 動態 derive、不 hardcode；非本 codex-pro repo 跑（如 CI 不同 path）需 export env var
