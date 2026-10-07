# Release e2e checklist for codex-pro

本檢核表有兩條人工發行路徑：Codex CLI／App 原生 plugin，以及 Claude Code Layer 3。
兩者都補足靜態與 behavioral tests 看不到的 host 安裝、skill 探索與真實 invocation。

**兩種跑法**：自動化 `bash tests/e2e.sh`（preferred）+ manual checklist（plugin install 等 UI flow）。

跑前先確保 Layer 1 + 2 通過：

```bash
cd <codex-pro repo root>
bash tests/run.sh
```

## Codex native plugin release checklist

這一段必須在**獨立 macOS 登入帳號或 disposable VM** 執行，不能只設定 `CODEX_HOME`。
Vendored Swift runtime 以 `FileManager.homeDirectoryForCurrentUser` 取得
`~/.codex/auth.json`，不讀 `CODEX_HOME`；在日常 macOS 帳號測 producer 仍可能讀取並更新
日常 OAuth。不要複製、改名或刪除日常使用者的 auth file。

### N0. Disposable CLI 環境

- [ ] 登入專用 macOS 測試帳號或啟動 disposable macOS VM；記錄 `whoami` 與 home 路徑，
  確認都不是日常帳號。整段 N0–N5 必須留在此隔離邊界內。
- [ ] 在隔離帳號建立專用工作目錄，例如
  `CODEX_PRO_E2E_WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/codex-pro-e2e.XXXXXX")`；fixture 與
  測試紀錄只放在這個已知路徑。
- [ ] 記下 `CODEX_PRO_E2E_BIN_DIR=$(dirname "$(command -v codex)")`。啟動 smoke task 時，
  將 PATH 限縮為 `"$CODEX_PRO_E2E_BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin"`，並清除 Claude
  plugin 路徑提示：

  ```bash
  env -u CLAUDE_PLUGIN_ROOT -u PLUGIN_ROOT -u CODEX_PLUGIN_ROOT \
    PATH="$CODEX_PRO_E2E_BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    codex
  ```
- [ ] 在隔離 OS 帳號內跑 `codex login`，使用 disposable ChatGPT test account；確認此隔離
  帳號的 `~/.codex/auth.json` 可讀，且日常 OS 帳號的 home 未掛載或未被測試程序存取。
- [ ] 確認 `swift --version` 成功；以下命令應為 non-zero，證明 producer smoke 不依賴
  Claude plugin 注入：

  ```bash
  env PATH="$CODEX_PRO_E2E_BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    sh -c 'command -v codex-call'
  ```

### N1. Self-hosted marketplace 與安裝

- [ ] 加入 Git marketplace：

  ```bash
  codex plugin marketplace add PsychQuant/codex-pro --ref main --json
  ```

- [ ] 跑 `codex plugin marketplace list --json`，確認列出 marketplace `codex-pro`；不能只
  依賴 `plugin list` 的 exit status。
- [ ] 跑 `codex plugin list --marketplace codex-pro --available --json`，確認看到未安裝的
  `codex-pro` 0.9.0。
- [ ] 安裝：`codex plugin add codex-pro@codex-pro --json`。再以 `codex plugin list
  --marketplace codex-pro --json` 確認 installed 與 enabled 狀態。

### N2. 新 task、十個 skills 與 setup

- [ ] 在相同隔離 OS 帳號內，以限縮 PATH 與已清除的 Claude variables 啟動一個**新
  Codex task**。安裝前已存在的 task 不算驗收證據。
- [ ] 在新 task 確認可探索以下十個名稱：`$codex-setup`、`$codex-review`、
  `$codex-adversarial-review`、`$codex-rescue`、`$codex-batch`、`$codex-status`、
  `$codex-result`、`$codex-config`、`$codex-cancel`、`$codex-visual-xval`。
- [ ] 跑 `$codex-setup`。預期 OAuth 可讀，runtime source 為 bundled wrapper，SHA-256 與
  provenance 相符，producer readiness 為 ready；輸出不得提議安裝 Claude Code 或
  `parallel-ai-agents`。
- [ ] 跑純本機 consumer `$codex-config`。預期能顯示 resolved model／effort／max_time，
  不建立 result file、不呼叫網路。

### N3. Producer fixture smoke 與結果檔

