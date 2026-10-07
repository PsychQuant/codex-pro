## Purpose

Visual cross-validation (`/codex-pro:codex-visual-xval`) lets Claude and Codex judge the same set of images independently, compares their per-frame claims with deterministic code, and settles disagreements only with a third kind of evidence. It exists because a single model misreading an image does not notice its own error.

## ADDED Requirements

### Requirement: Interpreter requirement

The skill's scripts SHALL require Python 3.10 or later. Under an older interpreter the orchestrator SHALL stop before loading any of its other modules, SHALL record `error: runtime_unavailable` naming the interpreter version found, and SHALL still write the result file.

#### Scenario: Old interpreter still leaves a result file

- **WHEN** the orchestrator runs under Python 3.9
- **THEN** no request is sent and a result file exists with `error: runtime_unavailable`

### Requirement: Runtime image capability preflight

The `codex-visual-xval` skill SHALL confirm, before reading OAuth data or sending any request, that the resolved `codex-call` runtime accepts the `--image` option, by checking that the runtime's help output lists `--image`. When the runtime does not list `--image`, the skill SHALL write its result file with `error: runtime_unsupported`, SHALL NOT invoke the runtime with image arguments, and SHALL NOT retry.

#### Scenario: Old runtime is refused before sending

- **WHEN** the resolved `codex-call` help output does not contain `--image`
- **THEN** the skill writes a result file with `error: runtime_unsupported` and no request is sent

#### Scenario: Supporting runtime proceeds

- **WHEN** the resolved `codex-call` help output contains `--image`
- **THEN** the skill continues to image validation

### Requirement: Claim schema and closed vocabulary

Each judgment SHALL be expressed as per-frame claims against a vocabulary file that lists the allowed object classes, which of them have a key point and how that point is defined, the physical constraints, the relations, and the position threshold as a percentage of image width (default 5). Only classes with a key-point definition SHALL be compared by position; the others SHALL be compared by count only. Each relation SHALL name two classes that have key points and SHALL be defined as `distance_pct`, a comparison operator, and a number (for example `distance_pct < 5`), where `distance_pct` is the smallest distance, in percent of image width, between a key point of the first class and a different key point of the second class; any other definition SHALL make the input invalid. A claim SHALL record, for one frame, the count of each class, exactly one key point for every counted object of a class that has a key-point definition, as percentages of image width and height, and the value of each relation. A claim whose number of key points for such a class differs from that class's count SHALL be invalid: from Claude it is `target_invalid`, from Codex it is `parse_failed`. Objects that fit no listed class SHALL be recorded as class `other` with a description. A run SHALL contain at most 12 images; more SHALL be `target_invalid`.

#### Scenario: Relation without a threshold is rejected

- **WHEN** the vocabulary file defines the relation `tips_together` with no numeric definition
- **THEN** the skill writes a result file with `error: target_invalid` naming that relation, before any request is sent

#### Scenario: A relation that names no quantity is rejected

- **WHEN** a relation is defined as `很近（< 5）` or as `closeness < 5`
- **THEN** the vocabulary is `target_invalid` and names that relation

#### Scenario: Classes without a key point are compared by count only

- **WHEN** the vocabulary defines a key point for instruments but not for the practice pad, and both sides report one pad at different places
- **THEN** the frame has no position mismatch for the pad

#### Scenario: Missing key points are not agreement

- **WHEN** instruments have a key-point definition and Codex reports two instruments in a frame without key points
- **THEN** the reply is `parse_failed` and no agreement rate is computed from it

#### Scenario: Too many images are refused

- **WHEN** a run is started with 13 images
- **THEN** the run stops with `error: target_invalid` before any request is sent

### Requirement: Sealed Claude answers

