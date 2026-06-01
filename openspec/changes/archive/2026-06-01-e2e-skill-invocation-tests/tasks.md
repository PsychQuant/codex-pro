# Tasks — e2e-skill-invocation-tests

實作 Layer 3 e2e automated test infrastructure：`tests/e2e.sh` standalone opt-in script、跑 `claude --print --plugin-dir` 觸發 real SKILL.md invocation、verify 10 組合（5 scenario × 2 skill）的 result file 結構 + behavioral marker。補 Layer 2 behavioral test 的 SKILL.md→runtime drift blind spot。

## 1. tests/lib/e2e-fixtures.sh（new）

- [x] 1.1 建立 `tests/lib/e2e-fixtures.sh` 並 export 5 fixture helper functions：`e2e_fixture_mixed(dir)`、`e2e_fixture_binary(dir)`、`e2e_fixture_oversize(dir)`、`e2e_fixture_empty_repo(dir)`、`e2e_fixture_all_empty(dir)`、各內呼 `assert_git_fixture` + scenario-specific file content（mixed: tracked.swift modified + untracked_normal.swift; binary: untracked_text.txt + untracked_image.png 含 NUL bytes; oversize: big.log 100KB; empty-repo: 無 commit + only_file.txt; all-empty: 無 commit + only_binary.bin 含 NUL bytes）。對應 design **D3: Fixture matrix — 5 scenario × 2 skill = 10 組合**。Acceptance: `bash -n tests/lib/e2e-fixtures.sh` 通過；source 後 5 個 function 可調用；fixture 內容與 Layer 2 behavioral fixture 對應一致（tests/review.sh + tests/adversarial-review.sh）。

## 2. tests/lib/e2e-claude-print.sh（new）

- [x] 2.1 建立 `tests/lib/e2e-claude-print.sh` 並 export `invoke_skill_via_claude_print(fixture_dir, skill_name)` function：cd 進 fixture、跑 `timeout 600 claude --print --plugin-dir <derived path> "/codex-pro:<skill>"`、return exit code via global `INVOKE_EXIT` 與 stdout capture via global `INVOKE_OUTPUT`。對應 design **D2: claude --print --plugin-dir 為 invocation mechanism** + **D7: cwd handling — invoke from fixture dir**。Acceptance: function 簽名正確、source 後可調用、用 dry-run test (trivial prompt without skill) 驗 mechanism 可用。
- [x] 2.2 在 `invoke_skill_via_claude_print` 內加 D4 retry policy：for loop 3 attempts、each attempt 跑 claude --print；grep stdout 含 `Server is temporarily limiting requests` substring → sleep $((30 * 2^(attempt-1))) 秒（30s, 60s, 120s）後 retry；其他 error 不 retry；3 attempts 後仍 throttle return non-zero。對應 design **D4: Retry policy on Anthropic API rate limit**。Acceptance: function body grep `Server is temporarily limiting requests` ≥ 1、`sleep` 含 backoff 表達式、retry counter cap = 3。
- [x] 2.3 derived plugin path：用 `dirname "$BASH_SOURCE"` + `/../../plugins/codex-pro` 算 repo-relative path、不 hardcode 絕對路徑、可在不同 maintainer 機器跑。Acceptance: function 不含字串 `/Users/che/Developer/codex-pro`；含 `BASH_SOURCE` 或 `SCRIPT_DIR` 動態 derive 語法。

## 3. tests/e2e.sh（new main script）

