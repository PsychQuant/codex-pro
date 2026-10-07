## Context

- **為什麼做**：使用者在一個影片評分工作中發現，單一模型從影格判讀會看錯而不自知。用 SAM 2.1 追蹤器械、再請 Codex 盲答核對，推翻了 Claude 三處判讀。使用者要把這個流程做成 codex-pro 的 skill，並決定**內建 SAM**，理由是「評分的準度是最重要的」。
- **現況**：
  - `codex-call` 只收文字。
  - Claude plugin 的 skill 從外部 PATH 找 `codex-call`（由 parallel-ai-agents 提供）。
  - 原生 Codex bundle 用 vendored snapshot，透過 `bin/codex-pro-call` 驗 SHA-256 後執行；snapshot 鎖在上游 commit `6fc6883`。
  - 上游之後已加入背景執行功能（`e3d1ceb`）。
- **限制**：
  - Design constraint #1–#4：只走 `codex-call`、硬 timeout、rate limit 斷路、結構化結果檔。
  - 產生 Codex 請求的 skill 只支援 macOS。
  - 新 skill 必須進 `scripts/codex-skills.manifest` 與 parity 測試。
- **Clarity 已決**（#23）：
  - 長邊超過 2048 px 先縮小，原檔超過 20 MB 報錯。
  - 先改上游再重新 vendor。
  - 需要放大時由 skill 先裁好再送。
  - Claude 答案寫檔並記 SHA-256。
  - 內建 SAM 2.1。

## Goals / Non-Goals

**Goals:**

- 讓 Claude 與 Codex 對同一批圖片各自獨立判讀，用確定性程式比對，找出分歧。
- 分歧以第三種證據裁決（放大複查、SAM 追蹤、物理約束），不用多數決、不讓一方遷就另一方。
- 結果檔可被 `/codex-pro:codex-status`、`codex-result` 讀取，並能事後驗證 Claude 的答案在 Codex 作答前已封存。
- runtime 不支援圖片時，在送出前就停下，而且看得出原因。

**Non-Goals:**

- 不證明判讀「正確」：兩邊一致不等於對，準度的最終驗證要靠人工標準答案。
- 不暴露上游的背景執行功能（`--detach/--poll/--abort`）給任何 skill。
- 不支援非 macOS 主機產生 Codex 請求；不內建 SAM 3（需申請權限）、YOLO 或其他偵測模型。
- 不決定 #15（`codex-call` 的所有權歸屬）。
- 不替使用者判斷圖片中哪些內容該遮蓋。

## Decisions

### Producer 結構比照 codex-review

skill 屬 mutating producer。流程：解析參數 → 讀 profile → 前景同步呼叫 `codex-call` → 寫 `.codex-pro/visual-xval-<timestamp>.md`。frontmatter 沿用 review 的欄位，另加 `n_images`、`n_claims`、`agreement_rate`、`claude_answers_sha256`、`sealed_at`、`sam_status`。

替代方案是讓 skill 只輸出到對話。不採用：違反 Design constraint #4，且 status／result 讀不到。

### 失敗分類增加兩類

在 rate_limit、oauth_invalid、timeout、target_invalid（沒有圖片或清單無效）之外，新增兩類：

- `runtime_unsupported`：runtime 不支援 `--image`。
- `parse_failed`：Codex 回覆不是符合 schema 的 JSON。

原生 bundle 另沿用 `runtime_unavailable`、`package_corruption`。腳本內部的意外例外記為 `internal_error`，讓「每次 run 都寫結果檔」沒有例外。全部不 retry，一律寫結果檔。

### Runtime 圖片能力在送出前檢查

送出前先執行 `codex-call --help`，輸出必須含 `--image`；原生 bundle 另先跑 `codex-pro-call --check`。

理由：舊版 `codex-call` 會把不認得的 flag 當成 prompt 吞掉且回傳 0（pai #80），圖片沒送出也不會報錯。替代方案是看版本號；不採用，因為 Claude 端的 PATH runtime 版本號格式不受 codex-pro 控制，直接看 `--help` 最不受版本格式影響。

### Claude 答案先封存

Claude 的逐格答案先寫到 run 目錄 `.codex-pro/visual-xval-run-<timestamp>/claude.json`，計算 SHA-256 並記錄時間，**之後**才呼叫 Codex。比對前重新計算 SHA-256，不符就在結果檔標示 `seal_broken: true`，比對照做，但結論欄註明封存失效。

先後由程式強制，不靠流程約定：`ask` 在沒有封存或封存不符時不送請求，封存一旦寫下就不能重寫。第一版只寫了封存，`ask` 卻不檢查它，先送 Codex、事後才封存的 run 產出的結果檔與正確流程一模一樣（verify 第一輪 B1）。紀錄只有在某個閘門依賴它時才是保證。

