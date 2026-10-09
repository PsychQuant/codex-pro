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
import tempfile
from typing import Any

import seal as sealing


class Stop(Exception):
    """record=False is for refusing a command whose step was already done (a second seal, a second
    request in one round). That is about the command, not the run, so it must not replace the run's
    error: a completed run stays completed, a rate_limit stays a rate_limit (#23 verify round 2, R6)."""
    def __init__(self, error: str, detail: str, record: bool = True, source: str = "xval",
                 records: list[str] | None = None, step: str | None = None):
        super().__init__(detail)
        # source: who wrote the detail. Only xval's own text reaches the result file; codex-call's
        # messages, the runtime check's detail, Python's exception text and SAM's output stay in the
        # run directory (#23 verify round 9). records: the ledger's records the step stopped on, so
        # the result file does not name them a second time (B4). step: the step the error belongs to
        # when it is not the command's own, as for an init that did not complete (round 12, G2).
        self.error, self.detail, self.record, self.source = error, detail, record, source
        self.records, self.step = records or [], step


def load(path: str, default: Any = None) -> Any:
    if not os.path.isfile(path):   # a FIFO or a device would stall the step (#23 verify round 8, K1)
        return default
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError, RecursionError):   # nested too deep is unreadable too (round 11, F9)
        return default


# ── the one write entry ─────────────────────────────────────────────
# Every file xval writes goes through write_bytes (#23 verify round 12, H1). The paths it wrote during the
# current step are noted here, so the step enters exactly those (G3); None outside a step.
_written: list[str] | None = None
_UMASK = os.umask(0)
os.umask(_UMASK)


def _where(folder: str) -> str:
    """A directory by role: one of the run's own by name, any other as 'the directory' (round 11, F5)."""
    name = os.path.basename(folder.rstrip("/"))
    return f"{name}/" if name in ("frames", "hires", "crops") else "the directory"


def write_bytes(path: str, data: bytes, refuse_links: bool = False) -> None:
    """The one way xval writes a file: to a new temporary file in the same directory, then moved over the name.
    A symbolic link, a hard link or a FIFO at the name is replaced and never written through, and no check is made
    before an open that could change in between. A directory that is itself a symbolic link is not written into
    (#23 verify round 12, H1). `refuse_links` is for the result file at --out, the user's own path: a link or
    anything but a regular file there is refused rather than replaced."""
    folder = os.path.dirname(os.path.abspath(path))
    # the run's own directories only: --out's folder is the user's, reached as the user chose (round 13, J3)
    if not refuse_links and os.path.islink(folder):
        raise Stop("target_invalid", f"{_where(folder)} is a symbolic link; nothing was written into it")
    if refuse_links and os.path.lexists(path) and (os.path.islink(path) or not os.path.isfile(path)):
        raise OSError(0, "not a regular file")
    if os.path.isdir(path) and not os.path.islink(path):
        raise Stop("target_invalid", f"{os.path.basename(path)} is a directory; nothing was written to it")
    fd, tmp = tempfile.mkstemp(dir=folder, prefix=".xval-", suffix=".tmp")
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
        os.chmod(tmp, 0o666 & ~_UMASK)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    if _written is not None:
        _written.append(os.path.abspath(path))


def scratch(folder: str, suffix: str) -> str:
    """A new, empty temporary file in `folder` for a tool such as sips to write into; the caller removes it. Its
    name begins with a dot, so it is never a record (round 12, H1)."""
    if os.path.islink(folder):
        raise Stop("target_invalid", f"{_where(folder)} is a symbolic link; nothing was written into it")
    fd, tmp = tempfile.mkstemp(dir=folder, prefix=".xval-", suffix=suffix)
    os.close(fd)
    return tmp


def write_text(path: str, text: str) -> None:
    write_bytes(path, text.encode("utf-8", "replace"))


def append_text(path: str, text: str) -> None:
    """The error history: rewritten whole with the new line, so a hard link out of the run is detached, not written
    through. A history that is not a regular file is skipped, not waited on (round 11, F1; round 12, H1)."""
    if os.path.lexists(path) and (os.path.islink(path) or not os.path.isfile(path)):
        return
    old = b""
    if os.path.isfile(path):
        with open(path, "rb") as fh:
            old = fh.read()
    write_bytes(path, old + text.encode("utf-8", "replace"))


def remove(path: str) -> None:
    """Remove a record xval wrote, noted like a write, so the step takes its entry out too (round 12, G3)."""
    os.remove(path)
    if _written is not None:
        _written.append(os.path.abspath(path))


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
        raise Stop("target_invalid", "the --run directory is not a run directory: it already holds other files; use a "
                   "new directory such as .codex-pro/visual-xval-run-<timestamp>", record=False)   # F5: by role
    os.makedirs(run, exist_ok=True)
    if not os.path.lexists(os.path.join(run, ".gitignore")):
        write_text(os.path.join(run, ".gitignore"), RUN_MARK + "\n*\n")


