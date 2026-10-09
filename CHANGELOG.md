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
  就停在 `target_invalid`。可以存在而沒有登記的只有兩種：尚未封存的那一輪 Claude 答案，以及還沒記下請求之前的 profile。
  Claude 的答案在封存後被改，下一個讀它的步驟就停下。帳本也在 run 目錄裡，防的是誤改與事後的手動修改，不是能寫入 run
  目錄的人。
- 登記與寫入各只有一個入口：每一步經同一個 `Step` 登記它自己寫的檔（含 codex-call、SAM 為它寫的那一個），中途停下或被
  中斷時也一樣；帳本已經發現不符的紀錄不會被登記、重新登記或移除條目，帳本不見時不重建；`result` 不登記任何東西，也不把
  結果檔寫進 `--run` 指的目錄，不論它是不是 run（路徑照作業系統的方式解析，先跟隨 symlink 再處理 `..`，作業系統到不了的目錄
  不算目錄，判斷與寫入用同一個結果，回報的也是它）。`--run` 在每一步開始時只定一次：含 `..` 的名字拒絕，結尾的 `/`、`/.` 去掉。所有寫入
  （含影格複本、裁切圖、封存檔）先寫到實際目錄下的暫存檔再以 `os.replace` 換上，名字上的 symlink、硬連結與 FIFO 都會被換掉
  而不會被寫穿；run 自己的目錄是 symlink 時不寫進去；`--out` 是使用者的路徑，那裡是 symlink 或 FIFO
  時改為拒絕。
- 結果檔只用帳本核對過的紀錄產生，沒通過的只列名一次，frontmatter 記為 `target_invalid`（run 已因別的錯誤停下時保留
  那個錯誤）；frontmatter 每個欄位只寫自己的格式，否則寫 `invalid`；`seal_broken` 只有 true／false。核對過的紀錄仍無法
  呈現時，結果檔只寫固定內容與 run 自己的錯誤類別；result 自己失敗不取代 run 原本的錯誤。
- 只有 codex-call 根本沒能啟動時才撤回這一輪的紀錄（連同為它登記的 profile）；啟動之後的任何事（含輸出無法解碼）都不
  撤回。`ask` 在 codex-call 執行中被 SIGINT 或 SIGTERM 中斷時，codex-call 跟著終止，記為 `backend_error`（算作已送出）；
  從記下請求到 codex-call 啟動之間中斷會先被擋住，這段期間不論因為什麼停下（含啟動失敗）都在擋住的狀態下撤回，訊息寫
  nothing was sent；一步停下或完成之後，記錄期間的中斷一律忽略。其他時候被中斷記為 `internal_error`，已寫出的檔照樣登記。回覆不是 UTF-8 時為 `parse_failed`。工具的輸出一律以 UTF-8 解碼，Big5、Shift-JIS 的 locale 下
  檔名含中日文的圖也量得到尺寸。
- `--vocab` 可以是管線或程序替換（`--vocab <(...)`）；run 的紀錄仍只讀一般檔案。
- 「已經做過」以帳本為準，不讀沒核對過的內容：封存、被拒的放大輪答案與隱私確認看帳本條目（有紀錄沒條目時停下，說它不在
  帳本上，也不換掉；FIFO、dangling symlink 不是紀錄），這一輪的請求看核對過的請求紀錄，init 的嘗試看那些名字上有沒有東西或
  條目；移開再放回不會讓一步重來。除了 `init`、`confirm-privacy`、`adjudicate` 與 `result`，每一步都要求 init 完成。
- 被拒絕而不取代 run 錯誤的指令列成四組的封閉清單：已經做過、還不能做或沒有事可做、Claude 的放大輪答案沒通過檢查、
  指令沒有指到一步。
- run 的錯誤若與帳本不符，或永遠解不開（init 嘗試記下之後的 init 錯誤、請求記下之後那一輪的錯誤），不會被其他步驟取代或
  清除；用掉與否在寫下錯誤的當下判定、記在錯誤裡。`ask` 送出前停下的錯誤，在重跑時請求一記下就清除，所以這一輪之後
  即使被 SIGKILL，結果檔也照紀錄推出這個失敗。
- Python 3.9 等舊版只回答 `runtime_unavailable`、記進錯誤歷史並寫自己的結果檔（固定內容，不讀 run 的任何紀錄，設定與張數
  都留空），不改 run 的
  錯誤與帳本；run 照原樣，改用 3.10 以上重跑那一步即可，之後寫的結果檔照紀錄呈現 run，舊版的停下只留在歷史。
- 外來文字的封閉清單是六種（含 Claude 答案裡的文字與 Codex 的回覆），不進結果檔；推導出來的紀錄（比對結果、裁決）要連
  來源一起核對過才呈現；訊息以位置稱呼使用者給的圖，`--run`、`--vocab`、`--out` 以角色稱呼。
- 原生 bundle 的 preflight 失敗在登入檢查之前回報；沒有送過請求時，結果檔從 `runtime_error.txt` 取錯誤類別。
- 結果檔的路徑過濾只是後備，它在反引號、全形標點等邊界上的殘留是接受的風險。
- 在 Claude Code 裡呼叫 `ask` 時 Bash 工具的 timeout 要設成 600000；它的上限等於預設的 `max_time`，`timeout` 類別出不來。
  harness 以 SIGKILL 結束時結果檔仍顯示這一輪失敗：沒有其他紀錄不符時從請求紀錄推出 `backend_error`，否則是
  `target_invalid`（#26 追蹤）。
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
