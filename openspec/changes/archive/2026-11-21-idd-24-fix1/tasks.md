## 1. 規格對齊（Requirement: Native Codex plugin manifest）

- [x] 1.1 （Native Codex plugin manifest）正向測試確認 pinned schema 檢查接受 repo 的 manifest 且不印任何輸出；測試帶標記 `spec-example: codex-native-plugin / pinned schema check accepts the native manifest`。驗證：`bash tests/codex-plugin.sh` 該案例 pass。
- [x] 1.2 [after: 1.1] 修正 pinned schema 檢查的 verify 第 1 輪 findings 2–13（regex、`..` 路徑、結束碼、整合案例、案例計數、skip 比對、`python3 -I`、docstring 與授權說明、CHANGELOG），每個行為修正先加會失敗的測試。驗證：新增的負向與整合案例在修正前失敗、修正後通過，`bash tests/codex-plugin.sh` exit 0，`/usr/bin/python3 tests/lib/codex_plugin_schema.py .` exit 0。
- [x] 1.3 [after: 1.2] 全套測試與本機 CI gate 通過。驗證：`idd-ci-gate.sh run --commit HEAD` exit 0。
- [x] 1.4 （Cross-harness version consistency）requirement 不再寫死 `0.9.0`；既有的版本一致性斷言帶標記 `spec-example: codex-native-plugin / three published manifests declare one version`。驗證：`bash tests/codex-plugin.sh` 中 "all three published manifest versions are identical" pass。
