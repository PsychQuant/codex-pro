#!/usr/bin/env python3
"""The run directory of /codex-pro:codex-visual-xval (#23): reading and writing its files, and the
checks that what a step reads is what an earlier step wrote. scripts/xval.py drives the steps.
"""
import datetime
import json
import os
import re
import struct
import subprocess
from typing import Any

import seal as sealing


class Stop(Exception):
    """record=False is for refusing a command whose step was already done (a second seal, a second
    request in one round). That is about the command, not the run, so it must not replace the run's
    error: a completed run stays completed, a rate_limit stays a rate_limit (#23 verify round 2, R6)."""
    def __init__(self, error: str, detail: str, record: bool = True, source: str = "xval",
                 records: list[str] | None = None):
        super().__init__(detail)
        # source: who wrote the detail. Only xval's own text reaches the result file; codex-call's
        # messages, the runtime check's detail, Python's exception text and SAM's output stay in the
        # run directory (#23 verify round 9). records: the ledger's records the step stopped on, so
        # the result file does not name them a second time (B4).
        self.error, self.detail, self.record, self.source = error, detail, record, source
        self.records = records or []


def load(path: str, default: Any = None) -> Any:
    if not os.path.isfile(path):   # a FIFO or a device would stall the step (#23 verify round 8, K1)
        return default
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError, RecursionError):   # nested too deep is unreadable too (round 11, F9)
        return default


def regular_or_absent(path: str) -> bool:
    """Whether `path` may be written: absent, or a regular file that is not a symlink. A FIFO would stall the
    step, and a symlink would write somewhere outside the run (#23 verify round 11, F1)."""
    return not os.path.lexists(path) or (os.path.isfile(path) and not os.path.islink(path))


def write_text(path: str, text: str, append: bool = False) -> None:
    """The one way a record, a prompt or the error history is written (#23 verify round 10, D5; round 11, F1)."""
    if not regular_or_absent(path):
        raise Stop("target_invalid", f"{os.path.basename(path)} is not a regular file; nothing was written to it")
    with open(path, "a" if append else "w", encoding="utf-8") as fh:
        fh.write(text)


def dump(path: str, data: Any) -> None:
    """Write a record, ASCII-escaped, so a lone surrogate from a reply cannot stop the write halfway (D5)."""
    write_text(path, json.dumps(data, ensure_ascii=True, indent=1))


RUN_MARK = "# copies of the images given to /codex-pro:codex-visual-xval"


def is_run_dir(run: str) -> bool:
    if not os.path.isfile(os.path.join(run, ".gitignore")):   # a FIFO there would stall every step (round 9, B2)
        return False
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


def adopt_run_dir(run: str) -> None:
    """Take over an existing empty directory as the run directory, creating none: SKILL Step 1 creates
    it, so a mistyped --run is refused instead of becoming a new directory tree (#23 verify round 6, Q1)."""
    if not os.path.isdir(run):
        raise Stop("target_invalid", f"{os.path.basename(os.path.abspath(run))} does not exist; create the run directory "
                   "first (SKILL Step 1)", record=False)
    run_dir(run)


def failure(exc: BaseException) -> str:
    """What went wrong, without local directories: an OSError names its file by name only, and a
    failed tool reports its exit status, not its command line, which holds full paths (#23 verify
    round 6, W1)."""
    if isinstance(exc, subprocess.TimeoutExpired):   # its text holds the command line (round 7, Y2)
        tool = os.path.basename(str(exc.cmd[0])) if isinstance(exc.cmd, (list, tuple)) and exc.cmd else "a tool"
        return f"{tool} timed out after {int(exc.timeout)} s"
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
    frames = load(os.path.join(run, "frames.json"), {})   # a record of another type lists nothing (round 7, Y3)
    return sorted(k for k in frames if isinstance(k, str)) if isinstance(frames, dict) else []


def safe_digest(path: str) -> str | None:
    """A file's digest, or None when it is missing: a missing file is a broken record, not a crash
    reported as the skill's own fault (#23 verify round 5, N2)."""
    if not os.path.isfile(path):   # only a regular file is read: a FIFO or a device would stall (round 7, Y3)
        return None
    try:
        return sealing.digest(path)
    except OSError:
        return None


