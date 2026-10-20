"""Behavioral bounds for explicit standalone worker service access."""
import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("service_network", Path(__file__).resolve().parents[1] / "scripts/render-service-network.py")
network = importlib.util.module_from_spec(spec)
spec.loader.exec_module(network)


class ServiceNetworkTest(unittest.TestCase):
    def setUp(self):
        self.config = {"schema": 1, "dns": ["10.248.18.1"], "services": [{"name": "joomla", "address": "10.50.0.12", "port": 443}], "ssh_sources": ["10.50.0.10"]}

    def test_exact_service_and_return_paths(self):
        acl = network.render(self.config)
        self.assertEqual(3, len(acl["egress"]))
        self.assertEqual("10.50.0.12/32", acl["egress"][-1]["destination"])
        self.assertEqual("443", acl["egress"][-1]["destination_port"])
        self.assertEqual("22", acl["ingress"][0]["destination_port"])
        self.assertEqual("10.50.0.10/32", acl["ingress"][0]["source"])
        self.assertTrue(all(rule["action"] == "allow" for rule in acl["egress"]))

    def test_reject_broad_or_special_routes(self):
        for value in ["0.0.0.0/0", "10.0.0.0/8", "169.254.169.254", "127.0.0.1", "100.64.0.1", "224.0.0.1", "::1", "joomla.example.test"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                network.address(value)

    def test_reject_unbounded_or_malformed_services(self):
        for port in [0, 65536, True, "443"]:
            config = copy.deepcopy(self.config)
            config["services"][0]["port"] = port
            with self.subTest(port=port), self.assertRaises(ValueError):
                network.render(config)
        self.config["services"].append(self.config["services"][0].copy())
        with self.assertRaises(ValueError):
            network.render(self.config)


if __name__ == "__main__":
    unittest.main()
