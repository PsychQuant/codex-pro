## MODIFIED Requirements

### Requirement: Native plugin static contract test

The automated suite SHALL include `tests/codex-plugin.sh` in `tests/run.sh`. The test SHALL validate the native manifest with repository-local assertions, validate the self-hosted marketplace entry, compare all three published versions, verify all referenced package paths remain inside the plugin root and exist, verify that the Claude source plugin contributes no root `bin/codex-call` or `bin/codex-pro-call`, verify that the isolated Claude package carries the complete MIT license and vendored-runtime notice, and run the repository-local schema check `tests/lib/codex_plugin_schema.py` as a release gate. The schema check SHALL implement the field rules of the upstream `openai/skills` file `skills/.system/plugin-creator/references/plugin-json-spec.md` pinned at commit `e940b8a86138adf03972802b990a1dfc57fcbf09`, and SHALL record that repository, path, commit and the file's sha256 in its source. The schema check SHALL exit 0 when both manifests conform; 1 when any rule is violated, printing each violated field (a field name that is not a plain identifier printed JSON-escaped), including a manifest that is valid JSON but not an object; 2 when a manifest is missing, unreadable, or is not strict UTF-8 JSON (NaN, Infinity, a repeated key, or nesting deeper than the parser allows); 3 on an unexpected internal error; and 64 on a usage error. The test SHALL NOT consult the Codex plugin-creator validator, and SHALL fail rather than skip when the schema check file is missing or exits non-zero. The release gate SHALL add exactly one failure to the test's failure count when the check fails or is missing, and the test SHALL show that in-process. The test SHALL check that the case table in this requirement lists exactly the cases it runs.

#### Scenario: Complete native package passes static validation

- **WHEN** `tests/codex-plugin.sh` runs against the complete native package
- **THEN** manifest schema, marketplace source, version consistency, skill count, resource paths, and the pinned schema check all pass

#### Scenario: Missing or escaping path fails validation

- **WHEN** a manifest or inventory path is missing, absolute, or resolves outside the plugin root
- **THEN** the test exits non-zero and names the invalid field or resource path

#### Scenario: Pinned schema rejects a non-conforming manifest

- **WHEN** the schema check runs on a copy of the repository whose manifest breaks a rule of the pinned upstream spec, is missing, or is not strict JSON
- **THEN** the check exits 1 for a rule violation and 2 for a missing, unreadable or non-JSON manifest, and its output names the violated field or the manifest
- **AND** a row of the case table with expected exit 0 is a valid input at the edge of a rule, and the check SHALL exit 0 and print nothing for it

#### Scenario: Schema gate failure is counted

- **WHEN** the release gate step runs with a missing checker, a checker that exits 1, or a checker that exits 0
- **THEN** it adds exactly one failure, one failure, or one pass to the test's counts, respectively

##### Example: pinned schema accepts the repository manifests

- **GIVEN** the repository's own `.codex-plugin/plugin.json` and `.agents/plugins/marketplace.json`
- **WHEN** `python3 -I tests/lib/codex_plugin_schema.py <repo-root>` runs
- **THEN** it exits 0

##### Example: pinned schema rejects a broken manifest

