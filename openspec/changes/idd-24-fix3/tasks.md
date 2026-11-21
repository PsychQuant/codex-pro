## 1. gate 計數與規則覆蓋（Requirement: Native plugin static contract test）

- [x] 1.1 （Native plugin static contract test）gate 改為 `run_schema_gate`，subshell 計數測試帶標記 `spec-example: tests / the gate's failure is counted`；移除整棵樹副本與巢狀執行；補 10 個案例（含 128 字邊界的正向案例）；欄位名稱跳脫、未預期錯誤 exit 3；spec 案例表一致性測試帶標記 `spec-example: tests / the case table matches the test`。驗證：修正前 4 個失敗（跳脫、lone surrogate、exit 3、案例表），修正後只剩案例表（待 archive）；`bash tests/codex-plugin.sh` 約 7 秒。
- [ ] 1.2 [after: 1.1] archive 之後全套測試與本機 CI gate 通過。驗證：`idd-ci-gate.sh run --commit HEAD` exit 0。
