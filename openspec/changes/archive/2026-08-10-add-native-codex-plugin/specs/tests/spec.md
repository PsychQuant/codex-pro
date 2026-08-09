## ADDED Requirements

### Requirement: Native plugin static contract test

The automated suite SHALL include `tests/codex-plugin.sh` in `tests/run.sh`. The test SHALL validate the native manifest with repository-local assertions, validate the self-hosted marketplace entry, compare all three published versions, verify all referenced package paths remain inside the plugin root and exist, verify that the Claude source plugin contributes no root `bin/codex-call` or `bin/codex-pro-call`, verify that the isolated Claude package carries the complete MIT license and vendored-runtime notice, and invoke the current bundled plugin-creator validator as a release gate without hard-coding a user-specific home path.

#### Scenario: Complete native package passes static validation

- **WHEN** `tests/codex-plugin.sh` runs against a complete 0.8.0 package
- **THEN** manifest schema, marketplace source, version consistency, skill count, resource paths, and validator checks all pass

#### Scenario: Missing or escaping path fails validation

- **WHEN** a manifest or inventory path is missing, absolute, or resolves outside the plugin root
- **THEN** the test exits non-zero and names the invalid field or resource path

### Requirement: Full bundle parity test

`tests/codex-skills-parity.sh` SHALL regenerate a complete temporary bundle and recursively compare it with `.codex/` generated resources and repository-root generated resources. The test SHALL verify the explicit skill set and resource set in both directions, all skill-relative Markdown link targets, byte-identical shared references and runtime payloads, generator idempotency, stale generated resource cleanup, and preservation of unrelated files.

The resource-manifest contract test SHALL reject source or publish entries that name only a managed subtree or expected skill directory instead of a child file. Complete-bundle staging SHALL be checked against the expected inventory by enumerating actual regular files, so an inventory entry cannot stand for a directory with undeclared descendants.

The generator safety matrix SHALL also reject a source skill directory or `SKILL.md` symbolic link before generated output is written, reject an expected complete-bundle `SKILL.md` ownership symlink before reading its marker, and prove that newline-bearing orphan names cannot create a deletion target outside the output root.

Recursive comparison SHALL enumerate actual files below every generator-owned expected skill directory rather than relying only on the ownership inventory. The generator safety matrix SHALL include an expected skill child symlink and `SKILL.md` symlink under `--output`, and SHALL verify that default mode does not change either committed bundle when validation of either destination fails.

#### Scenario: Existing broken-link class is detected

- **WHEN** a generated shared reference or `codex-batch/references/script-template.sh` is absent
- **THEN** bundle parity fails even when all nine SKILL.md files match a fresh transformation

#### Scenario: Both committed bundles are current

- **WHEN** all generated content matches a fresh complete bundle
- **THEN** parity reports no drift for either `.codex/` or the repository-root plugin payload

#### Scenario: Unowned file survives regeneration

- **WHEN** an unrelated file exists outside the generated ownership inventory and the generator runs
- **THEN** the unrelated file remains byte-identical while stale inventory-owned paths are removed

#### Scenario: Extra file in an owned skill directory is detected

- **WHEN** an additional file exists below one of the nine expected generated skill directories but is absent from the manifests
- **THEN** recursive parity fails and names that extra owned path

### Requirement: Runtime provenance and resolver matrix tests

The automated suite SHALL verify the pinned runtime fingerprint and wrapper behavior without OAuth or network access. Tests SHALL cover native bundle resolution, repo-local bundle resolution, paths containing spaces, unsupported platform, missing Swift, missing runtime, non-regular wrapper path, non-executable runtime, hash mismatch, broken native marker symlink, native fail-closed behavior, legacy PATH fallback, argument preservation, and exit-status preservation. Platform-dependent tests SHALL use controlled command stubs except for the macOS release smoke.

Producer contract tests SHALL verify that review, adversarial-review, and rescue do not directly exit on resolver failure, map native preflight states to `runtime_unavailable` or `package_corruption`, skip runtime invocation, retain their required structured result-file shape and no-retry rule, and explicitly write the sanitized preflight detail into the result body. The gate SHALL structurally extract the unique Step 4.3 invocation block and require the `"$CODEX_CALL"` call to be inside the `CODEX_RUNTIME_ERROR` guard; an in-memory mutation that moves the call after `fi` MUST be rejected. The Step 5 assertion SHALL pin the detail label, CR/LF/TAB and control-character sanitization, 500-character bound, frontmatter exclusion, and native no-retry statement rather than checking only for a variable token.

#### Scenario: Resolver matrix passes offline

- **WHEN** the resolver tests run with isolated fixture bundles and stubbed platform commands
- **THEN** every success and failure case produces the specified resolution source or machine-readable error without reading OAuth or accessing the network

#### Scenario: Native package cannot hide corruption with PATH

- **WHEN** a fixture has a native marker, no bundled wrapper, and a PATH stub named `codex-call`
- **THEN** the test confirms the PATH stub was not invoked

#### Scenario: Every producer records native preflight failure

- **WHEN** each generated producer contract is evaluated for one controlled native preflight failure
- **THEN** the runtime is not invoked and the expected review, adversarial-review, or rescue result contract includes the mapped error and detail

### Requirement: Test dispatcher honors layer process status

`tests/run.sh` SHALL preserve each layer process exit status and SHALL require both a zero process status and a parsed summary with zero failures before counting a summarized layer as passing. A non-zero layer without a summary and a non-zero layer that prints a zero-failure summary MUST both count as failed layers and MUST make the aggregate command exit non-zero. The regression SHALL run through an isolated fixture layer directory so it does not execute the normal suite recursively.

#### Scenario: Fatal layer without summary fails aggregate gate

- **WHEN** a fixture layer prints a fatal diagnostic, emits no summary, and exits non-zero
- **THEN** the dispatcher records a failed layer with the original exit status and exits non-zero

#### Scenario: Non-zero layer cannot hide behind a passing summary

- **WHEN** a fixture layer prints a syntactically valid zero-failure summary and then exits non-zero
- **THEN** the dispatcher records the layer as failed and exits non-zero

### Requirement: macOS offline runtime smoke cannot silently skip

On macOS, the release gate SHALL execute `swift --version`, the generated wrapper `--check`, and the vendored snapshot `--selftest-error-extract '{"error":{"message":"offline self-test"}}'`. The snapshot hook SHALL receive that deterministic JSON argument and SHALL output `offline self-test` without network access. The gate MUST fail when any command fails and MUST fail when all runtime checks are skipped. On non-macOS CI, the same script SHALL report the platform limitation distinctly from a passing macOS runtime smoke.

#### Scenario: macOS runtime smoke passes

- **WHEN** the release gate runs on macOS with Xcode Command Line Tools and the pinned snapshot
- **THEN** Swift and wrapper integrity pass, and the snapshot offline self-test outputs `offline self-test`

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
