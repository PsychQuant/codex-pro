## MODIFIED Requirements

### Requirement: Status skill registration and argument parsing

The plugin SHALL expose a `/codex-pro:codex-status` skill registered at `plugins/codex-pro/skills/codex-status/SKILL.md` with a YAML frontmatter declaring `name: codex-status`, a descriptive `description` block whose trigger keywords are codex-qualified — `list codex result files` / `codex review history` / `過去 codex 結果列表` — and MUST NOT list the bare standalone term `狀態` as a trigger keyword. The `allowed-tools` list MUST contain at least `Bash` (for filesystem scan) and `Read` (for frontmatter parse). The skill SHALL accept an optional `--skill <name>` flag where `<name>` is one of the producer result-file prefixes `review`, `rescue`, `adversarial-review` (bare producer identifiers — result-file naming is intentionally decoupled from the `codex-`-prefixed invocation name and is unchanged by this rename). Any other flag or positional argument SHALL be rejected with a usage hint.

#### Scenario: Skill is registered and discoverable

- **WHEN** the plugin is installed
- **THEN** `plugins/codex-pro/skills/codex-status/SKILL.md` MUST exist with valid YAML frontmatter
- **AND** the frontmatter `name` field MUST equal `codex-status`
- **AND** the frontmatter `allowed-tools` MUST contain both `Bash` and `Read`

#### Scenario: --skill filter parses a valid producer name

- **WHEN** a user invokes `/codex-pro:codex-status --skill review`
- **THEN** the skill SHALL filter the listing to only `review-*.md` filenames
- **AND** the skill SHALL accept `--skill rescue` and `--skill adversarial-review` identically

#### Scenario: Invalid --skill value is rejected

- **WHEN** a user invokes `/codex-pro:codex-status --skill bogus`
- **THEN** the skill SHALL emit a usage hint listing the three accepted values
- **AND** the skill SHALL exit non-zero
