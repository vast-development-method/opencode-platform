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
        self.assertEqual("false", config["features.networks"])
        self.assertEqual("allow", config["restricted.backups"])
        self.assertEqual("block", config["restricted.snapshots"])
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

    def test_networks_and_acls_are_explicitly_managed(self) -> None:
        for path in (ROOT / "incus/networks").glob("*.yaml"):
            network = yaml.safe_load(path.read_text())
            self.assertEqual(
                "vdm-opencode-platform",
                network["config"]["user.vdm.platform"],
            )
        for path in [
            ROOT / "incus/acls/vdm-build.yaml",
            *(ROOT / "incus/acls/generated").glob("*.yaml"),
        ]:
            acl = yaml.safe_load(path.read_text())
            self.assertEqual(
                "vdm-opencode-platform",
                acl["config"]["user.vdm.platform"],
            )
            for rule in [*acl["ingress"], *acl["egress"]]:
                self.assertEqual("enabled", rule["state"])

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

    def test_build_and_launch_avoid_implicit_snapshots(self) -> None:
        build = (ROOT / "scripts/build-image.sh").read_text()
        launch = (ROOT / "scripts/launch-vm.sh").read_text()
        self.assertNotIn("snapshot create", build)
        self.assertNotIn("snapshot create", launch)
        self.assertIn(
            'project_cmd publish "$BUILD_NAME" --alias "$ALIAS" --reuse',
            build,
        )
        self.assertIn('user.vdm.build.state finalized', build)
        self.assertIn("collect_failure_diagnostics", build)
        self.assertIn("Build failed. The stopped checkpoint was retained", build)
        self.assertNotIn(
            'PLATFORM_IMAGE_DEFAULT_SIZE[$VARIANT]',
            build,
            "Build VMs must not inherit launch-time runtime sizes.",
        )

    def test_bootstrap_never_changes_package_sources_or_coreutils_provider(self) -> None:
        bootstrap = (ROOT / "scripts/bootstrap-host.sh").read_text()
        for forbidden in (
            "gnu-coreutils",
            "coreutils-from-uutils",
            "add-apt-repository",
            "/etc/apt/sources.list",
            "/etc/apt/sources.list.d",
            "DOCKER-USER",
        ):
            self.assertNotIn(forbidden, bootstrap)
        self.assertIn("dpkg --audit", bootstrap)
        self.assertIn("apt-get check", bootstrap)

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

        session = (
            ROOT / "image/files/usr/local/libexec/vdm-opencode-session"
        ).read_text()
        self.assertIn("/usr/local/bin/vdm-joomla-mcp-live-test", session)
        self.assertNotIn("vdm-jomla", session)

    def test_all_provider_routes_exist(self) -> None:
        config = yaml.safe_load((ROOT / "broker/config/litellm.yaml").read_text())
        routes = {entry["model_name"] for entry in config["model_list"]}
        self.assertEqual(
            {"openai-default", "anthropic-default", "gemini-default", "xai-default", "local-default"},
            routes,
        )


if __name__ == "__main__":
    unittest.main()
