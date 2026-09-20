from __future__ import annotations

import re
import shutil
import subprocess
import unittest
from pathlib import Path


TOOLS = Path(__file__).resolve().parents[1]
SCRIPT = TOOLS / "prepare_lan_device_acceptance.ps1"


class LanDeviceAcceptancePreflightTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.text = SCRIPT.read_text(encoding="utf-8")

    def test_installer_never_clears_or_uninstalls_game_data(self) -> None:
        lowered = self.text.lower()
        self.assertNotIn("'uninstall'", lowered)
        self.assertNotRegex(lowered, r"\bpm\s+clear\b")
        self.assertRegex(
            self.text,
            re.compile(r"'install'\s+'-r'\s+\$apkPath", re.MULTILINE),
        )

    def test_exact_apk_and_pre_post_save_fingerprints_are_required(self) -> None:
        self.assertIn("$actualApkHash -cne [string]$apkReport.sha256", self.text)
        self.assertIn("Get-SaveFingerprint $before[$index]", self.text)
        self.assertIn("Get-SaveFingerprint $after[$index]", self.text)
        self.assertIn("Save files changed during installation", self.text)

    def test_single_connected_device_remains_an_array_for_inventory(self) -> None:
        self.assertNotIn("$selected = if (", self.text)
        self.assertIn("$selected = @($connected)", self.text)
        self.assertIn("if ($selected.Count -lt 1)", self.text)

    def test_launch_cannot_implicitly_authorize_installation(self) -> None:
        powershell = shutil.which("powershell.exe")
        if not powershell:
            self.skipTest("Windows PowerShell is unavailable.")
        completed = subprocess.run(
            [
                powershell,
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(SCRIPT),
                "-Launch",
            ],
            check=False,
            capture_output=True,
            text=True,
            timeout=15,
        )
        self.assertNotEqual(0, completed.returncode)
        self.assertIn("-Launch requires -Install.", completed.stderr)


if __name__ == "__main__":
    unittest.main()
