## MODIFIED Requirements

### Requirement: Cross-harness version consistency

The Codex manifest, Claude plugin manifest, and Claude marketplace entry SHALL all declare the same strict SemVer version. A version change MUST update all three in the same commit, and the release notes SHALL name what the version adds: for 0.9.0 that is visual cross-validation (`codex-visual-xval`), while Codex native plugin distribution stays recorded as the 0.8.0 feature.

#### Scenario: Version drift blocks the release gate

- **WHEN** any one of the three version values differs
- **THEN** the automated plugin test fails and identifies every mismatched manifest path

##### Example: three published manifests declare one version

- **GIVEN** `.codex-plugin/plugin.json`, `plugins/codex-pro/.claude-plugin/plugin.json` and the `codex-pro` entry of `.claude-plugin/marketplace.json`
- **WHEN** `tests/codex-plugin.sh` runs its version consistency assertion
- **THEN** the assertion "all three published manifest versions are identical" passes
