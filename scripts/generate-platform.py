#!/usr/bin/env python3
"""Validate the platform manifest and render every derived authority file."""

from __future__ import annotations

import argparse
import difflib
import json
import re
import shlex
import sys
from collections.abc import Iterable, Mapping
from pathlib import Path
from typing import Any

import yaml


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "manifest/images.yaml"
GENERATED_HEADER = "# Generated from manifest/images.yaml. Do not edit.\n"
IDENTIFIER = re.compile(r"^[a-z][a-z0-9-]*$")
SEMVER = re.compile(
    r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
    r"(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$"
)
FORBIDDEN_LANGUAGES = {"go", "java", "rust"}
VALID_STATUS = {"ready", "experimental", "planned", "blocked"}


class IndentedDumper(yaml.SafeDumper):
    """Emit block sequences indented beneath their mapping key."""

    def increase_indent(self, flow: bool = False, indentless: bool = False) -> None:
        return super().increase_indent(flow, False)


class ManifestError(ValueError):
    """Raised when the manifest contract is invalid."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ManifestError(message)


def require_mapping(value: Any, path: str) -> Mapping[str, Any]:
    require(isinstance(value, Mapping), f"{path} must be a mapping")
    return value


def require_identifiers(values: Iterable[str], path: str) -> None:
    for value in values:
        require(
            isinstance(value, str) and IDENTIFIER.fullmatch(value) is not None,
            f"{path}.{value!s} is not a safe identifier",
        )


def load_manifest() -> dict[str, Any]:
    with MANIFEST.open("r", encoding="utf-8") as stream:
        data = yaml.safe_load(stream)
    require(isinstance(data, dict), "manifest root must be a mapping")
    return data


def validate_manifest(data: Mapping[str, Any]) -> None:
    require(data.get("schema") == 2, "schema must be 2")
    platform = require_mapping(data.get("platform"), "platform")
    require(platform.get("name") == "vdm-opencode-platform", "unexpected platform name")
    version = platform.get("version")
    require(isinstance(version, str) and SEMVER.fullmatch(version) is not None, "invalid semantic version")
    require(platform.get("license") == "GPL-3.0-only", "license must be GPL-3.0-only")
    copyright_data = require_mapping(platform.get("copyright"), "platform.copyright")
    require(copyright_data.get("holder") == "Vast Development Method", "copyright holder must be Vast Development Method")
    require(isinstance(copyright_data.get("year"), int), "copyright year must be an integer")

    architectures = require_mapping(platform.get("architectures"), "platform.architectures")
    require({"amd64", "arm64"}.issubset(architectures), "amd64 and arm64 architectures are required")
    require_identifiers(architectures, "platform.architectures")
    aliases: set[str] = set()
    for name, architecture in architectures.items():
        architecture = require_mapping(architecture, f"platform.architectures.{name}")
        current = architecture.get("aliases")
        require(isinstance(current, list) and current, f"architecture {name} requires aliases")
        for alias in current:
            require(isinstance(alias, str) and alias not in aliases, f"duplicate architecture alias: {alias}")
            aliases.add(alias)
        require(isinstance(architecture.get("release"), bool), f"architecture {name}.release must be boolean")

    components = require_mapping(data.get("components"), "components")
    require_identifiers(components, "components")
    for name, component in components.items():
        component = require_mapping(component, f"components.{name}")
        require(component.get("status") in VALID_STATUS, f"invalid component status: {name}")
        provision = component.get("provision")
        require(provision is None or (isinstance(provision, str) and "/" not in provision), f"unsafe provision script: {name}")

    dimensions = require_mapping(data.get("dimensions"), "dimensions")
    languages = require_mapping(dimensions.get("languages"), "dimensions.languages")
    capabilities = require_mapping(dimensions.get("capabilities"), "dimensions.capabilities")
    policies = require_mapping(dimensions.get("policies"), "dimensions.policies")
    sizes = require_mapping(dimensions.get("sizes"), "dimensions.sizes")
    for values, path in (
        (languages, "dimensions.languages"),
        (capabilities, "dimensions.capabilities"),
        (policies, "dimensions.policies"),
        (sizes, "dimensions.sizes"),
    ):
        require_identifiers(values, path)

    require(not (FORBIDDEN_LANGUAGES & set(languages)), "Rust, Go, and Java language variants are intentionally unsupported")
    require({"shell", "php", "python", "node", "typescript", "c", "cpp"}.issubset(languages), "required language catalog is incomplete")
    require({"cpu", "browser", "database", "android", "gpu"}.issubset(capabilities), "required capability catalog is incomplete")
    require(len(policies) >= 5, "at least five policy classes are required")
    require(len(sizes) >= 5, "at least five size classes are required")

    for name, language in languages.items():
        language = require_mapping(language, f"dimensions.languages.{name}")
        require(language.get("status") in VALID_STATUS, f"invalid language status: {name}")
        dependencies = language.get("requires")
        refs = language.get("components")
        require(isinstance(dependencies, list), f"language {name}.requires must be a list")
        require(isinstance(refs, list), f"language {name}.components must be a list")
        require(all(dep in languages for dep in dependencies), f"language {name} references an unknown dependency")
        require(all(ref in components for ref in refs), f"language {name} references an unknown component")

    for name, capability in capabilities.items():
        capability = require_mapping(capability, f"dimensions.capabilities.{name}")
        require(capability.get("status") in VALID_STATUS, f"invalid capability status: {name}")
        refs = capability.get("components")
        require(isinstance(refs, list) and all(ref in components for ref in refs), f"capability {name} has invalid components")

    for name, policy in policies.items():
        policy = require_mapping(policy, f"dimensions.policies.{name}")
        require(policy.get("status") in VALID_STATUS, f"invalid policy status: {name}")
        require(policy.get("ingress") in {"allow", "reject"}, f"invalid ingress policy: {name}")
        require(policy.get("egress") in {"allow", "reject"}, f"invalid egress policy: {name}")

    for name, size in sizes.items():
        size = require_mapping(size, f"dimensions.sizes.{name}")
        require(isinstance(size.get("cpus"), int) and size["cpus"] > 0, f"invalid CPU count: {name}")
        for field in ("memory", "disk"):
            require(isinstance(size.get(field), str) and re.fullmatch(r"[1-9]\d*GiB", size[field]) is not None, f"invalid {field}: {name}")

    images = require_mapping(data.get("images"), "images")
    require_identifiers(images, "images")
    require(any(image.get("release") is True for image in images.values()), "at least one release image is required")
    for name, image in images.items():
        image = require_mapping(image, f"images.{name}")
        require(image.get("status") in VALID_STATUS, f"invalid image status: {name}")
        require(isinstance(image.get("release"), bool), f"image {name}.release must be boolean")
        image_languages = image.get("languages")
        image_capabilities = image.get("capabilities")
        require(isinstance(image_languages, list) and all(ref in languages for ref in image_languages), f"image {name} has invalid languages")
        require(isinstance(image_capabilities, list) and all(ref in capabilities for ref in image_capabilities), f"image {name} has invalid capabilities")
        require(image.get("default_policy") in policies, f"image {name} has an invalid default policy")
        require(image.get("default_size") in sizes, f"image {name} has an invalid default size")
        if image["release"]:
            require(image["status"] == "ready", f"release image {name} must be ready")
            require(all(languages[ref]["status"] == "ready" for ref in image_languages), f"release image {name} uses an unready language")
            require(all(capabilities[ref]["status"] == "ready" for ref in image_capabilities), f"release image {name} uses an unready capability")
            for component in resolve_components(data, image):
                require(components[component]["status"] == "ready", f"release image {name} uses unready component {component}")


def resolve_language_order(languages: Mapping[str, Any], requested: Iterable[str]) -> list[str]:
    result: list[str] = []
    state: dict[str, int] = {}

    def visit(name: str) -> None:
        marker = state.get(name, 0)
        require(marker != 1, f"language dependency cycle includes {name}")
        if marker == 2:
            return
        state[name] = 1
        for dependency in languages[name]["requires"]:
            visit(dependency)
        state[name] = 2
        result.append(name)

    for language in requested:
        visit(language)
    return result


def resolve_components(data: Mapping[str, Any], image: Mapping[str, Any]) -> list[str]:
    dimensions = data["dimensions"]
    result: list[str] = []
    seen: set[str] = set()

    def append(items: Iterable[str]) -> None:
        for item in items:
            if item not in seen:
                seen.add(item)
                result.append(item)

    for language in resolve_language_order(dimensions["languages"], image["languages"]):
        append(dimensions["languages"][language]["components"])
    for capability in image["capabilities"]:
        append(dimensions["capabilities"][capability]["components"])
    return result


def shell_array(values: Iterable[str]) -> str:
    return "(" + " ".join(shlex.quote(value) for value in values) + ")"


def render_shell(data: Mapping[str, Any]) -> str:
    platform = data["platform"]
    images = data["images"]
    release_images = [name for name, image in images.items() if image["release"]]
    release_architectures = [name for name, architecture in platform["architectures"].items() if architecture["release"]]
    lines = [
        GENERATED_HEADER.rstrip(),
        f"PLATFORM_NAME={shlex.quote(platform['name'])}",
        f"PLATFORM_VERSION={shlex.quote(platform['version'])}",
        f"INCUS_BASE_IMAGE={shlex.quote(platform['base_image'])}",
        f"INCUS_IMAGE_PREFIX={shlex.quote(platform['image_prefix'])}",
        f"PLATFORM_IMAGES={shell_array(images)}",
        f"PLATFORM_RELEASE_IMAGES={shell_array(release_images)}",
        f"PLATFORM_RELEASE_ARCHITECTURES={shell_array(release_architectures)}",
        "",
        "declare -Ag PLATFORM_ARCH_ALIASES=(",
    ]
    for canonical, architecture in platform["architectures"].items():
        for alias in architecture["aliases"]:
            lines.append(f"    [{shlex.quote(alias)}]={shlex.quote(canonical)}")
    lines.extend([")", "", "declare -Ag PLATFORM_IMAGE_COMPONENTS=("])
    for name, image in images.items():
        lines.append(f"    [{name}]={shlex.quote(' '.join(resolve_components(data, image)))}")
    lines.extend([")", "", "declare -Ag PLATFORM_IMAGE_DEFAULT_POLICY=("])
    for name, image in images.items():
        lines.append(f"    [{name}]={shlex.quote(image['default_policy'])}")
    lines.extend([")", "", "declare -Ag PLATFORM_IMAGE_DEFAULT_SIZE=("])
    for name, image in images.items():
        lines.append(f"    [{name}]={shlex.quote(image['default_size'])}")
    lines.extend([")", "", "declare -Ag PLATFORM_COMPONENT_PROVISION=("])
    for name, component in data["components"].items():
        if component["status"] == "ready":
            lines.append(f"    [{name}]={shlex.quote(component['provision'] or '')}")
    lines.extend([")", "", "declare -Ag PLATFORM_POLICY_STATUS=("])
    for name, policy in data["dimensions"]["policies"].items():
        lines.append(f"    [{name}]={shlex.quote(policy['status'])}")
    lines.extend([")", "", "declare -Ag PLATFORM_SIZE_CPUS=("])
    for name, size in data["dimensions"]["sizes"].items():
        lines.append(f"    [{name}]={shlex.quote(str(size['cpus']))}")
    lines.extend([")", ""])
    return "\n".join(lines)


def yaml_text(value: Mapping[str, Any]) -> str:
    return GENERATED_HEADER + yaml.dump(
        value,
        Dumper=IndentedDumper,
        sort_keys=False,
        default_flow_style=False,
    )


def image_profile(name: str, image: Mapping[str, Any]) -> str:
    return yaml_text(
        {
            "description": image["purpose"],
            "config": {
                "security.secureboot": "true",
                "user.vdm.variant": name,
            },
            "devices": {},
        }
    )


def size_profile(name: str, size: Mapping[str, Any]) -> str:
    return yaml_text(
        {
            "description": f"VDM resource class: {name}",
            "config": {
                "limits.cpu": str(size["cpus"]),
                "limits.memory": size["memory"],
            },
            "devices": {
                "root": {
                    "type": "disk",
                    "path": "/",
                    "pool": "default",
                    "size": size["disk"],
                }
            },
        }
    )


def policy_profile(name: str, policy: Mapping[str, Any]) -> str:
    return yaml_text(
        {
            "description": f"VDM network policy: {name}",
            "config": {
                "user.vdm.policy": name,
                "user.vdm.policy.status": policy["status"],
            },
            "devices": {
                "eth0": {
                    "type": "nic",
                    "name": "eth0",
                    "network": "vdm-agentbr0",
                    "security.acls": f"vdm-agent-{name}",
                    "security.acls.default.ingress.action": "reject",
                    "security.acls.default.egress.action": "reject",
                    "security.ipv4_filtering": "true",
                }
            },
        }
    )


def acl_rules(name: str) -> list[dict[str, str]]:
    gateway_rules = [
        {"action": "allow", "description": "Runtime DNS", "destination": "10.248.18.1/32", "protocol": "udp", "destination_port": "53"},
        {"action": "allow", "description": "Runtime DNS over TCP", "destination": "10.248.18.1/32", "protocol": "tcp", "destination_port": "53"},
        {"action": "allow", "description": "Capability gateway", "destination": "10.248.18.1/32", "protocol": "tcp", "destination_port": "443"},
    ]
    if name == "offline":
        return []
    if name in {"brokered", "restricted", "release"}:
        port = {"brokered": None, "restricted": "3128", "release": "3129"}[name]
        rules = list(gateway_rules)
        if port:
            rules.append({"action": "allow", "description": f"{name.title()} HTTP CONNECT proxy", "destination": "10.248.18.1/32", "protocol": "tcp", "destination_port": port})
        return rules
    if name == "connected":
        rules = list(gateway_rules)
        for network in ("10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8", "169.254.0.0/16", "172.16.0.0/12", "192.168.0.0/16", "224.0.0.0/4"):
            rules.append({"action": "reject", "description": "Deny private or special-use IPv4", "destination": network})
        rules.append({"action": "allow", "description": "Public IPv4 Internet"})
        return rules
    if name == "lab":
        return [{"action": "allow", "description": "Experimental lab egress"}]
    raise ManifestError(f"no ACL renderer for policy {name}")


def policy_acl(name: str) -> str:
    return yaml_text(
        {
            "description": f"VDM generated egress policy: {name}",
            "config": {},
            "ingress": [],
            "egress": acl_rules(name),
        }
    )


def rendered_files(data: Mapping[str, Any]) -> dict[Path, str]:
    files: dict[Path, str] = {
        ROOT / "VERSION": f"{data['platform']['version']}\n",
        ROOT / "manifest/generated/platform.env": render_shell(data),
    }
    for name, image in data["images"].items():
        files[ROOT / f"incus/profiles/generated/images/{name}.yaml"] = image_profile(name, image)
    for name, size in data["dimensions"]["sizes"].items():
        files[ROOT / f"incus/profiles/generated/sizes/{name}.yaml"] = size_profile(name, size)
    for name, policy in data["dimensions"]["policies"].items():
        files[ROOT / f"incus/profiles/generated/policies/{name}.yaml"] = policy_profile(name, policy)
        files[ROOT / f"incus/acls/generated/{name}.yaml"] = policy_acl(name)
    return files


def matrix(data: Mapping[str, Any]) -> dict[str, list[dict[str, str]]]:
    include: list[dict[str, str]] = []
    architectures = [
        name
        for name, architecture in data["platform"]["architectures"].items()
        if architecture["release"]
    ]
    for architecture in architectures:
        for variant, image in data["images"].items():
            if image["release"]:
                include.append(
                    {
                        "variant": variant,
                        "architecture": architecture,
                        "size": image["default_size"],
                        "policy": image["default_policy"],
                    }
                )
    return {"include": include}


def write_files(files: Mapping[Path, str]) -> None:
    for path, content in files.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")


def check_files(files: Mapping[Path, str]) -> bool:
    ok = True
    expected = set(files)
    generated_roots = (
        ROOT / "manifest/generated",
        ROOT / "incus/profiles/generated",
        ROOT / "incus/acls/generated",
    )
    for path, wanted in files.items():
        current = path.read_text(encoding="utf-8") if path.exists() else ""
        if current != wanted:
            ok = False
            relative = path.relative_to(ROOT)
            sys.stderr.writelines(
                difflib.unified_diff(
                    current.splitlines(keepends=True),
                    wanted.splitlines(keepends=True),
                    fromfile=f"{relative} (current)",
                    tofile=f"{relative} (generated)",
                )
            )
    for root in generated_roots:
        if not root.exists():
            continue
        for path in root.rglob("*"):
            if path.is_file() and path not in expected:
                print(f"unexpected generated file: {path.relative_to(ROOT)}", file=sys.stderr)
                ok = False
    return ok


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--write", action="store_true")
    action.add_argument("--check", action="store_true")
    action.add_argument("--matrix", choices=("github", "gitea"))
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        data = load_manifest()
        validate_manifest(data)
        if args.matrix:
            print(json.dumps(matrix(data), separators=(",", ":"), sort_keys=True))
            return 0
        files = rendered_files(data)
        if args.write:
            write_files(files)
            return 0
        return 0 if check_files(files) else 1
    except (ManifestError, OSError, yaml.YAMLError) as error:
        print(f"platform manifest error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
