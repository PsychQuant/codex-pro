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
from run_files import answers_changed, inputs_digest, is_run_dir


def load(path: str, default: Any = None) -> Any:
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return default


def option(argv: list[str], name: str) -> str | None:
    return argv[argv.index(name) + 1] if name in argv and argv.index(name) + 1 < len(argv) else None


def request_lines(run: str, rnd: str, label: str, reply_name: str, seal_record: dict) -> list[str]:
    """One round's request record, re-checked now: both the raw reply and the parsed answers are
    compared with the digests recorded when Codex answered (#23 verify round 2, S1, S9)."""
    record = load(os.path.join(run, "requests.json"), {}).get(rnd)
    if not record:
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


def neutral_names(run: str) -> list[str]:
    return sorted(load(os.path.join(run, "frames.json"), {}))


NATIVE_PREFLIGHT = {"runtime_unavailable", "package_corruption"}


def local_roots() -> list[tuple[str, str]]:
    """The machine's own directories, longest first: a home directory inside the temporary one is
    replaced as home."""
    home, tmp = os.path.expanduser("~").rstrip("/"), tempfile.gettempdir().rstrip("/")
    roots = [(home, "~"), (tmp, "$TMPDIR"), ("/private" + tmp, "$TMPDIR")]
    return sorted((r for r in roots if len(r[0]) > 1), key=lambda r: -len(r[0]))


OWN_PLACES = ("~/.codex-pro/",)   # the skill's own fixed locations, which tell the user where to look


def sanitize(text: str) -> str:
    """One line, no control characters, and no local directories. Details are built from file names
    where they are raised (#23 verify round 6, W1); this is the backstop for what a tool printed. The
    machine's roots are replaced first, then any absolute path is cut back to its last part: from its
    root to the last '/' before a quote or bracket, across spaces, since a directory name can hold
    spaces (round 5, V4 stopped at the first space). Cutting some text too many is better than leaving
    a directory name. A URL is left alone: its slashes follow ':' or '/' or a word."""
    text = re.sub(r"[\r\n\t]", " ", text)
    text = re.sub(r"[\x00-\x1f\x7f]", "", text)
    for root, name in local_roots():
        text = text.replace(root, name)
    for n, place in enumerate(OWN_PLACES):
        text = text.replace(place, f"\x00{n}\x00")
    text = re.sub(r"(?<![\w.:/$~\\])(?:~|\$TMPDIR)?/[^'\"\])\]\x00]*/", "…/", text)
    for n, place in enumerate(OWN_PLACES):
        text = text.replace(f"\x00{n}\x00", place)
    return text[:500]


def describe(item: dict) -> str:
    what = item.get("relation") or item.get("class") or ""
    return f"{item['frame']} — {item['kind']}" + (f" ({what})" if what else "")


def result(run: str, argv: list[str]) -> None:
    if not is_run_dir(run):
        # Nothing in a directory that is not a run is read: its files are not a run's, and an error.json
        # placed there would read as this run's outcome (#23 verify round 6, Q1). The file is still
        # written, from an empty directory, so the run ends with a result as always.
        with tempfile.TemporaryDirectory() as empty:
            write_result(empty, argv, {"error": "target_invalid", "step": "result",
                                       "detail": f"{os.path.basename(os.path.abspath(run))} is not a run directory, "
                                                 "so nothing in it was read"})
        return
    write_result(run, argv, None)


def write_result(run: str, argv: list[str], stopped: dict | None) -> None:
    error = stopped or load(os.path.join(run, "error.json"))
    comparison = load(os.path.join(run, "comparison.json"))
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
    codex_check = load(os.path.join(run, "codex_check.json"), {})
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
        "first_side_model": sanitize(str(meta.get("first_side_model", ""))),
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
    if error:
        fm["error"] = error["error"]
    lines = ["---"] + [f"{k}: {v}" for k, v in fm.items()] + ["---", "", f"# Visual cross-validation — {fm['target']}", ""]
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
    verdicts = {a["id"]: a for a in adjudicated.get("adjudications", [])}
    no_zoom = {z["id"]: z["reason"] for z in load(os.path.join(run, "zoom_skipped.json"), [])}
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
    if seal_record.get("inputs_sha256") and seal_record["inputs_sha256"] != inputs_digest(run):
        lines += ["", "**The vocabulary, the image copies or the run's settings changed after Claude's answers were "
                  "sealed** (checked when the result was written)."]
    changed = answers_changed(run)
    if changed:   # rechecked now, not only when compare ran (#23 verify round 6, W2)
        lines += ["", f"**{' and '.join(changed)} changed after the comparison read {'them' if len(changed) > 1 else 'it'}**, "
                  "so the answers in the run directory are not the ones compared and settled above."]
    if codex_check.get("codex_record_broken"):
        lines += ["", "**Codex's answers changed after they were recorded**: the comparison used a file whose "
                  "digest no longer matches the one recorded when Codex answered."]
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
    out = option(argv, "--out")
    if not out:   # .codex-pro is created only for the default location (round 6, Q1)
        os.makedirs(".codex-pro", exist_ok=True)
        out = os.path.join(".codex-pro", f"visual-xval-{now.astimezone(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')}.md")
    with open(out, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    print(json.dumps({"result": out, "error": fm.get("error")}))
