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
from run_files import Stop, differences, explain, is_run_dir, ledger, safe_digest


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


def request_lines(requests: dict, entries: dict, run: str, rnd: str, label: str, reply_name: str,
                  seal_record: dict) -> list[str]:
    """One round's request, from the verified request record, with the raw reply's digest from the ledger,
    re-checked now (#23 verify round 2, S1, S9). A mismatch is named once, in the list of records that do not
    match the ledger (round 9, B4)."""
    record = requests.get(rnd)
    if not isinstance(record, dict):
        return []
    entered = entries.get(reply_name)
    when = in_form("codex_requested_at", record.get("requested_at")) or "an unrecorded time"
    if entered and safe_digest(os.path.join(run, reply_name)) != entered:
        line = f"Codex {label}: requested at {when}."   # the reply is named once, in the list above (D4)
    else:
        digest = entered if isinstance(entered, str) and HEX64.fullmatch(entered) else "none"
        line = f"Codex {label}: requested at {when}; reply SHA-256 `{digest}`"
        if entered:
            line += "; the reply file still matches."
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
# A path starts at a root: '~/' or '$TMPDIR/', or '/' not preceded by an ASCII letter, digit or one of
# '_./$~\', in each case with any number of slashes; a colon or a CJK character may come before it
# (round 8, K4). Only the '//' of a URL, right after its ':', is not a root: a path that starts with '//'
# or follows a hyphen is cut too, and after a colon a single '/' still starts one (background security
# review after e79ff81).
PATH = re.compile(r"(?<![A-Za-z0-9_./$~\\])(?:(?:~|\$TMPDIR)/+|(?<!:)/+|(?<=:)/(?!/))(?:(?!://)[^\"\x00])*/")


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
    # Every line break splitlines() and YAML know ends a line here too: NEL, LS and PS included, or a
    # value would read as one line here and as two to whoever parses the frontmatter (background
    # security review after b8cef27). Other control characters, C1 included, are dropped.
    text = re.sub(r"\r\n|[\r\x85\u2028\u2029]", "\n", text).replace("\t", " ")
    text = re.sub(r"[\x00-\x09\x0b-\x1f\x7f-\x9f]", "", text)
    text = re.sub(r"[\ud800-\udfff]", "\ufffd", text)   # a lone surrogate cannot be written (round 9, A1)
    # Only a web URL is kept: file://, smb://, afp:// and the like name local or shared folders, so they
    # are cut like paths (round 8, K4; background review after e79ff81).
    text = re.sub(r"(?<![A-Za-z0-9+.-])(?!https?://)[A-Za-z][A-Za-z0-9+.-]*://", "/", text)
    # A root ends at '/', a line end or a space, or at punctuation that is itself followed by a space or the
    # line end: '/Users/jane.doe/…' is another directory, not home followed by '.doe' (round 8, K4; round 9, A2).
    for root, name in local_roots():
        text = re.sub(re.escape(root) + r"(?=/|$|\s|['\",.;:)\]](?:\s|$))", name, text, flags=re.MULTILINE)
    text = OWN_PLACE.sub("\x00", text)
    lines = ["; ".join(cut_paths(c) for c in line.split("; ")) for line in text.split("\n")]
    return " ".join(lines).replace("\x00", "~/.codex-pro/sam-env")[:500]


def describe(item: dict) -> str:
    what = item.get("relation") or item.get("class") or ""
    return f"{item['frame']} — {item['kind']}" + (f" ({what})" if what else "")


ERRORS = ("rate_limit", "oauth_invalid", "timeout", "target_invalid", "runtime_unsupported", "parse_failed",
          "runtime_unavailable", "package_corruption", "backend_error", "internal_error")
MODEL_ID = r"[A-Za-z0-9][A-Za-z0-9._:/@+-]{0,99}"
TIMESTAMP = r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})"
# Each frontmatter field, in order, and the only form it is written in; any other value is written `invalid`
# and an empty one means "not recorded" (#23 verify round 9). This closed list is what codex-status reads.
FORMS = {
    "skill": r"visual-xval",
    "target": r"\d{1,3} images(?: \(sequence\))?",
    "model": MODEL_ID,
    "effort": r"[a-z]{1,20}",
    "profile_source": r"default|global|project|mixed",
    "first_side_model": MODEL_ID,
    "timestamp": TIMESTAMP,
    "n_images": r"\d{1,3}",
    "n_claims": r"\d{1,4}",
    "agreement_rate": r"[01](?:\.\d{1,3})?",
    "claude_answers_sha256": r"[0-9a-f]{64}",
    "sealed_at": TIMESTAMP,
    "seal_broken": r"true|false",
    "codex_requested_at": TIMESTAMP,
    "codex_reply_sha256": r"[0-9a-f]{64}",
    "sam_status": r"not_run|not_applicable|no_anchor|not_installed|failed|ok",
    "error": "|".join(ERRORS),
}
STEP = re.compile(r"init|confirm-privacy|seal(?: --zoom)?|ask --round (?:1|zoom|None)|compare|crops|sam|adjudicate|result")
# Who may have written an error's detail. Only xval's own is shown; the others, a closed list, stay in the run
# directory (round 9): codex-call's messages, the runtime check's detail and Python's exception text. SAM's
# output is the fourth, kept in sam.json.
OUTSIDE = {"codex-call": "the message codex-call printed", "runtime": "the runtime check's detail",
           "python": "the text of the unexpected exception", "claude-answers": "the text of Claude's answers"}
