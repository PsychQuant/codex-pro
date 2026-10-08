#!/usr/bin/env python3
"""The structured result file of /codex-pro:codex-visual-xval (#23).

Reads only what the other steps left in the run directory, so it can always be written, also
after a failed step: every run ends with `.codex-pro/visual-xval-<timestamp>.md`.
"""
import datetime
import json
import os
import re
import tempfile
from typing import Any

import compare_claims
import seal as sealing
from run_files import Stop, failure, inputs_digest, is_run_dir, neutral_names, safe_digest


def load(path: str, default: Any = None) -> Any:
    """A record, or `default` when it is missing, unreadable or of another type than `default`: the
    result file is written whatever the run directory holds (#23 verify round 7, Y3)."""
    if not os.path.isfile(path):   # a FIFO or a device would stall the step (round 8, K1)
        return default
    try:
        with open(path, encoding="utf-8") as fh:
            value = json.load(fh)
    except (OSError, ValueError, RecursionError):
        return default
    return default if default is not None and not isinstance(value, type(default)) else value


def option(argv: list[str], name: str) -> str | None:
    return argv[argv.index(name) + 1] if name in argv and argv.index(name) + 1 < len(argv) else None


def request_lines(run: str, rnd: str, label: str, reply_name: str, seal_record: dict) -> list[str]:
    """One round's request record, re-checked now: both the raw reply and the parsed answers are
    compared with the digests recorded when Codex answered (#23 verify round 2, S1, S9)."""
    record = load(os.path.join(run, "requests.json"), {}).get(rnd)
    if not record or not isinstance(record, dict):
        return []
    line = f"Codex {label}: requested at {record.get('requested_at')}; reply SHA-256 `{record.get('reply_sha256') or 'none'}`"
    reply = os.path.join(run, reply_name)
    if record.get("reply_sha256"):
        same = os.path.isfile(reply) and sealing.digest(reply) == record["reply_sha256"]
        line += "; the reply file still matches." if same else "; **the reply file no longer matches** its recorded digest."
    if not seal_record:
        line += " Claude's answers for this round were never sealed."
    elif (seal_record.get("sealed_epoch") or 0) < (record.get("requested_epoch") or 0):
        line += " The seal predates the request."
    else:
        line += " **The seal does not predate the request.**"
    return ["", line]


NATIVE_PREFLIGHT = {"runtime_unavailable", "package_corruption"}


def local_roots() -> list[tuple[str, str]]:
    """The machine's own directories, longest first: a home directory inside the temporary one is
    replaced as home."""
    home, tmp = os.path.expanduser("~").rstrip("/"), tempfile.gettempdir().rstrip("/")
    roots = [(home, "~"), (tmp, "$TMPDIR"), ("/private" + tmp, "$TMPDIR")]
    return sorted((r for r in roots if len(r[0]) > 1), key=lambda r: -len(r[0]))


# The skill's own fixed location, which tells the user where SAM goes. Only the place itself is kept:
# anything below it is cut like any other path (#23 verify round 7, X2).
OWN_PLACE = re.compile(r"~/\.codex-pro/sam-env(?![\w./-])")
# A path starts at a root: '~/' or '$TMPDIR/' (any number of slashes after them), or a single '/' not
# preceded by an ASCII letter, digit or one of '_.-/$~\'. A colon or a CJK character may come before it
# (round 8, K4); a URL's '//' never starts one, since the first of its slashes is followed by another.
PATH = re.compile(r"(?<![A-Za-z0-9_.\-/$~\\])(?:(?:~|\$TMPDIR)/+|/(?!/))(?:(?!://)[^\"\x00])*/")


def cut_paths(clause: str) -> str:
    """Any absolute path keeps only its last part. A path runs from its root to the last '/' of the
    clause, across spaces, apostrophes, parentheses and brackets, which directory names hold ("Client
    (2024)", "Jane's"); it stops at a double quote and never runs into a URL ('://'). Cutting some
    text too many is better than leaving a directory name (#23 verify round 6, W1; round 7, Y1)."""
    return PATH.sub("…/", clause)


