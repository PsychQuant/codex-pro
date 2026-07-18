# Profile Resolution Contract（EXTERNAL-CONSUMER CONTRACT，STABLE since 0.7.0，#7）

> 本檔 + [`defaults.json`](defaults.json) 是 codex-pro 治理層（model / effort / max_time）對外的**凍結契約**。外部 consumer（首例：`issue-driven-dev` 的 idd-verify codex leg，見 issue-driven-development#264）依此解析，**不**抄 producer skill 的 prose resolver。契約變更走 semver：欄位增刪 / 路徑變動 = breaking（major）；defaults 值變動（如 model 換代）= minor + `contract_version` 註記。前例：pai#20 → pai 2.18.0 的 STABLE args/return surface。

## 1. Defaults（single source = `defaults.json`）

機器可讀：[`references/defaults.json`](defaults.json)。欄位：

| Field | Type | 現值 | 語意 |
|-------|------|------|------|
| `model` | string | `gpt-5.6-sol` | codex-call `--model`；#3 裁決（backend-api 路徑 5.6 世代僅此名可用） |
| `effort` | string | `xhigh` | codex-call `--effort` |
| `max_time` | int | `600` | codex-call `--max-time`（秒，硬 HTTP timeout） |
| `contract_version` | string | `1.0.0` | 本契約的 semver（consumer 可 gate） |

**producer skills 的 prose 表（codex-review / codex-rescue / codex-adversarial-review / codex-batch / codex-config）是本檔的鏡像** — 分歧時以 `defaults.json` 為準。（skills 全面改讀檔屬 follow-up，見 #7 Expected 3。）

## 2. Profile 層（使用者覆蓋）

| Layer | 路徑 | 優先序 |
|-------|------|--------|
| project | `<cwd>/.codex-pro/profile.yaml` | 高（覆蓋 global）|
| global | `~/.codex-pro/profile.yaml` | 中 |
| defaults | `references/defaults.json` | 低（缺欄位時的 fallback）|

**解析順序**：per-field 取第一個有值的層（project > global > defaults）。`profile.yaml` 是扁平 YAML（無巢狀），可解析欄位：`model` / `effort` / `max_time` / `focus_default`（最後者為 codex-pro skill 專用，外部 consumer 可忽略）。缺檔 = 該層跳過（不是錯誤）；欄位值非法（如 effort 不在 codex 支援值域）由 consumer 端自行 fail-loud——本契約不定義 consumer 的錯誤策略。

## 3. Consumer 端的解析範例（non-normative）

```bash
CP_DIR=$(ls -d ~/.claude/plugins/cache/codex-pro/codex-pro/*/ 2>/dev/null | grep -E '/[0-9]+\.[0-9]+\.[0-9]+/$' | sort -V | tail -1)
DEFAULTS="$CP_DIR/references/defaults.json"   # 缺檔 → consumer fail-fast（版本 < 0.7.0）
MODEL=$(python3 -c "import json;print(json.load(open('$DEFAULTS'))['model'])")
# 再依序疊 ~/.codex-pro/profile.yaml 與 ./.codex-pro/profile.yaml 的同名欄位（若存在）
```

## 4. Stability guarantees

- `defaults.json` 的路徑（`references/defaults.json` 相對 plugin root）、四個欄位名、profile.yaml 兩層路徑與 per-field 優先序 = **STABLE**，非 major 不動
- defaults **值**會隨治理決策變動（model 換代）— consumer 不應 pin 值，應 pin 契約
- executable（codex-call）**不在本契約內** — 那是 parallel-ai-agents 的 surface（codex-pro design D3：executable 歸 pai）
