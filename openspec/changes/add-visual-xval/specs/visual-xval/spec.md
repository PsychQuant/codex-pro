## Purpose

Visual cross-validation (`/codex-pro:codex-visual-xval`) lets Claude and Codex judge the same set of images independently, compares their per-frame claims with deterministic code, and settles disagreements only with a third kind of evidence. It exists because a single model misreading an image does not notice its own error.

## ADDED Requirements

### Requirement: Interpreter requirement

The skill's scripts SHALL require Python 3.10 or later. Under an older interpreter the orchestrator SHALL stop before loading any of its other modules, SHALL answer `error: runtime_unavailable` naming the interpreter version found and record it in the run's error history, and its `result` step SHALL still write the result file, except where the Structured result file requirement says no result file is written, in fixed text: it reads none of the run's records, so it shows none of their values (the image count and the settings included), says nothing of how far the run went, and does not show a seal it did not check as intact; it SHALL NOT write the run's error or its ledger, which only the main path writes, so their rules have one copy. A stop under the older interpreter therefore leaves the run as it was: the step can be run again under Python 3.10 or later, and a result file written there shows the run as its records stand, the stop staying in the error history only.

#### Scenario: Old interpreter still leaves a result file

- **WHEN** the orchestrator runs under Python 3.9, with the result file's location outside the directory `--run` names
- **THEN** no request is sent and a result file exists with `error: runtime_unavailable` and no value from the run's records

#### Scenario: A stop under an old interpreter leaves the run as it was

- **WHEN** a step stops under Python 3.9
- **THEN** the run's error and its ledger are unchanged, the stop is in the error history, and the step can be run again under Python 3.10 or later

### Requirement: Runtime image capability preflight

The `codex-visual-xval` skill SHALL confirm, before reading OAuth data or sending any request, that the resolved `codex-call` runtime accepts the `--image` option, by checking that the runtime's help output lists `--image`. When the runtime does not list `--image`, the skill SHALL write its result file with `error: runtime_unsupported`, SHALL NOT invoke the runtime with image arguments, and SHALL NOT retry.

#### Scenario: Old runtime is refused before sending

- **WHEN** the resolved `codex-call` help output does not contain `--image`
- **THEN** the skill writes a result file with `error: runtime_unsupported` and no request is sent

#### Scenario: Supporting runtime proceeds

- **WHEN** the resolved `codex-call` help output contains `--image`
- **THEN** the skill continues to image validation

### Requirement: Claim schema and closed vocabulary

Each judgment SHALL be expressed as per-frame claims against a vocabulary file that lists the allowed object classes, which of them have a key point and how that point is defined, the physical constraints, the relations, and the position threshold as a percentage of image width (default 5). Only classes with a key-point definition SHALL be compared by position; the others SHALL be compared by count only. Each relation SHALL name two classes that have key points and SHALL be defined as `distance_pct`, a comparison operator, and a number (for example `distance_pct < 5`), where `distance_pct` is the smallest distance, in percent of image width, between a key point of the first class and a different key point of the second class; when a frame has no such pair of key points, the relation SHALL be false. Any other definition SHALL make the input invalid. A claim SHALL record, for one frame, the count of each class, exactly one key point for every counted object of a class that has a key-point definition, as percentages of image width and height, and the value of each relation. A claim whose number of key points for such a class differs from that class's count SHALL be invalid: from Claude it is `target_invalid`, from Codex it is `parse_failed`. Objects that fit no listed class SHALL be recorded as class `other` with a description. A run SHALL contain at most 12 images; more SHALL be `target_invalid`.

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

