## Purpose

Visual cross-validation lets Claude and Codex judge the same set of images independently, compares their per-frame claims with deterministic code, and settles disagreements only with a third kind of evidence. It exists because a single model misreading an image does not notice its own error.

## ADDED Requirements

### Requirement: Runtime image capability preflight

The `codex-visual-xval` skill SHALL confirm, before reading OAuth data or sending any request, that the resolved `codex-call` runtime accepts the `--image` option, by checking that the runtime's help output lists `--image`. When the runtime does not list `--image`, the skill SHALL write its result file with `error: runtime_unsupported`, SHALL NOT invoke the runtime with image arguments, and SHALL NOT retry.

#### Scenario: Old runtime is refused before sending

- **WHEN** the resolved `codex-call` help output does not contain `--image`
- **THEN** the skill writes a result file with `error: runtime_unsupported` and no request is sent

#### Scenario: Supporting runtime proceeds

- **WHEN** the resolved `codex-call` help output contains `--image`
- **THEN** the skill continues to image validation

### Requirement: Claim schema and closed vocabulary

Each judgment SHALL be expressed as per-frame claims against a vocabulary file that lists the allowed object classes, the physical constraints, the relations with their quantitative definitions, and the position threshold as a percentage of image width (default 5). A claim SHALL record, for one frame, the count of each class, the key points of objects as percentages of image width and height, what each point touches, and the value of each relation. Objects that fit no listed class SHALL be recorded as class `other` with a description. A relation without a quantitative definition in the vocabulary file SHALL make the input invalid.

#### Scenario: Relation without a threshold is rejected

- **WHEN** the vocabulary file defines the relation `tips_together` with no numeric definition
- **THEN** the skill writes a result file with `error: target_invalid` naming that relation, before any request is sent

### Requirement: Sealed Claude answers

Claude's claims SHALL be written to a file inside the run directory, and its SHA-256 digest and timestamp SHALL be recorded before Codex is called. Before comparison, the skill SHALL recompute the digest; when it differs, the result file SHALL set `seal_broken: true` and the conclusion SHALL state that the seal failed.

#### Scenario: Unchanged answers keep the seal

- **WHEN** the Claude answer file is not modified between sealing and comparison
- **THEN** the result file records the same digest twice and `seal_broken: false`

#### Scenario: Edited answers break the seal

- **WHEN** the Claude answer file is modified after sealing
- **THEN** the result file records `seal_broken: true`

### Requirement: Blind Codex judgment

The skill SHALL send the images to Codex only through `codex-call`, passing each image with `--image`, under neutral file names that carry no timestamps or hints, together with the vocabulary and the claim schema. The prompt SHALL NOT include Claude's claims, Claude's conclusions, or any summary of them. The call SHALL run in the foreground with the profile's hard timeout. A reply that is not valid JSON matching the claim schema SHALL produce `error: parse_failed` without retry.

#### Scenario: Prompt carries no Claude answers

- **WHEN** the request body assembled for Codex is inspected
- **THEN** it contains the images, the vocabulary, and the schema, and none of the Claude claim values

### Requirement: Deterministic comparison

A comparison script SHALL compare the two claim sets frame by frame and SHALL classify each disagreement as exactly one of: count mismatch, position mismatch, or relation mismatch. Objects of the same class SHALL be paired by nearest distance before positions are compared; a position mismatch is a paired distance greater than the vocabulary's position threshold. The agreement rate SHALL be the number of frames with no disagreement divided by the number of frames compared.

#### Scenario: Same counts and close positions agree

- **WHEN** both claim sets report two instruments in a frame and every paired tip differs by no more than the position threshold
- **THEN** the frame has no count or position mismatch

##### Example: Relation disagreement in an otherwise agreeing frame

| Field | Claude claim | Codex claim | Classification |
| --- | --- | --- | --- |
| instrument count | 2 | 2 | agree |
| tip positions (x%, y%) | (31, 19), (33, 21) | (32, 20), (30, 22) | agree, paired distances under 5% |
| `tips_together` (distance_pct < 5) | true | false | relation mismatch |

The frame counts as a disagreement, so with 12 frames and this as the only disagreement the agreement rate is 11 / 12.

### Requirement: Zoom round

For each frame with a disagreement, the skill SHALL crop the region around the disputed points, enlarge it, and send the crops to Codex in a second request through `codex-call --image`, asking for the same claim fields for the cropped region only. The second request SHALL NOT include either side's earlier answers.

#### Scenario: Only disputed regions are re-sent

