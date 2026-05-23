## 1. Skill artifact 建立

- [x] 1.1 建立 SKILL.md（D1: Command → Skill 轉型策略）：產出 `plugins/codex-pro/skills/batch/SKILL.md`，內容自 psychquant-claude-plugins 內 codex-batch 的 `commands/codex-batch.md` 轉型；frontmatter 設 `name: batch`、`description` 沿用原 description 多行 block、`argument-hint` 沿用、`allowed-tools` 沿用（含 Bash）；body 內 trigger / 範例段改提 `/codex-pro:batch`。驗證 **Batch skill registration and parameter collection** — python3 parse YAML frontmatter 確認 `name=batch`、`description` 存在含 "batch generate" / "codex batch" 等 trigger keyword、`allowed-tools` 含 Bash。
- [x] 1.2 搬 script-template.sh byte-identical（D2: References sha256-identical copy）：cp psychquant-claude-plugins 內 codex-batch 的 `references/script-template.sh` 到 `plugins/codex-pro/skills/batch/references/script-template.sh`。驗證 **Batch script generation uses bundled template** — `shasum -a 256` 對 source 與 dest 輸出相同 hash；dest 含 `codex exec --full-auto` 命令字串。
- [x] 1.3 SKILL.md body 標示 explicit exception（D3: Design constraint #1 採 explicit exception 標示）：在 batch SKILL.md body 加一段註記「本 skill 為 codex-pro 既有 Design constraint #1 (No subprocess spawn for Codex) 的 explicit exception；理由：fan-out parallel codex exec 是 shell job control 的天然用法、與 upstream #330 IPC pipe deadlock 為不同類別問題；其他 skill 不引用此為 precedent」。驗證 **Parallel job orchestration via subprocess** scenario 之 explicit exception 紀律 — grep `exception` 與 `constraint` 字串於 SKILL.md body 至少各 1 次。

## 2. Source plugin 清理

- [x] 2.1 刪除 source plugin 目錄（D4: 原 plugin 採 hard delete）：移除 psychquant-claude-plugins 內整個 codex-batch plugin 目錄（含 `.claude-plugin/`、`commands/`、`references/`、`CHANGELOG.md`）。驗證：對該目錄跑 ls 應失敗或回空（目錄不存在）。
- [x] 2.2 同步 source marketplace.json（D5: 外部 marketplace 與 codex-pro 的清理同步）：psychquant-claude-plugins 的 marketplace.json 若 plugins[] 含 codex-batch entry 則移除。驗證：python3 parse 該 marketplace.json，遍歷 plugins[] 確認無 `name=="codex-batch"` 條目；若原本就無 entry，記錄為 no-op 並過。

## 3. Doc 更新

- [x] 3.1 更新 codex-pro CLAUDE.md：Commands surface 表加 `/codex-pro:batch` 列（描述含 `codex exec --full-auto`、parallel batch、non-read-only 行為）；Marketplace structure 段 skills 列表加 batch 條目。驗證：grep `/codex-pro:batch` CLAUDE.md ≥ 1 次；grep `batch` 於 Marketplace structure 段 ≥ 1 次（指 batch skill 列）。
- [x] 3.2 更新 codex-pro README.md：Skills 表加 batch 列（含 codex exec 平行批次描述、明寫非 read-only 與 setup 區別）。驗證：grep `batch` README.md Skills 段 ≥ 1 次；同時 grep `codex exec` README.md ≥ 1 次（描述觸發 codex CLI subprocess）。

## 4. 端到端驗收

- [x] 4.1 skill registration simulation（驗證 **Batch skill registration and parameter collection** 的 "Skill is discoverable after plugin install" scenario）：用 python3 解析 `plugins/codex-pro/skills/batch/SKILL.md` 的 YAML frontmatter，確認 `name=batch`、`description` block 存在、`allowed-tools` 列表含 Bash；同步用 grep 確認 body 含 trigger keyword（"batch generate" / "codex batch" 之一）。
- [x] 4.2 template integrity simulation（驗證 **Batch script generation uses bundled template** 的 "Template file accompanies skill" 與 "Generated script matches template structure" scenarios）：`shasum -a 256` 對 source plugin 內 script-template.sh 與 dest 兩端比對一致；同步 grep `codex exec --full-auto` 與 `wait` 於 dest template 確認 fan-out parallel orchestration 邏輯保留。
