#!/usr/bin/env python3
"""MonoKnight用のオリジナルBGM・SEを標準ライブラリだけで生成する。"""

from __future__ import annotations

import math
import struct
import wave
from pathlib import Path


SAMPLE_RATE = 22_050
OUTPUT_DIR = Path(__file__).resolve().parents[1] / "MonoKnightApp" / "Audio"


def envelope(index: int, length: int, attack: float = 0.04, release: float = 0.12) -> float:
    position = index / max(length - 1, 1)
    attack_level = min(position / max(attack, 0.001), 1.0)
    release_level = min((1.0 - position) / max(release, 0.001), 1.0)
    return min(attack_level, release_level)


def tone(frequency: float, duration: float, volume: float = 0.4, *, shimmer: bool = False) -> list[float]:
    length = int(SAMPLE_RATE * duration)
    samples: list[float] = []
    for index in range(length):
        time = index / SAMPLE_RATE
        value = math.sin(2 * math.pi * frequency * time)
        value += 0.35 * math.sin(2 * math.pi * frequency * 2 * time)
        if shimmer:
            value += 0.18 * math.sin(2 * math.pi * frequency * 3.01 * time)
        samples.append(value * volume * envelope(index, length))
    return samples


def glide(start: float, end: float, duration: float, volume: float = 0.42) -> list[float]:
    length = int(SAMPLE_RATE * duration)
    phase = 0.0
    samples: list[float] = []
    for index in range(length):
        ratio = index / max(length - 1, 1)
        frequency = start + (end - start) * ratio
        phase += 2 * math.pi * frequency / SAMPLE_RATE
        samples.append(math.sin(phase) * volume * envelope(index, length, 0.025, 0.18))
    return samples


def silence(duration: float) -> list[float]:
    return [0.0] * int(SAMPLE_RATE * duration)


def mix(*tracks: list[float]) -> list[float]:
    length = max((len(track) for track in tracks), default=0)
    result = [0.0] * length
    for track in tracks:
        for index, value in enumerate(track):
            result[index] += value
    peak = max((abs(value) for value in result), default=1.0)
    scale = min(0.92 / max(peak, 0.001), 1.0)
    return [value * scale for value in result]


def overlay(base: list[float], addition: list[float], offset_seconds: float) -> None:
    offset = int(offset_seconds * SAMPLE_RATE)
    for index, value in enumerate(addition):
        destination = offset + index
        if destination < len(base):
            base[destination] += value


def write_wav(name: str, samples: list[float]) -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    peak = max((abs(value) for value in samples), default=1.0)
    scale = min(0.94 / max(peak, 0.001), 1.0)
    pcm = b"".join(
        struct.pack("<h", int(max(-1.0, min(1.0, value * scale)) * 32_767))
        for value in samples
    )
    with wave.open(str(OUTPUT_DIR / name), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(SAMPLE_RATE)
        output.writeframes(pcm)


def make_loop(notes: list[float], bass: list[float], *, sparkle: bool) -> list[float]:
    duration = 12.0
    result = silence(duration)
    beat = 0.75
    for index in range(16):
        overlay(result, tone(notes[index % len(notes)], 0.64, 0.18, shimmer=sparkle), index * beat)
        overlay(result, tone(bass[index % len(bass)], 1.35, 0.10), index * beat)
        if sparkle and index % 2 == 1:
            overlay(result, tone(notes[(index + 2) % len(notes)] * 2, 0.22, 0.07, shimmer=True), index * beat + 0.42)
    fade = int(SAMPLE_RATE * 0.5)
    for index in range(fade):
        result[index] *= index / fade
        result[-index - 1] *= index / fade
    return result


def main() -> None:
    write_wav("bgm_title.wav", make_loop([261.63, 329.63, 392.00, 493.88], [130.81, 164.81], sparkle=True))
    write_wav("bgm_tower.wav", make_loop([293.66, 349.23, 440.00, 392.00], [146.83, 174.61], sparkle=True))
    write_wav("bgm_deep_tower.wav", make_loop([220.00, 261.63, 311.13, 293.66], [110.00, 130.81], sparkle=False))

    effects = {
        "se_waddle.wav": mix(tone(210, 0.09, 0.34), glide(310, 250, 0.09, 0.18)),
        "se_belly_slide.wav": glide(760, 260, 0.34, 0.42),
        "se_flutter_jump.wav": mix(glide(320, 820, 0.28, 0.34), tone(1040, 0.14, 0.12, shimmer=True)),
        "se_warp.wav": mix(glide(280, 1350, 0.42, 0.30), glide(920, 210, 0.42, 0.20)),
        "se_fall.wav": glide(520, 90, 0.48, 0.44),
        "se_damage.wav": mix(glide(190, 80, 0.24, 0.46), tone(74, 0.22, 0.26)),
        "se_pickup.wav": mix(tone(659.25, 0.17, 0.28, shimmer=True), [*silence(0.10), *tone(987.77, 0.20, 0.30, shimmer=True)]),
        "se_orca_warning.wav": mix(glide(150, 105, 0.55, 0.40), tone(55, 0.55, 0.24)),
        "se_decision.wav": mix(tone(523.25, 0.18, 0.26), [*silence(0.12), *tone(783.99, 0.30, 0.32, shimmer=True)]),
        "se_invalid.wav": mix(tone(145, 0.13, 0.34), [*silence(0.09), *tone(118, 0.14, 0.32)]),
        "se_heal.wav": mix(glide(420, 880, 0.40, 0.28), tone(1046.50, 0.24, 0.16, shimmer=True)),
    }
    for name, samples in effects.items():
        write_wav(name, samples)

    print(f"Generated {3 + len(effects)} files in {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
