## Context

codex-pro Design constraint #5 自 v0.1 起承諾 profile-based config（max-findings / sandbox / model / focus 全可配置）— 但 v0.4.x 為止仍是 vapor。三個 producer skill（review / rescue / adversarial-review）的 Step 4 codex-call invocation 全 hardcode `gpt-5.5` / `xhigh` / `--max-time 600`、user 沒辦法不改 SKILL.md 就調整。

Workflow synthesis (wqfvs53aw) 把 config 排到 #3（pure downstream、feature-foundational）。為什麼是 #3 而非 #1：

- #1（diff-untracked-fix）是 silent-correctness bug、必須先修
- #2（codex-call runtime upstream PR）是 cross-repo、屬於 parallel-ai-agents 的 Spectra cycle
- #3（config）才是 codex-pro 自家可以做的最大 leverage

User 場景：

- 我這台機器 Codex tier 不夠、想 review 都用 gpt-5.0 → 沒辦法
- 這個 repo 我希望 review --max-time 1200（2x default）→ 沒辦法
- adversarial-review 預設 --focus security（auth library） → 沒辦法

Constraint #5 列 4 個 field（max-findings / sandbox / model / focus）。本 cycle 取 model + effort + max_time + focus_default 為 v0.1 schema（4 fields）：

- 不收 `max_findings`：會 conflict review v0.1 spec「findings_count with no upper bound」承諾、scope 大、留 v0.2 評估
- 不收 `sandbox`：batch-specific、batch 本身是 explicit exception 性質不同、留 future cycle

兩 layer profile（global + project）+ field-level merge + missing → hardcoded default。100% backward compatible — 沒 profile 時 producer 行為與 v0.4 identical。

## Goals / Non-Goals

**Goals:**

- 新 `/codex-pro:config` read-only consumer skill display resolved profile + per-field source
- 兩 layer profile：`~/.codex-pro/profile.yaml`（global）+ `<project>/.codex-pro/profile.yaml`（project, priority 較高）
- v0.1 schema 4 fields：`model` / `effort` / `max_time` / `focus_default`
- 3 producer skill（review / rescue / adversarial-review）Step 4 改為 profile-aware：missing field → hardcoded default
- Result file frontmatter 加 optional `profile_source` field（per-field 標示來源、或 aggregate enum）
- 100% backward compat：未設 profile 行為與 v0.4 identical
- Plugin bump 0.4.0 → 0.5.0、三 producer skill 同 cycle 升 minor
- Test: Layer 2 config.sh + 三 producer 加 profile behavioral scenario；Layer 3 加 1 new `with-profile` scenario
- 解 Constraint #5 vapor（部分） — model + effort + max_time + focus_default 落地、max_findings + sandbox 留 future

**Non-Goals:**

- 不改 batch skill / sandbox / max_findings
- 不引入 retry / backoff config（fail-fast architectural invariant）
- 不引入 timeout-per-skill override（global max_time 即可）
- 不引入 profile schema version 字段
- 不引入 profile inheritance（base + override）
- 不引入 env var override（CODEX_PRO_MODEL=...）
- 不引入 multi-profile（named dev / prod）
- 不引入 JSON Schema spec
- 不引入 profile encryption / secret store
- 不對 setup 加 profile-check（profile 是 producer-跑時 lazy）
- 不寫 GUI / interactive edit
- 不 Windows 支援
- 不改 fail-fast 4 class、不改 result file H2 結構

## Decisions

### D1: Two-layer profile (global + project) with project priority, field-level merge

採 **`~/.codex-pro/profile.yaml`（global）+ `<project>/.codex-pro/profile.yaml`（project）、project per-field override global、missing field → hardcoded default**。

理由：

- Per-machine config（global）vs per-repo config（project）是 industry-standard pattern（git config global vs local、npm config、cargo config）
- 兩 layer 已足 v0.1 — single-flat profile 不夠（per-repo override 是 user 真實 use case）；3+ layer 過 complex
- Field-level merge 而非 file-level merge：user 只在 project profile 寫 `max_time: 1200`、其他 field 用 global default — 比強制 project 寫完整 schema friendly
- Project layer priority 較高：repo-specific intent > machine-wide preference
- Hardcoded default 為 final fallback：user 沒任何 profile 時行為與 v0.4 identical = 100% backward compat
- `<project>` = cwd（與 `.codex-pro/<skill>-<ts>.md` result file 的 cwd 定義一致）

