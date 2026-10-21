#!/usr/bin/env python3
"""Synthesize the game's looping sounds, footsteps, ambience, and music into
assets/audio/sfx/, using the building blocks in tools/make_sfx.py.

Loops (tools, wind, music) are made seamless by crossfading their tail into
their head, and audio/sfx.gd plays them looped. Like everything else here, all
of it is a project original: tones, noise, a plucked-string model, and a small
formant voice. Seeds are fixed, so re-running writes identical files.

Usage: python3 tools/make_loops.py              write everything
       python3 tools/make_loops.py mower_loop   write only that
"""
import math
import random
import sys

import make_sfx as s

RATE = s.RATE
TAU = s.TAU


def seamless(samples: list[float], fade_seconds: float) -> list[float]:
    """Crossfade the last fade_seconds into the first, so the loop has no seam."""
    fade = int(fade_seconds * RATE)
    body = samples[: len(samples) - fade]
    tail = samples[len(samples) - fade:]
    for index in range(fade):
        mix = index / fade
        body[index] = body[index] * mix + tail[index] * (1.0 - mix)
    return body


# ---------------------------------------------------------------- tools

def mower_loop() -> list[float]:
    """A little four-stroke mower engine: steady putts, a buzzy body, blade whir."""
    rng = random.Random(51)
    seconds = 2.6
    out = s.silence(seconds)
    rate = 26.0
    t = 0.0
    while t < seconds:
        pop = s.decay(s.lowpass(s.noise(rng, 0.03), 900.0), 160.0)
        s.mix_into(out, pop, t, 0.7 + rng.uniform(-0.1, 0.1))
        t += 1.0 / (rate * rng.uniform(0.96, 1.04))
    body = s.lowpass(s.tone(seconds, 104.0, "square", (3.0, 0.02)), 700.0)
    s.mix_into(out, body, 0.0, 0.25)
    whir = s.bandpass(s.noise(rng, seconds), 1900.0, 3.0)
    s.mix_into(out, whir, 0.0, 0.35)
    return seamless(out, 0.3)


def blower_loop() -> list[float]:
    """A leaf blower: a big airy roar and a two-stroke whine on top."""
    rng = random.Random(52)
    seconds = 2.6
    roar = s.bandpass(s.noise(rng, seconds), 1100.0, 0.7)
    whine = s.tone(seconds, 820.0, "saw", (5.0, 0.01))
    whine = s.bandpass(whine, 1650.0, 4.0)
    out = [a * 0.9 + b * 0.25 for a, b in zip(roar, whine)]
    return seamless(out, 0.3)


def hose_loop() -> list[float]:
    """A garden hose spraying: a soft hiss with water pattering."""
    rng = random.Random(53)
    seconds = 2.6
    hiss = s.lowpass(s.highpass(s.noise(rng, seconds), 1500.0), 7000.0)
    out = [value * 0.5 for value in hiss]
    for _ in range(140):
        drop = s.decay(s.bandpass(s.noise(rng, 0.02), rng.uniform(1500.0, 4000.0), 6.0), 220.0)
        s.mix_into(out, drop, rng.uniform(0.0, seconds - 0.03), rng.uniform(0.2, 0.5))
    return seamless(out, 0.3)


def washer_loop() -> list[float]:
    """A pressure washer: a harsh blasting hiss over a humming pump motor."""
    rng = random.Random(54)
    seconds = 2.6
    blast = s.highpass(s.noise(rng, seconds), 900.0)
    pump = s.lowpass(s.tone(seconds, 60.0, "square", (7.0, 0.04)), 400.0)
    out = [a * 0.75 + b * 0.35 for a, b in zip(blast, pump)]
    return seamless(out, 0.3)


def trimmer_loop() -> list[float]:
    """A hedge trimmer: a nasal buzz chattering as the blades snap back and forth."""
    seconds = 2.0
    buzz = s.tone(seconds, 142.0, "saw")
    chatter = [value * (0.55 + 0.45 * math.sin(TAU * 24.0 * index / RATE)) for index, value in enumerate(buzz)]
    out = s.bandpass(chatter, 900.0, 1.2)
    return seamless(out, 0.25)


def roller_loop() -> list[float]:
    """A paint roller: a soft wet squelch going back and forth."""
    rng = random.Random(55)
    seconds = 2.0
    out = s.silence(seconds)
    for stroke in range(4):
        squelch = s.bandpass(s.noise(rng, 0.45), lambda t: 500.0 + 900.0 * math.sin(math.pi * t / 0.45), 3.0)
        s.mix_into(out, s.envelope(squelch, 0.08, 0.15), stroke * 0.5, 0.8)
    return seamless(out, 0.2)


# ---------------------------------------------------------------- footsteps

