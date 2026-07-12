## MODIFIED Requirements

### Requirement: Review invocation uses codex-call HTTPS direct without subprocess for Codex

The skill SHALL invoke the `codex-call` Swift wrapper (provided by the `parallel-ai-agents` runtime dependency) to execute the Codex review request. The skill MUST NOT spawn the `codex` CLI as a subprocess. This requirement is the canonical adherence pattern for codex-pro Design constraint #1 ("No subprocess spawn for Codex") and contrasts with the `batch` skill which is the documented explicit exception. The skill MUST pass `--model`, `--effort`, and `--max-time` flags to `codex-call` whose values come from the resolved profile (per the `config` capability). When no profile is set or the field is absent, hardcoded defaults SHALL apply: `--model gpt-5.6-sol` / `--effort xhigh` / `--max-time 600` (the 2026-07 default bump per issue #3: `gpt-5.6-sol` is the only 5.6-generation model the codex-call ChatGPT-account backend-api path accepts — verified empirically 2026-07-10; users with a profile override are unaffected, 100% backward compatible). The frontmatter description block in SKILL.md SHALL contain the literal substring `v0.3 — profile-aware` to make the v0.2 → v0.3 version bump discoverable.

#### Scenario: SKILL.md contains codex-call invocation

- **WHEN** the static layer inspects `plugins/codex-pro/skills/codex-review/SKILL.md`
- **THEN** the body SHALL contain at least one occurrence of the literal string `codex-call`
- **AND** the body MUST NOT contain the literal string `codex exec` (the subprocess form is the batch exception, not allowed here)

#### Scenario: codex-call invocation includes hard timeout flag (default 600)

- **WHEN** the skill body documents the codex-call invocation
- **THEN** the documented invocation MUST include the `--max-time` flag with the literal substring `600` (the default fallback when the resolved profile has no `max_time` override)

#### Scenario: SKILL.md frontmatter announces v0.3 — profile-aware

- **WHEN** the static layer inspects `plugins/codex-pro/skills/codex-review/SKILL.md`
- **THEN** the frontmatter `description` MUST contain the literal substring `v0.3 — profile-aware`

#### Scenario: Producer reads profile via inline python3 before codex-call

- **WHEN** the SKILL.md Step 4 body documents the codex-call invocation
- **THEN** the body MUST contain an inline `python3` block that reads `~/.codex-pro/profile.yaml` and `.codex-pro/profile.yaml`
- **AND** the documented invocation MUST pass `--model "$MODEL"` / `--effort "$EFFORT"` / `--max-time "$MAX_TIME"` (or equivalent shell-variable expansion from the python3 output)
- **AND** the body MUST mention the hardcoded defaults `gpt-5.6-sol` / `xhigh` / `600` as fallbacks
