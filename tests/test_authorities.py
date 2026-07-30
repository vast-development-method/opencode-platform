#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]


def load_yaml(path: str) -> dict:
    value = yaml.safe_load((ROOT / path).read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise AssertionError(f"{path} must contain a mapping")
    return value


def load_toolchain() -> dict[str, str]:
    values: dict[str, str] = {}
    for line in (ROOT / "manifest/toolchain.env").read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        key, separator, value = line.partition("=")
        if separator:
            values[key] = value
    return values


class AuthorityContractTest(unittest.TestCase):
    def test_provider_routes_match_the_broker(self) -> None:
        providers = load_yaml("manifest/providers.yaml")
        broker = load_yaml("broker/config/litellm.yaml")
        self.assertEqual(1, providers["schema"])
        declared_routes = {
            provider["route"] for provider in providers["providers"].values()
        }
        broker_routes = {entry["model_name"] for entry in broker["model_list"]}
        self.assertEqual(broker_routes, declared_routes)
        for provider in providers["providers"].values():
            self.assertFalse(provider["persistent_in_image"])
            self.assertNotEqual("image", provider["credential_location"])

    def test_mcp_catalog_matches_the_shipped_configuration(self) -> None:
        catalog = load_yaml("manifest/mcp-catalog.yaml")
        config = json.loads(
            (
                ROOT
                / "image/files/home/opencode/.config/opencode/opencode.json"
            ).read_text(encoding="utf-8")
        )
        servers = catalog["servers"]
        self.assertEqual(1, catalog["schema"])
        self.assertEqual(set(servers), set(config["mcp"]) | {"joomla"})

        toolchain = load_toolchain()
        expected_versions = {
            "git": toolchain["GIT_MCP_EXPECTED_VERSION"],
            "joomla": toolchain["JOOMLA_MCP_EXPECTED_VERSION"],
            "playwright": toolchain["PLAYWRIGHT_MCP_EXPECTED_VERSION"],
        }
        for server, version in expected_versions.items():
            self.assertEqual(version, str(servers[server]["version"]))

        self.assertTrue(config["mcp"]["git"]["enabled"])
        self.assertFalse(config["mcp"]["playwright"]["enabled"])

    def test_session_policy_schema_preserves_fail_closed_controls(self) -> None:
        schema = json.loads(
            (ROOT / "schemas/session-policy.schema.json").read_text(encoding="utf-8")
        )
        self.assertEqual("object", schema["type"])
        self.assertFalse(schema["additionalProperties"])
        self.assertEqual(
            {"session", "expires_at", "models", "repositories", "mcp"},
            set(schema["required"]),
        )
        self.assertFalse(schema["properties"]["allow_protected_branches"]["const"])
        self.assertGreaterEqual(schema["properties"]["session"]["minLength"], 16)
        self.assertTrue(
            re.fullmatch(
                r"https://json-schema\.org/draft/2020-12/schema",
                schema["$schema"],
            )
        )


if __name__ == "__main__":
    unittest.main()
