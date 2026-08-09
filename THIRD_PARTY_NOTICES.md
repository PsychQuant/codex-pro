# Third-Party Notices

## `codex-call`

codex-pro 分發一份來自
[`PsychQuant/parallel-ai-agents`](https://github.com/PsychQuant/parallel-ai-agents)
的 `codex-call` 原始碼 snapshot：

- 上游 commit：`6fc6883ef1d655f5f782a97accc0a5adacc76226`
- 上游路徑：`plugins/parallel-ai-agents/bin/codex-call`
- Copyright (c) 2026 Che Cheng
- 授權：MIT

MIT 的著作權與許可聲明已完整收錄於本 repository 的 [`LICENSE`](LICENSE)。
snapshot 保持逐位元不變；來源、Git blob、大小與 SHA-256 記錄於
[`plugins/codex-pro/references/codex-call-provenance.json`](plugins/codex-pro/references/codex-call-provenance.json)。
Claude marketplace 只封裝 `plugins/codex-pro/` 子目錄，因此該套件另帶一份
完整 [`LICENSE`](plugins/codex-pro/LICENSE) 與
[`THIRD_PARTY_NOTICES.md`](plugins/codex-pro/THIRD_PARTY_NOTICES.md)，不依賴
repository 根層檔案才具備授權聲明。

此 snapshot 會繼承上游已知問題 #28 與 #35，且使用未承諾穩定的 ChatGPT backend
介面；納入本 repository 不代表該 runtime 已成為穩定的公開 API。
