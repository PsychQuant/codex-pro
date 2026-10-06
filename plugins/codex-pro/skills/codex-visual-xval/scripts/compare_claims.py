#!/usr/bin/env python3
"""Deterministic comparison of two claim sets for /codex-pro:codex-visual-xval (#23).

Subcommands:
  check-vocab VOCAB                         validate the vocabulary file
  compare VOCAB CLAUDE CODEX [--frames F]   compare per-frame claims, print JSON

Exit status: 0 ok; 2 target_invalid (vocabulary or Claude's own claims are wrong);
3 parse_failed (Codex's reply does not fit the claim schema). Errors are printed as
one JSON object {"error": ..., "detail": ...} on stdout.

Each disagreement is exactly one of: count (a class has different counts), position
(objects of one class, paired by minimum total distance, differ by more than the
position threshold), or relation (a relation has different truth values). Positions
are percentages of image width/height; the distance is measured in percent of image
width, using the frame's aspect ratio when --frames gives it (default 1.0).
"""
import itertools
import json
import math
import re
import sys
from typing import Any

THRESHOLD = re.compile(r"(<=|>=|<|>|==)\s*-?\d+(\.\d+)?")
MAX_EXACT_PAIRING = 7   # brute-force minimum-distance pairing up to 7! = 5040 orders


class SchemaError(Exception):
    pass


def fail(error: str, detail: str, status: int) -> None:
    print(json.dumps({"error": error, "detail": detail}, ensure_ascii=False))
    sys.exit(status)


def load_json(path: str) -> Any:
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def vocab_problems(vocab: Any) -> list[str]:
    problems = []
    if not isinstance(vocab, dict):
        return ["vocabulary is not a JSON object"]
    if not isinstance(vocab.get("classes"), dict) or not vocab["classes"]:
        problems.append("classes must be a non-empty object")
    relations = vocab.get("relations", {})
    if not isinstance(relations, dict):
        problems.append("relations must be an object")
    else:
        for name, definition in relations.items():
            if not isinstance(definition, str) or not THRESHOLD.search(definition):
                problems.append(f"relation '{name}' has no quantitative definition (e.g. 'distance_pct < 5')")
    threshold = vocab.get("position_threshold_pct", 5)
    if not isinstance(threshold, (int, float)) or threshold <= 0:
        problems.append("position_threshold_pct must be a positive number")
    return problems


def claims_list(data: Any) -> list[dict]:
    claims = data.get("claims") if isinstance(data, dict) else data
    if not isinstance(claims, list):
        raise SchemaError("expected a list of claims or an object with a 'claims' list")
    return claims


def check_claim(claim: Any, vocab: dict) -> None:
    allowed = set(vocab["classes"]) | {"other"}
    if not isinstance(claim, dict) or not isinstance(claim.get("frame"), str):
        raise SchemaError("every claim needs a 'frame' name")
    frame = claim["frame"]
    objects = claim.get("objects")
    if not isinstance(objects, dict):
        raise SchemaError(f"{frame}: 'objects' must be an object of class counts")
    for cls, count in objects.items():
        if cls not in allowed:
            raise SchemaError(f"{frame}: class '{cls}' is not in the vocabulary (use 'other')")
        if not isinstance(count, int) or isinstance(count, bool) or count < 0:
            raise SchemaError(f"{frame}: count of '{cls}' must be a non-negative integer")
    if objects.get("other") and not str(claim.get("other_description", "")).strip():
        raise SchemaError(f"{frame}: objects of class 'other' need an 'other_description'")
    points = claim.get("points", [])
    if not isinstance(points, list):
        raise SchemaError(f"{frame}: 'points' must be a list")
    for point in points:
        if not isinstance(point, dict) or point.get("class") not in allowed:
            raise SchemaError(f"{frame}: every point needs a vocabulary class")
        for axis in ("x_pct", "y_pct"):
            value = point.get(axis)
            if not isinstance(value, (int, float)) or isinstance(value, bool) or not 0 <= value <= 100:
                raise SchemaError(f"{frame}: point {axis} must be a number from 0 to 100")
    relations = claim.get("relations")
    if not isinstance(relations, dict):
        raise SchemaError(f"{frame}: 'relations' must be an object")
    for name in vocab.get("relations", {}):
        if not isinstance(relations.get(name), bool):
            raise SchemaError(f"{frame}: relation '{name}' must be true or false")


def by_frame(claims: list[dict], vocab: dict) -> dict[str, dict]:
    result = {}
    for claim in claims:
        check_claim(claim, vocab)
        if claim["frame"] in result:
            raise SchemaError(f"{claim['frame']}: frame answered twice")
        result[claim["frame"]] = claim
    return result


def distance(a: dict, b: dict, aspect: float) -> float:
    return math.hypot(a["x_pct"] - b["x_pct"], (a["y_pct"] - b["y_pct"]) * aspect)


