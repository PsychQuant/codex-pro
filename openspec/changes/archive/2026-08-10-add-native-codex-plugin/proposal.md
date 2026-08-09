## Why

codex-pro 已有 repo-local 的 Codex skill 鏡像，卻沒有 Codex 可安裝的 plugin manifest、marketplace 入口與獨立 runtime；使用者因此無法像 Superpowers 一樣安裝、更新並直接執行完整功能。現行鏡像生成也只驗證 9 個 SKILL.md，漏掉 shared references 與 batch template，必須在新增原生分發層時一併建立完整 bundle 契約。

初版實作完成後的交叉模型驗證另確認四個 release blocker：skill-only 相容介面會跟隨 expected child symlink 寫出目的地、test dispatcher 會吞掉 layer exit status、Claude plugin 根層 `bin/codex-call` 會改變原有 PATH resolution，以及 native producer runtime preflight 會在寫結構化 result 前直接離開。相同修正輪次也必須補上 owned skill directory 的真正遞迴 parity，並確保預設雙 bundle 在任何一份套用前都完成兩份狀態驗證。

最終 sharp-edge audit 再把 generator 的 source／resource／ownership containment、hard-link atomic replacement、newline-safe orphan framing、broken native marker fail-closed、producer preflight detail，以及 Claude 子套件的 MIT notice 納入同一個 release contract；這些都直接影響 #10 新增的分發與刪除路徑，不能留待後續 issue。

## What Changes

- 新增 Codex 原生 plugin manifest 與 repo marketplace，使 Codex App／CLI 可由本 repo 的 marketplace 安裝根層 plugin payload。
- 將現有單向 generator 提升為完整 bundle generator：由 plugins/codex-pro 單一來源同時產出 .codex 與 repo 根層的 skills、references、skill-local resources 及 runtime。
- 內含來源 commit、Git blob、SHA-256 與 MIT provenance 釘選的 codex-call snapshot，並以薄 wrapper 驗證平台、Swift 與內容雜湊後才執行。
- Codex 生成版的 setup 與三個 producer skills 從 active SKILL.md 的絕對位置解析 bundled runtime；native package 損壞時 fail-closed，不掃描 Codex cache，也不依賴未公開的 plugin-root 環境變數。
- 將 pinned runtime 與 wrapper 的手改來源移出 Claude plugin 自動加入 PATH 的根層 `bin/`，再由 resource mapping 只把它們發佈到兩份 Codex bundles 的 `bin/`；Claude Code 仍只解析外部 PATH runtime。
- 補強 generator 與 release runner：skill-only 子路徑 symlink／不安全名稱 fail-closed、預設雙 bundle 先完整 stage＋validate 再套用、owned skill directory 遞迴無額外檔案，且任何 layer 非零都使 aggregate gate 失敗。
- 對 source SKILL、resource mapping、staged inventory、ownership marker、hard link 與 orphan cleanup 建立 fail-closed containment；Claude-only 子套件另帶完整 MIT license 與第三方聲明。
- 三個 native producer 將 runtime preflight 失敗映射為 `runtime_unavailable` 或 `package_corruption`，跳過 OAuth／網路與 runtime invocation，但仍產出各 skill 既有形狀的結構化 result file。
- 新增 manifest、marketplace、版本同步、bundle parity、相對連結、runtime provenance、resolver matrix 與安裝 smoke gate；版本同步升為 0.8.0。
- 更新 README、AGENTS.md、CHANGELOG 與 e2e checklist，分別說明 Codex App、Codex CLI、本機開發與官方 directory 提交流程，以及 runtime 的 macOS／Swift／OAuth 限制。

## Capabilities

### New Capabilities

- `codex-native-plugin`: 定義可安裝的 Codex 原生 plugin、完整 bundle、repo marketplace、來源釘選 runtime 與安裝／更新契約。

### Modified Capabilities

- `setup`: Codex 生成版 setup 改為驗證 bundled runtime、macOS 與 Swift readiness，Claude Code 版維持既有 PATH 與 manifest 檢查。
- `tests`: 自動化驗證擴充至原生 manifest、marketplace、兩份完整 Codex bundles、runtime provenance／resolver 與三份 manifest 版本一致性。

## Impact

- Affected specs: codex-native-plugin, setup, tests
- Affected code:
  - New: `.codex-plugin/plugin.json`, `.agents/plugins/marketplace.json`, `plugins/codex-pro/runtime/codex-call`, `plugins/codex-pro/runtime/codex-pro-call`, `plugins/codex-pro/references/codex-call-provenance.json`, `plugins/codex-pro/LICENSE`, `plugins/codex-pro/THIRD_PARTY_NOTICES.md`, `scripts/codex-bundle-resources.manifest`, `tests/codex-plugin.sh`, `tests/run-dispatcher.sh`, `THIRD_PARTY_NOTICES.md`, `skills/`, `references/`, `bin/`, `.codex/references/`, `.codex/bin/`
  - Modified: `scripts/generate-codex-skills.sh`, `tests/codex-skills-parity.sh`, `tests/run.sh`, `tests/setup.sh`, producer behavioral tests, `plugins/codex-pro/references/profile-contract.md`, `plugins/codex-pro/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `.codex/skills/`, `README.md`, `AGENTS.md`, `CHANGELOG.md`, `tests/e2e-checklist.md`
  - Removed: `plugins/codex-pro/bin/codex-call`, `plugins/codex-pro/bin/codex-pro-call`（改由非自動 PATH 的 source runtime directory 維護）
- External dependencies: pinned snapshot from PsychQuant/parallel-ai-agents; macOS Xcode Command Line Tools Swift runtime; Codex App／CLI plugin marketplace ingestion.
