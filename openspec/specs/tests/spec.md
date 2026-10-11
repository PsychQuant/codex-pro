# tests Specification

## Purpose

The tests capability provides automated verification of codex-pro's structural correctness and skill behaviour. It defines three layers: Layer 1 (static) checks manifest schemas, SKILL.md frontmatter, shell syntax, the batch template's byte-identical sha256, and namespace consistency; Layer 2 (behavioral) reproduces skill scenarios in isolated environments using fake `HOME`, stripped `PATH`, and mktemp fake plugin roots; Layer 3 (manual) is a markdown checklist for UI verification that the automated layers cannot reach. The runner is pure Bash with two shared libraries (`lib/assert.sh`, `lib/isolate.sh`) and no external framework dependency. Hardcoded invariants — most notably the batch template sha256 reference value — encode design discipline as enforceable assertions so future drift is detected on the next `bash tests/run.sh`.

## Requirements

### Requirement: Test runner entry point

The plugin SHALL provide an executable Bash test runner at `tests/run.sh` that, when executed from the codex-pro repository root, runs all automated layers (static and behavioral) sequentially and reports an aggregate pass/fail summary. The runner MUST exit with code 0 when every assertion passes and a non-zero code when any assertion fails. The runner MUST NOT require external dependencies beyond `bash`, `python3`, and standard POSIX utilities.

#### Scenario: Runner reports pass on a clean repository

- **WHEN** a developer executes `bash tests/run.sh` from the codex-pro repository root in a clean state (no test-induced modifications)
- **THEN** the runner runs `tests/static.sh`, `tests/setup.sh`, and `tests/batch.sh` in sequence
- **AND** the runner prints a final summary including the count of passed and failed assertions
- **AND** the runner exits with code 0

#### Scenario: Runner reports fail when an assertion breaks

- **WHEN** a developer executes `bash tests/run.sh` and at least one assertion in any layer fails (for example, the batch template sha256 has drifted)
- **THEN** the runner prints the failing assertion message identifying the layer and the broken invariant
- **AND** the runner exits with a non-zero code

#### Scenario: Single layer can be executed independently

- **WHEN** a developer executes `bash tests/static.sh` or `bash tests/setup.sh` or `bash tests/batch.sh` directly
- **THEN** the script runs only its own assertions
- **AND** the script reports its own pass/fail summary and exit code

---
### Requirement: Static layer enforces structural invariants

The static layer at `tests/static.sh` SHALL verify the structural correctness of codex-pro artifacts without executing any skill behaviour. It MUST parse `.claude-plugin/marketplace.json` and `plugins/codex-pro/.claude-plugin/plugin.json` with `python3 -c "import json; json.load(open(...))"`, MUST parse the YAML frontmatter of every `SKILL.md` under `plugins/codex-pro/skills/`, MUST run `bash -n` on every `*.sh` file under `tests/` and under `plugins/codex-pro/skills/codex-batch/references/`, MUST verify byte-identical preservation of `script-template.sh` against a hardcoded sha256, and MUST verify namespace consistency across CLAUDE.md, README.md, and main spec files.

#### Scenario: Manifest JSON parses and name alignment holds

- **WHEN** the static layer runs
- **THEN** both `.claude-plugin/marketplace.json` and `plugins/codex-pro/.claude-plugin/plugin.json` parse as valid JSON
- **AND** `marketplace.json` declares `name == "codex-pro"`
- **AND** `marketplace.json` `plugins[0].name == "codex-pro"`
- **AND** `plugin.json` declares `name == "codex-pro"`

#### Scenario: SKILL.md frontmatter parses

- **WHEN** the static layer runs
- **THEN** each `SKILL.md` under `plugins/codex-pro/skills/` has a valid YAML frontmatter
- **AND** the `name` field equals the immediate parent directory basename (e.g., `skills/codex-setup/SKILL.md` has `name: codex-setup`)
- **AND** the `allowed-tools` field contains `Bash`

#### Scenario: Batch template byte-identical preservation

- **WHEN** the static layer runs
- **THEN** `shasum -a 256` on `plugins/codex-pro/skills/codex-batch/references/script-template.sh` produces the hardcoded reference hash

##### Example: reference hash

