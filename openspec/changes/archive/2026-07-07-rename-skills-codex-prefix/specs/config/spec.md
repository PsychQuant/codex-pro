## MODIFIED Requirements

### Requirement: Config skill registration with zero-argument display

The plugin SHALL expose a `/codex-pro:codex-config` skill registered at `plugins/codex-pro/skills/codex-config/SKILL.md` with a YAML frontmatter declaring `name: codex-config`, a descriptive `description` block whose trigger keywords are codex-qualified — `codex profile` / `codex config` / `show resolved profile` / `which model` — and MUST NOT list the bare standalone terms `設定`, `配置`, `settings`, or `config` as trigger keywords (these generic terms caused the collision with the system `/config` command that this change resolves). The `allowed-tools` list MUST contain at least `Bash` (for filesystem scan + python3 parse) and `Read` (for profile YAML inspection). The skill SHALL accept zero arguments. Any argument SHALL be silently ignored (the script still proceeds to display the profile — argument has no effect on output).

#### Scenario: Skill is registered and discoverable

- **WHEN** the plugin is installed
- **THEN** `plugins/codex-pro/skills/codex-config/SKILL.md` MUST exist with valid YAML frontmatter
- **AND** the frontmatter `name` field MUST equal `codex-config`
- **AND** the frontmatter `allowed-tools` MUST contain both `Bash` and `Read`
- **AND** the frontmatter `description` MUST contain the substring `profile`
- **AND** the frontmatter `description` MUST NOT contain the bare standalone trigger terms `設定` or `配置`

#### Scenario: Zero-argument invocation displays resolved profile

- **WHEN** a user invokes `/codex-pro:codex-config` with no arguments
- **THEN** the skill SHALL emit a 4-row markdown table to stdout with columns `field`, `resolved value`, `source`
- **AND** the skill SHALL emit two informational lines: `Global profile: ~/.codex-pro/profile.yaml (exists / does not exist)` and `Project profile: .codex-pro/profile.yaml (exists / does not exist)`
- **AND** the skill SHALL exit 0

#### Scenario: Argument is silently ignored

- **WHEN** a user invokes `/codex-pro:codex-config something extra` or `/codex-pro:codex-config --flag`
- **THEN** the skill SHALL proceed to display the resolved profile as if invoked with no argument
- **AND** the skill SHALL exit 0