# The records the comparison is derived from: it is shown only when they are verified too (round 10, D3).
# The adjudication is derived from every record, so any difference keeps its verdicts out.
COMPARED_FROM = ("vocab.json", "frames.json", "meta.json", "frames/", "hires/", "claude.json", "seal.json",
                 "codex.json", "comparison.json")
HEX64 = re.compile(r"[0-9a-f]{64}")


def in_form(field: str, value: Any) -> str:
    if value is None or value == "":
        return ""
    if isinstance(value, bool) or not isinstance(value, (str, int, float)):
        return "invalid"
    return str(value) if re.fullmatch(FORMS[field], str(value)) else "invalid"


def error_detail(error: dict) -> str:
    """The error's detail when xval wrote it, else where it is kept."""
    source, detail = error.get("source"), error.get("detail")
    if source == "xval" and isinstance(detail, str):
        return sanitize(detail)
    what = OUTSIDE.get(source, "its detail") if isinstance(source, str) else "its detail"
    return f"kept in error.json in the run directory ({what}, which the result file does not show)."


def result(run: str, argv: list[str]) -> None:
    """Render the result file, then write it. It is rendered only from records the ledger verifies, so a
    record of an unexpected shape means the ledger was redone by hand or xval has a defect; then the last
    resort writes fixed text only (round 9, A1, A3). Writing can fail, and that is the result step's own error."""
    if not is_run_dir(run):
        # Nothing in a directory that is not a run is read: its files are not a run's, and an error.json
        # placed there would read as this run's outcome (#23 verify round 6, Q1).
        with tempfile.TemporaryDirectory() as empty:
            text, error = render(empty, {"error": "target_invalid", "step": "result", "source": "xval",
                                         "detail": f"{os.path.basename(os.path.abspath(run))} is not a run directory, "
                                                   "so nothing in it was read"})
    else:
        try:
            text, error = render(run, None)
        except Exception:
            text, error = last_resort(run)
    emit(text, error, argv)


def emit(text: str, error: str | None, argv: list[str]) -> None:
    out = option(argv, "--out")
    data = text.encode("utf-8", "replace")   # encoded before the file is opened: no empty file is left (A1)
    try:
        if not out:   # .codex-pro is created only for the default location (round 6, Q1)
            os.makedirs(".codex-pro", exist_ok=True)
            stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
            out = os.path.join(".codex-pro", f"visual-xval-{stamp}.md")
        with open(out, "wb") as fh:
            fh.write(data)
    except OSError as exc:   # the result step's own error, kept out of the run's (round 8, K1)
        raise Stop("target_invalid", f"cannot write the result file {os.path.basename(out or '.codex-pro')}: "
                   f"{exc.strerror or type(exc).__name__}")
    print(json.dumps({"result": out, "error": error}))


def frontmatter(fm: dict) -> list[str]:
    return ["---"] + [f"{k}: {fm[k]}" for k in FORMS if k in fm] + ["---"]


def last_resort(run: str) -> tuple[str, str]:
    """Fixed text only. Nothing from the run's records is read but the class of its own error, which is
    kept when it is one of the classes; a seal that was not checked is not reported as intact (B5)."""
    own = load(os.path.join(run, "error.json"), {})
    error = own.get("error") if isinstance(own.get("error"), str) and own.get("error") in ERRORS else "internal_error"
    fm = {k: "" for k in FORMS}
    fm.update(skill="visual-xval", seal_broken="true", error=error,
              timestamp=datetime.datetime.now().astimezone().isoformat(timespec="seconds"))
    lines = frontmatter(fm) + [
        "", "# Visual cross-validation", "",
        "The result step could not render this run's records, so nothing from them is shown; they are in the run "
        "directory.", "", f"Error: `{error}`. No retry.", "",
        "## Agreement", "", "Not shown.", "", "## Disagreements", "", "Not shown.", "",
        "## SAM evidence", "", "Not shown.", "", "## Seal", "", "Not checked.", "",
        "## Limitations", "",
        "- Agreement between the two models does not establish that either is correct; only a human reference can."]
    return "\n".join(lines) + "\n", error


