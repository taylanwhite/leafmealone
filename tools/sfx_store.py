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
    """The doors parting: a soft click of the operator, a breathy pneumatic hiss
    that swells as the leaves run and falls away as they ease in, a low rumble
    of the rollers in the track under it, and a muffled rubber bump at the stop
    (about 0.55 s, matching ART_DOOR_OPEN_SECONDS)."""
    rng = random.Random(8810)
    out = base.silence(0.72)
    # The operator's relay: a tiny dry click before anything moves.
    base.mix_into(out, base.envelope(base.bandpass(base.noise(rng, 0.012), 3600.0, 2.5), 0.001, 0.008), 0.0, 0.35)
    # The hiss: airy noise, its band sweeping down as the slide slows.
    hiss = base.bandpass(base.noise(rng, 0.55), lambda t: 2400.0 - 1500.0 * min(1.0, t / 0.55), 1.4)
    shaped = []
    for index, value in enumerate(hiss):
        t = index / RATE
        # Swell in over 0.12 s, hold, ease away to nothing by the stop.
        rise = min(1.0, t / 0.12)
        fall = max(0.0, 1.0 - max(0.0, t - 0.2) / 0.35)
        shaped.append(value * rise * fall * fall)
    base.mix_into(out, shaped, 0.03, 0.9)
    # The rollers: a low rumble that follows the leaves' speed.
    rumble = base.lowpass(base.noise(rng, 0.5), 180.0)
    rolled = []
    for index, value in enumerate(rumble):
        t = index / RATE
        speed = math.sin(math.pi * min(1.0, t / 0.5))
        rolled.append(value * speed)
    base.mix_into(out, rolled, 0.04, 1.6)
    # The leaves easing into their stop: a soft rubber bump.
    base.mix_into(out, base.blip(0.08, 140.0, 90.0, 40.0), 0.55, 0.35)
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
