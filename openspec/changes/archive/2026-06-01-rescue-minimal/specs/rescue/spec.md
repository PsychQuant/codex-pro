## ADDED Requirements

### Requirement: Rescue skill registration and argument parsing

The plugin SHALL expose a `/codex-pro:rescue` skill registered at `plugins/codex-pro/skills/rescue/SKILL.md` with a YAML frontmatter declaring `name: rescue`, a descriptive `description` block, and an `allowed-tools` list containing at least `Bash` (for `codex-call` invocation) and `Read` (for context file collection). The skill SHALL accept a required positional task description argument and three optional flags: `--context <path>` (may repeat) for additional context files, `--criteria <text>` for completion criteria, and the mutually-exclusive pair `--resume <session-id>` / `--fresh` for session continuity (with `--fresh` as the default behaviour when neither is provided). The skill SHALL abort with a usage hint when invoked with an empty task description.

#### Scenario: Skill is registered and discoverable

- **WHEN** the plugin is installed
- **THEN** `plugins/codex-pro/skills/rescue/SKILL.md` MUST exist with valid YAML frontmatter
- **AND** the frontmatter `name` field MUST equal `rescue`
- **AND** the frontmatter `allowed-tools` MUST contain both `Bash` and `Read`

#### Scenario: Task description with optional flags is parsed

- **WHEN** a user invokes `/codex-pro:rescue 修復 .codex/auth.json TCC 問題 --context plugins/codex-pro/skills/setup/SKILL.md --criteria "OAuth check returns ✓"`
- **THEN** the skill SHALL extract `修復 .codex/auth.json TCC 問題` as the task description
- **AND** the skill SHALL collect the contents of `plugins/codex-pro/skills/setup/SKILL.md` as additional context
- **AND** the skill SHALL incorporate `OAuth check returns ✓` into the codex-call instructions as the success rubric

#### Scenario: Empty task description aborts with usage hint

- **WHEN** a user invokes `/codex-pro:rescue` with no positional task description argument (only flags or completely empty)
- **THEN** the skill SHALL abort without invoking codex-call
- **AND** the skill SHALL emit a usage hint listing the required and optional argument forms

#### Scenario: --resume and --fresh are mutually exclusive

- **WHEN** a user invokes `/codex-pro:rescue <task> --resume abc --fresh`
- **THEN** the skill SHALL emit an error explaining the flags are mutually exclusive
- **AND** the skill SHALL NOT invoke codex-call

### Requirement: Rescue invocation uses codex-call HTTPS direct without subprocess for Codex

The skill SHALL invoke the `codex-call` Swift wrapper (provided by the `parallel-ai-agents` runtime dependency) to delegate the task to Codex. The skill MUST NOT spawn the `codex` CLI as a subprocess. This requirement places `rescue` alongside `review` as the canonical adherence pattern for codex-pro Design constraint #1 ("No subprocess spawn for Codex"), in deliberate contrast to the `batch` capability which is the documented explicit exception. The skill MUST pass a hard timeout flag (`--max-time 600`) to bound runaway inference. When the user supplies `--resume <session-id>`, the skill MUST pass that session ID through to codex-call to continue the previous thread.

#### Scenario: SKILL.md contains codex-call invocation

- **WHEN** the static layer inspects `plugins/codex-pro/skills/rescue/SKILL.md`
- **THEN** the body SHALL contain at least one occurrence of the literal string `codex-call`
- **AND** the body MUST NOT contain the literal string `codex exec` (the subprocess form is the batch exception, not allowed here)

#### Scenario: codex-call invocation includes hard timeout and resume flag

- **WHEN** the skill body documents the codex-call invocation
- **THEN** the documented invocation MUST include the `--max-time 600` flag
- **AND** the documented invocation MUST reference both `--resume` and `--fresh` flag handling

### Requirement: Rescue output is a structured Markdown result file

