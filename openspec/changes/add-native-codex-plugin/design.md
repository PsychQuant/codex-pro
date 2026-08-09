## Context

codex-pro 目前以 `plugins/codex-pro/` 作為 Claude Code plugin 的可手改來源，`scripts/generate-codex-skills.sh` 只把 9 個 SKILL.md 轉為 `.codex/skills/`。這個模型沒有 Codex plugin manifest、marketplace、runtime，也沒有複製 shared references 與 `codex-batch` 的 skill-local template；現行 parity 測試因此能在產物有 7 個失效相對連結時仍回報 105/105。

OpenAI 的現行 plugin 契約要求 `.codex-plugin/plugin.json`，skills-only plugin 以 `skills: "./skills/"` 指向根層技能目錄；repo marketplace 使用 `.agents/plugins/marketplace.json`。官方只為 hook command 承諾 `PLUGIN_ROOT`，一般 skill shell 沒有 plugin-root 或自動加入 `bin/` 到 PATH 的契約，因此 runtime 必須從 active SKILL.md 的已知位置推導。

上游 runtime 是 `PsychQuant/parallel-ai-agents` commit `6fc6883ef1d655f5f782a97accc0a5adacc76226` 的 `plugins/parallel-ai-agents/bin/codex-call`：Git blob `c2418f5c0a0a3d092859d6252d2910c460dee981`、25,329 bytes、mode 100755、SHA-256 `fa80364b2159f3df4f2d9a27c885a7b50e510bf52933abaa79564945bedb6af0`、MIT。它是 macOS-only Swift script，會讀取並可能刷新 `~/.codex/auth.json`，且使用未承諾穩定的 ChatGPT backend surface。

## Goals / Non-Goals

**Goals:**

- 讓本 repo 同時是可安裝的 Codex 原生 plugin payload 與可加入的 repo marketplace。
- 維持 `plugins/codex-pro/` 為唯一可手改來源，機械產出兩個結構相同的完整 Codex bundles。
- 讓 setup、review、adversarial-review 與 rescue 在 Codex plugin 安裝後不依賴 Claude plugin PATH 即可定位 pinned runtime。
- 用 TDD 與 release gate 驗證 manifest、marketplace、resources、runtime provenance、resolver、版本同步與無漂移。
- 保持 Claude Code plugin 的 invocation、PATH runtime resolution 與既有行為相容。

**Non-Goals:**

- 不把 `codex-call` 宣告為 stable public API，也不自動追蹤上游 main。
- 不移植 Swift runtime 到 Linux／Windows；非 macOS producer 明確 fail-fast，consumer skills 仍可使用。
- 不修正上游 #28 的 SSE／UTF-8 已知缺陷，不改寫 producer 的 single-oracle 與結果檔契約。
- 不改寫 `codex-batch` 的現有平台假設，也不把它改成使用 bundled `codex-call`。
- 不在本次提交官方 universal Plugins Directory；只準備可驗證 payload、repo marketplace 與提交說明。
- 不借用 Superpowers 視覺資產；本版採無自訂圖示的最小有效 metadata。

## Decisions

### D1. 完整雙 bundle 生成

`plugins/codex-pro/` 保持唯一來源。generator 的預設執行同時更新 `.codex/` 與 repo 根層兩個 bundle；新增 `--bundle-root <path>` 產生單一完整 bundle供測試，既有 `--output <skills-dir>` 保留為向後相容的 skill-only harness。

每個完整 bundle 包含 `skills/`、`references/`、`bin/` 與 `.codex-bundle-files` ownership inventory。SKILL.md 繼續套用 namespace／setup／runtime 轉換；skill-local resources、shared references 與 bin payload 逐位元複製。`scripts/codex-bundle-resources.manifest` 明列所有非 SKILL.md 資源，避免來源與測試同時漏檔仍全綠。

每個 generated skill 目錄以 SKILL.md marker 判定 ownership，重生時以完整 staging directory 取代，從而清掉陳舊 nested resources。shared resources 只依上一版 `.codex-bundle-files` 與新 manifest 做 bounded cleanup；generator 不掃描或刪除 bundle root 的其他檔案。

Rejected alternative：手動維護根層 `skills/`，會建立第三份可漂移來源；只複製 SKILL.md，會保留目前 broken links 與 batch template 缺口。

### D2. 原生 manifest 與 self-hosted repo marketplace

`.codex-plugin/plugin.json` 使用 strict SemVer 0.8.0、`skills: "./skills/"` 與現行 validator 要求的 author／interface 欄位；`apps`、`mcpServers`、hooks 與不存在的 asset 欄位全部省略。`.agents/plugins/marketplace.json` 的唯一 entry 名稱為 `codex-pro`，source 為指向 marketplace root 的 local path `./`，policy 為 `AVAILABLE`／`ON_INSTALL`，category 為 `Developer Tools`。

因此 `codex plugin marketplace add PsychQuant/codex-pro --ref main` 取得 repo marketplace 後，可由相同 snapshot 安裝 repo 根層 plugin，無需另維護 `plugins/codex-pro` staging copy。官方 directory 提交文件另列，不宣稱本次已上架。