def sanitize(text: str) -> str:
    """One line, no control characters, and no local directories. Details are built from file names
    where they are raised (#23 verify round 6, W1); this is the backstop for what a tool printed. The
    machine's roots are replaced only where a path continues after them, so a directory that merely
    starts like the home directory is not half-replaced (round 7, Y1). Each line, and each clause of
    it split at '; ' (how the skill joins its own messages), is cut on its own."""
    text = text.replace("\r\n", "\n").replace("\r", "\n").replace("\t", " ")
    text = re.sub(r"[\x00-\x09\x0b-\x1f\x7f]", "", text)
    text = re.sub(r"file://(?=/)", "", text)   # a file URL is a local path (round 8, K4)
    for root, name in local_roots():   # also before punctuation, which ends a path (round 8, K4)
        text = re.sub(re.escape(root) + r"(?=/|$|[\s'\",.;:)\]])", name, text, flags=re.MULTILINE)
    text = OWN_PLACE.sub("\x00", text)
    lines = ["; ".join(cut_paths(c) for c in line.split("; ")) for line in text.split("\n")]
    return " ".join(lines).replace("\x00", "~/.codex-pro/sam-env")[:500]


def describe(item: dict) -> str:
    what = item.get("relation") or item.get("class") or ""
    return f"{item['frame']} — {item['kind']}" + (f" ({what})" if what else "")


def result(run: str, argv: list[str]) -> None:
    """Render the result file, then write it. Rendering never stops the result: a record of a shape
    nothing expected falls back to a file rendered from an empty directory that still carries the run's
    own error (round 7, Y3; round 8, Z2). Writing can fail, and that is the result step's own error."""
    if not is_run_dir(run):
        # Nothing in a directory that is not a run is read: its files are not a run's, and an error.json
        # placed there would read as this run's outcome (#23 verify round 6, Q1).
        with tempfile.TemporaryDirectory() as empty:
            text, error = render(empty, {"error": "target_invalid", "step": "result",
                                         "detail": f"{os.path.basename(os.path.abspath(run))} is not a run directory, "
                                                   "so nothing in it was read"})
    else:
        try:
            text, error = render(run, None)
        except Exception as exc:
            note = f"the run's records could not be read: {type(exc).__name__}: {failure(exc)}"
            own = load(os.path.join(run, "error.json"), {})
            own = own if isinstance(own.get("error"), str) else None
            with tempfile.TemporaryDirectory() as empty:
                text, error = render(empty, own or {"error": "internal_error", "step": "result", "detail": note},
                                     note=note if own else "", fallback=True)
    emit(text, error, argv)


def emit(text: str, error: str | None, argv: list[str]) -> None:
    out = option(argv, "--out")
    try:
        if not out:   # .codex-pro is created only for the default location (round 6, Q1)
            os.makedirs(".codex-pro", exist_ok=True)
            stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
            out = os.path.join(".codex-pro", f"visual-xval-{stamp}.md")
        with open(out, "w", encoding="utf-8") as fh:
            fh.write(text)
    except OSError as exc:   # the result step's own error, kept out of the run's (round 8, K1)
        raise Stop("target_invalid", f"cannot write the result file {os.path.basename(out or '.codex-pro')}: "
                   f"{exc.strerror or type(exc).__name__}")
    print(json.dumps({"result": out, "error": error}))


