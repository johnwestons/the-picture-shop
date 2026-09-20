from __future__ import annotations

import hashlib
import os
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))

from build_mobile_package import ZIP_TIMESTAMP, write_reproducible_archive


class MobilePackageReproducibilityTests(unittest.TestCase):
    def test_equal_content_with_different_mtimes_produces_identical_archive(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            first_stage = root / "first"
            second_stage = root / "second"
            for stage in (first_stage, second_stage):
                (stage / "src").mkdir(parents=True)
                (stage / "assets").mkdir()
                (stage / "src" / "main.lua").write_bytes(b"return true\n")
                (stage / "assets" / "pixel.png").write_bytes(b"not-a-real-png")
            os.utime(first_stage / "src" / "main.lua", (1_000_000_000, 1_000_000_000))
            os.utime(second_stage / "src" / "main.lua", (1_700_000_000, 1_700_000_000))
            first = root / "first.love"
            second = root / "second.love"
            write_reproducible_archive(first_stage, first)
            write_reproducible_archive(second_stage, second)
            self.assertEqual(first.read_bytes(), second.read_bytes())
            self.assertEqual(
                hashlib.sha256(first.read_bytes()).hexdigest(),
                hashlib.sha256(second.read_bytes()).hexdigest(),
            )
            with zipfile.ZipFile(first) as archive:
                self.assertEqual(
                    [entry.date_time for entry in archive.infolist()],
                    [ZIP_TIMESTAMP, ZIP_TIMESTAMP],
                )


if __name__ == "__main__":
    unittest.main()
