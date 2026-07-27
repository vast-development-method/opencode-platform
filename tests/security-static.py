#!/usr/bin/env python3
from __future__ import annotations

import json
import unittest
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]


class SecurityStaticTest(unittest.TestCase):
    def test_incus_project_restrictions(self) -> None:
        project = yaml.safe_load((ROOT / "incus/projects/vdm-agents.yaml").read_text())
        config = project["config"]
        self.assertEqual("true", config["restricted"])
        self.assertEqual("managed", config["restricted.devices.disk"])
        self.assertEqual("managed", config["restricted.devices.nic"])
        for key in (
            "restricted.devices.gpu",
            "restricted.devices.pci",
            "restricted.devices.proxy",
            "restricted.devices.usb",
            "restricted.virtual-machines.lowlevel",
        ):
            self.assertEqual("block", config[key])

    def test_generated_network_profiles_fail_closed(self) -> None:
        for path in (ROOT / "incus/profiles/generated/policies").glob("*.yaml"):
            profile = yaml.safe_load(path.read_text())
            nic = profile["devices"]["eth0"]
            self.assertEqual("reject", nic["security.acls.default.ingress.action"])
            self.assertEqual("reject", nic["security.acls.default.egress.action"])
            self.assertEqual("true", nic["security.ipv4_filtering"])

    def test_connected_policy_denies_private_networks_before_public_allow(self) -> None:
        acl = yaml.safe_load((ROOT / "incus/acls/generated/connected.yaml").read_text())
        rules = acl["egress"]
        final_allow = max(index for index, rule in enumerate(rules) if rule["action"] == "allow")
        for network in ("10.0.0.0/8", "100.64.0.0/10", "169.254.0.0/16", "172.16.0.0/12", "192.168.0.0/16"):
            index = next(i for i, rule in enumerate(rules) if rule.get("destination") == network)
            self.assertLess(index, final_allow)
            self.assertEqual("reject", rules[index]["action"])

    def test_session_secrets_do_not_enter_incus_arguments(self) -> None:
        session = (ROOT / "scripts/start-session.sh").read_text()
        self.assertNotIn('--env "$line"', session)
        self.assertIn("LoadCredential=session.env:", session)
        self.assertIn("RuntimeMaxSec=", session)
        self.assertIn("KillMode=control-group", session)
        self.assertIn("user.vdm.session.expires_epoch", session)
        for forbidden in ("OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GEMINI_API_KEY", "XAI_API_KEY", "LD_PRELOAD", "BASH_ENV"):
            self.assertNotIn(forbidden, session)

    def test_joomla_defaults_are_local_read_only_and_credential_free(self) -> None:
        example = json.loads(
            (
                ROOT
                / "image/files/etc/joomla-mcp/sites.readonly.example.json"
            ).read_text(encoding="utf-8")
        )
        self.assertNotIn("approval", example)
        for site in example["sites"].values():
            self.assertTrue(site["api"]["baseUrl"].startswith("https://"))
            self.assertEqual("JOOMLA_MCP_SITE_TOKEN", site["api"]["tokenEnv"])
            for toolset in site["toolsets"]:
                self.assertFalse(toolset.endswith(".write"))
                self.assertFalse(toolset.endswith(".admin"))
                self.assertNotEqual("core-update", toolset)

        provision = (ROOT / "image/provision/joomla-mcp.sh").read_text()
        self.assertIn('"enabled": false', provision)
        self.assertIn("--ignore-scripts", provision)
        self.assertNotIn("JOOMLA_MCP_SITE_TOKEN=", provision)

        configure = (ROOT / "scripts/configure-joomla-mcp.sh").read_text()
        self.assertIn("allowIndefinite: false", configure)
        self.assertNotIn("--env JOOMLA_MCP_SITE_TOKEN", configure)

    def test_all_provider_routes_exist(self) -> None:
        config = yaml.safe_load((ROOT / "broker/config/litellm.yaml").read_text())
        routes = {entry["model_name"] for entry in config["model_list"]}
        self.assertEqual(
            {"openai-default", "anthropic-default", "gemini-default", "xai-default", "local-default"},
            routes,
        )


if __name__ == "__main__":
    unittest.main()