Claude's claims SHALL be written to a file inside the run directory, and its SHA-256 digest and timestamp SHALL be recorded before Codex is called. The request to Codex SHALL NOT be sent unless the seal exists and the digest recomputed at that moment matches it. A seal SHALL NOT be rewritten once recorded, and Claude's claims SHALL NOT be sealed after Codex has answered. Every record a step writes SHALL be entered, with its SHA-256, in one ledger in the run directory: the vocabulary, the image copies and the settings `init` writes, the privacy confirmation, both sides' answers and seals in either round, the request record, the prompts, Codex's raw replies (also when the call failed), the comparison, the zoom plan, its question file, its crops, the list of disagreements without a zoom question and the record of rejected zoom answers, SAM's records and the adjudication. The run's error, the init attempt and the profile `ask` used SHALL be entered too. The files that are not records are a closed list: the ledger itself, `.gitignore`, the error history, the answers as the user gave them, the runtime path and runtime error written by the runtime resolution, and files whose names begin with a dot in the run's directories (xval's own temporary files among them). A step SHALL enter only what it wrote itself: the records it wrote through xval's one write entry, and the file the program it ran wrote for it (`codex-call` its reply, SAM its track) when that file is new or changed since the step began. It SHALL do so also when it stops partway, by failure or interruption, and a step that sends a request SHALL enter what it wrote before the request is sent. The only records a step enters without having written them are the two that may exist without an entry, each only while it has none: Claude's answers when they are sealed, with the digest the seal recorded, and the profile when a request is first recorded, before `codex-call` starts, with the digest of the bytes the step read; a request withdrawn because `codex-call` could not start takes that profile entry back, so the profile is pending again, and after a request is recorded a profile without an entry stops the next request. The `result` step SHALL enter nothing, and SHALL NOT write its file into the directory `--run` names, whether or not that directory reads as a run, at `--out` or at the default location, judged by the directory itself rather than its spelling (the default location by the working directory, before anything is created); the path SHALL be resolved from the string as given, as the operating system resolves it (each symbolic link before the `..` after it), a folder the system does not reach (a missing folder, or a file, followed by `..`) is no folder, and the check and the write SHALL both use the target that resolution gave, which the step also reports. A directory changed by another process between the check and the write is outside what xval guards, as the ledger is. A step SHALL NOT enter, re-enter or remove the entry of a record it did not write, so a record that does not match the ledger stays detected; when the ledger is missing or unreadable while the run holds records, no step SHALL write a new one. Every file xval writes SHALL be written to a new temporary file in the directory its path resolves to and then moved over its name there, so that a symbolic link, a hard link or a FIFO at that name is replaced and never written through, and xval SHALL NOT write into the run directory, or its frames, hires or crops directory, when it is a symbolic link; `--run` SHALL be settled once where a step starts, on both interpreters, so every path of the run is built from it: a name with `..` names no run and is refused, and a trailing `/` or `/.` is dropped, so the run directory is judged by its own name however it is written, and a run directory that is then a symbolic link is refused too, for every step, the result step included; both refusals come before anything else, so nothing at all is written, not even the error history, and no step writes through a linked run directory, the subdirectories a step writes first included; the error history is appended the same way, and skipped when it is not a regular file, and the result file at `--out`, the user's own path, is refused when a symbolic link or anything but a regular file is there, while the folder that holds it is the user's to choose. A decision that a step was already done SHALL read no record the ledger has not verified, and SHALL be made in one of these three ways, and only these; no other decision may be added to this list by likeness: (1) a seal of either round, the record of rejected zoom answers and the privacy confirmation count by their ledger entry; without an entry, what the ledger sees as a record at such a name (a regular file, or a link to one) stops the step with `target_invalid` as not in the run's ledger, and is neither counted as the step done nor replaced, while a FIFO or a dangling link there is not a record, does not count, and is replaced when the step writes the name, while a directory there stops the step with `target_invalid`; (2) a request in a round counts by the request record, checked against the ledger before it is read; (3) the init attempt and the settings and lists `init` writes count by anything at those names or their entries, whichever exists, and are not read, so a run is never initialised twice. Outside (3), whether a record is there SHALL be decided by that one test (its entry, or a regular file or a link to one at its name) everywhere, in a step that cannot be done yet as much as in one already done, and in which records may still be without an entry. Moving a record away and back does not let a step be done again; `init` SHALL refuse a run that holds an init attempt or the settings and lists `init` writes, by record or entry, or an entry for an image copy, and nothing else, so the privacy confirmation, the run's error and a record left by a step run before `init` do not use the run up. Every step but `init`, `confirm-privacy`, `adjudicate` and `result` SHALL require that `init` completed in the run (`adjudicate` records that there is no comparison after any stop): before any init attempt it is refused as a step that cannot be done yet, and after an attempt that did not complete it stops with `target_invalid` at step `init`, because the run is used up. The following refusals, and only these, SHALL NOT replace the run's error; no other refusal may be added to this list by likeness: (1) a step already done: a second privacy confirmation, a second seal of a round, sealing a round Codex was already asked, sealing zoom answers after they were rejected, a second `init`, a second request in a round, the zoom round after Claude's zoom answers were rejected, and `crops` after those answers were sealed or rejected; (2) a step that cannot be done yet or has nothing to do: any step but `init`, `confirm-privacy`, `adjudicate` and `result` before an init attempt, `compare` before Codex answered round 1, `crops` without a comparison, `sam` without a comparison when it needs one, the zoom round without a comparison or without a zoom plan that holds a question, and `seal --zoom` without such a plan; (3) Claude's zoom answers that fail the checks, which drops the zoom round while the run goes on; (4) a command that names no step: an unknown `--round`; a `--run` named with `..`, or that is a symbolic link, neither of which writes anything at all; or a `--run` that is not a run directory. The run's error SHALL NOT be replaced or cleared when it does not match the ledger, or when it can never be resolved: an error raised at `init` after its attempt was recorded, and an error raised at `ask --round 1` or `ask --round zoom` after that round's request was recorded, since the run or the round is used up; another step's stop then goes to the error history only. Whether an error can never be resolved SHALL be decided when it is recorded and kept in it, never inferred later from the run's records, so an error from before a request is cleared when that round later completes; an error `ask` raised before its round's request is cleared as that request is recorded, since every check that raised it has passed, so a request ended later, even by SIGKILL, shows as the failed round it is. A step interrupted by SIGINT or SIGTERM SHALL enter what it wrote and stop with `internal_error`, except `ask` while `codex-call` runs, which stops `codex-call`, waits for it, and stops with `backend_error` because the request counts as sent; interrupts are held from the moment the request is recorded until `codex-call` has started, so the record, its withdrawal when the start fails, and the start are each done whole, and none can arrive between the start and that guard, while `codex-call` itself starts with the interrupts as they were; once one interrupt has arrived, or the step has stopped or completed by itself, further interrupts are ignored while it records that, so none of them cuts short stopping `codex-call` or recording what happened. Every later step SHALL check the records it reads against the ledger before it reads them, and SHALL stop with `target_invalid`, sending nothing, when one of them is missing, differs from its entry, or exists without an entry; the only records that may exist without an entry are Claude's answers of a round not yet sealed, and the profile the runtime resolution wrote until a request is recorded. Every image sent SHALL be a file inside the run's frames or crops directory. A run SHALL be initialised at most once: an attempt that failed also uses up the run, so the privacy confirmation covers one set of images. When Claude's answers changed after they were sealed, the run SHALL stop at the next step that reads them, and the result file SHALL set `seal_broken: true` and state that the seal failed. A seal that was never checked SHALL NOT be reported as intact.

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