def step_leaves(variant: int) -> list[float]:
    """Stepping into dry leaves: a quick crackly crunch."""
    rng = random.Random(60 + variant)
    out = s.silence(0.3)
    for _ in range(18):
        crackle = s.decay(s.bandpass(s.noise(rng, 0.015), rng.uniform(2500.0, 6500.0), 3.0), 300.0)
        s.mix_into(out, crackle, rng.uniform(0.0, 0.16), rng.uniform(0.4, 1.0))
    s.mix_into(out, s.decay(s.lowpass(s.noise(rng, 0.12), 500.0), 30.0), 0.0, 0.4)
    return out


def step_grass(variant: int) -> list[float]:
    """Stepping on grass: a soft swish and a muffled pad."""
    rng = random.Random(70 + variant)
    swish = s.envelope(s.bandpass(s.noise(rng, 0.16), 1800.0 + variant * 200.0, 1.0), 0.03, 0.1)
    out = s.silence(0.25)
    s.mix_into(out, swish, 0.0, 0.6)
    s.mix_into(out, s.blip(0.1, 140.0, 80.0, 40.0), 0.0, 0.5)
    return out


def step_hard(variant: int) -> list[float]:
    """Stepping on concrete or asphalt: a short scuff and a tap."""
    rng = random.Random(80 + variant)
    out = s.silence(0.2)
    s.mix_into(out, s.decay(s.highpass(s.noise(rng, 0.04), 2000.0), 90.0), 0.0, 0.6)
    s.mix_into(out, s.blip(0.08, 220.0 + variant * 20.0, 120.0, 60.0), 0.0, 0.7)
    return out


# ---------------------------------------------------------------- ambience

def wind_loop() -> list[float]:
    """A gentle breeze through autumn trees: slow swells of soft noise."""
    rng = random.Random(90)
    seconds = 9.0
    base = s.lowpass(s.noise(rng, seconds), 600.0)
    leaves = s.bandpass(s.noise(rng, seconds), 3200.0, 0.8)
    out = []
    for index in range(len(base)):
        t = index / RATE
        swell = 0.55 + 0.3 * math.sin(TAU * t / 4.5) + 0.15 * math.sin(TAU * t / 1.7 + 1.0)
        out.append(base[index] * swell * 1.4 + leaves[index] * swell * swell * 0.18)
    return seamless(out, 1.5)


def bird(variant: int) -> list[float]:
    """A songbird: a few quick chirps, each bird its own little tune."""
    rng = random.Random(100 + variant)
    out = s.silence(1.4)
    t = 0.0
    base = rng.uniform(2600.0, 4200.0)
    for _ in range(rng.randint(2, 5)):
        up = rng.random() < 0.5
        start = base * rng.uniform(0.85, 1.15)
        end = start * (1.4 if up else 0.7)
        length = rng.uniform(0.06, 0.14)
        chirp = s.decay(s.tone(length, s.glide(start, end, length), "sine", (40.0, 0.05)), 25.0)
        s.mix_into(out, s.envelope(chirp, 0.005, 0.03), t, 0.8)
        t += length + rng.uniform(0.04, 0.18)
        if t > 1.2:
            break
    return out


def dog() -> list[float]:
    """A dog a few yards over: 'wuf! wuf!'"""
    rng = random.Random(110)
    out = s.silence(1.0)
    for index, at in enumerate((0.0, 0.32)):
        bark = s.vowel("uh", 0.16, s.glide(330.0 - index * 30.0, 210.0, 0.14), (0.0, 0.0))
        bark = s.envelope(bark, 0.008, 0.08)
        s.mix_into(out, bark, at, 1.0)
        s.mix_into(out, s.decay(s.bandpass(s.noise(rng, 0.06), 1200.0, 1.5), 40.0), at, 0.4)
    return out


def car_pass() -> list[float]:
    """A car going by on the street: a swelling rumble and tire hiss that fades away."""
    rng = random.Random(120)
    seconds = 4.0
    hum = s.lowpass(s.tone(seconds, lambda t: 70.0 - 8.0 * t / seconds, "saw"), 300.0)
    hiss = s.bandpass(s.noise(rng, seconds), 900.0, 0.8)
    out = []
    for index in range(len(hum)):
        t = index / RATE
        near = math.exp(-((t - seconds * 0.5) ** 2) / 0.6)
        out.append((hum[index] * 0.5 + hiss[index] * 0.6) * near)
    return out


# ---------------------------------------------------------------- music

