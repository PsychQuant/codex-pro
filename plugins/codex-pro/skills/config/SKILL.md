---
name: config
description: |
  顯示 codex-pro 已 resolve 的 profile 配置 — 列出 model / effort / max_time / focus_default 4 個 field 的當前值與來源（global / project / default）。
  Profile 來源兩 layer：global `~/.codex-pro/profile.yaml` + project `<cwd>/.codex-pro/profile.yaml`、project per-field override global、missing field fall back hardcoded default。
  Read-only consumer category — 純檔案讀取、無 file mutation、不 spawn 任何 subprocess、stdout-only markdown table。
  與 setup / status / result / cancel 同 category；對 producer skills（review / rescue / adversarial-review）以及 batch exception 不互動。
  Trigger keywords: profile, config, settings, 設定, 配置, which model, which max-time, show profile, view config, codex-pro profile
allowed-tools:
  - Bash
  - Read
---

# /codex-pro:config — Display Resolved Profile (v0.1 read-only consumer)

掃 `~/.codex-pro/profile.yaml`（global layer）+ `<cwd>/.codex-pro/profile.yaml`（project layer）兩 layer profile、field-level merge、missing field 用 hardcoded default、輸出 4-row markdown table + 2 行 profile file 存在性。本 skill 是 codex-pro 第 10 個 user-facing capability、屬 **read-only consumer category**（與 setup / status / result / cancel 同類、與 producer review / rescue / adversarial-review 對比、與 batch exception 對比）。

## 行為原則

本 skill 嚴守 codex-pro **read-only consumer category** 紀律：

- **無 Codex HTTP wrapper 呼叫**：不送 HTTPS request、不耗 Codex quota
- **無 Codex CLI subprocess**：完全不 spawn 任何 codex 相關 subprocess
- **無 file mutation**：**不建立** `~/.codex-pro/` 或 `<cwd>/.codex-pro/` 目錄、不寫任何 file、stdout-only
- **無外網 call**：純本機 file ops、純 Bash + Read + python3 parse
- **不互動 producer 邏輯**：不 simulate review / rescue / adversarial-review invocation、純 display profile state

與 producer skills 的 mutating-write category 對比、與 batch 的 mutating-exception category 對比、config 屬 **read-only consumer category** — 與 setup（環境檢查）+ status（list result files）+ result（display single result file）+ cancel（informational explainer）並列五件套。

## Step 1: Profile resolution algorithm

兩 layer profile load + field-level merge + hardcoded fallback：

```
Layer 1 (global) :  ~/.codex-pro/profile.yaml           ← optional
Layer 2 (project):  <cwd>/.codex-pro/profile.yaml       ← optional, 較高優先

Resolution per field:
  if field in project_layer → source = project, value = project_layer[field]
  elif field in global_layer → source = global, value = global_layer[field]
  else                       → source = (default), value = HARDCODED_DEFAULT[field]
```

**Lazy resolution per invocation** — 每次跑 skill 都重讀 profile、user edit profile 後立即生效、不 cache。Missing file 視為 empty layer（不 error）。Malformed YAML 也視為 empty layer（silent fallback、容錯路線；v0.2 評估 strict mode 留待 future cycle）。Unknown field 在 profile 但不在 schema → silently ignored（forward-compat with future schema additions）。Field type mismatch（如 `max_time: "abc"` instead of int）→ 該 field fall back 至 hardcoded default、其他 field 不受影響。

## Step 2: Schema v0.1 — 4 fields

| Field | YAML type | Hardcoded default | Producer skills that use it |
|---|---|---|---|
| `model` | string | `gpt-5.5` | review / rescue / adversarial-review |
| `effort` | string | `xhigh` | review / rescue / adversarial-review |
| `max_time` | int (seconds) | `600` | review / rescue / adversarial-review |
| `focus_default` | string | `""` (empty) | adversarial-review only（review / rescue 忽略） |

v0.1 schema 限定 4 fields。`max_findings` / `sandbox` 等 Constraint #5 列出但 v0.1 不收（max_findings 會 conflict review v0.1 「findings_count uncapped」承諾、sandbox 屬 batch 範疇；留 future cycle）。Schema 隱式 v1、未來改 schema 加 `version:` field 時 default `1`（migration friendly）。

## Step 3: Output format

stdout-only markdown table、4 row（schema 固定）+ 2 informational line：

```
| field          | resolved value          | source              |
| -------------- | ----------------------- | ------------------- |
| model          | gpt-5.5                 | (default)           |
| effort         | xhigh                   | (default)           |
| max_time       | 1200                    | project             |
| focus_default  | security                | global              |

Global profile:  ~/.codex-pro/profile.yaml (exists)
Project profile: .codex-pro/profile.yaml (does not exist)
```

`source` enum 值：`(default)` / `global` / `project`。Table column 順序固定為 `field | resolved value | source`、row 順序固定為 `model` → `effort` → `max_time` → `focus_default`。

兩 informational line 顯示 profile file 是否存在於兩 layer、user 不需自己 `ls`。

任何 argument 都 silently ignored — skill 仍 display profile + exit 0（與 cancel skill informational-only convention 對齊）。