- **GIVEN** the hardcoded sha256 reference value `746157138caf13436711b92f82af6570843d31c964387aa0b0ccb80c9983c1b0` (recorded during add-batch-skill task 1.2)
- **WHEN** the static layer reads the bundled template at its current location
- **THEN** the computed hash equals the reference value byte-for-byte

#### Scenario: Namespace consistency holds across artifacts

- **WHEN** the static layer runs
- **THEN** the obsolete namespace prefix `/codex-pro-setup` does NOT appear in CLAUDE.md, README.md, or main specs
- **AND** the obsolete plugin name `codex-pro-setup` does NOT appear in `.claude-plugin/marketplace.json` or `plugins/codex-pro/.claude-plugin/plugin.json`
- **AND** the canonical namespace `/codex-pro:` appears in CLAUDE.md, README.md, and main specs

---
### Requirement: Behavioral layer reproduces skill scenarios in isolated environments

The behavioral layer (`tests/setup.sh` and `tests/batch.sh`) SHALL reproduce the spec scenarios defined for setup and batch skills using isolated environments via shared helpers in `tests/lib/isolate.sh`. The behavioral layer MUST NOT mutate the developer's real `~/.codex/`, MUST NOT modify any file under `plugins/codex-pro/`, and MUST clean up any temporary directories it creates.

#### Scenario: Setup behaviour in missing-OAuth environment

- **WHEN** `tests/setup.sh` runs the OAuth token check inside `with_empty_home` (which sets `HOME=/nonexistent`)
- **THEN** the assertion confirms the check reports `missing` status
- **AND** the developer's real `~/.codex/` directory listing remains unchanged before and after the test

#### Scenario: Setup behaviour with corrupted plugin manifest

- **WHEN** `tests/setup.sh` runs the manifest self-check inside `with_fake_plugin_root` and writes a syntactically invalid JSON into the fake manifest
- **THEN** the assertion confirms the check reports a parse error containing the line and column of the failure
- **AND** the temporary directory created by the helper is removed after the test

#### Scenario: Batch SKILL records Design constraint exception

- **WHEN** `tests/batch.sh` inspects `plugins/codex-pro/skills/codex-batch/SKILL.md`
- **THEN** the body contains at least one occurrence of `exception` and at least one occurrence of `constraint`
- **AND** the body explicitly mentions Design constraint #1 by name

#### Scenario: Batch template preserves parallel orchestration markers

- **WHEN** `tests/batch.sh` greps the bundled `script-template.sh`
- **THEN** the template contains a `codex exec` invocation with a `--full-auto` flag (either as literal `codex exec --full-auto` or via `"$CODEX" exec ... --full-auto`)
- **AND** the template contains the shell parallel markers `&` (background process) and `wait` (synchronisation)

---
### Requirement: Manual e2e checklist provides UI verification steps

The plugin SHALL ship a manual e2e checklist at `tests/e2e-checklist.md` containing at least six checkbox items covering installation, setup all-green, setup missing-OAuth, batch trigger, batch parameter prompting, and post-skill read-only verification. The checklist MUST use markdown checkbox syntax (`- [ ]`) so a developer can tick items as they verify them. The checklist is NOT executed by the automated runner.

#### Scenario: Checklist documents both happy and unhappy paths

- **WHEN** a developer opens `tests/e2e-checklist.md`
- **THEN** the file contains at least six lines starting with `- [ ]`
- **AND** the checklist covers (in any order): plugin install via marketplace, setup skill triggers and reports ready when environment is clean, setup skill reports missing OAuth when token absent, batch skill triggers and prompts for required parameters, post-test `~/.codex/` is unchanged, and `tests/run.sh` was executed before any of the above

---
### Requirement: Native plugin static contract test

The automated suite SHALL include `tests/codex-plugin.sh` in `tests/run.sh`. The test SHALL validate the native manifest with repository-local assertions, validate the self-hosted marketplace entry, compare all three published versions, verify all referenced package paths remain inside the plugin root and exist, verify that the Claude source plugin contributes no root `bin/codex-call` or `bin/codex-pro-call`, verify that the isolated Claude package carries the complete MIT license and vendored-runtime notice, and invoke the current bundled plugin-creator validator as a release gate without hard-coding a user-specific home path.

