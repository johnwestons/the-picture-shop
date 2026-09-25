from __future__ import annotations

import hashlib
import re
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))

import build_mobile_package as package


class RuntimeSourcePackageTests(unittest.TestCase):
    def test_allowlist_is_complete_unique_and_existing(self) -> None:
        paths = package.runtime_source_paths()
        self.assertEqual(len(paths), 40)
        self.assertEqual(len(paths), len(set(paths)))
        self.assertTrue(all(path.suffix == ".png" for path in paths))

    def test_all_live_literal_source_paths_are_included(self) -> None:
        for relative in ("src/config.lua", "src/screens/pallet_rack_screen.lua",
                         "src/warehouse_renderer.lua"):
            text = (package.ROOT / relative).read_text(encoding="utf-8")
            for asset in re.findall(r'"(assets/source/[^"\n]+\.png)"', text):
                self.assertIn(asset, package.RUNTIME_SOURCE_ASSETS, relative)

    def test_directional_catalog_versions_and_work_atlas_match(self) -> None:
        presentation = (package.ROOT / "src/forklift_presentation.lua").read_text(encoding="utf-8")
        self.assertIn('direction == "north" and "2" or direction == "south" and "3" or "1"', presentation)
        for direction in ("northwest", "north", "northeast", "east", "southeast", "south", "southwest", "west"):
            version = 2 if direction == "north" else 3 if direction == "south" else 1
            self.assertIn(package.WAREHOUSE_SOURCE_ROOT + f"forklift-lift/{direction}-raise-v{version}.png",
                          package.RUNTIME_SOURCE_ASSETS)
            empty_version = 2 if direction == "southeast" else 1
            self.assertIn(package.WAREHOUSE_SOURCE_ROOT + f"forklift-lift/{direction}-raise-empty-v{empty_version}.png",
                          package.RUNTIME_SOURCE_ASSETS)
            for action in ("walk", "idle"):
                suffix = "" if direction == "east" else "_" + direction
                self.assertIn(package.WAREHOUSE_SOURCE_ROOT + f"mechanic-raccoon/{action}{suffix}.png",
                              package.RUNTIME_SOURCE_ASSETS)
        work = (package.ROOT / "src/mechanic_work_presentation.lua").read_text(encoding="utf-8")
        atlas = re.search(r'local ATLAS=ROOT\.\."([^"]+)"', work)
        self.assertIsNotNone(atlas)
        self.assertIn(package.WAREHOUSE_SOURCE_ROOT + atlas.group(1), package.RUNTIME_SOURCE_ASSETS)

    def test_continuous_side_view_layers_are_packaged(self) -> None:
        for name in ("east-fixed-manned-v1.png", "east-fixed-empty-v1.png", "east-carriage-v2.png"):
            self.assertIn(package.WAREHOUSE_SOURCE_ROOT + "forklift-layer-study/" + name,
                          package.RUNTIME_SOURCE_ASSETS)

    def test_real_assets_survive_isolated_copy_manifest_and_archive(self) -> None:
        with tempfile.TemporaryDirectory(prefix="picture-shop-runtime-assets-") as temporary:
            stage = Path(temporary) / "stage"
            package.copy_runtime_source_assets(stage)
            copied = {path.relative_to(stage).as_posix() for path in stage.rglob("*") if path.is_file()}
            self.assertEqual(copied, set(package.RUNTIME_SOURCE_ASSETS))
            manifest = package.runtime_source_manifest(stage)
            self.assertEqual(manifest, package.runtime_source_manifest())
            archive_path = Path(temporary) / "runtime-assets-test.love"
            package.write_reproducible_archive(stage, archive_path)
            with zipfile.ZipFile(archive_path) as archive:
                self.assertEqual(set(archive.namelist()), copied)
                for entry in manifest:
                    content = archive.read(entry["path"])
                    self.assertEqual(len(content), entry["bytes"])
                    self.assertEqual(hashlib.sha256(content).hexdigest(), entry["sha256"])
                self.assertFalse(any("prompts" in name or "-source-" in name or name.endswith(".json")
                                     for name in archive.namelist()))

    def test_missing_required_art_fails_before_any_copy(self) -> None:
        with tempfile.TemporaryDirectory(prefix="picture-shop-missing-assets-") as temporary:
            root = Path(temporary) / "root"
            stage = Path(temporary) / "stage"
            root.mkdir()
            with self.assertRaisesRegex(RuntimeError, "Missing required runtime source asset"):
                package.copy_runtime_source_assets(stage, root)
            self.assertFalse(stage.exists())

    def test_duplicate_or_escaping_manifest_entries_are_rejected(self) -> None:
        with patch.object(package, "RUNTIME_SOURCE_ASSETS", (package.RUNTIME_SOURCE_ASSETS[0],) * 2):
            with self.assertRaisesRegex(RuntimeError, "Duplicate"):
                package.runtime_source_paths()
        with patch.object(package, "RUNTIME_SOURCE_ASSETS", ("../outside.png",)):
            with self.assertRaisesRegex(RuntimeError, "escapes"):
                package.runtime_source_paths()

    def test_windows_uses_the_shared_package_builder(self) -> None:
        script = (TOOLS / "build_windows_installer.ps1").read_text(encoding="utf-8")
        self.assertIn("tools\\build_mobile_package.py", script)
        self.assertIn("Add-FileToStream $destination $package", script)


if __name__ == "__main__":
    unittest.main()