- [x] 3.1 [P] 建立 `tests/e2e.sh` 骨架：shebang、`set -uo pipefail`、source `tests/lib/assert.sh`、source `tests/lib/e2e-fixtures.sh`、source `tests/lib/e2e-claude-print.sh`、parse `--skill <name>` + `--scenario <name>` argument、reject invalid value with usage hint + exit 2、missing flag 也同樣 reject。對應 spec **e2e test script registration and argument parsing** 5 scenarios。Acceptance: `bash -n tests/e2e.sh` 通過；跑 `bash tests/e2e.sh` 印 usage + exit 2；跑 `bash tests/e2e.sh --skill bogus --scenario mixed` 印 usage + exit 2；跑 `bash tests/e2e.sh --skill review --scenario bogus` 印 usage + exit 2。
- [x] 3.2 加 fixture setup：mktemp + dispatch `e2e_fixture_<scenario>` based on `--scenario` value；trap EXIT 自動 `rm -rf "$TMP"`。Acceptance: 5 scenario 各跑都能建出對應 fixture state（手動 verify by cd進 + git status）。
- [x] 3.3 加 invocation step：`invoke_skill_via_claude_print "$TMP" "$SKILL"` + capture exit code、stdout；若 invoke return 非 0（包含 rate limit 3 retry fail），exit 4 + print 訊息。對應 spec **e2e invokes real SKILL.md via claude --print --plugin-dir** 3 scenarios + design **D4**。Acceptance: script 跑時觀察到 claude session 啟動、傳 skill prompt、return exit code。
- [x] 3.4 加 result file path lookup：用 glob `$TMP/.codex-pro/${SKILL}-*.md` 找 result file、若不存在 exit 5 with error。對應 spec **e2e verifies result file structure** "Result file path verified" scenario + design **D6: Verification surface**。Acceptance: 5 scenario 跑成功（claude 正常退）後、能找到 result file；不存在時清楚錯誤訊息。
- [x] 3.5 加 scenario-specific verification logic 為 case dispatch on `$SCENARIO`：mixed → grep untracked path + `## Summary` (review) 或 4 H2 (adversarial-review)；binary → grep `### Untracked binaries omitted` + binary path + assert content 不在 body；oversize → grep `truncated at 64KB of 100000 bytes`；empty-repo → grep `target: diff (pre-first-commit)` in frontmatter + untracked content in body；all-empty → grep `error: target_invalid` + (review only) `findings_count: 0`。對應 spec **e2e verifies result file structure and behavioral markers per scenario** 6 scenarios。Acceptance: 5 scenario × 2 skill = 10 組合 each fail-fast on missing marker + exit 6；pass 印 summary line + exit 0。
- [x] 3.6 加 adversarial-review 4-section non-empty enforcement：對 adversarial-review skill、scenario 非 all-empty 時、用 python3 / awk 拆 body 4 H2 段、each section body whitespace-strip 後 char count > 200。對應 spec **Adversarial-review section non-empty enforcement** scenario + design **D6**。Acceptance: paragraph length cutoff 200 chars、stub answer 會 fail。

## 4. tests/e2e-checklist.md update

- [x] 4.1 [P] 修改 `tests/e2e-checklist.md`：頭段加 Layer 3 automated e2e 概述、10 組合 listed as explicit `bash tests/e2e.sh --skill X --scenario Y` 命令；加 quota / 時間 budget 段：「~10 codex-call quota + ~500k Claude API tokens、預估 10-30min full run、$0.5-$2 cost」；加 rate limit recovery 段：「若 stdout 含 `Server is temporarily limiting requests`、自動 retry 3 次 30s/60s/120s backoff；若仍 fail、手動 wait 5min 後重跑」。對應 spec **e2e is opt-in and excluded from default tests/run.sh** "tests/e2e-checklist.md documents quota + time budget" scenario + design **D5: Quota budget per ship documented**。Acceptance: `grep "~10 codex-call" tests/e2e-checklist.md` ≥ 1、`grep "rate limit\|Server is temporarily limiting requests" tests/e2e-checklist.md` ≥ 1、10 組合命令各 ≥ 1 次出現。

## 5. tests/run.sh header comment

- [x] 5.1 [P] 修改 `tests/run.sh` header comment：加 Layer 3 opt-in 註明（如「Layer 3 e2e is opt-in via `bash tests/e2e.sh --skill <name> --scenario <name>` — not dispatched here due to ~10 codex-call quota cost and API rate limit flakiness」）；確認檔內無 `run_layer e2e` 或 `bash tests/e2e.sh` 字串（強制 exclude e2e）。對應 spec **e2e is opt-in and excluded from default tests/run.sh** "tests/run.sh does not invoke e2e.sh" scenario。Acceptance: `grep "Layer 3" tests/run.sh` ≥ 1、`grep -c "run_layer e2e\|bash tests/e2e.sh" tests/run.sh` 等於 0。

## 6. CLAUDE.md Tests section update