- [ ] 在 disposable 路徑建立小型 Git fixture：先 commit 一個短文字檔，再新增一行形成
  current uncommitted diff；不要在 codex-pro repo 本身製造 fixture diff。
- [ ] 從 fixture 目錄開另一個新 task，在仍無 `codex-call` PATH 與 Claude variables 的情境
  叫用 `$codex-review`，選 current uncommitted diff。預期只發出一次前景 producer call，
  不 fallback 到 PATH、不要求安裝 `parallel-ai-agents`。
- [ ] 確認 fixture 下新增且僅新增預期的 `.codex-pro/review-*.md`；檔案含可解析 YAML
  frontmatter、non-empty `## Summary` 與 `## Findings`。
- [ ] 跑 `$codex-status` 看到該 result，再跑 `$codex-result --latest review`，確認顯示同一檔案。

### N4. 更新、重新安裝與 CLI rollback

- [ ] 跑 `codex plugin marketplace upgrade codex-pro --json`，確認 Git snapshot refresh 成功。
- [ ] 跑 `codex plugin remove codex-pro@codex-pro --json` 後，再跑 `codex plugin add
  codex-pro@codex-pro --json`；開**另一個新 task**，再確認版本、十個 skill 與
  `$codex-setup`。
- [ ] 驗證 rollback 順序：先跑 `codex plugin remove codex-pro@codex-pro --json`，再跑
  `codex plugin marketplace remove codex-pro --json`。確認 listing 與已安裝狀態消失，但
  fixture 下既有 `.codex-pro/review-*.md` 保留。
- [ ] 保留測試紀錄後，僅清理 `$CODEX_PRO_E2E_WORKDIR`；先驗證實際路徑位於系統暫存
  目錄，禁止以空變數、`~` 或廣泛路徑執行遞迴刪除。依測試環境政策另行移除隔離 OS
  帳號或 VM。

### N5. Codex App 視覺 gate

- [ ] 在同一隔離 OS 帳號先以 CLI 執行 `codex plugin marketplace add
  PsychQuant/codex-pro --ref main --json`；完全結束並重啟 Codex App。
- [ ] 開啟 Plugins Directory，選擇 `codex-pro` marketplace，確認 listing 顯示同名 plugin
  0.9.0。不要把「加入 Git marketplace」寫成 App UI 內的操作。
- [ ] 安裝並啟用 plugin，開新 task，人工確認十個 skill 可見；跑 `$codex-setup` 與一個純
  本機 consumer。App 仍需遵守 macOS＋Swift 與 OAuth 前提。
- [ ] 走一次 update 或 reinstall UI，開新 task 確認仍載入 0.9.0。
- [ ] 從 App 解除安裝 plugin，必要時移除 marketplace；確認新 task 不再列出 skills，既有
  專案 result files 不被刪除。
- [ ] 記錄官方 directory 狀態為「尚未提交／審核中的外部步驟」；不得把 self-hosted smoke
  寫成已在官方 directory 發布。

以上 N0–N5 是 native release gate。任何一段因 host UI 或網路限制無法執行時，應在發行
紀錄明列 skipped 原因，不能以自動測試取代 App 視覺確認。

## Automated Layer 3 — `bash tests/e2e.sh`

`tests/e2e.sh` 在 fresh `claude --print --plugin-dir` session 觸發 SKILL.md、verify result file 結構 + behavioral marker。6 scenario × 2 producer skill = 12 組合（v0.5 加 `with-profile`：project profile `effort: high` → 驗 result frontmatter `effort: high` + `profile_source: project|mixed`，證實 profile 被 resolve 並流入 codex-call invocation）。

**Quota budget**：
- 每組合 = 1 codex-call quota + ~50k Claude API tokens + 60-180s
- 完整 12 組合 = ~12 codex-call + ~600k Claude API tokens + 12-36 min + ~$0.6-$2.4

**Rate limit recovery**：
- `tests/e2e.sh` 內建 retry — 觀察到 stdout 含 `Server is temporarily limiting requests` 字串時自動 sleep 30s/60s/120s exponential backoff、最多 3 次 retry
- 若 3 次仍 throttle、script exit 4；user 手動 wait 5min 後重跑該組合
- Codex-call 本身的 fail-fast (rate_limit / oauth_invalid / timeout / target_invalid) 是 valid e2e 結果、不 retry

跑 12 組合（建議分次跑、便於 spot regression）：

