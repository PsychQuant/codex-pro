## 1. 測試先行（Requirement: Native plugin static contract test 的 Examples）

- [x] 1.1 （Native plugin static contract test）在 `tests/codex-plugin.sh` 加正向測試：對 repo 本身執行 `python3 tests/lib/codex_plugin_schema.py <repo-root>` 應 exit 0；測試帶標記 `spec-example: tests / pinned schema accepts the repository manifests`。驗證：檢查檔尚未存在時此測試失敗（RED），完成後 `bash tests/codex-plugin.sh` 回報 pass。
- [x] 1.2 在 `tests/codex-plugin.sh` 加負向測試：對 repo 的暫存複本逐一套用 Example「pinned schema rejects a broken manifest」表中的 12 種變更，每種都斷言結束碼（1 或 2）與輸出包含該列的欄位名；測試帶標記 `spec-example: tests / pinned schema rejects a broken manifest`。驗證：檢查檔尚未存在時全部失敗（RED），完成後全部 pass。
- [x] 1.3 在 `tests/codex-plugin.sh` 加「檢查檔不存在」測試：以不存在的路徑當 schema 檢查檔時，契約測試的 schema 步驟回報 fail 並指名該檔，輸出不含 skip；測試帶標記 `spec-example: tests / missing schema check fails the contract test`。驗證：`bash tests/codex-plugin.sh` 顯示該案例 pass。

## 2. 實作 pinned schema 檢查

- [x] 2.1 [after: 1.2] 新增 `tests/lib/codex_plugin_schema.py`：原始碼記錄上游 repo `openai/skills`、路徑 `skills/.system/plugin-creator/references/plugin-json-spec.md`、commit `e940b8a86138adf03972802b990a1dfc57fcbf09` 與 sha256 `5d7223255decc44fcb93f3aa80bb17afc1469b2d3c339d65d9473c5c0c54fcdd`；實作 plugin.json 與 marketplace.json 的欄位、型別、允許值、路徑規則，未文件化欄位視為違規；結束碼 0／1／2，每條違規印出欄位名；只用 Python 3.9 可執行的語法。驗證：任務 1.1、1.2 的測試全部 pass，且 `/usr/bin/python3 tests/lib/codex_plugin_schema.py .` exit 0。

## 3. 接上契約測試並移除舊 validator（Requirement: Native plugin static contract test）

- [x] 3.1 [after: 2.1] （Native plugin static contract test）`tests/codex-plugin.sh` 的 release gate 改呼叫 `tests/lib/codex_plugin_schema.py`，刪除對 `skills/.system/plugin-creator/scripts/validate_plugin.py` 與 `CODEX_PLUGIN_CREATOR_VALIDATOR` 的依賴；檢查檔缺少或非 0 結束時記為 fail。驗證：`grep -n validate_plugin tests/codex-plugin.sh` 無輸出，任務 1.3 的測試 pass，`bash tests/codex-plugin.sh` exit 0。

## 4. 文件

- [x] 4.1 [after: 3.1] `README.md` 的 Codex package contract 那一行改寫成 pinned schema 檢查（不再提 plugin-creator validator），`CHANGELOG.md` 加一則 Unreleased 條目說明新檢查與來源 commit；0.11.0 已知問題那一行保留。驗證：`grep -n plugin-creator README.md` 無輸出；內容審閱 CHANGELOG 的新條目。

## 5. 全套驗證

- [ ] 5.1 [after: 4.1] 全套測試與本機 CI gate 通過。驗證：`bash tests/run.sh` exit 0，`idd-ci-gate.sh run --commit HEAD` exit 0。
