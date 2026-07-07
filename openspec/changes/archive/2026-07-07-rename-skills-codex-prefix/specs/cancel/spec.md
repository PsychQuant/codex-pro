## MODIFIED Requirements

### Requirement: Cancel skill registration with zero-argument acceptance

The plugin SHALL expose a `/codex-pro:codex-cancel` skill registered at `plugins/codex-pro/skills/codex-cancel/SKILL.md` with a YAML frontmatter declaring `name: codex-cancel`, a descriptive `description` block whose trigger keywords MUST include the literal substring `informational only` (mental-model anchor for users so they do not expect real cancellation), and an `allowed-tools` list containing at least `Bash`. The skill SHALL accept zero arguments. Any argument (positional or flag) SHALL be rejected with a usage hint that re-states the "informational only" nature, but the skill SHALL still exit 0 even when given arguments — because cancel is never an error, only a displayed limitation.

#### Scenario: Skill is registered and discoverable

- **WHEN** the plugin is installed
- **THEN** `plugins/codex-pro/skills/codex-cancel/SKILL.md` MUST exist with valid YAML frontmatter
- **AND** the frontmatter `name` field MUST equal `codex-cancel`
- **AND** the frontmatter `description` MUST contain the literal substring `informational only`

#### Scenario: Zero-argument invocation succeeds

- **WHEN** a user invokes `/codex-pro:codex-cancel` with no arguments
- **THEN** the skill SHALL emit the explainer plus three remediation lines to stdout
- **AND** the skill SHALL exit 0

#### Scenario: Argument is rejected with usage but still exit 0

- **WHEN** a user invokes `/codex-pro:codex-cancel pid 12345` or `/codex-pro:codex-cancel --job abc`
- **THEN** the skill SHALL emit a usage hint stating that cancel accepts no arguments and is informational only
- **AND** the skill SHALL exit 0 (cancel never errors)
