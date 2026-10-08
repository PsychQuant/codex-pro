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

- [x] 5.1 文件與版本一致。
  - `CLAUDE.md` 的指令表與 skill 類別表（mutating producer）加入新 skill。
  - README、CHANGELOG 記錄 0.9.0。
  - `plugins/codex-pro/.claude-plugin/plugin.json` 與原生 manifest 版本一致為 0.9.0。
  - 驗證：`bash tests/run.sh` 的 static 檢查（含跨 harness 版本一致）全綠。
  - [after: 2.2, 4.4, 4.5]

## 6. Verify 第一輪修正（#23 verify report 的 B1–B12、I1–I17）

- [x] 6.1 規格與 design 依使用者四項決定更新（依「放大輪由不知情的 subagent 作答」「Python 3.10 以上」「答案只記一次」「關係詞綁定兩個類別」「送出前確認與影格清理」）。
  - visual-xval delta spec：Claim schema and closed vocabulary、Sealed Claude answers、Blind Codex judgment、Zoom round、Built-in SAM evidence、Adjudication without majority vote、Structured result file、Privacy reminder before sending images 依修正改寫；新增 Python 版本需求；失敗類別加 `internal_error`。
  - design.md 補上五個決定與各自理由。
  - 驗證：`spectra validate add-visual-xval` 通過；新增與改寫的 scenario 在後續 task 都有對應測試。
- [x] 6.2 主張與詞彙表（B7、I4、I5、I17）。
  - 每個類別的關鍵點數必須等於該類別的數量；不符時 Claude 的答案為 `target_invalid`、Codex 的回覆為 `parse_failed`。
  - 拿掉 `touching`；關係詞改為 `{"between": [類別, 類別], "definition": "<量> <比較> <數字>"}`，定義只接受這個形式。
  - 詞彙表選填欄位（`max_count`、`track_class`、`sam_margin_pct`、`constraints`）驗證型別。
  - 第一輪 prompt 列出 `max_count`；放大輪 prompt 附類別定義。
  - 驗證：fixture 測試——Codex 省略關鍵點時為 `parse_failed`；`"很近（< 5）"` 被拒；兩個 prompt 都含上述內容。
  - [after: 6.1]
- [x] 6.3 封存與紀錄（B1、B3、I2 的確認部分）。
  - `ask --round 1` 在沒有封存、封存不符、或未記錄隱私確認時停下（`target_invalid`），不送請求。
  - `seal` 不覆寫既有封存；Codex 已作答後不能再封存。
  - 每一輪只送一次請求：送出前記錄時間，Codex 的回覆記錄 SHA-256；同一輪再送一次即停下。
  - 結果檔記錄 Codex 請求時間與回覆雜湊，並核對封存早於請求、回覆未被改動。
  - 驗證：behavioral 測試——未封存先 ask 被拒且 mock 沒被呼叫；重封被拒；同一輪第二次 ask 被拒；改動 codex.json 後結果檔標示不符。
  - [after: 6.2]
- [x] 6.4 放大輪（B2、B4、B8、B9、I11）。
  - `crops` 把放大輪的題目寫成 `zoom_prompt.md`，Claude 端由全新 subagent 只依該檔與裁切圖作答，寫成以裁切圖檔名為鍵的答案檔；`seal --zoom` 用與 Codex 相同的規則驗證後封存。
  - `ask --round zoom` 要求放大輪封存存在且完好；`adjudicate` 重算放大輪封存，不符時不採用放大輪證據並在結果檔標示。
  - 數量題的裁切範圍涵蓋兩邊在該格該類別的全部關鍵點；沒有關鍵點或範圍等於整張畫面時不產生放大題。
  - 位置題改為列出裁切圖內該類別全部關鍵點，裁決時依物件配對判斷分歧點各自對應哪一個物件。
  - 驗證：behavioral 測試——放大輪答案在 Codex 回覆後被改動時不採用；DA 的「同一支標兩次」情境由放大輪判給 Codex；只有裁切區外有物件時數量題不判勝。
  - [after: 6.3]