Alternatives:

- 單 layer profile（global only）：失去 per-repo override、user 不能對 monorepo 不同子 repo 設不同 config
- 三 layer（global + project + env vars）：env vars 留 future、Non-Goals
- File-level merge（不 field-level）：project must replicate global schema、不 friendly
- Global override project：違反 specific-overrides-general convention

### D2: Schema v0.1 = 4 fields (model / effort / max_time / focus_default)

採 **4 fields**、刻意不收 `max_findings` 與 `sandbox`。

| Field | Type | Default | Producer affected |
|---|---|---|---|
| `model` | string | `gpt-5.5` | review / rescue / adversarial-review |
| `effort` | string enum | `xhigh` | review / rescue / adversarial-review |
| `max_time` | int seconds | `600` | review / rescue / adversarial-review |
| `focus_default` | string | `""` | adversarial-review only（review / rescue 忽略） |

理由：

- 4 field 是 v0.1 user-facing value 的 80/20 — covers 「change my model」、「change my timeout」、「set default focus」三大常見 use case
- `max_findings` 不收：v0.1 review spec 明示「findings_count with no upper bound」、加 config 等於改 spec contract、scope 升一個 cycle
- `sandbox` 不收：batch-specific、且 batch 本身是 Design constraint #1 explicit exception、性質與 producer 不同、留 batch 自己 cycle 評估
- `effort` 是 enum 但 v0.1 不 hardcode 合法值（codex-call 接受 low/medium/high/xhigh/max；profile schema 不限定、verify 留 codex-call）
- `focus_default` 只 adversarial-review 用：review / rescue 收到 unknown profile field 不 error、silent ignore
- 不引入 schema version 字段：v0.1 隱式 v1、未來改 schema 加 `version:` field 時 default `1`（migration friendly）

Alternatives:

- 5 fields（含 max_findings）：影響 review spec、cycle 太大
- 6 fields（含 sandbox）：batch concern、單獨 cycle 評估
- 3 fields（drop focus_default）：失去 adversarial-review value、user 必須每次 invoke 寫 --focus
- 全 field optional：v0.1 schema 已全 optional（missing → default）、無 required field

### D3: Profile resolution algorithm — load global → load project → field merge → hardcoded fallback

採 **per-invocation lazy resolution**（不 cache、每次 producer skill 跑都重 resolve）。

Algorithm（pseudo-code）：

```python
DEFAULTS = {"model": "gpt-5.5", "effort": "xhigh", "max_time": 600, "focus_default": ""}

def resolve_profile(project_cwd: str) -> dict:
    global_path = expanduser("~/.codex-pro/profile.yaml")
    project_path = f"{project_cwd}/.codex-pro/profile.yaml"
    
    global_layer = parse_yaml_if_exists(global_path) or {}
    project_layer = parse_yaml_if_exists(project_path) or {}
    
    resolved = {**DEFAULTS, **global_layer, **project_layer}
    sources = {
        field: ("project" if field in project_layer
                else "global" if field in global_layer
                else "default")
        for field in DEFAULTS
    }
    return resolved, sources
```

理由：

- Lazy resolution：每次跑 producer 都重讀 profile、user edit profile 後立即生效、不需 reload
- 100% read-only（producer skill 不 mutate profile）
- 兩 layer 不存在時不 error（empty dict treated as no override）
- Unknown field 在 profile 但 not in DEFAULTS：v0.1 silently ignored（不 fail、preserve forward-compat）
- Missing required field：n/a（v0.1 schema 全 optional）
- Invalid value（如 `max_time: "abc"`）：v0.1 silently fallback to default（容錯路線、不 fail）— 留 v0.2 加 schema validation skill 評估

Alternatives:

- Cached resolution per session：user edit profile 後 session 不 refresh、surprise
- Strict validation（unknown field error）：太嚴、profile evolution friction
- File-level merge：要求 project 寫完整 schema（D1 已論證）

