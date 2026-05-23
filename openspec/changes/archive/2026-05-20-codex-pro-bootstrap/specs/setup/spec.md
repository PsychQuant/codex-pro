## ADDED Requirements

### Requirement: Plugin local development load

The plugin SHALL be loadable by Claude Code via the `--plugin-dir` flag pointing at the project root. The plugin manifest (`.claude-plugin/plugin.json`) MUST declare `name`, `version`, and `description` so the plugin appears under its declared name in plugin listings.

#### Scenario: Plugin name appears in plugin listing

- **WHEN** a developer starts Claude Code with `--plugin-dir` pointing at the codex-pro project root
- **THEN** the plugin manifest is parsed without error
- **AND** the plugin appears in the plugin listing under the name declared in `plugin.json`

#### Scenario: Plugin manifest missing or malformed

- **WHEN** Claude Code attempts to load the plugin with a missing or syntactically invalid `.claude-plugin/plugin.json`
- **THEN** Claude Code SHALL report a manifest parse error and refuse to register the plugin
- **AND** no `/codex-pro:*` command becomes available

### Requirement: Setup command produces structured readiness report

The plugin SHALL expose a `/codex-pro:setup` command that, when invoked, outputs a Markdown table containing at least three checks: Codex OAuth token file presence, `codex-call` wrapper PATH availability, and plugin manifest self-check. Each row MUST contain four columns: Check name, Status indicator (✓ / ✗ / ⚠), Detail describing the current state, and Remediation describing how to resolve a non-passing state or `N/A` when nothing is required.

#### Scenario: All checks pass

- **WHEN** the user invokes `/codex-pro:setup` in an environment where `~/.codex/auth.json` exists and is readable, `codex-call` resolves on PATH, and the plugin manifest parses successfully
- **THEN** the command outputs a Markdown table with at least three rows, every Status cell set to ✓
- **AND** the trailing summary contains the literal substring "ready"

##### Example: passing environment

| Check | Status | Detail | Remediation |
|-------|--------|--------|-------------|
| OAuth token | ✓ | `~/.codex/auth.json` present (mode 0600) | N/A |
| codex-call wrapper | ✓ | resolved at `/Users/<user>/.claude/plugins/.../bin/codex-call` | N/A |
| Plugin manifest | ✓ | `.claude-plugin/plugin.json` parsed (codex-pro v0.1.0) | N/A |

All checks passed — codex-pro ready.

#### Scenario: OAuth token missing

- **WHEN** the user invokes `/codex-pro:setup` in an environment where `~/.codex/auth.json` does not exist
- **THEN** the OAuth-token row Status is ✗
- **AND** the Remediation cell explicitly names the corrective command `codex login`
- **AND** the trailing summary states that one or more checks need attention

#### Scenario: codex-call wrapper missing from PATH

- **WHEN** the user invokes `/codex-pro:setup` in an environment where `codex-call` does not resolve on PATH
- **THEN** the codex-call row Status is ✗
- **AND** the Remediation cell instructs the user to install or repair the `parallel-ai-agents` plugin

### Requirement: Setup performs no mutating actions

The `/codex-pro:setup` command SHALL be strictly read-only. It MUST NOT create directories, modify files, install dependencies, alter environment variables, or invoke any external command that performs writes.

#### Scenario: Setup leaves environment unchanged

- **WHEN** the user invokes `/codex-pro:setup` regardless of which checks pass or fail
- **THEN** no file under `~/.codex/`, no entry on PATH, and no plugin-managed file MUST be created, modified, or deleted as a side effect of the command
- **AND** rerunning the command produces an identical report given an unchanged environment
