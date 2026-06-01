---
name: status
description: |
  列出 .codex-pro/ 內所有 producer skill（review / rescue / adversarial-review）的 result file 並輸出 markdown table summary。Read-only consumer category — 純掃目錄 + parse frontmatter、無 Codex HTTP wrapper 呼叫、無 subprocess、無 file mutation。
  與 review / rescue / adversarial-review 的 mutating producer 對比、與 setup（read-only environment check）同屬 read-only category。Triple skill set 之一（status + result + cancel）對應上游 codex-plugin-cc /codex:status drop-in surface。
  支援 --skill <review|rescue|adversarial-review> filter 看單一 producer。Missing / empty .codex-pro/ 為 informational case（exit 0 不算 error）。
  Trigger keywords: list result files, review history, 過去結果, 狀態, observability, codex-pro status, list .codex-pro
allowed-tools:
  - Bash
  - Read
---

# /codex-pro:status — List `.codex-pro/` Result Files (v0.1 read-only consumer)

掃 `.codex-pro/*.md` producer output、parse YAML frontmatter、輸出 markdown table summary。本 skill 是 codex-pro 第 7 個 user-facing capability、屬 **read-only consumer category**（與 setup 同類）— 純檔案讀取、無 Codex HTTP wrapper / 無 subprocess for Codex / 無 disk mutation。

## 行為原則

本 skill 嚴守 codex-pro **read-only category** 紀律：

- **無 Codex HTTP wrapper 呼叫**：不送 HTTPS request、不耗 Codex quota
- **無 Codex CLI subprocess**：與 batch 的 mutating exception 對比、status 完全不 spawn 任何 codex 相關 subprocess
- **無 file mutation**：不建立 `.codex-pro/` 目錄、不寫任何 file、stdout-only
- **無外網 call**：純本機 file ops、純 Bash + Read + python3 parse

與 review / rescue / adversarial-review 的 mutating producer category 對比、與 batch 的 mutating exception 對比、status 屬 read-only consumer category — 與 setup（read-only environment check）並列。Future skill design：read-only / mutating-producer / mutating-exception 三軸區隔對 user 表達「我跑這 skill 會不會動 disk / 燒 quota」是 mental model 必備 affordance。

## Step 1: Scan `.codex-pro/*.md`

用 Bash 掃 `.codex-pro/` 內所有 `*.md` 檔（不遞迴、不含 dotfile）：

```bash
if [ ! -d ".codex-pro" ]; then
  STATE="missing"
elif [ -z "$(ls -A .codex-pro/*.md 2>/dev/null)" ]; then
  STATE="empty"
else
  STATE="populated"
  # find with -maxdepth 1 避免遞迴；用 sort 拿 deterministic 順序
  FILES=$(find .codex-pro -maxdepth 1 -name '*.md' -type f | sort)
fi
```

若 user 給 `--skill <name>` flag、filter prefix：

```bash
case "$SKILL_FILTER" in
  review|rescue|adversarial-review)
    FILES=$(printf '%s\n' "$FILES" | grep -E "/${SKILL_FILTER}-[0-9]")
    ;;
  "")
    : # no filter
    ;;
  *)
    echo "Error: --skill must be one of: review, rescue, adversarial-review" >&2
    exit 2
    ;;
esac
```

## Step 2: Parse frontmatter per file

對每個 file、用 inline python3 拆 YAML frontmatter（`---` ... `---` 包圍區段）、抽 6 個 field（target / task_description / findings_count / outcome / focus / error）。容忍缺漏（render `—` em dash）、容忍 malformed YAML（該 row `outcome summary` 顯示 `(unparseable frontmatter)`、不阻塞其他 row）：