替代方案是只靠流程約定。不採用：使用者選擇可事後驗證。

### 答案只記一次

每一輪只送一次請求：送出前記下請求時間，Codex 的回覆存檔並記錄 SHA-256。同一輪再送一次，程式直接停下。結果檔列出 Codex 的請求時間與回覆雜湊，讀者可以核對「封存早於請求」與「回覆沒被改過」。

理由：spec 規定已記錄的答案不得被同一模型後來的答案取代。第一版的 `ask` 每次都覆寫 `codex.json`，等於允許重問到兩邊一致為止，這就是用重試做多數決（verify 第一輪 B3）。

### 放大輪由不知情的 subagent 作答

放大輪 Claude 這一側不由執行 skill 的 Claude 作答，改由一個全新的 subagent 作答。它只拿到 `crops` 寫出的題目檔與裁切圖，不知道原答、不知道分歧內容，與 Codex 拿到的完全相同。答案以裁切圖檔名為鍵，用與 Codex 回覆相同的規則驗證，封存後才送 Codex；裁決前重算這份封存，不符就不採用放大輪證據。

理由：執行 skill 的 Claude 知道哪裡有分歧，也記得自己的原答。布林關係只有真假兩種值，它知道「這裡有分歧」與自己的原答，就等於知道 Codex 的答案，可以翻成同一個值讓裁決判給 Codex（verify 第一輪 B4）。

替代方案：關係分歧不走放大輪（沒有 SAM 時多半停在 unverifiable）；只採信 Codex 改答的一側（不對稱，裁決偏向 Claude）。使用者選擇 subagent（2026-10-07）。

### Python 3.10 以上

腳本需要 Python 3.10 以上。`xval.py` 在載入任何其他模組之前檢查版本；版本不符時照樣寫結果檔（`runtime_unavailable`），不會在 import 時崩潰而留下空白。

理由：macOS 內建的 `/usr/bin/python3` 是 3.9，第一版在那裡 import 就崩潰，連結果檔都沒有（verify 第一輪 B10）。替代方案是改寫成相容 3.9；使用者選擇宣告需求（2026-10-07），由 #25 的 setup 檢查補上事前提示。

### 一輪一批，第二輪只送放大圖

- 第一輪：一次送整批圖片（上限 12 張，用 `--image` 重複帶入），要 Codex 依 JSON schema 回答。超過 12 張時 `init` 以 `target_invalid` 拒絕；要判讀更多張就分成多次 run。
- 第二輪：只針對分歧，由 skill 用 macOS `sips` 依分歧位置裁切、縮放，產生新圖送出。倍率最多 2 倍，而且長邊不超過 2048 px（`codex-call` 會把更長的圖縮小，所以更大的倍率不是 Codex 看到的），題目檔寫出每張裁切圖的實際倍率。數量題的裁切範圍涵蓋兩邊在該格該類別的全部關鍵點，否則裁切區內的數量不能拿來裁決整張影格的數量；位置題要求列出裁切區內該類別的全部關鍵點，再依物件配對判斷分歧點對應哪一個物件。沒有關鍵點可圈、或範圍等於整張畫面時不出放大題，因為那不是新的證據。

替代方案是讓 Codex 自己裁切（`codex exec`）。不採用：違反 Design constraint #1，使用者選擇由 skill 先裁好。

12 張是保守的選擇，不是後端限制：上游 #87 的實測（2026-10-07，`gpt-5.6-sol`、effort low）中，24 張 1920×1080 JPEG（request body 13.45 MB）與 8 張 2048×2048 PNG（109.10 MB）都一次成功、順序正確，上限尚未量到。維持 12 張是為了讓單次回覆的 JSON 不過長、出錯時重送的成本小。

### 主張的 JSON schema 與量化門檻

每格的主張都是封閉清單裡的物體，以及它們的數量與關鍵點位置（畫面寬高的百分比）。每個被計數的物件都要有一個關鍵點，點數與數量不符的答案不合格：第一版允許省略關鍵點，缺的點在比對時靜默消失，一致率因此虛高（verify 第一輪 B7）。

### 關鍵點由詞彙表指定

詞彙表的 `key_points` 列出哪些類別有關鍵點、關鍵點怎麼定義（例如器械：夾口尖端）。只有列出的類別要給點、比位置；其他類別只比數量。關係詞的兩邊與 SAM 追蹤的類別都必須有關鍵點。

理由：第一輪後要求「每個物件都要一個關鍵點」，但練習墊、縫線這類物件沒有明確的關鍵點，兩個模型各點一處必然相差超過門檻，整格被判為不一致，SAM 也拿不到錨點；在主要用途上一致率會接近 0（verify 第二輪 R2）。使用者選擇由詞彙表指定（2026-10-07）。

### 關係詞綁定兩個類別