Rejected alternative：把根層 manifest 指向 `.codex/skills/`，會偏離官方／Superpowers 根層 `skills/` 版型；在 repo 內再複製完整 plugin 子目錄，會新增第四份 payload 與版本漂移面。

### D3. 來源釘選 runtime 與 provenance

將上游 `codex-call` byte-for-byte snapshot 存於 `plugins/codex-pro/bin/codex-call`，不修改檔頭，讓 SHA-256 可直接對上游。`plugins/codex-pro/references/codex-call-provenance.json` 記錄 repository、path、commit、blob、raw URL、bytes、mode、sha256、license 與已知上游 issues；`THIRD_PARTY_NOTICES.md` 說明來源與 MIT 授權。

`plugins/codex-pro/bin/codex-pro-call` 是本 repo 維護的薄 wrapper。它從 `$0` 解析自身目錄，對正常執行與 `--check` 都驗證 Darwin、`swift --version`、runtime executable mode 與 SHA-256；通過後以原參數 exec snapshot。`--check` 不讀 auth、不連網、不執行 snapshot。任何檢查失敗皆輸出單行 machine-readable error 並以非零結束。

Rejected alternative：在每個 skill 內複製 runtime 會產生四份 25 KB snapshot；symlink 的 marketplace 封裝語意未受保證；只依賴外部 PATH 則重現原問題。

### D4. Skill-relative resolver 與 fail-closed

Codex generated setup 與三個 producer skills 先把 `SKILL_DIR` 設為 active SKILL.md 所在的絕對目錄，再令 `BUNDLE_ROOT` 為 `SKILL_DIR/../..`。若 `BUNDLE_ROOT/bin/codex-pro-call` 可執行就使用它；若 bundle inventory 或 native manifest 存在但 wrapper 缺失／不可執行，視為 package corruption 並停止，不得退回 PATH。

只有沒有 inventory、沒有 native manifest 的 legacy project mirror，才可最後使用 `command -v codex-call`，並在 setup report 或 producer error context 標示 legacy PATH fallback。resolver 不掃描 `~/.codex/plugins/cache`、不讀 `CODEX_HOME`、不假設 `PLUGIN_ROOT` 或 `CLAUDE_PLUGIN_ROOT`。

Rejected alternative：掃 cache 能在目前機器碰巧找到檔案，但 source namespace、版本目錄與 cache shape 都不是公開契約；hook-only 的 `PLUGIN_ROOT` 也不能外推到 skill shell。

### D5. 版本與 release gate

版本 0.8.0 必須同時出現在 Codex manifest、Claude plugin manifest 與 Claude marketplace entry。`tests/codex-plugin.sh` 驗證原生 manifest、self-hosted marketplace、版本一致、runtime/provenance、wrapper matrix 與 package resources；升級後的 `tests/codex-skills-parity.sh` 對兩個 committed bundles 與暫存重生 bundle 做 recursive parity、相對連結解析、冪等性與 ownership safety。

release gate 另執行內建 `plugin-creator` validator、完整 `tests/run.sh`、macOS `swift --version`、wrapper `--check`，並以固定 JSON payload 呼叫 snapshot 的 `--selftest-error-extract` 離線測試 hook；該 hook 必須帶一個 JSON 引數，不能以空引數呼叫。Codex CLI／App 的真正安裝、啟用與新 task invocation 放在 e2e checklist，且 producer smoke 必須在未注入 Claude plugin PATH 的情境產出 `.codex-pro/review-*.md`。

### D6. 最小 marketplace metadata

本版提供有效的 display name、說明、developer、category、capabilities、website 與三個 starter prompts，不放 composer icon、logo、screenshots 或 brand color。這符合 asset optional 的現行契約，避免臨時建立未經設計與審核的品牌資產；未來若新增資產，manifest test 必須驗證路徑留在 archive 內且檔案存在。

## Implementation Contract

### Observable behavior

- Codex CLI 可加入本 repo marketplace、看到 `codex-pro` entry 並安裝根層 plugin；新 task 可探索 9 個 `$codex-*` skills。
- `.codex/` 與 repo 根層 bundles 的 9 個 skill directories、nested resources、shared references 與 runtime bytes 相同；兩者只因 bundle root 不同而有不同絕對位置。
- `$codex-setup` 回報 OAuth 與 bundled runtime readiness。非 macOS 或缺 Swift 時，producer readiness 明確為不可用，但 consumer skills 不被描述為不可用。
- `$codex-review`、`$codex-adversarial-review` 與 `$codex-rescue` 以 bundle wrapper 前景同步呼叫 snapshot；結果檔與失敗分類維持既有契約。
- Claude Code 版仍以 PATH 找 `codex-call` 並驗 `.claude-plugin/plugin.json`，不改用 bundled runtime。

### Generator interface and bundle shape

