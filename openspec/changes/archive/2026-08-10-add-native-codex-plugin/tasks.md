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

## 5. Verification findings 的 RED 契約

- [x] [P] 5.1 擴充 **Full bundle parity test** 與 **Backward-compatible generator interfaces** 的 RED cases：在 `tests/codex-skills-parity.sh` 釘住 `--output` expected child／`SKILL.md` symlink 不得寫出 validated root、expected owned skill directory 的額外檔案必須被 recursive parity 找到，以及 default mode 任一目的地 validation 失敗時兩份 bundle 均不得改變；涵蓋 **D1. 完整雙 bundle 生成** 與 **Generator interface and bundle shape**。
- [x] [P] 5.2 建立 **Test dispatcher honors layer process status** 的 RED regression：新增隔離 fixture 驗證無 summary 非零與 zero-fail summary 後非零都使 `tests/run.sh` aggregate gate 失敗，涵蓋 **D5. 版本與 release gate** 與 **Acceptance criteria**。
- [x] [P] 5.3 擴充 **Pinned runtime provenance** 與 **Native plugin static contract test** 的 RED assertions：要求 Claude source plugin 根層不含 auto-PATH `bin/codex-call`／`bin/codex-pro-call`，resource manifest 能把非 PATH source 映射到 native `bin/*`，且三份 runtime fingerprint 維持一致；涵蓋 **D3. 來源釘選 runtime 與 provenance** 及 **Runtime and resolver interface**。
- [x] [P] 5.4 擴充三個 producer behavioral tests 的 RED contract：釘住 **Skill-relative runtime resolution** 的 `runtime_unavailable`／`package_corruption` mapping、resolver 不直接 `exit`、不呼叫 runtime／OAuth／network，並要求 review、adversarial-review、rescue 各自保留結構化 result file；涵蓋 **D4. Skill-relative resolver 與 fail-closed** 與 **Observable behavior**。

## 6. Verification findings 的 corrective implementation

- [x] 6.1 落實 **D1. 完整雙 bundle 生成** 的安全修正：驗證 skill manifest 名稱唯一且為安全單一 path component，`--output` child symlink／containment escape 在 mutation 前 fail-closed，default mode 先 stage＋validate 兩份 committed bundles 再套用，並讓 **Full bundle parity test** 真正遞迴列舉 generator-owned expected skill directories。
- [x] 6.2 落實 **D5. 版本與 release gate** 的 dispatcher 修正：保留 layer 真實 exit status，summary zero-fail 仍須 process exit 0 才算 pass，並把獨立 `tests/run-dispatcher.sh` 接入完整 gate以滿足 **Test dispatcher honors layer process status**。
- [x] 6.3 落實 **D3. 來源釘選 runtime 與 provenance** 的 host 相容修正：將 snapshot／wrapper source 移出 Claude plugin 根層 `bin/`，擴充 resource source→publish mapping並重生 native `bin/*`，確認 Claude 仍只從外部 PATH 解析而兩份 Codex bundles 的 runtime bytes／mode／SHA 不變。
- [x] 6.4 落實 **D4. Skill-relative resolver 與 fail-closed** 的可觀察 failure：三個 generated producer 以 `CODEX_RUNTIME_ERROR`／detail 跳過 runtime invocation並直接走 Step 5，將 native corruption 映射為 `package_corruption`、其他 availability failure 映射為 `runtime_unavailable`，且每種 failure 保留原 result shape與 no-retry 契約。

## 7. Corrective regeneration 與 release verification

- [x] 7.1 以修正後 generator 重生 `.codex/` 與 repo 根層 bundles，確認 source plugin 無 auto-PATH runtime、兩份 native inventories／skills／references／`bin/*` 完整一致，並以 targeted parity、runtime、producer 與 dispatcher tests 驗證 **Complete generated Codex bundles**、**Pinned runtime provenance**、**Skill-relative runtime resolution** 及 **Test dispatcher honors layer process status**。
- [x] 7.2 收斂 final sharp-edge findings：以 RED regression 鎖住 hard-linked `SKILL.md` 不得覆寫外部 inode、resource mapping 必須命名 expected skill 下的明確 child file且 staged regular-file set 必須精確等於 inventory、source SKILL symlink 不得越界、newline orphan cleanup 不得刪出 validated root、complete-bundle ownership 不得跟隨 SKILL symlink、Claude-only 子套件必須自帶完整 MIT license／vendored runtime notice、broken native marker與非 regular wrapper皆須 fail-closed，以及 producer result body 必須保留清理且有界的 preflight detail；修正後以 targeted parity、setup、producer 與 plugin contract tests驗證。
- [x] 7.3 收斂 final logic-review false-green：producer contract tests 必須結構化抽取 Step 4.3 的唯一 invocation、證明它位於 `CODEX_RUNTIME_ERROR` guard 內，並以移出 guard 的 in-memory mutation 證明 gate 會失敗；同時釘住 Step 5 的 sanitized／500 字元 detail 與 native no-retry 契約。
- [x] 7.4 重新執行 **Acceptance criteria** 與 **Scope boundaries**：`spectra analyze`、`spectra validate`、plugin-creator validator、完整 `tests/run.sh`、macOS offline runtime smoke、Codex CLI package smoke及 cross-model sharp-edge verify；必須 0 blocking、0 false-green、無 Claude PATH behavior regression，且不得把 #11–#14 的 follow-up scope 混入本 change。
