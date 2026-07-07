## MODIFIED Requirements

### Requirement: Plugin local development load

The `codex-pro` marketplace SHALL list the `codex-pro` sub-plugin in its catalog manifest at `.claude-plugin/marketplace.json`, and the sub-plugin SHALL be loadable through both production-style marketplace installation and direct sub-plugin development testing. The marketplace catalog manifest MUST declare the marketplace `name` and `owner`, and MUST list each sub-plugin with at minimum `name` and `source`. Each sub-plugin manifest (`plugins/<plugin-name>/.claude-plugin/plugin.json`) MUST declare `name`, `version`, and `description`. The sub-plugin's declared `name` MUST be the namespace prefix used for its skill triggers (for example, a plugin named `codex-pro` exposes skills as `/codex-pro:<skill>`, where each `<skill>` is itself `codex-`-prefixed such as `codex-setup`). When the marketplace and sub-plugin share the same name, the `/plugin install` command takes the form `/plugin install codex-pro@codex-pro`.

#### Scenario: Marketplace install path exposes sub-plugin

- **WHEN** a developer adds the codex-pro marketplace via `/plugin marketplace add` pointing at the codex-pro project root
- **AND** then installs the sub-plugin via `/plugin install codex-pro@codex-pro`
- **THEN** the marketplace catalog at `.claude-plugin/marketplace.json` is parsed without error
- **AND** the `/plugin` listing shows the `codex-pro` marketplace containing the `codex-pro` plugin entry
- **AND** the `/codex-pro:codex-setup` skill becomes available

#### Scenario: Sub-plugin dev-test path loads sub-plugin directly

- **WHEN** a developer starts Claude Code with `--plugin-dir` pointing at the sub-plugin directory `plugins/codex-pro` inside the codex-pro project
- **THEN** the sub-plugin manifest at `plugins/codex-pro/.claude-plugin/plugin.json` is parsed without error
- **AND** the sub-plugin appears in the plugin listing under the name `codex-pro`
- **AND** the `/codex-pro:codex-setup` skill becomes available without needing to add the marketplace first

#### Scenario: Sub-plugin manifest missing or malformed

- **WHEN** Claude Code attempts to load the sub-plugin and `plugins/codex-pro/.claude-plugin/plugin.json` is missing or syntactically invalid
- **THEN** Claude Code SHALL report a manifest parse error and refuse to register the sub-plugin
- **AND** no `/codex-pro:*` command becomes available
