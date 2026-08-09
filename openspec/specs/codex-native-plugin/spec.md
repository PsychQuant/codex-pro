# codex-native-plugin Specification

## Purpose

TBD - created by archiving change 'add-native-codex-plugin'. Update Purpose after archive.

## Requirements

### Requirement: Native Codex plugin manifest

The repository SHALL provide `.codex-plugin/plugin.json` as a valid skills-only Codex plugin manifest. The manifest SHALL declare `name` as `codex-pro`, strict SemVer `version` as `0.8.0`, `skills` as `./skills/`, a non-empty description, `author.name`, and install-surface `interface` metadata containing display name, short description, long description, developer name, category, capabilities, website URL, and one to three starter prompts. The manifest MUST NOT declare apps, MCP servers, hooks, or asset paths without corresponding package files.

#### Scenario: Plugin validator accepts the manifest

- **WHEN** the repository root is validated with the current Codex plugin validator
- **THEN** validation succeeds with no placeholder, schema, path, or missing-file errors

#### Scenario: Skills path targets the native bundle

- **WHEN** Codex resolves the manifest `skills` field relative to the repository root
- **THEN** it resolves to the generated root `skills/` directory containing exactly the nine names in `scripts/codex-skills.manifest`


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
### Requirement: Self-hosted repository marketplace

The repository SHALL provide `.agents/plugins/marketplace.json` with top-level marketplace name `codex-pro` and one plugin entry named `codex-pro`. The entry SHALL use local source path `./`, installation policy `AVAILABLE`, authentication policy `ON_INSTALL`, and category `Developer Tools`, so a Git marketplace snapshot uses its own repository root as the plugin payload.

#### Scenario: Git marketplace exposes the root plugin

- **WHEN** Codex adds `PsychQuant/codex-pro` as a marketplace at ref `main`
- **THEN** the marketplace lists `codex-pro` and its source resolves inside that same snapshot to a directory containing `.codex-plugin/plugin.json`

#### Scenario: Local marketplace exposes uncommitted development state

- **WHEN** Codex adds the local repository root as a marketplace
- **THEN** the same entry resolves to the current repository root without a copied staging plugin


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
### Requirement: Complete generated Codex bundles

`plugins/codex-pro/` SHALL remain the only hand-maintained source for Codex skill content and runtime resources. Running `scripts/generate-codex-skills.sh` without arguments SHALL update two complete bundle roots: `.codex/` and the repository root. Each bundle SHALL contain generated `skills/`, `references/`, `bin/`, and a sorted `.codex-bundle-files` ownership inventory. The nine skill directories, every manifest-listed skill-local resource, shared reference, wrapper, and runtime snapshot SHALL be byte-identical between both bundle roots, except generated SKILL.md content that is deterministically transformed from the Claude source and is itself identical across the two Codex bundles.

Every resource-manifest source and publish entry MUST name a file below its allowed subtree. A `skills/` entry MUST use `skills/<expected-skill>/<child-file>`; `references/`, `runtime/`, and `bin/` entries MUST contain at least one child component. Before writing the ownership inventory or applying a staged bundle, the generator SHALL independently enumerate staged regular files and require that exact set to equal the expected inventory.

Every expected source skill directory and its `SKILL.md` MUST be a regular in-bundle directory/file pair, not a symbolic link, and MUST resolve inside `plugins/codex-pro/`. Source containment SHALL be validated before creating or mutating any destination.

#### Scenario: Fresh full-bundle regeneration matches committed outputs

- **WHEN** the generator produces a bundle in a new temporary directory using `--bundle-root`
- **THEN** recursive comparison against both committed bundles reports no missing, extra, stale, or different generated files

#### Scenario: Batch template and shared references are present

- **WHEN** generated skill-relative Markdown links are resolved from each SKILL.md
- **THEN** `codex-batch/references/script-template.sh`, `references/defaults.json`, and `references/profile-contract.md` exist at their referenced locations in both bundles

#### Scenario: Cleanup remains bounded to generated ownership

- **WHEN** a former generated resource is removed from the explicit resource manifest and the generator runs again
- **THEN** the stale path recorded in the prior ownership inventory is removed while unrelated files elsewhere in the bundle root remain unchanged

#### Scenario: Owned skill directories contain no untracked residue

- **WHEN** recursive parity enumerates every file below each expected generated skill directory
- **THEN** an extra file not named by the current skill and resource manifests causes parity to fail, while files outside generator-owned expected skill directories remain governed by the bounded ownership inventory

#### Scenario: Resource publish path cannot name a skill directory

- **WHEN** a resource mapping publishes to `skills/<expected-skill>` without a child file path
- **THEN** generation exits non-zero before writing an ownership inventory or applying any bundle content

#### Scenario: Source skill symlink escape is rejected

