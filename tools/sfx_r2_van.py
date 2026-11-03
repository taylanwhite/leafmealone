#!/usr/bin/env python3
"""The Courtesy Shuttle's sounds (nice_boys:4, net/run_events/shuttle.gd), made the
same way as everything in tools/make_sfx.py (its building blocks, fixed seeds, the
same writer), into assets/audio/sfx/:

  van_door_slide   the sliding door on its rail: a rumbling roll and a latch clunk
  seatbelt_click   a buckle snapping home (and coming undone)
  blinker_tick     one tick of the turn signal's relay, tock-ish
  van_bump         a pothole: a thump through the springs and a rattle of the cabin
  window_knock     knuckles on the van's glass, two raps, a little hollow
  mirror_glint     the side mirror catching the light: a tiny bright 'ting'
  radio_babble     the cab radio (loop): a dispatcher babbling through a tinny speaker

Usage: python3 tools/sfx_r2_van.py            write them all
       python3 tools/sfx_r2_van.py van_bump   write only that one
"""
import random
import sys

import make_sfx as k


def van_door_slide() -> list[float]:
    """The sliding door on its rail: a low rolling rumble that runs 0.5 s, the
    rollers ticking over the track's joins, and a padded latch clunk at the end."""
    rng = random.Random(4201)
    out = k.silence(0.75)
    roll = k.lowpass(k.noise(rng, 0.55), 420.0)
    k.mix_into(out, k.envelope(roll, 0.05, 0.08), 0.0, 0.9)
    for index in range(5):
        k.mix_into(out, k.decay(k.highpass(k.noise(rng, 0.03), 1800.0), 90.0), 0.06 + index * 0.1, 0.25)
    k.mix_into(out, k.blip(0.14, 210.0, 90.0, 26.0), 0.52, 1.0)
    k.mix_into(out, k.decay(k.lowpass(k.noise(rng, 0.08), 700.0), 45.0), 0.52, 0.7)
    return out


def seatbelt_click() -> list[float]:
    """A buckle snapping home: a bright plastic click with a metal tongue under it."""
    rng = random.Random(4202)
    out = k.silence(0.16)
    k.mix_into(out, k.decay(k.highpass(k.noise(rng, 0.02), 3000.0), 220.0), 0.0, 0.9)
    k.mix_into(out, k.decay(k.tone(0.06, 2400.0, "triangle"), 80.0), 0.004, 0.35)
    k.mix_into(out, k.decay(k.highpass(k.noise(rng, 0.015), 2200.0), 260.0), 0.035, 0.6)
    return out


def blinker_tick() -> list[float]:
    """One tick of the turn signal's relay: a dry little tock."""
    rng = random.Random(4203)
    out = k.silence(0.08)
    k.mix_into(out, k.decay(k.bandpass(k.noise(rng, 0.03), 1300.0, 4.0), 160.0), 0.0, 1.0)
    k.mix_into(out, k.decay(k.tone(0.03, 820.0, "sine"), 140.0), 0.0, 0.4)
    return out


def van_bump() -> list[float]:
    """A pothole: a deep thump through the springs, a boing as they settle, and the
    cabin's loose stuff rattling (the water cooler, the clipboards)."""
    rng = random.Random(4204)
    out = k.silence(0.9)
    k.mix_into(out, k.blip(0.3, 110.0, 45.0, 10.0), 0.0, 1.0)
    k.mix_into(out, k.decay(k.lowpass(k.noise(rng, 0.2), 300.0), 18.0), 0.0, 0.8)
    k.mix_into(out, k.decay(k.tone(0.45, k.glide(180.0, 120.0, 0.45), "sine", (11.0, 0.08)), 7.0), 0.06, 0.35)
    for index in range(4):
        k.mix_into(out, k.decay(k.highpass(k.noise(rng, 0.04), 2600.0), 70.0), 0.1 + index * 0.07 + rng.uniform(0.0, 0.03), 0.3)
    return out


def window_knock() -> list[float]:
    """Knuckles on the glass: two quick raps, hollow and a touch ringing."""
    rng = random.Random(4205)
    out = k.silence(0.42)
    for start in (0.0, 0.14):
        k.mix_into(out, k.decay(k.bandpass(k.noise(rng, 0.05), 1700.0, 3.0), 90.0), start, 1.0)
        k.mix_into(out, k.decay(k.tone(0.18, 1150.0, "sine"), 30.0), start, 0.25)
        k.mix_into(out, k.decay(k.tone(0.1, 420.0, "sine"), 60.0), start, 0.45)
    return out


def mirror_glint() -> list[float]:
    """The mirror catching the light: a tiny bright 'ting' that sparkles off."""
    out = k.silence(0.45)
    k.mix_into(out, k.decay(k.tone(0.4, 3300.0, "sine"), 12.0), 0.0, 0.6)
    k.mix_into(out, k.decay(k.tone(0.3, 4950.0, "sine"), 18.0), 0.02, 0.3)
    return out


def radio_babble() -> list[float]:
    """The cab radio, a loop: a dispatcher babbling (the game's babble voice) band-
    passed down to a tinny speaker, with hiss and the odd squelch, 3 s long and
    faded at both ends so make_loops-style looping doesn't click."""
    rng = random.Random(4206)
    seconds = 3.0
    out = k.silence(seconds)
    hiss = k.highpass(k.noise(rng, seconds), 3000.0)
    k.mix_into(out, hiss, 0.0, 0.05)
    t = 0.15
    variant = 1
    while t < seconds - 0.9:
        line = k.babble(variant)
        k.mix_into(out, line, t, 0.8)
        t += len(line) / k.RATE + rng.uniform(0.15, 0.35)
        variant = variant % 5 + 1
    tinny = k.bandpass(out, 1500.0, 1.1)
    return k.envelope(tinny, 0.05, 0.05)


SOUNDS = {
    "van_door_slide": (van_door_slide, 0.8),
    "seatbelt_click": (seatbelt_click, 0.6),
    "blinker_tick": (blinker_tick, 0.45),
    "van_bump": (van_bump, 0.8),
    "window_knock": (window_knock, 0.8),
    "mirror_glint": (mirror_glint, 0.5),
    "radio_babble": (radio_babble, 0.5),
}


if __name__ == "__main__":
    k.OUT.mkdir(parents=True, exist_ok=True)
    for sound_name in sys.argv[1:] or list(SOUNDS):
        build, level = SOUNDS[sound_name]
        k.write(sound_name, build(), level)