- [x] 6.5 SAM 證據（B5、B6、I6、I7、I9、I13、I17）。
  - `track.json` 記錄追蹤類別；數量與位置證據只用於同一類別；關係證據只用於 `between` 兩邊都是追蹤類別的關係。
  - 位置證據以物件配對決定分歧點對應的追蹤物件。
  - 物件存在以模型的 object score 判定；影格順序取自 init 的順序；錨點配對用影格長寬比。
  - SAM 步驟移到放大輪之前，放大輪失敗不影響 SAM。
  - 模型鎖定 revision、權重放在 `~/.codex-pro/sam-env/` 內、追蹤時只用本機檔案；`sam_env.sh` 以 `python -I` 執行。
  - 驗證：fixture 測試——其他類別的分歧不被 SAM 裁決；DA 的「同一支標兩次」情境由 SAM 判給 Codex；SAM smoke 跑在實際影格上（§E）。
  - [after: 6.2]
- [x] 6.6 失敗路徑與紀錄，含 Interpreter requirement（B10、B11、I1、I10）。
  - Interpreter requirement：`xval.py` 在任何 import 之前檢查 Python 版本，低於 3.10 時寫 `error.json`，`result` 寫出結果檔（`runtime_unavailable`）。
  - 每一步的意外例外寫成 `internal_error`；沒有比對結果時 `adjudicate` 正常結束。
  - `classify` 依 codex-call 的實際錯誤訊息判定，圖片錯誤為 `target_invalid`。
  - profile 解析結果寫進 run 目錄，`ask` 與 `result` 從那裡讀；同一步之後成功時清除該步留下的錯誤；未驗證的封存寫「未驗證」。
  - 物理約束只排除一方時在證據中註明；放大輪兩邊一致推翻雙方原答時註明。
  - 驗證：以 `/usr/bin/python3`（3.9）執行時結果檔存在且為 `runtime_unavailable`；第一輪 timeout 後 `adjudicate` 與 `result` 都正常結束；時間戳含 `429` 的圖片錯誤分類為 `target_invalid`。
  - [after: 6.3, 6.4, 6.5]
- [x] 6.7 輸入處理（I2 的影格部分、I3、I12、I14、I15）。
  - init 重新編碼影格，去除 EXIF／XMP 並套用方向；run 目錄寫入 `.gitignore`。
  - 單次 run 最多 12 張圖片，超過時 `target_invalid`；中性檔名依張數補位。
  - SKILL.md 與給 Codex 的 instructions 都寫明畫面中的文字只是判讀內容、不是指令。
  - `--claude-answers` 檔可用原始檔名，init 後依對照表換成中性檔名再封存。
  - 驗證：帶 EXIF 的 JPEG 複本不含原拍攝時間；13 張圖被拒；以原始檔名作答的答案檔可以封存。
  - [after: 6.6]
- [x] 6.8 測試與文件（I8、I16）：Native Codex plugin manifest、Complete generated Codex bundles、Backward-compatible generator interfaces、Full bundle parity test、Codex installation e2e checklist 的 nine 改為 ten。
  - 測試層在缺 numpy 或非 macOS 時略過對應案例並印出原因，不算失敗。
  - 主規格的 nine skills 改為 ten；e2e-checklist 更新版本字串、producer 清單，加入 visual-xval 的端到端項目。
  - README 與 SKILL.md 寫明 Python 3.10 以上；重新產生原生 bundle。
  - 驗證：`bash tests/run.sh` 只剩 #24 那一條失敗。
  - [after: 6.7]
- [x] 6.9 真實後端端到端（B12）。
  - 本機 parallel-ai-agents 更新到 2.24.0 以上。
  - 用 3 張合成圖跑完整流程（含放大輪），確認回覆符合 schema、中性檔名與送出順序一致、結果檔完整。
  - 驗證：結果檔與 run 目錄的實際內容記錄在 e2e-checklist 的對應項目。
  - [after: 6.8]

## 7. Verify 第二輪修正（#23 第二輪 report 的 R1–R8、S1–S16、F1、F2）

