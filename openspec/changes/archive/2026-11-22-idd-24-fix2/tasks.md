## 1. 規格與測試對齊（Requirement: Native plugin static contract test）

- [x] 1.1 （Native plugin static contract test）第 2 輪 findings 1–6、8、10、11：每個 checker 規則都有會失敗的負向案例（46 個）、整合案例加 control 與 gate 失敗行的比對、沒有 git work tree 時改複製整棵樹、nested run 以每次執行的 token 判定、here-string 比對、「不印任何輸出」以檔案大小判定、trap 清除暫存；checker 對重複的 key 與過深巢狀回 exit 2、`./assets/.png` 違規。整合案例帶標記 `spec-example: tests / a broken copy fails the whole contract test`。驗證：新案例在修正前失敗（RED：3 個 schema 案例與 control），修正後 `bash tests/codex-plugin.sh` 130 pass / 0 fail，在沒有 `.git` 的副本裡同樣 130 / 0。
- [x] 1.2 [after: 1.1] 全套測試與本機 CI gate 通過。驗證：`idd-ci-gate.sh run --commit 993de17` exit 0（第 2 次 RESULT=pass，2036 / 0；第 1 次 setup 層 1 fail，原因是其他 Codex 程序寫入 `~/.codex`，見 #41）。
