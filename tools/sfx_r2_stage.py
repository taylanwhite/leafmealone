"""R2 chunk 1's sounds (gap-specs/nice_boys.json contract C17): the iris swish.

Built from tools/make_sfx.py's blocks, written next to its files:

    python tools/sfx_r2_stage.py            # every sound here
    python tools/sfx_r2_stage.py iris_swish
"""

import math
import random
import sys

import make_sfx as base


def iris_swish() -> list[float]:
    """The iris (ui/iris.gd) closing or opening: a soft paper-fan swish that sweeps
    up, and a small felt tock as the rosette meets in the middle."""
    rng = random.Random(2701)
    seconds = 0.42
    air = base.bandpass(base.noise(rng, seconds), lambda t: 700.0 + 2400.0 * math.sin(math.pi * min(1.0, t / seconds)) ** 1.5, 1.6)
    air = base.envelope(air, 0.08, 0.16)
    # A gentle flutter, like a stack of forms riffled past the ear.
    for index in range(len(air)):
        t = index / base.RATE
        air[index] *= 0.75 + 0.25 * math.sin(base.TAU * 38.0 * t)
    out = base.silence(seconds + 0.12)
    base.mix_into(out, air, 0.0, 0.9)
    tock = base.lowpass(base.blip(0.09, 420.0, 260.0, 38.0), 1800.0)
    base.mix_into(out, tock, seconds - 0.06, 0.55)
    return out


# Name -> (builder, number of variants or 0 for one file, peak level 0..1).
SOUNDS = {
    "iris_swish": (iris_swish, 0, 0.45),
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
