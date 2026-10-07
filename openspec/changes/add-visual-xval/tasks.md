## 1. 前置：上游 runtime

- [x] 1.1 確認 PsychQuant/parallel-ai-agents#87 已發版（本 change 依「重新 vendor 接受上游漂移」的決定，取上游最新 main 上的發版 commit）。
  - 記錄不可變 commit。
  - 確認該 commit 的 `codex-call --help` 列出 `--image`，且不認得的 flag 會報錯（上游 #80）。
  - 寫下一次送多張圖的實測 payload 上限。
  - 驗證：在該 commit 執行 `codex-call --help` 看得到 `--image`；實測上限記入 design.md 的 Open Questions 答案。

## 2. 重新 vendor 與 provenance

- [x] 2.1 Pinned runtime provenance 改以 JSON 為準（Provenance 以 JSON 為準）。
  - `references/codex-call-provenance.json`、`plugins/codex-pro/references/codex-call-provenance.json`、`.codex/references/codex-call-provenance.json` 記錄 1.1 的 commit、blob、raw URL、size、mode、SHA-256。
  - `bin/codex-call`、`.codex/bin/codex-call`、`plugins/codex-pro/runtime/codex-call` 換成該 commit 的位元組。
  - 驗證：三份 snapshot 的 `shasum -a 256` 相同，且等於 JSON 記錄的值。
  - [after: 1.1]
- [x] 2.2 Runtime provenance and resolver matrix tests 改為比對 provenance JSON。
  - 三份 `codex-pro-call` 的預期 SHA-256 與 JSON 一致。
  - `tests/codex-runtime.sh` 的 `PINNED_BYTES`／`PINNED_SHA256` 與 `tests/codex-plugin.sh` 的寫死值改成從 JSON 讀取。
  - 新增兩個測試：「Wrapper digest agrees with provenance」（wrapper 與 JSON 比對）、「Vendored runtime accepts images」（snapshot 的 `--help` 含 `--image`）。
  - 兩份 `THIRD_PARTY_NOTICES.md` 改為新 commit。
  - 驗證：故意改動 wrapper 預期值一個字元時新測試失敗、還原後通過；`bash tests/run.sh` 全綠，確認上游漂移沒有影響既有 9 個 skill。
  - [after: 2.1]

## 3. 腳本（可單獨執行與測試）

- [x] 3.1 實作 Claim schema and closed vocabulary 的驗證與 Deterministic comparison 比對腳本 `compare_claims.py`（依「主張的 JSON schema 與量化門檻」），放在 `plugins/codex-pro/skills/codex-visual-xval/scripts/`。
  - Claim schema and closed vocabulary：關係詞沒有量化定義時回報 `target_invalid`；不在清單的物體記為 `other`。
  - Deterministic comparison：同類物體依最近距離配對，分數量不同、位置不同（超過 `position_threshold_pct`）、關係不同三類，算出 `agreement_rate`。
  - 驗證：fixture 測試涵蓋三類分歧；spec 的 f08 例子 12 格中 1 格分歧時一致率為 11/12；缺門檻的關係詞回 `target_invalid`。
- [x] 3.2 依「Claude 答案先封存」實作 Sealed Claude answers：寫入答案檔，記錄 SHA-256 與時間；比對前重算，不符時 `seal_broken: true`。
  - 驗證：未改檔時兩次 digest 相同且 `seal_broken: false`；改一個字元後為 `true`。
- [x] 3.3 依「內建 SAM 2.1，多錨點，偵測塌陷」實作 Built-in SAM evidence 的追蹤腳本 `sam_track.py`。
  - 以兩邊一致的影格為錨點，每段一致影格重新錨定；影格存 CPU 記憶體。
  - 兩物件遮罩 IoU > 0.5 的格標為 invalid；輸出逐格位置與 invalid 標記的 JSON。
  - 驗證：用合成遮罩（不下載模型）測試塌陷偵測——IoU 0.7 判 invalid、0.1 判 valid；用一支短片的人工 smoke 步驟寫進 `tests/e2e-checklist.md`。
- [x] 3.4 實作 SAM 環境腳本 `sam_env.sh`。
  - 在 `~/.codex-pro/sam-env/` 用 uv 建 venv，鎖定 transformers 5.19 以上與相容的 torch。
  - 安裝前顯示預估下載量，使用者明確同意才安裝；`--check` 回報 installed 或 not_installed。
  - 確認 SAM 2.1 的授權並寫進兩份 `THIRD_PARTY_NOTICES.md`。
  - 驗證：以 stub 的 uv 測試拒絕安裝時回 not_installed 且沒有建立任何檔案。