關係詞（例如「會合」）寫成 `{"between": [類別, 類別], "definition": "<量> <比較> <數字>"}`。定義只接受「量的名稱、比較符號、數字」這個形式，`between` 指明量的是哪兩類物件的關鍵點。原本的接觸物欄位（`touching`）拿掉，「碰到什麼」一律寫成有門檻的關係詞。

量只接受 `distance_pct`，定義為「第一類的一個關鍵點與第二類另一個關鍵點之間的最小距離」，所以某類物件不是剛好兩個時也有確定的答案；一對這樣的點都沒有時，關係為 false。放大輪的關係題沿用同一個完整定義，並附上兩個類別的關鍵點定義，因為作答的 subagent 只看得到題目檔（第三輪 T7）。

理由：第一版只檢查定義裡有沒有「符號＋數字」，`很近（< 5）` 也能通過，而且沒說量哪兩點，兩個模型可以各量各的；SAM 也因此拿兩支器械的距離去裁決不相干的關係（verify 第一輪 I5、B5）。第二輪又發現 `closeness < 5` 這種沒有定義的量名仍能通過（第二輪 S7）。`touching` 有收集卻從不比對，等於一個沒有門檻的關係詞。

比對分三類：

- 數量不同。
- 同類物體依最近距離配對後，位置差超過門檻（預設畫面寬 5%）。
- 關係判斷不同。

`agreement_rate` = 三類都沒有分歧的格數 ÷ 總格數。

替代方案是讓模型自己比較兩份答案。不採用：這正是實測中出錯的方式。

### 內建 SAM 2.1，多錨點，偵測塌陷

- **環境**：skill 附 `sam_env.sh`，在 `~/.codex-pro/sam-env/` 用 uv 建 venv，鎖定 transformers 5.19 以上與相容的 torch。模型用 `facebook/sam2.1-hiera-large`（Hugging Face 上不需申請權限）。第一次安裝前先顯示預估下載量，取得使用者同意才進行。
- **錨點**：取兩邊判讀一致的影格當錨點，用一致的位置當提示點；每一段一致的影格都重新錨定，縮短傳遞距離。
- **塌陷偵測**：兩個物件遮罩的 IoU 超過 0.5，該格標為 invalid，不拿來裁決。實測中只錨定一格時，909 格裡有 332 格塌成同一支器械，所以多錨點與塌陷偵測都必要。
- **證據範圍**：SAM 只追蹤一個類別（`track_class`），所以數量與位置證據只用於同一類別的分歧，關係證據只用於 `between` 兩邊都是追蹤類別的關係。位置證據先把追蹤到的尖端與兩邊的全部關鍵點配對，看分歧點各自對應哪一個物件，不取「離任一方最近的尖端」（verify 第一輪 B5、B6）。物件是否存在以模型的 object score 判定，不只看遮罩面積。
- **長影片**：影格存在 CPU 記憶體（`video_storage_device="cpu"`），避開 MPS 的張量上限。

替代方案：
- 可選的外部步驟：使用者原本選這個，後改為內建，理由是準度。
- SAM 3：可用文字提示，但 Hugging Face 上需申請權限，目前取得不到。

### 送出前確認與影格清理

- 隱私提醒是閘門：使用者確認後，skill 才記錄確認時間，`ask` 沒有這筆紀錄就不送。
- `init` 先由 `sips` 把影格解碼、轉成 sRGB、長邊縮到 2048 以內後重新編碼成新檔，再依 EXIF 方向轉正，最後在位元組層面以白名單去除 `sips` 自己寫入的 metadata（EXIF／XMP、拍攝時間）。中性檔名之外不帶任何時間線索。
  - 只做位元組層的清除不夠：第四輪之後的背景安全審查指出，白名單只看區段的標記或簽章，資料可以藏在允許的區段裡（ICC profile、Adobe APP14），解析器與解碼器對位元組的切法不同時也有縫。只重新編碼也不夠：實測 `sips` 重新存檔會保留甚至加回 EXIF。兩者合用，送出的每個位元組都來自編碼器。使用者選擇（2026-10-07）；代價是 JPEG 以品質 95 重新壓縮一次。
  - 長邊限制在 2048 是 `codex-call` 本來就會做的縮小，提前在複本做，Claude 與 Codex 在第一輪拿到的是同一個檔案（服務端各自是否再縮圖，程式控制不到）。放大輪另用原解析度的複本，見第五輪的段落。
- run 目錄寫入 `.gitignore`，影格複本不會被 `git add -A` 帶上 remote。

理由：第一版只在 SKILL.md 寫提醒，程式沒有關卡；影格原樣複製，EXIF 隨圖送出；run 目錄留在使用者專案裡（verify 第一輪 I2、I3）。

### 裁決規則

