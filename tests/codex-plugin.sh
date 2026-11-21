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
EXPECTED_VERSION="0.11.0"

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
        "## 0.11.0",
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

# Release gate: the repository-local schema check pinned to the upstream
# plugin-creator `plugin-json-spec.md` (#24). The Codex plugin-creator
# validator is no longer consulted: Codex CLI stopped shipping it, and it never
# appeared in the upstream openai/skills history. The pinned repository, path,
# commit and file hash are recorded in the check itself.
SCHEMA_CHECK="$SCRIPT_DIR/lib/codex_plugin_schema.py"

# schema_gate_verdict <check> <repo-root> — prints "pass" or "fail: <reason>".
# A missing or unreadable check is a failure, never a skip.
schema_gate_verdict() {
  local check="$1" root="$2" output status reason
  if [ ! -r "$check" ]; then
    printf 'fail: pinned schema check is missing (%s)\n' "$check"
    return 0
  fi
  output=$(python3 -I "$check" "$root" 2>&1 </dev/null)
  status=$?
  if [ "$status" -eq 0 ]; then
    printf 'pass\n'
  else
    reason=$(printf '%s\n' "$output" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    printf 'fail: exit=%s: %s\n' "$status" "$reason"
  fi
}

# spec-example: tests / pinned schema accepts the repository manifests
gate_verdict=$(schema_gate_verdict "$SCHEMA_CHECK" "$REPO_ROOT")
if [ "$gate_verdict" = "pass" ]; then
  pass "pinned schema check accepts the native package"
else
  fail "pinned schema check accepts the native package (${gate_verdict#fail: })"
fi

# spec-example: codex-native-plugin / pinned schema check accepts the native manifest
if [ -r "$SCHEMA_CHECK" ]; then
  quiet_output=$(python3 -I "$SCHEMA_CHECK" "$REPO_ROOT" 2>&1 </dev/null)
  quiet_exit=$?
  if [ "$quiet_exit" -eq 0 ] && [ -z "$quiet_output" ]; then
    pass "pinned schema check exits 0 and prints nothing for the native manifest"
  else
    fail "pinned schema check exits 0 and prints nothing for the native manifest (exit=$quiet_exit: $quiet_output)"
  fi
  python3 -I "$SCHEMA_CHECK" >/dev/null 2>&1 </dev/null
  usage_exit=$?
  if [ "$usage_exit" -eq 64 ]; then
    pass "pinned schema check exits 64 on a usage error"
  else
    fail "pinned schema check exits 64 on a usage error (got $usage_exit)"
  fi
fi

# spec-example: tests / missing schema check fails the contract test
missing_verdict=$(schema_gate_verdict "$REPO_ROOT/tests/lib/does-not-exist.py" "$REPO_ROOT")
# The verdict's status word decides, not a substring of a message that holds a path.
case "$missing_verdict" in
  "fail: pinned schema check is missing ($REPO_ROOT/tests/lib/does-not-exist.py)")
    pass "a missing schema check is reported as a failure naming the file" ;;
  *) fail "a missing schema check is reported as a failure naming the file (got: $missing_verdict)" ;;
esac

# spec-example: tests / pinned schema rejects a broken manifest
# Each case mutates a temporary copy of the two manifests and expects the
# given exit code and the field name in the output.
schema_tmp=$(mktemp -d "${TMPDIR:-/tmp}/codex-plugin-schema.XXXXXX") || {
  fail "temporary directory for pinned schema negative cases"; schema_tmp=""; }
