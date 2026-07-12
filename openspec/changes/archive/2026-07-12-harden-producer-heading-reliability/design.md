## Context

codex-pro 的兩個 review 類 producer skill（review、adversarial-review）透過 codex-call 的 `--instructions` flag 把 system instructions 送給 Codex，要求輸出特定 H2 結構。result-file 契約（review spec「Review output is a structured Markdown result file」requirement）與 Layer 3 e2e（tests/e2e.sh）都以 literal token 驗證：review 要 `## Summary` + `## Findings`、adversarial-review 要 4 個固定 H2 section。

現狀問題（issue #1 diagnosis）：review 的 Step 3 instructions 用 prose 名詞（"Begin with a one-paragraph Summary" / "Follow with a Findings list"）描述結構，從未命名 literal `## ` token；Codex 輸出 `Summary:`、`### Summary` 或省略 heading 都滿足 prose 指示但 fail literal 檢查。e2e 因此把 heading 檢查降為 verify_substring_warn（警告、不 fail），與 e2e-tests spec 寫的 MUST 脫鉤 — 真實 regression 會靜默通過。

關鍵證據（discuss 收斂確認）：同一段 review instructions 內，literal 格式要求 "Finding N: <severity> — <file>:<line>" 在 e2e 一直可靠，prose 名詞就是漂移的部分；adversarial-review 的 literal 寫法（"Produce output in exactly four H2 sections, in this order"）在 e2e 與 v0.5 smoke 均 4/4 守住。

限制條件：(a) Codex 是 LLM，無 schema-validated 輸出 — 可靠性是機率性的、只能實證觀察；(b) e2e matrix 一次 run 燒約 12 次 codex-call quota；(c) producer skill 修改受 smoke-before-archive 紀律約束（archive 前必跑真 codex-call smoke）。

## Goals / Non-Goals

**Goals:**

- review Step 3 instructions 改為 literal-token 寫法，使 Codex 穩定輸出 `## Summary` / `## Findings` H2 與 `### Finding N:` H3
- 在一次完整 e2e matrix 觀察全綠的前提下，把 tests/e2e.sh 的 heading 檢查（review 2 項 + adversarial-review 4 項）從 verify_substring_warn 升為 verify_substring，使實作回到 e2e-tests spec 的 MUST 語意
- review v0.3→v0.4、plugin 0.5.0→0.5.1，版本語意可追溯

**Non-Goals:**

- 不保證 100% deterministic headings（需上游 codex-call structured-output，cross-repo）
- 不改 adversarial-review SKILL.md 措辭
- 不改 result-file 契約、不加 one-shot 範例、不動 e2e 的 prompt-side 驗證邊界（維持 v0.1 limitation）

## Decisions

**D1: Literal-token 命名而非 one-shot 範例。** instructions 改寫為 "Produce output in exactly two H2 sections, in this order" + literal `## Summary` / `## Findings` 行 + CRITICAL 開頭條款。拒絕 one-shot 範例：兩個內部證據（同 instructions 的 finding literal 格式行可靠、adversarial-review 四 section 可靠）顯示 literal 命名已足夠，範例徒增每次呼叫的 prompt token 成本。若 e2e 觀察推翻（出現 heading miss），在同 change 內迭代加 scaffold 後重新觀察，不推翻方向。

**D2: finding heading 指定 literal H3。** 現行 instructions 寫 "heading format \"Finding N: ...\"" 未指定 level，而 Step 5 findings_count 解析與 result-file 契約均預期 `### Finding N:`。改寫後 instructions 明示 literal `### Finding N: <severity> — <file>:<line>`。同一 instruction block、同一 defect class，併入本 change（discuss 收斂時納入）。

**D3: Conditional promotion（單 change 兩段式），而非拆兩個 change 或直接 promote。** 流程：harden（D1+D2）→ 跑一次完整 e2e matrix（12 combos）→ 全部 heading 斷言（約 14 樣本點：review `## Summary`+`## Findings` × 5 scenario、adversarial-review 4 section × 1 scenario）出現才 flip warn→hard；任一 miss 則本 change 只 ship hardening，e2e 維持 warn、在 tasks 與 commit message 記錄觀察證據、promotion 留待後續 change。拒絕拆兩 change（雙倍 e2e quota + 「SKILL 宣稱可靠、tests 不 enforce」半套狀態）；拒絕直接 promote（靜默 miss 換 flaky hard failure 更糟）。

**D4: adversarial-review 措辭零改動、其 e2e 斷言隨 D3 一併 promote。** 其 Step 3 已是 literal 模板（被 D1 借用的來源）；e2e 對它的 warn 是當初一刀切 stopgap 而非觀察到的失敗。promotion 的觀察 gate 同樣覆蓋它的 4 個 section 斷言。