def inside(run: str, sub: str, name: Any) -> bool:
    """Whether `name` is a plain file name that lies in the run's `sub` directory."""
    return (isinstance(name, str) and name not in ("", ".", "..") and os.path.basename(name) == name
            and os.path.dirname(os.path.realpath(os.path.join(run, sub, name))) == os.path.realpath(os.path.join(run, sub)))


# ── the ledger ──────────────────────────────────────────────────────
# Every record a step writes is entered here with its SHA-256, and every later step checks what it reads
# against it by one rule: an entry must match its file, and a record that exists must have an entry
# (#23 verify round 9, which replaced the pairwise records of earlier rounds). The list is closed.
LEDGER = "ledger.json"
TRACKED = ("vocab.json", "frames.json", "meta.json", "privacy.json", "profile.json", "error.json", "claude.json",
           "seal.json", "zoom_claude.json",
           "zoom_seal.json", "requests.json", "prompt_round1.md", "prompt_zoom.md", "codex_round1.md", "codex.json",
           "codex_zoom.md", "zoom_codex.json", "comparison.json", "zoom_plan.json", "zoom_prompt.md",
           "zoom_skipped.json", "zoom_rejected.json", "anchors.json", "sam_frames.json", "track.json", "sam.json",
           "adjudication.json")
TRACKED_DIRS = ("frames/", "hires/", "crops/")
# The only records that may exist without an entry, each until the record named beside it exists: Claude's
# answers of a round not yet sealed, and the profile Step 4.1 wrote, which becomes a record when `ask` reads it
# (#23 verify round 10, C2). The files that are not records at all are listed in the spec and design.
PENDING = {"claude.json": "seal.json", "zoom_claude.json": "zoom_seal.json", "profile.json": "requests.json"}
INPUTS = ("vocab.json", "frames.json", "meta.json", "frames/", "hires/")
ANSWERS = ("claude.json", "seal.json", "codex.json")


def ledger(run: str) -> dict:
    data = load(os.path.join(run, LEDGER), {})
    return {k: v for k, v in data.items() if isinstance(k, str) and isinstance(v, str)} if isinstance(data, dict) else {}


def expand(run: str, names: Any, entries: dict) -> list[str]:
    """Names with every file of a 'dir/' name, on disk or in the ledger (dot files are Finder's, not ours)."""
    out = []
    for name in names:
        if name.endswith("/"):
            folder = os.path.join(run, name)
            on_disk = {name + f for f in os.listdir(folder) if not f.startswith(".")} if os.path.isdir(folder) else set()
            # a key is a record only when it names a file in that directory: `frames/../../x` would lead
            # out of the run, so it is not one, and nothing outside the run is opened (round 10, D6)
            entered = {k for k in entries if k.startswith(name) and inside(run, name, k[len(name):])
                       and not k[len(name):].startswith(".")}
            out += sorted(on_disk | entered)
        else:
            out.append(name)
    return list(dict.fromkeys(out))


def enter(run: str, *names: str) -> None:
    """Record the digests of what a step has just written. When the ledger is missing or unreadable while the run
    holds other records, no new ledger is written over them: the next step would read the new one as the whole
    truth, and the evidence that it was gone would be lost (#23 verify round 11, F3)."""
    if not isinstance(load(os.path.join(run, LEDGER)), dict):
        listed = set(expand(run, names, {}))
        others = [n for n in expand(run, TRACKED + TRACKED_DIRS, {})
                  if n not in listed and safe_digest(os.path.join(run, n)) is not None]
        if others:
            raise Stop("target_invalid", f"the run's ledger ({LEDGER}) is missing or unreadable, so none of its records "
                       "can be checked; no new one is written over them")
    entries = ledger(run)
    for name in expand(run, names, entries):
        digest = safe_digest(os.path.join(run, name))
        if digest:
            entries[name] = digest
        else:
            entries.pop(name, None)
    dump(os.path.join(run, LEDGER), entries)


def snapshot(run: str, *names: str) -> dict:
    """The digests of `names` (a 'dir/' name: its files) as a step begins."""
    return {n: safe_digest(os.path.join(run, n)) for n in expand(run, names, {})}


def enter_written(run: str, before: dict, *names: str) -> None:
    """Enter what this step wrote before it stopped, and only that: the records among `names` that are new or
    changed since `before`. A record this step did not write, or one the ledger already found changed, is left as
    it is, so it stays detected (#23 verify round 11, E1, F2)."""
    written = []
    for n in expand(run, names, {}):
        digest = safe_digest(os.path.join(run, n))
        if digest is not None and digest != before.get(n):
            written.append(n)
    if written:
        enter(run, *written)