## Step 4: Inline python3 resolution

用 inline `python3` regex YAML parse、不依賴 `import yaml`（python3 stdlib 不含 PyYAML、user 不需 `pip install`）。完整 script：

```bash
python3 - <<'PY'
import os, re

DEFAULTS = {
    "model": "gpt-5.5",
    "effort": "xhigh",
    "max_time": 600,
    "focus_default": "",
}

def parse_yaml_simple(path):
    """Simple regex-based YAML parser for flat key:value schema.
    Not a general YAML parser — handles only `^<key>: <value>` lines.
    Returns dict or empty dict on missing/malformed file."""
    if not os.path.exists(path):
        return {}
    try:
        content = open(path).read()
    except Exception:
        return {}
    result = {}
    for line in content.splitlines():
        m = re.match(r'^(\w+):\s*(.*)$', line)
        if not m:
            continue
        key, raw = m.group(1), m.group(2).strip()
        # Strip optional quotes
        if (raw.startswith('"') and raw.endswith('"')) or (raw.startswith("'") and raw.endswith("'")):
            raw = raw[1:-1]
        result[key] = raw
    return result

global_path = os.path.expanduser("~/.codex-pro/profile.yaml")
project_path = ".codex-pro/profile.yaml"
global_layer = parse_yaml_simple(global_path)
project_layer = parse_yaml_simple(project_path)

resolved = {}
sources = {}
for field, default in DEFAULTS.items():
    if field in project_layer:
        raw = project_layer[field]
        sources[field] = "project"
    elif field in global_layer:
        raw = global_layer[field]
        sources[field] = "global"
    else:
        raw = default
        sources[field] = "(default)"
    # Type coercion: max_time must be int; mismatch → fall back to default
    if field == "max_time":
        try:
            raw = int(raw)
        except (ValueError, TypeError):
            raw = default
            sources[field] = "(default)"
    resolved[field] = raw

# Emit markdown table
print("| field          | resolved value          | source              |")
print("| -------------- | ----------------------- | ------------------- |")
for field in DEFAULTS:
    print(f"| {field:<14} | {str(resolved[field]):<23} | {sources[field]:<19} |")
print()
print(f"Global profile:  ~/.codex-pro/profile.yaml ({'exists' if os.path.exists(global_path) else 'does not exist'})")
print(f"Project profile: .codex-pro/profile.yaml ({'exists' if os.path.exists(project_path) else 'does not exist'})")
PY
```

關鍵：

- **No `import yaml`**：避免 user 需 `pip install pyyaml`（python3 stdlib 不含）；改用 regex inline parse（與 codex-pro 既有 status / result skill YAML parse 一致 pattern）
- **No write operations**：純讀 + stdout print；read-only invariant
- **Lazy per invocation**：每次跑都重 read、user edit profile 後 immediate effect
- **Forward-compat**：unknown field in profile silently ignored、不在 4-row table 顯示

## 與 setup / status / result / cancel 的對比

| 面向 | `/codex-pro:setup` | `/codex-pro:status` | `/codex-pro:result` | `/codex-pro:cancel` | `/codex-pro:config` |
|---|---|---|---|---|---|
| Mental model | 環境檢查 | list result files | display single file | informational only | display profile |
| 讀什麼 | `~/.codex/auth.json` + Codex HTTP wrapper PATH | `.codex-pro/*.md` | 特定 `.codex-pro/<skill>-<ts>.md` | 無檔依賴 | `~/.codex-pro/profile.yaml` + `.codex-pro/profile.yaml` |
| Argument | 無 | optional `--skill <name>` filter | 位置 / `--latest [<skill>]` 三 mode | 零 argument | 零 argument |
| Output | env check result | markdown table summary | verbatim file content | static explainer + 3 remediation | markdown table + 2 行 file 存在性 |
| File mutation | 無 | 無 | 無 | 無 | 無 |

五 skill 同屬 codex-pro **read-only consumer category** — 與 review / rescue / adversarial-review 的 mutating producer 對比、與 batch 的 mutating exception 對比。Config 是 read-only category 內最新成員（v0.5）、補 Constraint #5「Profile-based config」部分落地（model / effort / max_time / focus_default 4 fields；max_findings + sandbox 留 future cycle）。

## Sample profile.yaml

User 自己建立 profile file（skill 不會自動建立目錄或檔案）。先建立 `~/.codex-pro/` 目錄（global）或 `<repo>/.codex-pro/` 目錄（project），再寫入 `profile.yaml`。

Global profile（per-user、適用每個 codex-pro project，除非 project 覆蓋）：`~/.codex-pro/profile.yaml`

```yaml
model: gpt-5.5
effort: xhigh
max_time: 600
focus_default: ""
```

Project profile（per-repo、優先於 global）：`<repo>/.codex-pro/profile.yaml`

```yaml
max_time: 1200
focus_default: security
```

> Note: `.codex-pro/` 在 codex-pro repos 預設 gitignored。若要與 team 分享 project profile、un-gitignore 或 commit 到非 ignored path。

跑 `/codex-pro:config` 即顯示 resolved value 與 per-field source。
