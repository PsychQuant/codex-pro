## MODIFIED Requirements

### Requirement: Native plugin static contract test

The automated suite SHALL include `tests/codex-plugin.sh` in `tests/run.sh`. The test SHALL validate the native manifest with repository-local assertions, validate the self-hosted marketplace entry, compare all three published versions, verify all referenced package paths remain inside the plugin root and exist, verify that the Claude source plugin contributes no root `bin/codex-call` or `bin/codex-pro-call`, verify that the isolated Claude package carries the complete MIT license and vendored-runtime notice, and run the repository-local schema check `tests/lib/codex_plugin_schema.py` as a release gate. The schema check SHALL implement the field rules of the upstream `openai/skills` file `skills/.system/plugin-creator/references/plugin-json-spec.md` pinned at commit `e940b8a86138adf03972802b990a1dfc57fcbf09`, and SHALL record that repository, path, commit and the file's sha256 in its source. The schema check SHALL exit 0 when both manifests conform, 1 when any rule is violated (printing each violated field), and 2 when a manifest is missing or is not JSON. The test SHALL NOT consult the Codex plugin-creator validator, and SHALL fail rather than skip when the schema check file is missing or exits non-zero.

#### Scenario: Complete native package passes static validation

- **WHEN** `tests/codex-plugin.sh` runs against the complete native package
- **THEN** manifest schema, marketplace source, version consistency, skill count, resource paths, and the pinned schema check all pass

#### Scenario: Missing or escaping path fails validation

- **WHEN** a manifest or inventory path is missing, absolute, or resolves outside the plugin root
- **THEN** the test exits non-zero and names the invalid field or resource path

#### Scenario: Pinned schema rejects a non-conforming manifest

- **WHEN** the schema check runs on a copy of the repository whose manifest breaks a rule of the pinned upstream spec
- **THEN** the check exits 1 and its output names the violated field

##### Example: pinned schema accepts the repository manifests

- **GIVEN** the repository's own `.codex-plugin/plugin.json` and `.agents/plugins/marketplace.json`
- **WHEN** `python3 tests/lib/codex_plugin_schema.py <repo-root>` runs
- **THEN** it exits 0

##### Example: pinned schema rejects a broken manifest

| Mutation on a temporary copy | Expected exit | Output names |
| ---------------------------- | ------------- | ------------ |
| plugin.json without `name` | 1 | `name` |
| plugin.json `name` = `Codex Pro` | 1 | `name` |
| plugin.json `version` = `1` (number) | 1 | `version` |
| plugin.json `keywords` = `"codex"` (string) | 1 | `keywords` |
| plugin.json with top-level field `skill` | 1 | `skill` |
| plugin.json `skills` = `skills/` | 1 | `skills` |
| plugin.json `interface.defaultPrompt` with 4 entries | 1 | `defaultPrompt` |
| plugin.json `interface.defaultPrompt` entry of 129 characters | 1 | `defaultPrompt` |
| plugin.json `interface.screenshots` = `["./shot.png"]` | 1 | `screenshots` |
| marketplace entry `policy.installation` = `MAYBE` | 1 | `policy.installation` |
| marketplace entry `policy.authentication` = `SOMETIMES` | 1 | `policy.authentication` |
| marketplace entry `source.source` = `git` | 1 | `source.source` |
| marketplace entry `source.path` = `plugins/codex-pro` | 1 | `source.path` |
| marketplace entry without `category` | 1 | `category` |
| plugin.json replaced by `not json` | 2 | `plugin.json` |
| plugin.json removed | 2 | `plugin.json` |
| marketplace.json replaced by `not json` | 2 | `marketplace.json` |

##### Example: missing schema check fails the contract test

- **GIVEN** a schema check path that does not exist
- **WHEN** the contract test's schema step runs with that path
- **THEN** it reports a failure naming the missing check file and does not report a skip
