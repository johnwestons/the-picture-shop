from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "start_guest_worker_acceptance_host.ps1"
BOOTSTRAP = ROOT / "src" / "acceptance_host_bootstrap.lua"


class GuestWorkerAcceptanceHostTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.script = SCRIPT.read_text(encoding="utf-8")
        cls.bootstrap = BOOTSTRAP.read_text(encoding="utf-8")

    def test_fixture_is_confined_to_disposable_workspace_directory(self) -> None:
        self.assertIn("tmp\\physical-acceptance", self.script)
        self.assertIn("StartsWith($fixturePrefix", self.script)
        self.assertIn("ReparsePoint", self.script)

    def test_every_run_uses_a_new_guarded_love_identity(self) -> None:
        self.assertIn('"the-picture-shop-acceptance-$stamp"', self.script)
        self.assertIn("Test-Path -LiteralPath $identityRoot", self.script)
        self.assertNotIn("the-picture-shop'", self.script)

    def test_launcher_waits_for_real_host_readiness(self) -> None:
        self.assertRegex(
            self.script,
            re.compile(r"ACCEPTANCE HOST\[\]\] READY|ACCEPTANCE HOST", re.MULTILINE),
        )
        self.assertIn("did not report ready", self.script)

    def test_runtime_guard_rejects_normal_identity_and_android(self) -> None:
        self.assertIn('options.osName ~= "Windows"', self.bootstrap)
        self.assertIn('IDENTITY_PREFIX = "the-picture-shop-acceptance-"', self.bootstrap)
        self.assertIn('identity:match("^[a-z0-9%-]+$")', self.bootstrap)


if __name__ == "__main__":
    unittest.main()
