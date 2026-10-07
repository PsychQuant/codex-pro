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
- 第二輪：只針對分歧，由 skill 用 macOS `sips` 依分歧位置裁切、放大 2 倍，產生新圖送出。數量題的裁切範圍涵蓋兩邊在該格該類別的全部關鍵點，否則裁切區內的數量不能拿來裁決整張影格的數量；位置題要求列出裁切區內該類別的全部關鍵點，再依物件配對判斷分歧點對應哪一個物件。沒有關鍵點可圈、或範圍等於整張畫面時不出放大題，因為那不是新的證據。

替代方案是讓 Codex 自己裁切（`codex exec`）。不採用：違反 Design constraint #1，使用者選擇由 skill 先裁好。

12 張是保守的選擇，不是後端限制：上游 #87 的實測（2026-10-07，`gpt-5.6-sol`、effort low）中，24 張 1920×1080 JPEG（request body 13.45 MB）與 8 張 2048×2048 PNG（109.10 MB）都一次成功、順序正確，上限尚未量到。維持 12 張是為了讓單次回覆的 JSON 不過長、出錯時重送的成本小。

### 主張的 JSON schema 與量化門檻

每格的主張都是封閉清單裡的物體，以及它們的數量與關鍵點位置（畫面寬高的百分比）。每個被計數的物件都要有一個關鍵點，點數與數量不符的答案不合格：第一版允許省略關鍵點，缺的點在比對時靜默消失，一致率因此虛高（verify 第一輪 B7）。

### 關鍵點由詞彙表指定

詞彙表的 `key_points` 列出哪些類別有關鍵點、關鍵點怎麼定義（例如器械：夾口尖端）。只有列出的類別要給點、比位置；其他類別只比數量。關係詞的兩邊與 SAM 追蹤的類別都必須有關鍵點。

理由：第一輪後要求「每個物件都要一個關鍵點」，但練習墊、縫線這類物件沒有明確的關鍵點，兩個模型各點一處必然相差超過門檻，整格被判為不一致，SAM 也拿不到錨點；在主要用途上一致率會接近 0（verify 第二輪 R2）。使用者選擇由詞彙表指定（2026-10-07）。

### 關係詞綁定兩個類別

關係詞（例如「會合」）寫成 `{"between": [類別, 類別], "definition": "<量> <比較> <數字>"}`。定義只接受「量的名稱、比較符號、數字」這個形式，`between` 指明量的是哪兩類物件的關鍵點。原本的接觸物欄位（`touching`）拿掉，「碰到什麼」一律寫成有門檻的關係詞。

量只接受 `distance_pct`，定義為「第一類的一個關鍵點與第二類另一個關鍵點之間的最小距離」，所以某類物件不是剛好兩個時也有確定的答案。

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
- `init` 在位元組層面去除影格的內嵌資料（EXIF／XMP、拍攝時間、GPS、附加在影像之後的資料），清除前先依 EXIF 方向轉正；不靠重新編碼，因為實測 `sips` 重新存檔會保留甚至加回 EXIF。中性檔名之外不帶任何時間線索。
- run 目錄寫入 `.gitignore`，影格複本不會被 `git add -A` 帶上 remote。

理由：第一版只在 SKILL.md 寫提醒，程式沒有關卡；影格原樣複製，EXIF 隨圖送出；run 目錄留在使用者專案裡（verify 第一輪 I2、I3）。

### 裁決規則

每個分歧的結果只有三種：`resolved_claude`、`resolved_codex`、`unverifiable`。SAM 的量測值離門檻不到 1%（寬度百分比，可用詞彙表的 `sam_margin_pct` 改）時不算證據：實測（2026-10-07，12 格腹腔鏡影格）SAM 量出的兩尖端距離與標註相差中位 0.28%、最大 0.91%，曾有一格兩者正好跨在 5% 門檻兩側。多項證據互相矛盾時判 `unverifiable`。只有第三種證據（放大後兩邊重答一致、SAM 有效格的量測、違反物理約束）能裁決；沒有有效證據就是 `unverifiable`。不用多數決，也不讓任何一方看到另一方的答案後改答。

第二輪補上三條：
- 放大輪或 SAM 看到的數量只能證實較高的一方。裁切區外或沒有錨定的物件看不到，所以看到的數量等於較低的一方時，什麼也證明不了；第一版會因此在一方重複標記時判錯方（第二輪 R1）。
- 放大輪推翻雙方原答時，該分歧為 `unverifiable`，其他證據不得改判（第二輪 R3）。
- 違反 max_count 只排除一方。Claude 數 3、上限 2、Codex 數 1 時，真值可能是 2，所以單獨存在時是 `unverifiable` 並註明被排除的一方；與其他證據一致時才裁決（第二輪 R4）。

### 送出後的錯誤另立一類

`codex-call` 在送出後失敗（HTTP 400／500、連線中斷）記為 `backend_error`。原本落到 `runtime_unavailable`，而那一類的說明是「沒有送出請求」，結果檔還把它標成 preflight（第二輪 R5）。被拒絕的重跑（重封、同一輪再送）只進錯誤歷史，不取代這個 run 的錯誤（第二輪 R6）。

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

- 主張 JSON（每格一筆）：`{"frame": "<中性檔名>", "objects": {"<類別>": <數量>}, "points": [{"class": "<類別>", "x_pct": <0–100>, "y_pct": <0–100>}], "relations": {"<關係名>": <true|false>}}`；每個類別的點數等於它的數量。
- 清單檔：`classes`（類別與說明）、`constraints`（物理約束，文字）、`max_count`（各類別上限，裁決用）、`relations`（關係名對應 `{"between": [類別, 類別], "definition": "distance_pct < 5"}`）、`position_threshold_pct`（預設 5）、`track_class`、`sam_margin_pct`。
- 結果檔：frontmatter 如 Decisions 所列；內文依序是「一致率與分歧摘要」「逐格分歧與裁決」「SAM 狀態（未安裝、無效格數、錨點）」「封存驗證」「限制」。
- 比對腳本與 SAM 腳本放在 skill 的 `scripts/` 底下，輸入輸出都是 JSON，可單獨執行與測試。

**失敗模式**

- `runtime_unsupported`、`target_invalid`、`parse_failed`、`rate_limit`、`oauth_invalid`、`timeout`、`runtime_unavailable`、`package_corruption`、`internal_error`：一律寫結果檔、不 retry。
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
