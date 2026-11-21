## MODIFIED Requirements

### Requirement: Native Codex plugin manifest

The repository SHALL provide `.codex-plugin/plugin.json` as a valid skills-only Codex plugin manifest. The manifest SHALL declare `name` as `codex-pro`, a strict SemVer `version` equal to the version the other two published manifests declare, `skills` as `./skills/`, a non-empty description, `author.name`, and install-surface `interface` metadata containing display name, short description, long description, developer name, category, capabilities, website URL, and one to three starter prompts. The manifest MUST NOT declare apps, MCP servers, hooks, or asset paths without corresponding package files.

#### Scenario: Pinned schema check accepts the manifest

- **WHEN** the repository-local schema check `tests/lib/codex_plugin_schema.py`, pinned to the upstream plugin-json-spec commit, runs on the repository root
- **THEN** it exits 0 with no field, type, allowed-value, or path violations

##### Example: pinned schema check accepts the native manifest

- **GIVEN** the repository's own `.codex-plugin/plugin.json` and `.agents/plugins/marketplace.json`
- **WHEN** `python3 -I tests/lib/codex_plugin_schema.py <repo-root>` runs
- **THEN** it exits 0 and prints nothing

#### Scenario: Skills path targets the native bundle

- **WHEN** Codex resolves the manifest `skills` field relative to the repository root
- **THEN** it resolves to the generated root `skills/` directory containing exactly the ten names in `scripts/codex-skills.manifest`