SCHEMA_CASES=$(cat <<'CASES'
name-missing|1|plugin.json name:
name-not-kebab|1|plugin.json name:
name-trailing-newline|1|plugin.json name:
version-number|1|plugin.json version:
version-trailing-newline|1|plugin.json version:
version-non-ascii-digit|1|plugin.json version:
version-prerelease-leading-zero|1|plugin.json version:
keywords-string|1|plugin.json keywords:
undocumented-field|1|plugin.json skill:
skills-not-relative|1|plugin.json skills:
skills-dotdot|1|plugin.json skills:
default-prompt-four|1|plugin.json interface.defaultPrompt:
default-prompt-too-long|1|plugin.json interface.defaultPrompt:
screenshot-outside-assets|1|plugin.json interface.screenshots[0]:
screenshot-dotdot|1|plugin.json interface.screenshots[0]:
policy-installation-invalid|1|plugins[0].policy.installation:
policy-authentication-invalid|1|plugins[0].policy.authentication:
source-not-local|1|plugins[0].source.source:
source-path-not-relative|1|plugins[0].source.path:
source-path-dotdot|1|plugins[0].source.path:
category-missing|1|plugins[0].category:
plugin-not-object|1|plugin.json: must be a JSON object
plugin-not-json|2|plugin.json: not JSON
plugin-nan|2|plugin.json: not JSON
plugin-missing|2|plugin.json: missing
market-not-json|2|marketplace.json: not JSON
CASES
)
schema_cases_expected=$(printf '%s\n' "$SCHEMA_CASES" | grep -c .)
schema_cases_ran=0
if [ -n "$schema_tmp" ] && [ -r "$SCHEMA_CHECK" ]; then
  while IFS='|' read -r case_name expect_exit expect_field; do
    [ -n "$case_name" ] || continue
    case_root="$schema_tmp/$case_name"
    mkdir -p "$case_root/.codex-plugin" "$case_root/.agents/plugins"
    cp "$REPO_ROOT/.codex-plugin/plugin.json" "$case_root/.codex-plugin/plugin.json"
    cp "$REPO_ROOT/.agents/plugins/marketplace.json" "$case_root/.agents/plugins/marketplace.json"
    if ! python3 -I - "$case_root" "$case_name" <<'PY_MUTATE'
import json
import sys
from pathlib import Path

root, case = Path(sys.argv[1]), sys.argv[2]
plugin_path = root / ".codex-plugin" / "plugin.json"
market_path = root / ".agents" / "plugins" / "marketplace.json"
plugin = json.loads(plugin_path.read_text(encoding="utf-8"))
market = json.loads(market_path.read_text(encoding="utf-8"))
entry = market["plugins"][0]
if case == "name-missing":
    del plugin["name"]
elif case == "name-not-kebab":
    plugin["name"] = "Codex Pro"
elif case == "name-trailing-newline":
    plugin["name"] = "codex-pro\n"
elif case == "version-trailing-newline":
    plugin["version"] = "0.11.0\n"
elif case == "version-non-ascii-digit":
    plugin["version"] = "1.2.\u0663"
elif case == "version-prerelease-leading-zero":
    plugin["version"] = "1.2.3-01"
elif case == "skills-dotdot":
    plugin["skills"] = "./../skills/"
elif case == "screenshot-dotdot":
    plugin["interface"]["screenshots"] = ["./assets/../shot.png"]
elif case == "source-path-dotdot":
    entry["source"]["path"] = "./../outside"
elif case == "plugin-not-object":
    plugin_path.write_text("[]", encoding="utf-8")
    sys.exit(0)
elif case == "plugin-nan":
    plugin_path.write_text('{"name": "codex-pro", "version": NaN}', encoding="utf-8")
    sys.exit(0)
elif case == "version-number":
    plugin["version"] = 1
elif case == "keywords-string":
    plugin["keywords"] = "codex"
elif case == "undocumented-field":
    plugin["skill"] = "./skills/"
elif case == "skills-not-relative":
    plugin["skills"] = "skills/"
elif case == "default-prompt-four":
    plugin["interface"]["defaultPrompt"] = ["a", "b", "c", "d"]
elif case == "screenshot-outside-assets":
    plugin["interface"]["screenshots"] = ["./shot.png"]
elif case == "policy-installation-invalid":
    entry["policy"]["installation"] = "MAYBE"
elif case == "source-not-local":
    entry["source"]["source"] = "git"
