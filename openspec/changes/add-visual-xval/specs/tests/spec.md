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