Claude's claims SHALL be written to a file inside the run directory, and its SHA-256 digest and timestamp SHALL be recorded before Codex is called. The request to Codex SHALL NOT be sent unless the seal exists and the digest recomputed at that moment matches it. A seal SHALL NOT be rewritten once recorded, and Claude's claims SHALL NOT be sealed after Codex has answered. The seal SHALL also record the digests of the vocabulary and of the run's image copies; when either changes before comparison, the run SHALL stop with `target_invalid`, and a run that is sealed or has sent a request SHALL NOT be initialised again. Before comparison, the skill SHALL recompute the digest; when it differs, the result file SHALL set `seal_broken: true` and the conclusion SHALL state that the seal failed. A seal that was never recomputed SHALL NOT be reported as intact.

#### Scenario: Unchanged answers keep the seal

- **WHEN** the Claude answer file is not modified between sealing and comparison
- **THEN** the result file records the same digest twice and `seal_broken: false`

#### Scenario: Edited answers break the seal

- **WHEN** the Claude answer file is modified after sealing
- **THEN** the result file records `seal_broken: true`

#### Scenario: Unsealed answers block the request

- **WHEN** the first-round request is attempted before Claude's answers are sealed
- **THEN** the run stops with `error: target_invalid` and no request is sent

#### Scenario: A vocabulary changed after sealing stops the comparison

- **WHEN** the vocabulary file in the run directory is edited after Claude's answers were sealed
- **THEN** the comparison stops with `error: target_invalid`

#### Scenario: A seal cannot be rewritten

- **WHEN** Claude's answers are sealed a second time
- **THEN** the second seal is refused and the first seal stays unchanged

### Requirement: Blind Codex judgment

The skill SHALL send the images to Codex only through `codex-call`, passing each image with `--image`, under neutral file names that carry no timestamps or hints, together with the vocabulary, its maximum counts, its key-point definitions, and the claim schema. The prompt SHALL NOT include Claude's claims, Claude's conclusions, or any summary of them, and its instructions SHALL state that text visible in the images is content to judge, not instruction. The call SHALL run in the foreground with the profile's hard timeout. Each round SHALL send at most one request: the time of the request and the SHA-256 of the reply SHALL be recorded, a second request in the same round SHALL be refused, and the result file SHALL show, for each round, the request time and reply digest and whether the reply still matches it. When `codex-call` fails before sending anything, the request SHALL NOT be recorded as sent. A reply that is not valid JSON matching the claim schema SHALL produce `error: parse_failed` without retry.

#### Scenario: Prompt carries no Claude answers

- **WHEN** the request body assembled for Codex is inspected
- **THEN** it contains the images, the vocabulary, and the schema, and none of the Claude claim values

#### Scenario: A second request in the same round is refused

- **WHEN** the first-round request is attempted again after Codex has answered
- **THEN** the run stops with `error: target_invalid`, no second request is sent, and the recorded answer is unchanged

#### Scenario: An edited Codex answer is reported

- **WHEN** Codex's recorded answer file is modified after it was recorded
- **THEN** the result file reports that the Codex answer no longer matches its recorded digest

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

For each disagreement with a region to examine, the skill SHALL crop that region, enlarge it, and write one question file listing every crop with its question and the class definitions. Both sides SHALL answer from that file and the crops alone: Claude's side by a newly started subagent that is given only the question file and the crops, Codex through a second `codex-call --image` request carrying the same text. Neither request SHALL include either side's earlier answers. Claude's zoom answers SHALL be checked by the same rules as Codex's and sealed before the Codex zoom request is sent; before adjudication the seal SHALL be recomputed, and zoom answers whose seal does not match SHALL NOT be used as evidence. A count question's crop SHALL contain every key point that either side gave for that class in that frame. A position question SHALL ask for the key points of every object of that class in the crop. A disagreement with no key point to frame, or whose crop would cover the whole image, SHALL get no zoom question. The question file SHALL state the order in which the crops are attached and the actual enlargement, which SHALL keep the longer side at or below 2048 pixels. The zoom plan and question file SHALL be recorded when they are written and checked before the request, and only crops inside the run directory SHALL be sent.

#### Scenario: Only disputed regions are re-sent

- **WHEN** 1 of 12 frames has a disagreement
- **THEN** the second request carries crops of that 1 frame only

#### Scenario: Zoom answers changed after sealing are not evidence