| Case in `tests/codex-plugin.sh` | Expected exit | Output names |
| ------------------------------- | ------------- | ------------ |
| `name-missing` | 1 | `plugin.json name:` |
| `name-not-kebab` | 1 | `plugin.json name:` |
| `name-trailing-newline` | 1 | `plugin.json name:` |
| `version-number` | 1 | `plugin.json version:` |
| `version-trailing-newline` | 1 | `plugin.json version:` |
| `version-non-ascii-digit` | 1 | `plugin.json version:` |
| `version-prerelease-leading-zero` | 1 | `plugin.json version:` |
| `keywords-string` | 1 | `plugin.json keywords:` |
| `undocumented-field` | 1 | `plugin.json skill:` |
| `skills-not-relative` | 1 | `plugin.json skills:` |
| `skills-dotdot` | 1 | `plugin.json skills:` |
| `default-prompt-four` | 1 | `plugin.json interface.defaultPrompt:` |
| `default-prompt-too-long` | 1 | `plugin.json interface.defaultPrompt:` |
| `screenshot-outside-assets` | 1 | `plugin.json interface.screenshots[0]:` |
| `screenshot-dotdot` | 1 | `plugin.json interface.screenshots[0]:` |
| `policy-installation-invalid` | 1 | `plugins[0].policy.installation:` |
| `policy-authentication-invalid` | 1 | `plugins[0].policy.authentication:` |
| `source-not-local` | 1 | `plugins[0].source.source:` |
| `source-path-not-relative` | 1 | `plugins[0].source.path:` |
| `source-path-dotdot` | 1 | `plugins[0].source.path:` |
| `category-missing` | 1 | `plugins[0].category:` |
| `source-path-missing` | 1 | `plugins[0].source.path:` |
| `version-core-leading-zero` | 1 | `plugin.json version:` |
| `version-build-invalid` | 1 | `plugin.json version:` |
| `name-uppercase` | 1 | `plugin.json name:` |
| `products-not-strings` | 1 | `plugins[0].policy.products:` |
| `default-prompt-at-limit` | 0 | `` |
| `version-prerelease-build-valid` | 0 | `` |
| `name-null` | 1 | `plugin.json name: must be string` |
| `source-source-missing` | 1 | `plugins[0].source.source: required` |
| `policy-installation-missing` | 1 | `plugins[0].policy.installation: required` |
| `policy-authentication-missing` | 1 | `plugins[0].policy.authentication: required` |
| `author-not-object` | 1 | `plugin.json author: must be object` |
| `interface-not-object` | 1 | `plugin.json interface: must be object` |
| `plugins-not-array` | 1 | `marketplace.json plugins: must be array` |
| `source-not-object` | 1 | `plugins[0].source: must be object` |
| `policy-not-object` | 1 | `plugins[0].policy: must be object` |
| `version-long-integer` | 1 | `plugin.json version: must be string` |
| `key-with-newline` | 1 | `plugin.json "x\nfake":` |
| `key-lone-surrogate` | 1 | `plugin.json "\ud800":` |
| `market-not-object` | 1 | `marketplace.json: must be a JSON object` |
| `plugin-not-object` | 1 | `plugin.json: must be a JSON object` |
| `author-undocumented` | 1 | `plugin.json author.twitter:` |
| `interface-undocumented` | 1 | `plugin.json interface.tagline:` |
| `market-undocumented` | 1 | `marketplace.json owner:` |
| `market-interface-undocumented` | 1 | `marketplace.json interface.tagline:` |
| `entry-undocumented` | 1 | `plugins[0].displayName:` |
| `source-undocumented` | 1 | `plugins[0].source.ref:` |
| `policy-undocumented` | 1 | `plugins[0].policy.visibility:` |
| `screenshot-not-png` | 1 | `plugin.json interface.screenshots[0]:` |
| `screenshot-no-file-name` | 1 | `plugin.json interface.screenshots[0]:` |
| `hooks-not-relative` | 1 | `plugin.json hooks:` |
| `mcp-servers-not-relative` | 1 | `plugin.json mcpServers:` |
| `apps-not-relative` | 1 | `plugin.json apps:` |
| `composer-icon-not-relative` | 1 | `plugin.json interface.composerIcon:` |
| `logo-not-relative` | 1 | `plugin.json interface.logo:` |
| `keywords-element-number` | 1 | `plugin.json keywords:` |
| `market-name-missing` | 1 | `marketplace.json name:` |
| `market-plugins-missing` | 1 | `marketplace.json plugins:` |
| `entry-not-object` | 1 | `marketplace.json plugins[0]: must be an object` |
| `plugin-duplicate-key` | 2 | `plugin.json: not JSON` |
| `plugin-deep-nesting` | 2 | `plugin.json: not JSON` |
| `plugin-infinity` | 2 | `plugin.json: not JSON` |
| `plugin-not-utf8` | 2 | `plugin.json: not JSON` |
| `plugin-unreadable` | 2 | `plugin.json: not JSON` |
| `plugin-not-json` | 2 | `plugin.json: not JSON` |
| `plugin-nan` | 2 | `plugin.json: not JSON` |
| `plugin-missing` | 2 | `plugin.json: missing` |
| `market-not-json` | 2 | `marketplace.json: not JSON` |

##### Example: missing schema check fails the contract test

- **GIVEN** a schema check path that does not exist
- **WHEN** the contract test's schema step runs with that path
- **THEN** it reports a failure naming the missing check file and does not report a skip

##### Example: the gate's failure is counted

| Checker given to `run_schema_gate` | Failures added | Passes added |
| ---------------------------------- | -------------- | ------------ |
| missing | 1 | 0 |
| exits 1 | 1 | 0 |
| exits 0 | 0 | 1 |

##### Example: the case table matches the test

- **GIVEN** the `SCHEMA_CASES` list in `tests/codex-plugin.sh` and the table of the Example "pinned schema rejects a broken manifest"
- **WHEN** `tests/codex-plugin.sh` runs
- **THEN** the two list the same cases, in the same order, with the same exit codes and output names
