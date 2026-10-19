#!/usr/bin/env python3
"""Synthesize placeholder sound effects into assets/audio/sfx/.

Only writes the run event cue sounds listed in SOUNDS. Each is original and
generated here, so they are logged in assets/LICENSES.md as project originals.
Re-running produces identical files (fixed random seed).

Usage: python3 tools/make_placeholder_sfx.py
"""
import math
import pathlib
import random
import struct
import wave

RATE = 22050
OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "audio" / "sfx"


def envelope(t: float, length: float, attack: float = 0.01, release: float = 0.08) -> float:
    if t < attack:
        return t / attack
    if t > length - release:
        return max(0.0, (length - t) / release)
    return 1.0


def radio() -> list[float]:
    """A burst of band-limited static with two short call beeps: a radio crackling on."""
    rng = random.Random(7)
    length = 0.9
    samples = []
    low = 0.0
    high = 0.0
    for i in range(int(length * RATE)):
        t = i / RATE
        noise = rng.uniform(-1.0, 1.0)
        low += 0.25 * (noise - low)
        high = low - (high * 0.7)
        static = high * 0.5 * (0.6 + 0.4 * math.sin(t * 37.0))
        beep = 0.0
        if 0.25 < t < 0.37 or 0.45 < t < 0.57:
            beep = 0.35 * math.sin(2 * math.pi * 1250.0 * t)
        samples.append((static * (1.0 if t < 0.25 or t > 0.6 else 0.35) + beep) * envelope(t, length))
    return samples


def tick() -> list[float]:
    """A short wooden tick for the last seconds of the countdown."""
    length = 0.09
    return [
        0.7 * math.sin(2 * math.pi * 880.0 * (i / RATE)) * math.exp(-(i / RATE) * 60.0)
        for i in range(int(length * RATE))
    ]


def arrive() -> list[float]:
    """Two low, blunt horn honks: something big just pulled up."""
    length = 0.95
    samples = []
    for i in range(int(length * RATE)):
        t = i / RATE
        on = t < 0.35 or 0.5 < t < 0.85
        base = 196.0 if t < 0.42 else 175.0
        tone = sum(math.sin(2 * math.pi * base * k * t) / k for k in (1, 2, 3, 4))
        samples.append(0.35 * tone * (1.0 if on else 0.0) * envelope(t, length, 0.02, 0.1))
    return samples


def clear() -> list[float]:
    """Three rising soft notes: the coast is clear."""
    notes = [523.25, 659.25, 783.99]
    step = 0.16
    length = step * len(notes) + 0.25
    samples = []
    for i in range(int(length * RATE)):
        t = i / RATE
        value = 0.0
        for index, freq in enumerate(notes):
            start = index * step
            if t >= start:
                local = t - start
                value += 0.3 * math.sin(2 * math.pi * freq * local) * math.exp(-local * 6.0)
        samples.append(value * envelope(t, length))
    return samples


SOUNDS = {"radio": radio, "tick": tick, "arrive": arrive, "clear": clear}


def write(name: str, samples: list[float]) -> None:
    path = OUT / f"{name}.wav"
    peak = max(1e-6, max(abs(value) for value in samples))
    scale = min(1.0, 0.9 / peak)
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", int(value * scale * 32767)) for value in samples))
    print(f"wrote {path.relative_to(OUT.parent.parent.parent)}")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for sound_name, make in SOUNDS.items():
        write(sound_name, make())
