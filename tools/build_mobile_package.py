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
    }
    (STAGE / "mobile-build.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    package = OUTPUT / f"the-picture-shop-{config['versionName']}.love"
    temporary = package.with_suffix(".tmp.love")
    temporary.unlink(missing_ok=True)
    with zipfile.ZipFile(temporary, "w", allowZip64=True) as archive:
        for source in sorted(path for path in STAGE.rglob("*") if path.is_file()):
            relative = source.relative_to(STAGE).as_posix()
            compression = zipfile.ZIP_STORED if source.suffix.lower() in {".png", ".jpg", ".jpeg", ".ogg"} else zipfile.ZIP_DEFLATED
            archive.write(source, relative, compression)
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
