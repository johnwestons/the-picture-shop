"""Install Sound Studio edited Grandpa takes in the packaged dialogue manifest.

The original takes and edit metadata remain in assets/audio/voices/grandpa/.
Only one edited WAV per emotion is copied to the content-addressed runtime set.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/audio/voices/grandpa"
DEST = ROOT / "assets/audio/dialogue"
EMOTIONS = (
    "neutral", "greeting", "happy", "curious", "agreement", "disagreement",
    "surprised", "annoyed", "thanks", "goodbye", "worried", "sad",
)


def main() -> None:
    clips: dict[str, str] = {}
    for emotion in EMOTIONS:
        takes = sorted((SOURCE / emotion).glob("edit-*.wav"))
        if len(takes) != 1:
            raise RuntimeError(f"Expected one edited Grandpa {emotion} clip; found {len(takes)}")
        payload = takes[0].read_bytes()
        digest = hashlib.sha256(payload).hexdigest()
        path = f"assets/audio/dialogue/{digest}.wav"
        (ROOT / path).write_bytes(payload)
        clips[emotion] = path

    lua_path = DEST / "manifest.lua"
    lua = lua_path.read_text(encoding="utf-8")
    if '["grandpa"]' in lua:
        raise RuntimeError("Grandpa is already in the dialogue manifest")
    entry = ',["grandpa"]={' + ",".join(
        f'["{emotion}"]="{clips[emotion]}"' for emotion in EMOTIONS
    ) + "}"
    lua = lua.rstrip()
    if not lua.endswith("}"):
        raise RuntimeError("Unexpected dialogue Lua manifest format")
    lua = lua[:-1] + entry + "}\n"
    lua_path.write_text(lua, encoding="utf-8", newline="\n")

    json_path = DEST / "manifest.json"
    manifest = json.loads(json_path.read_text(encoding="utf-8"))
    manifest["files"].extend(clips.values())
    manifest["luaSha256"] = hashlib.sha256(lua.encode("utf-8")).hexdigest()
    json_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"Installed {len(clips)} Grandpa voice clips")


if __name__ == "__main__":
    main()