#### Scenario: Answers edited after the comparison stop the later steps

- **WHEN** Claude's or Codex's answer file is changed after `compare` read it, and `crops` or `adjudicate` runs, or `sam` runs on a sequence whose vocabulary has key points (otherwise it reads neither file)
- **THEN** the step stops with `error: target_invalid` and writes no crop, track or verdict

#### Scenario: Editing the run's error does not clear it

- **WHEN** a run stopped with `rate_limit`, its `error.json` is edited to name another step, and that step is run
- **THEN** the error is not cleared, and the result file carries `error: target_invalid` and names `error.json`

#### Scenario: A later failure does not replace a used-up round's error

- **WHEN** the first-round request was recorded and failed with `rate_limit`, another step then fails, and that step is run again until it completes
- **THEN** the run's error stays `rate_limit` at `ask --round 1`, and the result file carries `error: rate_limit`

#### Scenario: An error from before the request is cleared when the round completes

- **WHEN** `ask --round 1` stops before sending because Codex is not logged in, and after logging in the round is asked again and completes
- **THEN** the run has no error

#### Scenario: A reply file placed before the request is not entered

- **WHEN** a `codex_round1.md` that `codex-call` did not write is in the run before the first-round request
- **THEN** the request is not sent, and the file stays out of the ledger

#### Scenario: A failed init cannot be redone by moving its attempt away

- **WHEN** `init` failed, its `init_attempt.json` is moved out of the run, and `init` is run again
- **THEN** it is refused because the ledger records the attempt

#### Scenario: An interrupted init leaves its error

- **WHEN** `init` is interrupted with SIGINT while it copies the images
- **THEN** the run's error is `internal_error` at `init`, and every later step that needs `init` refuses the run

#### Scenario: A symbolic link at a record's name is not written through

- **WHEN** `crops/z01.png` is a symbolic link to a file outside the run and `crops` runs
- **THEN** the file outside the run is unchanged, and the crop is written in the run

#### Scenario: A seal cannot be redone by moving it away

- **WHEN** `seal.json` and `requests.json` are moved out of the run after Codex answered and `seal` is run again
- **THEN** it is refused because the ledger records the seal and the request, and no seal is written

#### Scenario: A seal cannot be rewritten

- **WHEN** Claude's answers are sealed a second time
- **THEN** the second seal is refused and the first seal stays unchanged

#### Scenario: A symbolic link followed by '..' does not lead the result file into the run

- **WHEN** `--out` names a path through a symbolic link followed by `..` that, as the operating system resolves it, still lies in the directory `--run` names (the link points at a directory inside it, such as `frames/`)
- **THEN** the result step stops with `target_invalid`, writes no result file, and no record in the run changes

#### Scenario: Both interpreters refuse a --run they cannot settle