- [x] 7.1 規格與 design 依使用者第二輪決定更新（依「關鍵點由詞彙表指定」「記錄第一方模型」「約束只能排除」「後端錯誤另立一類」）。
  - visual-xval delta spec：Claim schema and closed vocabulary（key_points、distance_pct 為唯一的量、最小距離）、Adjudication without majority vote（放大輪數量只能證實較高的一方、推翻雙方即 unverifiable、約束單獨存在時只排除）、Structured result file（first_side_model、backend_error、放大輪紀錄）、Built-in SAM evidence（只下載需要的權重）。
  - design.md 補上第二輪的決定與理由。
  - 驗證：`spectra validate` 與 `spectra analyze` 無 warning。
- [x] 7.2 關鍵點由詞彙表指定（R2、S7）。
  - 詞彙表 `key_points`：類別 → 關鍵點定義；只有列出的類別要給點、比位置，其他類別只比數量。
  - 關係詞的 `between` 與 SAM 的 `track_class` 都必須是有關鍵點的類別；量只接受 `distance_pct`，定義為兩類關鍵點之間的最小距離。
  - 兩個 prompt 列出各類別的關鍵點定義。
  - 驗證：詞彙表含 PAD／THREAD 而不給關鍵點時，兩邊只比數量、不產生位置分歧；`closeness < 5` 被拒。
  - [after: 7.1]
- [x] 7.3 裁決規則（R1、R3、R4、S11）。
  - 放大輪的數量答案只能證實較高的一方（與 SAM 相同），等於較低的一方時為 unverifiable。
  - 放大輪推翻雙方時，該分歧為 unverifiable，其他證據不得改判。
  - 違反 max_count 單獨存在時為 unverifiable，註明被排除的一方；與其他證據一致時才裁決。
  - SAM 位置證據的 margin 同時套用在兩方。
  - 驗證：R1 的「同一物件標兩次」情境為 unverifiable；R3、R4 的兩個實測情境為 unverifiable。
  - [after: 7.2]
- [x] 7.4 紀錄與失敗分類（R5、R6、S1、S9、S12、S13）。
  - 送出後的後端錯誤記為 `backend_error`；「refresh」只在 OAuth 字樣中才算。
  - 被拒絕的重跑（重封、同一輪再送）不寫入 `error.json`，只進 `errors.jsonl`。
  - Codex 原始回覆的雜湊在比對與寫結果檔時重算。
  - codex-call 在送出前就失敗（圖片檢查）時撤回該輪的請求紀錄。
  - 結果檔：沒有封存時不寫「封存早於請求」；列出放大輪的請求時間與雜湊；錯誤註明輪次；SAM detail 過濾本機路徑。
  - Step 4.1 的 max_time 不合法時不寫 profile.json 並說明原因。
  - 驗證：HTTP 500 為 backend_error；rate_limit 後重跑 ask，結果檔仍是 rate_limit；改動 codex_round1.md 被結果檔指出。
  - [after: 7.3]
- [x] 7.5 輸入與放大輪檔案（R7、S2、S3、S4、S10、S14、S15）。
  - JPEG 截到第一個 EOI，去掉附加在後面的圖片或影片；PNG 與 WebP 的 EXIF 方向先轉正再清除；格式依檔頭判斷。
  - 封存同時記錄詞彙表與影格的雜湊，比對前核對；已封存或已送出的 run 不得重跑 init。
  - 放大輪的 plan 與題目檔記錄雜湊，送出前核對；裁切圖必須在 run 目錄內。
  - 放大輪 prompt 寫明裁切圖的附加順序；放大倍率讓長邊不超過 2048，題目寫出實際倍率。
  - 原始檔名與中性檔名衝突時拒絕對照。
  - 驗證：附加尾段的 JPEG 複本不含尾段；PNG 方向 6 被轉正；封存後改詞彙表被拒；plan 指向 run 目錄外的檔案被拒。
  - [after: 7.4]
- [x] 7.6 SAM 下載與出貨路徑（R8、S16）。
  - `snapshot_download` 只取需要的檔案；同意文字依實際大小更新。
  - 以暫時的 HOME 讓 `~/.codex-pro/sam-env` 指向既有環境，從 `xval.py sam` 跑完出貨路徑。
  - 驗證：stub 測試確認 allow_patterns；出貨路徑 smoke 的紀錄寫進 e2e-checklist §E。
  - [after: 7.5]