def records_changed(run: str, seal_record: dict) -> list[str]:
    """Every record checked against the digest written beside it when the result is written: a record
    without its digest, or a digest without its record, counts as changed too (round 7, Y4; round 8,
    Z3, Z4). Claude's first-round answers are reported by seal_broken."""
    changed = []
    path = lambda name: os.path.join(run, name)
    if seal_record and seal_record.get("inputs_sha256") != inputs_digest(run):
        changed.append("the vocabulary, the image copies or the run's settings" if seal_record.get("inputs_sha256")
                       else "the seal (it lacks the inputs' digest)")
    comparison = load(path("comparison_record.json"), {})
    if comparison or os.path.exists(path("comparison.json")):
        for name, key in (("comparison.json", "sha256"), ("claude.json", "claude.json"), ("codex.json", "codex.json")):
            if comparison.get(key) != safe_digest(path(name)):
                changed.append(name)
    verdicts = load(path("adjudication_record.json"), {})
    if (verdicts or os.path.exists(path("adjudication.json"))) and verdicts.get("sha256") != safe_digest(path("adjudication.json")):
        changed.append("adjudication.json")
    requests = load(path("requests.json"), {})
    for rnd, answers, reply in (("1", "codex.json", "codex_round1.md"), ("zoom", "zoom_codex.json", "codex_zoom.md")):
        record = requests.get(rnd) if isinstance(requests.get(rnd), dict) else {}
        if (record.get("answers_sha256") or os.path.exists(path(answers))) and record.get("answers_sha256") != safe_digest(path(answers)):
            changed.append(answers)
        if record.get("reply_sha256") and record["reply_sha256"] != safe_digest(path(reply)):
            changed.append(reply)
    zoom_seal = load(path("zoom_seal.json"), {})
    if zoom_seal and zoom_seal.get("sha256") != safe_digest(path("zoom_claude.json")):
        changed.append("zoom_claude.json")
    return list(dict.fromkeys(changed))