每個分歧的結果只有三種：`resolved_claude`、`resolved_codex`、`unverifiable`。SAM 的量測值離門檻不到 1%（寬度百分比，可用詞彙表的 `sam_margin_pct` 改）時不算證據：實測（2026-10-07，12 格腹腔鏡影格）SAM 量出的兩尖端距離與標註相差中位 0.28%、最大 0.91%，曾有一格兩者正好跨在 5% 門檻兩側。多項證據互相矛盾時判 `unverifiable`。只有第三種證據（放大後兩邊重答一致、SAM 有效格的量測、違反物理約束）能裁決；沒有有效證據就是 `unverifiable`。不用多數決，也不讓任何一方看到另一方的答案後改答。

第二輪補上三條：
- 放大輪或 SAM 看到的數量只能證實較高的一方。裁切區外或沒有錨定的物件看不到，所以看到的數量等於較低的一方時，什麼也證明不了；第一版會因此在一方重複標記時判錯方（第二輪 R1）。
- 放大輪推翻雙方原答時，該分歧為 `unverifiable`，其他證據不得改判（第二輪 R3）。
- 違反 max_count 只排除一方。Claude 數 3、上限 2、Codex 數 1 時，真值可能是 2，所以單獨存在時是 `unverifiable` 並註明被排除的一方（第二輪 R4）。

### 證據只用來證明它證得出來的事

第二輪的三條規則各自正確，合起來卻互相矛盾（第三輪 T3、T5）：
- 放大輪數到的數量比雙方都低時，被寫成「推翻雙方」並壓過 SAM。但依 R1 的理由，看到的數量只是下限，低於雙方什麼也推翻不了。
- 只有一方超過上限時，被排除的一定是較高的一方，而看到的數量只能證實較高的一方，所以 `max_count` 永遠促成不了裁決；DA 窮舉 1152 種組合，0 種得到裁決。

第三輪把三種分歧都改成「證據給出的上下界」：
- **數量**：放大輪兩邊一致的數量、SAM 追蹤到且存在的物件數都是下限；`max_count` 是上限。低於下限或高於上限的一方被排除。只有在另一方被排除、而且這一方的數量正好等於最高的下限時才裁決；兩方都被排除、或下限高於上限時是 `unverifiable`。例：Claude 3、Codex 2、上限 2、放大輪兩邊都數到 2 → 判 Codex。使用者選擇這個做法（2026-10-07），理由是推理嚴格成立、能多裁決一些案例。
- **位置**：兩個分歧點對到同一個物件、而且那個物件離兩點都超出門檻時，推翻雙方；放大輪在裁切區裡沒有找到靠近任一點的物件時也是。第二輪的「推翻雙方」只檢查數量與關係，位置分歧被推翻時 SAM 照樣判給一方（第三輪 T3）。
- **關係**：SAM 只量到被錨定的物件，放大輪只框到兩邊標過的點，量到的最小距離只是整格最小距離的上界，所以「< 門檻」證得出來，「≥ 門檻」證不出來。只有雙方在該格對這兩類的數量一致（SAM 另外要求追蹤到的物件數等於那個數量）時，才兩個方向都採用（第三輪 T4）。第四輪起放大輪只證明「< 門檻」，兩個方向都採用只剩 SAM，見第四輪的段落（U2）。

任何證據推翻雙方時，其他證據都不得改判。只比數量的類別沒有放大題，SAM 也不追蹤，所以它們的數量分歧只會被排除、永遠不會被裁決；這寫進詞彙表說明與結果檔的 Limitations，不另外設計證據（使用者選擇，2026-10-07，第三輪 T8）。

### 送出後的錯誤另立一類

`codex-call` 在送出後失敗（HTTP 400／500、連線中斷）記為 `backend_error`。原本落到 `runtime_unavailable`，而那一類的說明是「沒有送出請求」，結果檔還把它標成 preflight（第二輪 R5）。被拒絕的重跑（重封、同一輪再送）只進錯誤歷史，不取代這個 run 的錯誤（第二輪 R6）；「已經做過」的檢查排在其他檢查之前，否則被拒的重跑會先撞上別的檢查而寫進錯誤（第三輪 T6）。

### 看不出有沒有送出時，一律當成送出

第二輪的修法讓 `runtime_unavailable` 撤回請求紀錄，理由是「沒送出的請求不該記成送出」。但 `runtime_unavailable` 是分類的預設值，而 `codex-call` 在收到回應之前的任何失敗都只印 `HTTP 0: (no body)`：離線（確實沒送）與上傳完才斷線、逾時（已經送出）印的是同一行字。後端串流的 error 事件也沒有固定字樣。結果是圖片已經送出、紀錄卻被刪掉，同一輪可以再送一次（第三輪 T1）。這一輪的 verify，Codex 腿本身就是這樣失敗的。