- [x] 7.7 第一方模型與文件（F1、F2、S5、S6、S8），含 Cross-harness version consistency 的 0.9.0 與 manifest 描述。
  - init 記錄第一方的實際模型（`--first-side`），結果檔 frontmatter 寫 `first_side_model`；第一方不是 Claude 時，Limitations 註明兩方可能同屬一個模型家族。
  - SKILL：subagent 結束後立刻封存、不讀內容、不重跑；沒有放大題時跳過放大輪；Limitations 補上跨 run 不盲答。
  - design.md 的步驟順序與 run 路徑、xval.py 用法說明、spec 的「重新編碼」字樣、0.8.0 殘留一併更正。
  - 驗證：SKILL 契約檢查涵蓋上述內容；`bash tests/run.sh` 只剩 #24。
  - [after: 7.6]
- [x] 7.8 真實後端端到端（第二次）。
  - 詞彙表含有關鍵點的類別與只計數的類別，跑完整流程。
  - 驗證：紀錄寫進 e2e-checklist §F。
  - [after: 7.7]

## 8. Verify 第三輪修正（#23 第三輪 report 的 T1–T9、L1–L16）

- [x] 8.1 規格與 design 依使用者第三輪決定更新（Adjudication without majority vote 改為上下界、Blind Codex judgment 改為 fail-closed、Zoom round、Structured result file、Privacy reminder before sending images、Cross-harness version consistency）。
  - 區間裁決（T5）、推翻雙方的規則（T3）、關係的單向證據（T4）、只比數量的類別無法裁決（T8）、送出判定的封閉列舉（T1）、放大輪不採用不是 run 的錯誤（T6）、白名單與圖片結尾（T2、L14）。
  - design.md 補上第三輪的決定與理由，更正 Implementation Contract 與「放大 2 倍」。
  - native-plugin delta spec 不再把原生發行寫成 0.9.0 的功能。
  - 驗證：`spectra validate` 與 `spectra analyze` 無 warning。
- [x] 8.2 送出判定 fail-closed（T1、L11；design「看不出有沒有送出時，一律當成送出」）。
  - 只有封閉列舉裡的錯誤撤回請求紀錄；`HTTP 0`、串流 error 事件與無法辨認的錯誤保留紀錄、記為 `backend_error`。
  - token refresh 被拒（`invalid_grant`）與 auth.json 錯誤記為 `oauth_invalid` 並撤回紀錄。
  - 驗證：`HTTP 0: (no body)`、`Codex error`、伺服器過載都保留紀錄、第二次請求被拒；`invalid_grant`、讀不到 prompt 撤回紀錄。
  - [after: 8.1]
- [x] 8.3 影格複本只留顯示需要的區塊（T2、L14）。
  - JPEG 略過 marker 前的填充位元組；WebP 只讀到 RIFF 長度為止；PNG 與 WebP 改用白名單。
  - 驗證：EOI 前有填充位元組的 JPEG、後面接第二張圖的 WebP、帶 `caBX` 的 PNG 與帶 `C2PA` 的 WebP，複本都不含附加或額外的資料，且仍能解碼。
  - [after: 8.1]
- [x] 8.4 裁決改為上下界（T3、T4、T5、L5；design「證據只用來證明它證得出來的事」）。
  - 數量：放大輪與 SAM 的數量是下限、max_count 是上限；另一方被排除且本方等於最高下限時才裁決。
  - 位置：兩點對到同一物件且都離它太遠，或放大輪在兩點附近都沒有物件時，推翻雙方。
  - 關係：雙方數量一致（SAM 另要求追蹤數相同）時兩個方向都採用，否則只採用上界證得出的方向；比對輸出為關係題記錄兩類的數量。
  - 驗證：spec 的五個新情境；DA 的 3 對 2、上限 2、放大 2 判 Codex。
  - [after: 8.1]
