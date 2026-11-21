#!/usr/bin/env python3
"""Pinned schema check for the native Codex plugin manifests (#24).

Replaces the Codex plugin-creator validator, which Codex CLI no longer ships
and which never appeared in the upstream skills repository. The rules below are
written as code from one upstream document, pinned here. The document itself is
not copied: the skill directory that holds it is Apache-2.0 (its LICENSE.txt),
and copying it would bring a license notice into this repository for no gain.

  repository: openai/skills
  path:       skills/.system/plugin-creator/references/plugin-json-spec.md
  commit:     e940b8a86138adf03972802b990a1dfc57fcbf09
  sha256:     5d7223255decc44fcb93f3aa80bb17afc1469b2d3c339d65d9473c5c0c54fcdd

The upstream file is a sample with a field guide, not a formal schema.

Required here:
  plugin.json       `name` (the guide marks it required).
  marketplace.json  top-level `name` and `plugins`; on each plugin entry `name`,
                    `source` with `source.source` and `source.path`, `policy`
                    with `policy.installation` and `policy.authentication`, and
                    `category` (the guide's "always include" plus the fields its
                    entry guide lists without marking them optional).
Every other documented field is checked for its documented type when present.

Where this check differs from the guide, on purpose:
  stricter  a field the guide does not document is a violation (a new upstream
            field becomes a re-pin decision instead of passing silently);
            `defaultPrompt` beyond 3 entries or 128 characters is a violation
            (the guide says the excess is ignored or truncated);
            `source.source` must be `local` (the guide's repo workflow);
            screenshots must be a lower-case `.png` file name under ./assets/;
            a path with a `..` component is a violation.
  looser    an entry `name` is not compared with the plugin folder or
            plugin.json `name`, and an empty `plugins` array passes: the
            codex-pro specific checks in tests/codex-plugin.sh cover both.

Usage: codex_plugin_schema.py <repo-root>
Exit:  0 both manifests conform; 1 one or more violations (each printed with
       its field), including valid JSON that is not an object; 2 a manifest is
       missing or is not strict JSON (NaN, Infinity, a repeated key, or nesting
       deeper than the parser allows);
       64 usage error.
Python 3.9 compatible (macOS system Python).
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any

SOURCE = {
    "repository": "openai/skills",
    "path": "skills/.system/plugin-creator/references/plugin-json-spec.md",
    "commit": "e940b8a86138adf03972802b990a1dfc57fcbf09",
    "sha256": "5d7223255decc44fcb93f3aa80bb17afc1469b2d3c339d65d9473c5c0c54fcdd",
}

# fullmatch with explicit ASCII classes: `$` would accept a trailing newline,
# and `\d` would accept non-ASCII digits.
KEBAB = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*")
_NUM = r"(?:0|[1-9][0-9]*)"
_PRE_ID = r"(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)"  # numeric ids: no leading zero
_BUILD_ID = r"[0-9A-Za-z-]+"
SEMVER = re.compile(
    rf"{_NUM}\.{_NUM}\.{_NUM}"
    rf"(?:-{_PRE_ID}(?:\.{_PRE_ID})*)?"
    rf"(?:\+{_BUILD_ID}(?:\.{_BUILD_ID})*)?"
)

STRING, OBJECT, STRINGS = "string", "object", "array of strings"

# plugin.json — "Top-level fields" of the field guide.
PLUGIN_FIELDS = {
    "name": STRING, "version": STRING, "description": STRING, "author": OBJECT,
    "homepage": STRING, "repository": STRING, "license": STRING,
    "keywords": STRINGS, "skills": STRING, "hooks": STRING,
    "mcpServers": STRING, "apps": STRING, "interface": OBJECT,
}
AUTHOR_FIELDS = {"name": STRING, "email": STRING, "url": STRING}
# plugin.json — "`interface` fields".
INTERFACE_FIELDS = {
    "displayName": STRING, "shortDescription": STRING, "longDescription": STRING,
    "developerName": STRING, "category": STRING, "capabilities": STRINGS,
    "websiteURL": STRING, "privacyPolicyURL": STRING, "termsOfServiceURL": STRING,
    "defaultPrompt": STRINGS, "brandColor": STRING, "composerIcon": STRING,
    "logo": STRING, "screenshots": STRINGS,
}
# "Path values should be relative and begin with `./`."
PLUGIN_PATHS = ("skills", "hooks", "mcpServers", "apps")
INTERFACE_PATHS = ("composerIcon", "logo")
PROMPT_LIMIT, PROMPT_CHARS = 3, 128

# marketplace.json — "Marketplace field guide".
MARKET_FIELDS = {"name": STRING, "interface": OBJECT, "plugins": "array"}
MARKET_INTERFACE_FIELDS = {"displayName": STRING}
ENTRY_FIELDS = {"name": STRING, "source": OBJECT, "policy": OBJECT, "category": STRING}
SOURCE_FIELDS = {"source": STRING, "path": STRING}
POLICY_FIELDS = {"installation": STRING, "authentication": STRING, "products": STRINGS}
INSTALLATION = ("NOT_AVAILABLE", "AVAILABLE", "INSTALLED_BY_DEFAULT")
AUTHENTICATION = ("ON_INSTALL", "ON_USE")


class ManifestUnreadable(Exception):
    pass


def _reject_constant(token: str) -> None:
    raise ValueError(f"{token} is not JSON")


def _reject_duplicates(pairs: list[tuple[str, Any]]) -> dict:
    """A repeated key would let another loader see a different manifest."""
    seen: dict = {}
    for key, value in pairs:
        if key in seen:
            raise ValueError(f"duplicate key {key!r}")
        seen[key] = value
    return seen


def has_type(value: Any, kind: str) -> bool:
    if kind == STRING:
        return isinstance(value, str)
    if kind == OBJECT:
        return isinstance(value, dict)
    if kind == STRINGS:
        return isinstance(value, list) and all(isinstance(v, str) for v in value)
    if kind == "array":
        return isinstance(value, list)
    raise ValueError(kind)


def check_fields(obj: dict, spec: dict[str, str], prefix: str, errors: list[str]) -> None:
    """Documented fields have their type; undocumented fields are violations."""
    for key, value in obj.items():
        field = prefix + key
        if key not in spec:
            errors.append(f"{field}: not documented by the pinned spec")
        elif not has_type(value, spec[key]):
            errors.append(f"{field}: must be {spec[key]}")


def has_parent_component(value: str) -> bool:
    return ".." in value.split("/")


def check_relative(value: Any, field: str, errors: list[str]) -> None:
    if not isinstance(value, str):
        return
    if not value.startswith("./"):
        errors.append(f"{field}: path must be relative and begin with ./")
    elif has_parent_component(value):
        errors.append(f"{field}: path must not contain a .. component")


def load(path: Path, label: str) -> Any:
    """Parse strict JSON; a missing or unreadable file raises ManifestUnreadable."""
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        raise ManifestUnreadable(f"{label}: missing")
    except (OSError, UnicodeDecodeError) as exc:
        raise ManifestUnreadable(f"{label}: not JSON ({type(exc).__name__})")
    try:
        return json.loads(text, parse_constant=_reject_constant, object_pairs_hook=_reject_duplicates)
    except ValueError as exc:
        raise ManifestUnreadable(f"{label}: not JSON ({exc})")
    except RecursionError:
        raise ManifestUnreadable(f"{label}: not JSON (nested deeper than the parser allows)")


def check_plugin(plugin: dict, errors: list[str]) -> None:
    check_fields(plugin, PLUGIN_FIELDS, "plugin.json ", errors)
    name = plugin.get("name")
    if name is None:
        errors.append("plugin.json name: required")
    elif isinstance(name, str) and not KEBAB.fullmatch(name):
        errors.append("plugin.json name: must be kebab-case")
    version = plugin.get("version")
    if isinstance(version, str) and not SEMVER.fullmatch(version):
        errors.append("plugin.json version: must be a semantic version")
    if isinstance(plugin.get("author"), dict):
        check_fields(plugin["author"], AUTHOR_FIELDS, "plugin.json author.", errors)
    for key in PLUGIN_PATHS:
        check_relative(plugin.get(key), f"plugin.json {key}", errors)
    interface = plugin.get("interface")
    if isinstance(interface, dict):
        check_interface(interface, errors)


def check_interface(interface: dict, errors: list[str]) -> None:
    check_fields(interface, INTERFACE_FIELDS, "plugin.json interface.", errors)
    prompts = interface.get("defaultPrompt")
    if isinstance(prompts, list):
        if len(prompts) > PROMPT_LIMIT:
            errors.append(f"plugin.json interface.defaultPrompt: at most {PROMPT_LIMIT} entries")
        if any(isinstance(p, str) and len(p) > PROMPT_CHARS for p in prompts):
            errors.append(f"plugin.json interface.defaultPrompt: each entry at most {PROMPT_CHARS} characters")
    for key in INTERFACE_PATHS:
        check_relative(interface.get(key), f"plugin.json interface.{key}", errors)
    shots = interface.get("screenshots")
    if isinstance(shots, list):
        for index, shot in enumerate(shots):
            name = shot.rsplit("/", 1)[-1] if isinstance(shot, str) else ""
            if isinstance(shot, str) and not (
                shot.startswith("./assets/") and name.endswith(".png") and len(name) > len(".png")
                and not has_parent_component(shot)
            ):
                errors.append(f"plugin.json interface.screenshots[{index}]: must be a .png under ./assets/")


def check_marketplace(market: dict, errors: list[str]) -> None:
    check_fields(market, MARKET_FIELDS, "marketplace.json ", errors)
    for key in ("name", "plugins"):
        if key not in market:
            errors.append(f"marketplace.json {key}: required")
    if isinstance(market.get("interface"), dict):
        check_fields(market["interface"], MARKET_INTERFACE_FIELDS, "marketplace.json interface.", errors)
    plugins = market.get("plugins")
    if isinstance(plugins, list):
        for index, entry in enumerate(plugins):
            check_entry(entry, f"marketplace.json plugins[{index}].", errors)


def check_entry(entry: Any, prefix: str, errors: list[str]) -> None:
    if not isinstance(entry, dict):
        errors.append(f"{prefix[:-1]}: must be an object")
        return
    # displayName belongs under the top-level interface, not individual entries.
    check_fields(entry, ENTRY_FIELDS, prefix, errors)
    for key in ENTRY_FIELDS:
        if key not in entry:
            errors.append(f"{prefix}{key}: required")
    source = entry.get("source")
    if isinstance(source, dict):
        check_fields(source, SOURCE_FIELDS, prefix + "source.", errors)
        if source.get("source") != "local":
            errors.append(f"{prefix}source.source: must be local")
        if "path" not in source:
            errors.append(f"{prefix}source.path: required")
        check_relative(source.get("path"), prefix + "source.path", errors)
    policy = entry.get("policy")
    if isinstance(policy, dict):
        check_fields(policy, POLICY_FIELDS, prefix + "policy.", errors)
        if policy.get("installation") not in INSTALLATION:
            errors.append(f"{prefix}policy.installation: must be one of {', '.join(INSTALLATION)}")
        if policy.get("authentication") not in AUTHENTICATION:
            errors.append(f"{prefix}policy.authentication: must be one of {', '.join(AUTHENTICATION)}")


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: codex_plugin_schema.py <repo-root>", file=sys.stderr)
        return 64
    root = Path(argv[1])
    try:
        plugin = load(root / ".codex-plugin" / "plugin.json", "plugin.json")
        market = load(root / ".agents" / "plugins" / "marketplace.json", "marketplace.json")
    except ManifestUnreadable as exc:
        print(exc)
        return 2
    errors: list[str] = []
    for label, data in (("plugin.json", plugin), ("marketplace.json", market)):
        if not isinstance(data, dict):
            errors.append(f"{label}: must be a JSON object")
    if isinstance(plugin, dict):
        check_plugin(plugin, errors)
    if isinstance(market, dict):
        check_marketplace(market, errors)
    for error in errors:
        print(error)
    if errors:
        print(f"{len(errors)} violation(s) of the pinned spec {SOURCE['repository']}@{SOURCE['commit'][:12]}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
