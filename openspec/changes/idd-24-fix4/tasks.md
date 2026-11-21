## 1. 第 4 輪 findings（Requirement: Native plugin static contract test）

- [x] 1.1 （Native plugin static contract test）不可讀 manifest 改用目錄、合法 prerelease／build 正向案例、object 與 array 型別案例、`name` 為 null 與 `source.source` 缺少的訊息、超長整數以 Decimal 解析、exit 0 案例要求無輸出、案例表解析失敗即報錯、`mktemp` 檢查與單一 trap、命令列入口的 exit-3 檢查，案例表同步更新。驗證：修正前 3 個失敗（`source.source` required、超長整數、案例表），修正後 `bash tests/codex-plugin.sh` 全部通過（archive 後）。
