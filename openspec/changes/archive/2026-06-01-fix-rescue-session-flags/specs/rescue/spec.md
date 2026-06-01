## MODIFIED Requirements

### Requirement: Rescue skill registration and argument parsing

The plugin SHALL expose a `/codex-pro:rescue` skill registered at `plugins/codex-pro/skills/rescue/SKILL.md` with a YAML frontmatter declaring `name: rescue`, a descriptive `description` block, and an `allowed-tools` list containing at least `Bash` (for `codex-call` invocation) and `Read` (for context file collection). The skill SHALL accept a required positional task description argument and two optional flags: `--context <path>` (may repeat) for additional context files and `--criteria <text>` for completion criteria. The skill SHALL abort with a usage hint when invoked with an empty task description. Every invocation is a stateless single-shot codex-call (no session continuity); the `--resume` / `--fresh` flags from v0.1 are removed in v0.1.1 because the underlying `codex-call` Swift wrapper has no `--session` flag and cannot support session continuation without upstream changes.

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
- **AND** the skill SHALL emit a usage hint listing the required and optional argument forms (task description plus `--context`, `--criteria`)

#### Scenario: Session continuity flags are not accepted

- **WHEN** a user invokes `/codex-pro:rescue <task> --resume sess_xyz` or `/codex-pro:rescue <task> --fresh`
- **THEN** the skill SHALL emit a clear error explaining that session continuity is removed in v0.1.1 because `codex-call` has no `--session` flag
- **AND** the error message SHALL mention that the limitation is tracked for future restoration when upstream `codex-call` gains session-tagging support
- **AND** the skill SHALL NOT invoke codex-call

### Requirement: Rescue output is a structured Markdown result file

The skill SHALL write the Codex rescue output to a Markdown file at `.codex-pro/rescue-<ISO8601-timestamp>.md` inside the project root. The directory `.codex-pro/` MUST be created on first run if absent. The result file MUST contain a YAML frontmatter block with the required fields `task_description`, `session_id`, `model`, `effort`, `timestamp`, and `outcome`; and an optional `error` field when a fail-fast condition fires. The `session_id` field records whatever conversation identifier codex-call surfaces from its HTTP response (or `null` when codex-call does not surface one); it does NOT imply any session-continuation capability. The `resume_from` field from v0.1 is removed because session continuity is not supported in v0.1.1. The `outcome` field MUST be one of the four enum values: `completed`, `partial`, `unclear`, `requires_external`. On success (any outcome except fail-fast), the body MUST contain three sections: `## Task Brief`, `## Outcome`, and `## Suggested Next Steps`. The skill MUST NOT return the outcome inline to Claude as the primary delivery path; the result file is the contract — this discipline prevents the silent-stub failure mode (issue #324 from upstream `openai/codex-plugin-cc`).

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

#### Scenario: First run creates output directory

- **WHEN** the skill runs and `.codex-pro/` does not exist
- **THEN** the skill SHALL create the directory before writing the result file
- **AND** the directory creation failure (permissions, read-only filesystem) MUST abort the skill with a clear error and MUST NOT silently fall back to writing elsewhere