#### Scenario: Complete native package passes static validation

- **WHEN** `tests/codex-plugin.sh` runs against a complete 0.8.0 package
- **THEN** manifest schema, marketplace source, version consistency, skill count, resource paths, and validator checks all pass

#### Scenario: Missing or escaping path fails validation

- **WHEN** a manifest or inventory path is missing, absolute, or resolves outside the plugin root
- **THEN** the test exits non-zero and names the invalid field or resource path


<!-- @trace
source: add-native-codex-plugin
updated: 2026-08-10
code:
  - THIRD_PARTY_NOTICES.md
  - tests/codex-plugin.sh
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
  - skills/codex-rescue/SKILL.md
-->

---
### Requirement: Full bundle parity test

`tests/codex-skills-parity.sh` SHALL regenerate a complete temporary bundle and recursively compare it with `.codex/` generated resources and repository-root generated resources. The test SHALL verify the explicit skill set and resource set in both directions, all skill-relative Markdown link targets, byte-identical shared references and runtime payloads, generator idempotency, stale generated resource cleanup, and preservation of unrelated files.

The resource-manifest contract test SHALL reject source or publish entries that name only a managed subtree or expected skill directory instead of a child file. Complete-bundle staging SHALL be checked against the expected inventory by enumerating actual regular files, so an inventory entry cannot stand for a directory with undeclared descendants.

The generator safety matrix SHALL also reject a source skill directory or `SKILL.md` symbolic link before generated output is written, reject an expected complete-bundle `SKILL.md` ownership symlink before reading its marker, and prove that newline-bearing orphan names cannot create a deletion target outside the output root.

Recursive comparison SHALL enumerate actual files below every generator-owned expected skill directory rather than relying only on the ownership inventory. The generator safety matrix SHALL include an expected skill child symlink and `SKILL.md` symlink under `--output`, and SHALL verify that default mode does not change either committed bundle when validation of either destination fails.

#### Scenario: Existing broken-link class is detected

- **WHEN** a generated shared reference or `codex-batch/references/script-template.sh` is absent
- **THEN** bundle parity fails even when all ten SKILL.md files match a fresh transformation

#### Scenario: Both committed bundles are current

- **WHEN** all generated content matches a fresh complete bundle
- **THEN** parity reports no drift for either `.codex/` or the repository-root plugin payload

#### Scenario: Unowned file survives regeneration

- **WHEN** an unrelated file exists outside the generated ownership inventory and the generator runs
- **THEN** the unrelated file remains byte-identical while stale inventory-owned paths are removed

#### Scenario: Extra file in an owned skill directory is detected

- **WHEN** an additional file exists below one of the ten expected generated skill directories but is absent from the manifests
- **THEN** recursive parity fails and names that extra owned path


<!-- @trace
source: add-native-codex-plugin
updated: 2026-08-10
code:
  - THIRD_PARTY_NOTICES.md
  - tests/codex-plugin.sh
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
  - skills/codex-rescue/SKILL.md
-->