def adopt_run_dir(run: str) -> None:
    """Take over an existing empty directory as the run directory, creating none: SKILL Step 1 creates
    it, so a mistyped --run is refused instead of becoming a new directory tree (#23 verify round 6, Q1)."""
    if not os.path.isdir(run):
        raise Stop("target_invalid", "the --run directory does not exist; create it first (SKILL Step 1)",
                   record=False)   # F5: by role
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
TRACKED = ("vocab.json", "frames.json", "meta.json", "init_attempt.json", "privacy.json", "profile.json", "error.json",
           "claude.json",
           "seal.json", "zoom_claude.json",
           "zoom_seal.json", "requests.json", "prompt_round1.md", "prompt_zoom.md", "codex_round1.md", "codex.json",
           "codex_zoom.md", "zoom_codex.json", "comparison.json", "zoom_plan.json", "zoom_prompt.md",
           "zoom_skipped.json", "zoom_rejected.json", "anchors.json", "sam_frames.json", "track.json", "sam.json",
           "adjudication.json")
TRACKED_DIRS = ("frames/", "hires/", "crops/")
# The only records that may exist without an entry, each until the record named beside it exists: Claude's
# answers of a round not yet sealed, and the profile Step 4.1 wrote, which becomes a record when the first request
# is recorded (#23 verify round 10, C2; round 11, F6). The files that are not records are listed in the spec.
PENDING = {"claude.json": "seal.json", "zoom_claude.json": "zoom_seal.json",
           "profile.json": "requests.json"}   # the profile: pending until a request is recorded in it (see pending())
INPUTS = ("vocab.json", "frames.json", "meta.json", "frames/", "hires/")
ANSWERS = ("claude.json", "seal.json", "codex.json")


def lies_inside(folder: str, run: str) -> bool:
    """Whether `folder` is the run directory or lies below it, judged by device and inode rather than by spelling,
    so a case variant, a firmlink or a symbolic link followed by '..' is still the same directory (round 14, L2)."""
    try:
        target = os.stat(run)
    except OSError:
        return False
    path = os.path.realpath(folder)
    while True:
        try:
            if os.path.samestat(os.stat(path), target):
                return True
        except OSError:
            pass
        parent = os.path.dirname(path)
        if parent == path:
            return False
        path = parent


def requested(run: str) -> bool:
    """Whether a request is recorded in the run: a withdrawn one leaves requests.json without it (round 13, J2)."""
    requests = load(os.path.join(run, "requests.json"), {})
    return isinstance(requests, dict) and any(isinstance(r, dict) and r.get("requested_at") for r in requests.values())


def pending(run: str, name: str) -> bool:
    """Whether a record of PENDING may still be without an entry: Claude's answers until their seal exists, the
    profile until a request is recorded."""
    if name == "profile.json":
        return not requested(run)
    return not os.path.exists(os.path.join(run, PENDING[name]))


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


def ledger_usable(run: str, *writing: str) -> bool:
    """Whether the ledger can take entries: it is readable, or the run holds no record but `writing`. A ledger
    that is missing or unreadable while the run holds other records is not written over: the next step would read
    the new one as the whole truth, and the evidence that it was gone would be lost (#23 verify round 11, F3)."""
    if isinstance(load(os.path.join(run, LEDGER)), dict):
        return True
    listed = set(expand(run, writing, {}))
    return not [n for n in expand(run, TRACKED + TRACKED_DIRS, {})
                if n not in listed and safe_digest(os.path.join(run, n)) is not None]


def enter(run: str, *names: str, digests: dict | None = None) -> None:
    """Record the digests of what a step has just written; a name whose file is gone loses its entry. Only Step
    calls this, and tests that write a record by hand (#23 verify round 12, G3)."""
    if not ledger_usable(run, *names):
        raise Stop("target_invalid", f"the run's ledger ({LEDGER}) is missing or unreadable, so none of its records "
                   "can be checked; no new one is written over them")
    entries = ledger(run)
    for name in expand(run, names, entries):
        digest = (digests or {}).get(name) or safe_digest(os.path.join(run, name))
        if digest:
            entries[name] = digest
        else:
            entries.pop(name, None)
    dump(os.path.join(run, LEDGER), entries)


def is_record(name: str) -> bool:
    """A name the ledger tracks: one of TRACKED, or a file in one of TRACKED_DIRS whose name does not begin with
    a dot (a dot file, xval's own temporary ones among them, is not a record)."""
    if name in TRACKED:
        return True
    folder, _, base = name.partition("/")
    return f"{folder}/" in TRACKED_DIRS and bool(base) and "/" not in base and not base.startswith(".")