```bash
# Review × 6 scenarios
bash tests/e2e.sh --skill review --scenario mixed
bash tests/e2e.sh --skill review --scenario binary
bash tests/e2e.sh --skill review --scenario oversize
bash tests/e2e.sh --skill review --scenario empty-repo
bash tests/e2e.sh --skill review --scenario all-empty
bash tests/e2e.sh --skill review --scenario with-profile

# Adversarial-review × 6 scenarios
bash tests/e2e.sh --skill adversarial-review --scenario mixed
bash tests/e2e.sh --skill adversarial-review --scenario binary
bash tests/e2e.sh --skill adversarial-review --scenario oversize
bash tests/e2e.sh --skill adversarial-review --scenario empty-repo
bash tests/e2e.sh --skill adversarial-review --scenario all-empty
bash tests/e2e.sh --skill adversarial-review --scenario with-profile
```

完整 matrix 通過後算 release gate clear。12/12 PASS 是目標；因偶發 rate limit／Codex quota
失敗的個別案例必須 retry 至通過，不能把 failure 當成 acceptable PASS。

## Manual Layer 3 — UI Flow Checklist

跑完 `tests/run.sh` 與 automated `tests/e2e.sh` 全綠後，再走以下 manual checklist（covering plugin install UI flow）。每項打勾代表你親自在 fresh Claude Code session 觀察到該行為。

## Preconditions

- [ ] **Layer 1+2 已綠**：跑完 `bash tests/run.sh` 顯示 0 fail / exit 0
- [ ] **Layer 3 automated 已綠**：跑完 `bash tests/e2e.sh` 12 組合全 PASS；個別
  rate-limit failure 已 retry 至通過

## A. Plugin install path（正規 marketplace 路徑）

- [ ] **Marketplace add**：在新 Claude Code session 跑 `/plugin marketplace add psychquant/codex-pro`（GitHub source；或 `/plugin marketplace add <local repo path>` 走 local dev）。預期：marketplace `codex-pro` 出現在 `/plugin` 命令清單。

- [ ] **Plugin install**：跑 `/plugin install codex-pro@codex-pro`。預期：plugin `codex-pro` 顯示為 installed、`/help` 列出 `/codex-pro:codex-setup` 與 `/codex-pro:codex-batch` 兩個 skill。

## B. Setup skill（已落地）

- [ ] **Setup ready 全綠**：在 OAuth token、codex-call、plugin manifest 三者就緒環境下跑 `/codex-pro:codex-setup`。預期：輸出 3 列 markdown 表格、3 個 Status 全 ✓、摘要含字串 `ready`。

- [ ] **Setup 缺 OAuth 報 codex login**：在 disposable test account／VM 的未登入狀態跑
  `/codex-pro:codex-setup`。預期：OAuth 列 Status ✗、Remediation 文字含 `codex login`；
  摘要含 `need attention`。不要改名日常使用者的真實 auth file。

- [ ] **Setup 為 read-only**：B 段的兩次 setup 前後，比對 disposable account 的
  `~/.codex/`。預期：目錄內容沒有 setup 引入的 mutation。

## C. Batch skill（已落地、含 Design constraint #1 exception）

- [ ] **Batch 觸發**：跑 `/codex-pro:codex-batch`（不帶參數）。預期：skill 開始向你詢問 5 個 required parameters — Reference file、Chunks、Prompt template、Output directory、optional model / reasoning effort 等。

- [ ] **Batch 跑完不污染 codex-pro**：用一個 fake reference + 短 chunk list 跑一輪 batch（output dir 指向 `/tmp/` 內某 fake dir）。預期：plugin 內檔案無變動、output 寫到 `/tmp/` 你指定的位置。**測完清理 /tmp/ 內產物**。

## D. Dev-test path（不裝 marketplace、純 --plugin-dir）

- [ ] **Sub-plugin dev-test**：開另一個 Claude Code session 用 `claude --plugin-dir <repo>/plugins/codex-pro`（從你 clone 的 codex-pro 目錄）。預期：載入後 `/codex-pro:codex-setup` 與 `/codex-pro:codex-batch` 都可觸發，行為與 marketplace install 路徑一致。

## E. Visual cross-validation：SAM 2.1 真實影格 smoke（手動）

