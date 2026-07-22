#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import unittest
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "manifest/images.yaml"
GENERATOR = ROOT / "scripts/generate-platform.py"


class PlatformManifestTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.data = yaml.safe_load(MANIFEST.read_text(encoding="utf-8"))

    def test_authority_and_ownership(self) -> None:
        self.assertEqual(2, self.data["schema"])
        platform = self.data["platform"]
        self.assertEqual((ROOT / "VERSION").read_text(encoding="utf-8").strip(), platform["version"])
        self.assertEqual("GPL-3.0-only", platform["license"])
        self.assertEqual("Vast Development Method", platform["copyright"]["holder"])

    def test_supported_languages_are_intentional(self) -> None:
        languages = set(self.data["dimensions"]["languages"])
        self.assertTrue({"shell", "php", "python", "node", "typescript", "c", "cpp"} <= languages)
        self.assertFalse({"rust", "go", "java"} & languages)

    def test_capability_policy_and_size_catalogs(self) -> None:
        dimensions = self.data["dimensions"]
        self.assertTrue({"cpu", "browser", "database", "android", "gpu"} <= set(dimensions["capabilities"]))
        self.assertGreaterEqual(len(dimensions["policies"]), 5)
        self.assertGreaterEqual(len(dimensions["sizes"]), 5)
        self.assertEqual("planned", dimensions["capabilities"]["android"]["status"])
        self.assertEqual("planned", dimensions["capabilities"]["gpu"]["status"])

    def test_provider_matrices_are_identical_and_complete(self) -> None:
        outputs = []
        for provider in ("github", "gitea"):
            result = subprocess.run(
                ["python3", str(GENERATOR), "--matrix", provider],
                check=True,
                capture_output=True,
                text=True,
            )
            outputs.append(json.loads(result.stdout))
        self.assertEqual(outputs[0], outputs[1])
        expected = {
            (name, architecture)
            for architecture, spec in self.data["platform"]["architectures"].items()
            if spec["release"]
            for name, image in self.data["images"].items()
            if image["release"]
        }
        actual = {(entry["variant"], entry["architecture"]) for entry in outputs[0]["include"]}
        self.assertEqual(expected, actual)


if __name__ == "__main__":
    unittest.main()
