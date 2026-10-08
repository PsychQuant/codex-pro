# Changelog

## 0.9.0 — 2026-10-07

Issue: [#23](https://github.com/PsychQuant/codex-pro/issues/23)

- 新增 `/codex-pro:codex-visual-xval`（原生版 `$codex-visual-xval`）：Claude 與 Codex 對同一批圖片各自判讀、
  用程式比對、只用第三種證據裁決分歧。Claude 的答案在呼叫 Codex 前封存（SHA-256＋時間）；Codex 透過
  `codex-call --image` 盲答，請求只含圖片（中性檔名）、詞彙表與 schema。分歧分數量、位置、關係三類，
  只由放大輪、SAM 2.1 量測或物理約束裁決，不用多數決；結果寫入 `.codex-pro/visual-xval-<ts>.md`。
- 內建 SAM 2.1 追蹤：`sam_env.sh` 在使用者同意後安裝到 `~/.codex-pro/sam-env/`（約 1 GB，版本鎖定），
  每段一致影格各自錨定，兩物件遮罩 IoU > 0.5 的格不當證據，量測值離門檻不到 1% 不算證據。
- 重新 vendor `codex-call`（parallel-ai-agents `19564c1`，PR #88）：支援 `--image`，並拒絕不認得的旗標。
  provenance 改以 `references/codex-call-provenance.json` 為唯一來源，測試從它讀取，不再寫死指紋。
- `/codex-pro:codex-status` 的 `--skill` 與 `/codex-pro:codex-result` 的 `--latest` 接受 `visual-xval`；
  status 以一致率顯示該列。
- 產生器新增 run 目錄型 producer 的原生改寫；skill 數由九個增為十個。

### 已知限制

- SAM 追蹤只用在同一支影片依時間排序的影格（`--sequence`），只量 `distance_pct`。
- 放大輪 Claude 一側由全新的 subagent 作答；它是否真的全新啟動、答案是否在被讀之前就封存，靠 skill 的流程，
  程式無法檢查。Codex 的放大輪請求不帶任何一方的答案。
- 只比數量的類別（詞彙表沒有給關鍵點）沒有放大題、SAM 也不追蹤，它們的數量分歧無法裁決。
- 放大輪的關係題只用來證明「距離小於門檻」；SAM 的位置與關係證據要詞彙表宣告 `track_point: tip` 才採用。
- 影格複本由 sips 重新編碼（sRGB、長邊 ≤ 2048、JPEG 品質 95）後才清除 metadata，與原圖相比有一次有損壓縮。
- `codex-call` 的任何失敗都當成已送出（錯誤字樣證明不了什麼都沒送出）；是否登入改在呼叫前自己檢查，看的是
  `codex-call` 讀的那一份 token 檔（帳號家目錄，或 `CFFIXED_USER_HOME`）。離線、refresh token 已失效，或 `codex-call` 自己的送出前檢查失敗時，
  這一輪也會用掉，要另開一個 run。上游改進：PsychQuant/parallel-ai-agents#89 要求「主請求的 body（圖片）一個位元組都沒送出」時
  用專屬的 exit status，後端的文字偽造不了；做到之前不採用任何字樣。
- 第一輪的複本長邊不超過 2048；放大輪從原解析度、同樣清除 metadata 的複本裁切。
- 結構顯示資料損毀或截斷的圖、超過 2.5 億像素的圖都拒收（PNG 的壓縮串流要結束並通過自己的 checksum，超出表頭
  承諾的資料最多 1 MB）；結構完整但壓縮資料本身壞掉的 JPEG、GIF、WebP 看不出來。
- 結果檔不帶 xval 以外的文字：codex-call 印出的訊息、runtime 檢查的 detail、Python 例外的文字與 SAM 的輸出只留在
  run 目錄（`error.json` 記下來源，SAM 的輸出在 `sam.json`），結果檔寫出錯誤類別並說明保存在哪裡。其餘錯誤細節是 xval
  自己的字句，只寫檔名；結果檔的路徑過濾只是後備，相對路徑無法從文字裡認出來。
- 會建立目錄或寫進非 run 目錄的只有六處；`confirm-privacy` 要求 run 目錄已經存在。
- 每一步寫下的紀錄都連同 SHA-256 登記在 run 目錄的 `ledger.json`；之後的步驟讀到內容不同、被刪掉或沒有登記的紀錄
  就停在 `target_invalid`（例外只有尚未封存的那一輪 Claude 答案），Claude 的答案在封存後被改，下一個讀它的步驟就停下。
  帳本也在 run 目錄裡，防的是誤改與事後的手動修改，不是能寫入 run 目錄的人。
- 結果檔只用帳本核對過的紀錄產生，沒通過的只列名一次，frontmatter 記為 `target_invalid`（run 已因別的錯誤停下時保留
  那個錯誤）；frontmatter 每個欄位只寫自己的格式，否則寫 `invalid`；`seal_broken` 只有 true／false。核對過的紀錄仍無法
  呈現時，結果檔只寫固定內容與 run 自己的錯誤類別；result 自己失敗不取代 run 原本的錯誤。
- 只有 codex-call 根本沒能啟動時才撤回這一輪的紀錄；啟動之後的任何事（含輸出無法解碼）都不撤回。`ask` 被中斷時
  codex-call 跟著終止；回覆不是 UTF-8 時為 `parse_failed`。工具的輸出一律以 UTF-8 解碼，Big5、Shift-JIS 的 locale 下
  檔名含中日文的圖也量得到尺寸。
- `--vocab` 可以是管線或程序替換（`--vocab <(...)`）；run 的紀錄仍只讀一般檔案。
- 結果檔的路徑過濾只保留 http、https 網址；`file://`、`smb://` 等其他網址與本機路徑一樣縮成最後一段。
- 兩個模型一致不代表正確；準度要靠人工標準答案。
- `tests/codex-plugin.sh` 的 plugin-creator validator 檢查在 Codex CLI 0.160.1 下必定失敗（#24），與本版無關。

## 0.8.0 — 2026-08-10

Issue: [#10](https://github.com/PsychQuant/codex-pro/issues/10)

- 新增可由 Codex CLI／App 安裝的原生 plugin manifest 與 self-hosted repository marketplace。
- 從 Claude Code skill 來源單向生成 repo 根層與 `.codex/` 兩個完整 bundle；兩份均含九個 skills、nested resources、shared references、runtime 與 ownership inventory。
- 分發具 commit／blob／SHA-256 provenance 的 `codex-call` snapshot，以及在任何 OAuth 或網路動作前驗證平台、Swift、mode 與雜湊的 `codex-pro-call` wrapper。
- Codex producer 改由 active `SKILL.md` 位置解析 bundled wrapper，native bundle 損壞時 fail-closed；Claude Code 版維持 PATH 相容性。
- 同步 Codex manifest、Claude plugin 與 Claude marketplace 版本為 0.8.0，並新增 plugin、runtime、resolver、bundle parity 與安裝 smoke release gates。
- README 明載 macOS＋Swift、OAuth refresh side effect、private backend、上游已知限制、consumer availability、官方 directory 外部步驟與 rollback。
- Producer skill 的 runtime 前置檢查失敗不再 `exit 1` 中止，改為設定 `CODEX_RUNTIME_ERROR` 後跳過 `codex-call`、OAuth 與網路存取，並照既有 result schema 寫入結構化 failure result；失敗分 `package_corruption` 與 `runtime_unavailable` 兩類，皆不 retry。此前 runtime 損壞會在不產生 result file 的情況下中止，屬 silent failure。
- `codex-pro-call` 改用固定路徑 `/usr/bin/swift`（不再經 `command -v` 受 `PATH` 影響），並拒絕 symlink 形式的 runtime。
- Bundle 完整性邊界收斂：各 SKILL.md 的 runtime 解析、generator 的 wrapper 解析與 bundle subtree 檢查一律拒絕 symlink，subtree 必須為實際目錄；generator 的產出路徑檢查改為偵測 parent 目錄含 symlink 即報錯（原先先 `resolve()` 再比對 common path，可被 symlink 繞過）。
- Test dispatcher 改為 fail-closed：assertion layer 缺少可解析的 summary 時直接計為失敗，不再回退到 exit code 判定。此前空的或被截斷的 test script 可以 `exit 0`，讓缺席的 release gate 顯示為 passing layer。

### 已知限制

- Producer runtime 目前只支援 macOS；Linux／Windows producer 不在本版範圍。
- Vendored snapshot 保留 `parallel-ai-agents` [#28](https://github.com/PsychQuant/parallel-ai-agents/issues/28) 的 SSE UTF-8／CJK 問題與 [#35](https://github.com/PsychQuant/parallel-ai-agents/issues/35) 的外部契約限制。
- `$codex-batch` 仍是 `codex exec --full-auto` subprocess 例外，未改寫為 bundled runtime。
- 尚未宣稱已通過 OpenAI 官方 plugin directory 審核；0.8.0 先提供 self-hosted marketplace。

## Earlier changes

0.7.0 與更早版本的詳細變更紀錄保留在 [`changelog/`](./changelog/)。
