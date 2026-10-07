#!/usr/bin/env python3
"""Orchestrator for /codex-pro:codex-visual-xval (#23). Every step reads and writes files in
one run directory, because each Bash call in the skill starts a fresh shell.

  init  --run RUN --vocab VOCAB [--sequence] IMAGE...   copy images under neutral names
  seal  --run RUN [--zoom]                              seal Claude's answers before Codex sees anything
  ask   --run RUN --round 1|zoom --model M --effort E --max-time S
  compare --run RUN                                     compare, print only what the zoom round needs
  crops --run RUN                                       crop and enlarge the disputed regions
  sam   --run RUN                                       SAM evidence when the frames are a sequence
  adjudicate --run RUN
  result --run RUN --out PATH [--model M --effort E --profile-source S]

The runtime comes from RUN/runtime.txt and any native preflight error from
RUN/runtime_error.txt; both are written by the skill's runtime-resolution step.

Exit status 5 means the run stopped with a structured error: {"error", "detail"} on stdout
and in RUN/error.json. Nothing is retried. Steps that see Codex's answers print only counts
and identifiers, never answer values, so Claude can still answer the zoom round blind.
"""
import datetime
import json
import os
import re
import shutil
import subprocess
import sys
from typing import Any

sys.dont_write_bytecode = True   # no __pycache__ next to the bundled scripts
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import adjudicate as adjudication  # noqa: E402
import compare_claims  # noqa: E402
import sam_track  # noqa: E402
import seal as sealing  # noqa: E402

INSTRUCTIONS = (
    "You are a careful visual analyst. Report only what is visible in the images you are given. "
    "Use only the classes in the vocabulary; anything else is class 'other' with a description. "
    "Answer every image, in the order given. Reply with JSON only, matching the schema exactly."
)


class Stop(Exception):
    def __init__(self, error: str, detail: str):
        super().__init__(detail)
        self.error, self.detail = error, detail


def load(path: str, default: Any = None) -> Any:
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return default


def dump(path: str, data: Any) -> None:
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=1)


def option(argv: list[str], name: str) -> str | None:
    return argv[argv.index(name) + 1] if name in argv and argv.index(name) + 1 < len(argv) else None


def image_size(path: str) -> tuple[int | None, int | None]:
    try:
        out = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", path],
                             capture_output=True, text=True, check=True).stdout
        w = int(re.search(r"pixelWidth: (\d+)", out).group(1))
        h = int(re.search(r"pixelHeight: (\d+)", out).group(1))
        return w, h
    except (OSError, subprocess.CalledProcessError, AttributeError):
        return None, None