def differences(run: str, names: Any = None) -> list[tuple[str, str]]:
    """(name, how) for every record that does not match the ledger: "changed" (another digest), "removed"
    (entered, now gone) or "not entered" (there, without an entry). Each record is named once, with what is
    actually the case: a file whose entry alone was removed is not called changed (#23 verify round 9, B4)."""
    entries = ledger(run)
    names = TRACKED + TRACKED_DIRS if names is None else names
    found = []
    for name in expand(run, names, entries):
        expected, actual = entries.get(name), safe_digest(os.path.join(run, name))
        if expected == actual:
            continue
        if expected is None:
            if name in PENDING and not os.path.exists(os.path.join(run, PENDING[name])):
                continue   # not a record yet: see PENDING
            found.append((name, "not entered"))
        else:
            found.append((name, "removed" if actual is None else "changed"))
    return found


def changed(run: str, names: Any = None) -> list[str]:
    """The records that do not match the ledger, by name."""
    return [name for name, _ in differences(run, names)]


# The names xval itself writes in its directories. Any other name found there is not printed: it is text from
# outside xval, and this message reaches the result file as xval's own (#23 verify round 10, D6).
OWN_NAME = re.compile(r"(?:frames|hires)/f\d{2}\.(?:png|jpg)|crops/z\d{2}\.png")


def shown_names(group: list[str]) -> list[str]:
    """The names as printed: xval's own as they are, the others counted per directory."""
    shown = [n for n in group if n in TRACKED or OWN_NAME.fullmatch(n)]
    others: dict[str, int] = {}
    for n in group:
        if n not in shown:
            folder = n.split("/", 1)[0] + "/" if "/" in n else "the run directory"
            others[folder] = others.get(folder, 0) + 1
    return shown + [f"{k} unexpected files in {d}" if k > 1 else f"an unexpected file in {d}" for d, k in others.items()]


def describe_differences(found: list[tuple[str, str]]) -> str:
    """One clause per kind, in the order the kinds were first met, each record named once."""
    groups: dict[str, list[str]] = {}
    for name, how in found:
        groups.setdefault(how, []).append(name)
    clauses = []
    for how, group in groups.items():
        names, many = ", ".join(shown_names(group)), len(group) > 1
        if how == "not entered":
            clauses.append(f"{names} {'are' if many else 'is'} not in the run's ledger")
            continue
        verb = "changed" if how == "changed" else "were removed" if many else "was removed"
        clauses.append(f"{names} {verb} after the step that wrote {'them' if many else 'it'}")
    return "; ".join(clauses)


def explain(run: str, found: list[tuple[str, str]]) -> str:
    """What is wrong, in words: a ledger that is gone or unreadable is said as such, not as every record
    in the run being "not in the run's ledger"."""
    if not isinstance(load(os.path.join(run, LEDGER)), dict):
        return f"the run's ledger ({LEDGER}) is missing or unreadable, so none of its records can be checked"
    return describe_differences(found)


def checked(run: str, names: Any = None, then: str = "") -> None:
    """Stop when any of `names` does not match the ledger (every tracked record when names is None);
    `then` says what that means for this step, such as that nothing was sent."""
    found = differences(run, names)
    if found:
        raise Stop("target_invalid", explain(run, found) + (f"; {then}" if then else ""),
                   records=[name for name, _ in found])


def checked_inputs(run: str) -> None:
    """The vocabulary, the frames and the run's settings as init wrote them: max_count, track_point,
    sam_margin_pct, sequence and order decide verdicts (#23 verify round 5, V8; round 6, W2)."""
    checked(run, INPUTS)


def checked_comparison(run: str) -> dict:
    """The comparison and both answer files as `compare` read and wrote them (L3; round 6, W2)."""
    if not os.path.exists(os.path.join(run, "comparison.json")) and "comparison.json" not in ledger(run):
        # nothing to work on yet, which is no new failure of the run: its own error stays (round 10, D7)
        raise Stop("target_invalid", "no comparison: run `compare` first", record=False)
    checked(run, ANSWERS + ("comparison.json",))
    return load(os.path.join(run, "comparison.json"))