`tests/visual-xval.sh` 只用合成遮罩測幾何，不下載模型。發布前用真實影格跑一次
`sam_track.py track`，確認遮罩、尖端與距離真的對得上：

- [ ] `~/.codex-pro/sam-env/` 已由 `sam_env.sh install --yes` 建好（約 1 GB，首次下載模型權重 898 MB，只取 model.safetensors）
- [ ] 準備一段**同一支影片、依時間排序**的 8–12 張影格（例如腹腔鏡訓練片每 5 秒一格），以及兩份
      claim JSON（可以兩份相同，再改一格的關係判斷製造一個分歧，讓錨點切成兩段）
- [ ] `compare_claims.py compare` → `sam_track.py anchors --class INST --order <影格順序.json>` → 用 sam-env 的
      python（加 `-I`、`HF_HOME=~/.codex-pro/sam-env/hf`）跑 `sam_track.py track`，`sam_status` 為 `ok`
- [ ] `track.json` 有 `class` 與 `revision`，每個物件有 `present` 與 `object_score`；畫面內的物件
      `present` 為 true（模型只用本機檔案載入，沒有重新下載）
- [ ] 把 `tip_pct` 畫回影格親眼看：尖端落在器械夾口，不是桿身入口、也不是沿縫線跑到另一支器械
- [ ] 尖端與標註位置的誤差：2026-10-07 的基準是 23/24 個尖端 ≤ 1.2%（寬度百分比），1 個貼著視野
      邊緣的被正確回報為 null。明顯變差就先查 `THREAD_RADIUS_AT_960` 與 `view_region`

紀錄：2026-10-07 第二輪（verify 修正後）在同一組 12 張影格重跑，revision `665f8e2` 以本機檔案載入，
`class: INST`，12 格尖端距離與第一輪完全相同（最大位移 0），兩支器械的 object score 全部為正
（5.87–17.65），無塌陷格。這次用的是既有環境加上全域 HF 快取，不是 `sam_env.sh` 新裝的環境。

出貨路徑紀錄：2026-10-07 第三輪修正（task 7.6）。以暫時的 HOME 讓 `~/.codex-pro/sam-env` 指向既有環境、
`sam-env/hf/hub` 指向既有模型快取（沒有下載），從 `xval.py` 跑完 `init --sequence` → 封存 → `compare` → `sam` →
`adjudicate` → `result`：`sam_env.sh --check` 通過（鎖定 revision、只用本機檔案、`-I`），`sam_status: ok`，12 格追蹤、
0 格塌陷，錨點 f01、f07；f06 的關係分歧（Claude false、Codex true）由 SAM 量到兩尖端相距 16.09% 裁決為
`resolved_claude`。這組影格是真實的訓練影片影格，所以**沒有執行 `ask`**：Codex 的答案取自先前的 smoke，
請求紀錄是手動補上的，沒有任何影格送出本機。

這一段踩過的坑（都已修，留著是為了重跑時知道要看什麼）：transformers 會清空傳入的 `obj_ids`
list（每格都沒有物件）；黑色桿身被當成視野外（尖端跑到入口）；遮罩黏著縫線（尖端沿線跑走）。

## F. Visual cross-validation：真實後端端到端（手動）

`tests/visual-xval.sh` 的請求全部送給 stub。發布前用真實的 `codex-call` 跑一次完整流程，確認真實模型
照 schema 回覆、中性檔名與送出順序一致、結果檔完整：

- [x] Claude 端 PATH 上的 `codex-call --help` 列出 `--image`（parallel-ai-agents 2.24.0 以上；
      `claude plugin marketplace update` 後 `claude plugin update parallel-ai-agents@<marketplace>`）
- [x] 準備 3 張**合成圖**（不含任何真實影格），寫好詞彙表；照 SKILL.md 從 Step 1 跑到 Step 9，
      至少製造一個分歧，讓放大輪實際送出
- [x] 第一輪：`requests.json` 有請求時間與回覆雜湊；`codex.json` 通過 schema（每個計數物件一個關鍵點）
- [x] 放大輪：Claude 端由 subagent 依 `zoom_prompt.md` 作答；送給 Codex 的 prompt 與該檔逐字相同
- [x] 結果檔：frontmatter 完整、`seal_broken: false`、封存早於請求；把結果檔路徑與重點記在下面