def pair_points(left: list[dict], right: list[dict], aspect: float) -> list[tuple[dict, dict]]:
    """Pairs that minimise the total distance (exact for small sets, greedy beyond)."""
    if len(left) > len(right):
        return [(a, b) for b, a in pair_points(right, left, aspect)]
    if len(right) <= MAX_EXACT_PAIRING:
        best = min(itertools.permutations(right, len(left)),
                   key=lambda order: sum(distance(a, b, aspect) for a, b in zip(left, order)))
        return list(zip(left, best))
    pairs, free = [], list(right)
    for a in left:
        b = min(free, key=lambda candidate: distance(a, candidate, aspect))
        free.remove(b)
        pairs.append((a, b))
    return pairs


def compare(vocab: dict, claude: dict[str, dict], codex: dict[str, dict], aspects: dict[str, float]) -> dict:
    threshold = float(vocab.get("position_threshold_pct", 5))
    disagreements = []
    for frame in sorted(claude):
        mine, theirs = claude[frame], codex[frame]
        aspect = aspects.get(frame, 1.0)
        classes = sorted(set(mine["objects"]) | set(theirs["objects"]))
        for cls in classes:
            a_count, b_count = mine["objects"].get(cls, 0), theirs["objects"].get(cls, 0)
            if a_count != b_count:
                disagreements.append({"frame": frame, "kind": "count", "class": cls,
                                      "claude": a_count, "codex": b_count})
                continue
            a_pts = [p for p in mine.get("points", []) if p["class"] == cls]
            b_pts = [p for p in theirs.get("points", []) if p["class"] == cls]
            for a, b in pair_points(a_pts, b_pts, aspect):
                gap = distance(a, b, aspect)
                if gap > threshold:
                    disagreements.append({
                        "frame": frame, "kind": "position", "class": cls,
                        "claude": [a["x_pct"], a["y_pct"]], "codex": [b["x_pct"], b["y_pct"]],
                        "distance_pct": round(gap, 2), "threshold_pct": threshold})
        for name in vocab.get("relations", {}):
            if mine["relations"][name] != theirs["relations"][name]:
                disagreements.append({"frame": frame, "kind": "relation", "relation": name,
                                      "definition": vocab["relations"][name],
                                      "claude": mine["relations"][name], "codex": theirs["relations"][name]})
    for number, item in enumerate(disagreements, 1):
        item["id"] = f"d{number}"
    disputed = {item["frame"] for item in disagreements}
    n_frames = len(claude)
    return {
        "n_frames": n_frames,
        "agreement_rate": round((n_frames - len(disputed)) / n_frames, 3) if n_frames else 0.0,
        "frames": {frame: {"agree": frame not in disputed} for frame in sorted(claude)},
        "disagreements": disagreements,
    }


def frame_aspects(path: str | None) -> dict[str, float]:
    if not path:
        return {}
    data = load_json(path)
    return {name: info["height"] / info["width"] for name, info in data.items()
            if info.get("width") and info.get("height")}


def main(argv: list[str]) -> None:
    if len(argv) >= 2 and argv[0] == "check-vocab":
        try:
            problems = vocab_problems(load_json(argv[1]))
        except (OSError, ValueError) as exc:
            fail("target_invalid", f"vocabulary unreadable: {exc}", 2)
        if problems:
            fail("target_invalid", "; ".join(problems), 2)
        print(json.dumps({"ok": True}))
        return
    if len(argv) >= 4 and argv[0] == "compare":
        frames_path = argv[argv.index("--frames") + 1] if "--frames" in argv else None
        try:
            vocab = load_json(argv[1])
        except (OSError, ValueError) as exc:
            fail("target_invalid", f"vocabulary unreadable: {exc}", 2)
        problems = vocab_problems(vocab)
        if problems:
            fail("target_invalid", "; ".join(problems), 2)
        try:
            claude = by_frame(claims_list(load_json(argv[2])), vocab)
        except (OSError, ValueError, SchemaError) as exc:
            fail("target_invalid", f"Claude claims: {exc}", 2)
        if not claude:
            fail("target_invalid", "Claude claims: no frames", 2)
        try:
            codex = by_frame(claims_list(load_json(argv[3])), vocab)
        except (OSError, ValueError, SchemaError) as exc:
            fail("parse_failed", f"Codex claims: {exc}", 3)
        if set(codex) != set(claude):
            missing = sorted(set(claude) - set(codex))
            extra = sorted(set(codex) - set(claude))
            fail("parse_failed", f"Codex claims cover other frames (missing={missing}, extra={extra})", 3)
        print(json.dumps(compare(vocab, claude, codex, frame_aspects(frames_path)), ensure_ascii=False, indent=1))
        return
    print(__doc__, file=sys.stderr)
    sys.exit(64)


if __name__ == "__main__":
    main(sys.argv[1:])
