## ADDED Requirements

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
