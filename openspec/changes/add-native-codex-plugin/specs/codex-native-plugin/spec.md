## ADDED Requirements

### Requirement: Native Codex plugin manifest

The repository SHALL provide `.codex-plugin/plugin.json` as a valid skills-only Codex plugin manifest. The manifest SHALL declare `name` as `codex-pro`, strict SemVer `version` as `0.8.0`, `skills` as `./skills/`, a non-empty description, `author.name`, and install-surface `interface` metadata containing display name, short description, long description, developer name, category, capabilities, website URL, and one to three starter prompts. The manifest MUST NOT declare apps, MCP servers, hooks, or asset paths without corresponding package files.

#### Scenario: Plugin validator accepts the manifest

- **WHEN** the repository root is validated with the current Codex plugin validator
- **THEN** validation succeeds with no placeholder, schema, path, or missing-file errors

#### Scenario: Skills path targets the native bundle

- **WHEN** Codex resolves the manifest `skills` field relative to the repository root
- **THEN** it resolves to the generated root `skills/` directory containing exactly the nine names in `scripts/codex-skills.manifest`

### Requirement: Self-hosted repository marketplace

The repository SHALL provide `.agents/plugins/marketplace.json` with top-level marketplace name `codex-pro` and one plugin entry named `codex-pro`. The entry SHALL use local source path `./`, installation policy `AVAILABLE`, authentication policy `ON_INSTALL`, and category `Developer Tools`, so a Git marketplace snapshot uses its own repository root as the plugin payload.

#### Scenario: Git marketplace exposes the root plugin

- **WHEN** Codex adds `PsychQuant/codex-pro` as a marketplace at ref `main`
- **THEN** the marketplace lists `codex-pro` and its source resolves inside that same snapshot to a directory containing `.codex-plugin/plugin.json`

#### Scenario: Local marketplace exposes uncommitted development state

- **WHEN** Codex adds the local repository root as a marketplace
- **THEN** the same entry resolves to the current repository root without a copied staging plugin

### Requirement: Complete generated Codex bundles

`plugins/codex-pro/` SHALL remain the only hand-maintained source for Codex skill content and runtime resources. Running `scripts/generate-codex-skills.sh` without arguments SHALL update two complete bundle roots: `.codex/` and the repository root. Each bundle SHALL contain generated `skills/`, `references/`, `bin/`, and a sorted `.codex-bundle-files` ownership inventory. The nine skill directories, every manifest-listed skill-local resource, shared reference, wrapper, and runtime snapshot SHALL be byte-identical between both bundle roots, except generated SKILL.md content that is deterministically transformed from the Claude source and is itself identical across the two Codex bundles.

#### Scenario: Fresh full-bundle regeneration matches committed outputs

- **WHEN** the generator produces a bundle in a new temporary directory using `--bundle-root`
- **THEN** recursive comparison against both committed bundles reports no missing, extra, stale, or different generated files

#### Scenario: Batch template and shared references are present

- **WHEN** generated skill-relative Markdown links are resolved from each SKILL.md
- **THEN** `codex-batch/references/script-template.sh`, `references/defaults.json`, and `references/profile-contract.md` exist at their referenced locations in both bundles

#### Scenario: Cleanup remains bounded to generated ownership

- **WHEN** a former generated resource is removed from the explicit resource manifest and the generator runs again
- **THEN** the stale path recorded in the prior ownership inventory is removed while unrelated files elsewhere in the bundle root remain unchanged

### Requirement: Backward-compatible generator interfaces

The generator SHALL support `--bundle-root <path>` for one complete bundle and SHALL preserve `--output <skills-dir>` as a skill-only compatibility interface. The generator MUST reject an empty destination, `/`, the current user's home directory, and any destination that cannot be resolved safely before deleting or replacing generated content.

#### Scenario: Legacy skill-only caller remains valid

- **WHEN** an existing test invokes the generator with `--output <temporary-skills-directory>`
- **THEN** the generator writes the nine transformed skill directories without changing either committed bundle

#### Scenario: Dangerous bundle destination is rejected

- **WHEN** `--bundle-root` receives `/`, the current user's home directory, or an empty value
- **THEN** the generator exits non-zero before any cleanup and names the rejected destination class

### Requirement: Pinned runtime provenance

The hand-maintained source bundle SHALL include a byte-for-byte snapshot of `PsychQuant/parallel-ai-agents` `codex-call` from commit `6fc6883ef1d655f5f782a97accc0a5adacc76226`. Provenance data SHALL record repository, source path, commit, Git blob `c2418f5c0a0a3d092859d6252d2910c460dee981`, raw URL, size `25329`, mode `100755`, SHA-256 `fa80364b2159f3df4f2d9a27c885a7b50e510bf52933abaa79564945bedb6af0`, MIT license, and known upstream issue identifiers. Updating the snapshot MUST use an immutable commit and MUST update provenance and verification tests in the same change.

#### Scenario: Vendored bytes match the pinned source fingerprint

