## MODIFIED Requirements

### Requirement: Result skill registration and selection-mode argument parsing

The plugin SHALL expose a `/codex-pro:codex-result` skill registered at `plugins/codex-pro/skills/codex-result/SKILL.md` with a YAML frontmatter declaring `name: codex-result`, a descriptive `description` block whose trigger keywords are codex-qualified — `show codex result file` / `display codex review output` / `顯示 codex 結果` — and MUST NOT list the bare standalone term `顯示結果` as a trigger keyword. The `allowed-tools` list MUST contain at least `Bash` and `Read`. The skill SHALL accept three mutually-exclusive selection modes: (a) a positional `<filename>` argument naming a file in `.codex-pro/` (filename only, no path prefix); (b) `--latest <skill>` where `<skill>` is one of the producer result-file prefixes `review`, `rescue`, `adversarial-review` (bare producer identifiers — result-file naming is intentionally decoupled from the `codex-`-prefixed invocation name and is unchanged by this rename); (c) `--latest` with no argument (selects the most recent result file across all producer skills). Supplying both a positional filename and `--latest` SHALL be rejected as a usage error.

#### Scenario: Skill is registered and discoverable

- **WHEN** the plugin is installed
- **THEN** `plugins/codex-pro/skills/codex-result/SKILL.md` MUST exist with valid YAML frontmatter
- **AND** the frontmatter `name` field MUST equal `codex-result`
- **AND** the frontmatter `allowed-tools` MUST contain both `Bash` and `Read`

#### Scenario: Positional filename selects a specific file

- **WHEN** a user invokes `/codex-pro:codex-result review-20260601T120000Z.md` with that file present in `.codex-pro/`
- **THEN** the skill SHALL display the full content of `.codex-pro/review-20260601T120000Z.md` to stdout

#### Scenario: --latest with skill selects most recent of that producer

- **WHEN** a user invokes `/codex-pro:codex-result --latest rescue` with multiple `rescue-*.md` files in `.codex-pro/`
- **THEN** the skill SHALL select the rescue file with the highest filename lexical order
- **AND** the skill SHALL display its content to stdout

#### Scenario: --latest without argument selects most recent across all producers

- **WHEN** a user invokes `/codex-pro:codex-result --latest` with mixed-producer files in `.codex-pro/`
- **THEN** the skill SHALL select the file with the highest filename lexical order regardless of producer prefix
- **AND** the skill SHALL display its content to stdout

#### Scenario: Conflicting arguments are rejected

- **WHEN** a user invokes `/codex-pro:codex-result review-20260601T120000Z.md --latest`
- **THEN** the skill SHALL emit a usage hint explaining the modes are mutually exclusive
- **AND** the skill SHALL exit non-zero
- **AND** the skill SHALL NOT display any file content
