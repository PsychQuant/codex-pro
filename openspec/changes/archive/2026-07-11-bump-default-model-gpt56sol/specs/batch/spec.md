## MODIFIED Requirements

### Requirement: Batch skill registration and parameter collection

The plugin SHALL expose a `/codex-pro:codex-batch` skill triggered by Claude Code's skill invocation mechanism. The skill MUST be declared in `plugins/codex-pro/skills/codex-batch/SKILL.md` with a YAML frontmatter containing `name: codex-batch`, a `description` block describing its batch generation purpose, an `argument-hint`, and an `allowed-tools` list including `Bash` (required for spawning `codex exec`). Upon invocation the skill SHALL collect the following parameters from the user (skipping any already supplied through the slash argument): reference file path, chunk specification, prompt template, output directory, model identifier (default `gpt-5.6-sol`), and reasoning effort (default `xhigh`).

#### Scenario: Skill is discoverable after plugin install

- **WHEN** a developer has installed the `codex-pro` plugin via the `codex-pro` marketplace (or loaded it via `--plugin-dir`)
- **AND** invokes `/codex-pro:codex-batch` in Claude Code
- **THEN** Claude triggers the `codex-batch` skill from `plugins/codex-pro/skills/codex-batch/SKILL.md`
- **AND** the skill is listed under the plugin namespace in `/help` output

#### Scenario: Skill prompts for required parameters

- **WHEN** the user invokes `/codex-pro:codex-batch` without supplying full parameters in the slash argument
- **THEN** the skill SHALL request each missing required parameter individually before proceeding (reference file, chunk specification, prompt template, output directory)
- **AND** the skill SHALL apply default values `gpt-5.6-sol` for model and `xhigh` for reasoning effort when the user omits them