# ── init / seal ─────────────────────────────────────────────────
def init(run: str, vocab_path: str, images: list[str], sequence: bool) -> None:
    vocab = load(vocab_path)
    if vocab is None:
        raise Stop("target_invalid", f"vocabulary unreadable: {vocab_path}")
    problems = compare_claims.vocab_problems(vocab)
    if problems:
        raise Stop("target_invalid", "; ".join(problems))
    if not images:
        raise Stop("target_invalid", "no images given")
    missing = [p for p in images if not os.path.isfile(p)]
    if missing:
        raise Stop("target_invalid", f"not a readable file: {missing}")
    os.makedirs(os.path.join(run, "frames"), exist_ok=True)
    frames = {}
    for n, src in enumerate(images, 1):
        name = f"f{n:02d}{os.path.splitext(src)[1].lower() or '.png'}"
        shutil.copyfile(src, os.path.join(run, "frames", name))
        w, h = image_size(src)
        frames[name] = {"source": os.path.abspath(src), "width": w, "height": h}
    dump(os.path.join(run, "frames.json"), frames)
    dump(os.path.join(run, "vocab.json"), vocab)
    dump(os.path.join(run, "meta.json"), {
        "started_at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "sequence": sequence, "n_images": len(images)})
    print(json.dumps({"ok": True, "frames": sorted(frames)}))


def neutral_names(run: str) -> list[str]:
    return sorted(load(os.path.join(run, "frames.json"), {}))


def seal_answers(run: str, zoom: bool) -> None:
    answers = os.path.join(run, "zoom_claude.json" if zoom else "claude.json")
    record = os.path.join(run, "zoom_seal.json" if zoom else "seal.json")
    if not os.path.isfile(answers):
        raise Stop("target_invalid", f"Claude's answers are missing: {answers}")
    if not zoom:
        vocab = load(os.path.join(run, "vocab.json"))
        try:
            claude = compare_claims.by_frame(compare_claims.claims_list(load(answers)), vocab)
        except (compare_claims.SchemaError, TypeError) as exc:
            raise Stop("target_invalid", f"Claude claims: {exc}")
        if sorted(claude) != neutral_names(run):
            raise Stop("target_invalid", "Claude claims must answer every image, by its neutral name")
    sealing.seal(answers, record)


# ── ask ─────────────────────────────────────────────────────────
def runtime(run: str) -> str:
    lines = open(os.path.join(run, "runtime_error.txt"), encoding="utf-8").read().splitlines() \
        if os.path.exists(os.path.join(run, "runtime_error.txt")) else []
    if lines and lines[0].strip():
        raise Stop(lines[0].strip(), " ".join(lines[1:]).strip() or lines[0].strip())
    path = open(os.path.join(run, "runtime.txt"), encoding="utf-8").read().strip() \
        if os.path.exists(os.path.join(run, "runtime.txt")) else ""
    if not path or not os.access(path, os.X_OK):
        raise Stop("runtime_unavailable", f"codex-call not found (runtime='{path}') remediation=install parallel-ai-agents or run codex-setup")
    try:
        help_text = subprocess.run([path, "--help"], capture_output=True, text=True, timeout=120).stdout
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise Stop("runtime_unavailable", f"codex-call --help failed: {exc}")
    if "--image" not in help_text:
        raise Stop("runtime_unsupported", "this codex-call does not accept --image; update parallel-ai-agents (needs 2.24.0 or later)")
    return path


def round1_prompt(run: str) -> str:
    vocab = load(os.path.join(run, "vocab.json"))
    names = neutral_names(run)
    constraints = [f"- {c}" for c in vocab.get("constraints", [])]
    constraints += [f"- There are at most {n} objects of class {c} in any image." for c, n in vocab.get("max_count", {}).items()]
    relations = "\n".join(f"- {k}: true when {r['definition']}, measured between the key points of "
                          f"{r['between'][0]} and {r['between'][1]}" for k, r in vocab.get("relations", {}).items())
    return f"""You are given {len(names)} images, in this order: {", ".join(names)}.

Closed vocabulary (anything else is class "other", with "other_description"):
{class_lines(vocab)}

Physical constraints that always hold:
{chr(10).join(constraints) or "- (none)"}

Relations to judge for every image (distance_pct is in percent of the image width):
{relations or "- (none)"}

For every image, report the count of each class you see and one key point for every object you count
(for instruments: the tip) as percentages of the image width (x_pct) and height (y_pct), so a class with
count 2 has exactly 2 points. Then judge every relation as true or false.

Reply with JSON only:
{{"claims": [{{"frame": "{names[0]}", "objects": {{"<CLASS>": <count>}},
  "points": [{{"class": "<CLASS>", "x_pct": <0-100>, "y_pct": <0-100>}}],
  "relations": {{"<relation>": true}}}}]}}
"""


def class_lines(vocab: dict) -> str:
    return "\n".join(f"- {k}: {v}" for k, v in vocab["classes"].items())


def extract_json(text: str) -> Any:
    fenced = re.findall(r"```(?:json)?\s*\n(.*?)\n```", text, re.DOTALL)
    for candidate in fenced + [text[text.find("{"): text.rfind("}") + 1] if "{" in text else ""]:
        try:
            return json.loads(candidate)
        except ValueError:
            continue
    return None


def classify(stderr: str, status: int) -> tuple[str, str]:
    low = stderr.lower()
    if "rate limit" in low or "429" in low:
        return "rate_limit", stderr.strip()[-500:]
    if "unauthorized" in low or "401" in low or "auth" in low:
        return "oauth_invalid", stderr.strip()[-500:]
    if "timed out" in low or "timeout" in low:
        return "timeout", stderr.strip()[-500:]
    return "runtime_unavailable", f"codex-call exit {status}: {stderr.strip()[-500:]}"


def call_codex(run: str, prompt: str, images: list[str], tag: str, argv: list[str]) -> str:
    path = runtime(run)
    prompt_file = os.path.join(run, f"prompt_{tag}.md")
    output = os.path.join(run, f"codex_{tag}.md")
    with open(prompt_file, "w", encoding="utf-8") as fh:
        fh.write(prompt)
    cmd = [path, "--output", output, "--model", option(argv, "--model") or "gpt-5.6-sol",
           "--effort", option(argv, "--effort") or "xhigh", "--max-time", option(argv, "--max-time") or "600",
           "--instructions", INSTRUCTIONS, "--prompt-file", prompt_file]
    for image in images:
        cmd += ["--image", image]
    done = subprocess.run(cmd, capture_output=True, text=True)   # foreground; the hard timeout is codex-call's
    if done.returncode != 0:
        raise Stop(*classify(done.stderr, done.returncode))
    try:
        return open(output, encoding="utf-8").read()
    except OSError:
        raise Stop("parse_failed", "codex-call exited 0 but wrote no output")


def ask(run: str, argv: list[str]) -> None:
    rnd = option(argv, "--round")
    if rnd == "1":
        names = neutral_names(run)
        reply = call_codex(run, round1_prompt(run), [os.path.join(run, "frames", n) for n in names], "round1", argv)
        data = extract_json(reply)
        vocab = load(os.path.join(run, "vocab.json"))
        try:
            codex = compare_claims.by_frame(compare_claims.claims_list(data), vocab)
        except (compare_claims.SchemaError, TypeError) as exc:
            raise Stop("parse_failed", f"Codex reply: {exc}")
        if sorted(codex) != names:
            raise Stop("parse_failed", "Codex reply does not answer every image")
        dump(os.path.join(run, "codex.json"), data if isinstance(data, dict) else {"claims": data})
        print(json.dumps({"ok": True, "round": "1", "frames_answered": len(codex)}))
        return
    if rnd == "zoom":
        plan = load(os.path.join(run, "zoom_plan.json"), {})
        if not plan:
            raise Stop("target_invalid", "no zoom plan: run `crops` first")
        crops = {item["crop"]: did for did, item in plan.items()}
        reply = call_codex(run, zoom_prompt(plan, load(os.path.join(run, "vocab.json"))),
                           [os.path.join(run, c) for c in sorted(crops)], "zoom", argv)
        data = extract_json(reply)
        answers = data.get("answers") if isinstance(data, dict) else None
        if not isinstance(answers, dict):
            raise Stop("parse_failed", "Codex zoom reply: expected {\"answers\": {...}}")
        result = {}
        for crop, did in crops.items():
            value = (answers.get(os.path.basename(crop)) or {}).get("value")
            if not valid_zoom_value(plan[did]["kind"], value):
                raise Stop("parse_failed", f"Codex zoom reply: no valid answer for {os.path.basename(crop)}")
            result[did] = value
        dump(os.path.join(run, "zoom_codex.json"), result)
        print(json.dumps({"ok": True, "round": "zoom", "crops_answered": len(result)}))
        return
    raise Stop("target_invalid", f"unknown round: {rnd}")


def valid_zoom_value(kind: str, value: Any) -> bool:
    if kind == "relation":
        return isinstance(value, bool)
    if kind == "count":
        return isinstance(value, int) and not isinstance(value, bool) and value >= 0
    if kind == "position":
        return isinstance(value, dict) and all(isinstance(value.get(k), (int, float)) for k in ("x_pct", "y_pct"))
    return False


def zoom_prompt(plan: dict, vocab: dict) -> str:
    lines = [f"You are given {len(plan)} cropped and enlarged image regions. Answer each question",
             "from that crop alone. The classes are:", class_lines(vocab), "",
             "Reply with JSON only:", '{"answers": {"<crop name>": {"value": <answer>}}}', ""]
    for did in sorted(plan, key=lambda d: plan[d]["crop"]):
        lines.append(f"- {os.path.basename(plan[did]['crop'])}: {plan[did]['question']}")
    return "\n".join(lines) + "\n"


# ── compare / crops ─────────────────────────────────────────────
def compare(run: str) -> None:
    check = {}
    if os.path.exists(os.path.join(run, "seal.json")):
        import contextlib, io
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            sealing.verify(os.path.join(run, "claude.json"), os.path.join(run, "seal.json"))
        check = json.loads(buf.getvalue())
    else:
        check = {"seal_broken": True, "sha256_sealed": None, "sha256_now": None}
    dump(os.path.join(run, "seal_check.json"), check)
    vocab = load(os.path.join(run, "vocab.json"))
    claude = compare_claims.by_frame(compare_claims.claims_list(load(os.path.join(run, "claude.json"))), vocab)
    codex = compare_claims.by_frame(compare_claims.claims_list(load(os.path.join(run, "codex.json"))), vocab)
    frames = load(os.path.join(run, "frames.json"), {})
    aspects = {n: f["height"] / f["width"] for n, f in frames.items() if f.get("width") and f.get("height")}
    result = compare_claims.compare(vocab, claude, codex, aspects)
    dump(os.path.join(run, "comparison.json"), result)
    disputes = [{k: d[k] for k in ("id", "frame", "kind", "class", "relation") if k in d} for d in result["disagreements"]]
    print(json.dumps({"agreement_rate": result["agreement_rate"], "n_frames": result["n_frames"],
                      "n_disagreements": len(disputes), "seal_broken": check["seal_broken"], "disputes": disputes},
                     ensure_ascii=False))


def dispute_points(item: dict, claude: dict, codex: dict) -> list[tuple[float, float]]:
    if item["kind"] == "position":
        return [tuple(item["claude"]), tuple(item["codex"])]
    pts = []
    for claim in (claude[item["frame"]], codex[item["frame"]]):
        for p in claim.get("points", []):
            if item["kind"] == "relation" or p["class"] == item.get("class"):
                pts.append((p["x_pct"], p["y_pct"]))
    return pts


def crop_box(points: list[tuple[float, float]]) -> list[float]:
    if not points:
        return [0.0, 0.0, 100.0, 100.0]
    pad, minimum = 12.0, 30.0
    x0, x1 = min(p[0] for p in points) - pad, max(p[0] for p in points) + pad
    y0, y1 = min(p[1] for p in points) - pad, max(p[1] for p in points) + pad
    for lo, hi, axis in ((x0, x1, "x"), (y0, y1, "y")):
        if hi - lo < minimum:
            grow = (minimum - (hi - lo)) / 2
            lo, hi = lo - grow, hi + grow
        lo, hi = max(0.0, lo), min(100.0, hi)
        if axis == "x":
            x0, x1 = lo, hi
        else:
            y0, y1 = lo, hi
    return [round(v, 2) for v in (x0, y0, x1, y1)]


def question(item: dict, box: list[float]) -> str:
    if item["kind"] == "relation":
        width = box[2] - box[0]
        return (f"Is '{item['relation']}' true here, defined as {item['definition']}? distance_pct is in percent of the "
                f"FULL image width; this crop spans {width:.0f}% of that width and is enlarged 2x. value: true or false.")
    if item["kind"] == "count":
        return f"How many objects of class {item['class']} are visible in this crop? value: an integer."
    return (f"Where is the key point (for an instrument: the tip) of the class {item['class']} object in this crop? "
            "value: {\"x_pct\": <0-100>, \"y_pct\": <0-100>} in percent of this crop.")


def crops(run: str) -> None:
    comparison = load(os.path.join(run, "comparison.json"))
    if comparison is None:
        raise Stop("target_invalid", "no comparison: run `compare` first")
    vocab = load(os.path.join(run, "vocab.json"))
    claude = compare_claims.by_frame(compare_claims.claims_list(load(os.path.join(run, "claude.json"))), vocab)
    codex = compare_claims.by_frame(compare_claims.claims_list(load(os.path.join(run, "codex.json"))), vocab)
    frames = load(os.path.join(run, "frames.json"), {})
    os.makedirs(os.path.join(run, "crops"), exist_ok=True)
    plan, shown = {}, []
    for n, item in enumerate(comparison["disagreements"], 1):
        box = crop_box(dispute_points(item, claude, codex))
        info = frames[item["frame"]]
        w, h = info.get("width"), info.get("height")
        if not w or not h:
            w, h = image_size(os.path.join(run, "frames", item["frame"]))
        px = [round(box[0] / 100 * w), round(box[1] / 100 * h), round(box[2] / 100 * w), round(box[3] / 100 * h)]
        crop = os.path.join("crops", f"z{n:02d}.png")
        target = os.path.join(run, crop)
        cw, ch = px[2] - px[0], px[3] - px[1]
        try:
            subprocess.run(["sips", "-s", "format", "png", "-c", str(ch), str(cw), "--cropOffset", str(px[1]), str(px[0]),
                            os.path.join(run, "frames", item["frame"]), "--out", target], capture_output=True, check=True)
            subprocess.run(["sips", "-Z", str(2 * max(cw, ch)), target, "--out", target], capture_output=True, check=True)
        except (OSError, subprocess.CalledProcessError) as exc:
            raise Stop("target_invalid", f"cannot crop {item['frame']}: {exc}")
        entry = {"crop": crop, "frame": item["frame"], "kind": item["kind"], "box_pct": box, "box_px": px,
                 "question": question(item, box)}
        for key in ("class", "relation", "definition"):
            if key in item:
                entry[key] = item[key]
        plan[item["id"]] = entry
        shown.append({"id": item["id"], "crop": os.path.join(run, crop), "question": entry["question"]})
    dump(os.path.join(run, "zoom_plan.json"), plan)
    print(json.dumps({"crops": shown}, ensure_ascii=False))


# ── SAM / adjudication ──────────────────────────────────────────
def sam(run: str) -> None:
    def record(status: str, detail: str = "") -> None:
        dump(os.path.join(run, "sam.json"), {"sam_status": status, "detail": detail})
        print(json.dumps({"sam_status": status, "detail": detail}, ensure_ascii=False))
    meta = load(os.path.join(run, "meta.json"), {})
    if not meta.get("sequence"):
        return record("not_applicable", "the images are not frames of one video in time order (init --sequence)")
    check = subprocess.run(["bash", os.path.join(HERE, "sam_env.sh"), "--check"], capture_output=True, text=True)
    if check.returncode != 0:
        return record("not_installed", check.stdout.strip())
    vocab = load(os.path.join(run, "vocab.json"))
    cls = vocab.get("track_class") or next(iter(vocab["classes"]))
    plan = sam_track.anchors(load(os.path.join(run, "comparison.json")), load(os.path.join(run, "claude.json")),
                             load(os.path.join(run, "codex.json")), cls)
    dump(os.path.join(run, "anchors.json"), plan)
    if not plan["anchors"]:
        return record("no_anchor", f"no agreeing frame has a {cls} to anchor on")
    dump(os.path.join(run, "sam_frames.json"), [os.path.join(run, "frames", n) for n in neutral_names(run)])
    python = os.path.expanduser("~/.codex-pro/sam-env/bin/python")
    done = subprocess.run([python, os.path.join(HERE, "sam_track.py"), "track", "--frames",
                           os.path.join(run, "sam_frames.json"), "--anchors", os.path.join(run, "anchors.json"),
                           "--out", os.path.join(run, "track.json")], capture_output=True, text=True)
    if done.returncode != 0:
        return record("failed", (done.stdout + done.stderr).strip()[-500:])
    track = load(os.path.join(run, "track.json"), {})
    record("ok", f"{len(track.get('frames', {}))} frames tracked, {len(track.get('invalid_frames', []))} collapsed")


def to_frame(value: dict, box: list[float]) -> list[float]:
    return [round(box[0] + value["x_pct"] / 100 * (box[2] - box[0]), 2),
            round(box[1] + value["y_pct"] / 100 * (box[3] - box[1]), 2)]


def adjudicate(run: str) -> None:
    plan = load(os.path.join(run, "zoom_plan.json"), {})
    mine, theirs = load(os.path.join(run, "zoom_claude.json"), {}), load(os.path.join(run, "zoom_codex.json"), {})
    zoom = {}
    for did, entry in plan.items():
        if did in mine and did in theirs:
            a, b = mine[did], theirs[did]
            if entry["kind"] == "position":
                a, b = to_frame(a, entry["box_pct"]), to_frame(b, entry["box_pct"])
            zoom[did] = {"claude": a, "codex": b}
    sam_state = load(os.path.join(run, "sam.json"), {})
    track = load(os.path.join(run, "track.json")) if sam_state.get("sam_status") == "ok" else None
    result = adjudication.adjudicate(load(os.path.join(run, "vocab.json")), load(os.path.join(run, "comparison.json")),
                                     zoom, track)
    dump(os.path.join(run, "adjudication.json"), result)
    print(json.dumps({"counts": result["counts"]}))


# ── result file ─────────────────────────────────────────────────
NATIVE_PREFLIGHT = {"runtime_unavailable", "package_corruption"}


def sanitize(text: str) -> str:
    text = re.sub(r"[\r\n\t]", " ", text)
    return re.sub(r"[\x00-\x1f\x7f]", "", text)[:500]


def describe(item: dict) -> str:
    what = item.get("relation") or item.get("class") or ""
    return f"{item['frame']} — {item['kind']}" + (f" ({what})" if what else "")


def result(run: str, argv: list[str]) -> None:
    error = load(os.path.join(run, "error.json"))
    comparison = load(os.path.join(run, "comparison.json"))
    adjudicated = load(os.path.join(run, "adjudication.json"), {})
    seal_record = load(os.path.join(run, "seal.json"), {})
    seal_check = load(os.path.join(run, "seal_check.json"), {})
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
        "model": option(argv, "--model") or "gpt-5.6-sol",
        "effort": option(argv, "--effort") or "xhigh",
        "profile_source": option(argv, "--profile-source") or "default",
        "timestamp": now.isoformat(timespec="seconds"),
        "n_images": n_images,
        "n_claims": n_claims,
        "agreement_rate": comparison["agreement_rate"] if comparison else "",
        "claude_answers_sha256": seal_record.get("sha256", ""),
        "sealed_at": seal_record.get("sealed_at", ""),
        "seal_broken": str(bool(seal_check.get("seal_broken", not seal_record))).lower(),
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
    for item in (comparison or {}).get("disagreements", []):
        a = verdicts.get(item["id"], {})
        lines.append(f"- **{item['id']}** {describe(item)}: Claude `{item['claude']}`, Codex `{item['codex']}` → "
                     f"**{a.get('verdict', 'unverifiable')}**")
        for e in a.get("evidence", []):
            lines.append(f"  - {e['source']}: {e['detail']}")
        if a.get("note"):
            lines.append(f"  - {a['note']}")
    if not (comparison or {}).get("disagreements"):
        lines.append("None.")
    lines += ["", "## SAM evidence", "", f"Status: `{fm['sam_status']}`. {sam_state.get('detail', '')}".rstrip()]
    if track:
        anchors = [a["frame"] for a in load(os.path.join(run, "anchors.json"), {}).get("anchors", [])]
        lines.append(f"Anchors: {', '.join(anchors) or 'none'}; collapsed (invalid) frames: "
                     f"{len(track.get('invalid_frames', []))} — {', '.join(track.get('invalid_frames', [])) or 'none'}.")
    lines += ["", "## Seal", "",
              f"Claude's answers: SHA-256 `{fm['claude_answers_sha256'] or 'none'}`, sealed at {fm['sealed_at'] or 'never'}; "
              f"recomputed before comparison: `{seal_check.get('sha256_now') or 'n/a'}` → "
              + ("**broken**." if fm["seal_broken"] == "true" else "intact.")]
    lines += ["", "## Limitations", "",
              "- Agreement between the two models does not establish that either is correct; only a human reference can.",
              "- Claude knows where the disagreements are when it answers the zoom round, so its zoom answers are not "
              "fully blind; Codex's zoom request carries no earlier answer from either side.",
              f"- A SAM measurement within {adjudicated.get('sam_margin_pct', 1.0)}% of a threshold is not used as evidence."]
    os.makedirs(".codex-pro", exist_ok=True)
    out = option(argv, "--out") or os.path.join(".codex-pro", f"visual-xval-{now.astimezone(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')}.md")
    with open(out, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    print(json.dumps({"result": out, "error": fm.get("error")}))


# ── entry point ─────────────────────────────────────────────────
def main(argv: list[str]) -> None:
    command, run = (argv[0] if argv else ""), option(argv, "--run")
    if not run:
        print(__doc__, file=sys.stderr)
        sys.exit(64)
    try:
        if command == "init":
            skip = {"--run", "--vocab"}
            images = [a for i, a in enumerate(argv[1:], 1)
                      if a not in ("--run", "--vocab", "--sequence") and argv[i - 1] not in skip]
            init(run, option(argv, "--vocab") or "", images, "--sequence" in argv)
        elif command == "seal":
            seal_answers(run, "--zoom" in argv)
        elif command == "ask":
            ask(run, argv)
        elif command == "compare":
            compare(run)
        elif command == "crops":
            crops(run)
        elif command == "sam":
            sam(run)
        elif command == "adjudicate":
            adjudicate(run)
        elif command == "result":
            result(run, argv)
        else:
            print(__doc__, file=sys.stderr)
            sys.exit(64)
    except Stop as stop:
        record = {"error": stop.error, "detail": stop.detail, "step": command}
        if os.path.isdir(run):
            dump(os.path.join(run, "error.json"), record)
        print(json.dumps({"error": stop.error, "detail": stop.detail}, ensure_ascii=False))
        sys.exit(5)


if __name__ == "__main__":
    main(sys.argv[1:])
