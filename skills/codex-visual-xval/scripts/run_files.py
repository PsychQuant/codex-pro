#!/usr/bin/env python3
"""The run directory of /codex-pro:codex-visual-xval (#23): reading and writing its files, and the
checks that what a step reads is what an earlier step wrote. scripts/xval.py drives the steps.
"""
import datetime
import json
import os
from typing import Any

import seal as sealing


class Stop(Exception):
    """record=False is for refusing a command whose step was already done (a second seal, a second
    request in one round). That is about the command, not the run, so it must not replace the run's
    error: a completed run stays completed, a rate_limit stays a rate_limit (#23 verify round 2, R6)."""
    def __init__(self, error: str, detail: str, record: bool = True):
        super().__init__(detail)
        self.error, self.detail, self.record = error, detail, record


def load(path: str, default: Any = None) -> Any:
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return default


def dump(path: str, data: Any) -> None:
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=1)


RUN_MARK = "# copies of the images given to /codex-pro:codex-visual-xval"


def is_run_dir(run: str) -> bool:
    try:
        with open(os.path.join(run, ".gitignore"), encoding="utf-8") as fh:
            return fh.readline().strip() == RUN_MARK
    except OSError:
        return False


def run_dir(run: str) -> None:
    """Create the run directory, out of version control from its first file on: it holds copies of
    the user's images, and error details that name local paths. A directory that already holds
    other files is not taken over, and an existing .gitignore is never overwritten: `--run .` used to
    replace a project's own .gitignore (#23 verify round 4, U5)."""
    if os.path.isdir(run) and not is_run_dir(run) and os.listdir(run):
        raise Stop("target_invalid", f"{os.path.basename(os.path.abspath(run))} is not a run directory: it already holds "
                   "other files; use a new directory such as .codex-pro/visual-xval-run-<timestamp>", record=False)
    os.makedirs(run, exist_ok=True)
    if not os.path.exists(os.path.join(run, ".gitignore")):
        with open(os.path.join(run, ".gitignore"), "w", encoding="utf-8") as fh:
            fh.write(RUN_MARK + "\n*\n")


def now_iso() -> str:
    return datetime.datetime.now().astimezone().isoformat(timespec="seconds")


def neutral_names(run: str) -> list[str]:
    return sorted(load(os.path.join(run, "frames.json"), {}))


def safe_digest(path: str) -> str | None:
    """A file's digest, or None when it is missing: a missing file is a broken record, not a crash
    reported as the skill's own fault (#23 verify round 5, N2)."""
    try:
        return sealing.digest(path)
    except OSError:
        return None


def inputs_digest(run: str) -> str:
    """One digest over the vocabulary, frames.json and every frame copy (#23 verify round 2, S2)."""
    import hashlib
    h = hashlib.sha256()
    # Only the frames the run lists: a file Finder adds (.DS_Store) is not an input (round 3, L2).
    for name in ["vocab.json", "frames.json"] + [os.path.join("frames", n) for n in neutral_names(run)]:
        h.update(name.encode() + b"\0" + (safe_digest(os.path.join(run, name)) or "missing").encode() + b"\n")
    return h.hexdigest()


def checked_inputs(run: str) -> None:
    """Every step after sealing reads the vocabulary and the frames as sealed: max_count, track_point
    and sam_margin_pct decide verdicts (#23 verify round 5, V8)."""
    sealed = (load(os.path.join(run, "seal.json"), {}) or {}).get("inputs_sha256")
    if not sealed or sealed != inputs_digest(run):
        raise Stop("target_invalid", "the vocabulary or the image copies changed after Claude's answers were sealed")


def seal_intact(run: str, zoom: bool) -> bool:
    record = load(os.path.join(run, "zoom_seal.json" if zoom else "seal.json"))
    answers = os.path.join(run, "zoom_claude.json" if zoom else "claude.json")
    return bool(record) and os.path.isfile(answers) and record.get("sha256") == sealing.digest(answers)


def checked_comparison(run: str) -> dict:
    """The comparison as `compare` wrote it; an edited one would change what is cropped and settled (L3)."""
    path = os.path.join(run, "comparison.json")
    comparison = load(path)
    if comparison is None:
        raise Stop("target_invalid", "no comparison: run `compare` first")
    if load(os.path.join(run, "comparison_record.json"), {}).get("sha256") != sealing.digest(path):
        raise Stop("target_invalid", "comparison.json changed after `compare` wrote it")
    return comparison


def zoom_record_intact(run: str, plan: dict) -> bool:
    """The plan, the question file, the crops and the comparison they came from, as `crops` wrote them."""
    record = load(os.path.join(run, "zoom_record.json"), {})
    crops = record.get("crops_sha256") or {}
    return (record.get("plan_sha256") == safe_digest(os.path.join(run, "zoom_plan.json"))
            and record.get("prompt_sha256") == safe_digest(os.path.join(run, "zoom_prompt.md"))
            and record.get("comparison_sha256") == safe_digest(os.path.join(run, "comparison.json"))
            and all(crops.get(e["crop"]) == safe_digest(os.path.join(run, e["crop"])) for e in plan.values()))
