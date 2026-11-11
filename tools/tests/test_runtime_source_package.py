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
    def test_runtime_asset_module_guard_rejects_excluded_registration(self) -> None:
        with tempfile.TemporaryDirectory(prefix="picture-shop-asset-modules-") as temporary:
            stage = Path(temporary)
            source = stage / "src" / "commute" / "gear_action_art.lua"
            source.parent.mkdir(parents=True)
            source.write_text("return require('assets.staging.commute-gear-actions-v1.registration')", encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "Runtime asset module is missing"):
                package.validate_runtime_asset_modules(stage)
            source.write_text("return require('assets.generated.commute-gear-actions-v1.registration')", encoding="utf-8")
            registration = stage / "assets/generated/commute-gear-actions-v1/registration.lua"
            registration.parent.mkdir(parents=True)
            registration.write_text("return {}", encoding="utf-8")
            package.validate_runtime_asset_modules(stage)

    def test_approved_gear_registration_and_all_strips_are_shipped_assets(self) -> None:
        source = (package.ROOT / "src/commute/gear_action_art.lua").read_text(encoding="utf-8")
        self.assertNotIn("assets.staging", source)
        registration = package.ROOT / "assets/generated/commute-gear-actions-v1/registration.lua"
        text = registration.read_text(encoding="utf-8")
        self.assertIn('status = "runtime_approved"', text)
        images = re.findall(r'"(assets/generated/commute-gear-actions-v1/[^"\n]+\.png)"', text)
        self.assertEqual(len(images), 8)
        self.assertTrue(all((package.ROOT / name).is_file() for name in images))

    def test_commute_runtime_contains_current_atlases_without_offline_sources(self) -> None:
        paths = package.runtime_commute_paths()
        names = {p.relative_to(package.ROOT).as_posix() for p in paths}
        self.assertIn("assets/commute/terrain/ground-desktop-v1.png", names)
        self.assertIn("assets/commute/terrain/ground-mobile-v1.png", names)
        self.assertIn("assets/commute/truck/decals/picture-shop.png", names)
        for image in ("driver-seat.png", "floorboard.png", "headliner.png", "rear-wall.png", "side-door.png"):
            self.assertIn(f"assets/commute/truck/interior-v1/{image}", names)
        for kind in ("chase", "isometric"):
            for page in range(1, 5):
                self.assertIn(f"assets/commute/truck/turntables/{kind}-64-{page}.png", names)
        self.assertFalse(any("picture-shop" in name and "/turntables/" in name for name in names))
        self.assertIn("assets/commute/cockpit/first-person-bike-v2.png", names)
        self.assertIn("assets/commute/bike/mounted-upright-64-v2.png", names)
        story_opening = (package.ROOT / "src/story_opening.lua").read_text(encoding="utf-8")
        for asset in ("assets/commute/bike/mounted.png", "assets/commute/bike/parked.png"):
            self.assertIn(asset, story_opening)
            self.assertIn(asset, names, f"Story opening asset is absent from the mobile package: {asset}")
        self.assertIn("assets/commute/bike/wheel_regions.lua", names)
        self.assertIn("assets/commute/bike/actions-64/paint_regions.lua", names)
        poses = ("aero", "boost", "brake", "shift", "impact", "turnLeft", "turnRight")
        for pose in poses:
            for phase in ("", "Mid"):
                for page in range(1, 5):
                    self.assertIn(f"assets/commute/bike/actions-64/{pose}{phase}-{page}.png", names)
        self.assertIn("assets/commute/cockpit/first-person-bike-fuel-v2.png", names)
        self.assertIn("assets/commute/cockpit/handlebars-fuel-v2.png", names)
        layout = (package.ROOT / "src/commute/vendor/plant_atlas_layout.lua").read_text(encoding="utf-8")
        for atlas in re.findall(r'"(assets/commute/plant-atlas/[^"\n]+\.png)"', layout):
            self.assertIn(atlas, names)
        self.assertFalse(any("/source/" in n or "prompt" in n or n.endswith(".json") for n in names))
        with patch.object(package, "COMMUTE_RUNTIME_GLOBS", ("assets/commute/missing.png",)):
            with self.assertRaisesRegex(RuntimeError, "Missing required commute artwork"):
                package.runtime_commute_paths()

    def test_vibes_radio_playlist_is_explicit_and_complete(self) -> None:
        tracks = package.runtime_music_paths()
        self.assertEqual(len(tracks), 9)
        self.assertEqual([path.name for path in tracks], list(package.VIBES_MUSIC_TRACKS))
        self.assertTrue(all(path.parent.as_posix().endswith("assets/audio/music/vibes")
                            for path in tracks))
        self.assertEqual(len(package.runtime_music_manifest()), 9)

    def test_allowlist_is_complete_unique_and_existing(self) -> None:
        paths = package.runtime_source_paths()
        self.assertEqual(len(paths), 70)
        self.assertEqual(len(paths), len(set(paths)))
        self.assertTrue(all(path.suffix == ".png" for path in paths))

    def test_all_live_literal_source_paths_are_included(self) -> None:
        for relative in ("src/config.lua", "src/screens/pallet_rack_screen.lua",
                         "src/warehouse_renderer.lua", "src/warehouse_rack_presentation.lua",
                         "src/warehouse_breakroom_presentation.lua"):
            text = (package.ROOT / relative).read_text(encoding="utf-8")
            for asset in re.findall(r'"(assets/source/[^"\n]+\.png)"', text):
                self.assertIn(asset, package.RUNTIME_SOURCE_ASSETS, relative)
        self.assertIn(package.WAREHOUSE_SOURCE_ROOT + "pallet-front-variants-v2-candidate.png",
                      package.RUNTIME_SOURCE_ASSETS)
        self.assertIn(package.WAREHOUSE_SOURCE_ROOT + "rack-world-left-v9-perspective-candidate.png",
                      package.RUNTIME_SOURCE_ASSETS)
        self.assertNotIn(package.WAREHOUSE_SOURCE_ROOT + "rack-world-left-v2.png",
                         package.RUNTIME_SOURCE_ASSETS)
        for direction in ("east", "north", "northeast", "southeast", "south"):
            self.assertIn(package.WAREHOUSE_SOURCE_ROOT +
                          f"pallet-jack-push/push-{direction}-v1-candidate.png",
                          package.RUNTIME_SOURCE_ASSETS)

    def test_authored_construction_stages_are_packaged(self) -> None:
        source = (package.ROOT / "src/warehouse_construction_presentation.lua").read_text(encoding="utf-8")
        self.assertIn('local STORAGE_ROOT=ROOT.."construction/"', source)
        self.assertIn('local ROOM_ROOT=ROOT.."rooms/"', source)
        self.assertIn('"left-storage-stage-"..stage..".png"', source)
        for stage in range(1, 5):
            self.assertIn(package.WAREHOUSE_SOURCE_ROOT + f"construction/left-storage-stage-{stage}.png",
                          package.RUNTIME_SOURCE_ASSETS)
        for asset in ("rooms/breakroom-triangle-v6-perspective-candidate.png",
                      "rooms/breakroom-construction-atlas-v1.png",
                      "rooms/floor-construction-atlas-v2-clean.png"):
            self.assertIn(package.WAREHOUSE_SOURCE_ROOT + asset, package.RUNTIME_SOURCE_ASSETS)

    def test_directional_catalog_versions_and_work_sheets_match(self) -> None:
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
        self.assertIn('width=1536,height=1024', work)
        for tool, version in (("concrete", "v3c"), ("hammer", "v3"),
                              ("drill", "v3c"), ("paint", "v3")):
            filename = f"mechanic-work-{tool}-{version}-candidate.png"
            self.assertIn(f'{tool}=sheet("{tool}","{version}"', work)
            self.assertIn(package.WAREHOUSE_SOURCE_ROOT + filename, package.RUNTIME_SOURCE_ASSETS)
        self.assertNotIn(package.WAREHOUSE_SOURCE_ROOT + "mechanic-work-atlas-v2.png",
                         package.RUNTIME_SOURCE_ASSETS)

    def test_continuous_side_view_layers_are_packaged(self) -> None:
        for name in ("east-fixed-manned-v1.png", "east-fixed-empty-v1.png", "east-carriage-v3.png",
                     "southeast-fixed-manned-v1.png", "southeast-fixed-empty-v1.png", "southeast-carriage-v2.png",
                     "northeast-fixed-manned-v1.png", "northeast-fixed-empty-v1.png", "northeast-carriage-v2.png",
                     "south-fixed-manned-v1.png", "south-fixed-empty-v1.png", "south-carriage-v1.png",
                     "north-fixed-manned-v1.png", "north-fixed-empty-v1.png", "north-carriage-v2.png"):
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

    def test_music_allowlist_rejects_missing_and_escaping_tracks(self) -> None:
        with patch.object(package, "VIBES_MUSIC_TRACKS", ("missing.wav",)):
            with self.assertRaisesRegex(RuntimeError, "Missing required Vibes radio track"):
                package.runtime_music_paths()
        with patch.object(package, "VIBES_MUSIC_TRACKS", ("../outside.wav",)):
            with self.assertRaisesRegex(RuntimeError, "escapes"):
                package.runtime_music_paths()

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

    def test_android_package_smoke_renders_story_opening_from_archive(self) -> None:
        script = (package.ROOT / "BUILD_ANDROID.ps1").read_text(encoding="utf-8")
        self.assertIn("$env:PICTURE_SHOP_SMOKE_FOCUS = 'story-intro'", script)
        self.assertIn("mobile-story-package-smoke.rpt", script)
        self.assertIn("story_opening_packing_scene_renders", script)
        self.assertIn("story_opening_travel_montage_renders", script)


if __name__ == "__main__":
    unittest.main()