改成 fail-closed：只有一份封閉列舉裡的錯誤算「沒有送出」，其餘一律保留紀錄、記為 `backend_error`（或可辨認的 rate_limit、oauth_invalid、timeout）。列舉是 `codex-call` 在任何網路請求之前就會停下的那幾種：圖片檢查（`--image …`）、未知選項或不合法的 `--max-time`、讀不到或空白的 prompt、`auth.json` 不是物件或缺欄位、token refresh 的鎖檔、refresh 沒拿到 token。不得依字面相似類推其他類。第三輪原本還列了「refresh 被拒（`invalid_grant`）」，第四輪拿掉，見下方第四輪的段落。

代價：離線時這一輪也會被鎖住，要另開一個 run。要精確分辨，得由 `codex-call` 印出原始錯誤碼與已送出的位元組數，這交給上游 PsychQuant/parallel-ai-agents#89（使用者選擇，2026-10-07）。第五輪起封閉列舉取消，見第五輪的段落；#89 在第六輪改為要求專屬的 exit status，見第六輪的段落。

### 第四輪：證據只在它看得到的範圍內作數

第四輪 verify 找到的問題都是同一個原則的邊界：證據只能證明它看得到的東西。

- **封閉列舉要錨定在 codex-call 自己的那一行**（U1；第五輪起取消，見第五輪的段落）。第三輪有兩條沒有錨定，後端回應的文字含 `auth.json` 或 `invalid_grant` 就會被當成沒送出；`classify` 又取最後一行 `error:`，多行的錯誤內容可以偽造這一行。改為只看第一行、整行比對。token refresh 失敗時印的 `HTTP <status>` 與主請求失敗完全相同，所以 `invalid_grant` 不再算送出前，一律當成已送出；要分辨得靠上游 PsychQuant/parallel-ai-agents#89 把 refresh 的失敗另外標出來。
- **放大輪的關係題只證明「近」**（U2）。第三輪規定沒有一對關鍵點時答 false，這讓 false 可能只是裁切區湊不出一對點，而放大輪只回 true／false，看不出模型看到了幾個點。所以放大輪只用來證明 `distance_pct < N`（或 `<=`）為 true，這個答案一定來自一對真的很近的點。使用者選擇這個做法（2026-10-07）：最簡單、一定成立，代價是「其實很遠」那一側較常停在 unverifiable。
- **SAM 不能推翻雙方**（U3）。SAM 只追蹤錨定的物件，配對時會把分歧點硬配到最近的那個追蹤物件；第三輪讓這種配對「推翻雙方」，結果壓過了一致的放大輪證據。只有窮舉的證據（放大輪列出裁切區內每一個點）能推翻雙方。
- **SAM 量的是遮罩的尖端**（U4）。尖端是遮罩上離進入點最遠的像素，只對器械這類物件是關鍵點；詞彙表的關鍵點卻可以是圓心。詞彙表要宣告 `track_point: tip`，SAM 才提供位置與關係證據；沒宣告時只提供數量證據（數量與關鍵點的種類無關）。使用者選擇（2026-10-07）。SAM 的關係量測要追蹤到「有尖端的」物件數等於雙方一致的數量，才兩個方向都採用。
- **run 目錄不接管別人的檔案**（U5）。第三輪讓失敗的指令也建立 run 目錄並寫 `.gitignore`，`--run .` 會蓋掉專案自己的 `.gitignore`。改為只有新建的目錄才寫 `.gitignore`、不覆寫既有的；含有非本 run 檔案的目錄不能當 run 目錄；只有 `init` 失敗時會為了記錄錯誤而建立目錄。
- **第一輪送出前核對輸入**（U6）。封存時記下的影格與詞彙表雜湊，原本要到 compare 才核對，影格被換回帶 GPS 的原檔照樣送出。改為送出前核對，且送出的檔案必須在 run 的 frames 目錄內。

雙方數量一致時，SAM 的關係量測兩個方向都採用，這等於把雙方一致的數量當成真值；兩個模型一致不代表正確，這一點寫進結果檔的 Limitations（M11）。

### 第五輪：不靠字樣判斷送出，也不讓重新編碼拿走放大輪的細節

