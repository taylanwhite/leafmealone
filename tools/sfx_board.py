#!/usr/bin/env python3
"""The Gutter Shredder's sounds (driving chunk G1, player/skate_view.gd), made the
same way as everything in tools/make_sfx.py (its building blocks, fixed seeds, the
same writer), into assets/audio/sfx/. Ids as gap-specs/critic.md C12 settled them:

  board_pop    the tail slapping the street on an ollie: a sharp wooden clack
  board_land   four wheels and a deck coming down: clack-thunk and a rattle
  board_roll   (loop) urethane on asphalt: a soft rumble with the cracks ticking by
  board_grind  (loop) a truck scraping a curb: a gritty metal hiss that rings
  board_bail   the board leaving without you: a slide whistle down, clatter, a wheel spinning out
  trick_ding   a trick landed: a bright bell and a little brass 'ba-DAH'

Usage: python3 tools/sfx_board.py              write them all
       python3 tools/sfx_board.py board_pop    write only that one
"""
import math
import random
import sys

import make_sfx as k
from make_loops import seamless

RATE = k.RATE
TAU = k.TAU


def _clack(rng: random.Random, pitch: float, length: float = 0.12) -> list[float]:
    """Hard maple hitting something: a click on top, a hollow wooden knock under it."""
    out = k.silence(length)
    click = k.decay(k.highpass(k.noise(rng, 0.02), 2400.0), 260.0)
    k.mix_into(out, click, 0.0, 0.9)
    knock = k.decay(k.tone(length, k.glide(pitch * 1.15, pitch, 0.03), "triangle"), 38.0)
    k.mix_into(out, knock, 0.0, 0.8)
    k.mix_into(out, k.decay(k.tone(length, pitch * 2.63), 60.0), 0.0, 0.25)
    return out


def _rattle(rng: random.Random, seconds: float, hits: int, start_gain: float) -> list[float]:
    """Loose trucks and wheel bearings settling: little metal ticks that die off."""
    out = k.silence(seconds)
    for index in range(hits):
        at = index * seconds / (hits + 1) + rng.uniform(0.0, 0.012)
        tick = k.decay(k.bandpass(k.noise(rng, 0.03), rng.uniform(3000.0, 4600.0), 4.0), 140.0)
        k.mix_into(out, tick, at, start_gain * (1.0 - index / hits))
    return out


def board_pop() -> list[float]:
    """The ollie: the tail cracks down on the street, a split second of scuff as
    the front foot drags it up."""
    rng = random.Random(8101)
    out = k.silence(0.26)
    k.mix_into(out, _clack(rng, 520.0, 0.16), 0.0, 1.0)
    k.mix_into(out, k.blip(0.08, 160.0, 90.0, 40.0), 0.0, 0.5)
    scuff = k.envelope(k.bandpass(k.noise(rng, 0.09), 1800.0, 1.2), 0.01, 0.06)
    k.mix_into(out, scuff, 0.05, 0.3)
    return out


def board_land() -> list[float]:
    """Landing: the deck slaps, the wheels thunk a hair later, the trucks rattle."""
    rng = random.Random(8102)
    out = k.silence(0.42)
    k.mix_into(out, _clack(rng, 430.0, 0.16), 0.0, 0.9)
    k.mix_into(out, k.blip(0.22, 140.0, 60.0, 16.0), 0.012, 1.0)
    k.mix_into(out, k.decay(k.lowpass(k.noise(rng, 0.1), 420.0), 30.0), 0.012, 0.8)
    k.mix_into(out, _rattle(rng, 0.3, 5, 0.3), 0.05, 1.0)
    return out


def board_roll() -> list[float]:
    """Rolling: a soft urethane rumble, breathing a little, and a tick-tock every
    time the wheels cross a crack in the pavement. One speed; skate_view.gd pitches
    and swells it with speed."""
    rng = random.Random(8103)
    seconds = 2.0
    out = k.silence(seconds + 0.3)
    rumble = k.lowpass(k.lowpass(k.noise(rng, seconds + 0.3), 320.0), 320.0)
    flutter = [0.75 + 0.25 * math.sin(TAU * 3.1 * index / RATE) * math.sin(TAU * 0.7 * index / RATE) for index in range(len(rumble))]
    k.mix_into(out, [a * b for a, b in zip(rumble, flutter)], 0.0, 2.6)
    grit = k.bandpass(k.noise(rng, seconds + 0.3), 1300.0, 0.9)
    k.mix_into(out, grit, 0.0, 0.18)
    # The cracks: front wheels, then back wheels a beat later.
    for at in (0.21, 0.83, 1.46):
        for offset, gain in ((0.0, 0.55), (0.11, 0.42)):
            thud = k.decay(k.tone(0.08, 110.0, "triangle"), 55.0)
            k.mix_into(out, thud, at + offset, gain)
            k.mix_into(out, k.decay(k.highpass(k.noise(rng, 0.015), 2000.0), 300.0), at + offset, gain * 0.35)
    return seamless(out, 0.3)