```bash
python3 - "$FILES" <<'PY'
import sys, re, os
files = sys.stdin.read().splitlines()
for path in files:
    if not path: continue
    fname = os.path.basename(path)
    # skill type by filename prefix
    if fname.startswith("review-"): skill = "review"
    elif fname.startswith("rescue-"): skill = "rescue"
    elif fname.startswith("adversarial-review-"): skill = "adversarial-review"
    else: skill = "—"
    # parse frontmatter
    try:
        content = open(path).read()
        m = re.match(r'^---\n(.*?)\n---\n', content, re.DOTALL)
        if not m:
            print(f"| {fname} | {skill} | — | (unparseable frontmatter) | — | — |")
            continue
        fm = m.group(1)
        target = re.search(r'^target:\s*(.+)$', fm, re.MULTILINE)
        task = re.search(r'^task_description:\s*(.+)$', fm, re.MULTILINE)
        findings = re.search(r'^findings_count:\s*(\d+)', fm, re.MULTILINE)
        outcome = re.search(r'^outcome:\s*(\w+)', fm, re.MULTILINE)
        error = re.search(r'^error:\s*(\w+)', fm, re.MULTILINE)
        # column derivation
        target_or_task = (target.group(1).strip() if target else
                          (task.group(1).strip()[:50] if task else "—"))
        if skill == "review": outcome_summary = f"{findings.group(1)} findings" if findings else "—"
        elif skill == "rescue": outcome_summary = outcome.group(1) if outcome else "—"
        elif skill == "adversarial-review": outcome_summary = "4/4 sections"
        else: outcome_summary = "—"
        # timestamp from filename ISO8601 portion
        ts_match = re.search(r'-(\d{8}T\d{6}Z?)', fname)
        ts = ts_match.group(1) if ts_match else "—"
        if ts != "—" and len(ts) >= 13:
            ts = f"{ts[:4]}-{ts[4:6]}-{ts[6:8]} {ts[9:11]}:{ts[11:13]}"
        err = error.group(1) if error else "—"
        print(f"| {fname} | {skill} | {target_or_task} | {outcome_summary} | {ts} | {err} |")
    except Exception:
        print(f"| {fname} | {skill} | — | (unparseable frontmatter) | — | — |")
PY
```

Frontmatter heterogeneity 設計選擇：union 欄位、缺漏 `—`、不強行 schema validation（producer schema 演進不破 consumer）。

## Step 3: Emit markdown table

`STATE="populated"` 時、先印 table header 再 cat python3 output：

```
| filename | skill type | target / task | outcome summary | timestamp | error |
| --- | --- | --- | --- | --- | --- |
<rows from Step 2>
```

Columns 順序固定：filename / skill type / target / task / outcome summary / timestamp / error。Markdown table format（pipe-separated、column-aligned）— Claude Code REPL 看 markdown render、可直接 copy 進 dogfooding 紀錄。

## Step 4: Handle missing / empty `.codex-pro/`

`STATE="missing"`：

```
.codex-pro/ not yet created — any producer skill (/codex-pro:review, /codex-pro:rescue,
/codex-pro:adversarial-review) creates it on first run.
```

`STATE="empty"`：

```
No result files found in .codex-pro/.
Run /codex-pro:review, /codex-pro:rescue, or /codex-pro:adversarial-review to produce one.
```

兩 case 都 exit 0（informational、不算 error）。**Skill 不建立 `.codex-pro/` 目錄**（read-only 不可 side-effect 建目錄）— 即使目錄不存在也只是印 informational 訊息、不嘗試建。

## 與 setup 的對比 + read-only category 定位

| 面向 | `/codex-pro:setup` | `/codex-pro:status` |
|---|---|---|
| Category | read-only environment | read-only consumer |
| 看什麼 | `~/.codex/auth.json` + Codex HTTP wrapper PATH | `.codex-pro/*.md` producer output |
| Argument | 無 | optional `--skill <name>` filter |
| Output | env check result（OK / fail） | markdown table summary |
| Mutating | 無 | 無 |
| Codex HTTP wrapper invocation | 無 | 無 |

兩 skill 同屬 codex-pro **read-only category** — 與 review / rescue / adversarial-review 的 mutating producer 對比、與 batch 的 mutating exception 對比。read-only category 為 v0.3 起的 mental model 轉軸：user 一眼看出「我跑這 skill 會不會動 disk / 燒 quota」。
