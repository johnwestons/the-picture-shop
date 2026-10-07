from __future__ import annotations

import hashlib
import io
import os
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from contextlib import redirect_stdout


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))

from build_mobile_package import (
    ZIP_TIMESTAMP,
    copy_windows_route_provider,
    verify_windows_route_package,
    write_reproducible_archive,
    write_runtime_version,
)
import build_mobile_package as package_builder


class MobilePackageReproducibilityTests(unittest.TestCase):
    def test_runtime_version_is_generated_from_the_selected_package_config(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            stage = Path(temporary) / "stage"
            runtime = write_runtime_version(stage, "0.1.0-android.44")
            self.assertEqual(runtime.relative_to(stage).as_posix(), "src/build_version.lua")
            self.assertEqual(
                runtime.read_text(encoding="utf-8"),
                'return { name = "0.1.0-android.44" }\n',
            )

    def test_runtime_version_rejects_lua_source_injection(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaisesRegex(RuntimeError, "unsupported characters"):
                write_runtime_version(Path(temporary), '42"; os.exit(1) --')

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

    def test_windows_route_provider_is_embedded_and_hash_pinned(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            stage = root / "stage"
            loader = stage / "src" / "net" / "gateway_native.lua"
            loader.parent.mkdir(parents=True)
            loader.write_text(
                'local PACKAGED_ROUTE_SHA256 = nil -- WINDOWS_RELEASE_HASH\n'
                'local WINDOWS_RELEASE_PACKAGE = false -- WINDOWS_RELEASE_MODE\n',
                encoding="utf-8",
            )
            provider = root / "tps_route.dll"
            provider.write_bytes(b"conformance-tested route provider bytes")

            manifest = copy_windows_route_provider(stage, provider)
            package = root / "windows.love"
            write_reproducible_archive(stage, package)
            verified = verify_windows_route_package(package, provider)

            self.assertEqual(verified, manifest)
            with zipfile.ZipFile(package) as archive:
                self.assertEqual(
                    archive.read("native/route/tps_route.dll"),
                    provider.read_bytes(),
                )
                packaged_loader = archive.read(
                    "src/net/gateway_native.lua"
                ).decode("utf-8")
                self.assertIn(manifest["sha256"], packaged_loader)

    def test_windows_route_package_rejects_provider_tampering(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            stage = root / "stage"
            loader = stage / "src" / "net" / "gateway_native.lua"
            loader.parent.mkdir(parents=True)
            loader.write_text(
                'local PACKAGED_ROUTE_SHA256 = nil -- WINDOWS_RELEASE_HASH\n'
                'local WINDOWS_RELEASE_PACKAGE = false -- WINDOWS_RELEASE_MODE\n',
                encoding="utf-8",
            )
            provider = root / "tps_route.dll"
            provider.write_bytes(b"expected provider")
            copy_windows_route_provider(stage, provider)
            packaged_provider = stage / "native" / "route" / "tps_route.dll"
            packaged_provider.write_bytes(b"tampered provider")
            package = root / "tampered.love"
            write_reproducible_archive(stage, package)

            with self.assertRaisesRegex(RuntimeError, "hash does not match"):
                verify_windows_route_package(package, provider)

    def test_full_windows_package_build_pins_the_provider(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            provider = root / "tps_route.dll"
            provider.write_bytes(b"conformance-tested route provider bytes")
            output = root / "mobile-output"
            with redirect_stdout(io.StringIO()):
                built = package_builder.build(provider, output_dir=output)
            verification = verify_windows_route_package(built, provider)

            self.assertEqual(built.parent, output)
            self.assertEqual(verification["path"], "native/route/tps_route.dll")
            with zipfile.ZipFile(built) as archive:
                names = archive.namelist()
                self.assertIn("src/net/gateway_native.lua", names)
                self.assertIn("native/route/tps_route.dll", names)


if __name__ == "__main__":
    unittest.main()