elif case == "category-missing":
    del entry["category"]
elif case == "default-prompt-too-long":
    plugin["interface"]["defaultPrompt"] = ["x" * 129]
elif case == "policy-authentication-invalid":
    entry["policy"]["authentication"] = "SOMETIMES"
elif case == "source-path-not-relative":
    entry["source"]["path"] = "plugins/codex-pro"
elif case == "plugin-not-json":
    plugin_path.write_text("not json", encoding="utf-8")
    sys.exit(0)
elif case == "plugin-missing":
    plugin_path.unlink()
    sys.exit(0)
elif case == "market-not-json":
    market_path.write_text("not json", encoding="utf-8")
    sys.exit(0)
else:
    sys.exit(f"unknown case {case}")
plugin_path.write_text(json.dumps(plugin), encoding="utf-8")
market_path.write_text(json.dumps(market), encoding="utf-8")
PY_MUTATE
    then
      fail "pinned schema negative case '$case_name' could be prepared"
      continue
    fi
    schema_cases_ran=$((schema_cases_ran + 1))
    case_output=$(python3 -I "$SCHEMA_CHECK" "$case_root" 2>&1 </dev/null)
    case_exit=$?
    if [ "$case_exit" -eq "$expect_exit" ] && printf '%s' "$case_output" | grep -qF -- "$expect_field"; then
      pass "pinned schema rejects '$case_name' (exit $expect_exit, names $expect_field)"
    else
      case_reason=$(printf '%s\n' "$case_output" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
      fail "pinned schema rejects '$case_name' (expected exit $expect_exit naming $expect_field; got exit $case_exit: $case_reason)"
    fi
  done <<<"$SCHEMA_CASES"
elif [ -n "$schema_tmp" ]; then
  fail "pinned schema negative cases need the check file ($SCHEMA_CHECK)"
fi
if [ "$schema_cases_ran" -eq "$schema_cases_expected" ]; then
  pass "pinned schema negative cases all ran ($schema_cases_ran of $schema_cases_expected)"
else
  fail "pinned schema negative cases all ran (ran $schema_cases_ran of $schema_cases_expected)"
fi

# The gate's failure reaches the whole script: a copy of the tracked tree with a
# broken manifest, and one without the check file, must make this script exit
# non-zero and name the schema step. Nested runs skip this section.
if [ -n "$schema_tmp" ] && [ "${CODEX_PLUGIN_NESTED:-}" != "1" ]; then
  for integration_case in broken-manifest missing-check; do
    copy_root="$schema_tmp/copy-$integration_case"
    mkdir -p "$copy_root"
    if ! (cd "$REPO_ROOT" && git ls-files -z | tar --null -T - -cf -) | (cd "$copy_root" && tar -xf -); then
      fail "integration copy of the tracked tree for '$integration_case'"
      continue
    fi
    if [ "$integration_case" = "broken-manifest" ]; then
      python3 -I -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["keywords"]="codex"; open(p,"w").write(json.dumps(d))' \
        "$copy_root/.codex-plugin/plugin.json"
      expect_text="✗ pinned schema check accepts the native package"
    else
      rm -f "$copy_root/tests/lib/codex_plugin_schema.py"
      expect_text="pinned schema check is missing"
    fi
    integration_output=$(CODEX_PLUGIN_NESTED=1 bash "$copy_root/tests/codex-plugin.sh" 2>&1 </dev/null)
    integration_exit=$?
    if [ "$integration_exit" -ne 0 ] && printf '%s' "$integration_output" | grep -qF -- "$expect_text"; then
      pass "codex-plugin.sh exits non-zero and names the schema step ($integration_case)"
    else
      fail "codex-plugin.sh exits non-zero and names the schema step ($integration_case; exit=$integration_exit)"
    fi
  done
fi
[ -n "$schema_tmp" ] && rm -rf "$schema_tmp"

report_summary "codex-plugin"
exit_code=$?
exit "$exit_code"
