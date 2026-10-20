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
            "playwright": toolchain["PLAYWRIGHT_MCP_EXPECTED_VERSION"],
        }
        for server, version in expected_versions.items():
            self.assertEqual(version, str(servers[server]["version"]))

        self.assertTrue(config["mcp"]["git"]["enabled"])
        self.assertFalse(config["mcp"]["playwright"]["enabled"])

        # Joomla supplies the server and tool catalogue; worker runtime pins
        # must not recreate a second server package or a separate JCB endpoint.
        joomla = servers["joomla"]
        self.assertEqual("streamable-http", joomla["transport"])
        self.assertEqual("ready-disabled", joomla["status"])
        self.assertEqual("https://github.com/joomengine/mcp_component", joomla["source"])
        self.assertNotIn("package", joomla)
        self.assertNotIn("JOOMLA_MCP_PACKAGE", toolchain)
        self.assertEqual("joomla", catalog["integrated_capabilities"]["jcb"]["server"])
        self.assertNotIn("jcb", catalog.get("deferred_integrations", {}))

    def test_node_runtime_lock_matches_the_provisioning_pin(self) -> None:
        toolchain = load_toolchain()
        node = load_yaml("manifest/sources.lock.yaml")["sources"]["node_runtime"]
        self.assertEqual(toolchain["NODE_EXPECTED_VERSION"], node["runtime_version"])
        self.assertEqual(toolchain["NODE_PACKAGE_VERSION"], node["build_ref"])
        self.assertEqual(toolchain["NODESOURCE_SETUP_SHA256"], node["setup_sha256"])
        self.assertEqual(
            f'https://deb.nodesource.com/setup_{toolchain["NODE_MAJOR"]}.x',
            node["setup_url"],
        )
        major, minor, _patch = map(int, toolchain["NODE_EXPECTED_VERSION"].split("."))
        self.assertTrue((major == 24 and minor >= 16) or (major == 26 and minor >= 1))

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