- **WHEN** an expected source `SKILL.md` is a symbolic link to content outside `plugins/codex-pro/`
- **THEN** generation exits non-zero before writing any generated output


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
### Requirement: Backward-compatible generator interfaces

The generator SHALL support `--bundle-root <path>` for one complete bundle and SHALL preserve `--output <skills-dir>` as a skill-only compatibility interface. The generator MUST reject an empty destination, `/`, the current user's home directory, and any destination that cannot be resolved safely before deleting or replacing generated content. Skill manifest entries MUST be unique safe single path components. The skill-only interface MUST reject an expected skill directory, its `SKILL.md`, or an existing parent chain that is a symbolic link or resolves outside the validated output root before any mutation. Orphan enumeration MUST preserve filename boundaries, validate every removal candidate as a direct child, and reject line-break-bearing directory names before deleting any orphan. Complete-bundle ownership validation MUST reject an expected `SKILL.md` symbolic link before reading its generated marker.

In default mode, the generator SHALL stage and validate both committed bundle destinations, including prior inventories and existing generated skill ownership, before mutating either destination. This pre-apply validation requirement does not claim crash-safe atomicity across two bundle roots.

#### Scenario: Legacy skill-only caller remains valid

- **WHEN** an existing test invokes the generator with `--output <temporary-skills-directory>`
- **THEN** the generator writes the nine transformed skill directories without changing either committed bundle

#### Scenario: Dangerous bundle destination is rejected

- **WHEN** `--bundle-root` receives `/`, the current user's home directory, or an empty value
- **THEN** the generator exits non-zero before any cleanup and names the rejected destination class

#### Scenario: Skill-only child symlink escape is rejected

- **WHEN** `--output` targets a safe temporary directory whose expected skill child or `SKILL.md` is a symbolic link to a path outside that directory
- **THEN** the generator exits non-zero before changing either the link target or any generated file

#### Scenario: Orphan filename cannot escape cleanup framing

- **WHEN** a direct-child orphan directory contains a newline that could be split into a caller-relative path
- **THEN** the generator exits non-zero before deletion and preserves every path outside the validated output root

#### Scenario: Complete-bundle ownership marker cannot be external

- **WHEN** an expected generated skill's `SKILL.md` is a symbolic link to an external file containing the generated marker
- **THEN** complete-bundle validation exits non-zero without trusting or modifying the external file

#### Scenario: Default destinations are validated as a set

- **WHEN** either committed bundle has an unsafe prior inventory, child symlink, or non-generated expected skill directory
- **THEN** the generator exits non-zero without changing the other committed bundle


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
### Requirement: Pinned runtime provenance

The hand-maintained source bundle SHALL include a byte-for-byte snapshot of `PsychQuant/parallel-ai-agents` `codex-call` from commit `6fc6883ef1d655f5f782a97accc0a5adacc76226`. The source snapshot and wrapper SHALL be stored outside the Claude plugin root `bin/` directory, and the resource manifest SHALL map them into each generated native bundle as `bin/codex-call` and `bin/codex-pro-call`. The Claude plugin package MUST NOT contribute either executable to the automatic Bash PATH and SHALL retain external PATH resolution for its unmodified Claude skills. Because Claude marketplace installation copies only `plugins/codex-pro/`, that package root SHALL include a complete MIT `LICENSE` and a third-party notice identifying the vendored snapshot and immutable commit; it MUST NOT depend on repository-root notice files for license compliance. Provenance data SHALL record repository, source path, commit, Git blob `c2418f5c0a0a3d092859d6252d2910c460dee981`, raw URL, size `25329`, mode `100755`, SHA-256 `fa80364b2159f3df4f2d9a27c885a7b50e510bf52933abaa79564945bedb6af0`, MIT license, and known upstream issue identifiers. Updating the snapshot MUST use an immutable commit and MUST update provenance and verification tests in the same change.

#### Scenario: Vendored bytes match the pinned source fingerprint

- **WHEN** the runtime provenance test hashes and stats the source and both generated snapshots
- **THEN** all three files are executable, 25,329 bytes, and match the recorded SHA-256

#### Scenario: Mutable upstream reference is not used

- **WHEN** the provenance JSON and synchronization documentation are inspected
- **THEN** the download URL contains the full pinned commit and no update instruction fetches mutable `main`

#### Scenario: Native runtime source does not shadow Claude PATH

- **WHEN** the Claude plugin payload rooted at `plugins/codex-pro/` is inspected or loaded with its automatic `bin/` PATH behavior
- **THEN** it contains no root `bin/codex-call` or `bin/codex-pro-call`, while a generated native bundle contains both mapped executables

#### Scenario: Claude subpackage carries the upstream license notice

