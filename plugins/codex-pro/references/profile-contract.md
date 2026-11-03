# Profile Resolution Contract（EXTERNAL-CONSUMER CONTRACT，STABLE since 0.7.0，#7）

> 本檔 + [`defaults.json`](defaults.json) 是 codex-pro 治理層（model / effort / max_time）對外的**凍結契約**。外部 consumer（首例：`issue-driven-dev` 的 idd-verify codex leg，見 issue-driven-development#264）依此解析，**不**抄 producer skill 的 prose resolver。契約變更走 semver：欄位增刪 / 路徑變動 = breaking（major）；defaults 值變動（如 model 換代）= minor + `contract_version` 註記。前例：pai#20 → pai 2.18.0 的 STABLE args/return surface。

## 1. Defaults（single source = `defaults.json`）

機器可讀：[`references/defaults.json`](defaults.json)。欄位：

| Field | Type | 現值 | 語意 |
|-------|------|------|------|
| `model` | string | `gpt-5.6-sol` | codex-call `--model`；#3 裁決（backend-api 路徑 5.6 世代僅此名可用） |
| `effort` | string | `xhigh` | codex-call `--effort` |
| `max_time` | int | `600` | codex-call `--max-time`（秒，硬 HTTP timeout） |
| `contract_version` | string | `1.1.0` | 本契約的 semver（consumer 可 gate）；1.1.0 新增角色表（第 5 節，#20） |

**producer skills 的 prose 表（codex-review / codex-rescue / codex-adversarial-review / codex-batch / codex-config）是本檔的鏡像** — 分歧時以 `defaults.json` 為準。（skills 全面改讀檔屬 follow-up，見 #7 Expected 3。）

## 2. Profile 層（使用者覆蓋）

| Layer | 路徑 | 優先序 |
|-------|------|--------|
| project | `<cwd>/.codex-pro/profile.yaml` | 高（覆蓋 global）|
| global | `~/.codex-pro/profile.yaml` | 中 |
| defaults | `references/defaults.json` | 低（缺欄位時的 fallback）|

**解析順序**：per-field 取第一個有值的層（project > global > defaults）。`profile.yaml` 是扁平 YAML（無巢狀），可解析欄位：`model` / `effort` / `max_time` / `focus_default`（最後者為 codex-pro skill 專用，外部 consumer 可忽略）。缺檔 = 該層跳過（不是錯誤）；欄位值非法（如 effort 不在 codex 支援值域）由 consumer 端自行 fail-loud——本契約不定義 consumer 的錯誤策略。

## 3. Consumer 端的解析範例（non-normative）

本契約規範的是「已知 codex-pro bundle root 後」的穩定相對路徑，不規範 host
如何發現或安裝 plugin。Consumer 應使用 active skill／plugin context 提供的絕對路徑，
不得掃描版本 cache 或從目前工作目錄猜測安裝位置。

Codex 原生 plugin 或 repo-local bundle 內的 skill，可從 Codex 提供的 active
`SKILL.md` 絕對位置設定 `SKILL_DIR`：

```bash
SKILL_DIR="/absolute/path/from/active-skill-context/skills/codex-review"
BUNDLE_ROOT=$(cd "$SKILL_DIR/../.." && pwd -P)
DEFAULTS="$BUNDLE_ROOT/references/defaults.json"
[ -f "$DEFAULTS" ] || { echo "codex-pro defaults missing: $DEFAULTS" >&2; exit 1; }
MODEL=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["model"])' "$DEFAULTS")
# 再依序疊 ~/.codex-pro/profile.yaml 與 ./.codex-pro/profile.yaml 的同名欄位（若存在）
```

Claude Code plugin 內的 consumer 應使用 host 提供的 plugin root；外部 plugin 若要消費
本契約，則由其安裝／依賴層明確傳入 codex-pro root。掃描
`~/.claude/plugins/cache/` 不是本契約的一部分，也不保證跨版本正確。

## 4. Stability guarantees

- `defaults.json` 的路徑（`references/defaults.json` 相對 plugin root）、四個欄位名、profile.yaml 兩層路徑與 per-field 優先序 = **STABLE**，非 major 不動
- defaults **值**會隨治理決策變動（model 換代）— consumer 不應 pin 值，應 pin 契約
- executable（codex-call）**不在本 profile 解析契約內**。Codex 原生發布釘選一份
  bundled snapshot，其來源與呼叫契約由 `codex-call-provenance.json`、
  `THIRD_PARTY_NOTICES.md` 與 `bin/codex-pro-call` 管理；Claude Code 版則維持 PATH
  解析。外部 consumer 不應從本檔推論 executable 的位置或穩定性

## 5. 角色表（`references/roles.yaml`，#20，1.1.0 起）

要的是「哪一種工作」而不是「哪個模型」時，consumer 依角色名稱讀這份表，自己不寫模型名。這裡是唯一決定某個角色用哪個模型的地方，要改就改這份表。

- 目前有兩個角色：`default` 的 `model`、`effort`、`max_time` 就是 `defaults.json` 的頂層欄位，測試檢查兩者一致；`proof-hard` 給 Lean 證明，有 `model`、`effort`、`service_tier`。
- 格式：角色名稱在第 0 欄，欄位縮排兩格，每行一個 `field: value`，欄位行不放註解。
- 只新增、不改名：第 4 節穩定的項目都不動，既有 consumer 不受影響。讀不到角色或缺欄位時，consumer 應停下報錯，不要退回別的模型。
- 這份表不經 `profile.yaml` 覆蓋：扁平解析器不能表達每個角色的欄位，覆蓋機制等 #18 決定。臨時換一次，由 consumer 的旗標處理。
