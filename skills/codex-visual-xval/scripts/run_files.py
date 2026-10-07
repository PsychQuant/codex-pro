#!/usr/bin/env python3
"""The run directory of /codex-pro:codex-visual-xval (#23): reading and writing its files, and the
checks that what a step reads is what an earlier step wrote. scripts/xval.py drives the steps.
"""
import datetime
import json
import os
import struct
import subprocess
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


def failure(exc: BaseException) -> str:
    """What went wrong, without local directories: an OSError names its file by name only, and a
    failed tool reports its exit status, not its command line, which holds full paths (#23 verify
    round 6, W1)."""
    if isinstance(exc, subprocess.CalledProcessError):
        tool = os.path.basename(str(exc.cmd[0])) if isinstance(exc.cmd, (list, tuple)) and exc.cmd else "a tool"
        return f"{tool} exited {exc.returncode}"
    if isinstance(exc, OSError):
        name = f" ({os.path.basename(str(exc.filename))})" if exc.filename else ""
        return f"{exc.strerror or type(exc).__name__}{name}"
    if isinstance(exc, struct.error):
        return "malformed image data"
    return str(exc)


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
    """One digest over the vocabulary, frames.json, every frame copy (#23 verify round 2, S2) and the
    settings init recorded in meta.json, which decide whether SAM runs and in what order (round 6, W2).
    A frames.json of another shape is hashed as it is, so it reads as a changed input, not a crash (Q8)."""
    import hashlib
    h = hashlib.sha256()
    # Only the frames the run lists: a file Finder adds (.DS_Store) is not an input (round 3, L2).
    frames = load(os.path.join(run, "frames.json"), {})
    names = sorted(frames) if isinstance(frames, dict) and all(isinstance(k, str) for k in frames) else []
    hires = [frames[n]["hires"] for n in names if isinstance(frames[n], dict) and isinstance(frames[n].get("hires"), str)]
    for name in ["vocab.json", "frames.json"] + [os.path.join("frames", n) for n in names] + hires:
        h.update(name.encode() + b"\0" + (safe_digest(os.path.join(run, name)) or "missing").encode() + b"\n")
    meta = load(os.path.join(run, "meta.json"))
    settings = {k: v for k, v in meta.items() if k != "inputs_sha256"} if isinstance(meta, dict) else "missing"
    h.update(b"meta\0" + json.dumps(settings, sort_keys=True).encode() + b"\n")
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
    """The comparison as `compare` wrote it; an edited one would change what is cropped and settled (L3).
    Both answer files must still be the ones it read: crops frame their points and SAM anchors on
    them, so an edited point would move the evidence (#23 verify round 6, W2)."""
    path = os.path.join(run, "comparison.json")
    comparison = load(path)
    record = load(os.path.join(run, "comparison_record.json"), {})
    if comparison is None and not record:
        raise Stop("target_invalid", "no comparison: run `compare` first")
    if not isinstance(record, dict) or record.get("sha256") != safe_digest(path):
        raise Stop("target_invalid", "comparison.json changed after `compare` wrote it")
    for name in ("claude.json", "codex.json"):
        if record.get(name) != safe_digest(os.path.join(run, name)):
            raise Stop("target_invalid", f"{name} changed after `compare` read it")
    return comparison


def answers_changed(run: str) -> list[str]:
    """The answer files that no longer match what `compare` read; empty when nothing was compared."""
    record = load(os.path.join(run, "comparison_record.json"), {})
    if not isinstance(record, dict) or not record:
        return []
    return [n for n in ("claude.json", "codex.json") if record.get(n) != safe_digest(os.path.join(run, n))]


def zoom_record_intact(run: str, plan: dict) -> bool:
    """The plan, the question file, the crops and the comparison they came from, as `crops` wrote them."""
    record = load(os.path.join(run, "zoom_record.json"), {})
    crops = record.get("crops_sha256") or {}
    return (record.get("plan_sha256") == safe_digest(os.path.join(run, "zoom_plan.json"))
            and record.get("prompt_sha256") == safe_digest(os.path.join(run, "zoom_prompt.md"))
            and record.get("comparison_sha256") == safe_digest(os.path.join(run, "comparison.json"))
            and all(crops.get(e["crop"]) == safe_digest(os.path.join(run, e["crop"])) for e in plan.values()))