- [x] 8.5 紀錄與輸入保護（T6、L2、L3、L4、L6、L7、L15）。
  - 放大輪封存失敗不設定 run 的錯誤，結果檔註明放大輪未採用；步驟名稱帶輪次；「已經做過」的檢查排在最前。
  - 輸入雜湊只算 run 列出的影格；comparison 與 zoom plan 在裁決前核對；放大輪封存後不得重做裁切；run 只能 init 一次。
  - max_time 不合法時錯誤進入 run 與結果檔；SAM 先判斷用不用得到，再檢查安裝；結果檔的 detail 一律過濾本機路徑。
  - 驗證：zoom 封存失敗後結果檔沒有 error；`.DS_Store` 不影響比對；改 comparison.json 後裁決被拒；第二次 init 被拒。
  - [after: 8.4]
- [x] 8.6 題目、第一方模型與檔名（T7、L1、L8、L10、L12、L13）。
  - 放大輪的關係題附完整定義與關鍵點定義；第一輪寫明沒有一對點時為 false；每題寫出實際倍率，不一律說放大。
  - `first_side_model` 只接受單行識別字；Python 3.9 的結果檔也有這個欄位；Limitations 寫明封存前未讀、未重跑靠流程。
  - 原始檔名與中性檔名衝突時，訊息只給做得到的補救。
  - [after: 8.5]
- [x] 8.7 文件（T8、T9、L9、L16）。
  - SKILL、vocab-format、README、CHANGELOG 與結果檔契約依第三輪更正；e2e-checklist §F 的兩次紀錄分開。
  - bundle 產生器略過 `__pycache__`。
  - 驗證：SKILL 契約檢查；`bash tests/run.sh` 只剩 #24。
  - [after: 8.6]
- [x] 8.8 真實後端端到端（第三次）。
  - 合成圖涵蓋 max_count 與放大輪夾出答案的情境。
  - 驗證：紀錄寫進 e2e-checklist §F。
  - [after: 8.7]

## 9. Verify 第四輪修正（#23 第四輪 report 的 U1–U6、M1–M11）

- [x] 9.1 規格與 design 依使用者第四輪決定更新（Blind Codex judgment 的封閉列舉錨定、Adjudication without majority vote 的放大輪單向與 SAM 不推翻、Built-in SAM evidence 的 track_point、Sealed Claude answers 的送出前核對、Privacy reminder before sending images 的 run 目錄）。
  - 驗證：`spectra validate` 與 `spectra analyze` 無 warning。
- [x] 9.2 送出判定只看 codex-call 自己的第一行、整行比對；`invalid_grant` 當成已送出（U1）。
  - 驗證：後端訊息含 `auth.json` 或 `invalid_grant` 時紀錄保留；多行內容偽造的 `error:` 行不被採用。
  - [after: 9.1]
- [x] 9.3 裁決：放大輪關係題只證明「近」；SAM 不推翻雙方；SAM 位置與關係證據需要 `track_point: tip`；SAM 關係的完整性數有尖端的物件；margin 嚴格大於；沒用上的 SAM 證據也列出；下限高於上限時點名被排除的一方；位置題的裁切邊距涵蓋門檻（U2、U3、U4、M2、M7、M8）。
  - 驗證：spec 的新情境；第四輪 reviewer 的重現案例。
  - [after: 9.1]
- [x] 9.4 紀錄與輸入保護：run 目錄不覆寫 `.gitignore`、不接管含其他檔案的目錄；第一輪送出前核對輸入與路徑；init 失敗也用掉這個 run；「已經做過」的檢查一律最先；放大計畫綁定比對結果、裁切圖與 SAM 輸出記錄雜湊；Python 3.9 的路徑寫錯誤歷史；profile 欄位錯誤具名（U5、U6、M1、M4、M6、M10）。
  - [after: 9.3]
- [x] 9.5 影格白名單的殘留：APP14 檢查 Adobe 簽章、JFIF 去掉縮圖、ANMF 只留影像子區塊、沒有 EOI 的 JPEG 拒收、裁切圖也清除 metadata（M5）。9.9 起改為先重新編碼：WebP 寫成 PNG，ANMF 過濾與「沒有 EOI 拒收」不再適用。
  - [after: 9.4]
- [x] 9.6 結果檔：路徑過濾改為前綴替換（家目錄與暫存目錄），不再改壞 URL；Limitations 寫明雙方一致的數量被當成真值（M3、M11）。
  - [after: 9.5]
