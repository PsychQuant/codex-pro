# 主張（claim）的 JSON schema

每張圖一筆主張；兩個模型用同一個 schema。座標是畫面寬度（`x_pct`）與高度（`y_pct`）的百分比，0–100。

```json
{"claims": [
  {"frame": "f01.png",
   "objects": {"INST": 2, "THREAD": 1},
   "points": [
     {"class": "INST", "x_pct": 39.6, "y_pct": 71.5},
     {"class": "INST", "x_pct": 53.2, "y_pct": 55.2},
     {"class": "THREAD", "x_pct": 47.0, "y_pct": 60.1}
   ],
   "relations": {"tips_together": false}}
]}
```

- `frame`：中性檔名（`f01.png`…），每張圖恰好一筆。
- `objects`：每個類別看到幾個。清單外的物體記為 `other`，並在同一筆主張加 `other_description`。
- `points`：**每個計數的物體恰好一個關鍵點**，所以某類別的點數必須等於它在 `objects` 的數量（上例 INST 2 個點、
  THREAD 1 個點）。器械取**尖端**（夾口末端），不是桿身。點數與數量不符的答案不合格：Claude 的答案為
  `target_invalid`，Codex 的回覆為 `parse_failed`。「碰到什麼」不另外記，寫成詞彙表裡有門檻的關係詞。
- `relations`：詞彙表裡的每個關係都要回答 `true` 或 `false`。

比對時，同類物體依總距離最小配對，分歧分成三類：數量不同、位置差超過門檻、關係不同。