**D5: 版本語意。** review SKILL frontmatter description 加 literal 字樣 `v0.4 — heading-hardened`（與既有 `v0.2 — untracked-by-default`、`v0.3 — profile-aware` 並存，同既有 pattern）；adversarial-review 不 bump（檔案零改動）；plugin.json 0.5.0→0.5.1（patch：reliability hardening、無新 capability）；marketplace.json 同步。tests/review.sh 加 v0.4 marker 斷言（grep frontmatter 含 `v0.4 — heading-hardened`），同既有版本 marker 測試 pattern。

## Implementation Contract

**Behavior（使用者可觀察）**：`/codex-pro:codex-review` 的輸出 result file 穩定以 `## Summary` 開頭、後接 `## Findings`，每個 finding 用 `### Finding N: <severity> — <file>:<line>` H3 heading — 與 v0.3 的契約相同，但 Codex 遵守率從「偶爾漂移」變為「e2e matrix 觀察全綠」。promotion 落地後，`bash tests/e2e.sh` 在 heading 缺失時 FAIL（exit 非 0）而非僅印 ⚠ 警告。

**Interface / data shape**：result-file 契約、frontmatter 欄位、codex-call flags 全部不變。唯一介面層變化是 review SKILL.md Step 3 instructions 文字（送給 `--instructions` 的內容）與 frontmatter description 的 `v0.4 — heading-hardened` 字樣。

**Step 3 instructions 改寫目標文字**（apply 時依此為準、容許措辭微調但 literal token 行不可省）：

    You are a senior code reviewer. Review the following <diff | file | branch comparison>.

    Output requirements:
    - Produce output in exactly two H2 sections, in this order:
      ## Summary
      ## Findings
    - CRITICAL: the output MUST begin with the literal line "## Summary"
      (one paragraph overall assessment), followed by the literal line "## Findings".
    - Under "## Findings", each finding MUST use the literal H3 heading format
      "### Finding N: <severity> — <file>:<line>" where severity is one of
      critical / high / medium / low / info.
    - Each finding's body MUST contain a concise message describing the issue,
      followed by a single line starting with "**Suggestion:**" with concrete remediation.
    - No findings cap — report ALL material issues you observe.
    - Output format is Markdown. Do NOT wrap in code fences.

**Promotion gate 判準（可驗證）**：一次完整 `bash tests/e2e.sh` matrix run（兩 producer × 各自全部 scenario）中，所有 heading 類 verify_substring_warn 印出 pass（零 ⚠ heading 警告）→ 允許把 tests/e2e.sh 中 heading 檢查的 verify_substring_warn 呼叫改為 verify_substring；否則不改。

**Error / edge handling**：fail-fast 路徑（rate_limit / oauth_invalid / timeout / target_invalid）不受影響 — 這些路徑的 result file 由 Claude pre-flight 寫入、不經 Codex，heading 結構本來就 deterministic。all-empty scenario 的 hard 斷言（`error: target_invalid`）維持不變。

**Verification targets**：(a) `bash tests/run.sh` Layer 1+2 全綠（review.sh 的 v0.4 marker + 既有斷言）；(b) 一次完整 `bash tests/e2e.sh` matrix 觀察結果記錄於 tasks checkbox；(c) promotion 後（若觸發）再跑受影響 e2e scenario 確認 hard 斷言通過；(d) MANDATORY producer smoke（真 codex-call、檢查兩 heading + finding H3）於 archive 前執行。

## Risks / Trade-offs

- **Flaky gate 風險**：promote 後若 Codex 可靠性退化，e2e 變 flaky hard failure。緩衝：D3 的觀察 gate + 失敗時的明確 fallback（ship hardening only）。殘餘風險：一次 matrix 全綠仍是有限樣本（約 14 點），不排除低機率漂移 — 接受此風險，因 warn 的靜默 miss 危害更大（spec MUST 已脫鉤）。
- **e2e quota 成本**：觀察 gate 需 ~12 次 codex-call。緩衝：與 per-release e2e gate 及 producer smoke 同場跑、不額外加跑。
- **過度硬化**：instructions 過度約束可能壓抑 Codex review 內容品質。緩衝：改寫只約束 heading 結構、不約束內容形狀（D1 範圍限定）。

## Migration Plan

無資料遷移。版本順序：SKILL.md 改寫 + Layer 2 測試同步 → e2e matrix 觀察 → conditional promotion → plugin.json/marketplace.json bump → docs（CLAUDE.md / README.md）同步 → smoke → archive。rollback：revert 單一 commit 即回 v0.3 行為（instructions 與 e2e 斷言同 commit、原子回退）。

## Open Questions

（無 — discuss 階段已收斂全部 5 個決策點；唯一執行期分支是 D3 的 conditional promotion，其判準已在 Implementation Contract 寫死。）
