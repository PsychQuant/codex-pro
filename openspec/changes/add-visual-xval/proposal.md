## Why

從圖片或影格下判斷時（例如替訓練影片評分），單一模型看錯了自己不會發現；一次實測中，Claude 有三處判讀被器械追蹤與第二個模型推翻。使用者要 codex-pro 提供「兩個 AI 用視覺交叉驗證」的 skill，並明說評分的準度最重要（PsychQuant/codex-pro#23）。目前 `codex-call` 只收文字，無法把圖片交給 Codex。

## What Changes

- 新增 producer skill `/codex-pro:codex-visual-xval`：
  - 封閉物體清單與物理約束
  - 把判讀拆成逐格可核對的主張（JSON）
  - Claude 先寫答案並封存（寫檔，記 SHA-256 與時間）
  - Codex 透過 `codex-call --image` 盲答
  - 確定性腳本比對
  - 分歧處送裁切放大圖做第二輪
  - 以內建 SAM 2.1 追蹤做第三種證據裁決分歧
  - 結果寫 `.codex-pro/visual-xval-<timestamp>.md`
- 內建 SAM 2.1 追蹤：
  - 環境建在 `~/.codex-pro/sam-env/`，首次下載模型前先取得使用者同意。
  - 取兩邊判讀一致的影格當錨點，多次重新錨定。
  - 兩個物件遮罩的 IoU 超過 0.5 時，該格標為無效，不拿來裁決。
- 呼叫前檢查 runtime 是否支援 `--image`；不支援時以 `runtime_unsupported` 寫結果檔並停止，不送出請求。
- 重新 vendor `codex-call`：三份 snapshot、`codex-pro-call` 的預期 SHA-256、兩份 provenance JSON、`THIRD_PARTY_NOTICES.md` 一起更新到上游 PsychQuant/parallel-ai-agents#87 發版後的不可變 commit。上游在舊鎖版之後加入的背景執行功能（`--detach/--poll/--abort`）會一併帶入，但沒有任何 skill 使用。
- provenance 的指紋數值改以 `references/codex-call-provenance.json` 為準，spec 不再逐字寫死 commit、blob、大小與 SHA-256。
- 新 skill 加入 `scripts/codex-skills.manifest`、`scripts/codex-bundle-resources.manifest`，並重新產生 `.codex/skills` 鏡像。
- `/codex-pro:codex-status` 的 `--skill` 與 `/codex-pro:codex-result` 的 `--latest` 加入 `visual-xval`；status 的輸出表把它的結果顯示為一致率。
- 版本 0.8.0 → 0.9.0；更新 `CLAUDE.md` 指令表與 skill 類別表、README、CHANGELOG。

## Capabilities

### New Capabilities

- `visual-xval`: 兩個模型對同一批圖片的獨立判讀、封存、比對、放大複查，以及以 SAM 2.1 追蹤裁決分歧的完整契約與結果檔格式

### Modified Capabilities

- `codex-native-plugin`: provenance 改以 provenance JSON 為準並換到支援圖片輸入的上游 commit；runtime 解析與 platform-scoped producer 兩條 requirement 涵蓋新的 producer skill。
- `tests`: runtime provenance 與 resolver 矩陣測試的 producer 契約測試要涵蓋新 skill，並以 provenance JSON 比對指紋。
- `status`: `--skill` 可選 `visual-xval`；輸出表把 visual-xval 的結果顯示為一致率。
- `result`: `--latest visual-xval` 可選取最近一次視覺交叉驗證結果。

## Impact

- 前置依賴：PsychQuant/parallel-ai-agents#87（`codex-call --image`，並修正把不認得的 flag 當成 prompt 的問題）必須先發版，取得不可變 commit。
- 新增檔案：
  - plugins/codex-pro/skills/codex-visual-xval/SKILL.md
  - plugins/codex-pro/skills/codex-visual-xval/scripts/ 底下的比對腳本、SAM 追蹤腳本與環境準備腳本
  - openspec/specs/visual-xval/spec.md
- 修改檔案：
  - bin/codex-call、.codex/bin/codex-call、plugins/codex-pro/runtime/codex-call
  - bin/codex-pro-call 及其產生的副本
  - references/codex-call-provenance.json、plugins/codex-pro/references/codex-call-provenance.json
  - THIRD_PARTY_NOTICES.md、plugins/codex-pro/THIRD_PARTY_NOTICES.md
  - scripts/codex-skills.manifest、scripts/codex-bundle-resources.manifest、.codex/skills/
  - plugins/codex-pro/skills/codex-status/SKILL.md、plugins/codex-pro/skills/codex-result/SKILL.md（加入新的 producer 前綴）
  - tests/ 底下的 static、behavioral、runtime provenance 測試
  - CLAUDE.md、README.md、CHANGELOG.md、plugins/codex-pro/.claude-plugin/plugin.json
- 新的外部依賴：SAM 2.1 需要 Python、uv、torch 與 transformers 5.19 以上，模型權重 856 MB（2026-10-07 實測），連同 torch 與 transformers 總下載約 1 GB（估計值，首次在乾淨環境安裝時實測確認）。依賴只在使用者同意後安裝到 `~/.codex-pro/sam-env/`，不影響其他 skill。
- 隱私：圖片會送到 OpenAI；skill 在送出前提醒使用者遮蓋不該外送的內容。