<!-- @trace
source: add-visual-xval
updated: 2026-10-12
code:
  - .codex/skills/codex-visual-xval/references/claim-schema.md
  - .codex/skills/codex-visual-xval/scripts/zoom_round.py
  - skills/codex-visual-xval/scripts/adjudicate.py
  - plugins/codex-pro/skills/codex-result/SKILL.md
  - plugins/codex-pro/.claude-plugin/plugin.json
  - .codex/skills/codex-visual-xval/scripts/adjudicate.py
  - .codex/skills/codex-status/SKILL.md
  - tests/codex-skills-parity.sh
  - THIRD_PARTY_NOTICES.md
  - .agents/skills/spectra-ask/SKILL.md
  - bin/codex-pro-call
  - plugins/codex-pro/skills/codex-visual-xval/scripts/adjudicate.py
  - skills/codex-visual-xval/references/claim-schema.md
  - skills/codex-visual-xval/scripts/xval.py
  - skills/codex-visual-xval/scripts/sam_env.sh
  - .agents/skills/spectra-commit/SKILL.md
  - .codex/.codex-bundle-files
  - plugins/codex-pro/runtime/codex-call
  - .codex/skills/codex-visual-xval/scripts/codex_errors.py
  - plugins/codex-pro/skills/codex-visual-xval/scripts/sam_track.py
  - skills/codex-setup/SKILL.md
  - scripts/codex-skills.manifest
  - plugins/codex-pro/skills/codex-visual-xval/scripts/zoom_round.py
  - .codex/bin/codex-pro-call
  - .codex/skills/codex-visual-xval/scripts/media.py
  - skills/codex-visual-xval/scripts/seal.py
  - skills/codex-visual-xval/references/vocab-format.md
  - bin/codex-call
  - .codex/skills/codex-visual-xval/scripts/sam_track.py
  - plugins/codex-pro/skills/codex-visual-xval/SKILL.md
  - plugins/codex-pro/skills/codex-visual-xval/scripts/xval.py
  - .agents/skills/spectra-analyze/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - plugins/codex-pro/skills/codex-visual-xval/scripts/seal.py
  - .codex/skills/codex-visual-xval/scripts/result_file.py
  - CHANGELOG.md
  - skills/codex-status/SKILL.md
  - tests/result.sh
  - tests/e2e-checklist.md
  - .codex-bundle-files
  - plugins/codex-pro/skills/codex-visual-xval/references/vocab-format.md
  - .agents/skills/spectra-ingest/SKILL.md
  - .agents/skills/spectra-review/SKILL.md
  - tests/lib/assert.sh
  - AGENTS.md
  - skills/codex-visual-xval/scripts/codex_errors.py
  - skills/codex-visual-xval/scripts/sam_track.py
  - tests/run.sh
  - .codex/skills/codex-visual-xval/scripts/xval.py
  - .codex/skills/codex-visual-xval/scripts/sam_env.sh
  - skills/codex-visual-xval/SKILL.md
  - tests/codex-plugin.sh
  - .codex/skills/codex-visual-xval/scripts/seal.py
  - plugins/codex-pro/references/codex-call-provenance.json
  - .codex/skills/codex-visual-xval/SKILL.md
  - plugins/codex-pro/skills/codex-visual-xval/scripts/result_file.py
  - .agents/skills/spectra-drift/SKILL.md
  - .codex/bin/codex-call
  - skills/codex-visual-xval/scripts/media.py
  - .codex/skills/codex-visual-xval/scripts/run_files.py
  - scripts/codex-bundle-resources.manifest
  - skills/codex-visual-xval/scripts/zoom_round.py
  - plugins/codex-pro/skills/codex-visual-xval/scripts/media.py
  - .agents/skills/spectra-verify/SKILL.md
  - .codex-plugin/plugin.json
  - plugins/codex-pro/THIRD_PARTY_NOTICES.md
  - .agents/skills/spectra-archive/SKILL.md
  - .codex/skills/codex-visual-xval/references/vocab-format.md
  - .codex/skills/codex-result/SKILL.md
  - plugins/codex-pro/runtime/codex-pro-call
  - .codex/skills/codex-visual-xval/scripts/compare_claims.py
  - skills/codex-visual-xval/scripts/run_files.py
  - tests/visual-xval.sh
  - .codex/references/codex-call-provenance.json
  - CLAUDE.md
  - skills/codex-visual-xval/scripts/compare_claims.py
  - plugins/codex-pro/skills/codex-visual-xval/scripts/run_files.py
  - .agents/skills/spectra-debug/SKILL.md
  - references/codex-call-provenance.json
  - .agents/skills/spectra-audit/SKILL.md
  - scripts/generate-codex-skills.sh
  - plugins/codex-pro/skills/codex-visual-xval/scripts/sam_env.sh
  - plugins/codex-pro/skills/codex-visual-xval/references/claim-schema.md
  - plugins/codex-pro/skills/codex-visual-xval/scripts/compare_claims.py
  - tests/status.sh
  - tests/codex-runtime.sh
  - skills/codex-result/SKILL.md
  - README.md
  - .claude-plugin/marketplace.json
  - .agents/skills/spectra-apply/SKILL.md
  - .codex/skills/codex-setup/SKILL.md
  - plugins/codex-pro/skills/codex-status/SKILL.md
  - skills/codex-visual-xval/scripts/result_file.py
  - .agents/skills/spectra-propose/SKILL.md
  - plugins/codex-pro/skills/codex-visual-xval/scripts/codex_errors.py