- **WHEN** the runtime provenance test hashes and stats the source and both generated snapshots
- **THEN** all three files are executable, 25,329 bytes, and match the recorded SHA-256

#### Scenario: Mutable upstream reference is not used

- **WHEN** the provenance JSON and synchronization documentation are inspected
- **THEN** the download URL contains the full pinned commit and no update instruction fetches mutable `main`

### Requirement: Runtime wrapper preflight and execution

Each complete bundle SHALL contain `bin/codex-pro-call` and `bin/codex-call`. The wrapper SHALL derive its own bundle path from `$0`; verify Darwin, an executable Swift compiler, executable runtime mode, and the pinned runtime SHA-256; and then execute the snapshot with the original argument vector. `--check` SHALL perform only these local checks, SHALL NOT execute the snapshot, SHALL NOT read or modify OAuth data, and SHALL NOT access the network. The wrapper SHALL preserve the snapshot exit status and MUST NOT retry.

#### Scenario: Read-only wrapper check succeeds

- **WHEN** `bin/codex-pro-call --check` runs on macOS with Swift and the pinned executable snapshot
- **THEN** it exits 0 and prints one line containing `ok`, the absolute runtime path, recorded SHA-256, and Swift version

#### Scenario: Wrapper failures are machine-readable

- **WHEN** a preflight condition fails
- **THEN** the wrapper exits non-zero and prints one line beginning with the matching error class

##### Example: Preflight error classes

| Condition | Expected prefix |
| --- | --- |
| host is not Darwin | `error=unsupported_platform` |
| Swift cannot execute | `error=swift_missing` |
| runtime file is absent | `error=runtime_missing` |
| runtime is not executable | `error=runtime_not_executable` |
| SHA-256 differs | `error=hash_mismatch` |

#### Scenario: Arguments and exit status pass through

- **WHEN** preflight succeeds and the wrapper receives runtime arguments
- **THEN** the snapshot receives the same ordered arguments exactly once and the wrapper exits with the snapshot exit status

### Requirement: Skill-relative runtime resolution

The generated Codex setup, review, adversarial-review, and rescue skills SHALL set `SKILL_DIR` from the active SKILL.md absolute location supplied by Codex, derive `BUNDLE_ROOT` as two parent directories above it, and prefer `BUNDLE_ROOT/bin/codex-pro-call`. They MUST NOT infer the skill location from the current working directory, scan Codex cache directories, read `CODEX_HOME`, or require `PLUGIN_ROOT`, `CODEX_PLUGIN_ROOT`, `CODEX_SKILL_ROOT`, or `CLAUDE_PLUGIN_ROOT`.

If the bundle contains `.codex-plugin/plugin.json` or `.codex-bundle-files` but its wrapper is missing or non-executable, the generated skill SHALL fail closed as package corruption. A final `command -v codex-call` fallback SHALL be permitted only when neither native marker exists, preserving an explicitly identified legacy project mirror.

#### Scenario: Installed native producer uses bundled runtime

- **WHEN** a native installed producer skill runs with no external `codex-call` on PATH
- **THEN** it invokes the wrapper inside the same installed plugin bundle

#### Scenario: Native corruption does not fall back to PATH

- **WHEN** a native bundle marker exists, its wrapper is missing, and an unrelated `codex-call` exists on PATH
- **THEN** the skill reports package corruption and does not invoke the PATH executable

#### Scenario: Legacy project mirror retains compatibility

- **WHEN** a legacy Codex mirror has no bundle inventory or native manifest and has `codex-call` on PATH
- **THEN** the skill uses that PATH executable and identifies the resolution as a legacy fallback

### Requirement: Platform-scoped producer capability

The plugin SHALL remain installable on supported Codex surfaces, and its pure local consumer skills SHALL remain usable without the bundled producer runtime. The bundled review, adversarial-review, and rescue runtime SHALL be declared macOS-only with Xcode Command Line Tools Swift. On unsupported platforms, setup SHALL report producer unavailability and SHALL distinguish that result from consumer skill availability.

#### Scenario: Consumer skill remains available on a non-macOS host

- **WHEN** a non-macOS user invokes status, result, config, or cancel
- **THEN** the skill performs its existing local behavior without executing `codex-pro-call`

#### Scenario: Producer stops before OAuth or network access on a non-macOS host

- **WHEN** a non-macOS user invokes review, adversarial-review, or rescue
- **THEN** runtime preflight returns `error=unsupported_platform` before reading OAuth data or accessing the network

### Requirement: Cross-harness version consistency

The Codex manifest, Claude plugin manifest, and Claude marketplace entry SHALL all declare version `0.8.0`. A version change MUST update all three in the same commit, and the release notes SHALL identify Codex native plugin distribution as the 0.8.0 feature.

#### Scenario: Version drift blocks the release gate

- **WHEN** any one of the three version values differs
- **THEN** the automated plugin test fails and identifies every mismatched manifest path
