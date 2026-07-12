## MODIFIED Requirements

### Requirement: Rescue invocation uses codex-call HTTPS direct without subprocess for Codex

The skill SHALL invoke the `codex-call` Swift wrapper (provided by the `parallel-ai-agents` runtime dependency) to delegate the task to Codex. The skill MUST NOT spawn the `codex` CLI as a subprocess. This requirement places `rescue` alongside `review` as the canonical adherence pattern for codex-pro Design constraint #1 ("No subprocess spawn for Codex"), in deliberate contrast to the `batch` capability which is the documented explicit exception. The skill MUST pass `--model`, `--effort`, and `--max-time` flags to `codex-call` whose values come from the resolved profile (per the `config` capability). When no profile is set or the field is absent, hardcoded defaults SHALL apply: `--model gpt-5.6-sol` / `--effort xhigh` / `--max-time 600` (the 2026-07 default bump per issue #3: `gpt-5.6-sol` is the only 5.6-generation model the codex-call ChatGPT-account backend-api path accepts — verified empirically 2026-07-10; users with a profile override are unaffected, 100% backward compatible). The frontmatter description block in SKILL.md SHALL contain the literal substring `v0.2 — profile-aware` to make the v0.1.1 → v0.2 version bump discoverable. Rescue remains stateless per-invocation (no session continuity; the `--resume` / `--fresh` flags from v0.1 remain removed per the v0.1.1 fix because `codex-call` has no `--session` flag).

#### Scenario: SKILL.md contains codex-call invocation

- **WHEN** the static layer inspects `plugins/codex-pro/skills/codex-rescue/SKILL.md`
- **THEN** the body SHALL contain at least one occurrence of the literal string `codex-call`
- **AND** the body MUST NOT contain the literal string `codex exec` (the subprocess form is the batch exception, not allowed here)

#### Scenario: codex-call invocation includes hard timeout flag (default 600)

- **WHEN** the skill body documents the codex-call invocation
- **THEN** the documented invocation MUST include the `--max-time` flag with the literal substring `600` (the default fallback when the resolved profile has no `max_time` override)
- **AND** the documented invocation MUST NOT reference `--resume` / `--fresh` flag handling (those flags were removed in v0.1.1 and have not been restored)

#### Scenario: SKILL.md frontmatter announces v0.2 — profile-aware

- **WHEN** the static layer inspects `plugins/codex-pro/skills/codex-rescue/SKILL.md`
- **THEN** the frontmatter `description` MUST contain the literal substring `v0.2 — profile-aware`

#### Scenario: Producer reads profile via inline python3 before codex-call

- **WHEN** the SKILL.md Step 4 body documents the codex-call invocation
- **THEN** the body MUST contain an inline `python3` block that reads `~/.codex-pro/profile.yaml` and `.codex-pro/profile.yaml`
- **AND** the documented invocation MUST pass `--model "$MODEL"` / `--effort "$EFFORT"` / `--max-time "$MAX_TIME"` (or equivalent shell-variable expansion from the python3 output)
- **AND** the body MUST mention the hardcoded defaults `gpt-5.6-sol` / `xhigh` / `600` as fallbacks

### Requirement: Rescue output is a structured Markdown result file

The skill SHALL write the Codex rescue output to a Markdown file at `.codex-pro/rescue-<ISO8601-timestamp>.md` inside the project root. The directory `.codex-pro/` MUST be created on first run if absent. The result file MUST contain a YAML frontmatter block with the required fields `task_description`, `session_id`, `model`, `effort`, `timestamp`, and `outcome`; and an optional `error` field when a fail-fast condition fires. The `session_id` field records whatever conversation identifier codex-call surfaces from its HTTP response (or `null` when codex-call does not surface one); it does NOT imply any session-continuation capability. The `resume_from` field from v0.1 remains removed because session continuity is not supported (per the v0.1.1 fix). An optional v0.2 `profile_source` field MAY appear with one of four enum values: `default` (all 3 producer-relevant fields hardcoded), `global` (at least one field from global, none from project), `project` (at least one field from project, no global-only fields), or `mixed` (at least one global field AND at least one project field). v0.1.1 result files without `profile_source` remain valid (`/codex-pro:codex-status` and `/codex-pro:codex-result` MUST tolerate missing `profile_source`). The `outcome` field MUST be one of the four enum values: `completed`, `partial`, `unclear`, `requires_external`. On success (any outcome except fail-fast), the body MUST contain three sections: `## Task Brief`, `## Outcome`, and `## Suggested Next Steps`. The skill MUST NOT return the outcome inline to Claude as the primary delivery path; the result file is the contract — this discipline prevents the silent-stub failure mode (issue #324 from upstream `openai/codex-plugin-cc`).

#### Scenario: Success case writes structured result file

- **WHEN** a rescue completes (outcome `completed`, `partial`, or `requires_external`)
- **THEN** `.codex-pro/rescue-<timestamp>.md` MUST exist with YAML frontmatter containing the six required fields plus `outcome` (one of the four enum values)
- **AND** the body MUST contain `## Task Brief`, `## Outcome`, and `## Suggested Next Steps` sections

##### Example: minimal success frontmatter

| Field            | Example value                                  |
| ---------------- | ---------------------------------------------- |
| task_description | `修復 .codex/auth.json TCC 問題`               |
| session_id       | `null`                                         |
| model            | `gpt-5.6-sol`                                  |
| effort           | `xhigh`                                        |
| timestamp        | `2026-06-01T22:00:48+08:00`                    |
| outcome          | `completed`                                    |

#### Scenario: profile_source frontmatter field reflects resolution source

- **WHEN** a rescue runs with no profile set
- **THEN** the result file frontmatter MAY include `profile_source: default` (v0.2 producer SHOULD emit it; v0.1.1 compat layer for missing-field reads is intact)
- **WHEN** a rescue runs with a project profile that only sets `model`
- **THEN** the result file frontmatter `profile_source` MAY be `project`

#### Scenario: First run creates output directory

- **WHEN** the skill runs and `.codex-pro/` does not exist
- **THEN** the skill SHALL create the directory before writing the result file
- **AND** the directory creation failure (permissions, read-only filesystem) MUST abort the skill with a clear error and MUST NOT silently fall back to writing elsewhere