### D4: Producer skill Step 4 modification — read profile + pass resolved value to codex-call

採 **producer skill body inline `python3 -c` 讀 profile + 替代 hardcoded value**。

3 producer 的 Step 4 偽碼（共用 pattern）：

```bash
PROFILE_RESOLVED=$(python3 -c "
import yaml, os
DEFAULTS = {'model':'gpt-5.5','effort':'xhigh','max_time':600,'focus_default':''}
def load(p):
    if os.path.exists(p):
        try: return yaml.safe_load(open(p).read()) or {}
        except: return {}
    return {}
g = load(os.path.expanduser('~/.codex-pro/profile.yaml'))
p = load('.codex-pro/profile.yaml')
resolved = {**DEFAULTS, **g, **p}
print(f'{resolved[\"model\"]}|{resolved[\"effort\"]}|{resolved[\"max_time\"]}|{resolved.get(\"focus_default\",\"\")}')
")
IFS='|' read MODEL EFFORT MAX_TIME FOCUS_DEFAULT <<< "$PROFILE_RESOLVED"

codex-call \
  --output ".codex-pro/<skill>-<ts>.md" \
  --model "$MODEL" \
  --effort "$EFFORT" \
  --max-time "$MAX_TIME" \
  --instructions "..." \
  --prompt-file <prompt-file>
```

理由：

- Inline `python3 -c` 與 codex-pro 既有 YAML parsing pattern（status / result skill）一致
- 不依賴外部 `yaml` Python module — 改用 inline regex parse（避免 user 需 `pip install pyyaml`）
- 不抽出 shared bash function — keep SKILL.md self-contained（與 Layer 2 grep test pattern 一致）
- 重複 inline code 是 deliberate trade-off — SKILL.md 是 read-by-Claude 文件、不是 production code、不需 DRY
- Source 標示留給 `/codex-pro:config` skill：producer skill 只用 resolved value、不 emit source 進 codex-call

實作細節：

- v0.1 不用 `import yaml` — codex-pro 已寫 inline regex YAML parser（status skill）、複用同 pattern
- 不調用 `import yaml`：避免要求 user `pip install pyyaml`（python3 stdlib 不含 yaml）
- 改用「找 `^<field>: <value>` regex」inline parse（與 status / result skill 同 pattern）

Alternatives:

- 抽 shared `lib/profile-resolve.sh`：違反 SKILL.md self-contained、與 codex-pro pattern 不一致
- Producer skill 不 inline resolve、改 invoke `/codex-pro:config --resolve`：增加 nested skill invocation、複雜
- 用 `yq` 外部 binary：增加 runtime dependency

### D5: `/codex-pro:config` skill display semantics — 4-row markdown table with per-field source

採 **stdout-only markdown table、4 row（一 row per field）、columns `field | resolved value | source`**。

Output format：

```
| field          | resolved value          | source              |
| -------------- | ----------------------- | ------------------- |
| model          | gpt-5.5                 | (default)           |
| effort         | xhigh                   | (default)           |
| max_time       | 1200                    | project             |
| focus_default  | security                | global              |
```

`source` enum：`(default)` / `global` / `project`。

理由：

- 與 status / result skill markdown table convention 一致（user expectation: read-only consumer = markdown table）
- 4 row 固定 — schema fixed v0.1、不 variable
- Source column 是 v0.1 user value 的 80/20：「我設了 max_time 為什麼還是 600?」 → 看 source = global → 知道 project layer 有 override
- 不 emit raw YAML file content（user 自己 cat profile.yaml）、不 emit DEFAULTS reference docs（留 SKILL.md prose）

`/codex-pro:config` 額外印 2 行 informational：

```
Global profile:  ~/.codex-pro/profile.yaml (exists / does not exist)
Project profile: .codex-pro/profile.yaml (exists / does not exist)
```

讓 user 一眼看「profile file 存在嗎」、無需自己 ls。

Alternatives:

- JSON output：不 REPL-friendly
- Plain text 對齊：不 markdown render（user 通常在 Claude Code REPL 看）
- 多 row（含 unknown profile fields）：v0.1 silent ignore unknown、不 surface

