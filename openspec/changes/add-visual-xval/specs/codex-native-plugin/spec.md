## MODIFIED Requirements

### Requirement: Pinned runtime provenance

The hand-maintained source bundle SHALL include a byte-for-byte snapshot of `PsychQuant/parallel-ai-agents` `codex-call` from the immutable commit recorded in `references/codex-call-provenance.json`; that commit SHALL be one whose `codex-call` accepts the `--image` option. The source snapshot and wrapper SHALL be stored outside the Claude plugin root `bin/` directory, and the resource manifest SHALL map them into each generated native bundle as `bin/codex-call` and `bin/codex-pro-call`. The Claude plugin package MUST NOT contribute either executable to the automatic Bash PATH and SHALL retain external PATH resolution for its unmodified Claude skills. Because Claude marketplace installation copies only `plugins/codex-pro/`, that package root SHALL include a complete MIT `LICENSE` and a third-party notice identifying the vendored snapshot and immutable commit; it MUST NOT depend on repository-root notice files for license compliance. Provenance data SHALL record repository, source path, commit, Git blob, raw URL, size, mode, SHA-256, MIT license, and known upstream issue identifiers. The provenance JSON SHALL be the single authoritative source for these values: the wrapper's expected SHA-256, the provenance tests, and the third-party notices SHALL be checked against it, and specifications SHALL NOT restate the fingerprint values. Updating the snapshot MUST use an immutable commit and MUST update provenance and verification tests in the same change.

#### Scenario: Vendored bytes match the pinned source fingerprint

- **WHEN** the runtime provenance test hashes and stats the source and both generated snapshots
- **THEN** all three files are executable and match the size and SHA-256 recorded in the provenance JSON

#### Scenario: Mutable upstream reference is not used

- **WHEN** the provenance JSON and synchronization documentation are inspected
- **THEN** the download URL contains the full pinned commit and no update instruction fetches mutable `main`

#### Scenario: Native runtime source does not shadow Claude PATH

- **WHEN** the Claude plugin payload rooted at `plugins/codex-pro/` is inspected or loaded with its automatic `bin/` PATH behavior
- **THEN** it contains no root `bin/codex-call` or `bin/codex-pro-call`, while a generated native bundle contains both mapped executables

#### Scenario: Claude subpackage carries the upstream license notice

- **WHEN** only `plugins/codex-pro/` is copied into a Claude marketplace cache
- **THEN** that isolated package still contains the complete MIT text and a notice identifying `runtime/codex-call` and its immutable upstream commit

#### Scenario: Wrapper digest agrees with provenance

- **WHEN** the expected SHA-256 embedded in `codex-pro-call` is compared with the provenance JSON
- **THEN** the two values are identical, and a mismatch fails the static test suite

#### Scenario: Vendored runtime accepts images

- **WHEN** the help output of the vendored `codex-call` snapshot is inspected
- **THEN** it lists the `--image` option

### Requirement: Skill-relative runtime resolution

The generated Codex setup, review, adversarial-review, rescue, and visual-xval skills SHALL set `SKILL_DIR` from the active SKILL.md absolute location supplied by Codex, derive `BUNDLE_ROOT` as two parent directories above it, and prefer `BUNDLE_ROOT/bin/codex-pro-call`. They MUST NOT infer the skill location from the current working directory, scan Codex cache directories, read `CODEX_HOME`, or require `PLUGIN_ROOT`, `CODEX_PLUGIN_ROOT`, `CODEX_SKILL_ROOT`, or `CLAUDE_PLUGIN_ROOT`.

If the bundle contains `.codex-plugin/plugin.json` or `.codex-bundle-files` but its wrapper is missing, not a regular file, or non-executable, the generated skill SHALL fail closed as package corruption. A directory or special file MUST NOT pass as a wrapper merely because its path satisfies `test -x`. A broken symbolic link at either native marker path SHALL still count as native package state and MUST NOT reopen PATH fallback. A final `command -v codex-call` fallback SHALL be permitted only when neither native marker path exists, preserving an explicitly identified legacy project mirror.

The generated producer resolver MUST NOT terminate the skill before result handling. It SHALL set a stable preflight error and detail, skip runtime execution, OAuth access, and network access, and continue to the existing result-writing step. Missing, non-regular, or non-executable native wrapper/runtime and integrity mismatch SHALL map to `package_corruption`; unsupported platform, missing Swift, missing legacy PATH runtime, and other runtime availability failures SHALL map to `runtime_unavailable`. Review, adversarial-review, rescue, and visual-xval SHALL preserve their existing result shapes while permitting these two native-only frontmatter error values, and every such failure SHALL write a result file without retrying. The result body SHALL include a sanitized and bounded representation of the preflight detail; raw control characters or unbounded wrapper output MUST NOT be copied into frontmatter.

#### Scenario: Installed native producer uses bundled runtime

- **WHEN** a native installed producer skill runs with no external `codex-call` on PATH
- **THEN** it invokes the wrapper inside the same installed plugin bundle

#### Scenario: Native corruption does not fall back to PATH

- **WHEN** a native bundle marker exists, its wrapper is missing, and an unrelated `codex-call` exists on PATH
- **THEN** the skill reports package corruption and does not invoke the PATH executable

#### Scenario: Broken native marker still prevents PATH fallback

- **WHEN** a native marker path is a broken symbolic link and the bundled wrapper is missing
- **THEN** the skill reports package corruption and does not resolve or invoke a PATH executable

#### Scenario: Wrapper directory is not executable runtime

- **WHEN** the native wrapper path names a searchable directory instead of a regular executable file
- **THEN** the skill classifies the package as corrupt before attempting execution

#### Scenario: Legacy project mirror retains compatibility

- **WHEN** a legacy Codex mirror has no bundle inventory or native manifest and has `codex-call` on PATH
- **THEN** the skill uses that PATH executable and identifies the resolution as a legacy fallback

#### Scenario: Native preflight failure remains observable

- **WHEN** review, adversarial-review, rescue, or visual-xval encounters a package-corruption or runtime-unavailable preflight state
- **THEN** it does not invoke the runtime and writes its normal structured result file with `error: package_corruption` or `error: runtime_unavailable` plus a sanitized, bounded preflight detail in the result body

### Requirement: Platform-scoped producer capability

The plugin SHALL remain installable on supported Codex surfaces, and its pure local consumer skills SHALL remain usable without the bundled producer runtime. The bundled review, adversarial-review, rescue, and visual-xval runtime SHALL be declared macOS-only with Xcode Command Line Tools Swift. On unsupported platforms, setup SHALL report producer unavailability and SHALL distinguish that result from consumer skill availability.

#### Scenario: Consumer skill remains available on a non-macOS host

- **WHEN** a non-macOS user invokes status, result, config, or cancel
- **THEN** the skill performs its existing local behavior without executing `codex-pro-call`

#### Scenario: Producer stops before OAuth or network access on a non-macOS host

- **WHEN** a non-macOS user invokes review, adversarial-review, rescue, or visual-xval
- **THEN** runtime preflight returns `error=unsupported_platform` before reading OAuth data or accessing the network
