"""Package the shared Picture Shop source tree as an Android-ready .love archive."""

from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import zipfile
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "output" / "mobile"
STAGE = OUTPUT / "stage"
CONFIG = ROOT / "mobile" / "config.json"
ZIP_TIMESTAMP = (1980, 1, 1, 0, 0, 0)

# Reviewed development art currently used by normal warehouse play lives under
# source/. Ship only these exact files, never the full source/prompt archive.
# Windows installers consume this same .love archive, so this is shared by both
# platform packages. Keep the direction versions in sync with the Lua catalog.
WAREHOUSE_SOURCE_ROOT = "assets/source/warehouse-expansion-v1/"
RUNTIME_SOURCE_ASSETS = tuple(
    WAREHOUSE_SOURCE_ROOT + relative
    for relative in (
        "warehouse-base-v3-top-remake.png",
        "rack-front-2x5-approved.png",
        "pallet-front-variants-v1.png",
        "forklift-eight-directions-unmanned-v1.png",
        "mechanic-work-atlas-v2.png",
        "forklift-lift/northwest-raise-v1.png",
        "forklift-lift/north-raise-v2.png",
        "forklift-lift/northeast-raise-v1.png",
        "forklift-lift/east-raise-v1.png",
        "forklift-lift/southeast-raise-v1.png",
        "forklift-lift/south-raise-v3.png",
        "forklift-lift/southwest-raise-v1.png",
        "forklift-lift/west-raise-v1.png",
        "forklift-lift/northwest-raise-empty-v1.png",
        "forklift-lift/north-raise-empty-v1.png",
        "forklift-lift/northeast-raise-empty-v1.png",
        "forklift-lift/east-raise-empty-v1.png",
        "forklift-lift/southeast-raise-empty-v2.png",
        "forklift-lift/south-raise-empty-v1.png",
        "forklift-lift/southwest-raise-empty-v1.png",
        "forklift-lift/west-raise-empty-v1.png",
        "mechanic-raccoon/idle.png",
        "mechanic-raccoon/idle_north.png",
        "mechanic-raccoon/idle_northeast.png",
        "mechanic-raccoon/idle_northwest.png",
        "mechanic-raccoon/idle_south.png",
        "mechanic-raccoon/idle_southeast.png",
        "mechanic-raccoon/idle_southwest.png",
        "mechanic-raccoon/idle_west.png",
        "mechanic-raccoon/walk.png",
        "mechanic-raccoon/walk_north.png",
        "mechanic-raccoon/walk_northeast.png",
        "mechanic-raccoon/walk_northwest.png",
        "mechanic-raccoon/walk_south.png",
        "mechanic-raccoon/walk_southeast.png",
        "mechanic-raccoon/walk_southwest.png",
        "mechanic-raccoon/walk_west.png",
    )
)


def runtime_source_paths(root: Path = ROOT) -> list[Path]:
    """Validate the complete explicit set before copying any of its files."""
    if len(RUNTIME_SOURCE_ASSETS) != len(set(RUNTIME_SOURCE_ASSETS)):
        raise RuntimeError("Duplicate runtime source-asset allowlist entry")
    resolved_root = root.resolve()
    result = []
    for relative in RUNTIME_SOURCE_ASSETS:
        path = root / relative
        resolved = path.resolve()
        if not relative.startswith(WAREHOUSE_SOURCE_ROOT) or resolved_root not in resolved.parents:
            raise RuntimeError(f"Runtime source asset escapes its package root: {relative}")
        if not path.is_file():
            raise RuntimeError(f"Missing required runtime source asset: {relative}")
        result.append(path)
    return result


def copy_runtime_source_assets(stage: Path, root: Path = ROOT) -> None:
    for source in runtime_source_paths(root):
        destination = stage / source.relative_to(root)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)


