## 1. Plugin skeleton

- [x] 1.1 建立 plugin manifest（D1: Plugin manifest 採 .claude-plugin/plugin.json）：產出 `.claude-plugin/plugin.json` 聲明 `name=codex-pro`、`version`、`description`、`author`。驗證 **Plugin local development load** 行為 — 以 `claude --plugin-dir <codex-pro 路徑>` 載入後，`/plugin` 清單出現名為 `codex-pro` 的條目。
- [x] 1.2 建立 skill 入口骨架（D2: Skill 命名為 setup 對齊命令名後綴）：產出 `skills/setup/SKILL.md` 含 YAML frontmatter（`name`、`description` 描述「驗證 codex-pro 環境是否就緒」、`allowed-tools: Bash`）。驗證方式：載入 plugin 後使用者輸入 `/codex-pro:setup` 時 Claude 觸發此 skill 並執行 SKILL.md 指引。

## 2. Setup 環境檢查邏輯

- [x] 2.1 OAuth token 偵測（D5: Setup 嚴格 read-only）：SKILL body 指示用 read-only 命令（`test -r`、純讀檔）檢查 `~/.codex/auth.json` 存在與可讀，輸出 readiness report 對應列。同步驗證 **Setup performs no mutating actions** — 在缺檔環境跑 setup 後，`~/.codex/` 內容未被新增或修改（人工 `ls -la ~/.codex/` 前後比對）。
- [x] 2.2 codex-call PATH 偵測（D3: codex-call discovery 走 PATH lookup）：SKILL body 指示用 `command -v codex-call` 探測 wrapper，輸出對應列。驗證方式：在 PATH 中無 codex-call 的 shell 下跑 setup 回 Status ✗ 且 Remediation 列文字指向「安裝 / 確認 parallel-ai-agents plugin」。
- [x] 2.3 Plugin manifest self-check：SKILL body 指示讀取自身 `.claude-plugin/plugin.json` 並做語法解析（`python3 -c 'import json,sys; json.load(open(sys.argv[1]))'` 或等價），輸出對應列。驗證方式：刻意把 manifest 改為非法 JSON 後跑 setup，對應列回 Status ✗ 且 Detail 含 parse error 訊息。
- [x] 2.4 組裝 readiness report 輸出（D4: Readiness report 用 markdown 表格、**Setup command produces structured readiness report**）：SKILL body 定義最終輸出為 4 欄 markdown 表格（Check / Status / Detail / Remediation），表格後一段總結含字串 "ready" 或 "need attention"。驗證方式：人工跑 setup 比對輸出格式與 spec 的「Example: passing environment」結構一致。

## 3. 端到端驗收

- [x] 3.1 全綠 ready 路徑端到端：在 OAuth token、codex-call、manifest 三者均就緒環境下，跑 `claude --plugin-dir <codex-pro 路徑>` 載入 plugin，呼叫 `/codex-pro:setup`。驗證 **Plugin local development load** 與 **Setup command produces structured readiness report** 行為 — 輸出含 3 列 Status 全 ✓ 的 markdown 表格 + 摘要含 "ready"。
- [x] 3.2 失敗 + read-only 路徑端到端：在 `~/.codex/auth.json` 缺檔環境跑 `/codex-pro:setup`，輸出對應列 Status ✗、Remediation 含 `codex login`；同時驗證 **Setup performs no mutating actions** — 命令完成後 `~/.codex/` 目錄內容（用 `ls -la` 前後比對）未變動，無新增檔案、無屬性變更。