class Step:
    """The one entry to the ledger (#23 verify round 12, G3). A step enters what it wrote itself: the records it
    wrote or removed through the write entry, and the file the program it ran wrote for it (`expect`), when that
    file is new or changed since the step declared it. A record the step did not write keeps its entry as it was,
    or stays without one, so the ledger keeps detecting it. commit() enters what was written so far: a step that
    sends a request commits first, and every step commits as it ends, also when it fails or is interrupted. The
    two records that may exist without an entry are entered by `adopt`, and only while they have none."""

    def __init__(self, run: str, enters: bool = True):
        global _written
        self.run, self.outputs, self.pending, self.enters, self.adopted = run, {}, {}, enters, set()
        _written = []   # `enters=False`: the result step, which writes outside the run and enters nothing (round 13, J1)

    def expect(self, name: str) -> None:
        """A file that a program this step runs (codex-call, SAM) writes: entered when new or changed since now."""
        self.outputs[name] = safe_digest(os.path.join(self.run, name))

    def adopt(self, name: str, digest: str | None = None) -> None:
        """A record the step did not write but makes a record now: Claude's answers when sealed, the profile when a
        request is first recorded, with the digest of the bytes the step read (round 12, H6; round 14, L5)."""
        if name not in PENDING:
            raise ValueError(f"{name} is not one of the records that may exist without an entry")
        self.pending[name] = digest

    def release(self, name: str) -> None:
        """Take back an entry this step adopted, as when the request the profile was entered for is withdrawn because
        codex-call could not start: the profile is pending again (round 13, J2)."""
        if name in self.adopted:
            entries = ledger(self.run)
            if entries.pop(name, None) is not None:
                dump(os.path.join(self.run, LEDGER), entries)
            self.adopted.discard(name)

    def commit(self) -> None:
        global _written
        if not self.enters:
            _written = []
            return
        run = os.path.abspath(self.run)
        names = []
        for path in list(_written or []):
            name = os.path.relpath(path, run)
            if is_record(name) and name not in PENDING:   # Claude's answers and the profile only by adopt
                names.append(name)
        for name, before in self.outputs.items():
            now = safe_digest(os.path.join(self.run, name))
            if now is not None and now != before:
                names.append(name)
        names = list(dict.fromkeys(names))
        entries = ledger(self.run) if self.pending else {}
        adopted = {n: d or safe_digest(os.path.join(self.run, n)) for n, d in self.pending.items() if n not in entries}
        adopted = {n: d for n, d in adopted.items() if d}
        if names or adopted:
            enter(self.run, *names, *adopted, digests=adopted)
        self.adopted |= set(adopted)
        _written = []
        self.outputs = {n: safe_digest(os.path.join(self.run, n)) for n in self.outputs}
        self.pending = {}


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
            if name in PENDING and pending(run, name):
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


def initialised(run: str) -> None:
    """Every step but init, confirm-privacy and result needs init to have completed (#23 verify round 12, G2).
    Before any attempt it cannot be done yet, which keeps the run's own error; after an attempt that did not
    complete the run is used up, and that is init's error."""
    if not isinstance(load(os.path.join(run, LEDGER)), dict):
        checked(run, INPUTS)   # a ledger that is gone is said as such, not as an init that did not complete
    entries = ledger(run)
    if not (os.path.lexists(os.path.join(run, "init_attempt.json")) or "init_attempt.json" in entries):
        raise Stop("target_invalid", "the run is not initialised yet: run `init` first", record=False)
    if "meta.json" not in entries:
        raise Stop("target_invalid", "init did not complete in this run, so the run is used up; start a new run",
                   step="init")


ROUND_STEP = re.compile(r"ask --round (1|zoom)")


def uses_up(run: str, step: str) -> bool:
    """Whether an error recorded now at `step` can never be resolved: init's once its attempt is recorded (a run
    is initialised once), a round's once its request is recorded (a round is asked once). Decided when the error is
    recorded and kept in it as `used_up`, never inferred later from the run's records: a request recorded after an
    error from before it does not make that error used up (#23 verify round 12, G1; round 13, I1)."""
    if step == "init":
        return os.path.lexists(os.path.join(run, "init_attempt.json")) or "init_attempt.json" in ledger(run)
    match = ROUND_STEP.fullmatch(step) if isinstance(step, str) else None
    if not match:
        return False
    if differences(run, ("requests.json",)):
        return True   # it cannot be told whether the round was asked: kept, so nothing is lost
    requests = load(os.path.join(run, "requests.json"), {})
    asked = requests.get(match.group(1)) if isinstance(requests, dict) else None
    return isinstance(asked, dict) and bool(asked.get("requested_at"))


def keeps_error(run: str) -> bool:
    """Whether the run's error stays as it is when another step stops or completes: it does not match the ledger,
    so it stays detected (round 11, E1), or it was recorded as using up the run or its round (round 13, I1)."""
    if differences(run, ("error.json",)):
        return True
    current = load(os.path.join(run, "error.json"))
    return isinstance(current, dict) and current.get("used_up") is True


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