- **WHEN** only `plugins/codex-pro/` is copied into a Claude marketplace cache
- **THEN** that isolated package still contains the complete MIT text and a notice identifying `runtime/codex-call` and its immutable upstream commit


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
### Requirement: Skill-relative runtime resolution

The generated Codex setup, review, adversarial-review, and rescue skills SHALL set `SKILL_DIR` from the active SKILL.md absolute location supplied by Codex, derive `BUNDLE_ROOT` as two parent directories above it, and prefer `BUNDLE_ROOT/bin/codex-pro-call`. They MUST NOT infer the skill location from the current working directory, scan Codex cache directories, read `CODEX_HOME`, or require `PLUGIN_ROOT`, `CODEX_PLUGIN_ROOT`, `CODEX_SKILL_ROOT`, or `CLAUDE_PLUGIN_ROOT`.

If the bundle contains `.codex-plugin/plugin.json` or `.codex-bundle-files` but its wrapper is missing, not a regular file, or non-executable, the generated skill SHALL fail closed as package corruption. A directory or special file MUST NOT pass as a wrapper merely because its path satisfies `test -x`. A broken symbolic link at either native marker path SHALL still count as native package state and MUST NOT reopen PATH fallback. A final `command -v codex-call` fallback SHALL be permitted only when neither native marker path exists, preserving an explicitly identified legacy project mirror.

The generated producer resolver MUST NOT terminate the skill before result handling. It SHALL set a stable preflight error and detail, skip runtime execution, OAuth access, and network access, and continue to the existing result-writing step. Missing, non-regular, or non-executable native wrapper/runtime and integrity mismatch SHALL map to `package_corruption`; unsupported platform, missing Swift, missing legacy PATH runtime, and other runtime availability failures SHALL map to `runtime_unavailable`. Review, adversarial-review, and rescue SHALL preserve their existing result shapes while permitting these two native-only frontmatter error values, and every such failure SHALL write a result file without retrying. The result body SHALL include a sanitized and bounded representation of the preflight detail; raw control characters or unbounded wrapper output MUST NOT be copied into frontmatter.

#### Scenario: Installed native producer uses bundled runtime

- **WHEN** a native installed producer skill runs with no external `codex-call` on PATH
- **THEN** it invokes the wrapper inside the same installed plugin bundle

#### Scenario: Native corruption does not fall back to PATH

- **WHEN** a native bundle marker exists, its wrapper is missing, and an unrelated `codex-call` exists on PATH
- **THEN** the skill reports package corruption and does not invoke the PATH executable

#### Scenario: Broken native marker still prevents PATH fallback

- **WHEN** a native marker path is a broken symbolic link and the bundled wrapper is missing
- **THEN** the skill reports package corruption and does not resolve or invoke a PATH executable

#### Scenario: Wrapper directory is not executable runtime

- **WHEN** the native wrapper path names a searchable directory instead of a regular executable file
- **THEN** the skill classifies the package as corrupt before attempting execution

#### Scenario: Legacy project mirror retains compatibility

- **WHEN** a legacy Codex mirror has no bundle inventory or native manifest and has `codex-call` on PATH
- **THEN** the skill uses that PATH executable and identifies the resolution as a legacy fallback

#### Scenario: Native preflight failure remains observable

- **WHEN** review, adversarial-review, or rescue encounters a package-corruption or runtime-unavailable preflight state
- **THEN** it does not invoke the runtime and writes its normal structured result file with `error: package_corruption` or `error: runtime_unavailable` plus a sanitized, bounded preflight detail in the result body


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
### Requirement: Platform-scoped producer capability

The plugin SHALL remain installable on supported Codex surfaces, and its pure local consumer skills SHALL remain usable without the bundled producer runtime. The bundled review, adversarial-review, and rescue runtime SHALL be declared macOS-only with Xcode Command Line Tools Swift. On unsupported platforms, setup SHALL report producer unavailability and SHALL distinguish that result from consumer skill availability.

#### Scenario: Consumer skill remains available on a non-macOS host

- **WHEN** a non-macOS user invokes status, result, config, or cancel
- **THEN** the skill performs its existing local behavior without executing `codex-pro-call`

#### Scenario: Producer stops before OAuth or network access on a non-macOS host

- **WHEN** a non-macOS user invokes review, adversarial-review, or rescue
- **THEN** runtime preflight returns `error=unsupported_platform` before reading OAuth data or accessing the network


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
### Requirement: Cross-harness version consistency

The Codex manifest, Claude plugin manifest, and Claude marketplace entry SHALL all declare version `0.8.0`. A version change MUST update all three in the same commit, and the release notes SHALL identify Codex native plugin distribution as the 0.8.0 feature.

#### Scenario: Version drift blocks the release gate

- **WHEN** any one of the three version values differs
- **THEN** the automated plugin test fails and identifies every mismatched manifest path

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