- **codex-call 失敗一律當成已送出**（V1、V2）。第四輪把封閉列舉錨定在 codex-call 的第一行，但後端的串流錯誤事件原文照印，只要內容剛好與列舉的字樣相同，已送出的一輪仍會被當成沒送出；同時「讀不到 auth.json」因為印的是系統訊息，被當成已送出，最常見的「沒登入」反而鎖住這一輪。只看字樣，兩個方向都會出錯。改為：codex-call 只要失敗就保留紀錄，只有程式根本沒啟動時才算沒送出；常見的送出前狀況改由 xval 在呼叫之前自己檢查——Codex 是否已登入（token 檔案存在且有 token 欄位，不讀出內容）、影格與 prompt 是否就緒，沒過就不呼叫、給出正確的處置。使用者選擇（2026-10-07）。代價：codex-call 自己的其他送出前檢查失敗時（極少見），這一輪也會用掉。第三、四輪的封閉列舉因此取消。
- **放大輪從原解析度的複本裁切**（V7）。第四輪把複本統一縮到長邊 2048，第一輪兩個模型看到同一張圖，卻讓放大輪只是把 2048 的像素放大，失去它存在的意義。改為：原圖長邊超過 2048 時，init 另外寫一份原解析度、同樣重新編碼並清除 metadata 的複本，只用來裁切；第一輪仍用 2048 的複本。使用者選擇（2026-10-07）。
- **位置題的裁切邊距以畫面寬度為單位**（V3）。門檻以畫面寬度的百分比計，垂直方向要換算成高度的百分比（除以高寬比），否則橫向影格的上下涵蓋不到門檻。
- **之後的每一步都核對輸入**（V8、N1）。封存時核對 init 寫下的輸入雜湊，crops、sam、adjudicate 開頭都核對封存的雜湊；原本 compare 之後改詞彙表的 `max_count` 就能改變裁決。
- **只有 init 會建立目錄**（V5）。其他步驟遇到不是 run 的目錄就拒絕，不寫任何檔案。
- **結果檔只寫檔名**（V4）。路徑在產生錯誤的地方就只放檔名；結果檔再把剩下的絕對路徑縮成最後一段，網址不動。第四輪只替換家目錄與暫存目錄，其他位置的完整路徑又跑了出來。

### 第六輪：比對之後也核對答案檔，路徑在產生的地方就只放檔名

- **錯誤細節由檔名組成**（W1）。第五輪的後備過濾以空白為界，含空白的目錄名照樣進結果檔；詞彙表路徑、sips 的指令列、OSError 的訊息也還帶完整路徑。改為：錯誤細節在產生的地方就只放檔名（sips 失敗只報結束碼，OSError 只報原因與檔名）；結果檔的後備過濾從路徑起點一路吃到最後一個 `/`，跨過空白，寧可多吃掉一些文字，也不留下目錄名。skill 自己的固定位置 `~/.codex-pro/` 保留原樣，否則使用者找不到 SAM 環境裝在哪裡。相對路徑無法從文字裡認出來，所以靠的是產生的地方只放檔名。
- **比對之後，答案檔也要是比對時的那一份**（W2）。compare 記下它讀到的 claude.json、codex.json 的雜湊；crops、sam、adjudicate 開頭核對，不符就停在 `target_invalid`；結果檔寫出時也重算一次。原本 compare 之後改兩邊一致格的點，SAM 的錨點就跟著移動，結果檔仍寫封存完好。輸入的雜湊另外納入 meta.json 的設定（`sequence`、`order` 等），meta.json 沒有參考雜湊時封存拒絕，不再放行；frames.json 被改成型別不對的 JSON 時當成輸入被改過；原解析度複本必須在 `run/hires` 之內，與第一輪對影格的要求相同。
- **會寫入目錄的步驟列成封閉清單**（Q1）。第五輪的「只有 init 會建立目錄」是一句總括判準，與 SKILL 的步驟順序衝突（Step 1 先建目錄、Step 2 confirm-privacy 寫進去），result 也要寫 `.codex-pro/`。改成封閉列舉，只有這五類，不得依性質相似類推：
  1. `init` 建立 run 目錄（不存在時）與其中的 `frames/`、`hires/`；
  2. `confirm-privacy` 只接管已經存在的空目錄（Step 1 建的），不建立任何目錄；
  3. `crops` 在 run 目錄內建立 `crops/`；
  4. `result` 把結果檔寫到 `--out`，沒給時才建立工作目錄下的 `.codex-pro/`；不是 run 的目錄裡的檔案它一概不讀；
  5. `sam_env.sh install` 建立 `~/.codex-pro/sam-env`。

  其他步驟遇到不是 run 的目錄就拒絕，不寫任何檔案。