- [x] 6.1 修改 `CLAUDE.md` Tests 段：原 3 layer 表（Layer 1 static / Layer 2 behavioral / Layer 3 manual checklist）加 row Layer 3 e2e（在 manual checklist 行之上或之下）— `bash tests/e2e.sh --skill X --scenario Y`、10 組合、opt-in per release、~10 codex-call quota、predominantly verifies SKILL→runtime drift。對應 spec **CLAUDE.md Tests section includes Layer 3 row** scenario。Acceptance: `grep "tests/e2e.sh" CLAUDE.md` ≥ 1、`grep "Layer 3.*e2e\|e2e.*Layer 3" CLAUDE.md` ≥ 1、`grep "opt-in" CLAUDE.md` ≥ 1（in Tests section）。

## 7. README.md Tests section update

- [x] 7.1 修改 `README.md` Tests 段：加 Layer 3 opt-in 描述 + 一句說明 e2e 為 release gate（不是 commit gate）+ refer 到 `tests/e2e-checklist.md` 看 procedural detail。Acceptance: `grep "tests/e2e.sh\|Layer 3 opt-in" README.md` ≥ 1。

## 8. 整合驗證

- [x] 8.1 跑 1 組合 dry-run 驗 mechanism：`bash tests/e2e.sh --skill review --scenario empty-repo`（最便宜 scenario）、確認 (a) fixture 建出、(b) claude session 啟動 + skill 觸發、(c) result file 寫到 fixture 的 .codex-pro/、(d) frontmatter `target: diff (pre-first-commit)` marker 存在、(e) script exit 0。Acceptance: 1 組合 PASS（若 rate limit 衝到、retry policy 觸發、最後 PASS）。
- [x] 8.2 跑剩餘 9 組合 verify full matrix：empty-repo × adversarial-review、mixed × 2 skill、binary × 2 skill、oversize × 2 skill、all-empty × 2 skill；每組合各跑 1 次、log 結果、cumulative pass。Acceptance: 9/9 PASS（或可 acceptable 有 1-2 個因 rate limit/codex quota 個別 fail、需 record + retry）；全 pass 後算 release gate clear。
- [x] 8.3 跑 `bash tests/run.sh` 確認 Layer 1+2 仍 290 assertions / 9 layers green、未被 e2e infrastructure 影響、e2e.sh 沒進 dispatcher。Acceptance: aggregate 290 / 0 fail / 9 layers all green、`bash tests/run.sh; echo $?` 印 0。

## Coverage map

本 change task → spec requirement → design decision 對應（analyzer 用此區段 cross-check；勿因美觀刪除）。

### Spec requirements covered

- **e2e test script registration and argument parsing** → tasks 3.1（usage / 5 scenarios all addressed）
- **e2e invokes real SKILL.md via claude --print --plugin-dir** → tasks 2.1 + 2.2 + 2.3 + 3.3（invocation mechanism + retry + derived path）
- **e2e verifies result file structure and behavioral markers per scenario** → tasks 3.4 + 3.5 + 3.6（path lookup + 5 scenario dispatch + adversarial 4 H2 non-empty）
- **e2e is opt-in and excluded from default tests/run.sh** → tasks 4.1 + 5.1 + 6.1 + 7.1（checklist + run.sh header + CLAUDE.md + README.md docs）

### Design decisions covered

- **D1: Layer 3 為 opt-in script 而非 default `tests/run.sh` extension** → tasks 5.1 + 6.1 + 7.1（run.sh header / CLAUDE.md / README.md docs）
- **D2: `claude --print --plugin-dir` 為 invocation mechanism** → tasks 2.1 + 2.3（invocation function + derived plugin path）
- **D3: Fixture matrix — 5 scenario × 2 skill = 10 組合** → tasks 1.1 + 3.5 + 8.1 + 8.2（5 fixture helper + per-scenario verify + 10 組合 full matrix run）
- **D4: Retry policy on Anthropic API rate limit** → task 2.2（exponential backoff 30s/60s/120s 3 attempts）
- **D5: Quota budget per ship documented** → task 4.1（checklist 含 quota + 時間 + cost 段）
- **D6: Verification surface — result file structure + behavioral marker、不驗 LLM content** → tasks 3.4 + 3.5 + 3.6（path / structural marker / 4 H2 non-empty）
- **D7: cwd handling — invoke from fixture dir, accept session reset** → task 2.1（cd 進 fixture 啟動 claude）
- **D8: Boundary with Layer 2 behavioral test — complementary, not replacement** → tasks 6.1 + 7.1（CLAUDE.md + README.md 描述 cumulative coverage）
