# Layer 3 — Manual e2e checklist for codex-pro

跑前先確保 Layer 1 + 2 通過：

```bash
cd <codex-pro repo root>
bash tests/run.sh
```

跑完 `tests/run.sh` 全綠後，再走以下 manual checklist。每項打勾代表你親自在 fresh Claude Code session 觀察到該行為。

## Preconditions

- [ ] **Layer 1+2 已綠**：跑完 `bash tests/run.sh` 顯示 0 fail / exit 0（這是進入 e2e 的前置）

## A. Plugin install path（正規 marketplace 路徑）

- [ ] **Marketplace add**：在新 Claude Code session 跑 `/plugin marketplace add psychquant/codex-pro`（GitHub source；或 `/plugin marketplace add <local repo path>` 走 local dev）。預期：marketplace `codex-pro` 出現在 `/plugin` 命令清單。

- [ ] **Plugin install**：跑 `/plugin install codex-pro@codex-pro`。預期：plugin `codex-pro` 顯示為 installed、`/help` 列出 `/codex-pro:setup` 與 `/codex-pro:batch` 兩個 skill。

## B. Setup skill（已落地）

- [ ] **Setup ready 全綠**：在 OAuth token、codex-call、plugin manifest 三者就緒環境下跑 `/codex-pro:setup`。預期：輸出 3 列 markdown 表格、3 個 Status 全 ✓、摘要含字串 `ready`。

- [ ] **Setup 缺 OAuth 報 codex login**：暫時 rename `~/.codex/auth.json` → `~/.codex/auth.json.bak`，再跑 `/codex-pro:setup`。預期：OAuth 列 Status ✗、Remediation 文字含 `codex login`；摘要含 `need attention`。**測完還原檔名**。

- [ ] **Setup 為 read-only**：B 段的兩次跑 setup 前後，跑 `ls -la ~/.codex/` 比對。預期：除了你自己改檔名造成的差異外，目錄內容無 setup 引入的 mutation。

## C. Batch skill（已落地、含 Design constraint #1 exception）

- [ ] **Batch 觸發**：跑 `/codex-pro:batch`（不帶參數）。預期：skill 開始向你詢問 5 個 required parameters — Reference file、Chunks、Prompt template、Output directory、optional model / reasoning effort 等。

- [ ] **Batch 跑完不污染 codex-pro**：用一個 fake reference + 短 chunk list 跑一輪 batch（output dir 指向 `/tmp/` 內某 fake dir）。預期：plugin 內檔案無變動、output 寫到 `/tmp/` 你指定的位置。**測完清理 /tmp/ 內產物**。

## D. Dev-test path（不裝 marketplace、純 --plugin-dir）

- [ ] **Sub-plugin dev-test**：開另一個 Claude Code session 用 `claude --plugin-dir <repo>/plugins/codex-pro`（從你 clone 的 codex-pro 目錄）。預期：載入後 `/codex-pro:setup` 與 `/codex-pro:batch` 都可觸發，行為與 marketplace install 路徑一致。

## Post-test cleanup checklist

- [ ] B 段的 `~/.codex/auth.json` rename **已還原**（你應該看到原檔再次存在）
- [ ] C 段的 `/tmp/` 內 fake output 已清乾淨
- [ ] `bash tests/run.sh` 再跑一次仍綠（確認 e2e 過程沒污染 repo）

---

**何時需要跑這份 checklist？**

- 重大 namespace change 之後（例如又一輪 consolidate-naming-like 改動）
- 新增 skill 之後（review、rescue、jobs-* 等未來 capability）
- Plugin 重大重組（marketplace.json schema 變化等）
- 對外發布前（推 GitHub / 廣告 marketplace）

日常 dev iterate 不需要每次跑這份 — Layer 1+2 自動化已 cover artifact 與行為正確性，e2e 是「最後一公里」UI 確認。