def render(run: str, stopped: dict | None) -> tuple[str, str | None]:
    # The ledger's one rule over every record, checked now (round 7, Y4; round 9). Only the records it verifies
    # are read; the others are listed once and shown as not shown (A3). The run's error and the profile are
    # records too (round 10, C2).
    found = differences(run) if not stopped else []
    bad = {name for name, _ in found}
    entries = ledger(run)

    def record(name: str, default: Any) -> Any:
        return default if name in bad else load(os.path.join(run, name), default)

    error = stopped or record("error.json", {}) or None
    if error and "error" not in error:
        error = None

    compared_ok = not any(n == x or (x.endswith("/") and n.startswith(x)) for n in bad for x in COMPARED_FROM)
    comparison = (record("comparison.json", {}) or None) if compared_ok else None
    if comparison and not (isinstance(comparison.get("disagreements"), list)
                           and all(isinstance(d, dict) for d in comparison["disagreements"])):
        comparison = None
    verdicts_shown = not found   # the adjudication rests on every record (D3)
    adjudicated = record("adjudication.json", {}) if verdicts_shown else {}
    seal_record = record("seal.json", {})
    # The seal is checked now: one never checked is not reported as intact, a missing one counts as broken (A4)
    sealed_now = safe_digest(os.path.join(run, "claude.json"))
    seal_broken = not seal_record or sealed_now != seal_record.get("sha256") or bool(bad & {"claude.json", "seal.json"})
    settings = record("profile.json", {})   # each value is form-checked as well
    requests = record("requests.json", {})
    request = requests.get("1") if isinstance(requests.get("1"), dict) else {}
    sam_state = record("sam.json", {})
    track = record("track.json", {}) if sam_state.get("sam_status") == "ok" else {}
    meta = record("meta.json", {})
    frames = record("frames.json", {})
    n_images = len([k for k in frames if isinstance(k, str)])
    claude = record("claude.json", None)
    try:
        n_claims = len(compare_claims.claims_list(claude)) if claude is not None else 0
    except compare_claims.SchemaError:
        n_claims = 0
    raw = {
        "skill": "visual-xval",
        "target": f"{n_images} images" + (" (sequence)" if meta.get("sequence") is True else ""),
        "model": settings.get("model"),
        "effort": settings.get("effort"),
        "profile_source": settings.get("profile_source"),
        "first_side_model": meta.get("first_side_model"),
        "timestamp": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "n_images": n_images,
        "n_claims": n_claims,
        "agreement_rate": comparison.get("agreement_rate") if comparison else "",
        "claude_answers_sha256": seal_record.get("sha256"),
        "sealed_at": seal_record.get("sealed_at"),
        "seal_broken": "true" if seal_broken else "false",
        "codex_requested_at": request.get("requested_at"),
        "codex_reply_sha256": entries.get("codex_round1.md") if request and "codex_round1.md" not in bad else "",
        "sam_status": "" if "sam.json" in bad else sam_state.get("sam_status", "not_run"),
    }
    if error:
        raw["error"] = error["error"]
    elif found:   # in the frontmatter, where codex-status reads (round 7, Y4)
        raw["error"] = "target_invalid"
    fm = {k: in_form(k, v) for k, v in raw.items()}
    lines = frontmatter(fm) + ["", f"# Visual cross-validation — {fm['target'] or 'images'}", ""]
    # each record once, with what is actually the case: those the run already stopped on are in its error (B4)
    named = set(n for n in error.get("records") or [] if isinstance(n, str)) \
        if error and isinstance(error.get("records"), list) else set()
    unnamed = [(name, how) for name, how in found if name not in named]
    if unnamed:
        lines += [f"Found when the result was written: {explain(run, unnamed)}; those records are not shown.", ""]
    if error:
        step = error.get("step") if isinstance(error.get("step"), str) and STEP.fullmatch(error.get("step")) else "?"
        lines += [f"Run stopped at step `{step}`: `{fm['error']}`. No retry.", ""]
        label = "Runtime preflight detail" if fm["error"] in NATIVE_PREFLIGHT else "Detail"
        lines += [f"{label}: {error_detail(error)}", ""]
    lines += ["## Agreement", ""]
    if not compared_ok:
        lines += ["Not shown: the comparison, or a record it came from, does not match the run's ledger."]
    elif comparison:
        n_dis = len(comparison["disagreements"])
        counts = adjudicated.get("counts", {})
        summary = f"Agreement rate {fm['agreement_rate']} over {comparison['n_frames']} frames; {n_dis} disagreement(s)"
        lines += [summary + (f": {counts.get('resolved_claude', 0)} resolved for Claude, {counts.get('resolved_codex', 0)} "
                             f"for Codex, {counts.get('unverifiable', n_dis)} unverifiable." if verdicts_shown
                             else "; the verdicts are not shown: the adjudication, or a record it came from, does "
                                  "not match the run's ledger.")]
    else:
        lines += ["No comparison was made."]
    if fm["seal_broken"] == "true" and "seal.json" in entries:   # a seal was made; also before comparing (A4)
        lines += ["", "**The seal failed**: Claude's answer file or its seal no longer matches what was sealed, so it "
                  "cannot be shown that Claude answered before seeing Codex's answers."]
    lines += ["", "## Disagreements", ""]
    verdicts = {a["id"]: a for a in adjudicated.get("adjudications", []) if isinstance(a, dict) and "id" in a}
    no_zoom = {z["id"]: z.get("reason") for z in record("zoom_skipped.json", [])
               if isinstance(z, dict) and "id" in z}
    for item in (comparison or {}).get("disagreements", []):
        a = verdicts.get(item["id"], {})
        verdict = a.get("verdict", "unverifiable") if verdicts_shown else "not shown"
        lines.append(f"- **{item['id']}** {describe(item)}: Claude `{item['claude']}`, Codex `{item['codex']}` → "
                     f"**{verdict}**")
        for e in a.get("evidence", []):
            lines.append(f"  - {e['source']}: {e['detail']}")
        if item["id"] in no_zoom:
            lines.append(f"  - no zoom question: {no_zoom[item['id']]}")
        if a.get("note"):
            lines.append(f"  - {a['note']}")
    if not (comparison or {}).get("disagreements"):
        lines.append("None." if compared_ok else "Not shown.")
    if adjudicated.get("zoom_seal_broken") or bad & {"zoom_claude.json", "zoom_seal.json"}:
        lines += ["", "**The zoom seal failed**: Claude's zoom answers or their seal no longer match what was sealed, "
                  "so no disagreement is settled by the zoom round."]
    rejected = record("zoom_rejected.json", {})
    if rejected:   # xval's own words about the answers it refused
        detail = rejected.get("detail") if isinstance(rejected.get("detail"), str) else ""
        lines += ["", f"**The zoom round was not used**: Claude's zoom answers failed the checks "
                  f"({sanitize(detail)}), so no disagreement was settled by it."]
    lines += ["", "## SAM evidence", ""]
    if "sam.json" in bad:
        lines.append("Not shown: SAM's record does not match the run's ledger.")
    else:
        detail = sam_state.get("detail")
        if sam_state.get("detail_source") == "xval" and isinstance(detail, str):
            shown = sanitize(detail)
        else:   # SAM's own output, the fourth outside source (round 9)
            shown = "SAM's output is kept in sam.json in the run directory." if detail else ""
        lines.append(f"Status: `{fm['sam_status']}`. {shown}".rstrip())
    if track and "anchors.json" not in bad:
        anchors = [a["frame"] for a in record("anchors.json", {}).get("anchors", [])]
        lines.append(f"Anchors: {', '.join(anchors) or 'none'}; collapsed (invalid) frames: "
                     f"{len(track.get('invalid_frames', []))} — {', '.join(track.get('invalid_frames', [])) or 'none'}.")
    if "seal.json" in bad:   # not "never sealed": the seal is there in the ledger, and not shown (D3)
        sealed = "the seal does not match the run's ledger, so it is not shown"
    else:
        sealed = f"SHA-256 `{fm['claude_answers_sha256'] or 'none'}`, sealed at {fm['sealed_at'] or 'never'}"
    lines += ["", "## Seal", "",
              f"Claude's answers: {sealed}; recomputed when the result was written: `{sealed_now or 'n/a'}` → "
              + ("**broken**." if fm["seal_broken"] == "true" else "intact.")]
    for rnd, label, reply_name, seal_name in (("1", "round 1", "codex_round1.md", "seal.json"),
                                              ("zoom", "zoom round", "codex_zoom.md", "zoom_seal.json")):
        lines += request_lines(requests, entries, run, rnd, label, reply_name, record(seal_name, {}))
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
    vocab = record("vocab.json", {})
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
    if first in ("", "invalid"):
        lines.append("- The model that gave the first side's answers was not recorded"
                     + (" in a valid form." if first else "."))
    elif not first.lower().startswith("claude"):
        lines.append(f"- The first side's answers came from `{first}`, not a Claude model. Both sides may then come from "
                     "one model family, whose errors are not independent, so agreement says less than it would across families.")
    return "\n".join(lines) + "\n", fm.get("error")