-->

---
### Requirement: Runtime provenance and resolver matrix tests

The automated suite SHALL verify the pinned runtime fingerprint against the provenance JSON and wrapper behavior without OAuth or network access. Tests SHALL cover native bundle resolution, repo-local bundle resolution, paths containing spaces, unsupported platform, missing Swift, missing runtime, non-regular wrapper path, non-executable runtime, hash mismatch, broken native marker symlink, native fail-closed behavior, legacy PATH fallback, argument preservation, and exit-status preservation. Platform-dependent tests SHALL use controlled command stubs except for the macOS release smoke.

Producer contract tests SHALL verify that review, adversarial-review, rescue, and visual-xval do not directly exit on resolver failure, map native preflight states to `runtime_unavailable` or `package_corruption`, skip runtime invocation, retain their required structured result-file shape and no-retry rule, and explicitly write the sanitized preflight detail into the result body. The gate SHALL structurally extract the unique Step 4.3 invocation block and require the `"$CODEX_CALL"` call to be inside the `CODEX_RUNTIME_ERROR` guard; an in-memory mutation that moves the call after `fi` MUST be rejected. The Step 5 assertion SHALL pin the detail label, CR/LF/TAB and control-character sanitization, 500-character bound, frontmatter exclusion, and native no-retry statement rather than checking only for a variable token.

#### Scenario: Resolver matrix passes offline

- **WHEN** the resolver tests run with isolated fixture bundles and stubbed platform commands
- **THEN** every success and failure case produces the specified resolution source or machine-readable error without reading OAuth or accessing the network

#### Scenario: Native package cannot hide corruption with PATH

- **WHEN** a fixture has a native marker, no bundled wrapper, and a PATH stub named `codex-call`
- **THEN** the test confirms the PATH stub was not invoked

#### Scenario: Every producer records native preflight failure

- **WHEN** each generated producer contract is evaluated for one controlled native preflight failure
- **THEN** the runtime is not invoked and the expected review, adversarial-review, rescue, or visual-xval result contract includes the mapped error and detail


