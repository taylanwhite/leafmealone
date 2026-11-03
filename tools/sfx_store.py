#!/usr/bin/env python3
"""Homie Depot's walk-in lobby (art chunk 8; docs/GAME.md "Homie Depot, inside and
out"): the automatic doors' pneumatic hiss as they part (props/sliding_doors.gd
plays it when they start to open, and a little lower and quieter when they start
to close).

Built from tools/make_sfx.py's building blocks and written with its write(), so
everything is a project original with fixed seeds (re-running writes identical
files). Register every id in audio/sound_bank.gd (next to "whoosh").

Usage: python tools/sfx_store.py              write everything here
       python tools/sfx_store.py door_whoosh  write only that
"""
import math
import random
import sys

import make_sfx as base

RATE = base.RATE


def door_whoosh() -> list[float]:
    """The doors parting: the operator's latch letting go with a clunk, the valve's
    pneumatic burst right on it, a breathy hiss that eases as the leaves run, a
    low rumble of the rollers in the track under it, and a muffled rubber bump at
    the stop (0.5 s, matching ART_DOOR_OPEN_SECONDS).

    Everything that says "the doors are going" lands in the first 20 ms, because
    the leaves start on the same frame the sound is asked for (props/sliding_doors.gd)
    and most of their slide comes early: a hiss that swelled in over a tenth of a
    second was heard 70-200 ms after the glass had begun to move."""
    rng = random.Random(8810)
    out = base.silence(0.7)
    # The latch: a dry, bright click and a low thunk of the arm, both at once,
    # the loudest thing in the sound.
    base.mix_into(out, base.envelope(base.bandpass(base.noise(rng, 0.02), 2600.0, 1.6), 0.0005, 0.016), 0.0, 1.1)
    base.mix_into(out, base.blip(0.07, 190.0, 95.0, 55.0), 0.0, 0.9)
    # The hiss: airy noise, its band sweeping down as the slide slows. The valve
    # opens with a burst (full in 15 ms), settles, and eases away by the stop.
    hiss = base.bandpass(base.noise(rng, 0.52), lambda t: 2600.0 - 1600.0 * min(1.0, t / 0.5), 1.3)
    shaped = []
    for index, value in enumerate(hiss):
        t = index / RATE
        rise = min(1.0, t / 0.015)
        burst = 0.62 + 0.38 * math.exp(-t / 0.06)
        fall = max(0.0, 1.0 - max(0.0, t - 0.18) / 0.34)
        shaped.append(value * rise * burst * fall * fall)
    base.mix_into(out, shaped, 0.002, 1.0)
    # The rollers: a low rumble that follows the leaves' speed (their slide is
    # skewed early, ART_DOOR_OPEN_SKEW, so the rumble peaks early too).
    rumble = base.lowpass(base.noise(rng, 0.5), 180.0)
    rolled = []
    for index, value in enumerate(rumble):
        t = index / RATE
        speed = math.sin(math.pi * min(1.0, t / 0.5) ** 0.7)
        rolled.append(value * speed)
    base.mix_into(out, rolled, 0.0, 1.6)
    # The leaves easing into their stop: a soft rubber bump.
    base.mix_into(out, base.blip(0.08, 140.0, 90.0, 40.0), 0.49, 0.35)
    return out


# Name -> (builder, number of variants or 0 for one file, peak level 0..1).
SOUNDS = {
    "door_whoosh": (door_whoosh, 0, 0.42),
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
