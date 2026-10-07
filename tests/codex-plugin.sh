#!/usr/bin/env bash
# tests/codex-plugin.sh — Codex native plugin static contract.
#
# This layer intentionally owns only package metadata and safe-path checks.
# Runtime behaviour and full-bundle parity are exercised by their dedicated
# layers so a failure here identifies a distribution-contract problem.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"

EXPECTED_NAME="codex-pro"
EXPECTED_VERSION="0.8.0"

if ! command -v python3 >/dev/null 2>&1; then
  echo "FATAL: python3 not on PATH (required for JSON contract checks)" >&2
  exit 2
fi

# The Python checker emits tab-delimited assertion records. Keeping JSON and
# path normalization in one process avoids jq as a test dependency while the
# shell remains responsible for the shared pass/fail accounting and summary.
contract_output=$(python3 - "$REPO_ROOT" "$EXPECTED_NAME" "$EXPECTED_VERSION" <<'PY' 2>&1
from __future__ import annotations

import json
import re
import sys
from pathlib import Path, PurePosixPath
from urllib.parse import urlparse

repo_root = Path(sys.argv[1]).resolve()
expected_name = sys.argv[2]
expected_version = sys.argv[3]
native_manifest_path = repo_root / ".codex-plugin" / "plugin.json"
marketplace_path = repo_root / ".agents" / "plugins" / "marketplace.json"
skills_manifest_path = repo_root / "scripts" / "codex-skills.manifest"
resource_manifest_path = repo_root / "scripts" / "codex-bundle-resources.manifest"
claude_plugin_root = repo_root / "plugins" / expected_name
semver_re = re.compile(
    r"^(0|[1-9]\d*)\."
    r"(0|[1-9]\d*)\."
    r"(0|[1-9]\d*)"
    r"(?:-(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)(?:\."
    r"(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*))*)?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$"
)


def emit(ok: bool, message: str, detail: str | None = None) -> None:
    if detail and not ok:
        message = f"{message} ({detail})"
    print(("PASS" if ok else "FAIL") + "\t" + message)


def load_object(path: Path, label: str) -> dict | None:
    if not path.is_file():
        emit(False, f"{label} exists", f"missing: {path.relative_to(repo_root)}")
        return None
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        emit(False, f"{label} contains valid JSON", str(exc))
        return None
    if not isinstance(payload, dict):
        emit(False, f"{label} contains a JSON object", f"actual={type(payload).__name__}")
        return None
    emit(True, f"{label} exists and contains a JSON object")
    return payload


def non_empty_string(value: object) -> bool:
    return isinstance(value, str) and bool(value.strip())


def nested(payload: object, *keys: object) -> object:
    current = payload
    for key in keys:
        if isinstance(key, int):
            if not isinstance(current, list) or key >= len(current):
                return None
            current = current[key]
        else:
            if not isinstance(current, dict):
                return None
            current = current.get(key)
    return current


def path_is_within(root: Path, candidate: Path) -> bool:
    try:
        candidate.relative_to(root)
    except ValueError:
        return False
    return True


def check_package_path(raw: object, field: str, *, require_directory: bool = False) -> Path | None:
    if not isinstance(raw, str) or not raw.startswith("./"):
        emit(False, f"{field} is a package-relative ./ path", f"actual={raw!r}")
        return None
    posix_path = PurePosixPath(raw)
    if posix_path.is_absolute() or ".." in posix_path.parts:
        emit(False, f"{field} remains inside the plugin root", f"actual={raw!r}")
        return None
    resolved = (repo_root / posix_path).resolve()
    if not path_is_within(repo_root, resolved):
        emit(False, f"{field} remains inside the plugin root", f"resolved={resolved}")
        return None
    emit(True, f"{field} remains inside the plugin root")
    exists = resolved.is_dir() if require_directory else resolved.exists()
    expected_kind = "directory" if require_directory else "path"
    emit(exists, f"{field} resolves to an existing {expected_kind}", f"resolved={resolved}")
    return resolved if exists else None


native = load_object(native_manifest_path, ".codex-plugin/plugin.json")
native_skills_root: Path | None = None
if native is not None:
    emit(native.get("name") == expected_name, "plugin.json name == codex-pro", f"actual={native.get('name')!r}")
    version = native.get("version")
    emit(isinstance(version, str) and semver_re.fullmatch(version) is not None,
         "plugin.json version uses strict SemVer", f"actual={version!r}")
    emit(non_empty_string(native.get("description")), "plugin.json description is non-empty")
    emit(non_empty_string(nested(native, "author", "name")), "plugin.json author.name is non-empty")

    skills_path = native.get("skills")
    emit(skills_path == "./skills/", "plugin.json skills == ./skills/", f"actual={skills_path!r}")
    native_skills_root = check_package_path(skills_path, "plugin.json skills", require_directory=True)

    for unsupported in ("apps", "mcpServers", "hooks"):
        emit(unsupported not in native, f"plugin.json omits unsupported {unsupported}")

    interface = native.get("interface")
    emit(isinstance(interface, dict), "plugin.json interface is an object")
    if isinstance(interface, dict):
        for field in (
            "displayName",
            "shortDescription",
            "longDescription",
            "developerName",
        ):
            emit(non_empty_string(interface.get(field)), f"plugin.json interface.{field} is non-empty")
        emit(interface.get("category") == "Developer Tools",
             "plugin.json interface.category == Developer Tools",
             f"actual={interface.get('category')!r}")
        capabilities = interface.get("capabilities")
        emit(
            isinstance(capabilities, list)
            and len(capabilities) >= 1
            and all(non_empty_string(value) for value in capabilities),
            "plugin.json interface.capabilities is a non-empty string array",
        )
        website = interface.get("websiteURL")
        parsed_website = urlparse(website) if isinstance(website, str) else None
        emit(
            parsed_website is not None
            and parsed_website.scheme == "https"
            and bool(parsed_website.netloc),
            "plugin.json interface.websiteURL is an absolute HTTPS URL",
            f"actual={website!r}",
        )
        prompts = interface.get("defaultPrompt")
        emit(
            isinstance(prompts, list)
            and 1 <= len(prompts) <= 3
            and all(non_empty_string(prompt) and len(prompt) <= 128 for prompt in prompts),
            "plugin.json interface.defaultPrompt contains one to three prompts of at most 128 characters",
        )

        # D6 intentionally ships without custom visual assets or brand colour.
        for field in ("brandColor", "composerIcon", "logo", "logoDark", "screenshots"):
            emit(field not in interface, f"plugin.json interface omits optional {field}")

        # If an implementation introduces a path despite the minimal-metadata
        # assertion, still report whether that path escapes or is missing.
        for field in ("composerIcon", "logo", "logoDark"):
            if field in interface:
                check_package_path(interface[field], f"plugin.json interface.{field}")
        screenshots = interface.get("screenshots")
        if isinstance(screenshots, list):
            for index, screenshot in enumerate(screenshots):
                check_package_path(screenshot, f"plugin.json interface.screenshots[{index}]")

    if native_skills_root is not None:
        expected_skills = sorted(
            line.strip()
            for line in skills_manifest_path.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        )
        actual_skills = sorted(
            path.name
            for path in native_skills_root.iterdir()
            if path.is_dir() and (path / "SKILL.md").is_file()
        )
        emit(
            len(expected_skills) == 10,
            "scripts/codex-skills.manifest declares exactly ten skills",
            f"actual={len(expected_skills)}",
        )
        emit(
            actual_skills == expected_skills,
            "plugin.json skills path contains exactly the manifest-listed skills",
            f"expected={expected_skills!r}, actual={actual_skills!r}",
        )


marketplace = load_object(marketplace_path, ".agents/plugins/marketplace.json")
if marketplace is not None:
    emit(marketplace.get("name") == expected_name,
         "marketplace.json name == codex-pro", f"actual={marketplace.get('name')!r}")
    plugins = marketplace.get("plugins")
    emit(isinstance(plugins, list) and len(plugins) == 1,
         "marketplace.json contains exactly one plugin entry")
    entry = plugins[0] if isinstance(plugins, list) and len(plugins) == 1 and isinstance(plugins[0], dict) else None
    emit(entry is not None, "marketplace.json plugin entry is an object")
    if entry is not None:
        emit(entry.get("name") == expected_name,
             "marketplace plugin name == codex-pro", f"actual={entry.get('name')!r}")
        source = entry.get("source")
        expected_source = {"source": "local", "path": "./"}
        emit(source == expected_source,
             "marketplace plugin source is local repository root ./", f"actual={source!r}")
        source_root = None
        if isinstance(source, dict):
            source_root = check_package_path(source.get("path"), "marketplace plugin source.path", require_directory=True)
        if source_root is not None:
            source_manifest = source_root / ".codex-plugin" / "plugin.json"
            emit(source_manifest.is_file(),
                 "marketplace source contains .codex-plugin/plugin.json",
                 f"missing={source_manifest}")
        policy = entry.get("policy")
        emit(isinstance(policy, dict), "marketplace plugin policy is an object")
        if isinstance(policy, dict):
            emit(policy.get("installation") == "AVAILABLE",
                 "marketplace policy.installation == AVAILABLE",
                 f"actual={policy.get('installation')!r}")
            emit(policy.get("authentication") == "ON_INSTALL",
                 "marketplace policy.authentication == ON_INSTALL",
                 f"actual={policy.get('authentication')!r}")
        emit(entry.get("category") == "Developer Tools",
             "marketplace plugin category == Developer Tools",
             f"actual={entry.get('category')!r}")


claude_manifest = load_object(
    repo_root / "plugins" / expected_name / ".claude-plugin" / "plugin.json",
    "plugins/codex-pro/.claude-plugin/plugin.json",
)
claude_marketplace = load_object(
    repo_root / ".claude-plugin" / "marketplace.json",
    ".claude-plugin/marketplace.json",
)

versions = [
    (".codex-plugin/plugin.json", nested(native, "version") if native is not None else None),
    (
        "plugins/codex-pro/.claude-plugin/plugin.json",
        nested(claude_manifest, "version") if claude_manifest is not None else None,
    ),
    (
        ".claude-plugin/marketplace.json plugins[0]",
        nested(claude_marketplace, "plugins", 0, "version") if claude_marketplace is not None else None,
    ),
]
for label, version in versions:
    emit(version == expected_version,
         f"{label} version == {expected_version}", f"actual={version!r}")
emit(
    all(version is not None for _, version in versions)
    and len({version for _, version in versions}) == 1,
    "all three published manifest versions are identical",
    f"actual={dict(versions)!r}",
)

# Claude Code automatically exposes a plugin root's bin/ directory on Bash
# PATH.  The native-only runtime sources therefore live under runtime/ and
# are mapped to bin/ only when the Codex bundles are generated.
for executable in ("codex-call", "codex-pro-call"):
    auto_path_path = claude_plugin_root / "bin" / executable
    emit(
        not auto_path_path.exists() and not auto_path_path.is_symlink(),
        f"Claude source plugin omits auto-PATH bin/{executable}",
        f"present={auto_path_path.relative_to(repo_root)}",
    )

resource_mappings: set[tuple[str, str]] = set()
mapping_errors: list[str] = []
try:
    manifest_lines = resource_manifest_path.read_text(encoding="utf-8").splitlines()
except OSError as exc:
    mapping_errors.append(str(exc))
else:
    for number, raw in enumerate(manifest_lines, 1):
        value = raw.split("#", 1)[0].strip()
        if not value:
            continue
        fields = value.split()
        if len(fields) == 1:
            source = publish = fields[0]
        elif len(fields) == 2:
            source, publish = fields
        else:
            mapping_errors.append(
                f"line {number}: expected '<source> [publish]', got {value!r}"
            )
            continue
        resource_mappings.add((source, publish))

emit(
    not mapping_errors,
    "resource manifest source-to-publish mappings are parseable",
    "; ".join(mapping_errors),
)
for source, publish in (
    ("runtime/codex-call", "bin/codex-call"),
    ("runtime/codex-pro-call", "bin/codex-pro-call"),
):
    emit(
        (source, publish) in resource_mappings,
        f"resource manifest maps {source} to native {publish}",
        f"actual={sorted(resource_mappings)!r}",
    )


def load_text(path: Path, label: str) -> str:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        emit(False, f"{label} exists and is readable", str(exc))
        return ""
    emit(bool(text.strip()), f"{label} exists and is non-empty")
    return text


repository_license = load_text(repo_root / "LICENSE", "repository LICENSE")
claude_package_license = load_text(
    claude_plugin_root / "LICENSE",
    "Claude package LICENSE",
)
claude_package_notices = load_text(
    claude_plugin_root / "THIRD_PARTY_NOTICES.md",
    "Claude package third-party notices",
)
emit(
    bool(repository_license) and claude_package_license == repository_license,
    "Claude package carries the complete repository MIT license text",
)
# The pinned commit comes from the provenance record, the single source of truth (#23).
pinned_commit = json.loads(
    load_text(claude_plugin_root / "references" / "codex-call-provenance.json", "runtime provenance")
    or "{}"
).get("commit") or "MISSING-PROVENANCE-COMMIT"
missing_notice_tokens = [
    token
    for token in (
        "runtime/codex-call",
        pinned_commit,
        "Copyright (c) 2026 Che Cheng",
        "[LICENSE](LICENSE)",
    )
    if token not in claude_package_notices
]
emit(
    not missing_notice_tokens,
    "Claude package notices identify the vendored runtime and local MIT text",
    f"missing={missing_notice_tokens!r}",
)


documentation = {
    "README.md": load_text(repo_root / "README.md", "README.md"),
    "AGENTS.md": load_text(repo_root / "AGENTS.md", "AGENTS.md"),
    "CHANGELOG.md": load_text(repo_root / "CHANGELOG.md", "CHANGELOG.md"),
    "profile contract": load_text(
        repo_root / "plugins" / expected_name / "references" / "profile-contract.md",
        "profile contract",
    ),
    "Codex installation e2e checklist": load_text(
        repo_root / "tests" / "e2e-checklist.md",
        "Codex installation e2e checklist",
    ),
}

required_tokens = {
    "README.md": (
        "codex plugin marketplace add PsychQuant/codex-pro",
        "codex plugin marketplace upgrade codex-pro",
        "codex plugin remove codex-pro@codex-pro",
        "macOS",
        "swift",
        "~/.codex/auth.json",
        "auth.openai.com/oauth/token",
        "chatgpt.com/backend-api/codex/responses",
        "parallel-ai-agents#28",
        "parallel-ai-agents#35",
        "官方 plugin directory",
        "$codex-status",
    ),
    "AGENTS.md": (
        "plugins/codex-pro/skills/<name>/SKILL.md",
        ".codex/skills/<name>/SKILL.md",
        "skills/<name>/SKILL.md",
        "scripts/generate-codex-skills.sh",
        "Consumer",
    ),
    "CHANGELOG.md": (
        "## 0.8.0",
        "Issue: [#10]",
        "self-hosted repository marketplace",
        "已知限制",
    ),
    "profile contract": (
        "SKILL_DIR",
        "BUNDLE_ROOT",
        "codex-call-provenance.json",
        "不得掃描版本 cache",
    ),
    "Codex installation e2e checklist": (
        "CODEX_PRO_E2E_WORKDIR",
        "codex plugin marketplace list --json",
        "codex plugin add",
        "新 Codex",
        "$codex-setup",
        "$codex-config",
        "$codex-review",
        "command -v codex-call",
        ".codex-pro/review-*.md",
        "marketplace upgrade",
        "plugin remove",
        "Codex App",
        "十個 skill",
        "獨立 macOS 登入帳號或 disposable VM",
        "不讀 `CODEX_HOME`",
        "完全結束並重啟 Codex App",
    ),
}

for label, tokens in required_tokens.items():
    text = documentation[label]
    normalized_text = re.sub(r"\s+", " ", text)
    missing = [
        token
        for token in tokens
        if re.sub(r"\s+", " ", token) not in normalized_text
    ]
    emit(
        not missing,
        f"{label} covers the native distribution documentation contract",
        f"missing={missing!r}",
    )

profile_text = documentation["profile contract"]
emit(
    "ls -d ~/.claude/plugins/cache" not in profile_text,
    "profile contract does not scan a Claude version cache",
)

documentation_paths = {
    "README.md": repo_root / "README.md",
    "AGENTS.md": repo_root / "AGENTS.md",
    "CHANGELOG.md": repo_root / "CHANGELOG.md",
    "profile contract": repo_root / "plugins" / expected_name / "references" / "profile-contract.md",
    "Codex installation e2e checklist": repo_root / "tests" / "e2e-checklist.md",
}
markdown_link_re = re.compile(r"(?<!!)\[[^\]]+\]\(([^)]+)\)")
for label, path in documentation_paths.items():
    broken: list[str] = []
    for match in markdown_link_re.finditer(documentation[label]):
        target = match.group(1).strip()
        if target.startswith("<") and target.endswith(">"):
            target = target[1:-1]
        target = target.split(maxsplit=1)[0]
        parsed = urlparse(target)
        if parsed.scheme or parsed.netloc or target.startswith("#"):
            continue
        relative_path = parsed.path
        if not relative_path:
            continue
        candidate = (path.parent / relative_path).resolve()
        if not candidate.exists():
            broken.append(target)
    emit(
        not broken,
        f"{label} relative Markdown links resolve",
        f"broken={broken!r}",
    )
PY
)
contract_exit=$?

