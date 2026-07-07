# Layer 3 — e2e checklist for codex-pro

Layer 3 = Claude 跑 SKILL.md prose 真正觸發 codex-call。補 Layer 2 的 SKILL.md→runtime drift blind spot（Layer 2 跑 test-script 自 implement 的 mock；Layer 3 跑 Claude 解讀 SKILL.md 的 real invocation）。

**兩種跑法**：自動化 `bash tests/e2e.sh`（preferred）+ manual checklist（plugin install 等 UI flow）。

跑前先確保 Layer 1 + 2 通過：

```bash
cd <codex-pro repo root>
bash tests/run.sh
```

## Automated Layer 3 — `bash tests/e2e.sh`

`tests/e2e.sh` 在 fresh `claude --print --plugin-dir` session 觸發 SKILL.md、verify result file 結構 + behavioral marker。6 scenario × 2 producer skill = 12 組合（v0.5 加 `with-profile`：project profile `effort: high` → 驗 result frontmatter `effort: high` + `profile_source: project|mixed`，證實 profile 被 resolve 並流入 codex-call invocation）。

**Quota budget**：
- 每組合 = 1 codex-call quota + ~50k Claude API tokens + 60-180s
- 完整 12 組合 = ~12 codex-call + ~600k Claude API tokens + 12-36 min + ~$0.6-$2.4

**Rate limit recovery**：
- `tests/e2e.sh` 內建 retry — 觀察到 stdout 含 `Server is temporarily limiting requests` 字串時自動 sleep 30s/60s/120s exponential backoff、最多 3 次 retry
- 若 3 次仍 throttle、script exit 4；user 手動 wait 5min 後重跑該組合
- Codex-call 本身的 fail-fast (rate_limit / oauth_invalid / timeout / target_invalid) 是 valid e2e 結果、不 retry

跑 12 組合（建議分次跑、便於 spot regression）：

```bash
# Review × 6 scenarios
bash tests/e2e.sh --skill review --scenario mixed
bash tests/e2e.sh --skill review --scenario binary
bash tests/e2e.sh --skill review --scenario oversize
bash tests/e2e.sh --skill review --scenario empty-repo
bash tests/e2e.sh --skill review --scenario all-empty
bash tests/e2e.sh --skill review --scenario with-profile

# Adversarial-review × 6 scenarios
bash tests/e2e.sh --skill adversarial-review --scenario mixed
bash tests/e2e.sh --skill adversarial-review --scenario binary
bash tests/e2e.sh --skill adversarial-review --scenario oversize
bash tests/e2e.sh --skill adversarial-review --scenario empty-repo
bash tests/e2e.sh --skill adversarial-review --scenario all-empty
bash tests/e2e.sh --skill adversarial-review --scenario with-profile
```

完整 matrix 通過後算 release gate clear。10/10 PASS 是目標、acceptable 1-2 個因偶發 rate limit / codex quota 個別 fail 需 retry。

## Manual Layer 3 — UI Flow Checklist

跑完 `tests/run.sh` 與 automated `tests/e2e.sh` 全綠後，再走以下 manual checklist（covering plugin install UI flow）。每項打勾代表你親自在 fresh Claude Code session 觀察到該行為。

## Preconditions

- [ ] **Layer 1+2 已綠**：跑完 `bash tests/run.sh` 顯示 0 fail / exit 0
- [ ] **Layer 3 automated 已綠**：跑完 `bash tests/e2e.sh` 12 組合全 PASS（或 acceptable 1-2 個個別 rate-limit fail 已 retry pass）

## A. Plugin install path（正規 marketplace 路徑）

- [ ] **Marketplace add**：在新 Claude Code session 跑 `/plugin marketplace add psychquant/codex-pro`（GitHub source；或 `/plugin marketplace add <local repo path>` 走 local dev）。預期：marketplace `codex-pro` 出現在 `/plugin` 命令清單。

- [ ] **Plugin install**：跑 `/plugin install codex-pro@codex-pro`。預期：plugin `codex-pro` 顯示為 installed、`/help` 列出 `/codex-pro:codex-setup` 與 `/codex-pro:codex-batch` 兩個 skill。

## B. Setup skill（已落地）

- [ ] **Setup ready 全綠**：在 OAuth token、codex-call、plugin manifest 三者就緒環境下跑 `/codex-pro:codex-setup`。預期：輸出 3 列 markdown 表格、3 個 Status 全 ✓、摘要含字串 `ready`。

- [ ] **Setup 缺 OAuth 報 codex login**：暫時 rename `~/.codex/auth.json` → `~/.codex/auth.json.bak`，再跑 `/codex-pro:codex-setup`。預期：OAuth 列 Status ✗、Remediation 文字含 `codex login`；摘要含 `need attention`。**測完還原檔名**。

- [ ] **Setup 為 read-only**：B 段的兩次跑 setup 前後，跑 `ls -la ~/.codex/` 比對。預期：除了你自己改檔名造成的差異外，目錄內容無 setup 引入的 mutation。

## C. Batch skill（已落地、含 Design constraint #1 exception）

- [ ] **Batch 觸發**：跑 `/codex-pro:codex-batch`（不帶參數）。預期：skill 開始向你詢問 5 個 required parameters — Reference file、Chunks、Prompt template、Output directory、optional model / reasoning effort 等。

- [ ] **Batch 跑完不污染 codex-pro**：用一個 fake reference + 短 chunk list 跑一輪 batch（output dir 指向 `/tmp/` 內某 fake dir）。預期：plugin 內檔案無變動、output 寫到 `/tmp/` 你指定的位置。**測完清理 /tmp/ 內產物**。

## D. Dev-test path（不裝 marketplace、純 --plugin-dir）

- [ ] **Sub-plugin dev-test**：開另一個 Claude Code session 用 `claude --plugin-dir <repo>/plugins/codex-pro`（從你 clone 的 codex-pro 目錄）。預期：載入後 `/codex-pro:codex-setup` 與 `/codex-pro:codex-batch` 都可觸發，行為與 marketplace install 路徑一致。

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
