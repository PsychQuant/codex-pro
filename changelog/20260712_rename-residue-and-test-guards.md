# 2026-07-12 — Rename 殘留清理 + test 防線強化（issues #2 / #4 / #5）

## 摘要

`/idd-all` batch（#1 #2 #4 #5）前三個 lane 的產出：rename-skills-codex-prefix（`43b7b67`，issue #2）的 catch-up verify 與殘留清理、test 迴歸防線強化（issue #4）、specs 樹 122 處舊路徑同步（issue #5）。三個 issue 均達 verified（6-AI cluster/catch-up verify PASS）。

Commits: `77c4239`、`9b509c7`、`ff392ef`、`b45938d`｜Tags: `idd-2-verified`、`idd-4-verified`、`idd-5-verified`

## 變更

### Issue #2 — rename 殘留（`77c4239`）
- codex-cancel SKILL.md：舊裸名 shorthand `:rescue` / `:adversarial-review` → codex- 前綴（中英文各一處）
- 裸「取消」trigger keyword qualify 為「取消 codex」；result 的「看完整 / detail」qualify
- codex-config 移除 stale「第 10 個 user-facing capability」序號

### Issue #4 — test 防線（`9b509c7` + `b45938d`）
- tests/review.sh / rescue.sh：no-profile resolver 斷言（`gpt-5.6-sol|xhigh|600||default`）— 三 producer default 迴歸保護對稱化
- tests/config.sh：修 **anti-guard**（舊 whitelist 主動接受裸 `設定`/`配置`/`config`，會綠燈放行 issue #2 的回歸）
- tests/{config,result,status}.sh：bare-generic guard 統一改 **token 級**（解析 Trigger keywords 行 — 修 status 塌陷邏輯、補英文裸詞覆蓋；cluster verify findings）
- codex-result SKILL.md：`--latest <skill>` enum fail-fast reject（非法值不再流進 glob 產生誤導訊息）；tests/result.sh 斷言強化（case + exit 2 結構檢查）
- temp dir cleanup 移至 assert 前（trap-safe）

### Issue #5 — specs 路徑同步（`ff392ef` + `b45938d`）
- 10 個 active spec 檔 122 處 `skills/<name>/` → `skills/codex-<name>/`（trace 註解大宗 + batch/tests spec 的 normative 條款路徑）
- **可執行殘留**（DA 獨抓）：`tests/lib/e2e-claude-print.sh` 的 Layer 3 e2e 觸發仍組裸名 `/codex-pro:review` — 修為 `codex-` 前綴（result-file glob 維持裸名，兩者本需不同值）
- trace code-list 去重 ×80（機械替換撞上既有 codex-* 條目）
- `tests/spec.md` bare-prefix 範例修正（逃過完整前綴 pattern 的縮寫形式）

## 驗證

- `tests/run.sh` 全綠（斷言 370 → 377+）
- 6-AI ensemble ×2：#2 catch-up verify（18 findings 分類，PASS）、#4+#5 cluster verify（24 findings、5 MEDIUM 全修，PASS）
- Verify reports：[#2](https://github.com/PsychQuant/codex-pro/issues/2#issuecomment-4949815623)、[#4+#5 cluster](https://github.com/PsychQuant/codex-pro/issues/4#issuecomment-4949958059)

## 進行中

- Issue #1（heading-reliability promotion）：12-combo Layer 3 e2e matrix 執行中，結果決定 warn→hard 斷言 promotion