if [ "$contract_exit" -ne 0 ]; then
  fail "native plugin JSON contract checker completed (exit=$contract_exit)"
  printf '%s\n' "$contract_output" >&2
else
  while IFS=$'\t' read -r outcome message; do
    [ -n "$outcome" ] || continue
    case "$outcome" in
      PASS) pass "$message" ;;
      FAIL) fail "$message" ;;
      *) fail "native plugin JSON contract checker emitted an invalid record: $outcome $message" ;;
    esac
  done <<< "$contract_output"
fi

# The native package targets the macOS/Xcode toolchain, whose system Python is
# still 3.9 on supported hosts.  Execute the exact embedded checker with that
# interpreter so newer developer Pythons cannot hide annotation incompatibility.
checker_source=$(python3 - "$0" <<'PY_SOURCE'
import sys
from pathlib import Path

script = Path(sys.argv[1]).read_text(encoding="utf-8")
start_marker = "contract_output=$(python3 - \"$REPO_ROOT\" \"$EXPECTED_NAME\" \"$EXPECTED_VERSION\" <<'PY' 2>&1\n"
start = script.find(start_marker)
if start < 0:
    raise SystemExit("embedded contract checker start marker not found")
start += len(start_marker)
end = script.find("\nPY\n)", start)
if end < 0:
    raise SystemExit("embedded contract checker end marker not found")
sys.stdout.write(script[start:end])
PY_SOURCE
)
checker_source_exit=$?

