## 1. Helper lib（共用 assertion + isolation）

- [x] 1.1 建立 tests/lib/assert.sh（D2: Runner 採 pure Bash + small helper lib）：產出 helper functions — `assert_eq`、`assert_contains`、`assert_file`、`assert_no_file`、`assert_sha256`、`assert_exit`、`fail`、`pass`；維護全局 PASS_COUNT / FAIL_COUNT；提供 `report_summary` 函數列印最終統計。驗證：跑空 test（只 source assert.sh 不 assert 任何）應 exit 0；故意跑 `assert_eq a b` 應 fail；shellcheck-style 跑 `bash -n tests/lib/assert.sh` exit 0。
- [x] 1.2 建立 tests/lib/isolate.sh（D3: Isolation 策略採 sub-shell 變數 override）：產出 3 個 wrapper — `with_empty_home <cmd>`、`with_path_stripped <cmd>`、`with_fake_plugin_root <body>`；mktemp 用法須 cleanup（trap EXIT 或 explicit rm）。驗證：跑 `with_empty_home env` 顯示 `HOME=/nonexistent`；跑 `with_fake_plugin_root 'cat $CLAUDE_PLUGIN_ROOT/.claude-plugin/test.txt'` 後 mktemp dir 不存在。

## 2. Layer 1 static

- [x] 2.1 建立 tests/static.sh（D4: Layer scope split、D5: Known-good invariants 編碼為 assertion）：實作 **Static layer enforces structural invariants** requirement 的所有 scenarios — manifest JSON parse（marketplace.json + plugin.json）、SKILL.md frontmatter parse（setup + batch、name 與 dir basename 一致、allowed-tools 含 Bash）、`bash -n` 對 tests/*.sh 與 script-template.sh、batch template sha256 比對 hardcoded `746157138caf13436711b92f82af6570843d31c964387aa0b0ccb80c9983c1b0`、namespace consistency grep（`/codex-pro-setup` = 0 於 CLAUDE.md/README.md/main specs、`/codex-pro:` ≥ 1）。驗證：跑 `bash tests/static.sh` 全 pass；故意把 marketplace.json 改成 invalid JSON 後跑 static.sh 對應 assertion fail；故意改 batch template 一字元後 sha256 assertion fail。

## 3. Layer 2 behavioral

- [x] 3.1 建立 tests/setup.sh（D4: Layer scope split、D3 sub-shell isolation）：實作 **Behavioral layer reproduces skill scenarios in isolated environments** 中與 setup 相關的 scenarios — `with_empty_home` 跑 setup 的 OAuth token check assert `missing` 輸出；用 mktemp + chmod 600 fake auth.json 跑 assert `readable mode=600`；`with_path_stripped` 跑 codex-call PATH check assert `missing`；`with_fake_plugin_root` 寫壞 JSON 跑 manifest self-check assert 含 `parse_error`；`ls -la ~/.codex/` 前後 diff exit 0 證明 read-only。驗證：跑 `bash tests/setup.sh` 全 pass、執行前後 `~/.codex/` 完全未變。
- [x] 3.2 建立 tests/batch.sh（D4: Layer scope split、D5: Known-good invariants）：實作 **Behavioral layer ...** 中與 batch 相關的 scenarios — SKILL.md body grep `exception` ≥ 1、`constraint` ≥ 1、`Design constraint #1` 字串存在；template grep `codex exec` 或 `"$CODEX" exec` ≥ 1、`--full-auto` ≥ 1、`&` 與 `wait` 各 ≥ 1（parallel orchestration markers）；template sha256 與 hardcoded 一致（與 static.sh 的 sha check 重複但獨立驗）。驗證：跑 `bash tests/batch.sh` 全 pass；故意刪除 SKILL.md 內 exception 段後跑 batch.sh 對應 assertion fail。

## 4. Layer 3 manual + Runner

- [x] 4.1 建立 tests/e2e-checklist.md（D4: Layer scope split）：實作 **Manual e2e checklist provides UI verification steps** requirement — markdown 文件含 ≥ 6 個 `- [ ]` checkbox 條目，順序：(a) `/plugin marketplace add` 安裝、(b) `/codex-pro:setup` ready 全綠、(c) `/codex-pro:setup` 缺 OAuth 報 `codex login`、(d) `/codex-pro:batch` 觸發、(e) batch 詢問 5 個 required params、(f) 跑完後 `~/.codex/` 未變動、附加跑 tests/run.sh 前置一條。驗證：grep `^- \[ \]` tests/e2e-checklist.md ≥ 6；每條含具體命令或預期觀察。
- [x] 4.2 建立 tests/run.sh dispatcher（D1: Layout 採 tests/ at root + per-layer entry script）：實作 **Test runner entry point** requirement 的所有 scenarios — source lib/assert.sh、source lib/isolate.sh、依序跑 tests/static.sh、tests/setup.sh、tests/batch.sh、aggregate 各 layer pass/fail count、report_summary、依 FAIL_COUNT 決定 exit code；於開頭 `command -v python3` check fail fast。驗證：`bash tests/run.sh` 全綠時 exit 0、含 final summary；故意改壞 marketplace.json 跑 run.sh exit 非 0 + 顯示失敗 assertion；單獨跑 `bash tests/static.sh` 也能獨立 exit code 0。

## 5. Doc 更新 + 端到端驗收

- [x] 5.1 更新 codex-pro CLAUDE.md：Development workflow 段新增「實作 / 變更 SKILL 後跑 `bash tests/run.sh`」一條；新增 Tests 段（含 layer 簡述、單獨跑各 layer 命令）。驗證：grep `tests/run.sh` CLAUDE.md ≥ 1、grep `tests/static.sh` ≥ 1。
- [x] 5.2 更新 codex-pro README.md：新增 Tests 段於 Install 段下方，簡述三層用途、列 `bash tests/run.sh` 與單 layer 命令；提醒 user manual checklist 在 tests/e2e-checklist.md。驗證：grep `^## Tests` README.md = 1、grep `bash tests/run.sh` README.md ≥ 1。
- [x] 5.3 全綠端到端跑（驗證 **Test runner entry point** 與全部 layer 的 happy path）：在乾淨 codex-pro repo 跑 `bash tests/run.sh`、確認 exit 0、final summary 顯示 0 fail；單跑 `bash tests/static.sh`、`bash tests/setup.sh`、`bash tests/batch.sh` 各自 exit 0；`ls -la ~/.codex/` 跑前跑後 diff exit 0。
- [x] 5.4 失敗路徑端到端 demo（驗證 **Test runner entry point** 的 fail scenario + **Static layer** 與 **Behavioral layer** 的 detection 能力）：暫時把 batch template 改一字（追加空白行），跑 `bash tests/run.sh` 確認 sha256 assertion fail + exit 非 0 + summary 顯示對應失敗訊息；還原 template 後再跑一次 確認 全綠 exit 0。本 task 不留 mutation 在 repo。