<!-- @trace
source: add-visual-xval
updated: 2026-10-12
code:
  - .codex/skills/codex-visual-xval/references/claim-schema.md
  - .codex/skills/codex-visual-xval/scripts/zoom_round.py
  - skills/codex-visual-xval/scripts/adjudicate.py
  - plugins/codex-pro/skills/codex-result/SKILL.md
  - plugins/codex-pro/.claude-plugin/plugin.json
  - .codex/skills/codex-visual-xval/scripts/adjudicate.py
  - .codex/skills/codex-status/SKILL.md
  - tests/codex-skills-parity.sh
  - THIRD_PARTY_NOTICES.md
  - .agents/skills/spectra-ask/SKILL.md
  - bin/codex-pro-call
  - plugins/codex-pro/skills/codex-visual-xval/scripts/adjudicate.py
  - skills/codex-visual-xval/references/claim-schema.md
  - skills/codex-visual-xval/scripts/xval.py
  - skills/codex-visual-xval/scripts/sam_env.sh
  - .agents/skills/spectra-commit/SKILL.md
  - .codex/.codex-bundle-files
  - plugins/codex-pro/runtime/codex-call
  - .codex/skills/codex-visual-xval/scripts/codex_errors.py
  - plugins/codex-pro/skills/codex-visual-xval/scripts/sam_track.py
  - skills/codex-setup/SKILL.md
  - scripts/codex-skills.manifest
  - plugins/codex-pro/skills/codex-visual-xval/scripts/zoom_round.py
  - .codex/bin/codex-pro-call
  - .codex/skills/codex-visual-xval/scripts/media.py
  - skills/codex-visual-xval/scripts/seal.py
  - skills/codex-visual-xval/references/vocab-format.md
  - bin/codex-call
  - .codex/skills/codex-visual-xval/scripts/sam_track.py
  - plugins/codex-pro/skills/codex-visual-xval/SKILL.md
  - plugins/codex-pro/skills/codex-visual-xval/scripts/xval.py
  - .agents/skills/spectra-analyze/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - plugins/codex-pro/skills/codex-visual-xval/scripts/seal.py
  - .codex/skills/codex-visual-xval/scripts/result_file.py
  - CHANGELOG.md
  - skills/codex-status/SKILL.md
  - tests/result.sh
  - tests/e2e-checklist.md
  - .codex-bundle-files
  - plugins/codex-pro/skills/codex-visual-xval/references/vocab-format.md
  - .agents/skills/spectra-ingest/SKILL.md
  - .agents/skills/spectra-review/SKILL.md
  - tests/lib/assert.sh
  - AGENTS.md
  - skills/codex-visual-xval/scripts/codex_errors.py
  - skills/codex-visual-xval/scripts/sam_track.py
  - tests/run.sh
  - .codex/skills/codex-visual-xval/scripts/xval.py
  - .codex/skills/codex-visual-xval/scripts/sam_env.sh
  - skills/codex-visual-xval/SKILL.md
  - tests/codex-plugin.sh
  - .codex/skills/codex-visual-xval/scripts/seal.py
  - plugins/codex-pro/references/codex-call-provenance.json
  - .codex/skills/codex-visual-xval/SKILL.md
  - plugins/codex-pro/skills/codex-visual-xval/scripts/result_file.py
  - .agents/skills/spectra-drift/SKILL.md
  - .codex/bin/codex-call
  - skills/codex-visual-xval/scripts/media.py
  - .codex/skills/codex-visual-xval/scripts/run_files.py
  - scripts/codex-bundle-resources.manifest
  - skills/codex-visual-xval/scripts/zoom_round.py
  - plugins/codex-pro/skills/codex-visual-xval/scripts/media.py
  - .agents/skills/spectra-verify/SKILL.md
  - .codex-plugin/plugin.json
  - plugins/codex-pro/THIRD_PARTY_NOTICES.md
  - .agents/skills/spectra-archive/SKILL.md
  - .codex/skills/codex-visual-xval/references/vocab-format.md
  - .codex/skills/codex-result/SKILL.md
  - plugins/codex-pro/runtime/codex-pro-call
  - .codex/skills/codex-visual-xval/scripts/compare_claims.py
  - skills/codex-visual-xval/scripts/run_files.py
  - tests/visual-xval.sh
  - .codex/references/codex-call-provenance.json
  - CLAUDE.md
  - skills/codex-visual-xval/scripts/compare_claims.py
  - plugins/codex-pro/skills/codex-visual-xval/scripts/run_files.py
  - .agents/skills/spectra-debug/SKILL.md
  - references/codex-call-provenance.json
  - .agents/skills/spectra-audit/SKILL.md
  - scripts/generate-codex-skills.sh
  - plugins/codex-pro/skills/codex-visual-xval/scripts/sam_env.sh
  - plugins/codex-pro/skills/codex-visual-xval/references/claim-schema.md
  - plugins/codex-pro/skills/codex-visual-xval/scripts/compare_claims.py
  - tests/status.sh
  - tests/codex-runtime.sh
  - skills/codex-result/SKILL.md
  - README.md
  - .claude-plugin/marketplace.json
  - .agents/skills/spectra-apply/SKILL.md
  - .codex/skills/codex-setup/SKILL.md
  - plugins/codex-pro/skills/codex-status/SKILL.md
  - skills/codex-visual-xval/scripts/result_file.py
  - .agents/skills/spectra-propose/SKILL.md
  - plugins/codex-pro/skills/codex-visual-xval/scripts/codex_errors.py
-->

---
### Requirement: Test dispatcher honors layer process status

`tests/run.sh` SHALL preserve each layer process exit status and SHALL require both a zero process status and a parsed summary with zero failures before counting a summarized layer as passing. A non-zero layer without a summary and a non-zero layer that prints a zero-failure summary MUST both count as failed layers and MUST make the aggregate command exit non-zero. The regression SHALL run through an isolated fixture layer directory so it does not execute the normal suite recursively.

#### Scenario: Fatal layer without summary fails aggregate gate

- **WHEN** a fixture layer prints a fatal diagnostic, emits no summary, and exits non-zero
- **THEN** the dispatcher records a failed layer with the original exit status and exits non-zero

