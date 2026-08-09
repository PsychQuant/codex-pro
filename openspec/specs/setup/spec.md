# setup Specification

## Purpose

The setup capability verifies that a Claude Code user's environment is ready to run `codex-pro` commands. It checks for the Codex OAuth token file, the `codex-call` runtime wrapper, and the plugin's own manifest, then reports the result as a structured Markdown readiness table without performing any mutating action.

## Requirements

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


<!-- @trace
source: rename-skills-codex-prefix
updated: 2026-07-07
code:
  - tests/adversarial-review.sh
  - plugins/codex-pro/skills/codex-adversarial-review/SKILL.md
  - tests/result.sh
  - plugins/codex-pro/skills/codex-setup/SKILL.md
  - tests/status.sh
  - CLAUDE.md
  - tests/cancel.sh
  - tests/static.sh
  - plugins/codex-pro/skills/codex-result/SKILL.md
  - tests/rescue.sh
  - plugins/codex-pro/skills/codex-batch/SKILL.md
  - plugins/codex-pro/skills/codex-review/SKILL.md
  - tests/batch.sh
  - tests/e2e-checklist.md
  - plugins/codex-pro/skills/codex-batch/references/script-template.sh
  - plugins/codex-pro/skills/codex-cancel/SKILL.md
  - README.md
  - plugins/codex-pro/skills/codex-rescue/SKILL.md
  - tests/config.sh
  - tests/review.sh
  - plugins/codex-pro/skills/codex-status/SKILL.md
  - tests/setup.sh
  - plugins/codex-pro/skills/codex-config/SKILL.md
  - plugins/codex-pro/.claude-plugin/plugin.json
-->

---
### Requirement: Setup command produces structured readiness report

The plugin SHALL expose a `/codex-pro:codex-setup` command that, when invoked, outputs a Markdown table containing at least three checks: Codex OAuth token file presence, `codex-call` wrapper PATH availability, and plugin manifest self-check. Each row MUST contain four columns: Check name, Status indicator (✓ / ✗ / ⚠), Detail describing the current state, and Remediation describing how to resolve a non-passing state or `N/A` when nothing is required.

#### Scenario: All checks pass

- **WHEN** the user invokes `/codex-pro:codex-setup` in an environment where `~/.codex/auth.json` exists and is readable, `codex-call` resolves on PATH, and the plugin manifest parses successfully
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

- **WHEN** the user invokes `/codex-pro:codex-setup` in an environment where `~/.codex/auth.json` does not exist
- **THEN** the OAuth-token row Status is ✗
- **AND** the Remediation cell explicitly names the corrective command `codex login`
- **AND** the trailing summary states that one or more checks need attention

#### Scenario: codex-call wrapper missing from PATH

- **WHEN** the user invokes `/codex-pro:codex-setup` in an environment where `codex-call` does not resolve on PATH
- **THEN** the codex-call row Status is ✗
- **AND** the Remediation cell instructs the user to install or repair the `parallel-ai-agents` plugin

---
### Requirement: Setup performs no mutating actions

The `/codex-pro:codex-setup` command SHALL be strictly read-only. It MUST NOT create directories, modify files, install dependencies, alter environment variables, or invoke any external command that performs writes.

#### Scenario: Setup leaves environment unchanged

- **WHEN** the user invokes `/codex-pro:codex-setup` regardless of which checks pass or fail
- **THEN** no file under `~/.codex/`, no entry on PATH, and no plugin-managed file MUST be created, modified, or deleted as a side effect of the command
- **AND** rerunning the command produces an identical report given an unchanged environment

---
### Requirement: Codex setup reports bundled runtime readiness

The generated `$codex-setup` skill SHALL resolve the active Codex bundle from its own SKILL.md absolute location and SHALL run the bundled `bin/codex-pro-call --check` without executing the runtime snapshot. Its readiness report SHALL identify the resolution source as bundled, legacy PATH fallback, package corruption, or unavailable. The Claude Code source skill SHALL retain its existing PATH lookup and `.claude-plugin/plugin.json` self-check.

#### Scenario: Bundled runtime is ready

- **WHEN** `$codex-setup` runs on macOS with a readable OAuth file, executable bundled wrapper, valid pinned runtime, and working Swift
- **THEN** the report marks OAuth and producer runtime checks as passing, identifies the bundled runtime path, and reports codex-pro ready