def pluck(freq: float, seconds: float, rng: random.Random, brightness: float = 0.5) -> list[float]:
    """A plucked string (Karplus-Strong): a soft nylon-guitar-ish note."""
    period = max(2, int(RATE / freq))
    buffer = [rng.uniform(-1.0, 1.0) for _ in range(period)]
    out = []
    last = 0.0
    for index in range(int(seconds * RATE)):
        value = buffer[index % period]
        new = 0.5 * (value + last) * (0.994 + 0.004 * brightness)
        last = value
        buffer[index % period] = new
        out.append(value)
    return s.lowpass(out, 2500.0 + 2500.0 * brightness)


def note(name: str) -> float:
    names = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
    octave = int(name[-1])
    return 261.63 * 2.0 ** ((names[name[0]] + 12 * (octave - 4)) / 12.0)


def music_loop() -> list[float]:
    """A laid-back little tune for raking: plucked arpeggios over I-vi-IV-V, a warm
    bass, brushy drums, and a few glockenspiel notes on top. 8 bars at 92 bpm."""
    rng = random.Random(130)
    bpm = 92.0
    beat = 60.0 / bpm
    bars = 8
    seconds = bars * 4 * beat
    out = s.silence(seconds + 2.0)
    chords = [("C3", "E3", "G3", "C4"), ("A2", "E3", "A3", "C4"), ("F2", "C3", "F3", "A3"), ("G2", "D3", "G3", "B3")]
    pattern = [0, 2, 1, 3, 2, 1, 3, 2]
    for bar in range(bars):
        chord = chords[(bar // 2) % len(chords)]
        bar_start = bar * 4 * beat
        # Bass on beats 1 and 3.
        root = note(chord[0]) * 0.5
        for hit in (0, 2):
            bass = s.decay(s.tone(beat * 1.8, root, "sine"), 2.2)
            s.mix_into(out, s.envelope(bass, 0.01, 0.2), bar_start + hit * beat, 0.5)
        # Arpeggio in eighths.
        for step in range(8):
            freq = note(chord[pattern[step]])
            s.mix_into(out, pluck(freq, beat * 1.6, rng, 0.4), bar_start + step * beat * 0.5 + rng.uniform(0.0, 0.01), 0.32)
        # Kick on 1 and 3, brush on 2 and 4, shaker on the off-beats.
        for hit in range(4):
            at = bar_start + hit * beat
            if hit % 2 == 0:
                s.mix_into(out, s.blip(0.25, 110.0, 45.0, 14.0), at, 0.45)
            else:
                brush = s.envelope(s.bandpass(s.noise(rng, 0.18), 2500.0, 0.8), 0.01, 0.15)
                s.mix_into(out, brush, at, 0.22)
            shaker = s.envelope(s.highpass(s.noise(rng, 0.06), 6000.0), 0.01, 0.04)
            s.mix_into(out, shaker, at + beat * 0.5, 0.1)
    # A few glockenspiel notes, sparse and sweet.
    melody = [(0, "E5"), (1.5, "G5"), (3, "C6"), (8, "A5"), (10, "E5"), (16, "F5"), (17.5, "A5"), (19, "C6"), (24, "B5"), (26, "G5"), (28, "D5")]
    for beat_at, name in melody:
        freq = note(name)
        bell = s.decay(s.tone(1.4, freq, "sine"), 4.0)
        partial = s.decay(s.tone(1.4, freq * 2.76, "sine"), 9.0)
        s.mix_into(out, [a + b * 0.3 for a, b in zip(bell, partial)], beat_at * beat, 0.16)
    # Wrap the ringing tail back onto the start, so the loop is seamless.
    loop_length = int(seconds * RATE)
    for index in range(len(out) - loop_length):
        out[index] += out[loop_length + index]
    return out[:loop_length]


SOUNDS = {
    "mower_loop": (mower_loop, 0, 0.55),
    "blower_loop": (blower_loop, 0, 0.5),
    "hose_loop": (hose_loop, 0, 0.45),
    "washer_loop": (washer_loop, 0, 0.55),
    "trimmer_loop": (trimmer_loop, 0, 0.45),
    "roller_loop": (roller_loop, 0, 0.4),
    "step_leaves": (step_leaves, 3, 0.35),
    "step_grass": (step_grass, 3, 0.25),
    "step_hard": (step_hard, 3, 0.3),
    "wind_loop": (wind_loop, 0, 0.4),
    "bird": (bird, 4, 0.35),
    "dog": (dog, 0, 0.5),
    "car_pass": (car_pass, 0, 0.5),
    "music_loop": (music_loop, 0, 0.6),
}


if __name__ == "__main__":
    s.OUT.mkdir(parents=True, exist_ok=True)
    wanted = sys.argv[1:] or list(SOUNDS)
    for sound_name in wanted:
        build, variants, level = SOUNDS[sound_name]
        if variants:
            for variant in range(1, variants + 1):
                s.write(f"{sound_name}_{variant}", build(variant), level)
        else:
            s.write(sound_name, build(), level)