### D6: Frontmatter `profile_source` field — optional, aggregate enum

採 **optional aggregate field in result file frontmatter**：`profile_source: <enum>`，enum 值：

- `default` — all 4 (or 3 for review/rescue) fields 全 hardcoded default
- `global` — 至少 1 field 來自 global、無 project override
- `project` — 至少 1 field 來自 project
- `mixed` — 至少 1 field global、至少 1 field project（hybrid）

理由：

- 用 single enum 而非 per-field source（4 fields × 3 source = 12 値）— v0.1 minimal、frontmatter 不 bloat
- 嫌簡略可以 `/codex-pro:config` 看 per-field detail
- Optional：v0.4 result file 沒此 field、下游 status / result skill 容忍 missing
- 不寫 v0.4 fallback：unread 即 unknown source、與 `(default)` 表現一致
- `mixed` enum 為「project override 部分 global」case、user 看 frontmatter 一眼知 hybrid

實作：producer skill Step 5 在 prepend frontmatter 時 compute enum：

```python
if any(s == "project" for s in sources.values()):
    profile_source = "project" if all(s in ("project", "default") for s in sources.values()) else "mixed"
elif any(s == "global" for s in sources.values()):
    profile_source = "global"
else:
    profile_source = "default"
```

Alternatives:

- Per-field source frontmatter（4 sub-keys）：bloat、v0.1 不需
- Source path string（`~/.codex-pro/profile.yaml`）：user-friendly 但長
- Drop entirely：失去「未來 status skill 過濾 profile-set runs」的 value

### D7: Read-only consumer category invariants enforced

`/codex-pro:config` 嚴守 read-only consumer 三 invariant（與 status / result / cancel 相同）：

- 無 `codex-call` 呼叫
- 無 `codex exec` subprocess
- 無 file mutation（不建 `~/.codex-pro/`、不寫 profile）

加 config-specific 一條：

- 不**呼叫** producer 邏輯（不 simulate review/rescue/adversarial-review invocation）

`/codex-pro:config` 純讀 profile + 印 table。

理由：

- 與 status / result / cancel category invariants 一致 — user 一眼看「跑 /codex-pro:config 不會動 disk / 燒 quota」
- 不建 `~/.codex-pro/`（user 必須自己 `mkdir -p ~/.codex-pro` + 寫 profile.yaml）— D2 100% backward compat 紀律
- Layer 2 test 強制 0 occurrence of `codex-call` / `codex exec` / `mkdir`（與 status SKILL.md 同 pattern）

Alternatives:

- 加 `--init` flag 自動建 profile：違反 read-only invariant
- 加 `--validate` mode：留 v0.2 schema validation skill

### D8: Test fixture pattern — fake `~/.codex-pro/` via tmp HOME

採 **Layer 2 behavioral test 用 fake HOME + fake project cwd 雙 isolation**：

```bash
fake_profile_test() {
  local global_yaml="$1"   # content for ~/.codex-pro/profile.yaml
  local project_yaml="$2"  # content for ./.codex-pro/profile.yaml
  local TMP_HOME=$(mktemp -d)
  local TMP_PROJ=$(mktemp -d)
  trap "rm -rf '$TMP_HOME' '$TMP_PROJ'" EXIT
  mkdir -p "$TMP_HOME/.codex-pro" "$TMP_PROJ/.codex-pro"
  [ -n "$global_yaml" ] && printf '%s' "$global_yaml" > "$TMP_HOME/.codex-pro/profile.yaml"
  [ -n "$project_yaml" ] && printf '%s' "$project_yaml" > "$TMP_PROJ/.codex-pro/profile.yaml"
  HOME="$TMP_HOME" cd "$TMP_PROJ" && <invoke skill or resolver>
}
```

5 fixture scenario for tests/config.sh：

1. **no-profile** — both layer missing → all default
2. **global-only** — `~/.codex-pro/profile.yaml: {model: gpt-5.0}` → model=global, others=default
3. **project-only** — `<proj>/.codex-pro/profile.yaml: {max_time: 1200}` → max_time=project, others=default
4. **mixed** — global has model, project has max_time → mixed enum
5. **project-overrides-global** — global model=gpt-5.0, project model=gpt-4.5 → project wins

