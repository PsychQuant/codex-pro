## MODIFIED Requirements

### Requirement: Native plugin static contract test

The automated suite SHALL include `tests/codex-plugin.sh` in `tests/run.sh`. The test SHALL validate the native manifest with repository-local assertions, validate the self-hosted marketplace entry, compare all three published versions, verify all referenced package paths remain inside the plugin root and exist, verify that the Claude source plugin contributes no root `bin/codex-call` or `bin/codex-pro-call`, verify that the isolated Claude package carries the complete MIT license and vendored-runtime notice, and run the repository-local schema check `tests/lib/codex_plugin_schema.py` as a release gate. The schema check SHALL implement the field rules of the upstream `openai/skills` file `skills/.system/plugin-creator/references/plugin-json-spec.md` pinned at commit `e940b8a86138adf03972802b990a1dfc57fcbf09`, and SHALL record that repository, path, commit and the file's sha256 in its source. The schema check SHALL exit 0 when both manifests conform; 1 when any rule is violated, printing each violated field, including a manifest that is valid JSON but not an object; 2 when a manifest is missing or is not strict JSON (NaN, Infinity, a repeated key, or nesting deeper than the parser allows); and 64 on a usage error. The test SHALL NOT consult the Codex plugin-creator validator, and SHALL fail rather than skip when the schema check file is missing or exits non-zero. The test SHALL also show that the gate's failure reaches its own exit status, on copies of the tree.

#### Scenario: Complete native package passes static validation

- **WHEN** `tests/codex-plugin.sh` runs against the complete native package
- **THEN** manifest schema, marketplace source, version consistency, skill count, resource paths, and the pinned schema check all pass

#### Scenario: Missing or escaping path fails validation

- **WHEN** a manifest or inventory path is missing, absolute, or resolves outside the plugin root
- **THEN** the test exits non-zero and names the invalid field or resource path

#### Scenario: Pinned schema rejects a non-conforming manifest

- **WHEN** the schema check runs on a copy of the repository whose manifest breaks a rule of the pinned upstream spec, is missing, or is not strict JSON
- **THEN** the check exits 1 for a rule violation and 2 for a missing or non-JSON manifest, and its output names the violated field or the manifest

#### Scenario: Schema gate failure fails the whole contract test

- **WHEN** `tests/codex-plugin.sh` runs on a copy of the tree with a broken manifest, or without the schema check file
- **THEN** it exits non-zero and prints the schema gate's own failure line, while an unmodified copy exits 0

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
| `plugin-not-json` | 2 | `plugin.json: not JSON` |
| `plugin-nan` | 2 | `plugin.json: not JSON` |
| `plugin-missing` | 2 | `plugin.json: missing` |
| `market-not-json` | 2 | `marketplace.json: not JSON` |

##### Example: missing schema check fails the contract test

- **GIVEN** a schema check path that does not exist
- **WHEN** the contract test's schema step runs with that path
- **THEN** it reports a failure naming the missing check file and does not report a skip

##### Example: a broken copy fails the whole contract test

| Copy of the tree | Expected exit of `tests/codex-plugin.sh` | Gate failure line |
| ---------------- | ---------------------------------------- | ----------------- |
| unmodified (control) | 0 | absent |
| `keywords` = `"codex"` in plugin.json | non-zero | present |
| `tests/lib/codex_plugin_schema.py` removed | non-zero | present |

