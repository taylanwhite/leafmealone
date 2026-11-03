#!/usr/bin/env python3
"""Synthesize the hiding sounds (R2 chunk 3, docs/GAME.md "Hiding") into
assets/audio/sfx/, with make_sfx.py's building blocks.

Hedges shush, bins clang, sheds creak, leaf piles whump and burst, a refused
dive bonks off the outside, and a NICE BOY's Courtesy Notice slaps onto a spot
he poked and found nothing in. Same rules as make_sfx.py: generated from tones
and noise, fixed seeds, identical files on every run.

Usage: python tools/sfx_r2_hide.py                write all of them
       python tools/sfx_r2_hide.py pile_dive     write only those
"""
import math
import random
import sys

import make_sfx as base

from make_sfx import (RATE, TAU, bandpass, blip, decay, envelope, glide, highpass, lowpass, mix_into, noise, silence, tone)


def _twigs(rng: random.Random, out: list[float], start: float, length: float, count: int, gain: float) -> None:
    """Little dry snaps scattered through a rustle: twigs and stiff leaves."""
    for _ in range(count):
        at = start + rng.uniform(0.0, length)
        snap = decay(bandpass(noise(rng, 0.02), rng.uniform(2600.0, 4800.0), 3.0), 220.0)
        mix_into(out, snap, at, gain * rng.uniform(0.5, 1.0))


def _shush(rng: random.Random, seconds: float, low: float, high: float) -> list[float]:
    """Leaves brushing leaves: band-passed noise whose brightness and level
    flutter like a branch being pushed through."""
    raw = noise(rng, seconds)
    flutter_rate = rng.uniform(9.0, 14.0)
    shaped = bandpass(raw, lambda t: low + (high - low) * (0.5 + 0.5 * math.sin(TAU * 2.3 * t)), 1.4)
    out = []
    for index, value in enumerate(shaped):
        t = index / RATE
        wobble = 0.55 + 0.45 * abs(math.sin(TAU * flutter_rate * t + 0.7 * math.sin(TAU * 3.1 * t)))
        out.append(value * wobble)
    return envelope(out, 0.03, seconds * 0.5)


def hedge_rustle(variant: int) -> list[float]:
    """Diving through a hedge, or a hider turning too fast in one: a leafy
    shush with twig snaps, a little different every time."""
    rng = random.Random(1300 + variant)
    length = 0.42 + 0.06 * variant
    out = silence(length + 0.1)
    mix_into(out, _shush(rng, length, 1800.0 + 200.0 * variant, 5200.0), 0.0, 1.0)
    _twigs(rng, out, 0.03, length * 0.7, 5 + variant, 0.55)
    # The body of the push: a soft low brush under the leaves.
    mix_into(out, envelope(lowpass(noise(rng, length * 0.6), 500.0), 0.04, 0.15), 0.0, 0.5)
    return out


def peek_rustle(variant: int) -> list[float]:
    """Parting the leaves (or the lid) to look: a small, careful rustle."""
    rng = random.Random(1350 + variant)
    out = silence(0.3)
    mix_into(out, _shush(rng, 0.24, 2600.0, 6000.0), 0.0, 0.7)
    _twigs(rng, out, 0.02, 0.16, 2, 0.35)
    return out


def bin_lid() -> list[float]:
    """The wheelie bin's lid flipped open: a plastic creak up, and a hollow
    knock as it falls back against the handle."""
    rng = random.Random(1400)
    out = silence(0.55)
    creak = bandpass(tone(0.2, glide(260.0, 420.0, 0.2), "saw", (32.0, 0.05)), 900.0, 2.0)
    mix_into(out, envelope(creak, 0.02, 0.06), 0.0, 0.5)
    knock = decay(tone(0.3, glide(240.0, 170.0, 0.12), "triangle"), 16.0)
    mix_into(out, knock, 0.2, 1.0)
    mix_into(out, decay(bandpass(noise(rng, 0.08), 1100.0, 1.5), 40.0), 0.2, 0.5)
    return out


def bin_clang() -> list[float]:
    """The lid slammed shut with you inside: a big hollow plastic BONG with a
    rattle, ringing in the empty bin."""
    rng = random.Random(1401)
    out = silence(0.95)
    for freq, gain, rate in ((150.0, 1.0, 6.0), (342.0, 0.55, 8.0), (617.0, 0.32, 11.0), (1105.0, 0.16, 16.0)):
        mix_into(out, decay(tone(0.9, freq * rng.uniform(0.99, 1.01), "triangle"), rate), 0.0, gain)
    mix_into(out, decay(lowpass(noise(rng, 0.1), 1400.0), 45.0), 0.0, 0.9)
    # The lid bouncing once on its rim.
    mix_into(out, decay(tone(0.2, 360.0, "triangle"), 25.0), 0.13, 0.35)
    mix_into(out, decay(bandpass(noise(rng, 0.04), 2200.0, 2.0), 80.0), 0.13, 0.3)
    return out


