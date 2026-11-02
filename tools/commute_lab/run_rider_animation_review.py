#!/usr/bin/env python3
"""Run the isolated LÖVE animation capture without loading a shop save."""

import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOVE = Path(r"C:\Program Files\LOVE\lovec.exe")
FOCUS_OPTIONS = {"suited-walk", "suited-idle"}


def main() -> None:
    focus = sys.argv[1] if len(sys.argv) > 1 else "suited-walk"
    if focus not in FOCUS_OPTIONS:
        raise SystemExit(f"Choose one of: {', '.join(sorted(FOCUS_OPTIONS))}")
    if not LOVE.is_file():
        raise SystemExit(f"LÖVE 11.5 was not found at {LOVE}")
    output = ROOT / "output/commute-rider-v3-engine-review" / focus
    output.mkdir(parents=True, exist_ok=True)
    appdata = output / "appdata"
    appdata.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update({
        "APPDATA": str(appdata),
        "PICTURE_SHOP_SMOKE": "1",
        "PICTURE_SHOP_TEST_IDENTITY": "the-picture-shop-test-animation-review",
        "PICTURE_SHOP_ANIMATION_REVIEW": "1",
        "PICTURE_SHOP_ANIMATION_OUTPUT": str(output),
        "PICTURE_SHOP_ANIMATION_REVIEW_FOCUS": focus,
    })
    result = subprocess.run(
        [str(LOVE), str(ROOT)], cwd=ROOT, env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=600,
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0x08000000),
    )
    (output / "stdout.log").write_text(result.stdout, encoding="utf-8")
    (output / "stderr.log").write_text(result.stderr, encoding="utf-8")
    report = output / "engine-review.txt"
    if result.returncode != 0 or not report.is_file():
        raise SystemExit(
            f"LÖVE review failed (exit {result.returncode}). See {output} for logs."
        )
    text = report.read_text(encoding="utf-8")
    if not text.startswith("PASS:"):
        raise SystemExit(f"LÖVE review did not pass. See {report}.")
    print(text, end="")
    print(f"Capture folder: {output}")


if __name__ == "__main__":
    main()
