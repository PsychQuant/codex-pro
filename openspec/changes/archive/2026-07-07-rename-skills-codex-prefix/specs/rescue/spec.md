## MODIFIED Requirements

### Requirement: Rescue skill registration and argument parsing

The plugin SHALL expose a `/codex-pro:codex-rescue` skill registered at `plugins/codex-pro/skills/codex-rescue/SKILL.md` with a YAML frontmatter declaring `name: codex-rescue`, a descriptive `description` block, and an `allowed-tools` list containing at least `Bash` (for `codex-call` invocation) and `Read` (for context file collection). The skill SHALL accept a required positional task description argument and two optional flags: `--context <path>` (may repeat) for additional context files and `--criteria <text>` for completion criteria. The skill SHALL abort with a usage hint when invoked with an empty task description. Every invocation is a stateless single-shot codex-call (no session continuity); the `--resume` / `--fresh` flags from v0.1 are removed in v0.1.1 because the underlying `codex-call` Swift wrapper has no `--session` flag and cannot support session continuation without upstream changes.

#### Scenario: Skill is registered and discoverable

- **WHEN** the plugin is installed
- **THEN** `plugins/codex-pro/skills/codex-rescue/SKILL.md` MUST exist with valid YAML frontmatter
- **AND** the frontmatter `name` field MUST equal `codex-rescue`
- **AND** the frontmatter `allowed-tools` MUST contain both `Bash` and `Read`

#### Scenario: Task description with optional flags is parsed

- **WHEN** a user invokes `/codex-pro:codex-rescue 修復 .codex/auth.json TCC 問題 --context plugins/codex-pro/skills/codex-setup/SKILL.md --criteria "OAuth check returns ✓"`
- **THEN** the skill SHALL extract `修復 .codex/auth.json TCC 問題` as the task description
- **AND** the skill SHALL collect the contents of `plugins/codex-pro/skills/codex-setup/SKILL.md` as additional context
- **AND** the skill SHALL incorporate `OAuth check returns ✓` into the codex-call instructions as the success rubric

#### Scenario: Empty task description aborts with usage hint

- **WHEN** a user invokes `/codex-pro:codex-rescue` with no positional task description argument (only flags or completely empty)
- **THEN** the skill SHALL abort without invoking codex-call
- **AND** the skill SHALL emit a usage hint listing the required and optional argument forms (task description plus `--context`, `--criteria`)

#### Scenario: Session continuity flags are not accepted

- **WHEN** a user invokes `/codex-pro:codex-rescue <task> --resume sess_xyz` or `/codex-pro:codex-rescue <task> --fresh`
- **THEN** the skill SHALL emit a clear error explaining that session continuity is removed in v0.1.1 because `codex-call` has no `--session` flag
- **AND** the error message SHALL mention that the limitation is tracked for future restoration when upstream `codex-call` gains session-tagging support
- **AND** the skill SHALL NOT invoke codex-call
