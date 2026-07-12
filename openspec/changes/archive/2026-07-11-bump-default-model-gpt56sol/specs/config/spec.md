## MODIFIED Requirements

### Requirement: Config profile resolution algorithm — two-layer with project priority

The skill SHALL resolve the effective profile by loading two YAML files in order: (1) `~/.codex-pro/profile.yaml` as the global layer; (2) `<cwd>/.codex-pro/profile.yaml` as the project layer (where `<cwd>` is the invocation working directory). Field-level merging applies: a field present in the project layer SHALL override the same field in the global layer; a field present only in the global layer SHALL apply; a field absent from both layers SHALL fall back to hardcoded defaults (`model: gpt-5.6-sol`, `effort: xhigh`, `max_time: 600`, `focus_default: ""` (empty string)). Resolution SHALL be lazy per invocation — no caching between runs. Missing files (either layer) SHALL be treated as an empty layer and SHALL NOT raise an error. Malformed YAML (parse failure) SHALL be treated as an empty layer (silent fallback for that layer). Unknown fields in profile YAML SHALL be silently ignored (forward-compat with future schema additions). Field type mismatches (e.g. `max_time: "abc"` instead of int) SHALL cause that single field to fall back to its hardcoded default (other fields unaffected).

#### Scenario: Both layers missing — all defaults

- **WHEN** the skill runs in an environment where neither `~/.codex-pro/profile.yaml` nor `<cwd>/.codex-pro/profile.yaml` exists
- **THEN** the resolved profile SHALL contain all hardcoded defaults
- **AND** all 4 rows in the output table SHALL show source `(default)`

#### Scenario: Only global layer — global wins for set fields

- **WHEN** the skill runs with `~/.codex-pro/profile.yaml` containing `{model: gpt-5.0}` and no project file
- **THEN** the resolved profile SHALL set `model` to `gpt-5.0` with source `global`
- **AND** the other 3 fields SHALL show source `(default)`

#### Scenario: Project layer overrides global for set fields

- **WHEN** the skill runs with `~/.codex-pro/profile.yaml` containing `{model: gpt-5.0, max_time: 900}` and `<cwd>/.codex-pro/profile.yaml` containing `{max_time: 1200}`
- **THEN** the resolved profile SHALL set `model` to `gpt-5.0` with source `global`
- **AND** SHALL set `max_time` to `1200` with source `project`
- **AND** the other 2 fields SHALL show source `(default)`

#### Scenario: Malformed YAML silently falls back

- **WHEN** the skill runs with `<cwd>/.codex-pro/profile.yaml` containing invalid YAML (e.g. a missing colon)
- **THEN** the project layer SHALL be treated as empty
- **AND** the skill SHALL NOT raise an error
- **AND** the skill SHALL exit 0 with the global layer (or defaults) applied

#### Scenario: Unknown profile field is silently ignored

- **WHEN** the skill runs with `<cwd>/.codex-pro/profile.yaml` containing `{model: gpt-5.0, future_field: foo}`
- **THEN** the resolved profile SHALL set `model` to `gpt-5.0`
- **AND** the output table SHALL NOT include a row for `future_field` (only the 4 known fields)

### Requirement: Config v0.1 schema is exactly 4 fields

The v0.1 profile schema SHALL contain exactly 4 fields with the types and defaults specified below. The `/codex-pro:codex-config` output table SHALL contain exactly 4 rows, one per schema field, in the listed order.

| Field | YAML type | Hardcoded default | Producer skills that use it |
| --- | --- | --- | --- |
| `model` | string | `gpt-5.6-sol` | review / rescue / adversarial-review |
| `effort` | string | `xhigh` | review / rescue / adversarial-review |
| `max_time` | int (seconds) | `600` | review / rescue / adversarial-review |
| `focus_default` | string | `""` (empty) | adversarial-review only |

`max_findings`, `sandbox`, retry/backoff, timeout-per-skill, multi-profile, named profiles, env-var overrides, model-escalation fields, and schema versioning are explicitly OUT of v0.1 scope (the model-escalation field was evaluated and rejected during issue #3: `gpt-5.6-sol` is already the top available model on the codex-call path, so an escalation target does not exist).

#### Scenario: Output table has exactly 4 rows in canonical order

- **WHEN** a user invokes `/codex-pro:codex-config`
- **THEN** the output table body SHALL contain exactly 4 rows
- **AND** the rows SHALL appear in this order: `model`, `effort`, `max_time`, `focus_default`

##### Example: full default state

| field          | resolved value | source    |
| -------------- | -------------- | --------- |
| model          | gpt-5.6-sol    | (default) |
| effort         | xhigh          | (default) |
| max_time       | 600            | (default) |
| focus_default  |                | (default) |

#### Scenario: focus_default is read by adversarial-review only

- **WHEN** the resolved profile sets `focus_default: security` and `/codex-pro:codex-adversarial-review` is invoked WITHOUT a `--focus` argument
- **THEN** the adversarial-review skill SHALL use `security` as the focus value
- **WHEN** `/codex-pro:codex-review` or `/codex-pro:codex-rescue` is invoked under the same profile
- **THEN** the `focus_default` field SHALL NOT affect their behavior (silently unused)