if [ "$checker_source_exit" -ne 0 ] || [ -z "$checker_source" ]; then
  fail "embedded native plugin checker source is extractable"
else
  pass "embedded native plugin checker source is extractable"

  if printf '%s\n' "$checker_source" | grep -Fq ' | None' \
    && ! printf '%s\n' "$checker_source" | grep -Fxq 'from __future__ import annotations'; then
    fail "embedded native plugin checker defers PEP 604 annotations for Python 3.9"
  else
    pass "embedded native plugin checker defers PEP 604 annotations for Python 3.9"
  fi

  system_python="${CODEX_MACOS_SYSTEM_PYTHON:-/usr/bin/python3}"
  if [ ! -x "$system_python" ]; then
    fail "macOS system Python is available for native checker compatibility (checked: $system_python)"
  else
    compatibility_output=$(printf '%s\n' "$checker_source" \
      | "$system_python" - "$REPO_ROOT" "$EXPECTED_NAME" "$EXPECTED_VERSION" 2>&1)
    compatibility_exit=$?
    if [ "$compatibility_exit" -eq 0 ]; then
      pass "macOS system Python executes the native plugin checker"
    else
      compatibility_reason=$(printf '%s\n' "$compatibility_output" | head -n 1)
      fail "macOS system Python executes the native plugin checker (exit=$compatibility_exit: $compatibility_reason)"
    fi
  fi
fi

# Resolve the bundled plugin-creator validator without embedding a maintainer's
# absolute home path. Tests may pin another current validator through the
# explicit environment override when Codex stores system skills elsewhere.
validator_path="${CODEX_PLUGIN_CREATOR_VALIDATOR:-${CODEX_HOME:-$HOME/.codex}/skills/.system/plugin-creator/scripts/validate_plugin.py}"
if [ ! -r "$validator_path" ]; then
  fail "current plugin-creator validator is available (checked: $validator_path)"
else
  validator_output=$(python3 "$validator_path" "$REPO_ROOT" 2>&1)
  validator_exit=$?
  if [ "$validator_exit" -eq 0 ]; then
    pass "current plugin-creator validator accepts the native package"
  else
    validator_reason=$(printf '%s\n' "$validator_output" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    fail "current plugin-creator validator accepts the native package (exit=$validator_exit: $validator_reason)"
  fi
fi

report_summary "codex-plugin"
exit_code=$?
exit "$exit_code"
