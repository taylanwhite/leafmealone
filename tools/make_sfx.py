#!/usr/bin/env python3
"""Synthesize the game's sound effects into assets/audio/sfx/.

Every sound is generated here from noise, clicks, and tones, so they are
project originals: nothing downloaded, nothing AI-generated. Seeds are fixed,
so re-running writes identical files. Sounds the player hears constantly come
in a few variants (name_1.wav, name_2.wav, ...) that audio/sfx.gd picks between.

Usage: python3 tools/make_sfx.py            write everything
       python3 tools/make_sfx.py step rake  write only those
"""
import math
import pathlib
import random
import struct
import sys
import wave

RATE = 44100
OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "audio" / "sfx"


# ---------------------------------------------------------------- building blocks

def silence(seconds: float) -> list[float]:
    return [0.0] * int(seconds * RATE)


def mix_into(target: list[float], source: list[float], at_seconds: float, gain: float = 1.0) -> None:
    start = int(at_seconds * RATE)
    for index, value in enumerate(source):
        if start + index < len(target):
            target[start + index] += value * gain


def noise(rng: random.Random, seconds: float) -> list[float]:
    return [rng.uniform(-1.0, 1.0) for _ in range(int(seconds * RATE))]


def lowpass(samples: list[float], cutoff: float) -> list[float]:
    alpha = 1.0 - math.exp(-2.0 * math.pi * cutoff / RATE)
    out, state = [], 0.0
    for value in samples:
        state += alpha * (value - state)
        out.append(state)
    return out


def highpass(samples: list[float], cutoff: float) -> list[float]:
    low = lowpass(samples, cutoff)
    return [value - smooth for value, smooth in zip(samples, low)]