def render(run: str, stopped: dict | None, note: str = "", fallback: bool = False) -> tuple[str, str | None]:
    error = stopped or load(os.path.join(run, "error.json"), {}) or None
    if error and not isinstance(error.get("error"), str):
        error = None
    comparison = load(os.path.join(run, "comparison.json"), {}) or None
    if comparison and not (isinstance(comparison.get("disagreements"), list)
                           and all(isinstance(d, dict) for d in comparison["disagreements"])):
        comparison = None
    adjudicated = load(os.path.join(run, "adjudication.json"), {})
    seal_record = load(os.path.join(run, "seal.json"), {})
    seal_check = load(os.path.join(run, "seal_check.json"), {})
    seal_when = "before comparison"
    if not seal_check and seal_record:
        # The run stopped before comparing; check the seal now rather than call it intact unchecked.
        now_digest = sealing.digest(os.path.join(run, "claude.json")) if os.path.isfile(os.path.join(run, "claude.json")) else None
        seal_check = {"sha256_now": now_digest, "seal_broken": now_digest != seal_record.get("sha256")}
        seal_when = "when the result was written"
    settings = load(os.path.join(run, "profile.json"), {})
    request = load(os.path.join(run, "requests.json"), {}).get("1", {})
    request = request if isinstance(request, dict) else {}
    sam_state = load(os.path.join(run, "sam.json"), {})
    track = load(os.path.join(run, "track.json"), {}) if sam_state.get("sam_status") == "ok" else {}
    meta = load(os.path.join(run, "meta.json"), {})
    n_images = len(neutral_names(run))
    claude = load(os.path.join(run, "claude.json"))
    try:
        n_claims = len(compare_claims.claims_list(claude)) if claude is not None else 0
    except compare_claims.SchemaError:
        n_claims = 0
    now = datetime.datetime.now().astimezone()
    fm = {
        "skill": "visual-xval",
        "target": f"{n_images} images" + (" (sequence)" if meta.get("sequence") else ""),
        "model": settings.get("model", ""),
        "effort": settings.get("effort", ""),
        "profile_source": settings.get("profile_source", ""),
        "first_side_model": str(meta.get("first_side_model", "")),
        "timestamp": now.isoformat(timespec="seconds"),
        "n_images": n_images,
        "n_claims": n_claims,
        "agreement_rate": comparison["agreement_rate"] if comparison else "",
        "claude_answers_sha256": seal_record.get("sha256", ""),
        "sealed_at": seal_record.get("sealed_at", ""),
        "seal_broken": str(bool(seal_check.get("seal_broken", not seal_record))).lower(),
        "codex_requested_at": request.get("requested_at", ""),
        "codex_reply_sha256": request.get("reply_sha256", ""),
        "sam_status": sam_state.get("sam_status", "not_run"),
    }
    if fallback:   # nothing was read, so nothing is claimed about the seal (round 8, Z2)
        fm["seal_broken"] = "unknown"
    changed = records_changed(run, seal_record) if not stopped else []
    if error:
        fm["error"] = error["error"]
    elif changed:   # in the frontmatter, where codex-status reads (round 7, Y4)
        fm["error"] = "target_invalid"
    # one line each, no control characters: a value copied from a record cannot add a field (round 8, K5)
    fm = {k: sanitize(v) if isinstance(v, str) else v for k, v in fm.items()}
    lines = ["---"] + [f"{k}: {v}" for k, v in fm.items()] + ["---", "", f"# Visual cross-validation — {fm['target']}", ""]
    if note:
        lines += [f"The result step could not read all of the run's records ({sanitize(note)}); the run's own error "
                  "is shown, and nothing else from the run is.", ""]
    if changed:
        lines += [f"Found when the result was written: {', '.join(changed)} changed after the step that wrote "
                  f"{'them' if len(changed) > 1 else 'it'}, so the values below may not be the ones the steps produced.", ""]
    if error:
        lines += [f"Run stopped at step `{error.get('step', '?')}`: `{error['error']}`. No retry.", ""]
        if error["error"] in NATIVE_PREFLIGHT:
            lines += [f"Runtime preflight detail: {sanitize(error.get('detail', ''))}", ""]
        else:
            lines += [f"Detail: {sanitize(error.get('detail', ''))}", ""]
    lines += ["## Agreement", ""]
    if comparison:
        n_dis = len(comparison["disagreements"])
        counts = adjudicated.get("counts", {})
        lines += [f"Agreement rate {comparison['agreement_rate']} over {comparison['n_frames']} frames; "
                  f"{n_dis} disagreement(s): {counts.get('resolved_claude', 0)} resolved for Claude, "
                  f"{counts.get('resolved_codex', 0)} for Codex, {counts.get('unverifiable', n_dis)} unverifiable."]
        if fm["seal_broken"] == "true":
            lines += ["", "**The seal failed**: Claude's answer file changed after it was sealed, so it cannot be shown "
                      "that Claude answered before seeing Codex's answers. The comparison below was still made."]
    else:
        lines += ["No comparison was made."]
    lines += ["", "## Disagreements", ""]
    verdicts = {a["id"]: a for a in adjudicated.get("adjudications", []) if isinstance(a, dict) and "id" in a}
    no_zoom = {z["id"]: z.get("reason") for z in load(os.path.join(run, "zoom_skipped.json"), [])
               if isinstance(z, dict) and "id" in z}
    for item in (comparison or {}).get("disagreements", []):
        a = verdicts.get(item["id"], {})
        lines.append(f"- **{item['id']}** {describe(item)}: Claude `{item['claude']}`, Codex `{item['codex']}` → "
                     f"**{a.get('verdict', 'unverifiable')}**")
        for e in a.get("evidence", []):
            lines.append(f"  - {e['source']}: {e['detail']}")
        if item["id"] in no_zoom:
            lines.append(f"  - no zoom question: {no_zoom[item['id']]}")
        if a.get("note"):
            lines.append(f"  - {a['note']}")
    if not (comparison or {}).get("disagreements"):
        lines.append("None.")
    if adjudicated.get("zoom_seal_broken"):
        lines += ["", "**The zoom seal failed**: Claude's zoom answers changed after they were sealed, so no "
                  "disagreement was settled by the zoom round."]
    if load(os.path.join(run, "zoom_rejected.json")):
        rejected = load(os.path.join(run, "zoom_rejected.json"), {})
        lines += ["", f"**The zoom round was not used**: Claude's zoom answers failed the checks "
                  f"({sanitize(rejected.get('detail', ''))}), so no disagreement was settled by it."]
    if adjudicated.get("zoom_plan_broken"):
        lines += ["", "**The zoom plan, its crops or the comparison it came from changed after they were recorded**, "
                  "so no disagreement was settled by the zoom round."]
    if adjudicated.get("sam_record_broken"):
        lines += ["", "**SAM's output does not match what the SAM step recorded**, so no disagreement was settled by SAM."]
    if adjudicated.get("zoom_codex_record_broken"):
        lines += ["", "**Codex's zoom answers changed after they were recorded**, so no disagreement was settled "
                  "by the zoom round."]
    sam_detail = sanitize(sam_state.get("detail", ""))
    lines += ["", "## SAM evidence", "", f"Status: `{fm['sam_status']}`. {sam_detail}".rstrip()]
    if track:
        anchors = [a["frame"] for a in load(os.path.join(run, "anchors.json"), {}).get("anchors", [])]
        lines.append(f"Anchors: {', '.join(anchors) or 'none'}; collapsed (invalid) frames: "
                     f"{len(track.get('invalid_frames', []))} — {', '.join(track.get('invalid_frames', [])) or 'none'}.")
    lines += ["", "## Seal", "",
              f"Claude's answers: SHA-256 `{fm['claude_answers_sha256'] or 'none'}`, sealed at {fm['sealed_at'] or 'never'}; "
              f"recomputed {seal_when}: `{seal_check.get('sha256_now') or 'n/a'}` → "
              + ("**broken**." if fm["seal_broken"] == "true" else "intact.")]
    for rnd, label, reply_name, seal_name in (("1", "round 1", "codex_round1.md", "seal.json"),
                                              ("zoom", "zoom round", "codex_zoom.md", "zoom_seal.json")):
        lines += request_lines(run, rnd, label, reply_name, load(os.path.join(run, seal_name), {}))
    lines += ["", "## Limitations", "",
              "- Agreement between the two models does not establish that either is correct; only a human reference can.",
              "- Zoom-round answers on Claude's side come from a subagent that saw only the crops and the question "
              "file; whether it was started fresh, with nothing else in its prompt, and whether its answers were sealed "
              "before they were read, depend on the skill being followed.",
              "- A count disagreement settled for one side means that the other count was ruled out and that exactly "
              "that many objects were seen in the crop or by SAM; objects that neither saw could still make the true "
              "count higher.",
              f"- A SAM measurement within {adjudicated.get('sam_margin_pct', 1.0)}% of a threshold is not used as evidence.",
              "- Each round is asked once per run. A new run on the same images is a fresh attempt the program cannot "
              "link to this one, and it is no longer blind to what this run showed."]
    vocab = load(os.path.join(run, "vocab.json"), {}) or {}
    if vocab.get("relations"):
        lines.append("- A SAM distance settles a relation both ways only when SAM measured as many tips as both sides "
                     "counted, which treats the agreed count as the true count; both sides can miss the same object.")
    if fm["sam_status"] == "ok" and vocab.get("track_point") != "tip":
        lines.append("- The vocabulary does not declare `track_point: tip`, so SAM gave count evidence only: its point "
                     "is the mask tip, which may not be the key point.")
    count_only = sorted(set(vocab.get("classes", {})) - set(vocab.get("key_points", {})))
    if count_only:   # no zoom question and no SAM evidence for them (#23 verify round 3, T8)
        lines.append(f"- Classes without a key point ({', '.join(count_only)}) are compared by count only: a count "
                     "disagreement on them gets no zoom question and no SAM evidence, so it cannot be settled.")
    first = fm["first_side_model"]
    if not first:
        lines.append("- The model that gave the first side's answers was not recorded.")
    elif not first.lower().startswith("claude"):
        lines.append(f"- The first side's answers came from `{first}`, not a Claude model. Both sides may then come from "
                     "one model family, whose errors are not independent, so agreement says less than it would across families.")
    return "\n".join(lines) + "\n", fm.get("error")
