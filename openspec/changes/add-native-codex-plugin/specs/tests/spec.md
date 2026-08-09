## ADDED Requirements

### Requirement: Native plugin static contract test

The automated suite SHALL include `tests/codex-plugin.sh` in `tests/run.sh`. The test SHALL validate the native manifest with repository-local assertions, validate the self-hosted marketplace entry, compare all three published versions, verify all referenced package paths remain inside the plugin root and exist, and invoke the current bundled plugin-creator validator as a release gate without hard-coding a user-specific home path.

#### Scenario: Complete native package passes static validation

- **WHEN** `tests/codex-plugin.sh` runs against a complete 0.8.0 package
- **THEN** manifest schema, marketplace source, version consistency, skill count, resource paths, and validator checks all pass

#### Scenario: Missing or escaping path fails validation

- **WHEN** a manifest or inventory path is missing, absolute, or resolves outside the plugin root
- **THEN** the test exits non-zero and names the invalid field or resource path

### Requirement: Full bundle parity test

`tests/codex-skills-parity.sh` SHALL regenerate a complete temporary bundle and recursively compare it with `.codex/` generated resources and repository-root generated resources. The test SHALL verify the explicit skill set and resource set in both directions, all skill-relative Markdown link targets, byte-identical shared references and runtime payloads, generator idempotency, stale generated resource cleanup, and preservation of unrelated files.

#### Scenario: Existing broken-link class is detected

- **WHEN** a generated shared reference or `codex-batch/references/script-template.sh` is absent
- **THEN** bundle parity fails even when all nine SKILL.md files match a fresh transformation

#### Scenario: Both committed bundles are current

- **WHEN** all generated content matches a fresh complete bundle
- **THEN** parity reports no drift for either `.codex/` or the repository-root plugin payload

#### Scenario: Unowned file survives regeneration

- **WHEN** an unrelated file exists outside the generated ownership inventory and the generator runs
- **THEN** the unrelated file remains byte-identical while stale inventory-owned paths are removed

### Requirement: Runtime provenance and resolver matrix tests

The automated suite SHALL verify the pinned runtime fingerprint and wrapper behavior without OAuth or network access. Tests SHALL cover native bundle resolution, repo-local bundle resolution, paths containing spaces, unsupported platform, missing Swift, missing runtime, non-executable runtime, hash mismatch, native fail-closed behavior, legacy PATH fallback, argument preservation, and exit-status preservation. Platform-dependent tests SHALL use controlled command stubs except for the macOS release smoke.

#### Scenario: Resolver matrix passes offline

- **WHEN** the resolver tests run with isolated fixture bundles and stubbed platform commands
- **THEN** every success and failure case produces the specified resolution source or machine-readable error without reading OAuth or accessing the network

#### Scenario: Native package cannot hide corruption with PATH

- **WHEN** a fixture has a native marker, no bundled wrapper, and a PATH stub named `codex-call`
- **THEN** the test confirms the PATH stub was not invoked

### Requirement: macOS offline runtime smoke cannot silently skip

On macOS, the release gate SHALL execute `swift --version`, the generated wrapper `--check`, and the vendored snapshot `--selftest-error-extract`. The gate MUST fail when any command fails and MUST fail when all runtime checks are skipped. On non-macOS CI, the same script SHALL report the platform limitation distinctly from a passing macOS runtime smoke.

#### Scenario: macOS runtime smoke passes

- **WHEN** the release gate runs on macOS with Xcode Command Line Tools and the pinned snapshot
- **THEN** Swift, wrapper integrity, and the snapshot offline self-test all execute and pass

#### Scenario: Empty smoke execution is rejected

- **WHEN** the test harness records zero executed runtime checks
- **THEN** the gate exits non-zero instead of reporting success

### Requirement: Codex installation e2e checklist

The manual e2e checklist SHALL document a disposable Codex CLI marketplace install and a Codex App install from the native package. It SHALL require a new task after installation and SHALL cover `$codex-setup`, one pure local consumer, one producer against a small fixture diff, absence of Claude plugin PATH injection, result-file verification, update or reinstall, and cleanup or rollback.

#### Scenario: Reviewer can reproduce native installation

- **WHEN** a release reviewer follows the checklist on a clean macOS Codex environment
- **THEN** the reviewer can install `codex-pro`, see nine skills in a new task, verify bundled readiness, run a consumer, and produce a structured review result without installing `parallel-ai-agents`

#### Scenario: Codex App visual gate remains explicit

- **WHEN** automated tests complete
- **THEN** the checklist still requires manual confirmation of plugin listing, install state, skill visibility in a new task, and uninstall or rollback behavior in the Codex App