The skill SHALL write the Codex rescue output to a Markdown file at `.codex-pro/rescue-<ISO8601-timestamp>.md` inside the project root. The directory `.codex-pro/` MUST be created on first run if absent. The result file MUST contain a YAML frontmatter block with the required fields `task_description`, `session_id`, `model`, `effort`, `timestamp`, and `outcome`; an optional `resume_from` field when `--resume` was used; and an optional `error` field when a fail-fast condition fires. The `outcome` field MUST be one of the four enum values: `completed`, `partial`, `unclear`, `requires_external`. On success (any outcome except fail-fast), the body MUST contain three sections: `## Task Brief`, `## Outcome`, and `## Suggested Next Steps`. The skill MUST NOT return the outcome inline to Claude as the primary delivery path; the result file is the contract — this discipline prevents the silent-stub failure mode (issue #324 from upstream `openai/codex-plugin-cc`).

#### Scenario: Success case writes structured result file

- **WHEN** a rescue completes (outcome `completed`, `partial`, or `requires_external`)
- **THEN** `.codex-pro/rescue-<timestamp>.md` MUST exist with YAML frontmatter containing the six required fields plus `outcome` (one of the four enum values)
- **AND** the body MUST contain `## Task Brief`, `## Outcome`, and `## Suggested Next Steps` sections

##### Example: minimal success frontmatter

| Field            | Example value                                  |
| ---------------- | ---------------------------------------------- |
| task_description | `修復 .codex/auth.json TCC 問題`               |
| session_id       | `sess_abc123def456`                            |
| model            | `gpt-5.5`                                      |
| effort           | `xhigh`                                        |
| timestamp        | `2026-06-01T10:30:48+08:00`                    |
| outcome          | `completed`                                    |

#### Scenario: Resume flag records original session

- **WHEN** a user invokes `/codex-pro:rescue <task> --resume sess_original`
- **THEN** the result file frontmatter MUST include `resume_from: sess_original`
- **AND** the new `session_id` field MUST contain the session ID returned by codex-call (which may equal or differ from `resume_from` depending on codex-call session semantics)

#### Scenario: First run creates output directory

- **WHEN** the skill runs and `.codex-pro/` does not exist
- **THEN** the skill SHALL create the directory before writing the result file
- **AND** the directory creation failure (permissions, read-only filesystem) MUST abort the skill with a clear error and MUST NOT silently fall back to writing elsewhere

### Requirement: Rescue failures trigger circuit-breaker fail-fast across four classes

When the underlying `codex-call` invocation fails or Codex itself reports the task as unanswerable, the skill SHALL fail fast across four classes — rate-limit response, OAuth-invalid response, hard-timeout exhaustion, and task-unclear (Codex unable to commit an answer). The skill MUST NOT retry the request, MUST still write the result file with a YAML frontmatter `error` field naming the failure class (`rate_limit` / `oauth_invalid` / `timeout` / `task_unclear`), MUST set the `outcome` field to `unclear` for the `task_unclear` case (or leave `outcome` consistent with the partial state for the other three classes), and MUST report a remediation message to the user identifying the failure class. The `task_unclear` class is rescue-specific and directly counters the silent-stub failure mode (upstream issue #324) by making "Codex does not have an answer" an explicit and machine-readable state instead of a stubbed placeholder string.

#### Scenario: Rate-limit response writes error frontmatter and stops

- **WHEN** `codex-call` exits non-zero with output containing "rate limit" or HTTP status 429
- **THEN** the result file MUST be written with YAML frontmatter `error: rate_limit`
- **AND** the skill MUST NOT retry the codex-call invocation

#### Scenario: OAuth-invalid response writes error frontmatter and stops

- **WHEN** `codex-call` exits non-zero with output containing "auth" or HTTP status 401
- **THEN** the result file MUST be written with YAML frontmatter `error: oauth_invalid`
- **AND** the skill MUST emit a remediation message directing the user to run `/codex-pro:setup`

#### Scenario: Timeout exhaustion writes error frontmatter and stops

- **WHEN** `codex-call` exceeds the `--max-time 600` hard timeout
- **THEN** the result file MUST be written with YAML frontmatter `error: timeout`
- **AND** the skill MUST emit a remediation message suggesting a narrower task scope or splitting the task into sub-tasks

#### Scenario: Task-unclear response writes error and outcome unclear

- **WHEN** Codex output indicates it cannot commit an answer (outcome `unclear` or explicit refusal)
- **THEN** the result file MUST be written with YAML frontmatter `error: task_unclear` AND `outcome: unclear`
- **AND** the skill MUST emit a remediation message suggesting the user add completion criteria via `--criteria` or break the task into smaller sub-tasks
- **AND** the skill MUST NOT silently substitute a stubbed answer in the body
