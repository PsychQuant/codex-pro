## 1. 契約優先的 RED 測試

- [x] [P] 1.1 建立 **Native plugin static contract test**：`tests/codex-plugin.sh` 先釘住 **Native Codex plugin manifest**、**Self-hosted repository marketplace** 與 **Cross-harness version consistency**，涵蓋 design 的 **D2. 原生 manifest 與 self-hosted repo marketplace**、**D5. 版本與 release gate**、**D6. 最小 marketplace metadata** 及 **Manifest and marketplace data**；以缺少 `.codex-plugin/plugin.json` 時測試非零作為 RED 證據。
- [x] [P] 1.2 擴充 **Full bundle parity test**：先用 `tests/codex-skills-parity.sh` 釘住 **Complete generated Codex bundles** 與 **Backward-compatible generator interfaces**，涵蓋 **D1. 完整雙 bundle 生成** 及 **Generator interface and bundle shape**；以目前缺 shared references／batch template／root skills 時測試非零作為 RED 證據。
- [x] [P] 1.3 建立 **Runtime provenance and resolver matrix tests**：在 `tests/codex-plugin.sh`／`tests/setup.sh` 的獨立區段先釘住 **Pinned runtime provenance**、**Runtime wrapper preflight and execution**、**Skill-relative runtime resolution**、**Platform-scoped producer capability**、**Codex setup reports bundled runtime readiness**、**Codex setup distinguishes platform support from consumer availability** 與 **macOS offline runtime smoke cannot silently skip**，涵蓋 **Runtime and resolver interface**；以 runtime／wrapper 尚不存在時測試非零作為 RED 證據。

## 2. Runtime 與完整 bundle 實作

- [x] 2.1 落實 **D3. 來源釘選 runtime 與 provenance**：加入 byte-for-byte `codex-call`、provenance JSON、`THIRD_PARTY_NOTICES.md` 與 `codex-pro-call` 的平台／Swift／mode／SHA-256 preflight、`--check`、參數及 exit status passthrough；以 targeted runtime tests、`bin/codex-pro-call --check` 與帶固定 JSON 引數且輸出 `offline self-test` 的 `bin/codex-call --selftest-error-extract` 驗證 **Pinned runtime provenance** 及 **Runtime wrapper preflight and execution**。
- [x] 2.2 落實 **D1. 完整雙 bundle 生成**：擴充 generator、resource manifest、ownership inventory、bounded cleanup、`--bundle-root`，同時保留 `--output`，讓 nested resources、shared references 與 bin payload 完整生成；以 **Full bundle parity test**、危險 destination 測試、冪等性與 unrelated-file preservation 驗證 **Complete generated Codex bundles**、**Backward-compatible generator interfaces** 及 **Generator interface and bundle shape**。
- [x] 2.3 落實 **D4. Skill-relative resolver 與 fail-closed**：Codex generated setup 與三個 producer 從 active SKILL.md 設定 `SKILL_DIR`、優先 bundled wrapper、native corruption 不退回 PATH、legacy mirror 才 fallback，並在非 macOS／缺 Swift 時保留 consumer availability；以 resolver matrix 與 setup behavioral tests 驗證 **Skill-relative runtime resolution**、**Platform-scoped producer capability**、**Codex setup reports bundled runtime readiness**、**Codex setup distinguishes platform support from consumer availability** 及 **Observable behavior**。

## 3. 原生分發與文件

- [x] 3.1 落實 **D2. 原生 manifest 與 self-hosted repo marketplace**、**D5. 版本與 release gate**、**D6. 最小 marketplace metadata**：建立 native manifest／repo marketplace、同步三份 0.8.0 版本並接入 `tests/run.sh`；以 **Native plugin static contract test**、plugin-creator validator 與 Codex CLI marketplace list/install packaging smoke 驗證 **Native Codex plugin manifest**、**Self-hosted repository marketplace**、**Cross-harness version consistency** 及 **Manifest and marketplace data**。
- [x] 3.2 更新 README、AGENTS.md、CHANGELOG、profile contract 與 **Codex installation e2e checklist**，讓安裝／更新、macOS＋Swift、OAuth refresh、private backend、上游 #28／#35、consumer availability、官方 directory 外部步驟與 rollback 都可被 reviewer 重現；以文件連結檢查、checklist content assertions 與人工內容審閱驗證 **Codex installation e2e checklist** 及 **Scope boundaries**。

## 4. 重生與 release verification

- [x] 4.1 以完成後的 generator 重生 `.codex/` 與 repo 根層 bundles，確認 9 個 skills、nested resources、references、wrapper、snapshot 與 inventory 符合 **Observable behavior**；以 recursive fresh regeneration、相對連結解析與 `git diff --check` 驗證無手改漂移。
- [x] 4.2 依 **Acceptance criteria** 與 **Scope boundaries** 執行 `spectra analyze`、`spectra validate`、plugin-creator validator、`tests/codex-plugin.sh`、`tests/codex-skills-parity.sh`、完整 `tests/run.sh`、macOS offline runtime smoke 及可行的 Codex CLI 安裝 smoke；確認 0 個 blocking finding、沒有全部 skip，且改動未擴張到 Linux／Windows runtime、上游缺陷修正、batch rewrite、品牌資產或官方 directory 發布。