- **WHEN** 1 of 12 frames has a disagreement
- **THEN** the second request carries crops of that 1 frame only

### Requirement: Built-in SAM evidence

The skill SHALL include a SAM 2.1 tracking step, using model `facebook/sam2.1-hiera-large`, inside a dedicated environment at `~/.codex-pro/sam-env/`. Before the first installation, the skill SHALL state the estimated download size and SHALL install only after the user agrees. Tracking SHALL use frames where both claim sets agree as anchors, with the agreed positions as prompt points, and SHALL re-anchor at every run of agreeing frames. When the masks of two tracked objects in a frame have intersection-over-union greater than 0.5, that frame SHALL be marked invalid and SHALL NOT be used to settle a disagreement. When the environment is not installed or the user declines installation, the result file SHALL record `sam_status: not_installed` and the run SHALL continue without failing.

#### Scenario: Collapsed masks are not evidence

- **WHEN** two tracked objects have masks with intersection-over-union 0.7 in a disputed frame
- **THEN** that frame is marked invalid and the disagreement is not settled by SAM

#### Scenario: Declined installation degrades gracefully

- **WHEN** the user declines the SAM installation
- **THEN** the run completes, the result file records `sam_status: not_installed`, and disagreements that needed SAM are marked `unverifiable`

### Requirement: Adjudication without majority vote

Each disagreement SHALL end as exactly one of `resolved_claude`, `resolved_codex`, or `unverifiable`. Only third evidence SHALL settle a disagreement: matching answers from the zoom round, a measurement from a valid SAM frame, or a violated physical constraint from the vocabulary. A SAM measurement SHALL count as evidence only when it lies farther from the relevant threshold than the SAM margin, which defaults to 1 percent of image width and can be set by `sam_margin_pct` in the vocabulary file; a measurement within the margin is not evidence. When the available pieces of evidence point to different sides, the disagreement SHALL be `unverifiable`. No request to either model SHALL contain the other model's claims, and an answer already recorded SHALL NOT be replaced by a later answer from the same model. Without valid third evidence, the disagreement SHALL be `unverifiable`.

#### Scenario: A measurement within the SAM margin is not evidence

- **WHEN** a relation mismatch on `tips_together` (defined as distance_pct < 5) has only one piece of evidence, a valid SAM frame measuring the tips 5.18% of the image width apart, and the SAM margin is 1
- **THEN** the measurement is not used and the disagreement is `unverifiable`

#### Scenario: Disagreement without valid evidence stays unverifiable

- **WHEN** a disagreement has no matching zoom-round answers, every SAM frame for it is invalid, and no physical constraint is violated
- **THEN** the disagreement is recorded as `unverifiable` and no further request carries either model's claims

##### Example: SAM settles a relation mismatch

- **GIVEN** a relation mismatch on `tips_together` defined as distance_pct < 5, Claude says true and Codex says false
- **WHEN** a valid SAM frame measures the two tips 3.5% of the image width apart, farther from the threshold than the default margin of 1
- **THEN** the disagreement is `resolved_claude` with the SAM measurement recorded as evidence

### Requirement: Structured result file

Every run SHALL write `.codex-pro/visual-xval-<ISO8601-timestamp>.md`. Its frontmatter SHALL include the skill name, model, effort, profile source, error, `n_images`, `n_claims`, `agreement_rate`, `claude_answers_sha256`, `sealed_at`, `seal_broken`, and `sam_status`. Its body SHALL contain, in order: the agreement rate and disagreement summary, each disagreement with its classification, adjudication and evidence, the SAM status with invalid frame count and anchors, the seal verification, and the limitations, which SHALL state that agreement between the two models does not establish correctness. Failures of the classes `rate_limit`, `oauth_invalid`, `timeout`, `target_invalid`, `runtime_unsupported`, `parse_failed`, `runtime_unavailable`, and `package_corruption` SHALL each write this file and SHALL NOT retry.

#### Scenario: Failed run still leaves a result file

- **WHEN** the run stops with `error: timeout`
- **THEN** a result file exists with that error in its frontmatter and the status skill can list it

### Requirement: Privacy reminder before sending images

Before the first request in a run, the skill SHALL remind the user that the images will be sent to OpenAI and that content which must not leave the machine has to be masked first. The skill SHALL NOT decide on the user's behalf which content to mask.

#### Scenario: Reminder precedes the first request

- **WHEN** a run reaches the point of sending images
- **THEN** the privacy reminder has been shown earlier in that run