- **WHEN** Claude's zoom answer file is modified after it was sealed
- **THEN** no disagreement is settled by the zoom round and the result file says the zoom seal failed

#### Scenario: The zoom question file carries no earlier answers

- **WHEN** the zoom question file is inspected
- **THEN** it contains the crop names, the questions, and the class definitions, and none of either side's first-round answers

### Requirement: Built-in SAM evidence

The skill SHALL include a SAM 2.1 tracking step, using model `facebook/sam2.1-hiera-large` at a pinned revision, inside a dedicated environment at `~/.codex-pro/sam-env/` that also holds the model weights; the installation SHALL download only the files the tracking loads. Before the first installation, the skill SHALL state the estimated download size and SHALL install only after the user agrees; tracking SHALL use only files already present. Tracking SHALL follow one class that has a key-point definition, take the frame order from the order the images were given, use frames where both claim sets agree as anchors with the agreed positions as prompt points, and SHALL re-anchor at every run of agreeing frames. An object SHALL count as present in a frame only when the model's object score says so. When the masks of two tracked objects in a frame have intersection-over-union greater than 0.5, that frame SHALL be marked invalid and SHALL NOT be used to settle a disagreement. SAM evidence SHALL apply only to count and position disagreements of the tracked class and to relations whose two classes are both the tracked class. The SAM step SHALL run before the zoom round, so a failed zoom request does not discard it. When the environment is not installed or the user declines installation, the result file SHALL record `sam_status: not_installed` and the run SHALL continue without failing.

#### Scenario: Collapsed masks are not evidence

- **WHEN** two tracked objects have masks with intersection-over-union 0.7 in a disputed frame
- **THEN** that frame is marked invalid and the disagreement is not settled by SAM

#### Scenario: Declined installation degrades gracefully

- **WHEN** the user declines the SAM installation
- **THEN** the run completes, the result file records `sam_status: not_installed`, and disagreements that needed SAM are marked `unverifiable`

#### Scenario: Another class is not settled by SAM

- **WHEN** SAM tracked two instruments and the disagreement is a count mismatch on suture threads
- **THEN** the SAM measurement is not used for that disagreement

### Requirement: Adjudication without majority vote

Each disagreement SHALL end as exactly one of `resolved_claude`, `resolved_codex`, or `unverifiable`. Only third evidence SHALL settle a disagreement: matching answers from the zoom round, a measurement from a valid SAM frame, or a violated physical constraint from the vocabulary. A SAM measurement SHALL count as evidence only when it lies farther from the relevant threshold than the SAM margin, which defaults to 1 percent of image width and can be set by `sam_margin_pct` in the vocabulary file; a measurement within the margin is not evidence. Position evidence, from SAM or from the zoom round, SHALL first pair the evidence points with all of each side's key points of that class and SHALL settle the disagreement only when both disputed points correspond to the same object, with the SAM margin applied to both sides. A count seen in a crop or by SAM SHALL only confirm the higher of the two counts, because objects outside the crop or not anchored are not seen; a count equal to the lower one SHALL settle nothing. When the zoom round refutes both answers, the disagreement SHALL be `unverifiable` whatever the other evidence says. A violated maximum count SHALL exclude one side and SHALL NOT by itself confirm the other: alone it leaves the disagreement `unverifiable` with the excluded side named. When the available pieces of evidence point to different sides, the disagreement SHALL be `unverifiable`. No request to either model SHALL contain the other model's claims, and an answer already recorded SHALL NOT be replaced by a later answer from the same model. Without valid third evidence, the disagreement SHALL be `unverifiable`.

#### Scenario: A measurement within the SAM margin is not evidence

- **WHEN** a relation mismatch on `tips_together` (defined as distance_pct < 5) has only one piece of evidence, a valid SAM frame measuring the tips 5.18% of the image width apart, and the SAM margin is 1
- **THEN** the measurement is not used and the disagreement is `unverifiable`

#### Scenario: Disagreement without valid evidence stays unverifiable