def shed_door() -> list[float]:
    """The shed door: a long rusty creak that bends in pitch, and the wooden
    clack of it swinging to."""
    rng = random.Random(1450)
    out = silence(1.05)
    creak_pitch = lambda t: 190.0 + 70.0 * math.sin(TAU * 1.3 * t) + 40.0 * math.sin(TAU * 4.7 * t)
    creak = tone(0.7, creak_pitch, "saw", (23.0, 0.08))
    creak = bandpass(creak, lambda t: 1200.0 + 500.0 * math.sin(TAU * 0.9 * t), 3.0)
    mix_into(out, envelope(creak, 0.06, 0.2), 0.0, 0.7)
    clack = lowpass(decay(tone(0.25, glide(150.0, 90.0, 0.1), "triangle"), 20.0), 900.0)
    mix_into(out, clack, 0.74, 1.0)
    mix_into(out, decay(bandpass(noise(rng, 0.05), 1800.0, 2.0), 70.0), 0.74, 0.6)
    # The latch.
    mix_into(out, decay(tone(0.06, 2400.0, "square"), 120.0), 0.8, 0.12)
    return out


def pile_dive() -> list[float]:
    """A cannonball into a leaf pile: a soft WHUMP and a big dry crunch that
    settles into rustling."""
    rng = random.Random(1500)
    out = silence(0.8)
    mix_into(out, blip(0.3, 140.0, 55.0, 9.0), 0.0, 1.0)
    crunch = envelope(bandpass(noise(rng, 0.45), lambda t: 3800.0 - 1800.0 * min(1.0, t / 0.4), 0.9), 0.005, 0.3)
    mix_into(out, crunch, 0.0, 0.9)
    _twigs(rng, out, 0.0, 0.25, 14, 0.4)
    mix_into(out, _shush(rng, 0.35, 2200.0, 5000.0), 0.3, 0.35)
    return out


def pile_pop() -> list[float]:
    """Turned out of a pile: leaves burst up (a pfoomf) and a springy boing as
    you pop out."""
    rng = random.Random(1501)
    out = silence(0.7)
    burst = envelope(bandpass(noise(rng, 0.35), lambda t: 1500.0 + 3500.0 * min(1.0, t / 0.2), 0.8), 0.004, 0.25)
    mix_into(out, burst, 0.0, 1.0)
    _twigs(rng, out, 0.0, 0.3, 10, 0.35)
    boing = tone(0.35, lambda t: 260.0 * (1.0 + 0.5 * math.exp(-7.0 * t) * math.sin(TAU * 13.0 * t)) + 300.0 * min(1.0, t / 0.3), "triangle")
    mix_into(out, decay(boing, 7.0), 0.03, 0.45)
    return out


def hide_bonk() -> list[float]:
    """A dive that doesn't fit (the spot's full, or too far): you bonk off the
    outside with a hollow knock and a sheepish little boing."""
    rng = random.Random(1550)
    out = silence(0.5)
    mix_into(out, decay(tone(0.3, glide(320.0, 180.0, 0.15), "triangle"), 18.0), 0.0, 1.0)
    mix_into(out, decay(lowpass(noise(rng, 0.06), 1500.0), 60.0), 0.0, 0.7)
    boing = tone(0.3, lambda t: 420.0 * (1.0 + 0.3 * math.exp(-8.0 * t) * math.sin(TAU * 16.0 * t)) - 200.0 * min(1.0, t / 0.3), "sine")
    mix_into(out, decay(boing, 9.0), 0.06, 0.4)
    return out


def notice_slap() -> list[float]:
    """A Courtesy Notice sticker slapped onto the spot: a crisp paper SLAP and a
    little rub to smooth it down."""
    rng = random.Random(1600)
    out = silence(0.4)
    mix_into(out, decay(highpass(noise(rng, 0.05), 1200.0), 70.0), 0.0, 1.0)
    mix_into(out, blip(0.08, 380.0, 200.0, 50.0), 0.0, 0.45)
    rub = bandpass(noise(rng, 0.16), lambda t: 2400.0 + 900.0 * math.sin(TAU * 12.0 * t), 2.0)
    mix_into(out, envelope(rub, 0.02, 0.06), 0.14, 0.25)
    return out