Plus 1 e2e scenario `with-profile`（producer skill × profile）— mktemp + fake HOME + fake project profile + 跑 producer + verify codex-call invocation 用 profile value（via grep -A in result file frontmatter `profile_source`）。

理由：

- Fake HOME isolation 與 setup skill test pattern 一致
- 5 scenario for config.sh × producer-side scenario 為 v0.1 minimal coverage
- e2e `with-profile` 為 Layer 3 minimum — 只 1 scenario 而非 10（4 fields × 各 source = 12）— focus on backward compat invariant + project override 是 v0.1 user value 80/20

Alternatives:

- 不用 fake HOME、直接寫 real `~/.codex-pro/`：cross-machine pollution、CI flaky
- 抽 shared lib/profile-fixture.sh：與 D4 一致、本 cycle 接受 inline duplication

## Implementation Contract

#### Behavior

User 在 codex-pro repo 跑：

- `/codex-pro:config` → 印 4-row markdown table（field / resolved value / source）+ 2 行 profile file 存在性
- `/codex-pro:review` 等 producer → Step 4 自動 resolve profile + 跑 codex-call with profile value

#### Interface

- `/codex-pro:config` — read-only consumer skill、zero argument、output stdout markdown table + 2 行 profile file 存在性
- `~/.codex-pro/profile.yaml` — global profile YAML（optional）
- `<cwd>/.codex-pro/profile.yaml` — project profile YAML（optional、cwd = invocation 時的 working directory）
- Schema v0.1：`model: <string>` / `effort: <string>` / `max_time: <int>` / `focus_default: <string>`
- Producer skill Step 4 invocation 從 profile resolve `--model` / `--effort` / `--max-time` value、adversarial-review 額外 resolve `focus_default`

#### Failure modes

- Profile file missing：silent fallback to next layer (project missing → global) or defaults
- Profile YAML malformed：silent fallback to defaults（v0.1 容錯、不 fail）
- Profile contains unknown field：v0.1 silent ignore
- Profile field type mismatch（e.g. `max_time: "abc"`）：v0.1 silent fallback to default for that field

#### Acceptance criteria

- `/codex-pro:config` 跑 with both profile missing → output 4 row 全 `(default)` + 2 行 file `(does not exist)`
- `/codex-pro:config` 跑 with project profile `{max_time: 1200}` → output max_time row 顯示 `1200 / project`、others `(default)`
- review / rescue / adversarial-review SKILL.md Step 4 body 含 inline `python3 -c` profile read pattern、`HOME` env var + cwd `.codex-pro/profile.yaml`
- 3 producer SKILL.md frontmatter description 含 v0.x → v0.y bump marker（review v0.3、rescue v0.2、adversarial-review v0.3）
- result file frontmatter optional `profile_source` field（enum default / global / project / mixed）
- adversarial-review `focus_default` value used when no `--focus` arg supplied
- `/codex-pro:config` SKILL.md grep `codex-call` = 0、`codex exec` = 0、`mkdir` = 0
- `tests/config.sh` 跑 5 behavioral scenario + ~10 structural = ~25 assertion 全綠
- `tests/review.sh` + `tests/rescue.sh` + `tests/adversarial-review.sh` 各加 ~10 assertion（v0.x marker + profile scenario）
- `tests/run.sh` aggregate ~370 / 0 fail / 10 layers green（9 + config）
- `plugin.json` 版 0.5.0
- `tests/e2e.sh` 加 `with-profile` scenario、跑 12 組合（5 scenario × 2 producer + with-profile × 2 producer）
- Pre-archive smoke：3 producer 各跑 1 real codex-call on profile-set fixture、verify codex-call invocation 用 profile value

#### Scope boundaries

In scope:

- 1 new SKILL.md (config) + spec
- 3 producer SKILL.md Step 4 modification + spec MODIFIED
- 5 test file modification (config.sh new + 3 producer extension + e2e.sh + e2e-fixtures.sh)
- CLAUDE.md / README.md update
- plugin.json bump
- 3 producer smoke gate