- **登入檢查看 codex-call 讀的那一份**（Q4）。codex-call 讀帳號本身家目錄的 `~/.codex/auth.json`，不看 `$HOME`；檢查原本跟著 `$HOME`，兩者可能不是同一個檔。refresh token 失效（久未使用）時檢查會通過、codex-call 在 refresh 時失敗，這一輪會用掉，圖片卻沒有送出：只寫進文件，請使用者重新登入、另開一個 run（Q5，使用者選擇，2026-10-07）。只看 access token 的到期時間分不出 refresh 會不會成功，擋下來會連 refresh 會成功的正常情況一起擋。
- **送出前要就緒的東西，在記錄請求之前寫好**（Q6）。prompt 檔先寫，再記錄請求、啟動 codex-call；寫不進去就停在 `runtime_unavailable`，什麼都沒送出。
- **`backend_error` 的意思是「codex-call 啟動之後失敗」**（Q3）。封閉列舉取消後，codex-call 自己的本機失敗（讀不到 prompt、鎖檔權限）也落在這一類；算作已送出是對的，但規格原本把它定義成「後端或連線出錯」，SKILL 也回報「Codex 後端出錯」。定義改成「codex-call 啟動之後失敗、沒有更具體的類別，算作已送出」。
- **解不開的圖靠檔案結構判斷**（Q13）。sips 帶 `--matchTo` 時，IDAT 不是壓縮資料的 PNG 也回 exit 0，產出全黑的圖；截斷的 PNG、JPEG 則安靜地解出一部分。兩個模型在空白圖上的答案一致，一致率虛高。所以 init 在交給 sips 之前先核對檔案結構：PNG 每個 chunk 的 CRC、壓縮資料完整且長度不少於 IHDR 推算的值（Apple 的 CgBI PNG 是 raw deflate）；JPEG 在掃描資料之後要有 end-of-image；GIF 要有結尾位元組；WebP 的長度欄位不超過檔案。看不出來的是結構完整、但壓縮資料本身壞掉的 JPEG、GIF、WebP。這個檢查本身不能成為解壓炸彈（背景安全審查）：一次最多解壓 1 MB、只數到 IHDR 承諾的長度、不呼叫會一次解完剩餘資料的 `flush()`；IHDR 的寬高是傳送者寫的，所以超過 2.5 億像素的圖直接拒收，其他格式也以標頭的尺寸在交給 sips 之前核對。
- **上游 #89 改成要求 exit status**（Q11）。#89 原本要 codex-call 在訊息裡多寫送出的位元組數，但第五輪已經決定字樣不可信。改為要求「主請求一個位元組都沒送出」時用專屬的 exit status，後端的文字偽造不了；上游做到之後，xval 才把那個 exit status 判為沒送出。使用者選擇（2026-10-07）。

### 放大輪不採用不是 run 的錯誤

Claude 的放大輪答案格式不合時，SKILL 說放大輪不採用、照樣往下走，程式卻把它記成 run 的錯誤（`seal`，看不出是哪一輪），完整跑完的 run 被標成失敗（第三輪 T6）。改為：放大輪封存失敗只記進錯誤歷史並在結果檔註明「放大輪未採用」，不設定 run 的錯誤；錯誤的步驟名稱一律帶上輪次（`seal --zoom`、`ask --round zoom`）。

### 記錄第一方的實際模型

結果檔記錄第一方是哪個模型（`first_side_model`）。在原生 Codex bundle 裡執行時，第一方是 Codex 的宿主模型，兩方同屬 OpenAI；第一方不是 Claude 時，Limitations 註明兩方可能同屬一個模型家族，交叉驗證的價值會打折。理由：本 skill 的前提是不同家族的模型錯誤不相關（第二輪 F1）。使用者選擇記錄並註明，原生版照樣可用（2026-10-07）。

### 重新 vendor 接受上游漂移

上游 #87 從 parallel-ai-agents 最新的 main 實作，發版 commit 會包含 `e3d1ceb` 的背景執行功能，codex-pro 照樣 vendor 進來但不使用。

替代方案是在 `6fc6883` 上只加 `--image`、做成旁支 tag。不採用：上游會分岔，下次同步更痛。

### Provenance 以 JSON 為準

spec 不再逐字寫死 commit、blob、大小與 SHA-256，改規定這些值以 `references/codex-call-provenance.json` 為唯一來源；測試與 `codex-pro-call` 的預期值都比對它。

理由：這次的上游 commit 要等 #87 發版才知道，而且原本 spec、JSON、wrapper、測試四處都寫同一組數字，每次重新 vendor 都要改四處。

## Implementation Contract

**行為**

- `/codex-pro:codex-visual-xval <images...> --vocab <清單檔> [--claude-answers <檔>]` 依序：
  1. 取得隱私確認、建立 run 與影格複本
  2. Claude 作答並封存
  3. 解析 profile、檢查 runtime 是否支援 `--image`
  4. 第一輪送 Codex
  5. 比對
  6. 必要時跑 SAM（排在放大輪之前，放大輪失敗不影響它）
  7. 對分歧送第二輪放大圖（Claude 一側由 subagent 作答）
  8. 裁決並寫結果檔
- 沒給 `--claude-answers` 時，由正在執行的 Claude 依同一 schema 先作答並寫檔，再繼續。
- 結果檔裡每個分歧都標明裁決結果與所用證據。

**介面與資料形狀**

