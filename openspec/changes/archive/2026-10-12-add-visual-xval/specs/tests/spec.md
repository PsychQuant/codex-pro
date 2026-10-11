## MODIFIED Requirements

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