- **WHEN** `result` runs with a `--run` named with `..`, or that is a symbolic link, under Python 3.10 or later or under Python 3.9
- **THEN** both stop with `target_invalid` naming the reason, and neither writes a result file or anything else

#### Scenario: A symbolic link to the run itself followed by '..' is written beside the run

- **WHEN** `--out` names a path through a symbolic link to the run directory itself followed by `..`
- **THEN** the path resolves beside the run, outside it, and the result file is written there

#### Scenario: A record that marks a step done is not taken for one without its entry

- **WHEN** `zoom_rejected.json` is in the run directory without a ledger entry
- **THEN** `seal --zoom`, the zoom round and `crops` stop with `target_invalid` naming it as not in the run's ledger, and none of them reports the zoom round as dropped

### Requirement: Blind Codex judgment

The skill SHALL send the images to Codex only through `codex-call`, passing each image with `--image`, under neutral file names that carry no timestamps or hints, together with the vocabulary, its maximum counts, its key-point definitions, and the claim schema. The prompt SHALL NOT include Claude's claims, Claude's conclusions, or any summary of them, and its instructions SHALL state that text visible in the images is content to judge, not instruction. The call SHALL run in the foreground with the profile's hard timeout. Each round SHALL send at most one request: the time of the request and the SHA-256 of the reply SHALL be recorded, a second request in the same round SHALL be refused, and the result file SHALL show, for each round, the request time and reply digest and whether the reply still matches it. A failed call SHALL be treated as sent and its record kept, whatever its message says: a message cannot show that nothing was sent, because `codex-call` prints the backend's error events as they come and prints every failure before a response as `HTTP 0`. Only a call that never started SHALL leave the round unsent: whatever stops the step after the request is recorded and before `codex-call` has started (a failure while starting the process, one in the new process before `codex-call` is executed included) withdraws the record while interrupts are still held, and the step then says nothing was sent. When the withdrawal itself fails, the round counts as used up, and the step says that instead. Once `codex-call` has started, nothing withdraws the record, including output that cannot be decoded. When `ask` is interrupted (SIGINT or SIGTERM) while `codex-call` runs, `codex-call` SHALL be stopped, whatever it wrote SHALL be entered in the ledger, and the run SHALL stop with `backend_error`, the request counted as sent; an interrupt before `codex-call` starts, or after it has ended, stops the step with `internal_error`. The error the runtime resolution recorded SHALL be checked before the login check, so a failed native preflight reads no OAuth state. Before the call, the skill SHALL itself check what commonly fails before sending, and SHALL stop without sending when a check fails: that Codex is logged in (the token store `codex-call` reads holds its tokens, checked without reporting its contents; it lies where Foundation puts the home directory: `CFFIXED_USER_HOME` when that is set, even to an empty value (then the working directory), and the process is not set-id, otherwise the account's own home directory, whatever `HOME` says) and that the images and the prompt are in place; the prompt file SHALL be written before the request is recorded, and when it cannot be written the run SHALL stop with nothing sent. A login that passes this check but whose token refresh fails in `codex-call` counts as sent like any other failure of the call. A reply that is not valid JSON matching the claim schema SHALL produce `error: parse_failed` without retry.

#### Scenario: Prompt carries no Claude answers

- **WHEN** the request body assembled for Codex is inspected
- **THEN** it contains the images, the vocabulary, and the schema, and none of the Claude claim values

#### Scenario: A second request in the same round is refused

- **WHEN** the first-round request is attempted again after Codex has answered
- **THEN** the run stops with `error: target_invalid`, no second request is sent, and the recorded answer is unchanged

#### Scenario: A failure before any response keeps the record

- **WHEN** `codex-call` fails with `HTTP 0: (no body)` in the first round
- **THEN** the run stops with `error: backend_error`, the request stays recorded, and a second first-round request is refused

#### Scenario: Any failure of the call keeps the record

- **WHEN** `codex-call` fails with a message that reads exactly like one of its own checks before sending, such as `empty prompt`
- **THEN** the request stays recorded and a second request in that round is refused

#### Scenario: Not being logged in is caught before sending

- **WHEN** the Codex token store is missing and the first-round request is attempted
- **THEN** the run stops with `error: oauth_invalid`, `codex-call` is not run, and the round is not recorded as sent

#### Scenario: An edited Codex answer is reported

- **WHEN** Codex's recorded answer file is modified after it was recorded
- **THEN** the next step that reads it stops with `error: target_invalid`, and the result file names it as changed

#### Scenario: A start that fails while an interrupt is held is withdrawn

- **WHEN** `codex-call` cannot be started and an interrupt arrives meanwhile
- **THEN** the request record is withdrawn and the profile entry taken back before the interrupt stops the step, and the round is not used up

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

For each disagreement with a region to examine, the skill SHALL crop that region, resize it, and write one question file listing every crop with its question, its actual scale, and the class definitions. A relation question SHALL state the full definition of `distance_pct` and the key-point definitions of both classes, as the first round does. Both sides SHALL answer from that file and the crops alone: Claude's side by a newly started subagent that is given only the question file and the crops, Codex through a second `codex-call --image` request carrying the same text. Neither request SHALL include either side's earlier answers. Claude's zoom answers SHALL be checked by the same rules as Codex's and sealed before the Codex zoom request is sent; before adjudication the seal SHALL be recomputed, and zoom answers whose seal does not match SHALL NOT be used as evidence. When Claude's zoom answers fail the checks, the zoom round SHALL NOT be used and the run SHALL continue; this SHALL NOT be recorded as the run's error. A count question's crop SHALL contain every key point that either side gave for that class in that frame. Crops SHALL be cut from a copy at the image's full resolution, re-encoded and stripped like the others, so the zoom round sees detail the round-1 copy lost. A position crop SHALL reach at least the position threshold beyond each disputed point in both directions, measured in units of image width. A relation whose definition is not `distance_pct <` or `<=` SHALL get no zoom question, since its answer is never used. A position question SHALL ask for the key points of every object of that class in the crop. A disagreement with no key point to frame, which includes every count disagreement on a class without a key-point definition, or whose crop would cover the whole image, SHALL get no zoom question. The question file SHALL state the order in which the crops are attached and the actual enlargement, which SHALL keep the longer side at or below 2048 pixels. The zoom plan and question file SHALL be recorded when they are written and checked before the request, and only crops inside the run directory SHALL be sent. The comparison SHALL be recorded when it is written and checked before the crops are made and before adjudication, and the crops SHALL NOT be made again once Claude's zoom answers are sealed.

#### Scenario: Only disputed regions are re-sent

- **WHEN** 1 of 12 frames has a disagreement
- **THEN** the second request carries crops of that 1 frame only

#### Scenario: Zoom answers changed after sealing are not evidence

- **WHEN** Claude's zoom answer file is modified after it was sealed
- **THEN** `adjudicate` stops with `error: target_invalid`, so no disagreement is settled by the zoom round, and the result file says the zoom seal failed

#### Scenario: Zoom answers that fail the checks leave the run complete

- **WHEN** Claude's zoom answer file does not match the question file's format and the run continues to adjudication
- **THEN** the result file has no error, says the zoom round was not used, and the disagreements are adjudicated without it

#### Scenario: The zoom question file carries no earlier answers

- **WHEN** the zoom question file is inspected
- **THEN** it contains the crop names, the questions, and the class definitions, and none of either side's first-round answers

### Requirement: Built-in SAM evidence

The skill SHALL include a SAM 2.1 tracking step, using model `facebook/sam2.1-hiera-large` at a pinned revision, inside a dedicated environment at `~/.codex-pro/sam-env/` that also holds the model weights; the installation SHALL download only the files the tracking loads. Before the first installation, the skill SHALL state the estimated download size and SHALL install only after the user agrees; tracking SHALL use only files already present. Tracking SHALL follow one class that has a key-point definition, take the frame order from the order the images were given, use frames where both claim sets agree as anchors with the agreed positions as prompt points, and SHALL re-anchor at every run of agreeing frames. An object SHALL count as present in a frame only when the model's object score says so. When the masks of two tracked objects in a frame have intersection-over-union greater than 0.5, that frame SHALL be marked invalid and SHALL NOT be used to settle a disagreement. SAM measures the tip of each tracked mask, the point farthest from where the object enters the view, so SAM evidence for positions and relations SHALL be used only when the vocabulary declares `track_point: tip`, saying that the tracked class's key point is that tip; without it SAM SHALL give count evidence only. SAM evidence SHALL apply only to count and position disagreements of the tracked class and to relations whose two classes are both the tracked class. The tracking output SHALL be recorded when it is written and checked before it is used. The SAM step SHALL run before the zoom round, so a failed zoom request does not discard it. When the environment is not installed or the user declines installation, the result file SHALL record `sam_status: not_installed` and the run SHALL continue without failing.

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

Each disagreement SHALL end as exactly one of `resolved_claude`, `resolved_codex`, or `unverifiable`. Only third evidence SHALL settle a disagreement: matching answers from the zoom round, a measurement from a valid SAM frame, and the vocabulary's maximum counts. Evidence SHALL be used only for what it can prove, because objects outside a crop or not anchored by SAM are not seen. For a count, a number of objects seen in a crop (both zoom answers equal) or by SAM (present objects of the tracked class) SHALL be a lower bound on the frame's count, and the vocabulary's maximum count SHALL be an upper bound. A side whose count lies below the highest lower bound or above the maximum SHALL be excluded, and the result SHALL name it. A count disagreement SHALL be resolved for a side only when the other side is excluded and that side's count equals the highest lower bound; when both sides are excluded, or the lower bound exceeds the maximum, it SHALL be `unverifiable`. For a position, the evidence points SHALL first be paired with all of each side's key points of that class, and the disagreement SHALL be settled only when both disputed points correspond to the same object, with the SAM margin applied to both sides. When the zoom round places that object clearly away from both disputed points, or finds no object of the class near either of them, it refutes both. SAM follows only the objects it was anchored on, so SAM SHALL NOT refute both. For a relation, the smallest distance measured among the objects seen SHALL be an upper bound on the frame's smallest distance. A zoom answer SHALL be used only to show that `distance_pct < N` (or `<=`) holds, because that answer needs a pair of key points that are close; a `false`, or any answer about `>`, can come from a crop in which no pair was seen. A SAM measurement SHALL settle the relation in either direction only when both sides report the same count of each class in the relation in that frame and SAM measured the tip of that many present objects; otherwise only a value the upper bound proves SHALL be used. A SAM measurement SHALL count as evidence only when it lies strictly farther from the relevant threshold than the SAM margin, which defaults to 1 percent of image width and can be set by `sam_margin_pct` in the vocabulary file. When any evidence refutes both answers, the disagreement SHALL be `unverifiable` whatever the other evidence says. When the available pieces of evidence point to different sides, the disagreement SHALL be `unverifiable`. A count disagreement on a class without a key-point definition has no zoom question and no SAM evidence, so it can only be excluded, never resolved. No request to either model SHALL contain the other model's claims, and an answer already recorded SHALL NOT be replaced by a later answer from the same model. Without valid third evidence, the disagreement SHALL be `unverifiable`.

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

#### Scenario: A maximum and a seen count that meet settle the count

- **WHEN** Claude counts 3 instruments, Codex counts 2, the maximum is 2, and both zoom answers count 2 in the crop
- **THEN** the disagreement is `resolved_codex`

#### Scenario: A zoom count below both answers refutes neither

- **WHEN** a count mismatch is 1 against 2, both zoom answers count 0 in the crop, and SAM tracks 2 present objects of that class
- **THEN** the disagreement is `resolved_codex` and the result does not say the zoom round refuted both

#### Scenario: Both counts above the maximum are both excluded

- **WHEN** Claude counts 4 instruments, Codex counts 3, and the maximum is 2
- **THEN** the disagreement is `unverifiable` and both counts are named as excluded

#### Scenario: A zoom round that places the object away from both points refutes both

- **WHEN** the disputed key points are at (50, 50) and (60, 50), both zoom answers place the only instrument in the crop at (75, 50), and a SAM tip lies at (50.2, 50)
- **THEN** the disagreement is `unverifiable`

#### Scenario: SAM does not refute both

- **WHEN** both zoom answers place the instrument at Claude's disputed point and SAM tracked only another instrument, away from both points
- **THEN** the disagreement is `resolved_claude`

#### Scenario: A zoom answer of false does not show the objects are apart

- **WHEN** a relation mismatch on `tips_together` (distance_pct < 5) has both sides counting 2 instruments and both zoom answers say false
- **THEN** the zoom answers are not used and, without other evidence, the disagreement is `unverifiable`

#### Scenario: A distance measured on some of the objects cannot show they are apart

- **WHEN** a relation mismatch on `tips_together` (distance_pct < 5) has Claude counting 3 instruments and Codex 2 in that frame, and SAM measures 30% between the two tracked tips
- **THEN** the measurement is not used and the disagreement is `unverifiable`

#### Scenario: A doubled mark is not confirmed by the other object

- **WHEN** one side marked the same instrument twice and missed the other, the other side marked both, and SAM tracked both instruments
- **THEN** the position disagreement is settled for the side that marked both

##### Example: SAM settles a relation mismatch

- **GIVEN** a relation mismatch on `tips_together` defined as distance_pct < 5, Claude says true and Codex says false, and the vocabulary declares `track_point: tip`
- **WHEN** a valid SAM frame measures the two tips 3.5% of the image width apart, farther from the threshold than the default margin of 1
- **THEN** the disagreement is `resolved_claude` with the SAM measurement recorded as evidence

### Requirement: Structured result file

Every run SHALL write `.codex-pro/visual-xval-<ISO8601-timestamp>.md`, or the file `--out` names. The result step SHALL write no result file only when it stops with its own error, in these cases and only these; no other case may be added by likeness: (1) the location, default or given, resolves into the directory `--run` names (the step is run from inside it, or `--out` leads into it); (2) the path names no file (its last name is empty, `.` or `..`; an empty `--out` included) or its folder is one the system does not reach; (3) at `--out`, the user's own path, a symbolic link or anything but a regular file is there; (4) the file cannot be written; (5) the step is interrupted, or fails unexpectedly (`internal_error`); (6) `--run` is named with `..` or is a symbolic link (refusal group 4). In (1) to (4) and (6) it stops with `target_invalid` and says why. In (1) to (5) its own error goes to the error history only, when `--run` names a run directory, and no record in the run changes; in (6) nothing at all is written. Both interpreters follow this list alike. Its frontmatter SHALL include the skill name, model, effort, profile source, the model that gave the first side's answers (`first_side_model`), error, `n_images`, `n_claims`, `agreement_rate`, `claude_answers_sha256`, `sealed_at`, `seal_broken`, `codex_requested_at`, `codex_reply_sha256`, and `sam_status`. Model, effort, and profile source SHALL be the values resolved for the run and recorded in the run directory, and `first_side_model` SHALL be a single-line model identifier. Its body SHALL contain, in order: the agreement rate and disagreement summary, each disagreement with its classification, adjudication and evidence, the SAM status with invalid frame count and anchors, the seal verification, and the limitations, which SHALL state that agreement between the two models does not establish correctness. Failures of the classes `rate_limit`, `oauth_invalid`, `timeout`, `target_invalid`, `runtime_unsupported`, `parse_failed`, `runtime_unavailable`, `package_corruption`, `backend_error` (`codex-call` failed after it started and no more specific class applies; the request counts as sent), and `internal_error` SHALL each write this file and SHALL NOT retry. The result file SHALL show no text that came from outside xval, and the text that comes from outside xval is the text of these six sources, and only these; it is kept in the run directory instead and the result file says where: the messages `codex-call` prints, the runtime check's detail, the text of an unexpected Python exception, SAM's output, and the text of Claude's answers (names of frames, classes and relations as Claude wrote them), and Codex's replies (only their values that pass the claim schema reach the records); names from the user's own vocabulary are not outside text; every other error detail is xval's own and SHALL be built from fixed wording, numbers and the names of xval's own files; the user's images are named by their position (a path filter remains as a backstop). The result file SHALL show only the records the ledger verifies, and a record derived from others (the comparison, the adjudication) only when the records it was derived from are verified too; file names and digests SHALL be shown only in xval's own forms. When the run shows no error of its own, the result file SHALL derive the failures that can never be resolved from the records themselves: a round whose request was recorded and that has no entered answer (`codex.json`, `zoom_codex.json`) as `backend_error` at that round's step, and an init attempt without entered settings (`meta.json`) as `target_invalid` at `init`. When the run shows no error and made no request, and the runtime resolution recorded a runtime error, the result file SHALL carry that error class. SAM's anchors, counts and detail rest on the comparison and SHALL be shown only when it is verified. Every record that is not verified SHALL be listed once, and its frontmatter SHALL carry `error: target_invalid` unless the run already stopped with another error. Each frontmatter value SHALL be written only in the form its field allows (a model identifier, an enumerated class or status, a timestamp, a hexadecimal digest, a number), and otherwise as `invalid`. The result file SHALL be written whatever the run directory holds, and a failure of the result step itself SHALL NOT replace the run's error, neither in `error.json` nor in the result file. An error SHALL name the step that raised it, including the round for sealing and asking. An error SHALL be cleared when the step that raised it later completes, unless it can never be resolved; a command refused because its step was already done SHALL NOT replace the run's error, and that check SHALL come before any other check of the command. When the first side is not a Claude model, the limitations SHALL say that both sides may come from one model family. The limitations SHALL also say that the zoom subagent's fresh start and the sealing of its answers before they are read depend on the skill being followed, and, when the vocabulary has classes without a key-point definition, that count disagreements on those classes cannot be settled.

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

Before the first request in a run, the skill SHALL remind the user that the images will be sent to OpenAI and that content which must not leave the machine has to be masked first, and SHALL record the user's confirmation in the run directory; no request SHALL be sent without that record. The skill SHALL NOT decide on the user's behalf which content to mask. The copies made for a run SHALL be decoded and encoded again into new files, with colours converted to sRGB; the copies both models judge in the first round SHALL have the longer side at most 2048 pixels, and the zoom round's crops SHALL come from a copy at full resolution made the same way, so that no byte of the original image reaches either model, and a file that cannot be decoded, that claims more than 250 megapixels, or whose structure shows that its image data is damaged or cut short SHALL be `target_invalid`; for a PNG that means a critical chunk that fails its checksum, no `IEND`, a bit depth its colour type does not allow, or a compressed stream that does not end, fails its own checksum, holds less data than the header promises or more than 1 MB beyond it. The new files SHALL then keep only the segments or chunks the format needs to show the image, so they carry no embedded metadata such as capture time, location, or content credentials, and SHALL end where the format says the image ends (the JPEG end-of-image marker after any fill bytes, the PNG `IEND` chunk), so data appended after the image is dropped. They SHALL be turned upright from any EXIF orientation first, SHALL be read by their file header rather than their extension, and the run directory SHALL exclude itself from version control by a `.gitignore` written when the directory is created; an existing `.gitignore` SHALL NOT be overwritten, a directory that already holds files other than the run's own SHALL NOT be used as a run directory. Only the following steps of this skill SHALL create a directory or write into one that is not a run directory, and this list is closed: SKILL Step 1 creates the run directory (`mkdir -p`); `init` creates the run directory with any missing parents when it is missing, and its `frames` and `hires` directories; `confirm-privacy` takes over an existing empty directory and creates none; `crops` creates `crops` inside the run directory; `result` writes the result file at `--out`, whose directory must already exist, or creates `.codex-pro` in the working directory for it, works from a temporary directory of its own when the run directory is not a run, and reads nothing from a directory that is not a run directory; `sam_env.sh install` creates `~/.codex-pro` and `~/.codex-pro/sam-env`. The tools these steps call write their own files outside this list, and only these: `codex-call` its token store and lock under `~/.codex` when it refreshes a token, `sips` its temporary files, `uv` (called by `sam_env.sh install`) its cache and, when no suitable Python is installed, a Python it manages, and the Python and Swift interpreters their caches. Every other step SHALL refuse a directory that is not a run directory without writing anything.

#### Scenario: A damaged image is refused

- **WHEN** `init` is given a PNG whose image data is not a complete compressed stream
- **THEN** it stops with `error: target_invalid` and writes no copy

#### Scenario: Output that cannot be decoded keeps the record

- **WHEN** `codex-call` runs and prints bytes that are not valid UTF-8
- **THEN** the request stays recorded and the run does not say that nothing was sent

#### Scenario: Claude's answer text stays out of the result file

- **WHEN** Claude's answers name a class that is not in the vocabulary and `seal` stops
- **THEN** the result file gives the error class and says where the detail is kept, without the class name

#### Scenario: A native preflight failure is in the result file without running ask

- **WHEN** the runtime resolution recorded `package_corruption` and the run goes on to `adjudicate` and `result`
- **THEN** the result file's frontmatter carries `error: package_corruption`

#### Scenario: A message from codex-call stays in the run directory

- **WHEN** `codex-call` fails and prints a message
- **THEN** `error.json` keeps the message with its source, and the result file gives the error class and says where the message is kept, without showing it

#### Scenario: A value outside its field's form is written as invalid

- **WHEN** the model recorded in the run directory holds a space or a line break
- **THEN** the result file's frontmatter has `model: invalid` and no other field is added

#### Scenario: Codex's answers changed after they were recorded are reported in the frontmatter

- **WHEN** `codex.json` is changed after `ask` recorded it, and the run goes on to `result`
- **THEN** the result file's frontmatter carries `error: target_invalid`

#### Scenario: A PNG whose compressed stream does not end is refused

- **WHEN** `init` is given a PNG whose pixel data is complete but whose compressed stream lacks its closing checksum
- **THEN** it stops with `error: target_invalid` and writes no copy

#### Scenario: A failed result step keeps the run's error

- **WHEN** the run stopped with `rate_limit` and `result` then fails, for example because the directory of `--out` does not exist
- **THEN** the run's error stays `rate_limit`, and a later `result` writes it

#### Scenario: A mistyped run directory is not created

- **WHEN** `confirm-privacy` is given a run directory that does not exist
- **THEN** it stops with `error: target_invalid` and creates no directory

#### Scenario: Reminder precedes the first request

- **WHEN** a run reaches the point of sending images without a recorded confirmation
- **THEN** no request is sent and the run stops with `error: target_invalid`

#### Scenario: Copies carry no capture time

- **WHEN** a JPEG with an EXIF capture time is given
- **THEN** the copy in the run directory has no EXIF capture time

#### Scenario: Data hidden inside an allowed block does not reach the copy

- **WHEN** a JPEG carries extra data inside its ICC profile segment and its Adobe segment
- **THEN** the copy in the run directory contains none of that data

#### Scenario: Data appended after the image is dropped

- **WHEN** a JPEG whose end-of-image marker is preceded by a fill byte, or a WebP, is followed by a second image carrying GPS data
- **THEN** the copy in the run directory does not contain that second image