#### Scenario: Non-zero layer cannot hide behind a passing summary

- **WHEN** a fixture layer prints a syntactically valid zero-failure summary and then exits non-zero
- **THEN** the dispatcher records the layer as failed and exits non-zero


<!-- @trace
source: add-native-codex-plugin
updated: 2026-08-10
code:
  - THIRD_PARTY_NOTICES.md
  - tests/codex-plugin.sh
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
  - skills/codex-rescue/SKILL.md
-->

---
### Requirement: macOS offline runtime smoke cannot silently skip

On macOS, the release gate SHALL execute `swift --version`, the generated wrapper `--check`, and the vendored snapshot `--selftest-error-extract '{"error":{"message":"offline self-test"}}'`. The snapshot hook SHALL receive that deterministic JSON argument and SHALL output `offline self-test` without network access. The gate MUST fail when any command fails and MUST fail when all runtime checks are skipped. On non-macOS CI, the same script SHALL report the platform limitation distinctly from a passing macOS runtime smoke.

#### Scenario: macOS runtime smoke passes

- **WHEN** the release gate runs on macOS with Xcode Command Line Tools and the pinned snapshot
- **THEN** Swift and wrapper integrity pass, and the snapshot offline self-test outputs `offline self-test`

#### Scenario: Empty smoke execution is rejected

- **WHEN** the test harness records zero executed runtime checks
- **THEN** the gate exits non-zero instead of reporting success


<!-- @trace
source: add-native-codex-plugin
updated: 2026-08-10
code:
  - THIRD_PARTY_NOTICES.md
  - tests/codex-plugin.sh
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
  - skills/codex-rescue/SKILL.md
-->

---
### Requirement: Codex installation e2e checklist

The manual e2e checklist SHALL document a disposable Codex CLI marketplace install and a Codex App install from the native package. It SHALL require a new task after installation and SHALL cover `$codex-setup`, one pure local consumer, one producer against a small fixture diff, absence of Claude plugin PATH injection, result-file verification, update or reinstall, and cleanup or rollback.

#### Scenario: Reviewer can reproduce native installation

- **WHEN** a release reviewer follows the checklist on a clean macOS Codex environment
- **THEN** the reviewer can install `codex-pro`, see ten skills in a new task, verify bundled readiness, run a consumer, and produce a structured review result without installing `parallel-ai-agents`

#### Scenario: Codex App visual gate remains explicit

- **WHEN** automated tests complete
- **THEN** the checklist still requires manual confirmation of plugin listing, install state, skill visibility in a new task, and uninstall or rollback behavior in the Codex App

<!-- @trace
source: add-native-codex-plugin
updated: 2026-08-10
code:
  - THIRD_PARTY_NOTICES.md
  - tests/codex-plugin.sh
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
  - skills/codex-rescue/SKILL.md
-->

