#!/usr/bin/env python3
"""Validate the versioned installer placeholder contract as source data.

The checker deliberately reads bytes and text only.  It never imports installer
modules, sources shell, executes Perl/AWK, or inspects a live target.  The
JSON registry remains authored under ``d-i/debian/catalog`` for full-checkout
validation. Its validated TSV projection is runtime data: normal payload
capture and receipts bind that index to the same source identity as the
renderer. The developer JSON is intentionally excluded from runtime payloads.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Iterable


ROOT = Path(__file__).resolve().parents[1]
SEED = ROOT / "d-i/debian"
REGISTRY = SEED / "catalog/placeholder-registry.json"
REGISTRY_TSV = SEED / "catalog/placeholder-registry.tsv"
REPORT_DEFAULT = ROOT / ".build/validation/placeholder-registry-coverage.json"
REGISTRY_FORMAT = 2
REGISTRY_VERSION = "2026-11-17"
REGISTRY_ARTIFACTS = {"catalog/placeholder-registry.json", "catalog/placeholder-registry.tsv"}
TSV_COLUMNS = (
    "token",
    "name",
    "namespace",
    "variable",
    "owner_module",
    "owner_function",
    "owner_phase",
    "producer_map",
    "consumer_module",
    "publication_kind",
    "source_family",
    "required",
    "default_policy",
    "syntax",
    "encoding",
    "must_be_absent_from_final_target",
    "final_assertion",
    "source_members",
    "literal_members",
)

# Prefix fragments are part of the renderer implementation and are never
# copied to an installed target.  All other production fragments are rejected.
FRAGMENT_ALLOWLIST = {
    "scripts/common/modules/files-logging.sh",
    "scripts/common/render.pl",
    "scripts/late/templates.sh",
}
NAMESPACES = {
    "PATH",
    "APPARMOR_PROFILE",
    "GITBUILD_DISTRIBUTION",
    "SCALAR",
    "THEME",
    "APPLICATION_GRAMMAR",
}
PUBLICATION_KINDS = {
    "plain",
    "template-input",
    "template",
    "map",
    "resources",
    "pre-clean",
    "appearance",
    "firstboot",
}
PHASES = {
    "base-stage",
    "appearance",
    "installer-hook",
    "firstboot",
    "late-command",
    "desktop-late",
    "target-asset",
    "shared-bootstrap",
}

# Language/package syntax is explicitly distinct from installer substitution.
# Each allowance is still scoped to the exact source member in the registry;
# copying a marker into another owned file does not inherit the allowance.
APPLICATION_TOKENS = {
    "PACKAGE": "Perl package pseudo-constant",
    "all": "Python export declaration",
    "doc": "Python module documentation",
    "enter": "Python context manager protocol",
    "exit": "Python context manager protocol",
    "file": "Python module filename",
    "future": "Python future imports",
    "getitem": "Python subscription protocol",
    "import": "Python import protocol",
    "init": "Python constructor protocol",
    "main": "Python script entrypoint",
    "name": "Python module identity",
    "post_init": "Python dataclass protocol",
    "pycache": "Python bytecode cache filename",
    "version": "Python package version",
    "cause": "Python exception cause attribute",
    "class": "Python class identity attribute",
    "custom_url": "application custom URL identifier",
    "internal": "Sleek internal record identifier",
    "Headphones": "ALSA UCM device identifier",
    "Speaker": "ALSA UCM device identifier",
    "LABWC_GREETER_OUTPUT_STOP": "greeter shell heredoc delimiter",
}

APPEARANCE_REGISTRY = "hooks/target/usr/local/share/desktop/labwc-appearance/fields.json.tmpl"
APPEARANCE_SHADOWS = {
    "INSTALLER_LABWC_WAYBAR_INTERNAL_ACTIVE_SHADOW",
    "INSTALLER_LABWC_WAYBAR_INTERNAL_PANEL_SHADOW",
    "INSTALLER_LABWC_WAYBAR_EXTERNAL_ACTIVE_SHADOW",
    "INSTALLER_LABWC_WAYBAR_EXTERNAL_PANEL_SHADOW",
    "INSTALLER_LABWC_WAYBAR_SHARED_MENU_SHADOW",
    "INSTALLER_LABWC_WAYBAR_SHARED_MENU_HOVER_SHADOW",
}
# A consumer may retain an exact marker as program data. This is separate
# from the same marker's template inputs, which must be absent when rendered.
APP_VETH_RULESET = "hooks/target/etc/app-veth.nft.tmpl"
APP_VETH_CONSUMER = "hooks/target/usr/local/sbin/desktop/app-veth"
APP_VETH_RUNTIME_FIELDS = {
    "APP_INTERFACES": "validated reserved interface-name set",
    "DNS_ADDRESS": "validated private IPv4 DNS address",
    "DNS_HOST_ADDRESS": "validated loopback IPv4 DNS listener",
    "DNS_HOST_PORT": "validated decimal DNS listener port in 1024..65535",
}
# This installed file is input to apply_network_identity, not a final nft
# program. The service fills these four fields from read_configuration before
# invoking nft; its installer-owned port allowlist must already be rendered.
LITERAL_CONSUMERS = {
    "APP_INTERFACES": {APP_VETH_RULESET, APP_VETH_CONSUMER},
    "DNS_ADDRESS": {APP_VETH_RULESET},
    "DNS_HOST_ADDRESS": {APP_VETH_RULESET},
    "DNS_HOST_PORT": {APP_VETH_RULESET},
}
BLOCK_CONSUMERS = {
    "INSTALLER_FSTAB_RECORDS": (
        "scripts/common/render.pl", "fstab_bytes"),
    "INSTALLER_SYSTEM_NAMESERVERS_UPSTREAMS": (
        "scripts/late/stubby-config.py", "render"),
    "INSTALLER_LABWC_WORKSPACE_NAME_LINES": (
        "scripts/desktop/components/rendering-access.sh", "desktop_render_declared_template_blocks"),
    "INSTALLER_LABWC_WORKSPACE_KEYBIND_LINES": (
        "scripts/desktop/components/rendering-access.sh", "desktop_render_declared_template_blocks"),
    "INSTALLER_LABWC_RECORDING_KEYBIND_LINES": (
        "scripts/desktop/components/rendering-access.sh", "desktop_render_declared_template_blocks"),
}


def exact_tokens(data: str) -> list[str]:
    """Return adjacent tokens without allowing underscores to span a token."""
    result: list[str] = []
    offset = 0
    while True:
        start = data.find("__", offset)
        if start < 0:
            return result
        name_start = start + 2
        close = data.find("__", name_start)
        if close < 0:
            return result
        name = data[name_start:close]
        if re.fullmatch(r"[A-Za-z][A-Za-z0-9]*(?:_[A-Za-z0-9]+)*", name):
            result.append(f"__{name}__")
            offset = close + 2
        else:
            offset = name_start


def read_text(path: Path) -> str | None:
    try:
        data = path.read_bytes()
    except OSError:
        return None
    if b"\0" in data:
        return None
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return None


def production_files() -> list[Path]:
    paths: list[Path] = []
    for path in sorted(SEED.rglob("*")):
        if not path.is_file() or path.is_symlink():
            continue
        relative = path.relative_to(SEED).as_posix()
        if relative in REGISTRY_ARTIFACTS:
            continue
        if relative.startswith("tests/") or "/tests/" in relative:
            continue
        if path.name in {"AGENTS.md", "AGENTS.override.md"}:
            continue
        if path.name == "__pycache__":
            continue
        paths.append(path)
    return paths


def source_fingerprint(paths: Iterable[Path]) -> str:
    rows = []
    for path in paths:
        rows.append(f"{path.relative_to(SEED).as_posix()} {hashlib.sha256(path.read_bytes()).hexdigest()}\n")
    return hashlib.sha256("".join(rows).encode("utf-8")).hexdigest()


def phase_for(path: str) -> str:
    if path.startswith("hooks/installer/"):
        return "installer-hook"
    if path.startswith("scripts/firstboot/"):
        return "firstboot"
    if path.startswith("scripts/late/"):
        return "late-command"
    if path.startswith("scripts/desktop/"):
        return "desktop-late"
    if path.startswith("hooks/target/"):
        return "target-asset"
    return "shared-bootstrap"


def namespace(name: str) -> str:
    if name.startswith("INSTALLER_PATH_"):
        return "PATH"
    if name.startswith("INSTALLER_APPARMOR_PROFILE_"):
        return "APPARMOR_PROFILE"
    if name == "INSTALLER_GITBUILD_DISTRIBUTION":
        return "GITBUILD_DISTRIBUTION"
    if name.startswith("INSTALLER_"):
        return "SCALAR"
    if name.startswith("THEME_"):
        return "THEME"
    if name in APPLICATION_TOKENS:
        return "APPLICATION_GRAMMAR"
    return "SCALAR"


def publication_kind(name: str, members: list[str]) -> str:
    if name.startswith("THEME_"):
        return "appearance"
    if any("stubby.yml.tmpl" in member for member in members):
        return "template-input"
    if any(member.startswith("scripts/firstboot/") for member in members):
        return "firstboot"
    if any(member.endswith(".tmpl") for member in members):
        return "template"
    if any("placeholder_map" in member for member in members):
        return "map"
    return "plain"


def build_registry() -> dict:
    files = production_files()
    occurrences: dict[str, list[str]] = {}
    for path in files:
        text = read_text(path)
        if text is None:
            continue
        relative = path.relative_to(SEED).as_posix()
        for token in exact_tokens(text):
            occurrences.setdefault(token, []).append(relative)

    # Refresh discovers references, not authority. A new scalar requires an
    # explicit checked-in declaration instead of silently acquiring an owner
    # from whichever asset happens to sort first.
    declared = {}
    if REGISTRY.exists():
        previous = json.loads(REGISTRY.read_text(encoding="utf-8"))
        for entry in previous.get("entries", []):
            token = entry["token"]
            if token in declared:
                raise ValueError("duplicate registry owner: " + token)
            declared[token] = entry
    entries = []
    for token in sorted(occurrences):
        name = token[2:-2]
        members = sorted(set(occurrences[token]))
        ns = namespace(name)
        if ns == "SCALAR" and token not in declared:
            raise ValueError("new scalar requires an explicit producer/consumer declaration: " + token)
        if ns == "SCALAR" and token in declared:
            allowed_members = set(declared[token]["consumer"]["source_members"])
            if name == "INSTALLER_DATA_END":
                # The same private snapshot terminator is consumed by the
                # base-stage Perl reader, never by an installed target file.
                allowed_members.add("scripts/common/render.pl")
            if name == "DESKTOP_APPARMOR_STATE":
                # The typed Perl policy consumer now owns this exact marker;
                # the late shell adapter supplies only the validated state map.
                allowed_members.add("scripts/common/render.pl")
            if name in BLOCK_CONSUMERS:
                allowed_members.add(BLOCK_CONSUMERS[name][0])
            if set(members) - allowed_members:
                raise ValueError("scalar source family has no declared consumer: " + token + " in " +
                                 ", ".join(sorted(set(members) - allowed_members)))
        if ns == "PATH":
            syntax = "absolute-normalized-target-path"
            owner = {"module": "scripts/common/modules/files-logging.sh",
                     "function": "installer_runtime_path_placeholder_map",
                     "phase": "base-stage"}
            producer = "installer_runtime_path_placeholder_map"
        elif ns == "APPARMOR_PROFILE":
            syntax = "apparmor-profile-name"
            owner = {"module": "hosts/installer/apparmor.env",
                     "function": "validated-profile-map",
                     "phase": "base-stage"}
            producer = "installer_runtime_path_placeholder_map"
        elif ns == "GITBUILD_DISTRIBUTION":
            syntax = "suite-id"
            owner = {"module": "scripts/common/modules/files-logging.sh",
                     "function": "installer_runtime_path_placeholder_map",
                     "phase": "base-stage"}
            producer = "installer_runtime_path_placeholder_map"
        elif ns == "THEME":
            syntax = "theme-schema-value"
            owner = {"module": "scripts/late/themes.sh",
                     "function": "installer_load_themes",
                     "phase": "appearance"}
            producer = "theme registry"
        elif ns == "APPLICATION_GRAMMAR":
            syntax = APPLICATION_TOKENS[name]
            owner = {"module": "scripts/common/target-owned-scan.awk",
                     "function": "source-scoped-application-grammar", "phase": "target-asset"}
            producer = "declared language/package consumer"
        elif name in APP_VETH_RUNTIME_FIELDS:
            syntax = APP_VETH_RUNTIME_FIELDS[name]
            owner = {"module": APP_VETH_CONSUMER,
                     "function": "apply_network_identity", "phase": "target-asset"}
            producer = "read_configuration: validated app-veth network identity"
        elif name == "DESKTOP_APPARMOR_STATE":
            syntax = "enforce-or-complain"
            owner = {"module": "scripts/common/render.pl",
                     "function": "apparmor_modes_bytes", "phase": "late-command"}
            producer = "apparmor_requested_desktop_state"
        elif name in BLOCK_CONSUMERS:
            module, function = BLOCK_CONSUMERS[name]
            syntax = "exactly-one-whole-line-block; consumer validates generated records"
            owner = {"module": module, "function": function, "phase": phase_for(module)}
            producer = function
        else:
            syntax = declared[token]["syntax"]
            owner = declared[token]["owner"]
            producer = declared[token]["producer_map"]
        literal_members = set(LITERAL_CONSUMERS.get(name, set())) & set(members)
        if (ns == "THEME" or name in APPEARANCE_SHADOWS) and APPEARANCE_REGISTRY in members:
            literal_members.add(APPEARANCE_REGISTRY)
        entries.append({
            "token": token,
            "name": name,
            "namespace": ns,
            "owner": owner,
            "producer_map": producer,
            "consumer": {"module": members[0], "source_members": members},
            "literal_members": sorted(literal_members),
            "publication_kind": publication_kind(name, members),
            "source_family": sorted({phase_for(member) for member in members}),
            "required": True,
            "default_policy": "fail-closed",
            "syntax": syntax,
            "encoding": "UTF-8",
            "must_be_absent_from_final_target": ns in {"PATH", "APPARMOR_PROFILE", "GITBUILD_DISTRIBUTION", "SCALAR", "THEME"},
            "final_assertion": (
                "runtime ruleset field allowed only in declared literal source members; "
                "app-veth consumes it before nft; installer markers remain forbidden"
                if name in APP_VETH_RUNTIME_FIELDS else
                "forbidden installer marker absent from every project-owned final target file"
            ),
        })

    return {
        "format": REGISTRY_FORMAT,
        "version": REGISTRY_VERSION,
        "token_grammar": "__[A-Za-z][A-Za-z0-9]*(_[A-Za-z0-9]+)*__ with exact closing delimiters",
        "source_root": "d-i/debian",
        "source_fingerprint": source_fingerprint(files),
        "entries": entries,
    }


def map_keys() -> set[str]:
    keys: set[str] = set()
    for line in (SEED / "catalog/runtime-paths.tsv").read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) != 2:
            raise ValueError("malformed canonical path schema row")
        key, variable = fields
        if (not re.fullmatch(r"(?:DIR_|FILE_|APPARMOR_PROFILE_)[A-Z0-9_]+|GITBUILD_DISTRIBUTION", variable)
                or key != ("PATH_" + variable if variable.startswith(("DIR_", "FILE_")) else variable)
                or key in keys):
            raise ValueError("invalid or duplicate canonical path schema owner: " + key)
        keys.add(key)
    return keys


def tsv_variable(entry: dict) -> str:
    """Map a registry name to the owning runtime environment field."""
    name = entry["name"]
    namespace_name = entry["namespace"]
    if namespace_name == "PATH":
        return name.removeprefix("INSTALLER_PATH_")
    if namespace_name == "APPARMOR_PROFILE":
        return name.removeprefix("INSTALLER_")
    if namespace_name == "GITBUILD_DISTRIBUTION":
        return "GITBUILD_DISTRIBUTION"
    return name


def write_tsv(registry: dict) -> None:
    # Keep every TSV record at one field count so the repository-wide data
    # checker cannot mistake the format marker for a malformed row.
    rows = [
        "\t".join(("format", "2", *("-" for _ in TSV_COLUMNS[2:]))) + "\n",
        "\t".join(TSV_COLUMNS) + "\n",
    ]
    for entry in registry["entries"]:
        owner = entry["owner"]
        consumer = entry["consumer"]
        fields = (
            entry["token"],
            entry["name"],
            entry["namespace"],
            tsv_variable(entry),
            owner["module"],
            owner["function"],
            owner["phase"],
            entry["producer_map"],
            consumer["module"],
            entry["publication_kind"],
            ",".join(entry["source_family"]),
            str(bool(entry["required"])).lower(),
            entry["default_policy"],
            entry["syntax"],
            entry["encoding"],
            str(bool(entry["must_be_absent_from_final_target"])).lower(),
            entry["final_assertion"],
            ",".join(consumer["source_members"]),
            ",".join(entry["literal_members"]),
        )
        if any("\t" in field or "\r" in field or "\n" in field for field in fields):
            raise ValueError("placeholder registry TSV field contains a control separator")
        # A visible empty-field sentinel avoids trailing TAB whitespace while
        # retaining the fixed field count. It grants no literal allowance.
        rows.append("\t".join(field if field else "-" for field in fields) + "\n")
    REGISTRY_TSV.write_text("".join(rows), encoding="utf-8")


def validate_tsv(registry: dict) -> None:
    data = REGISTRY_TSV.read_text(encoding="utf-8").splitlines()
    expected_header = [
        "\t".join(("format", "2", *("-" for _ in TSV_COLUMNS[2:]))),
        "\t".join(TSV_COLUMNS),
    ]
    if data[:2] != expected_header:
        raise ValueError("malformed placeholder registry TSV header")
    expected = set()
    for entry in registry["entries"]:
        owner = entry["owner"]
        consumer = entry["consumer"]
        expected.add((
            entry["token"],
            entry["name"],
            entry["namespace"],
            tsv_variable(entry),
            owner["module"],
            owner["function"],
            owner["phase"],
            entry["producer_map"],
            consumer["module"],
            entry["publication_kind"],
            ",".join(entry["source_family"]),
            str(bool(entry["required"])).lower(),
            entry["default_policy"],
            entry["syntax"],
            entry["encoding"],
            str(bool(entry["must_be_absent_from_final_target"])).lower(),
            entry["final_assertion"],
            ",".join(consumer["source_members"]),
            ",".join(entry["literal_members"]),
        ))
    actual = set()
    for row in data[2:]:
        fields = row.split("\t")
        if (
            len(fields) != len(TSV_COLUMNS)
            or not re.fullmatch(r"__[A-Za-z][A-Za-z0-9]*(?:_[A-Za-z0-9]+)*__", fields[0])
            or not re.fullmatch(r"[A-Za-z][A-Za-z0-9]*(?:_[A-Za-z0-9]+)*", fields[1])
        ):
            raise ValueError("malformed placeholder registry TSV row")
        actual.add(tuple(field if field != "-" else "" for field in fields))
    if len(actual) != len(data[2:]) or actual != expected:
        raise ValueError("placeholder registry TSV does not match JSON registry")


def validate(registry: dict) -> dict:
    if registry.get("format") != REGISTRY_FORMAT or not registry.get("version"):
        raise ValueError("unsupported placeholder registry format")
    entries = registry.get("entries")
    if not isinstance(entries, list) or not entries:
        raise ValueError("placeholder registry has no entries")
    validate_tsv(registry)
    by_token: dict[str, dict] = {}
    for entry in entries:
        token = entry.get("token") if isinstance(entry, dict) else None
        if not isinstance(token, str) or not re.fullmatch(r"__[A-Za-z][A-Za-z0-9]*(?:_[A-Za-z0-9]+)*__", token):
            raise ValueError("malformed registry token")
        if token in by_token:
            raise ValueError("duplicate registry owner: " + token)
        required = {"name", "namespace", "owner", "producer_map", "consumer",
                    "publication_kind", "source_family", "required", "default_policy",
                    "syntax", "encoding", "must_be_absent_from_final_target", "final_assertion"}
        if not required <= entry.keys():
            raise ValueError("incomplete registry entry: " + token)
        name = token[2:-2]
        if entry.get("name") != name:
            raise ValueError("registry token/name mismatch: " + token)
        if entry.get("namespace") not in NAMESPACES:
            raise ValueError("unsupported placeholder namespace: " + token)
        owner = entry.get("owner")
        if (not isinstance(owner, dict) or
                not all(isinstance(owner.get(field), str) and owner[field]
                        for field in ("module", "function", "phase")) or
                owner["phase"] not in PHASES):
            raise ValueError("malformed placeholder owner: " + token)
        producer = entry.get("producer_map")
        if not isinstance(producer, str) or not producer:
            raise ValueError("placeholder producer is missing: " + token)
        consumer = entry.get("consumer")
        if not isinstance(consumer, dict):
            raise ValueError("malformed placeholder consumer: " + token)
        members = consumer.get("source_members")
        if (not isinstance(consumer.get("module"), str) or not consumer["module"] or
                not isinstance(members, list) or not members or
                not all(isinstance(member, str) and member for member in members) or
                consumer["module"] not in members):
            raise ValueError("placeholder consumer/source ownership is malformed: " + token)
        if entry.get("publication_kind") not in PUBLICATION_KINDS:
            raise ValueError("unsupported placeholder publication kind: " + token)
        families = entry.get("source_family")
        if (not isinstance(families, list) or not families or
                not all(isinstance(family, str) and family in PHASES for family in families)):
            raise ValueError("placeholder source family is malformed: " + token)
        if not isinstance(entry.get("required"), bool) or not isinstance(entry.get("default_policy"), str) or not entry["default_policy"]:
            raise ValueError("placeholder required/default policy is malformed: " + token)
        if not isinstance(entry.get("syntax"), str) or not entry["syntax"] or not isinstance(entry.get("encoding"), str) or not entry["encoding"]:
            raise ValueError("placeholder syntax/encoding is malformed: " + token)
        if not isinstance(entry.get("must_be_absent_from_final_target"), bool) or not isinstance(entry.get("final_assertion"), str) or not entry["final_assertion"]:
            raise ValueError("placeholder final assertion is malformed: " + token)
        namespace_name = entry["namespace"]
        if namespace_name == "PATH" and not name.startswith("INSTALLER_PATH_"):
            raise ValueError("PATH namespace token has wrong prefix: " + token)
        if namespace_name == "APPARMOR_PROFILE" and not name.startswith("INSTALLER_APPARMOR_PROFILE_"):
            raise ValueError("AppArmor namespace token has wrong prefix: " + token)
        if namespace_name == "GITBUILD_DISTRIBUTION" and name != "INSTALLER_GITBUILD_DISTRIBUTION":
            raise ValueError("distribution namespace token has wrong name: " + token)
        if namespace_name == "THEME" and not name.startswith("THEME_"):
            raise ValueError("theme namespace token has wrong prefix: " + token)
        if namespace_name == "APPLICATION_GRAMMAR" and entry["must_be_absent_from_final_target"]:
            raise ValueError("application grammar must be explicitly allowlisted: " + token)
        if namespace_name == "APPLICATION_GRAMMAR" and name not in APPLICATION_TOKENS:
            raise ValueError("undeclared application grammar: " + token)
        literal_members = entry.get("literal_members")
        if not isinstance(literal_members, list) or len(set(literal_members)) != len(literal_members):
            raise ValueError("malformed literal consumer declaration: " + token)
        allowed_literal = set(LITERAL_CONSUMERS.get(name, set()))
        if namespace_name == "THEME" or name in APPEARANCE_SHADOWS:
            allowed_literal.add(APPEARANCE_REGISTRY)
        if not set(literal_members) <= allowed_literal & set(members):
            raise ValueError("undeclared literal consumer grammar: " + token)
        if name in APP_VETH_RUNTIME_FIELDS:
            if (set(literal_members) != LITERAL_CONSUMERS[name] or
                    not LITERAL_CONSUMERS[name] <= set(members) or
                    owner != {"module": APP_VETH_CONSUMER,
                              "function": "apply_network_identity", "phase": "target-asset"}):
                raise ValueError("incomplete app-veth runtime ruleset ownership: " + token)
        by_token[token] = entry

    occurrences: dict[str, list[str]] = {}
    malformed: list[dict[str, str]] = []
    for path in production_files():
        text = read_text(path)
        if text is None:
            continue
        relative = path.relative_to(SEED).as_posix()
        for token in exact_tokens(text):
            occurrences.setdefault(token, []).append(relative)
        # Executable renderer code legitimately inspects the marker prefix as
        # data.  Asset templates are the publication contract and therefore
        # reject malformed installer markers here.
        if relative not in FRAGMENT_ALLOWLIST and path.suffix == ".tmpl":
            offset = 0
            while True:
                start = text.find("__INSTALLER_", offset)
                if start < 0:
                    break
                close = text.find("__", start + 2)
                if close < 0:
                    malformed.append({"file": relative, "token": text[start:start + 80]})
                    break
                name = text[start + 2:close]
                if not re.fullmatch(r"INSTALLER_[A-Z][A-Z0-9_]*", name):
                    malformed.append({"file": relative, "token": text[start:close + 2]})
                offset = close + 2

    source_tokens = set(occurrences)
    registry_tokens = set(by_token)
    unknown = sorted(source_tokens - registry_tokens)
    missing = sorted(registry_tokens - source_tokens)
    invalid_sources = []
    for token in source_tokens & registry_tokens:
        declared_members = set(by_token[token]["consumer"]["source_members"])
        actual_members = set(occurrences[token])
        if actual_members != declared_members:
            invalid_sources.append(token)
    canonical = {entry["name"].removeprefix("INSTALLER_") for entry in entries
                 if entry["namespace"] in {"PATH", "APPARMOR_PROFILE", "GITBUILD_DISTRIBUTION"}}
    emitted = map_keys()
    canonical_missing = sorted(canonical - emitted)
    emitted_unowned = sorted(emitted - canonical)
    negative_fixtures: dict[str, list[str]] = {}
    for path in sorted((SEED / "tests").rglob("*")):
        if not path.is_file():
            continue
        text = read_text(path)
        if text is None:
            continue
        tokens = sorted(set(exact_tokens(text)) - registry_tokens)
        if tokens:
            negative_fixtures[path.relative_to(SEED).as_posix()] = tokens

    if unknown:
        raise ValueError("unowned production placeholders: " + ", ".join(unknown[:12]))
    if missing:
        raise ValueError("registry entries are not present in production source: " + ", ".join(missing[:12]))
    if invalid_sources:
        raise ValueError("placeholder source/consumer closure differs: " + ", ".join(invalid_sources[:12]))
    if canonical_missing:
        raise ValueError("canonical map keys missing from emitter: " + ", ".join(canonical_missing[:12]))
    if malformed:
        first = malformed[0]
        raise ValueError(f"malformed production placeholder {first['token']} in {first['file']}")

    return {
        "format": 1,
        "registry_version": registry["version"],
        "source_fingerprint": source_fingerprint(production_files()),
        "production_tokens": len(source_tokens),
        "registry_entries": len(registry_tokens),
        "owners": len({(entry["owner"]["module"], entry["owner"]["function"]) for entry in entries}),
        "canonical_map_keys": len(emitted),
        "canonical_registry_keys": len(canonical),
        "canonical_missing": canonical_missing,
        "emitted_unowned": emitted_unowned,
        "unknown_production_tokens": unknown,
        "malformed_production_tokens": malformed,
        "test_only_negative_fixture_files": len(negative_fixtures),
        "test_only_negative_tokens": sum(len(tokens) for tokens in negative_fixtures.values()),
        "negative_fixtures": negative_fixtures,
        "final_target_forbidden_token_failures": None,
        "deferred_ownership_requires_review": [entry["token"] for entry in entries
                                               if entry["owner"]["function"] == "typed-consumer"],
        "final_target_scan": "source contract only; native target scan requires isolated fixture",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--refresh", action="store_true", help="rebuild the checked-in registry from production source data")
    parser.add_argument("--report", type=Path, default=REPORT_DEFAULT)
    args = parser.parse_args()
    try:
        if args.refresh:
            registry = build_registry()
            REGISTRY.parent.mkdir(parents=True, exist_ok=True)
            REGISTRY.write_text(json.dumps(registry, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            write_tsv(registry)
        else:
            registry = json.loads(REGISTRY.read_text(encoding="utf-8"))
            expected = registry.get("source_fingerprint")
            actual = source_fingerprint(production_files())
            if expected != actual:
                raise ValueError("placeholder registry source fingerprint is stale; run --refresh")
        report = validate(registry)
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(json.dumps({k: report[k] for k in (
            "production_tokens", "registry_entries", "canonical_map_keys",
            "test_only_negative_fixture_files", "final_target_forbidden_token_failures")}, sort_keys=True))
        return 0
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"placeholder registry validation failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