def runtime_source_manifest(root: Path = ROOT) -> list[dict[str, str | int]]:
    return [
        {
            "path": source.relative_to(root).as_posix(),
            "bytes": source.stat().st_size,
            "sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        }
        for source in runtime_source_paths(root)
    ]


def git_value(*arguments: str) -> str | None:
    try:
        return subprocess.check_output(
            ["git", *arguments], cwd=ROOT, text=True, stderr=subprocess.DEVNULL
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def safe_clean(path: Path) -> None:
    resolved = path.resolve()
    output = OUTPUT.resolve()
    if resolved == output or output not in resolved.parents:
        raise RuntimeError(f"Refusing to clean outside mobile output: {resolved}")
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True)


def copy_runtime() -> None:
    # Validate before the larger shared runtime copy, then copy this closed set.
    runtime_source_paths()
    for source in (ROOT / "main.lua", ROOT / "conf.lua"):
        shutil.copy2(source, STAGE / source.name)
    for source_root in (ROOT / "src", ROOT / "assets" / "generated"):
        for source in source_root.rglob("*"):
            if source.is_file():
                destination = STAGE / source.relative_to(ROOT)
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, destination)
    audio_root = ROOT / "assets" / "audio"
    audio_files = [audio_root / "SOURCES.md", audio_root / "source_manifest.json"]
    audio_files.extend(
        source for source in (audio_root / "sfx").glob("*.wav")
        if source.name != "picture_shop_sfx_preview.wav"
    )
    for source in audio_files:
        destination = STAGE / source.relative_to(ROOT)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
    copy_runtime_source_assets(STAGE)


def generate_icons() -> None:
    source = ROOT / "mobile" / "android" / "polar-cutter-launcher.png"
    icon_root = OUTPUT / "android-res"
    with Image.open(source) as opened:
        cutter = opened.convert("RGBA")
        scale = min(492 / cutter.width, 492 / cutter.height)
        cutter = cutter.resize(
            (round(cutter.width * scale), round(cutter.height * scale)),
            Image.Resampling.LANCZOS,
        )
    master = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    master.alpha_composite(cutter, ((512 - cutter.width) // 2, (512 - cutter.height) // 2))
    for density, size in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        destination = icon_root / f"drawable-{density}" / "love.png"
        destination.parent.mkdir(parents=True, exist_ok=True)
        master.resize((size, size), Image.Resampling.LANCZOS).save(destination, "PNG", optimize=True)


def write_reproducible_archive(stage: Path, destination: Path) -> None:
    with zipfile.ZipFile(destination, "w", allowZip64=True) as archive:
        for source in sorted(path for path in stage.rglob("*") if path.is_file()):
            relative = source.relative_to(stage).as_posix()
            compression = (
                zipfile.ZIP_STORED
                if source.suffix.lower() in {".png", ".jpg", ".jpeg", ".ogg"}
                else zipfile.ZIP_DEFLATED
            )
            entry = zipfile.ZipInfo(relative, ZIP_TIMESTAMP)
            entry.create_system = 3
            entry.external_attr = 0o100644 << 16
            entry.compress_type = compression
            archive.writestr(entry, source.read_bytes())


def build() -> Path:
    config = json.loads(CONFIG.read_text(encoding="utf-8"))
    OUTPUT.mkdir(parents=True, exist_ok=True)
    safe_clean(STAGE)
    copy_runtime()
    runtime_files = sorted(path for path in STAGE.rglob("*") if path.is_file())
    manifest = {
        "applicationId": config["applicationId"],
        "applicationName": config["applicationName"],
        "versionName": config["versionName"],
        "versionCode": config["versionCode"],
        "loveVersion": config["loveVersion"],
        "sourceCommit": git_value("rev-parse", "HEAD"),
        "sourceDirty": bool(git_value("status", "--porcelain")),
        "runtimeFiles": len(runtime_files),
        "runtimeBytes": sum(path.stat().st_size for path in runtime_files),
        "runtimeSourceAssets": runtime_source_manifest(STAGE),
    }
    (STAGE / "mobile-build.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    package = OUTPUT / f"the-picture-shop-{config['versionName']}.love"
    temporary = package.with_suffix(".tmp.love")
    temporary.unlink(missing_ok=True)
    write_reproducible_archive(STAGE, temporary)
    temporary.replace(package)
    generate_icons()
    manifest["package"] = str(package)
    manifest["packageBytes"] = package.stat().st_size
    manifest["sha256"] = hashlib.sha256(package.read_bytes()).hexdigest()
    (OUTPUT / "build-report.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifest, indent=2))
    print(f"MOBILE_PACKAGE={package}")
    return package


if __name__ == "__main__":
    build()
