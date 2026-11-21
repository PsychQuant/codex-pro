## 1. 第 5 輪 findings（Requirement: Native plugin static contract test、Cross-harness version consistency）

- [x] 1.1 （Native plugin static contract test）案例輸出寫進檔案、exit 0 以檔案大小判定；policy 兩欄缺少時印 required 並加案例；四個案例斷言舊訊息不再出現；gate 計數 fixture 寫入失敗記為失敗；案例表要求表頭與分隔線、容許欄位補空白、其他列一律 unparseable；以注入錯誤的副本從命令列檢查 exit 3。（Cross-harness version consistency）恢復 0.9.0／0.8.0 的 release notes 說明。驗證：修正前 4 個失敗，修正後 `bash tests/codex-plugin.sh` 全部通過（archive 後）。