- `scripts/generate-codex-skills.sh` 無參數：更新 `.codex/` 與 repo 根層兩個 committed bundles。
- `scripts/generate-codex-skills.sh --bundle-root <path>`：更新一個含 `skills/`、`references/`、`bin/`、`.codex-bundle-files` 的完整 bundle。
- `scripts/generate-codex-skills.sh --output <skills-dir>`：保留既有 skill-only 測試介面；不得被 release parity 當成完整 bundle。
- 空路徑、`/`、使用者 home 與未解析的危險 destination 必須在任何 cleanup 前拒絕。
- `.codex-bundle-files` 為換行分隔、repo-relative-to-bundle 的 generated path inventory；只列 generator 擁有的檔案，排序固定且重生冪等。

### Manifest and marketplace data

- `.codex-plugin/plugin.json` 的 `name` 為 `codex-pro`、`version` 為 `0.8.0`、`skills` 為 `./skills/`，並通過 plugin-creator validator。
- `.agents/plugins/marketplace.json` 的 top-level `name` 與 entry `name` 為 `codex-pro`；entry source 為 `{ "source": "local", "path": "./" }`，policy 包含 installation `AVAILABLE` 與 authentication `ON_INSTALL`。
- 三份發布版本完全一致；任何不一致使 `tests/run.sh` 失敗。

### Runtime and resolver interface

- provenance JSON 的 commit、blob、bytes、mode、sha256 必須與 vendored runtime 一致。
- `bin/codex-pro-call --check` 成功時輸出 `ok runtime=<absolute-path> sha256=<hash> swift=<version>` 並結束 0；錯誤輸出以 `error=<class>` 開頭，class 至少涵蓋 `unsupported_platform`、`swift_missing`、`runtime_missing`、`runtime_not_executable`、`hash_mismatch`。
- 其他參數在檢查成功後逐字傳給 snapshot；wrapper 不 retry、不改寫 auth、不吞掉 snapshot exit status。
- generated skills 使用 active skill path 設定 `SKILL_DIR`，不得從 cwd 推測。含 manifest／inventory 的 bundle 發現 runtime 損壞時必須 fail-closed；只有明確認定的 legacy mirror可用 PATH fallback。

### Acceptance criteria

- 新測試先在缺 manifest／resources／runtime 時呈現 RED，再由實作轉為 GREEN。
- `python3 <plugin-creator-skill>/scripts/validate_plugin.py <repo-root>`、`bash tests/run.sh`、`bash tests/codex-plugin.sh`、`bash tests/codex-skills-parity.sh` 全部通過。
- 在 macOS 上，`bin/codex-pro-call --check` 與 `bin/codex-call --selftest-error-extract '{"error":{"message":"offline self-test"}}'` 通過，後者輸出 `offline self-test`；測試不得把「全部 skip」算成功。
- e2e checklist 記錄 Codex CLI marketplace add／plugin add、新 task 的 setup、consumer、producer smoke，以及 Codex App 視覺安裝檢查。

### Scope boundaries

In scope：root native plugin、self-hosted repo marketplace、兩個 generated bundles、pinned macOS runtime、resolver、tests、docs、version 0.8.0。Out of scope：官方 directory 審核完成、Linux／Windows producer、上游 runtime 修正、batch portable rewrite、品牌圖示與任何新的 MCP／hook。

## Risks / Trade-offs

- [Private backend contract 可能改變] → commit/hash pin 隔離非預期更新，文件明載 experimental surface，更新必須人工審閱。
- [上游 #28 的 SSE／UTF-8 缺陷被一併 vendoring] → provenance 與 known limitations 明載，未把 snapshot 穩定性包裝成保證。
- [runtime 會接觸 OAuth 並可能刷新 auth file] → setup 的 `--check` 保持純唯讀，README 與 threat note 清楚揭露正常 producer 的 side effect。
- [macOS-only runtime 與通用 plugin 安裝面不一致] → setup 與 wrapper在執行前 fail-fast，consumer skills 仍可用，官方 listing 文案不宣稱跨平台 producer。
- [root marketplace source `./` 與 ingestion 實作漂移] → static schema test加 CLI install smoke；若 host 不接受，rollback 為 staging subdirectory marketplace，不改 plugin payload契約。
- [雙 bundle 增加 committed generated files] → source ownership inventory、fresh regeneration parity 與禁止手改說明把 drift 變成測試失敗。

## Migration Plan

1. 以 TDD 新增原生 plugin／bundle contract tests並確認 RED。
2. 加入來源 runtime、wrapper、provenance，再擴充 generator 產出兩個完整 bundles。
3. 加入 manifest、marketplace、版本同步與文件，重生所有 committed outputs。
4. 跑 static／behavioral／validator／macOS offline smoke；再執行 Codex CLI 與 App checklist。
5. 發布時以 0.8.0 tag 提交官方 directory；若 rollback，移除 marketplace listing或退回上一版本，不修改使用者既有 `.codex-pro/` result files。

## Open Questions

(none) — 官方 directory 的實際審核與資產要求屬 release 後外部步驟，不阻擋本變更。