#### Scenario: Native package is corrupt

- **WHEN** a native manifest or bundle inventory exists but the bundled wrapper is missing, non-executable, or fails integrity verification
- **THEN** the report marks producer runtime as failed, identifies package corruption, recommends reinstalling the plugin, and does not use an executable from PATH

#### Scenario: Legacy mirror uses PATH compatibility

- **WHEN** no native manifest or bundle inventory exists and `command -v codex-call` succeeds
- **THEN** the report marks the runtime as available through an explicit legacy PATH fallback


<!-- @trace
source: add-native-codex-plugin
updated: 2026-08-10
code:
  - THIRD_PARTY_NOTICES.md
  - tests/codex-plugin.sh
  - plugins/codex-pro/bin/codex-call
  - scripts/generate-codex-skills.sh
  - tests/rescue.sh
  - plugins/codex-pro/runtime/codex-pro-call
  - skills/codex-review/SKILL.md
  - .codex/skills/codex-setup/SKILL.md
  - .codex/skills/codex-adversarial-review/SKILL.md
  - tests/adversarial-review.sh
  - tests/review.sh
  - tests/setup.sh
  - tests/run-dispatcher.sh
  - plugins/codex-pro/THIRD_PARTY_NOTICES.md
  - tests/codex-runtime.sh
  - AGENTS.md
  - plugins/codex-pro/runtime/codex-call
  - skills/codex-adversarial-review/SKILL.md
  - tests/run.sh
  - .codex/skills/codex-review/SKILL.md
  - tests/codex-skills-parity.sh
  - .codex/skills/codex-rescue/SKILL.md
  - plugins/codex-pro/LICENSE
  - scripts/codex-bundle-resources.manifest
  - skills/codex-setup/SKILL.md
  - plugins/codex-pro/bin/codex-pro-call
  - skills/codex-rescue/SKILL.md
-->

---
### Requirement: Codex setup distinguishes platform support from consumer availability

The generated `$codex-setup` skill SHALL state that bundled producer skills require macOS and Xcode Command Line Tools Swift. An unsupported platform or missing Swift SHALL mark producer runtime unavailable while explicitly stating that status, result, config, and cancel remain usable. The setup workflow SHALL NOT install Swift, invoke `codex login`, change file permissions, execute the runtime snapshot, or modify any file.

#### Scenario: Unsupported platform is reported without disabling consumers

- **WHEN** `$codex-setup` runs on a non-macOS host
- **THEN** the report surfaces `unsupported_platform`, marks producer runtime unavailable, and lists the four pure local consumer skills as still available

#### Scenario: Swift is missing on macOS

- **WHEN** `$codex-setup` runs on macOS and the Swift compiler cannot execute
- **THEN** the report surfaces `swift_missing`, recommends installing or repairing Xcode Command Line Tools, and performs no installation action

#### Scenario: Setup remains read-only

- **WHEN** `$codex-setup` completes in any readiness state
- **THEN** OAuth files, plugin files, PATH, permissions, and network state remain unchanged

<!-- @trace
source: add-native-codex-plugin
updated: 2026-08-10
code:
  - THIRD_PARTY_NOTICES.md
  - tests/codex-plugin.sh
  - plugins/codex-pro/bin/codex-call
  - scripts/generate-codex-skills.sh
  - tests/rescue.sh
  - plugins/codex-pro/runtime/codex-pro-call
  - skills/codex-review/SKILL.md
  - .codex/skills/codex-setup/SKILL.md
  - .codex/skills/codex-adversarial-review/SKILL.md
  - tests/adversarial-review.sh
  - tests/review.sh
  - tests/setup.sh
  - tests/run-dispatcher.sh
  - plugins/codex-pro/THIRD_PARTY_NOTICES.md
  - tests/codex-runtime.sh
  - AGENTS.md
  - plugins/codex-pro/runtime/codex-call
  - skills/codex-adversarial-review/SKILL.md
  - tests/run.sh
  - .codex/skills/codex-review/SKILL.md
  - tests/codex-skills-parity.sh
  - .codex/skills/codex-rescue/SKILL.md
  - plugins/codex-pro/LICENSE
  - scripts/codex-bundle-resources.manifest
  - skills/codex-setup/SKILL.md
  - plugins/codex-pro/bin/codex-pro-call
  - skills/codex-rescue/SKILL.md
-->