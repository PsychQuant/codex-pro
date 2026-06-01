---
name: cancel
description: |
  informational only — codex-pro v0.2 為 stateless single-shot model、無 background job 可 cancel。本 skill 輸出 explainer + 3 remediation lines、永不 error、永不 mutate disk、永不 signal any process。
  與 status / result / setup 同屬 read-only consumer category — 本 skill 屬 stdout-only informational subtype。Drop-in 對應上游 codex-plugin-cc /codex:cancel、但因 codex-pro stateless model 而為 displayed limitation 而非 silent stub。
  零 argument acceptance（任何 argument 都印 usage 但仍 exit 0、因為 cancel 永不為 error）。
  Trigger keywords: cancel codex-pro, cancel run, abort review, 取消, codex-pro cancel
allowed-tools:
  - Bash
---

# /codex-pro:cancel — Informational Only (v0.2 stateless limitation)

**informational only** — codex-pro v0.2 為 stateless single-shot model：每個 `/codex-pro:review` / `:rescue` / `:adversarial-review` invocation 都是 synchronous HTTPS round-trip to Codex HTTP wrapper、無 background job、無 persistent PID、無 upstream chatgpt.com/backend-api cancel API。**沒有東西可以給本 skill cancel**。

本 skill 為 stdout-only informational explainer + 3 條 remediation：不殺 PID、不送 HTTPS、不寫任何 file、不建立 `.codex-pro/`、不 signal 任何 process。Output deterministic（同 invocation 永遠 byte-identical），讓 user 一眼認出這是 known displayed limitation 而非 transient failure。

## 行為原則（4 條紀律）

本 skill 嚴守 codex-pro **read-only informational** 紀律 — 比 status / result 更嚴：

1. **無 Codex HTTP wrapper 呼叫**：完全不送 HTTPS request、零 Codex quota cost
2. **無 Codex CLI subprocess**：完全不 spawn 任何 codex 相關 subprocess（與 batch 的 mutating exception 對比）
3. **無 process signal**：不執行任何 process termination 命令、不發送任何 termination signal（不對任何 PID 動作；因為 codex-pro v0.2 沒有可被 signal 的 background process）
4. **無 file mutation**：不建立目錄、不寫任何 file、stdout-only；甚至不讀取 `.codex-pro/`（cancel 與 `.codex-pro/` 完全解耦）

**任何 argument 都 exit 0**：cancel 永不為 error。給 PID / job ID / flag、skill 印 usage hint 提醒「本 skill 為 informational only、零 argument」、但仍 `exit 0`。這個設計避免 user shell script 內 `set -e` 因 cancel 跳 trap。

## Output 契約（deterministic byte-identical）

本 skill 每次跑都 print **exactly** 以下文字到 stdout、然後 exit 0：

```
codex-pro cancel — informational only

codex-pro v0.2 is single-shot stateless: each /codex-pro:review / :rescue /
:adversarial-review invocation is a synchronous HTTPS round-trip to the Codex
HTTP wrapper, with no background job, no persistent PID, and no upstream
cancel API on chatgpt.com/backend-api. There is nothing for /codex-pro:cancel
to terminate.

If you need to abort a running invocation, choose one:

  1. Press Ctrl-C in the Claude Code session — Claude aborts the bash call
     that runs the Codex HTTP wrapper.
  2. Wait for the --max-time 600 hard timeout (10 minutes). The invocation
     will fail-fast with frontmatter `error: timeout`.
  3. Future codex-pro v0.3+ may add a background job mode; if so, this skill
     will be re-implemented to actually cancel a job. Until then, this is a
     displayed limitation.

This message is not an error. exit 0.
```

Output deterministic — bytes 永遠相同。Claude Code 在 SKILL.md 內可用 heredoc / printf 直接寫死、bash function 或 inline command 印出。**No template expansion / no env var interpolation / no timestamp 等動態元素**。

## 與 status / result 的對比

| 面向 | `/codex-pro:status` | `/codex-pro:result` | `/codex-pro:cancel` |
|---|---|---|---|
| Mental model | list summary | detail display | informational limitation |
| File ops | scan `.codex-pro/*.md` | read single file | 不讀 `.codex-pro/`（解耦）|
| Argument | optional `--skill <name>` | 位置 / `--latest [<skill>]` | 零 argument（給也 exit 0）|
| Exit code | 0 (informational) | 0 / 非 0 (fail-fast) | **永遠 0** |
| Mutation | 無 | 無 | 無 |
| Process signal | 無 | 無 | 無（紀律 #3）|

三 skill 同屬 codex-pro **read-only consumer category** — 與 setup（read-only environment）+ review/rescue/adversarial-review（mutating producer）+ batch（mutating exception）區隔。Cancel 是 read-only category 內最嚴格的 subtype：stdout-only informational、零 file ops、零 process signal、deterministic output、永遠 exit 0。

## Drop-in 對應上游 codex-plugin-cc

上游 codex-plugin-cc 有 `/codex:cancel` row。codex-pro v0.2 stateless model 下無法真 cancel — 但**不採 silent stub return**（會重演 #324 痛點）、改採 **displayed limitation** 路線：

- 顯式列出三條 remediation = user 自助力強、有 actionable next step
- Exit 0 因為「informational only」非「failure」
- Future v0.3+ 若推 background job mode、本 skill restore 為 real cancel

drop-in 命令名為 user 轉場降低成本、行為誠實表達 architectural constraint。
