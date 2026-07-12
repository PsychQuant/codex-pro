## Summary

把 review skill Step 3 system instructions 從 prose 名詞（"a Summary" / "a Findings list"）改寫為 literal-token 寫法（命名 `## Summary` / `## Findings` H2 與 `### Finding N:` H3），並在實證觀察全綠後把 e2e 的 heading 檢查從 warn 升級為 hard assertion — 解 GitHub issue #1。

## Motivation

review 的 result-file 契約與 e2e 驗證都預期 literal `## Summary` / `## Findings` H2 token，但 Step 3 送給 codex-call 的 instructions 只用 prose 名詞描述結構，從未命名 literal token — Codex 因此可以輸出 `Summary:`、`### Summary` 或整段省略而仍滿足 prose 指示。tests/e2e.sh 為此把 heading 檢查降為 verify_substring_warn（best-effort 警告、不 fail），導致 e2e-tests spec 寫的 MUST 與實作脫鉤：真實 regression（Codex 停止輸出必要結構）會靜默通過 Layer 3 gate。

Root cause 有內部對照證據：同一段 instructions 裡 literal 格式要求（"Finding N: <severity> — <file>:<line>"）在 e2e 一直可靠（findings_count 解析從未壞過），而 prose 名詞就是漂移的那兩個 — 同一模型、同一次 call，差別只在 literal vs prose。adversarial-review Step 3 的 "Produce output in exactly four H2 sections, in this order" literal 模式在 e2e 與 v0.5 smoke 都 4/4 守住，是已驗證可靠的修法模板。

收斂時發現同類細節一併修：review instructions 說 finding 用 "heading format" 但沒指定 `###` level，而 Step 5 的 findings_count 解析與 result-file 契約都預期 `### Finding N:`。

## Proposed Solution

1. **review SKILL.md Step 3 literal-token 改寫**（v0.3 → v0.4）：instructions 改為命名 literal token — "Produce output in exactly two H2 sections, in this order" + literal `## Summary` / `## Findings` 行 + CRITICAL 開頭條款 + finding heading 指定 literal H3 `### Finding N: <severity> — <file>:<line>`。不加 one-shot 範例（prompt 長度成本高、邊際收益低）。frontmatter description 加 `v0.4 — heading-hardened` 字樣。
2. **adversarial-review 零措辭改動**：其 Step 3 已是 literal 寫法（"exactly four H2 sections, in this order" + CRITICAL non-empty），只有 e2e 斷言層被動到。
3. **e2e matrix 實證觀察 gate**：跑一次完整 Layer 3 e2e matrix（12 combos、約 14 個 heading 斷言樣本點），記錄 heading 出現狀況。
4. **Conditional promotion**：觀察全綠才把 tests/e2e.sh 的 heading 檢查由 verify_substring_warn 改為 verify_substring（hard fail）；任一 miss 則本 change 只 ship hardening、promotion 留待後續並記錄證據。
5. **版本**：review v0.3→v0.4、adversarial-review 維持 v0.3 不動、plugin 0.5.0→0.5.1（patch — reliability hardening、無新 capability）。

## Non-Goals

- 不追求「100% deterministic headings」— Codex 是 LLM 非 schema-validated endpoint，本 change 的誠實目標是把失敗率降到 hard assertion 可穩定的程度；結構保證需要上游 codex-call 的 structured-output 支援（parallel-ai-agents cross-repo，不在此處）。
- 不改 adversarial-review SKILL.md 的任何措辭。
- 不改 result-file 契約本身（`## Summary` + `## Findings` 一直是契約；本 change 只讓 Codex 可靠遵守）。
- 不加 one-shot / few-shot 範例到 instructions（已評估並拒絕：每次 call 的 prompt token 成本不值邊際收益）。
- 不動 e2e 的 PROMPT-side 驗證邊界（仍維持 v0.1 limitation：不驗 prompt body、不驗 Codex output 內容細節）。

## Alternatives Considered

- **One-shot 範例 / format scaffold 加進 instructions**：被拒 — literal-token 命名已有兩個內部證據（finding 格式行、adversarial-review 四 section）支持其足夠；範例增加每次呼叫的 token 成本。若 e2e 觀察推翻此判斷，再迭代加 scaffold。
- **拆成兩個 change（先 harden、下個 release 再 promote）**：被拒 — promotion 需要的 e2e matrix run 與 producer smoke 本來就要跑，拆開付兩次 quota，且留下「SKILL 宣稱可靠、tests 不 enforce」的半套狀態。改用單 change 內 conditional promotion 達到同樣的保守性。
- **直接 promote 不做觀察 gate**：被拒 — 把靜默 miss 換成 flaky hard failure 更糟；sequencing（harden → observe → promote）是必要的緩衝。

## Impact

- Affected specs: `review`（Step 3 instructions 的 literal-token 要求 + v0.4 版本字樣）、`e2e-tests`（heading 驗證從 warn 語意改為 hard assertion 語意 + conditional promotion 紀錄）
- Affected code:
  - Modified: plugins/codex-pro/skills/review/SKILL.md（Step 3 instructions 改寫 + frontmatter v0.4 字樣）、tests/e2e.sh（heading 檢查 warn→hard，conditional）、tests/review.sh（v0.4 marker 斷言同步）、plugins/codex-pro/.claude-plugin/plugin.json（0.5.0→0.5.1）、.claude-plugin/marketplace.json（版本同步）、CLAUDE.md（Commands surface review 列 v0.4）、README.md（Skills table 版本同步）
  - New: （無）
  - Removed: （無）