Out of scope:

- batch / sandbox / max_findings
- retry / backoff / timeout-per-skill config
- profile schema version field
- profile inheritance / env vars / multi-profile
- JSON Schema spec / encryption
- setup profile-check
- GUI / interactive edit
- Windows / fail-fast 4 class / result file H2 structure changes
- e2e × 4 source × 3 producer matrix (only 1 `with-profile` e2e scenario per skill, total +2 combos)

## Risks / Trade-offs

- [Profile YAML parse 用 inline regex 而非 import yaml] → 限制 schema 表達力（nested struct / array 無法用）。Mitigation: v0.1 schema 全 flat key-value、regex 足夠；future schema 升 nested 時改用 `import yaml`（python3 stdlib 不含 PyYAML、需 `pip install` — 那時評估 trade-off）。
- [Silent fallback on malformed profile] → user 寫錯 YAML 不報錯、跑出 default 行為 surprise。Mitigation: `/codex-pro:config` 顯示 resolved source、user 跑 config 看到 source = default 就知道「我 profile 沒生效」；v0.2 加 schema validation skill 評估 strict mode。
- [Backward compat for v0.4 result files in /codex-pro:status / :result] → v0.4 result file 沒 `profile_source` field、status display 此欄需 fallback。Mitigation: status / result skill 視 `profile_source` 為 optional、missing → row 顯示 `(n/a)`；不 break v0.4 file。
- [3 producer 同時改 + plugin minor bump 大] → cycle 大、blast radius 高。Mitigation: 100% backward compat（無 profile 行為 identical）；Layer 2 behavioral test 各 producer 加 fixture；3 producer pre-archive smoke gate 全跑（已 budget）。
- [Profile location `<cwd>/.codex-pro/profile.yaml` 在 .gitignore 內] → user commit profile.yaml 到 repo 才能跨 maintainer 分享、但 `.codex-pro/` gitignored。Mitigation: v0.1 nature: profile 是 local config（非 repo policy）— 跟 vscode settings.json 同性質、推薦 commit-out；user 若想 share project profile、自己 `git add -f .codex-pro/profile.yaml`；future cycle 評估搬到非 ignored path（如 `.codex-pro.yaml` repo root）。
- [`focus_default` for review / rescue silent-ignored may confuse user] → user 寫 `focus_default: security` 在 profile、發現 review 沒用此 field。Mitigation: `/codex-pro:config` 顯示 focus_default value、user 看得到；SKILL.md 文檔說「focus_default 只 adversarial-review 使用」；v0.2 評估 per-field-applicability mapping。
- [Schema 沒 version field、未來改 schema 困難] → v0.2 改 schema 時無法區分 v1 vs v2 YAML。Mitigation: v0.2 加 `version:` field 時 default `1`（migration friendly）；v0.1 silent ignore unknown field 已 forward-compat。
- [Layer 3 e2e `with-profile` scenario 增加 quota cost] → 12 vs 10 combinations = +20% quota per Layer 3 pass。Mitigation: Layer 3 是 opt-in release gate、user 可選擇跳過 `with-profile`；documented 在 checklist；v0.2 評估更高解析度的 profile e2e matrix。
- [SKILL.md inline python3 -c 重複代碼 in 3 producer] → 維護成本（改 schema 要動 3 處）。Mitigation: D4 已論證 SKILL.md self-contained 是 codex-pro pattern；schema 改機率低（v0.1 → v0.2 加 max_findings 才會動）；future 可抽 shared helper 如有需要。
- [profile_source aggregate enum 失去 per-field detail] → user 看 frontmatter 不知 max_time 來自 global 還是 project。Mitigation: `/codex-pro:config` 看 per-field 詳情；frontmatter aggregate enum 為 v0.1 minimal；v0.2 評估擴 per-field 後 sub-keys。
- [Pre-archive smoke gate 3 producer 各跑 = 3 real codex-call quota] → 比 diff-untracked-fix（2 producer × 1 = 2 quota）成本高 50%。Mitigation: producer skill modification 紀律標準（[[feedback-codex-pro-smoke-before-archive]]）；quota cost 接受、release 紀律不打折。