- [x] 9.7 文件：SKILL、design、vocab-format 的送出前錯誤列舉、拒絕順序與 exit 5、Step 5 的可否重送、`track_point`（M9、U4）。
  - 驗證：`bash tests/run.sh` 只剩 #24。
  - [after: 9.6]
- [x] 9.8 真實後端端到端（第四次）。
  - 驗證：紀錄寫進 e2e-checklist §F。
  - [after: 9.7]
- [x] 9.9 影格複本先重新編碼再清除（第四輪之後的背景安全審查：白名單只看區段外型、解析失步）。
  - 由 sips 解碼後重新編碼（sRGB、長邊 ≤ 2048），再以白名單清除 sips 寫入的 metadata；送出的每個位元組都來自編碼器。
  - 驗證：ICC 與 Adobe 區段裡夾帶的資料不會出現在複本；長邊 3000 的圖複本為 2048；解不開的檔案拒收。
  - [after: 9.6]

## 10. Verify 第五輪修正（#23 第五輪 report 的 V1–V9、N1–N12）

- [x] 10.1 規格與 design 依使用者第五輪決定更新（design「第五輪：不靠字樣判斷送出，也不讓重新編碼拿走放大輪的細節」；Blind Codex judgment 一律當成已送出並在送出前自檢、Zoom round 從原解析度複本裁切與邊距、Sealed Claude answers 每一步核對輸入、Structured result file 只寫檔名、Privacy reminder before sending images 的 run 目錄與複本）。
  - 驗證：`spectra validate` 與 `spectra analyze` 無 warning。
- [x] 10.2 送出判定：codex-call 失敗一律保留紀錄；呼叫前自檢登入、影格與 prompt（V1、V2、N12）。
  - [after: 10.1]
- [x] 10.3 裁切與裁決：位置題邊距依高寬比換算；只有 `<`／`<=` 的關係題出放大題；SAM 位置證據的 margin 嚴格大於；沒用上的證據一律列出（V3、N4、N5、N10）。
  - [after: 10.1]
- [x] 10.4 紀錄與輸入：只有 init 建立目錄；每一步核對輸入；init 寫下的輸入在封存時核對；雜湊核對遇到缺檔不當內部錯誤；結果檔只寫檔名；SAM 用不到時不要求安裝（V4、V5、V6、V8、N1、N2、N3、N7）。
  - [after: 10.3]
- [x] 10.5 原解析度複本：長邊超過 2048 時 init 另寫一份原解析度的複本供裁切；轉正與編碼一次完成（V7、N8、N11）。
  - [after: 10.4]
- [x] 10.6 文件：SKILL Step 5 的可否重送與 init、送出判定、exit 5；media.py、vocab-format、design 的殘留；結果檔不帶內部編號（V9、N6、N9）。
  - 驗證：`bash tests/run.sh` 只剩 #24。
  - [after: 10.5]
- [x] 10.7 真實後端端到端（第五次）。
  - 驗證：紀錄寫進 e2e-checklist §F。
  - [after: 10.6]

## 11. Verify 第六輪修正（#23 第六輪 report 的 W1–W2、Q1–Q15）

- [x] 11.1 規格與 design 依第六輪更新（design「第六輪：比對之後也核對答案檔，路徑在產生的地方就只放檔名」；Sealed Claude answers 比對之後核對答案檔與 meta、Blind Codex judgment 的登入檢查與 prompt 先寫、Structured result file 的 backend_error 與路徑、Privacy reminder before sending images 的寫入目錄封閉清單與損毀的圖）。
  - 驗證：`spectra validate` 與 `spectra analyze` 無 warning。
- [x] 11.2 錯誤細節由檔名組成；路徑過濾跨過空白、保留 `~/.codex-pro/`（W1、Q15）。
  - [after: 11.1]
- [x] 11.3 比對之後核對答案檔；輸入納入 meta.json；sam、adjudicate、result 先核對；frames.json 型別錯誤；原解析度複本限定在 run 內（W2、Q8、Q9）。
  - [after: 11.2]
- [x] 11.4 寫入目錄的封閉清單、登入檢查看帳號家目錄、prompt 先寫、init 建不起目錄的類別、深層巢狀的回覆、compare_claims 不引用 Codex 的名稱（Q1、Q4、Q6、Q7、Q8、Q14）。
  - [after: 11.3]