def shed_creak(variant: int) -> list[float]:
    """Peeking out of the shed (R2b hide): the door eased open a crack. A short,
    careful rusty creak that bends up in pitch, no clack."""
    rng = random.Random(1700 + variant)
    out = silence(0.38)
    base_hz = 230.0 + 30.0 * variant
    creak_pitch = lambda t: base_hz + 90.0 * min(1.0, t / 0.25) + 25.0 * math.sin(TAU * 6.0 * t)
    creak = tone(0.3, creak_pitch, "saw", (19.0 + 4.0 * variant, 0.1))
    creak = bandpass(creak, lambda t: 1300.0 + 400.0 * math.sin(TAU * 1.7 * t), 3.0)
    mix_into(out, envelope(creak, 0.006, 0.1), 0.0, 0.8)
    mix_into(out, decay(bandpass(noise(rng, 0.03), 2400.0, 2.0), 90.0), 0.0, 0.25)
    return out


def hide_grab() -> list[float]:
    """Found (R2b hide): two big hands close on your collar inside the hedge, the
    bin or the shed. A sharp cloth snatch (a bright fabric crunch with a hard
    attack), a soft thump of knuckles on shoulders, and a short rising squeak:
    the cartoon 'gotcha' grip, heard over the parting leaves."""
    rng = random.Random(1650)
    out = silence(0.42)
    # The snatch: a crisp burst of cloth, bright at the front, dying fast.
    snatch = bandpass(noise(rng, 0.12), lambda t: 3200.0 - 1600.0 * min(1.0, t / 0.1), 1.1)
    mix_into(out, decay(snatch, 34.0), 0.0, 1.0)
    # Knuckles on shoulders: a low, round thump right on the attack.
    mix_into(out, blip(0.16, 150.0, 80.0, 22.0), 0.0, 0.9)
    mix_into(out, decay(lowpass(noise(rng, 0.05), 700.0), 60.0), 0.004, 0.6)
    # The fabric bunching up in his fists.
    rub = bandpass(noise(rng, 0.18), lambda t: 1800.0 + 700.0 * math.sin(TAU * 17.0 * t), 2.0)
    mix_into(out, envelope(rub, 0.01, 0.1), 0.05, 0.35)
    # A little rising squeak of surprise from the shirt (or you).
    squeak = tone(0.12, glide(620.0, 980.0, 0.12), "triangle", (28.0, 0.04))
    mix_into(out, envelope(squeak, 0.01, 0.05), 0.07, 0.22)
    return out


def hedge_poke(variant: int) -> list[float]:
    """A NICE BOY's hands shoved into your hedge (R2c hide): heard from inside,
    right at your ears. A hard crack of twigs on the very first sample, a dry
    thump of the push, and a short leafy shush that dies fast."""
    rng = random.Random(1750 + variant)
    out = silence(0.42)
    # The crack: a cluster of bright snaps with no fade-in at all.
    for index in range(4 + variant):
        snap = decay(bandpass(noise(rng, 0.025), rng.uniform(2400.0, 4200.0), 2.5), 260.0)
        mix_into(out, snap, 0.003 * index + rng.uniform(0.0, 0.004), 0.9 * rng.uniform(0.6, 1.0))
    # The push: knuckles into the leaves, low and short.
    mix_into(out, blip(0.12, 170.0 + 20.0 * variant, 90.0, 26.0), 0.0, 0.7)
    shush = bandpass(noise(rng, 0.26), lambda t: 3400.0 - 1600.0 * min(1.0, t / 0.2), 1.2)
    mix_into(out, decay(shush, 11.0), 0.0, 0.75)
    _twigs(rng, out, 0.02, 0.18, 3, 0.4)
    return out


# Name -> (builder, number of variants or 0 for one file, peak level 0..1).
SOUNDS = {
    "hedge_rustle": (hedge_rustle, 3, 0.55),
    "peek_rustle": (peek_rustle, 2, 0.35),
    "bin_lid": (bin_lid, 0, 0.6),
    "bin_clang": (bin_clang, 0, 0.75),
    "shed_door": (shed_door, 0, 0.6),
    "pile_dive": (pile_dive, 0, 0.7),
    "pile_pop": (pile_pop, 0, 0.65),
    "hide_bonk": (hide_bonk, 0, 0.7),
    "notice_slap": (notice_slap, 0, 0.6),
    "hide_grab": (hide_grab, 0, 0.75),
    "shed_creak": (shed_creak, 2, 0.45),
    "hedge_poke": (hedge_poke, 2, 0.6),
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