紀錄：2026-10-07，codex-pro `512b306`，parallel-ai-agents 2.24.0（`codex-call` sha256 `50ab7eb…`，與 vendor 副本相同），
profile `gpt-6.1-sol`／`medium`（global）。

- 輸入：3 張 640×400 合成圖（紅點、藍方塊），正確答案由產生程式決定。Claude 的答案在 f03 **刻意植入一個錯誤**
  （3 個紅點只寫 2 個），用來確保放大輪實際送出。
- 第一輪 7.7 秒，回覆一次通過 schema（每個計數物件一個關鍵點）。比對：一致率 0.667，唯一分歧是 f03 的 DOT 數量
  （Claude 2、Codex 3），正是植入的錯誤；f01、f02 的數量、位置與 `dots_close` 全部一致。
- 放大輪：subagent 只依 `zoom_prompt.md` 與裁切圖作答，答 3；封存後送 Codex（4.3 秒），送出的 prompt 與題目檔逐字
  相同，Codex 也答 3。裁決 `resolved_codex`，證據為放大輪。
- 結果檔：frontmatter 完整，`seal_broken: false`；封存 10:21:18 早於請求 10:21:27；`profile_source: global`；
  送出的 prompt 只有中性檔名，影格複本不含 metadata 區塊。`sam_status: not_applicable`（非影片序列）。
- 與 SKILL 的差異：這個 session 的 PATH 在更新 plugin 之前就設定好了，`command -v codex-call` 仍指向 2.23.0，
  所以 `runtime.txt` 直接寫 2.24.0 的路徑（新 session 的 `command -v` 會解析到的位置）。第二次與第三次沿用同一做法。

第二次紀錄：2026-10-07，codex-pro `dcaf036`（第二輪 verify 的修正之後），同一個 runtime 與 profile，`--first-side claude-opus-5-5`。

- 輸入：3 張合成圖。詞彙表只有 DOT 有關鍵點（圓心），SQUARE 與一條細長的 BAR 只比數量。f03 **植入兩個錯誤**：
  3 個紅點只寫 2 個、2 個方塊只寫 1 個。
- 第一輪 12.2 秒，回覆通過 schema。比對：一致率 0.667，分歧只有 f03 的兩個植入錯誤；f01 的 BAR 只比數量，
  沒有因為兩邊點在不同位置而產生假分歧（第二輪 R2 的情境）。
- 放大輪：DOT 的數量題由 subagent 作答、結束後立刻封存；Codex 拿到逐字相同的題目檔。兩邊都數到 3，等於較高
  的一方，裁決 `resolved_codex`。SQUARE 沒有關鍵點，不出放大題，結果檔寫明原因，裁決 `unverifiable`。
- 結果檔：`first_side_model: claude-opus-5-5`；兩輪的請求都列出時間與回覆雜湊，回覆檔都仍相符，封存都早於請求。

第三次紀錄：2026-10-07，codex-pro `6ec0255`（第三輪 verify 的修正之後），同一個 runtime 與 profile，`--first-side claude-opus-5-5`。
詞彙表 DOT 有關鍵點、上限 2，SQUARE 只比數量；關係 `dots_close` 為 `distance_pct < 10`。

- 植入兩個錯誤：f01 把同一個紅點標兩次（數成 3，依自己的標記關係為 true）；f02 兩個紅點相距約 6%，卻答 false。
- 第一輪 9.0 秒。分歧正好三筆：f01 數量、f01 關係、f02 關係。放大輪題目檔的關係題帶完整定義與關鍵點定義，
  每行寫實際倍率（shown at 2x）；subagent 結束後立刻封存，Codex 拿到逐字相同的題目檔（10.4 秒）。
- f01 數量（T5）：放大輪兩邊都數到 2，上限 2 → Claude 被排除、2 被看見 → `resolved_codex`。第三輪之前這一型
  永遠是 unverifiable。
- f02 關係（T4、T7）：雙方數量一致，裁切區含全部標記點，兩邊都答 true → `resolved_codex`。
- f01 關係（T4）：雙方數量不一致，放大輪答 false 證不出整格的答案 → `unverifiable`。這次發現結果檔只寫
  「no third evidence」，像是放大輪沒跑；已改為列出放大輪的答案與不能用的原因。
- 結果檔：沒有 error；Limitations 點名 SQUARE 只比數量、數量判給一方的意義、封存前未讀靠流程。