- [x] 11.5 損毀或截斷的圖拒收；SAM 塌陷格與量不到距離列為沒用上；JPEG 只壓縮一次的測試（Q10、Q12、Q13）。
  - [after: 11.4]
- [x] 11.6 文件：SKILL Step 4.2 與 Step 5、README、media.py、design 的指向、CHANGELOG 與 #89、refresh 失效、測試註解（Q2、Q3、Q5、Q11、Q14、Q15）。
  - 驗證：`bash tests/run.sh` 只剩 #24。
  - [after: 11.5]
- [x] 11.7 真實後端端到端（第六次）。
  - 驗證：紀錄寫進 e2e-checklist §F。
  - [after: 11.6]

## 12. Verify 第七輪修正（#23 第七輪 report 的 X1–X2、Y1–Y10）

- [x] 12.1 規格與 design 依第七輪更新（design「第七輪：檢查要做到文件說的程度」；Privacy reminder before sending images 的 PNG 結構與寫入目錄清單、Structured result file 的路徑過濾與結果檔穩健性、Blind Codex judgment 的登入檢查、Sealed Claude answers 的 sam 情境）。
  - 驗證：`spectra validate` 與 `spectra analyze` 無 warning。
- [x] 12.2 PNG 結構檢查：串流結尾與 checksum、超出資料的上限、只看關鍵 chunk 的 CRC、位元深度；原解析度複本的位置在裁切前核對（X1、Y8）。
  - [after: 12.1]
- [x] 12.3 路徑過濾與錯誤細節：只保留 SAM 環境的固定位置、家目錄的邊界、含引號括號的目錄名、不吃掉網址與自己的訊息、逾時與 compare_claims 的路徑與措辭（X2、Y1、Y2、Y9）。
  - [after: 12.2]
- [x] 12.4 結果檔與紀錄：型別不對照樣寫結果檔、result 失敗不取代 run 的錯誤、雜湊不讀 run 以外的檔、重算不符寫進 frontmatter、核對比對結果與裁決、缺參考雜湊不放行；送出邊界與登入檢查（Y3、Y4、Y6、Y7）。
  - [after: 12.3]
- [x] 12.5 文件：寫入目錄清單、sam 的情境、SKILL Step 4.2 的放大輪檢查、design 的措辭、CHANGELOG 與 #89 的「body」（Y5、Y10）。
  - 驗證：`bash tests/run.sh` 只剩 #24。
  - [after: 12.4]
- [x] 12.6 真實後端端到端（第七次）。
  - 驗證：紀錄寫進 e2e-checklist §F。
  - [after: 12.5]

## 13. Verify 第八輪修正（#23 第八輪 report 的 Z1–Z4、K1–K10）

- [x] 13.1 規格與 design 依第八輪更新（design「第八輪：送出邊界以「程式有沒有啟動」為準，結果檔核對每一份紀錄」；Blind Codex judgment 的送出邊界與 CFFIXED_USER_HOME、Structured result file 的紀錄核對、Privacy reminder before sending images 的寫入清單）。
  - 驗證：`spectra validate` 與 `spectra analyze` 無 warning。
- [ ] 13.2 送出邊界：只有建立程序的例外撤回紀錄、輸出以 UTF-8 取代解碼；CFFIXED_USER_HOME 的空值（Z1、K7）。
  - [after: 13.1]
- [ ] 13.3 結果檔：退路保留 run 的錯誤、寫入失敗的類別、只讀一般檔案、紀錄與雜湊對稱、Codex 答案與原始回覆的核對、frontmatter 的值、措辭（Z2、Z3、Z4、K1、K5、K10）。
  - [after: 13.2]
- [ ] 13.4 路徑過濾、3.9 路徑、eXIf、PNG 讀取上限（K4、K6、K8、K9）。
  - [after: 13.3]
- [ ] 13.5 文件：寫入清單、design 的指向、SKILL（K2、K3）。
  - 驗證：`bash tests/run.sh` 只剩 #24。
  - [after: 13.4]
- [ ] 13.6 真實後端端到端（第八次）。
  - 驗證：紀錄寫進 e2e-checklist §F。
  - [after: 13.5]
