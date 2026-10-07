# 主張（claim）的 JSON schema

每張圖一筆主張；兩個模型用同一個 schema。座標是畫面寬度（`x_pct`）與高度（`y_pct`）的百分比，0–100。

```json
{"claims": [
  {"frame": "f01.png",
   "objects": {"INST": 2, "THREAD": 1},
   "points": [
     {"class": "INST", "x_pct": 39.6, "y_pct": 71.5, "touching": "NEEDLE"},
     {"class": "INST", "x_pct": 53.2, "y_pct": 55.2, "touching": "THREAD"}
   ],
   "relations": {"tips_together": false}}
]}
```

- `frame`：中性檔名（`f01.png`…），每張圖恰好一筆。
- `objects`：每個類別看到幾個。清單外的物體記為 `other`，並在同一筆主張加 `other_description`。
- `points`：每個物體的關鍵點；器械取**尖端**（夾口末端），不是桿身。`touching` 是它碰到的類別或 `null`。
- `relations`：詞彙表裡的每個關係都要回答 `true` 或 `false`。

比對時，同類物體依總距離最小配對，分歧分成三類：數量不同、位置差超過門檻、關係不同。