- [x] 3.5 依「裁決規則」實作 Adjudication without majority vote 的裁決腳本。
  - 輸入比對結果、放大輪答案、SAM 輸出，每個分歧輸出 `resolved_claude`、`resolved_codex`、`unverifiable` 之一，附上證據。
  - 驗證：fixture 測試——SAM 有效格量到 4.3% → `resolved_claude`；只有 invalid 格 → `unverifiable`；輸入中不存在讓任一方看到對方答案的路徑。
  - [after: 3.1, 3.3]

## 4. Skill 與既有 skill 的整合

- [x] 4.1 撰寫 SKILL.md 前半流程：Runtime image capability preflight、Privacy reminder before sending images、封存、Blind Codex judgment（依「Producer 結構比照 codex-review」「Runtime 圖片能力在送出前檢查」「失敗分類增加兩類」），位置 `plugins/codex-pro/skills/codex-visual-xval/SKILL.md`。
  - Runtime image capability preflight。
  - Privacy reminder before sending images。
  - 封存。
  - Blind Codex judgment：`codex-call --image`、中性檔名、不帶 Claude 答案、前景同步、profile 的 hard timeout。
  - 驗證：behavioral 測試以 mock `codex-call` 確認三件事——`--help` 不含 `--image` 時寫出 `error: runtime_unsupported` 的結果檔且 mock 沒被帶圖呼叫；mock 回非 JSON 時為 `parse_failed`；送出的 prompt 不含任何 Claude 主張值。
  - [after: 3.1, 3.2]
- [x] 4.2 依「一輪一批，第二輪只送放大圖」完成 Zoom round 與 SAM 接線。
  - 只對有分歧的格裁切、放大 2 倍後送第二輪，不帶任何一方先前的答案。
  - 呼叫 SAM 腳本與裁決腳本；SAM 未安裝時 `sam_status: not_installed`，需要 SAM 的分歧標 `unverifiable`。
  - 驗證：behavioral 測試確認 12 格中 1 格分歧時第二輪只帶那 1 格的裁切圖；未安裝 SAM 時流程仍完成。
  - [after: 3.3, 3.4, 3.5, 4.1]
- [x] 4.3 實作 Structured result file：寫 `.codex-pro/visual-xval-<ISO8601-timestamp>.md`。
  - frontmatter 欄位依 spec。
  - 內文依序：一致率與分歧摘要、逐格分歧與裁決、SAM 狀態、封存驗證、限制（明寫一致不等於正確）。
  - 八種失敗類別都寫結果檔、不 retry。
  - 驗證：behavioral 測試解析產生的結果檔，欄位與段落順序符合 spec；timeout 情境也有結果檔。
  - [after: 4.2]
- [x] 4.4 原生 bundle 的 Skill-relative runtime resolution 與 Platform-scoped producer capability 涵蓋新 skill。
  - `scripts/codex-skills.manifest` 與 `scripts/codex-bundle-resources.manifest` 加入 `codex-visual-xval` 與其腳本，重新產生 `.codex/skills` 鏡像。
  - 非 macOS 主機在讀取 OAuth 前回 `unsupported_platform`。
  - 驗證：`tests/codex-skills-parity.sh` 與 resolver 矩陣測試包含新 skill 且通過。
  - [after: 4.3]
- [x] 4.5 status 與 result 支援新的 producer 前綴：Status skill registration and argument parsing、Status output is a markdown table of result file frontmatter summary、Result skill registration and selection-mode argument parsing。
  - Status skill registration and argument parsing：接受 `--skill visual-xval`，錯誤值時列出四個合法值。
  - Status output is a markdown table of result file frontmatter summary：visual-xval 列顯示 `<百分比> agreement`。
  - Result skill registration and selection-mode argument parsing：接受 `--latest visual-xval`。
  - 驗證：`tests/status.sh` 與 `tests/result.sh` 新增對應案例並通過。
  - [after: 4.3]

## 5. 文件與版本

- [ ] 5.1 文件與版本一致。
  - `CLAUDE.md` 的指令表與 skill 類別表（mutating producer）加入新 skill。
  - README、CHANGELOG 記錄 0.9.0。
  - `plugins/codex-pro/.claude-plugin/plugin.json` 與原生 manifest 版本一致為 0.9.0。
  - 驗證：`bash tests/run.sh` 的 static 檢查（含跨 harness 版本一致）全綠。
  - [after: 2.2, 4.4, 4.5]