- 主張 JSON（每格一筆）：`{"frame": "<中性檔名>", "objects": {"<類別>": <數量>}, "points": [{"class": "<類別>", "x_pct": <0–100>, "y_pct": <0–100>}], "relations": {"<關係名>": <true|false>}}`；`key_points` 列出的類別，點數等於它的數量，其他類別不給點。
- 清單檔：`classes`（類別與說明）、`key_points`（有關鍵點的類別與關鍵點定義）、`constraints`（物理約束，文字）、`max_count`（各類別上限，裁決用）、`relations`（關係名對應 `{"between": [類別, 類別], "definition": "distance_pct < 5"}`，兩個類別都要有關鍵點）、`position_threshold_pct`（預設 5）、`track_class`（必須有關鍵點）、`sam_margin_pct`。
- 結果檔：frontmatter 如 Decisions 所列；內文依序是「一致率與分歧摘要」「逐格分歧與裁決」「SAM 狀態（未安裝、無效格數、錨點）」「封存驗證」「限制」。
- 比對腳本與 SAM 腳本放在 skill 的 `scripts/` 底下，輸入輸出都是 JSON，可單獨執行與測試。

**失敗模式**

- `runtime_unsupported`、`target_invalid`、`parse_failed`、`rate_limit`、`oauth_invalid`、`timeout`、`runtime_unavailable`、`package_corruption`、`backend_error`、`internal_error`：一律寫結果檔、不 retry。放大輪封存失敗不在其中：它只讓放大輪不採用。
- SAM 未安裝或使用者拒絕安裝：不算失敗，`sam_status: not_installed`，分歧中需要 SAM 的標為 `unverifiable`。
- 圖片超過 20 MB 或不是圖片：由上游 `codex-call` 報錯，skill 以 `target_invalid` 記錄。

**驗收**

- `bash tests/run.sh` 全綠，其中包含：
  - 比對腳本的 fixture 測試，涵蓋三類分歧與 `agreement_rate`，以 f08 例子為案例。
  - 封存 SHA-256 的竄改偵測。
  - runtime 不含 `--image` 時以 `runtime_unsupported` 寫結果檔、不呼叫 runtime。
  - SAM 腳本的塌陷偵測（兩遮罩 IoU > 0.5 → invalid）。
  - parity 與 manifest 測試涵蓋新 skill。
  - provenance 測試改為比對 JSON。
- e2e（opt-in）：用 3 張合成圖跑一次完整流程。

**範圍**

- 在範圍內：新 skill、比對與 SAM 腳本、runtime 能力檢查、重新 vendor、provenance 以 JSON 為準、status 與 result 加入新前綴、相關 spec 與測試、文件與版本號。
- 不在範圍內：上游 #87 本身的實作（在 parallel-ai-agents 進行）、#15 的所有權決定、背景執行功能的使用、非 macOS 支援。

## Risks / Trade-offs

- [後端未公開，多張圖的 payload 上限不明] → #87 實測多張圖；單次 run 上限 12 張，超過時拒絕並請使用者分次執行。
- [上游漂移帶入未經 codex-pro 測試的程式碼] → 重新 vendor 後跑完整測試與 e2e；背景執行功能不接到任何 skill。
- [SAM 依賴重：模型權重 898 MB（856 MiB，實測；只下載 model.safetensors，不下載同一 repo 中用不到的 .pt）、總下載約 1 GB（估計），首次慢，MPS 有坑] → 安裝前取得同意；鎖版本；長片存 CPU；未安裝時降級為 `unverifiable`，不讓整個 skill 失敗。
- [SAM 追蹤會塌陷、換身分或在物件離開畫面後漂到別的東西上] → 多錨點、IoU 塌陷偵測、無效格不裁決；物件存在以 object score 判定，不存在的物件不算證據。
- [圖片外送的隱私風險] → 送出前提醒；skill 不自動判斷該遮什麼。
- [兩邊一致仍可能都錯] → 結果檔的限制段明寫；不以一致率宣稱準度。

## Migration Plan

1. 上游 parallel-ai-agents#87 完成並發版，取得不可變 commit（本 change 的前置）。
2. 重新 vendor 並把 provenance 改以 JSON 為準，跑完整測試。
3. 實作新 skill、腳本與測試。
4. 更新文件與版本號。

**Rollback**：新 skill 獨立，移除 manifest 項目與目錄即可；重新 vendor 可回到舊 snapshot 與舊 JSON。

## Open Questions

- ~~後端一次可收幾張圖、總 payload 上限是多少~~：已在上游 #87（PR #88）實測。24 張、13.45 MB 與 8 張、109.10 MB 都成功，上限未量到。若日後單批需要超過 24 張或 110 MB，要先再量一次。
- ~~SAM 2.1 的授權條款~~：Hugging Face metadata 為 Apache-2.0，已寫進 `THIRD_PARTY_NOTICES.md`；模型不隨 plugin 散布。