- **WHEN** a disagreement has no matching zoom-round answers, every SAM frame for it is invalid, and no physical constraint is violated
- **THEN** the disagreement is recorded as `unverifiable` and no further request carries either model's claims

#### Scenario: A zoom count equal to the lower answer settles nothing

- **WHEN** a count mismatch is 1 against 2 and both zoom answers count 1 in the crop
- **THEN** the disagreement is `unverifiable`

#### Scenario: A violated maximum alone does not confirm the other side

- **WHEN** Claude counts 3 instruments, Codex counts 1, the maximum is 2, and there is no other evidence
- **THEN** the disagreement is `unverifiable` and the result names Claude's count as excluded

#### Scenario: A doubled mark is not confirmed by the other object

- **WHEN** one side marked the same instrument twice and missed the other, the other side marked both, and SAM tracked both instruments
- **THEN** the position disagreement is settled for the side that marked both

##### Example: SAM settles a relation mismatch

- **GIVEN** a relation mismatch on `tips_together` defined as distance_pct < 5, Claude says true and Codex says false
- **WHEN** a valid SAM frame measures the two tips 3.5% of the image width apart, farther from the threshold than the default margin of 1
- **THEN** the disagreement is `resolved_claude` with the SAM measurement recorded as evidence

### Requirement: Structured result file

Every run SHALL write `.codex-pro/visual-xval-<ISO8601-timestamp>.md`. Its frontmatter SHALL include the skill name, model, effort, profile source, the model that gave the first side's answers (`first_side_model`), error, `n_images`, `n_claims`, `agreement_rate`, `claude_answers_sha256`, `sealed_at`, `seal_broken`, `codex_requested_at`, `codex_reply_sha256`, and `sam_status`. Model, effort, and profile source SHALL be the values resolved for the run and recorded in the run directory. Its body SHALL contain, in order: the agreement rate and disagreement summary, each disagreement with its classification, adjudication and evidence, the SAM status with invalid frame count and anchors, the seal verification, and the limitations, which SHALL state that agreement between the two models does not establish correctness. Failures of the classes `rate_limit`, `oauth_invalid`, `timeout`, `target_invalid`, `runtime_unsupported`, `parse_failed`, `runtime_unavailable`, `package_corruption`, `backend_error` (a request was sent and the backend or the connection failed), and `internal_error` SHALL each write this file and SHALL NOT retry. An error SHALL be cleared when the step that raised it later completes; a command refused because its step was already done SHALL NOT replace the run's error. When the first side is not a Claude model, the limitations SHALL say that both sides may come from one model family.

#### Scenario: Failed run still leaves a result file

- **WHEN** the run stops with `error: timeout`
- **THEN** a result file exists with that error in its frontmatter and the status skill can list it

#### Scenario: A refused repeat does not replace the run's error

- **WHEN** the first-round request failed with `rate_limit` and the first-round request is attempted again
- **THEN** the second attempt is refused and the result file still records `error: rate_limit`

#### Scenario: A first-round failure still adjudicates and reports

- **WHEN** the first-round request fails, so no comparison exists
- **THEN** adjudication finishes without an error of its own and the result file says no comparison was made

### Requirement: Privacy reminder before sending images

Before the first request in a run, the skill SHALL remind the user that the images will be sent to OpenAI and that content which must not leave the machine has to be masked first, and SHALL record the user's confirmation in the run directory; no request SHALL be sent without that record. The skill SHALL NOT decide on the user's behalf which content to mask. The copies made for a run SHALL carry no embedded metadata such as capture time or location, including data appended after the image, SHALL be turned upright from any EXIF orientation first, SHALL be read by their file header rather than their extension, and the run directory SHALL exclude itself from version control.

#### Scenario: Reminder precedes the first request

- **WHEN** a run reaches the point of sending images without a recorded confirmation
- **THEN** no request is sent and the run stops with `error: target_invalid`

#### Scenario: Copies carry no capture time

- **WHEN** a JPEG with an EXIF capture time is given
- **THEN** the copy in the run directory has no EXIF capture time
