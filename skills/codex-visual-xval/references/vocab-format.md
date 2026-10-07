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
  "relations": {"tips_together": "distance_pct < 5"},
  "position_threshold_pct": 5,
  "max_count": {"INST": 2},
  "track_class": "INST",
  "sam_margin_pct": 1
}
```

| 欄位 | 必填 | 說明 |
|---|---|---|
| `classes` | 是 | 類別代號 → 說明。清單外的物體一律記為 `other`，並附 `other_description` |
| `constraints` | 否 | 物理約束的文字說明，放進給 Codex 的 prompt |
| `relations` | 否 | 關係名 → 量化定義（`<量> <比較符號> <數值>`）。**沒有數值門檻的關係詞會讓輸入不合格**（`target_invalid`）：沒有門檻的「會合」「靠近」會造成假分歧 |
| `position_threshold_pct` | 否 | 位置差超過多少（畫面寬度百分比）算分歧，預設 5 |
| `max_count` | 否 | 類別 → 數量上限。答案超過上限的一方，在數量分歧裡輸 |
| `track_class` | 否 | SAM 追蹤的類別，預設為 `classes` 的第一個 |
| `sam_margin_pct` | 否 | SAM 量測值離門檻多近就不算證據，預設 1（實測 SAM 與標註的距離差最大 0.91%） |

SAM 目前只量 `distance_pct`（兩個追蹤物件尖端的距離，以畫面寬度百分比計）。其他量的關係詞仍可比對，
但只能靠放大輪或物理約束裁決。
