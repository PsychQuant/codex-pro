## MODIFIED Requirements

### Requirement: Review invocation uses codex-call HTTPS direct without subprocess for Codex

The skill SHALL invoke the `codex-call` Swift wrapper (provided by the `parallel-ai-agents` runtime dependency) to execute the Codex review request. The skill MUST NOT spawn the `codex` CLI as a subprocess. This requirement is the canonical adherence pattern for codex-pro Design constraint #1 ("No subprocess spawn for Codex") and contrasts with the `batch` skill which is the documented explicit exception. The skill MUST pass `--model`, `--effort`, and `--max-time` flags to `codex-call` whose values come from the resolved profile (per the `config` capability). When no profile is set or the field is absent, hardcoded defaults SHALL apply: `--model gpt-5.5` / `--effort xhigh` / `--max-time 600` (the v0.2 hardcoded values become v0.3 default fallbacks — 100% backward compatible for users without a profile). The frontmatter description block in SKILL.md SHALL contain the literal substring `v0.3 — profile-aware` to make the v0.2 → v0.3 version bump discoverable.

#### Scenario: SKILL.md contains codex-call invocation

- **WHEN** the static layer inspects `plugins/codex-pro/skills/review/SKILL.md`
- **THEN** the body SHALL contain at least one occurrence of the literal string `codex-call`
- **AND** the body MUST NOT contain the literal string `codex exec` (the subprocess form is the batch exception, not allowed here)

#### Scenario: codex-call invocation includes hard timeout flag (default 600)

- **WHEN** the skill body documents the codex-call invocation
- **THEN** the documented invocation MUST include the `--max-time` flag with the literal substring `600` (the v0.3 default fallback when the resolved profile has no `max_time` override)

#### Scenario: SKILL.md frontmatter announces v0.3 — profile-aware

- **WHEN** the static layer inspects `plugins/codex-pro/skills/review/SKILL.md`
- **THEN** the frontmatter `description` MUST contain the literal substring `v0.3 — profile-aware`

#### Scenario: Producer reads profile via inline python3 before codex-call

- **WHEN** the SKILL.md Step 4 body documents the codex-call invocation
- **THEN** the body MUST contain an inline `python3` block that reads `~/.codex-pro/profile.yaml` and `.codex-pro/profile.yaml`
- **AND** the documented invocation MUST pass `--model "$MODEL"` / `--effort "$EFFORT"` / `--max-time "$MAX_TIME"` (or equivalent shell-variable expansion from the python3 output)
- **AND** the body MUST mention the hardcoded defaults `gpt-5.5` / `xhigh` / `600` as fallbacks

### Requirement: Review output is a structured Markdown result file

The skill SHALL write the Codex review output to a Markdown file at `.codex-pro/review-<ISO8601-timestamp>.md` inside the project root. The directory `.codex-pro/` MUST be created on first run if absent. The result file MUST contain a YAML frontmatter block with the required fields `target`, `model`, `effort`, `timestamp`, `findings_count` (with no upper bound), and an optional `error` field when a fail-fast condition fires. An optional v0.3 `profile_source` field MAY appear with one of four enum values: `default` (all 3 producer-relevant fields hardcoded), `global` (at least one field from global, none from project), `project` (at least one field from project, no global-only fields), or `mixed` (at least one global field AND at least one project field). v0.2 result files without `profile_source` remain valid (`/codex-pro:status` and `/codex-pro:result` MUST tolerate missing `profile_source`). The body MUST contain a `## Summary` section (one-paragraph overall assessment) followed by a `## Findings` section. Each finding heading MUST use the format `### Finding N: <severity> — <file>:<line>` and each finding body MUST contain a concise message followed by a single line beginning with `**Suggestion:**` providing concrete remediation. The skill MUST NOT return findings inline to Claude as the primary delivery path; the result file is the contract.

#### Scenario: Success case writes structured result file

- **WHEN** a review completes successfully
- **THEN** `.codex-pro/review-<timestamp>.md` MUST exist with YAML frontmatter containing `target`, `model`, `effort`, `timestamp`, `findings_count`
- **AND** the body MUST contain `## Summary` and `## Findings` sections
- **AND** each `### Finding N:` body MUST contain a `**Suggestion:**` line

#### Scenario: profile_source frontmatter field reflects resolution source

- **WHEN** a review runs with no profile set
- **THEN** the result file frontmatter MAY include `profile_source: default` (v0.3 producer SHOULD emit it; v0.2 compat layer for missing-field reads is intact)
- **WHEN** a review runs with a project profile that only sets `max_time`
- **THEN** the result file frontmatter `profile_source` MAY be `project`
- **WHEN** a review runs with a global profile setting `model` and a project profile setting `max_time`
- **THEN** the result file frontmatter `profile_source` MAY be `mixed`

#### Scenario: First run creates output directory

- **WHEN** the skill runs and `.codex-pro/` does not exist
- **THEN** the skill SHALL create the directory before writing the result file
- **AND** a failure to create the directory (permissions, read-only filesystem) MUST abort the skill with a clear error and MUST NOT silently fall back to writing elsewhere