第四次紀錄：2026-10-07，codex-pro `72c97ba`（第四輪 verify 的修正之後），同一個 runtime 與 profile，`--first-side claude-opus-5-5`。
詞彙表同第三次；f03 改用 WebP 輸入，驗證複本重新編碼成 PNG。

- 植入三個錯誤：f01 把同一個紅點標兩次；f02 兩點相距約 6% 卻答「不近」；f03 兩點相距很遠卻答「近」。
- 第一輪 9.9 秒，分歧四筆（f01 數量與關係、f02 關係、f03 關係），全是植入的錯誤。放大輪 subagent 立刻封存，
  Codex 拿到逐字相同的題目檔（8.4 秒）。
- f01 數量（T5）：放大輪數到 2、上限 2 → `resolved_codex`。
- f02 關係（U2 證得出來的方向）：兩邊都答 true → `resolved_codex`。
- f01、f03 關係（U2）：放大輪答 false，不採用 → `unverifiable`，結果檔寫明「只有看到一對靠近的點才證得出整格的答案」。
  f03 的真值其實是 Codex 對；「很遠」這一側在沒有 SAM 時證不出來，是使用者選擇的取捨。
- 影格複本：三張都由 sips 重新編碼（WebP → PNG），不含 EXIF 或文字區塊；結果檔沒有 error。

第五次紀錄：2026-10-07，codex-pro `1b9ac98`（第五輪 verify 的修正之後），同一個 runtime 與 profile。
f01 是 3000×1875 的大圖，驗證原解析度複本；送出前的登入檢查照常通過（V2）。

- init：f01 的第一輪複本為 2048×1280，另有原解析度的 `hires/f01.png`；f02 為 640×400，沒有原解析度複本。
- 植入兩個錯誤：f01 把同一個紅點標兩次；f02 兩點相距約 6% 卻答「不近」。第一輪 9.7 秒，分歧三筆，全是植入的錯誤。
- f01 的裁切框為 2400×1031 px，從 3000 px 寬的原解析度複本裁出，再縮到長邊 2048 以內（0.85x）；放大輪兩邊都數到 2，
  上限 2 → `resolved_codex`（T5，V7）。
- f02 關係：放大輪兩邊答 true → `resolved_codex`；f01 關係：放大輪答 false，不採用 → `unverifiable`。
- 第一輪複本、原解析度複本與三張裁切圖都不含 EXIF 或文字區塊；結果檔沒有 error。

第六次紀錄：2026-10-08，codex-pro `04c41fb`（第六輪 verify 的修正之後），同一個 runtime 與 profile。
原圖放在名稱含空白的資料夾，run 目錄照 SKILL Step 1 先建立，再做隱私確認（confirm-privacy 不再建立目錄）。

- 登入檢查讀帳號家目錄的 token 檔，照常通過；init 為 3000×1875 的 f01 寫出原解析度的 `hires/f01.png`。
- 植入與第五次相同的兩個錯誤；第一輪 6.1 秒，分歧三筆，全是植入的錯誤。comparison_record.json 記下兩邊答案檔的雜湊。
- 放大輪 5.3 秒，Codex 收到的題目檔與 subagent 作答的那份逐字相同；f01 數量 → `resolved_codex`（上限 2），
  f02 關係 → `resolved_codex`，f01 關係的 false 不採用 → `unverifiable`。
- 結果檔沒有出現原圖資料夾的名稱，沒有「changed after」的警示；複本與裁切圖都不含 EXIF 或文字區塊。

## Post-test cleanup checklist

- [ ] B 段使用的 disposable account／VM 沒有污染日常 Codex home
- [ ] C 段的 `/tmp/` 內 fake output 已清乾淨
- [ ] `bash tests/run.sh` 再跑一次仍綠（確認 e2e 過程沒污染 repo）

---

**何時需要跑這份 checklist？**

- 重大 namespace change 之後（例如又一輪 consolidate-naming-like 改動）
- 新增 skill 之後（review、rescue、jobs-* 等未來 capability）
- Plugin 重大重組（marketplace.json schema 變化等）
- 對外發布前（推 GitHub / 廣告 marketplace）

日常 dev iterate 不需要每次跑這份 — Layer 1+2 自動化已 cover artifact 與行為正確性，e2e 是「最後一公里」UI 確認。