<!-- @trace
source: add-visual-xval
updated: 2026-10-12
code:
  - .codex/skills/codex-visual-xval/references/claim-schema.md
  - .codex/skills/codex-visual-xval/scripts/zoom_round.py
  - skills/codex-visual-xval/scripts/adjudicate.py
  - plugins/codex-pro/skills/codex-result/SKILL.md
  - plugins/codex-pro/.claude-plugin/plugin.json
  - .codex/skills/codex-visual-xval/scripts/adjudicate.py
  - .codex/skills/codex-status/SKILL.md
  - tests/codex-skills-parity.sh
  - THIRD_PARTY_NOTICES.md
  - .agents/skills/spectra-ask/SKILL.md
  - bin/codex-pro-call
  - plugins/codex-pro/skills/codex-visual-xval/scripts/adjudicate.py
  - skills/codex-visual-xval/references/claim-schema.md
  - skills/codex-visual-xval/scripts/xval.py
  - skills/codex-visual-xval/scripts/sam_env.sh
  - .agents/skills/spectra-commit/SKILL.md
  - .codex/.codex-bundle-files
  - plugins/codex-pro/runtime/codex-call
  - .codex/skills/codex-visual-xval/scripts/codex_errors.py
  - plugins/codex-pro/skills/codex-visual-xval/scripts/sam_track.py
  - skills/codex-setup/SKILL.md
  - scripts/codex-skills.manifest
  - plugins/codex-pro/skills/codex-visual-xval/scripts/zoom_round.py
  - .codex/bin/codex-pro-call
  - .codex/skills/codex-visual-xval/scripts/media.py
  - skills/codex-visual-xval/scripts/seal.py
  - skills/codex-visual-xval/references/vocab-format.md
  - bin/codex-call
  - .codex/skills/codex-visual-xval/scripts/sam_track.py
  - plugins/codex-pro/skills/codex-visual-xval/SKILL.md
  - plugins/codex-pro/skills/codex-visual-xval/scripts/xval.py
  - .agents/skills/spectra-analyze/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - plugins/codex-pro/skills/codex-visual-xval/scripts/seal.py
  - .codex/skills/codex-visual-xval/scripts/result_file.py
  - CHANGELOG.md
  - skills/codex-status/SKILL.md
  - tests/result.sh
  - tests/e2e-checklist.md
  - .codex-bundle-files
  - plugins/codex-pro/skills/codex-visual-xval/references/vocab-format.md
  - .agents/skills/spectra-ingest/SKILL.md
  - .agents/skills/spectra-review/SKILL.md
  - tests/lib/assert.sh
  - AGENTS.md
  - skills/codex-visual-xval/scripts/codex_errors.py
  - skills/codex-visual-xval/scripts/sam_track.py
  - tests/run.sh
  - .codex/skills/codex-visual-xval/scripts/xval.py
  - .codex/skills/codex-visual-xval/scripts/sam_env.sh
  - skills/codex-visual-xval/SKILL.md
  - tests/codex-plugin.sh
  - .codex/skills/codex-visual-xval/scripts/seal.py
  - plugins/codex-pro/references/codex-call-provenance.json
  - .codex/skills/codex-visual-xval/SKILL.md
  - plugins/codex-pro/skills/codex-visual-xval/scripts/result_file.py
  - .agents/skills/spectra-drift/SKILL.md
  - .codex/bin/codex-call
  - skills/codex-visual-xval/scripts/media.py
  - .codex/skills/codex-visual-xval/scripts/run_files.py
  - scripts/codex-bundle-resources.manifest
  - skills/codex-visual-xval/scripts/zoom_round.py
  - plugins/codex-pro/skills/codex-visual-xval/scripts/media.py
  - .agents/skills/spectra-verify/SKILL.md
  - .codex-plugin/plugin.json
  - plugins/codex-pro/THIRD_PARTY_NOTICES.md
  - .agents/skills/spectra-archive/SKILL.md
  - .codex/skills/codex-visual-xval/references/vocab-format.md
  - .codex/skills/codex-result/SKILL.md
  - plugins/codex-pro/runtime/codex-pro-call
  - .codex/skills/codex-visual-xval/scripts/compare_claims.py
  - skills/codex-visual-xval/scripts/run_files.py
  - tests/visual-xval.sh
  - .codex/references/codex-call-provenance.json
  - CLAUDE.md
  - skills/codex-visual-xval/scripts/compare_claims.py
  - plugins/codex-pro/skills/codex-visual-xval/scripts/run_files.py
  - .agents/skills/spectra-debug/SKILL.md
  - references/codex-call-provenance.json
  - .agents/skills/spectra-audit/SKILL.md
  - scripts/generate-codex-skills.sh
  - plugins/codex-pro/skills/codex-visual-xval/scripts/sam_env.sh
  - plugins/codex-pro/skills/codex-visual-xval/references/claim-schema.md
  - plugins/codex-pro/skills/codex-visual-xval/scripts/compare_claims.py
  - tests/status.sh
  - tests/codex-runtime.sh
  - skills/codex-result/SKILL.md
  - README.md
  - .claude-plugin/marketplace.json
  - .agents/skills/spectra-apply/SKILL.md
  - .codex/skills/codex-setup/SKILL.md
  - plugins/codex-pro/skills/codex-status/SKILL.md
  - skills/codex-visual-xval/scripts/result_file.py
  - .agents/skills/spectra-propose/SKILL.md
  - plugins/codex-pro/skills/codex-visual-xval/scripts/codex_errors.py
-->