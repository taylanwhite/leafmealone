#!/usr/bin/env python3
"""The NICE BOYS' catch sounds (R2 chunk 2; docs/GAME.md "The NICE BOYS encounter
(R2)"): their barks, the pea whistle, the clipboard scribble, the gotcha slap,
the lunge, the sticker, the torn page, the itemized pops, their heavy cartoon
footsteps and the knee-bounce landing out of the van.

Built from tools/make_sfx.py's building blocks and written with its write(), so
everything is a project original with fixed seeds (re-running writes identical
files). Register every id in audio/sound_bank.gd (the '# ---- R2:2' block).

Usage: python tools/sfx_r2_crew.py              write everything here
       python tools/sfx_r2_crew.py whistle bark write only those
"""
import math
import random
import sys

import make_sfx as base

RATE = base.RATE
TAU = base.TAU


def megaphone(samples: list[float]) -> list[float]:
    """A cheap bullhorn: band-limited, a little clipped, a little boxy."""
    boxed = base.bandpass(samples, 1400.0, 0.7)
    return [math.tanh(value * 2.2) for value in boxed]


def bark(variant: int) -> list[float]:
    """A NICE BOY calling out: two or three bright, nasal, cheerful syllables
    ('HEY-yo!', 'ex-CUSE!', 'hup-HUP!'), through his megaphone voice. The caption
    carries the words; this carries the attitude."""
    rng = random.Random(4100 + variant)
    patterns = [
        [("e", 0.13, 420.0, 470.0), ("o", 0.2, 520.0, 380.0)],
        [("e", 0.08, 380.0, 400.0), ("u", 0.11, 470.0, 500.0), ("e", 0.2, 560.0, 430.0)],
        [("uh", 0.1, 440.0, 460.0), ("uh", 0.17, 540.0, 520.0)],
    ]
    out = base.silence(0.62)
    at = 0.0
    for name, length, start, end in patterns[(variant - 1) % len(patterns)]:
        syllable = base.vowel(name, length, base.glide(start, end, length), (7.0, 0.03))
        base.mix_into(out, syllable, at, 1.0)
        at += length + rng.uniform(0.01, 0.03)
    return base.envelope(megaphone(out), 0.005, 0.06)


def whistle() -> list[float]:
    """The pea whistle: two sharp trilled tweets, the pea rattling inside."""
    out = base.silence(0.5)
    for at, length in ((0.0, 0.12), (0.17, 0.26)):
        trill = base.tone(length, lambda t: 2950.0 * (1.0 + 0.035 * math.sin(TAU * 34.0 * t)), "sine")
        rattle = [value * (0.75 + 0.25 * math.sin(TAU * 34.0 * index / RATE)) for index, value in enumerate(trill)]
        base.mix_into(out, base.envelope(rattle, 0.006, 0.03), at, 1.0)
    rng = random.Random(4200)
    base.mix_into(out, base.envelope(base.highpass(base.noise(rng, 0.42), 5000.0), 0.01, 0.1), 0.0, 0.12)
    return out


def scribble() -> list[float]:
    """A pencil scratching a citation onto a clipboard: quick zig-zag strokes, a
    tap for the full stop. Long enough to loop under the cite."""
    rng = random.Random(4300)
    length = 1.2
    out = base.silence(length)
    at = 0.0
    while at < length - 0.12:
        stroke = rng.uniform(0.05, 0.1)
        scratch = base.bandpass(base.noise(rng, stroke), rng.uniform(3200.0, 4600.0), 2.0)
        base.mix_into(out, base.envelope(scratch, 0.004, stroke * 0.5), at, rng.uniform(0.6, 1.0))
        at += stroke + rng.uniform(0.01, 0.035)
    base.mix_into(out, base.blip(0.04, 900.0, 600.0, 90.0), length - 0.1, 0.4)
    return out


def gotcha_grab() -> list[float]:
    """His hand lands on your shoulder: a fat cartoon slap and, in the same instant,
    a chirp of the whistle."""
    rng = random.Random(4400)
    out = base.silence(0.42)
    # R2b: a hard, bright crack on the very first sample (the contact frame has to
    # be heard through the whoosh and the music), then the meaty slap under it.
    crack = base.envelope(base.highpass(base.noise(rng, 0.012), 1800.0), 0.0005, 0.009)
    base.mix_into(out, crack, 0.0, 1.0)
    slap = base.envelope(base.lowpass(base.noise(rng, 0.07), 4200.0), 0.0008, 0.05)
    base.mix_into(out, slap, 0.0, 0.9)
    base.mix_into(out, base.blip(0.14, 260.0, 120.0, 28.0), 0.0, 0.8)
    chirp = base.tone(0.11, lambda t: 3100.0 * (1.0 + 0.04 * math.sin(TAU * 36.0 * t)), "sine")
    base.mix_into(out, base.envelope(chirp, 0.003, 0.04), 0.004, 0.55)
    return out


def lunge_whoosh() -> list[float]:
    """The lunge: a short, rising swish of a clipboard arm and a big khaki stride.
    It plays as he leaves the crouch (CREW_LUNGE_SECONDS before contact) and has
    died away by the hand landing, so the slap lands in a gap (R2b)."""
    rng = random.Random(4500)
    length = 0.22
    out = base.silence(length)
    # R2c: a crisp fwip of khaki on the very first samples (the leave-the-crouch
    # frame), then the swish starting already bright: its soft 600 Hz start was heard
    # 180 ms late under the bark's tail in two takes of five.
    base.mix_into(out, base.envelope(base.bandpass(base.noise(rng, 0.03), 2600.0, 1.5), 0.001, 0.02), 0.0, 0.9)
    swish = base.bandpass(base.noise(rng, length), lambda t: 1500.0 + 2200.0 * (t / length) ** 1.2, 2.2)
    base.mix_into(out, base.envelope(swish, 0.004, 0.12), 0.0, 1.0)
    return out