def bandpass(samples: list[float], center: float, q: float = 1.0) -> list[float]:
    """RBJ biquad band-pass, constant peak gain."""
    w = 2.0 * math.pi * center / RATE
    alpha = math.sin(w) / (2.0 * q)
    b0, b1, b2 = alpha, 0.0, -alpha
    a0, a1, a2 = 1.0 + alpha, -2.0 * math.cos(w), 1.0 - alpha
    out = []
    x1 = x2 = y1 = y2 = 0.0
    for x in samples:
        y = (b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0
        out.append(y)
        x2, x1, y2, y1 = x1, x, y1, y
    return out


def decay(samples: list[float], rate: float) -> list[float]:
    return [value * math.exp(-rate * index / RATE) for index, value in enumerate(samples)]


def shape(samples: list[float], attack: float, release: float) -> list[float]:
    length = len(samples)
    attack_n = max(1, int(attack * RATE))
    release_n = max(1, int(release * RATE))
    out = []
    for index, value in enumerate(samples):
        gain = 1.0
        if index < attack_n:
            gain = index / attack_n
        if index > length - release_n:
            gain = min(gain, (length - index) / release_n)
        out.append(value * gain)
    return out


def click(rng: random.Random, center: float, width: float = 0.012, decay_rate: float = 700.0) -> list[float]:
    """One tiny crackle: a burst of band-passed noise that dies fast."""
    return decay(bandpass(noise(rng, width), center, 1.4), decay_rate)


def thud(freq: float, seconds: float, decay_rate: float) -> list[float]:
    """A low body hit: a sine that drops in pitch as it dies."""
    out, phase = [], 0.0
    for index in range(int(seconds * RATE)):
        t = index / RATE
        phase += 2.0 * math.pi * freq * (1.0 + 0.6 * math.exp(-t * 40.0)) / RATE
        out.append(math.sin(phase) * math.exp(-t * decay_rate))
    return out


# ---------------------------------------------------------------- sounds

def step(variant: int) -> list[float]:
    """A footstep into a pile of dry leaves: a soft thud under a spray of crunches."""
    rng = random.Random(100 + variant)
    out = silence(0.22)
    mix_into(out, thud(70.0 + variant * 6.0, 0.12, 38.0), 0.0, 0.45)
    bed = decay(bandpass(noise(rng, 0.2), 3200.0, 0.7), 22.0)
    mix_into(out, bed, 0.0, 0.25)
    for _ in range(rng.randint(26, 40)):
        at = abs(rng.gauss(0.035, 0.03))
        mix_into(out, click(rng, rng.uniform(2200.0, 6500.0)), at, rng.uniform(0.25, 0.9))
    return out


def rake(variant: int) -> list[float]:
    """One rake stroke: tines chattering over ground and a swell of rustling leaves."""
    rng = random.Random(200 + variant)
    length = 0.5 + variant * 0.04
    out = silence(length)
    rustle = bandpass(noise(rng, length), 1800.0 + variant * 200.0, 0.5)
    wobble = [0.6 + 0.4 * math.sin(2.0 * math.pi * 7.0 * i / RATE + variant) for i in range(len(rustle))]
    mix_into(out, shape([r * w for r, w in zip(rustle, wobble)], 0.06, 0.18), 0.0, 0.5)
    whoosh = shape(lowpass(noise(rng, length), 350.0), 0.1, 0.2)
    mix_into(out, whoosh, 0.0, 1.4)
    t = 0.03
    while t < length - 0.12:
        mix_into(out, click(rng, rng.uniform(2600.0, 4800.0), 0.008, 900.0), t, rng.uniform(0.2, 0.55))
        t += rng.uniform(0.012, 0.03)
    return out


def bag(variant: int) -> list[float]:
    """Stuffing a leaf bag: plastic crinkle in three shakes, then the full bag set down."""
    rng = random.Random(300 + variant)
    out = silence(0.75)
    for shake_at in (0.0, 0.17, 0.33):
        bed = shape(highpass(noise(rng, 0.13), 2500.0), 0.01, 0.07)
        mix_into(out, bed, shake_at, 0.3)
        for _ in range(rng.randint(14, 22)):
            mix_into(out, click(rng, rng.uniform(4000.0, 9000.0), 0.006, 1300.0), shake_at + rng.uniform(0.0, 0.12), rng.uniform(0.3, 1.0))
    mix_into(out, thud(85.0, 0.2, 22.0), 0.52, 0.6)
    mix_into(out, decay(bandpass(noise(rng, 0.2), 1500.0, 0.6), 18.0), 0.52, 0.35)
    return out


def engine(rng: random.Random, seconds: float, start_hz: float, end_hz: float, brightness: float) -> list[float]:
    """A petrol engine pulling away: firing pulses with harmonics, revving up, fading off."""
    out, phase = [], 0.0
    exhaust = lowpass(noise(rng, seconds), 500.0)
    count = int(seconds * RATE)
    for index in range(count):
        t = index / RATE
        progress = t / seconds
        rev = start_hz + (end_hz - start_hz) * (1.0 - math.exp(-progress * 3.0))
        phase += 2.0 * math.pi * rev / RATE
        # Uneven firing: strong odd harmonics, a bit of second and fourth.
        tone = (math.sin(phase) + 0.55 * math.sin(2 * phase + 0.4) + 0.7 * math.sin(3 * phase)
                + 0.3 * math.sin(4 * phase + 1.1) + 0.35 * math.sin(5 * phase) * brightness)
        pulse = 0.65 + 0.35 * math.sin(phase * 0.5)
        sample = tone * 0.3 * pulse + exhaust[index] * 2.2 * pulse
        fade_in = min(1.0, t / 0.15)
        fade_out = min(1.0, (seconds - t) / (seconds * 0.45))
        out.append(sample * fade_in * fade_out)
    return lowpass(out, 900.0 + 600.0 * brightness)


def truck() -> list[float]:
    """Chefty pulling out: a low pickup engine revving up and driving off."""
    return engine(random.Random(400), 2.4, 34.0, 58.0, 0.6)


def door_slam(rng: random.Random) -> list[float]:
    """A car door shutting: a body thump, the latch, a short rattle."""
    out = silence(0.35)
    mix_into(out, thud(62.0, 0.25, 26.0), 0.0, 0.9)
    mix_into(out, decay(lowpass(noise(rng, 0.12), 400.0), 30.0), 0.0, 2.2)
    mix_into(out, click(rng, 3200.0, 0.01, 500.0), 0.004, 0.6)
    mix_into(out, decay(bandpass(noise(rng, 0.15), 1800.0, 2.0), 40.0), 0.01, 0.25)
    return out


def van() -> list[float]:
    """The van leaving: its sliding door rolls shut, then a heavier engine pulls away."""
    rng = random.Random(500)
    out = silence(3.0)
    slide = shape(bandpass(noise(rng, 0.45), 900.0, 0.8), 0.05, 0.05)
    mix_into(out, [value * (0.5 + 0.5 * math.sin(2 * math.pi * 30 * i / RATE)) for i, value in enumerate(slide)], 0.0, 0.5)
    mix_into(out, door_slam(rng), 0.45, 1.0)
    mix_into(out, engine(rng, 2.3, 30.0, 50.0, 0.3), 0.65, 1.0)
    return out


def warning() -> list[float]:
    """A tense low swell: two detuned brass-like tones a tritone apart."""
    seconds = 1.6
    out = []
    for index in range(int(seconds * RATE)):
        t = index / RATE
        value = 0.0
        for freq, detune in ((110.0, 0.0), (155.56, 0.0), (110.0, 0.7), (155.56, -0.6)):
            f = freq + detune
            # A softened sawtooth from a handful of harmonics.
            value += sum(math.sin(2 * math.pi * f * k * t) / k for k in range(1, 7))
        swell = min(1.0, t / 0.9) * min(1.0, (seconds - t) / 0.35)
        out.append(value * 0.12 * swell)
    return lowpass(out, 1400.0)


def radio() -> list[float]:
    """A two-way radio: squelch click, a burst of garbled voice-band chatter, squelch tail."""
    rng = random.Random(600)
    out = silence(1.5)
    mix_into(out, click(rng, 2500.0, 0.01, 400.0), 0.0, 0.8)
    chatter_length = 1.05
    voice = bandpass(noise(rng, chatter_length), 1100.0, 0.9)
    voice = bandpass(voice, 1700.0, 0.8)
    syllables = []
    level, target, next_change = 0.0, 0.0, 0.0
    for index in range(len(voice)):
        t = index / RATE
        if t >= next_change:
            target = rng.choice([0.0, 0.5, 0.9, 1.0, 0.7])
            next_change = t + rng.uniform(0.05, 0.16)
        level += (target - level) * 0.004
        syllables.append(voice[index] * level)
    static = bandpass(noise(rng, chatter_length), 2400.0, 0.6)
    mix_into(out, [s * 2.2 + n * 0.12 for s, n in zip(syllables, static)], 0.05, 1.0)
    tail = decay(highpass(noise(rng, 0.25), 1500.0), 14.0)
    mix_into(out, tail, 0.05 + chatter_length, 0.35)
    mix_into(out, click(rng, 2500.0, 0.01, 400.0), 1.38, 0.6)
    return out


def arrive() -> list[float]:
    """The crew pulling up: two car doors slamming, one after the other."""
    rng = random.Random(700)
    out = silence(0.9)
    mix_into(out, door_slam(rng), 0.0, 1.0)
    mix_into(out, door_slam(rng), 0.33, 0.85)
    return out


def tick() -> list[float]:
    """A wood block tick for the countdown."""
    rng = random.Random(800)
    out = silence(0.1)
    mix_into(out, decay([math.sin(2 * math.pi * 1250.0 * i / RATE) for i in range(int(0.1 * RATE))], 70.0), 0.0, 0.6)
    mix_into(out, click(rng, 1800.0, 0.02, 160.0), 0.0, 0.8)
    return out


def clear() -> list[float]:
    """All clear: three soft bell notes rising, with inharmonic bell partials."""
    notes = (523.25, 659.25, 783.99)
    seconds = 1.4
    out = silence(seconds)
    for index, freq in enumerate(notes):
        bell = []
        for sample in range(int((seconds - index * 0.17) * RATE)):
            t = sample / RATE
            value = (math.sin(2 * math.pi * freq * t) * math.exp(-t * 3.0)
                     + 0.4 * math.sin(2 * math.pi * freq * 2.76 * t) * math.exp(-t * 6.0)
                     + 0.2 * math.sin(2 * math.pi * freq * 5.4 * t) * math.exp(-t * 11.0))
            bell.append(value)
        mix_into(out, bell, index * 0.17, 0.3)
    return out


# Name -> (builder, number of variants or 0 for one file, peak level 0..1).
SOUNDS = {
    "step": (step, 4, 0.45),
    "rake": (rake, 3, 0.6),
    "bag": (bag, 2, 0.7),
    "truck": (truck, 0, 0.75),
    "van": (van, 0, 0.8),
    "warning": (warning, 0, 0.7),
    "radio": (radio, 0, 0.6),
    "arrive": (arrive, 0, 0.85),
    "tick": (tick, 0, 0.5),
    "clear": (clear, 0, 0.55),
}


def write(name: str, samples: list[float], peak_level: float) -> None:
    path = OUT / f"{name}.wav"
    peak = max(1e-6, max(abs(value) for value in samples))
    scale = peak_level / peak
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v * scale)) * 32767)) for v in samples))
    print(f"wrote assets/audio/sfx/{path.name}")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    wanted = sys.argv[1:] or list(SOUNDS)
    for sound_name in wanted:
        build, variants, level = SOUNDS[sound_name]
        if variants:
            for variant in range(1, variants + 1):
                write(f"{sound_name}_{variant}", build(variant), level)
        else:
            write(sound_name, build(), level)
