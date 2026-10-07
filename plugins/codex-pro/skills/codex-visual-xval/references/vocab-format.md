# 詞彙表格式（`--vocab`）

詞彙表把「畫面裡可能出現什麼」寫成封閉清單，讓兩個模型用同一套語言作答，也讓比對可以用程式做。

```json
{
  "classes": {
    "INST": "腹腔鏡器械（含夾口）",
    "THREAD": "縫線",
    "NEEDLE": "縫針",
    "PAD": "練習墊或組織"
  },
  "constraints": ["畫面中最多兩支器械", "器械是剛體，從畫面邊緣進入"],
  "relations": {
    "tips_together": {"between": ["INST", "INST"], "definition": "distance_pct < 5"}
  },
  "position_threshold_pct": 5,
  "max_count": {"INST": 2},
  "track_class": "INST",
  "sam_margin_pct": 1
}
```

| 欄位 | 必填 | 說明 |
|---|---|---|
| `classes` | 是 | 類別代號 → 說明。清單外的物體一律記為 `other`，並附 `other_description` |
| `constraints` | 否 | 物理約束的文字說明（字串陣列），放進給兩個模型的 prompt。**只是提示，不會當成裁決證據**；要當證據的上限寫在 `max_count` |
| `relations` | 否 | 關係名 → `{"between": [類別, 類別], "definition": "<量> <比較符號> <數值>"}`。`between` 指明量的是哪兩類物件的關鍵點；`definition` 只接受「量的名稱、比較符號、數字」，例如 `distance_pct < 5`。其他寫法（`很近（< 5）`、沒有門檻的「會合」）一律 `target_invalid`：沒說量什麼、量哪兩點，兩個模型會各量各的，造成假分歧 |
| `position_threshold_pct` | 否 | 位置差超過多少（畫面寬度百分比）算分歧，預設 5 |
| `max_count` | 否 | 類別 → 數量上限，也會寫進給兩個模型的 prompt。答案超過上限的一方在數量分歧裡被排除；這是排除法，不代表另一方的數量被確認 |
| `track_class` | 否 | SAM 追蹤的類別，預設為 `classes` 的第一個 |
| `sam_margin_pct` | 否 | SAM 量測值離門檻多近就不算證據，預設 1（實測 SAM 與標註的距離差最大 0.91%） |

SAM 只追蹤 `track_class` 一個類別，所以 SAM 證據只用於這個類別的數量與位置分歧，以及 `between` 兩邊都是
`track_class`、定義為 `distance_pct` 的關係（兩個追蹤物件尖端的距離，以畫面寬度百分比計）。其他分歧只能靠
放大輪或 `max_count` 裁決。
