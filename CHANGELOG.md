# Changelog

## 0.8.0 — 2026-08-10

Issue: [#10](https://github.com/PsychQuant/codex-pro/issues/10)

- 新增可由 Codex CLI／App 安裝的原生 plugin manifest 與 self-hosted repository marketplace。
- 從 Claude Code skill 來源單向生成 repo 根層與 `.codex/` 兩個完整 bundle；兩份均含九個 skills、nested resources、shared references、runtime 與 ownership inventory。
- 分發具 commit／blob／SHA-256 provenance 的 `codex-call` snapshot，以及在任何 OAuth 或網路動作前驗證平台、Swift、mode 與雜湊的 `codex-pro-call` wrapper。
- Codex producer 改由 active `SKILL.md` 位置解析 bundled wrapper，native bundle 損壞時 fail-closed；Claude Code 版維持 PATH 相容性。
- 同步 Codex manifest、Claude plugin 與 Claude marketplace 版本為 0.8.0，並新增 plugin、runtime、resolver、bundle parity 與安裝 smoke release gates。
- README 明載 macOS＋Swift、OAuth refresh side effect、private backend、上游已知限制、consumer availability、官方 directory 外部步驟與 rollback。
- Producer skill 的 runtime 前置檢查失敗不再 `exit 1` 中止，改為設定 `CODEX_RUNTIME_ERROR` 後跳過 `codex-call`、OAuth 與網路存取，並照既有 result schema 寫入結構化 failure result；失敗分 `package_corruption` 與 `runtime_unavailable` 兩類，皆不 retry。此前 runtime 損壞會在不產生 result file 的情況下中止，屬 silent failure。
- `codex-pro-call` 改用固定路徑 `/usr/bin/swift`（不再經 `command -v` 受 `PATH` 影響），並拒絕 symlink 形式的 runtime。
- Bundle 完整性邊界收斂：各 SKILL.md 的 runtime 解析、generator 的 wrapper 解析與 bundle subtree 檢查一律拒絕 symlink，subtree 必須為實際目錄；generator 的產出路徑檢查改為偵測 parent 目錄含 symlink 即報錯（原先先 `resolve()` 再比對 common path，可被 symlink 繞過）。
- Test dispatcher 改為 fail-closed：assertion layer 缺少可解析的 summary 時直接計為失敗，不再回退到 exit code 判定。此前空的或被截斷的 test script 可以 `exit 0`，讓缺席的 release gate 顯示為 passing layer。

### 已知限制

- Producer runtime 目前只支援 macOS；Linux／Windows producer 不在本版範圍。
- Vendored snapshot 保留 `parallel-ai-agents` [#28](https://github.com/PsychQuant/parallel-ai-agents/issues/28) 的 SSE UTF-8／CJK 問題與 [#35](https://github.com/PsychQuant/parallel-ai-agents/issues/35) 的外部契約限制。
- `$codex-batch` 仍是 `codex exec --full-auto` subprocess 例外，未改寫為 bundled runtime。
- 尚未宣稱已通過 OpenAI 官方 plugin directory 審核；0.8.0 先提供 self-hosted marketplace。

## Earlier changes

0.7.0 與更早版本的詳細變更紀錄保留在 [`changelog/`](./changelog/)。
