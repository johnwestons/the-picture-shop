"""Generate The Picture Shop's foley-style sound palette.

The cues combine deterministic synthesis with transformed, Creative Commons
recordings listed in ``assets/audio/source_manifest.json``.  Source files are
not silently optional: every required byte count and SHA-256 digest is checked
before generation so a clean build either reproduces the palette or fails with
an actionable error.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import random
import struct
import wave
from pathlib import Path


RATE = 44_100
TAU = math.tau
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "audio" / "sfx"
SOURCE_MANIFEST = ROOT / "assets" / "audio" / "source_manifest.json"
DEFAULT_SOURCE_ROOT = ROOT.parent / "Mouse Frontier 8.10" / "sounds" / "soundEffects"
SOURCE_ROOT = DEFAULT_SOURCE_ROOT
RNG = random.Random(260825)


def load_source_manifest() -> dict:
    return json.loads(SOURCE_MANIFEST.read_text(encoding="utf-8"))


def validate_sources(source_root: Path, manifest: dict) -> None:
    problems = []
    for item in manifest["sources"]:
        path = source_root / Path(item["relativePath"])
        if not path.is_file():
            problems.append(f"missing {item['relativePath']}")
            continue
        size = path.stat().st_size
        if size != item["bytes"]:
            problems.append(
                f"size mismatch for {item['relativePath']}: expected {item['bytes']}, got {size}"
            )
            continue
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest != item["sha256"]:
            problems.append(
                f"SHA-256 mismatch for {item['relativePath']}: expected {item['sha256']}, got {digest}"
            )
    if problems:
        detail = "\n  - ".join(problems)
        raise SystemExit(
            "Audio source validation failed. Set --source-root or "
            "PICTURE_SHOP_AUDIO_SOURCES to the licensed source directory.\n  - " + detail
        )


def samples(seconds: float) -> int:
    return max(1, round(seconds * RATE))


def blank(seconds: float) -> list[float]:
    return [0.0] * samples(seconds)


def add(output: list[float], source: list[float], offset: float = 0.0,
        level: float = 1.0) -> None:
    start = round(offset * RATE)
    needed = start + len(source)
    if needed > len(output):
        output.extend([0.0] * (needed - len(output)))
    for index, value in enumerate(source):
        output[start + index] += value * level


def mix(seconds: float, *tracks: tuple[list[float], float, float]) -> list[float]:
    output = blank(seconds)
    for source, offset, level in tracks:
        add(output, source, offset, level)
    return output


def white(seconds: float) -> list[float]:
    return [RNG.uniform(-1.0, 1.0) for _ in range(samples(seconds))]


def recording(relative_path: str, start: float = 0.0,
              duration: float | None = None) -> list[float]:
    """Load, downmix, and resample a PCM WAV from the sister project."""
    path = SOURCE_ROOT / relative_path
    if not path.exists():
        raise FileNotFoundError(f"Required audio source is missing: {path}")
    try:
        with wave.open(str(path), "rb") as source:
            channels = source.getnchannels()
            width = source.getsampwidth()
            source_rate = source.getframerate()
            source.setpos(min(source.getnframes(), round(start * source_rate)))
            frame_count = (source.getnframes() - source.tell() if duration is None
                           else min(source.getnframes() - source.tell(), round(duration * source_rate)))
            raw = source.readframes(frame_count)
        if width == 1:
            decoded = [(value - 128) / 128.0 for value in raw]
        elif width == 2:
            decoded = [value / 32768.0 for value in struct.unpack(f"<{len(raw) // 2}h", raw)]
        elif width == 3:
            decoded = []
            for index in range(0, len(raw), 3):
                value = raw[index] | raw[index + 1] << 8 | raw[index + 2] << 16
                if value & 0x800000:
                    value -= 1 << 24
                decoded.append(value / 8388608.0)
        else:
            return []
    except wave.Error:
        # Mouse Frontier's menu click is IEEE float WAV (format tag 3).
        data = path.read_bytes()
        cursor, fmt, raw = 12, None, b""
        while cursor + 8 <= len(data):
            chunk_id = data[cursor:cursor + 4]
            chunk_size = struct.unpack_from("<I", data, cursor + 4)[0]
            chunk = data[cursor + 8:cursor + 8 + chunk_size]
            if chunk_id == b"fmt ":
                fmt = struct.unpack_from("<HHIIHH", chunk)
            elif chunk_id == b"data":
                raw = chunk
            cursor += 8 + chunk_size + chunk_size % 2
        if not fmt or fmt[0] != 3 or fmt[5] != 32 or not raw:
            return []
        _, channels, source_rate, _, _, _ = fmt
        all_values = list(struct.unpack(f"<{len(raw) // 4}f", raw))
        first = round(start * source_rate) * channels
        count = (len(all_values) - first if duration is None
                 else min(len(all_values) - first, round(duration * source_rate) * channels))
        decoded = all_values[first:first + count]
    mono = [sum(decoded[index:index + channels]) / channels
            for index in range(0, len(decoded), channels)]
    if source_rate == RATE or not mono:
        return mono
    output_length = round(len(mono) * RATE / source_rate)
    output = []
    for index in range(output_length):
        position = index * source_rate / RATE
        left = min(len(mono) - 1, int(position))
        right = min(len(mono) - 1, left + 1)
        fraction = position - left
        output.append(mono[left] * (1.0 - fraction) + mono[right] * fraction)
    return output


def set_peak(source: list[float], peak: float) -> list[float]:
    maximum = max((abs(value) for value in source), default=0.0)
    return ([value * peak / maximum for value in source] if maximum else source)


def lowpass(source: list[float], cutoff: float) -> list[float]:
    coefficient = 1.0 - math.exp(-TAU * cutoff / RATE)
    prior = 0.0
    output = []
    for value in source:
        prior += coefficient * (value - prior)
        output.append(prior)
    return output


def highpass(source: list[float], cutoff: float) -> list[float]:
    low = lowpass(source, cutoff)
    return [value - base for value, base in zip(source, low)]


def band_noise(seconds: float, low: float, high: float) -> list[float]:
    return lowpass(highpass(white(seconds), low), high)


def fade(source: list[float], attack: float, release: float,
         curve: float = 1.8) -> list[float]:
    a, r, length = samples(attack), samples(release), len(source)
    output = []
    for index, value in enumerate(source):
        onset = min(1.0, index / a) ** curve
        tail = min(1.0, (length - 1 - index) / r) ** curve
        output.append(value * onset * tail)
    return output


def decay(source: list[float], seconds: float, power: float = 2.0) -> list[float]:
    release = max(1, samples(seconds))
    return [value * max(0.0, 1.0 - index / release) ** power
            for index, value in enumerate(source)]


def oscillator(seconds: float, frequency: float, roughness: float = 0.0,
               harmonic: float = 0.0) -> list[float]:
    output, phase = [], RNG.random()
    drift = lowpass(white(seconds), 7.0)
    for index in range(samples(seconds)):
        freq = frequency * (1.0 + roughness * drift[index])
        phase += freq / RATE
        output.append(math.sin(TAU * phase) + harmonic * math.sin(TAU * phase * 2.003))
    return output


def sweep(seconds: float, start: float, end: float, roughness: float = 0.0) -> list[float]:
    output, phase, length = [], RNG.random(), samples(seconds)
    drift = lowpass(white(seconds), 12.0)
    for index in range(length):
        progress = index / max(1, length - 1)
        frequency = start * (end / start) ** progress
        frequency *= 1.0 + roughness * drift[index]
        phase += frequency / RATE
        output.append(math.sin(TAU * phase))
    return output


def resonant_hit(seconds: float, fundamental: float, material: str = "metal") -> list[float]:
    if material == "metal":
        ratios = (1.0, 1.39, 2.17, 2.91, 3.83, 5.37)
        damping = (19.0, 27.0, 38.0, 52.0, 70.0, 92.0)
    elif material == "wood":
        ratios = (1.0, 1.78, 2.73, 4.31)
        damping = (38.0, 52.0, 71.0, 96.0)
    else:
        ratios = (1.0, 1.87, 3.29)
        damping = (68.0, 91.0, 125.0)
    length = samples(seconds)
    phases = [RNG.uniform(0.0, TAU) for _ in ratios]
    output = []
    for index in range(length):
        time = index / RATE
        value = 0.0
        for mode, (ratio, damp) in enumerate(zip(ratios, damping)):
            value += (math.sin(TAU * fundamental * ratio * time + phases[mode])
                      * math.exp(-damp * time) / (1 + mode * 0.42))
        output.append(value)
    exciter = decay(band_noise(min(seconds, 0.035), 180, 9000), 0.035, 3.5)
    add(output, exciter, 0.0, 0.8)
    return output


def room(source: list[float], size: float = 0.35, wet: float = 0.16) -> list[float]:
    output = source.copy()
    reflections = ((0.019, 0.55), (0.033, 0.34), (0.051, 0.22), (0.079, 0.12))
    softened = lowpass(source, 4200 - size * 1400)
    for delay, amount in reflections:
        add(output, softened, delay * (0.7 + size), wet * amount)
    return output


def dc_block(source: list[float]) -> list[float]:
    output, prior_input, prior_output = [], 0.0, 0.0
    for value in source:
        current = value - prior_input + 0.995 * prior_output
        output.append(current)
        prior_input, prior_output = value, current
    return output


def master(source: list[float], peak: float) -> list[float]:
    source = dc_block(source)
    maximum = max((abs(value) for value in source), default=1.0)
    scale = peak / maximum if maximum else 1.0
    return [math.tanh(value * scale * 1.15) / math.tanh(1.15) * peak for value in source]


def seamless(source: list[float], seconds: float, crossfade: float = 0.20) -> list[float]:
    target, overlap = samples(seconds), samples(crossfade)
    if len(source) < target + overlap:
        raise ValueError("loop render needs a crossfade tail")
    output = source[:target]
    for index in range(overlap):
        blend = index / max(1, overlap - 1)
        output[index] = source[target + index] * (1.0 - blend) + source[index] * blend
    return output


def motor(seconds: float, fundamental: float, rpm_pulse: float,
          ramp: tuple[float, float] = (1.0, 1.0)) -> list[float]:
    length = samples(seconds)
    phase, pulse_phase = RNG.random(), RNG.random()
    grit = lowpass(white(seconds), 1900)
    drift = lowpass(white(seconds), 5.0)
    output = []
    for index in range(length):
        progress = index / max(1, length - 1)
        speed = ramp[0] + (ramp[1] - ramp[0]) * min(1.0, progress * 1.3)
        phase += fundamental * speed * (1.0 + drift[index] * 0.025) / RATE
        pulse_phase += rpm_pulse * speed / RATE
        body = (math.sin(TAU * phase) + 0.45 * math.sin(TAU * phase * 2.01)
                + 0.19 * math.sin(TAU * phase * 3.98))
        pulse = 0.72 + 0.28 * math.sin(TAU * pulse_phase)
        output.append(body * pulse * 0.32 + grit[index] * 0.16 * speed)
    return output


def plastic_click(heavy: bool = False) -> list[float]:
    duration = 0.115 if heavy else 0.075
    result = blank(duration)
    add(result, resonant_hit(duration, 310 if heavy else 520, "plastic"), 0, 0.8)
    add(result, decay(band_noise(0.025, 900, 7800), 0.025, 3.0), 0, 0.5)
    add(result, resonant_hit(0.045, 430 if heavy else 720, "plastic"), 0.028, 0.32)
    return result


def build_legacy_cues() -> dict[str, list[float]]:
    cues: dict[str, list[float]] = {}
    cues["ui_click"] = room(plastic_click(), 0.12, 0.07)
    cues["ui_confirm"] = mix(0.34,
        (plastic_click(), 0.0, 0.70),
        (decay(band_noise(0.14, 750, 5200), 0.14, 3.2), 0.072, 0.24),
        (resonant_hit(0.10, 180, "wood"), 0.078, 0.18))
    cues["ui_error"] = mix(0.31,
        (plastic_click(True), 0.0, 0.8),
        (resonant_hit(0.18, 92, "wood"), 0.045, 0.64),
        (decay(band_noise(0.19, 90, 900), 0.19), 0.04, 0.22))
    drawer = mix(0.56,
        (fade(band_noise(0.18, 100, 2400), 0.002, 0.16), 0.0, 0.44),
        (resonant_hit(0.28, 118, "metal"), 0.04, 0.52),
        (decay(band_noise(0.17, 1300, 8200), 0.17, 2.8), 0.13, 0.28),
        (decay(band_noise(0.14, 1700, 9400), 0.14, 3.1), 0.19, 0.22),
        (resonant_hit(0.18, 205, "wood"), 0.34, 0.72))
    cues["cash_sale"] = room(drawer, 0.28, 0.14)
    completion = mix(0.68,
        (fade(band_noise(0.38, 180, 3600), 0.025, 0.30), 0.0, 0.28),
        (resonant_hit(0.22, 86, "wood"), 0.12, 0.78),
        (plastic_click(True), 0.26, 0.42),
        (decay(band_noise(0.22, 700, 5200), 0.22, 2.6), 0.28, 0.19))
    cues["job_complete"] = room(completion, 0.50, 0.19)

    door = blank(1.44)
    recorded_door = recording("doors/398750__anthousai__door-open-01.wav", 0, 1.24)
    add(door, set_peak(lowpass(recorded_door, 7200), 0.58), 0.02, 0.72)
    add(door, fade(motor(1.25, 38, 5.8), 0.08, 0.18), 0.06, 0.42)
    add(door, fade(band_noise(1.24, 55, 1300), 0.04, 0.16), 0.04, 0.52)
    for position, pitch, strength in ((0.02, 92, .65), (.27, 148, .23), (.49, 132, .20),
                                      (.72, 162, .20), (.95, 126, .24), (1.16, 78, .88)):
        add(door, resonant_hit(0.28, pitch, "metal"), position, strength)
    cues["loading_door"] = room(door, 0.72, 0.22)

    truck = blank(3.12)
    recorded_stop = recording(
        "train/trainArrive/854736__kevp888__260425_160902_fr_steam_train_stopping_at_st-valery.wav",
        14.45, 3.12)
    add(truck, set_peak(lowpass(highpass(recorded_stop, 38), 1450), 0.46), 0, 0.62)
    add(truck, fade(motor(2.82, 43, 5.1, (1.12, .86)), 0.12, 0.34), 0.0, 0.64)
    add(truck, fade(band_noise(2.75, 32, 700), 0.12, 0.30), 0.0, 0.30)
    for position in (0.36, 1.05):
        beep = fade(oscillator(0.25, 875, 0.008, 0.09), 0.008, 0.035)
        add(truck, beep, position, 0.24)
    add(truck, fade(band_noise(0.58, 400, 7600), 0.006, 0.50), 2.20, 0.68)
    add(truck, resonant_hit(0.38, 62, "metal"), 2.48, 0.70)
    cues["truck_arrival"] = room(truck, 0.82, 0.17)

    pickup = mix(0.48,
        (fade(band_noise(0.24, 90, 1700), 0.005, 0.20), 0.0, 0.46),
        (sweep(0.24, 110, 72, 0.03), 0.015, 0.30),
        (resonant_hit(0.22, 172, "metal"), 0.13, 0.58),
        (resonant_hit(0.20, 89, "wood"), 0.22, 0.70))
    cues["pallet_pickup"] = room(pickup, 0.46, 0.13)
    place = mix(0.43,
        (resonant_hit(0.26, 72, "wood"), 0.0, 0.95),
        (resonant_hit(0.23, 151, "metal"), 0.025, 0.47),
        (decay(band_noise(0.22, 70, 1850), 0.22), 0.02, 0.48),
        (resonant_hit(0.13, 230, "wood"), 0.12, 0.33))
    cues["pallet_place"] = room(place, 0.55, 0.15)

    clamp = mix(0.62,
        (fade(band_noise(0.37, 300, 7200), 0.006, 0.21), 0.0, 0.40),
        (sweep(0.34, 128, 65, 0.05), 0.0, 0.42),
        (resonant_hit(0.32, 78, "metal"), 0.27, 0.92),
        (resonant_hit(0.22, 224, "metal"), 0.285, 0.35))
    cues["cutter_clamp"] = room(clamp, 0.62, 0.17)
    cut = mix(0.78,
        (fade(band_noise(0.20, 900, 10500), 0.001, 0.15), 0.0, 0.82),
        (sweep(0.18, 390, 74, 0.02), 0.0, 0.58),
        (resonant_hit(0.39, 68, "metal"), 0.105, 0.93),
        (decay(band_noise(0.25, 120, 3500), 0.25, 2.4), 0.12, 0.52),
        (resonant_hit(0.23, 112, "wood"), 0.34, 0.38))
    recorded_slice = recording("slash/442903__qubodup__slash.wav", 0, 0.26)
    add(cut, set_peak(highpass(recorded_slice, 180), 0.68), 0.015, 0.58)
    cues["cutter_cut"] = room(cut, 0.73, 0.20)

    press_start = blank(1.82)
    add(press_start, fade(motor(1.72, 52, 7.0, (.28, 1.0)), 0.04, 0.24), 0, 0.70)
    add(press_start, fade(band_noise(1.65, 70, 2500), 0.04, 0.25), 0, 0.26)
    add(press_start, resonant_hit(0.31, 114, "metal"), 0.74, 0.55)
    add(press_start, resonant_hit(0.29, 168, "metal"), 1.29, 0.42)
    cues["press_start"] = room(press_start, 0.66, 0.16)
    press = blank(4.24)
    recorded_mechanism = recording(
        "train/trainTraveling/855304__kevp888__260426_112308_fr_steam_train_travelling.wav",
        105.0, 4.24)
    add(press, set_peak(lowpass(highpass(recorded_mechanism, 48), 2600), 0.34), 0, 0.46)
    add(press, motor(4.24, 71, 8.0), 0, 0.54)
    add(press, band_noise(4.24, 80, 2600), 0, 0.17)
    for position in [0.10 + 0.50 * index for index in range(9)]:
        add(press, resonant_hit(0.16, RNG.uniform(128, 168), "metal"), position, 0.28)
        add(press, decay(band_noise(0.10, 500, 6200), 0.10, 2.8), position + .055, 0.17)
    cues["press_running_loop"] = seamless(room(press, 0.64, 0.11), 4.0)

    wrapper = blank(3.18)
    add(wrapper, fade(motor(2.98, 57, 3.2, (.65, 1.0)), 0.10, 0.30), 0, 0.58)
    add(wrapper, fade(band_noise(2.91, 500, 9000), 0.12, 0.27), 0.03, 0.26)
    film = lowpass(highpass(white(2.72), 1250), 7200)
    modulation = [0.30 + 0.70 * abs(math.sin(TAU * 2.8 * i / RATE)) for i in range(len(film))]
    add(wrapper, [a * b for a, b in zip(film, modulation)], 0.13, 0.26)
    add(wrapper, resonant_hit(0.24, 128, "metal"), 2.67, 0.56)
    add(wrapper, plastic_click(True), 2.88, 0.46)
    cues["wrapper_cycle"] = room(wrapper, 0.58, 0.14)
    tool = mix(0.42,
        (resonant_hit(0.22, 230, "metal"), 0.0, 0.58),
        (decay(band_noise(0.16, 850, 6800), 0.16, 3.0), 0.045, 0.32),
        (resonant_hit(0.16, 108, "metal"), 0.17, 0.52))
    cues["maintenance_tool"] = room(tool, 0.46, 0.18)

    ambience = blank(6.24)
    recorded_room = recording(
        "train/trainTraveling/855304__kevp888__260426_112308_fr_steam_train_travelling.wav",
        103.0, 6.24)
    add(ambience, set_peak(lowpass(highpass(recorded_room, 35), 1600), 0.16), 0, 0.34)
    add(ambience, lowpass(white(6.24), 680), 0, 0.26)
    add(ambience, oscillator(6.24, 59.7, 0.018, 0.28), 0, 0.20)
    add(ambience, band_noise(6.24, 1000, 4400), 0, 0.045)
    for position, pitch in ((1.72, 92), (4.41, 137)):
        add(ambience, room(resonant_hit(0.48, pitch, "metal"), 0.82, 0.24), position, 0.07)
    cues["warehouse_ambience_loop"] = seamless(ambience, 6.0)

    peaks = {
        "ui_click": .46, "ui_confirm": .56, "ui_error": .62,
        "cash_sale": .70, "job_complete": .68, "loading_door": .72,
        "truck_arrival": .68, "pallet_pickup": .70, "pallet_place": .74,
        "cutter_clamp": .76, "cutter_cut": .80, "press_start": .72,
        "press_running_loop": .48, "wrapper_cycle": .62,
        "maintenance_tool": .68, "warehouse_ambience_loop": .22,
    }
    return {name: master(source, peaks[name]) for name, source in cues.items()}


def crop(source: list[float], start: float, duration: float) -> list[float]:
    first = max(0, round(start * RATE))
    return source[first:first + samples(duration)]


def build_cues() -> dict[str, list[float]]:
    """Build the shipping palette entirely from recorded foley and noise."""
    click = recording("menu/733769__slv443__click-menu.wav")
    door = recording("doors/398750__anthousai__door-open-01.wav")
    sliding = recording("train/trainDoor/134715__joedeshon__sliding_door_opening.wav")
    step_left = recording("walkingSteps/386519__glennm__left_foot_stone.wav")
    step_right = recording("walkingSteps/386525__glennm__right_foot_stone.wav")
    gravel_left = recording("walkingSteps/386522__glennm__left_foot_gravel.wav")
    slash = recording("slash/442903__qubodup__slash.wav")
    train_stop = recording(
        "train/trainArrive/854736__kevp888__260425_160902_fr_steam_train_stopping_at_st-valery.wav",
        14.45, 4.20)
    train_run = recording(
        "train/trainTraveling/855304__kevp888__260426_112308_fr_steam_train_travelling.wav",
        103.0, 8.30)

    # Interface: physical switch and desk-contact sounds, never pitched tones.
    cues: dict[str, list[float]] = {}
    cues["ui_click"] = master(set_peak(click, .34), .34)
    confirm = blank(.18)
    add(confirm, set_peak(click, .30), 0, 1)
    add(confirm, set_peak(crop(step_left, 0, .08), .12), .055, 1)
    cues["ui_confirm"] = master(confirm, .38)
    error = blank(.24)
    add(error, set_peak(lowpass(step_right, 1200), .42), 0, 1)
    add(error, set_peak(lowpass(crop(door, .72, .16), 900), .24), .07, 1)
    cues["ui_error"] = master(error, .45)

    # Desk feedback: drawer/latch movement, paper friction, and a muted knock.
    cash = blank(.66)
    add(cash, set_peak(crop(door, .22, .42), .48), 0, 1)
    add(cash, set_peak(highpass(gravel_left, 850), .23), .24, 1)
    add(cash, set_peak(lowpass(step_left, 1300), .34), .39, 1)
    cues["cash_sale"] = master(cash, .58)
    done = blank(.62)
    add(done, set_peak(fade(band_noise(.34, 240, 4300), .015, .25), .18), 0, 1)
    add(done, set_peak(lowpass(step_right, 1500), .46), .20, 1)
    add(done, set_peak(click, .24), .39, 1)
    cues["job_complete"] = master(done, .56)

    # Warehouse mechanisms use field recordings as their dominant layers.
    loading = blank(1.50)
    add(loading, set_peak(lowpass(door, 7600), .62), 0, 1)
    add(loading, set_peak(crop(sliding, .08, 1.35), .35), .06, .72)
    add(loading, fade(band_noise(1.30, 80, 1450), .02, .18), .04, .18)
    cues["loading_door"] = master(loading, .68)

    truck = blank(3.55)
    add(truck, set_peak(lowpass(highpass(train_stop, 32), 3200), .58), 0, 1)
    add(truck, fade(band_noise(3.25, 38, 780), .10, .32), 0, .14)
    add(truck, set_peak(lowpass(step_right, 650), .25), 2.86, 1)
    cues["truck_arrival"] = master(truck, .62)

    pickup = blank(.43)
    add(pickup, set_peak(lowpass(gravel_left, 2800), .35), 0, 1)
    add(pickup, set_peak(lowpass(step_left, 1100), .48), .12, 1)
    add(pickup, fade(band_noise(.20, 120, 1600), .002, .16), .10, .16)
    cues["pallet_pickup"] = master(pickup, .64)
    place = blank(.42)
    add(place, set_peak(lowpass(step_right, 1600), .56), 0, 1)
    add(place, set_peak(lowpass(step_left, 950), .37), .07, 1)
    add(place, set_peak(crop(gravel_left, 0, .14), .19), .13, 1)
    cues["pallet_place"] = master(place, .68)

    clamp = blank(.56)
    add(clamp, set_peak(crop(sliding, .32, .38), .37), 0, 1)
    add(clamp, fade(band_noise(.32, 260, 6200), .004, .22), 0, .18)
    add(clamp, set_peak(lowpass(step_right, 1150), .62), .25, 1)
    cues["cutter_clamp"] = master(clamp, .72)
    cut = blank(.68)
    add(cut, set_peak(highpass(slash, 110), .68), 0, 1)
    add(cut, set_peak(lowpass(step_right, 1000), .56), .12, 1)
    add(cut, set_peak(crop(sliding, 1.76, .24), .26), .28, 1)
    cues["cutter_cut"] = master(cut, .76)

    press_start = blank(1.72)
    add(press_start, set_peak(lowpass(highpass(crop(train_stop, 0, 1.62), 35), 2800), .55), 0, 1)
    add(press_start, fade(band_noise(1.60, 60, 1700), .08, .20), 0, .12)
    add(press_start, set_peak(lowpass(step_left, 900), .30), 1.22, 1)
    cues["press_start"] = master(press_start, .66)
    press = blank(4.24)
    add(press, set_peak(lowpass(highpass(crop(train_run, 1.0, 4.24), 42), 3400), .46), 0, 1)
    add(press, band_noise(4.24, 75, 2100), 0, .055)
    for position in (.44, 1.43, 2.42, 3.41):
        add(press, set_peak(lowpass(step_left, 1800), .16), position, 1)
    cues["press_running_loop"] = master(seamless(press + press[:samples(.20)], 4.0), .45)

    wrapper = blank(3.10)
    add(wrapper, set_peak(lowpass(sliding, 5400), .48), 0, 1)
    add(wrapper, fade(band_noise(2.86, 850, 8800), .08, .24), .10, .12)
    add(wrapper, set_peak(gravel_left, .20), 2.60, 1)
    cues["wrapper_cycle"] = master(wrapper, .56)
    tool = blank(.38)
    add(tool, set_peak(crop(door, .68, .28), .40), 0, 1)
    add(tool, set_peak(highpass(step_left, 520), .37), .075, 1)
    cues["maintenance_tool"] = master(tool, .58)

    ambience = blank(6.24)
    add(ambience, set_peak(lowpass(highpass(crop(train_run, 0, 6.24), 30), 1350), .13), 0, 1)
    add(ambience, lowpass(white(6.24), 520), 0, .035)
    add(ambience, band_noise(6.24, 900, 4300), 0, .012)
    cues["warehouse_ambience_loop"] = master(seamless(ambience, 6.0), .18)
    return cues


def write_wav(path: Path, source: list[float]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    frames = bytearray()
    for value in source:
        value = max(-1.0, min(1.0, value))
        frames.extend(round(value * 32767).to_bytes(2, "little", signed=True))
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(frames)


def preview(cues: dict[str, list[float]]) -> list[float]:
    order = [
        "ui_click", "ui_confirm", "ui_error", "cash_sale", "job_complete",
        "loading_door", "truck_arrival", "pallet_pickup", "pallet_place",
        "cutter_clamp", "cutter_cut", "press_start", "press_running_loop",
        "wrapper_cycle", "maintenance_tool", "warehouse_ambience_loop",
    ]
    output: list[float] = []
    gap = blank(0.34)
    for name in order:
        excerpt = cues[name]
        if name == "warehouse_ambience_loop":
            excerpt = excerpt[:samples(3.0)]
        output.extend(excerpt)
        output.extend(gap)
    return output


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source-root", type=Path,
        default=Path(os.environ.get("PICTURE_SHOP_AUDIO_SOURCES", DEFAULT_SOURCE_ROOT)),
        help="Directory containing the relative source paths in source_manifest.json",
    )
    parser.add_argument(
        "--verify-only", action="store_true",
        help="Validate licensed source files without generating cues",
    )
    parser.add_argument(
        "--preview", action="store_true",
        help="Also create the ignored picture_shop_sfx_preview.wav audition reel",
    )
    return parser.parse_args()


def main() -> None:
    global SOURCE_ROOT
    args = parse_args()
    SOURCE_ROOT = args.source_root.resolve()
    manifest = load_source_manifest()
    validate_sources(SOURCE_ROOT, manifest)
    if args.verify_only:
        print(f"Verified {len(manifest['sources'])} licensed audio sources in {SOURCE_ROOT}")
        return
    cues = build_cues()
    for name, source in cues.items():
        write_wav(OUT / f"{name}.wav", source)
    if args.preview:
        write_wav(OUT / "picture_shop_sfx_preview.wav", preview(cues))
    print(f"Generated {len(cues)} attributed foley-style cues in {OUT}")


if __name__ == "__main__":
    main()