def windup_squeak() -> list[float]:
    """The wind-up's crouch (R2c): sneaker rubber squealing on the path as he
    sinks into the goalkeeper crouch, and a creak of khaki knees. It plays where he
    is, so a wind-up out of view is still heard from his side (audit dodge-offscreen)."""
    rng = random.Random(4550)
    out = base.silence(0.3)
    squeal = base.tone(0.16, lambda t: 1750.0 + 500.0 * math.sin(TAU * 9.0 * t) * (1.0 - t / 0.16), "sine")
    base.mix_into(out, base.envelope(squeal, 0.003, 0.06), 0.0, 0.8)
    base.mix_into(out, base.envelope(base.bandpass(base.noise(rng, 0.05), 3800.0, 2.5), 0.002, 0.03), 0.0, 0.35)
    creak = base.tone(0.12, lambda t: 210.0 + 60.0 * (t / 0.12), "saw")
    base.mix_into(out, base.envelope(base.lowpass(creak, 900.0), 0.01, 0.05), 0.12, 0.35)
    return out


def sticker_slap() -> list[float]:
    """A sticker slapped flat on a chest: a papery thwap and a little crinkle."""
    rng = random.Random(4600)
    out = base.silence(0.3)
    # R2b: a crisp front edge, so the slap is heard on the frame the sticker lands.
    base.mix_into(out, base.envelope(base.highpass(base.noise(rng, 0.01), 2000.0), 0.0005, 0.008), 0.0, 0.8)
    base.mix_into(out, base.envelope(base.lowpass(base.noise(rng, 0.05), 3000.0), 0.0008, 0.04), 0.0, 1.0)
    base.mix_into(out, base.blip(0.08, 340.0, 200.0, 40.0), 0.0, 0.5)
    base.mix_into(out, base.envelope(base.highpass(base.noise(rng, 0.09), 4200.0), 0.004, 0.06), 0.07, 0.3)
    return out


def paper_tear() -> list[float]:
    """Rrrip: a page torn off the citation pad, crackling as it goes."""
    rng = random.Random(4700)
    length = 0.36
    raw = base.noise(rng, length)
    crackle = [value * (0.35 + 0.65 * (1.0 if rng.random() < 0.18 else 0.3)) for value in raw]
    torn = base.bandpass(crackle, lambda t: 1800.0 + 2800.0 * (t / length), 1.4)
    return base.envelope(torn, 0.01, 0.08)


def itemize_pop() -> list[float]:
    """One of your things popping out onto the lawn, itemized: a bright plip. The
    row plays it at a rising pitch, item by item (net/components/hotbar.gd)."""
    out = base.silence(0.16)
    base.mix_into(out, base.decay(base.tone(0.14, base.glide(620.0, 1150.0, 0.05)), 34.0), 0.0, 1.0)
    return base.envelope(out, 0.002, 0.05)


def crew_step(variant: int) -> list[float]:
    """A NICE BOY's footstep: a heavy, rubbery cartoon clomp, sneakers that mean it."""
    rng = random.Random(4800 + variant)
    out = base.silence(0.2)
    base.mix_into(out, base.blip(0.17, 150.0 + variant * 9.0, 62.0, 22.0), 0.0, 1.0)
    base.mix_into(out, base.envelope(base.lowpass(base.noise(rng, 0.05), 900.0), 0.002, 0.04), 0.0, 0.5)
    squeak = base.tone(0.05, base.glide(1500.0 + variant * 70.0, 1900.0, 0.05))
    base.mix_into(out, base.envelope(squeak, 0.004, 0.02), 0.03, 0.08)
    return out


def hop_land() -> list[float]:
    """Hopping down from the van onto the curb: both feet, a knee bounce, a jangle
    of lanyard."""
    rng = random.Random(4900)
    out = base.silence(0.32)
    base.mix_into(out, base.blip(0.2, 200.0, 70.0, 18.0), 0.0, 1.0)
    base.mix_into(out, base.envelope(base.lowpass(base.noise(rng, 0.06), 1200.0), 0.002, 0.05), 0.0, 0.6)
    for at in (0.06, 0.1, 0.15):
        base.mix_into(out, base.envelope(base.bandpass(base.noise(rng, 0.03), 5200.0, 3.0), 0.002, 0.02), at, 0.18)
    return out


# Name -> (builder, number of variants or 0 for one file, peak level 0..1).
SOUNDS = {
    "bark": (bark, 3, 0.62),
    "whistle": (whistle, 0, 0.6),
    "scribble": (scribble, 0, 0.45),
    "gotcha_grab": (gotcha_grab, 0, 0.95),
    "lunge_whoosh": (lunge_whoosh, 0, 0.55),
    "windup_squeak": (windup_squeak, 0, 0.55),
    "sticker_slap": (sticker_slap, 0, 0.6),
    "paper_tear": (paper_tear, 0, 0.55),
    "itemize_pop": (itemize_pop, 0, 0.5),
    "crew_step": (crew_step, 3, 0.45),
    "hop_land": (hop_land, 0, 0.6),
}


if __name__ == "__main__":
    base.OUT.mkdir(parents=True, exist_ok=True)
    wanted = sys.argv[1:] or list(SOUNDS)
    for sound_name in wanted:
        build, variants, level = SOUNDS[sound_name]
        if variants:
            for variant in range(1, variants + 1):
                base.write(f"{sound_name}_{variant}", build(variant), level)
        else:
            base.write(sound_name, build(), level)