def board_grind() -> list[float]:
    """Grinding a curb: aluminum on concrete, a gritty hiss that wobbles with the
    curb's bumps and a thin metal ring over it."""
    rng = random.Random(8104)
    seconds = 1.4
    out = k.silence(seconds + 0.25)
    span = seconds + 0.25
    hiss = k.bandpass(k.noise(rng, span), lambda t: 3200.0 + 700.0 * math.sin(TAU * 2.3 * t), 2.5)
    bumps = [0.6 + 0.4 * abs(math.sin(TAU * 5.5 * index / RATE + math.sin(TAU * 1.3 * index / RATE))) for index in range(len(hiss))]
    k.mix_into(out, [a * b for a, b in zip(hiss, bumps)], 0.0, 1.0)
    ring = k.bandpass(k.tone(span, 1870.0, "saw", (7.0, 0.012)), 1870.0, 6.0)
    k.mix_into(out, ring, 0.0, 0.22)
    k.mix_into(out, k.lowpass(k.noise(rng, span), 500.0), 0.0, 0.5)
    return seamless(out, 0.25)


def board_bail() -> list[float]:
    """A bail: the slide whistle drops out from under you while the board clatters
    off, clack, clack, clk, and a wheel spins itself out."""
    rng = random.Random(8105)
    out = k.silence(1.25)
    whistle = k.tone(0.6, k.glide(1450.0, 330.0, 0.58, 0.8), "sine", (8.0, 0.01))
    k.mix_into(out, k.envelope(whistle, 0.02, 0.1), 0.0, 0.55)
    for at, pitch, gain in ((0.12, 560.0, 1.0), (0.38, 610.0, 0.75), (0.55, 520.0, 0.5), (0.66, 590.0, 0.3)):
        k.mix_into(out, _clack(rng, pitch, 0.14), at, gain)
    spin = k.bandpass(k.noise(rng, 0.5), lambda t: 2600.0 - 1400.0 * min(1.0, t / 0.5), 3.0)
    ticks = [0.5 + 0.5 * math.sin(TAU * (26.0 - 30.0 * index / RATE) * index / RATE) for index in range(len(spin))]
    k.mix_into(out, k.envelope([a * b for a, b in zip(spin, ticks)], 0.02, 0.3), 0.7, 0.35)
    return out


def trick_ding() -> list[float]:
    """A trick landed: a bright little bell and a two-note brass 'ba-DAH' under it."""
    out = k.silence(0.8)
    k.mix_into(out, k.brass(0.09, 392.0, (0.0, 0.0)), 0.0, 0.55)
    k.mix_into(out, k.brass(0.32, 523.25, (6.0, 0.015)), 0.1, 0.75)
    for index, freq in enumerate((1568.0, 2349.0)):
        bell = k.decay(k.tone(0.6, freq), 7.0)
        k.mix_into(out, [a + 0.3 * b for a, b in zip(bell, k.decay(k.tone(0.6, freq * 2.7), 14.0))], 0.1 + index * 0.05, 0.3)
    return out


# Name -> (builder, variants or 0, peak level), like make_sfx.SOUNDS.
SOUNDS = {
    "board_pop": (board_pop, 0, 0.7),
    "board_land": (board_land, 0, 0.75),
    "board_roll": (board_roll, 0, 0.5),
    "board_grind": (board_grind, 0, 0.45),
    "board_bail": (board_bail, 0, 0.7),
    "trick_ding": (trick_ding, 0, 0.55),
}


if __name__ == "__main__":
    k.OUT.mkdir(parents=True, exist_ok=True)
    for sound_name in sys.argv[1:] or list(SOUNDS):
        build, variants, level = SOUNDS[sound_name]
        if variants:
            for variant in range(1, variants + 1):
                k.write(f"{sound_name}_{variant}", build(variant), level)
        else:
            k.write(sound_name, build(), level)
