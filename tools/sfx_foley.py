#!/usr/bin/env python3
"""Synthesize the foley, task and neighborhood sounds (gap audio chunk 6;
docs/GAME.md "Foley: what the crew sounds like") into assets/audio/sfx/, with
make_sfx.py's oscillators and sfx_grains.py's physical models.

What a body does (audio/player_foley.gd, from replicated state, heard where it
happens): paint and water hitting you, a big landing, being grabbed, being
thrown, the punch wind-up's windmill, a foot coming off. What a prop does
(audio/prop_foley.gd): a ladder set up and knocked down, a hose coupling
snapping on, a bag dropped in the wheelbarrow, picking things up, a TurfMasters
sign pulled out of the lawn. Task work at the spot (levels/lots/task_looks.gd
TASK_SOUNDS): litter, weeds, gutter goop, the squeegee, the shears, the pool
net. The neighborhood (audio/ambience.gd): crickets and an owl at night, Homie
Depot's hum and PA, a shopping cart, a neighbor mowing a few yards over.

Every file is written at an RMS target (sfx_grains.write_rms), so levels sit
against the rest of the mix by design rather than by peak; loops are built to
wrap (events that run past the end land at the start), so they loop with no
seam. Same rules as make_sfx.py: tones and noise only, fixed seeds, identical
files on every run.

Usage: python tools/sfx_foley.py               write all of them
       python tools/sfx_foley.py owl splash    write only those
"""
import math
import pathlib
import random
import struct
import sys
import wave

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import make_sfx as base  # noqa: E402
import sfx_grains as g  # noqa: E402

RATE = base.RATE
TAU = base.TAU


# ---------------------------------------------------------------- helpers

def mix_wrap(target: list[float], source: list[float], at: float, gain: float = 1.0) -> None:
    """Mix source into a loop at 'at' seconds; whatever runs past the end comes
    back in at the start, so the loop has no seam."""
    n = len(target)
    start = int(at * RATE)
    for index, value in enumerate(source):
        target[(start + index) % n] += value * gain


def pluck_up(seconds: float, start_hz: float, end_hz: float, rate: float, shape: str = "sine") -> list[float]:
    """A pitch that rises and dies: the 'bloop' of something light."""
    return base.decay(base.tone(seconds, base.glide(start_hz, end_hz, seconds * 0.5), shape), rate)


def droplets(rng: random.Random, out: list[float], start: float, length: float, count: int, gain: float,
             low: float = 1400.0, high: float = 3600.0) -> None:
    """Little drops landing: tiny rising plinks scattered through a stretch."""
    for _ in range(count):
        at = start + rng.uniform(0.0, length)
        f = g.loguniform(rng, low, high)
        plink = base.decay(base.tone(0.05, base.glide(f, f * 1.6, 0.02)), rng.uniform(90.0, 160.0))
        base.mix_into(out, plink, at, gain * rng.uniform(0.3, 1.0))


def slide_whistle(seconds: float, start_hz: float, end_hz: float, curve: float = 1.0) -> list[float]:
    """A cartoon slide whistle: a breathy sine with a quick vibrato, sliding."""
    rng = random.Random(int(start_hz * 7 + end_hz))
    pipe = base.tone(seconds, base.glide(start_hz, end_hz, seconds * 0.9, curve), "sine", (7.5, 0.012))
    air = base.bandpass(base.noise(rng, seconds), lambda t: start_hz + (end_hz - start_hz) * min(1.0, t / seconds), 6.0)
    return base.envelope([p + 0.18 * a for p, a in zip(pipe, air)], 0.02, seconds * 0.3)


def metal(freqs: list[float], taus: list[float], amps: list[float], seconds: float, rng: random.Random) -> list[float]:
    """A struck piece of aluminum: its modes, each a hair off every time."""
    return g.modal_click([f * rng.uniform(0.985, 1.015) for f in freqs], taus, amps, seconds)


def write_loop(name: str, samples: list[float], rms_dbfs: float, ceiling: float = 0.89) -> pathlib.Path:
    """A loop at an RMS target, with no fades and no DC filter (both would put a
    step at the seam); the recipes are built zero-mean and wrapped already."""
    target = 10.0 ** (rms_dbfs / 20.0)
    mean = sum(samples) / max(1, len(samples))
    out = [v - mean for v in samples]
    for _ in range(4):
        level = g.rms_of(out) or 1e-9
        out = [v * target / level for v in out]
        out = [ceiling * math.tanh(v / ceiling) for v in out]
    path = g.OUT / f"{name}.wav"
    g.OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(b"".join(struct.pack("<h", int(round(max(-1.0, min(1.0, v)) * 32767))) for v in out))
    return path


# ---------------------------------------------------------------- the body

def paint_splat() -> list[float]:
    """A roller's worth of paint landing on you: a wet SPLORT (a low slap with a
    gloopy band sweeping down) and a few drips peeling off after."""
    rng = random.Random(6100)
    out = base.silence(0.5)
    base.mix_into(out, base.blip(0.22, 190.0, 70.0, 16.0), 0.0, 1.0)
    slap = base.bandpass(base.noise(rng, 0.25), lambda t: 1500.0 - 1100.0 * min(1.0, t / 0.18), 2.2)
    base.mix_into(out, base.decay(slap, 18.0), 0.0, 0.9)
    base.mix_into(out, base.decay(base.highpass(base.noise(rng, 0.04), 2500.0), 120.0), 0.0, 0.5)
    for at in (0.16, 0.27, 0.36):
        drip = pluck_up(0.06, rng.uniform(420.0, 620.0), rng.uniform(900.0, 1200.0), 70.0)
        base.mix_into(out, drip, at, rng.uniform(0.25, 0.4))
    return out


def splash() -> list[float]:
    """A pressure washer or a hose catching you full on: a bright spray burst,
    a body 'sploosh' sweeping down, and the drops pattering after."""
    rng = random.Random(6110)
    out = base.silence(0.65)
    spray = base.decay(base.highpass(base.noise(rng, 0.45), 2200.0), 7.0)
    base.mix_into(out, base.envelope(spray, 0.006, 0.2), 0.0, 0.8)
    body = base.bandpass(base.noise(rng, 0.35), lambda t: 1600.0 - 1100.0 * min(1.0, t / 0.3), 2.0)
    base.mix_into(out, base.envelope(base.decay(body, 6.0), 0.004, 0.15), 0.0, 1.0)
    base.mix_into(out, base.blip(0.15, 160.0, 80.0, 20.0), 0.0, 0.5)
    droplets(rng, out, 0.12, 0.42, 22, 0.25)
    return out


def land_thump(variant: int) -> list[float]:
    """A hard landing (off a roof, out of a throw): the ground taking a body,
    a cartoon 'bwomp', a puff of dust and a grassy crunch."""
    rng = random.Random(6120 + variant)
    out = base.silence(0.5)
    f = rng.uniform(55.0, 70.0)
    base.mix_into(out, g.modal_click([f, f * 2.3, f * 4.1], [0.09, 0.05, 0.02], [1.0, 0.45, 0.2], 0.45), 0.0, 1.0)
    base.mix_into(out, base.blip(0.3, 130.0 + 15.0 * variant, 55.0, 11.0), 0.0, 0.7)
    puff = g.onepole_lp([v * math.exp(-i / (0.06 * RATE)) for i, v in enumerate(g.brown(rng, 0.3, 0.99))], 500.0)
    base.mix_into(out, puff, 0.004, 0.35)
    base.mix_into(out, g.crackle(rng, 0.25, lambda t: 900.0 * math.exp(-t / 0.05), lambda t: 0.05,
                                 band=(900.0, 5000.0), crumple_share=0.3), 0.003, 1.0)
    return out


def grab_yoink() -> list[float]:
    """Picked up by a teammate: a fistful of shirt and a quick zip up the slide
    whistle. YOINK."""
    rng = random.Random(6130)
    out = base.silence(0.42)
    cloth = base.bandpass(base.noise(rng, 0.12), lambda t: 3000.0 - 1400.0 * min(1.0, t / 0.1), 1.2)
    base.mix_into(out, base.decay(cloth, 30.0), 0.0, 1.0)
    base.mix_into(out, base.blip(0.12, 170.0, 100.0, 25.0), 0.0, 0.6)
    base.mix_into(out, slide_whistle(0.2, 520.0, 1450.0, 0.7), 0.03, 0.55)
    return out


def throw_big() -> list[float]:
    """A teammate thrown like a sack: a heavy airy WHOOSH that swells past, and
    a slide whistle falling away under it."""
    rng = random.Random(6140)
    seconds = 0.75
    out = base.silence(seconds)
    swell = lambda t: math.sin(math.pi * min(1.0, t / 0.55)) ** 1.5
    air = base.bandpass(base.noise(rng, 0.55), lambda t: 350.0 + 1500.0 * swell(t), 1.1)
    base.mix_into(out, [v * swell(i / RATE) for i, v in enumerate(air)], 0.0, 1.0)
    base.mix_into(out, slide_whistle(0.6, 1350.0, 480.0, 1.3), 0.08, 0.35)
    return out


def punch_windup() -> list[float]:
    """Winding up a punch, cartoon windmill style: an arm whirring round six
    times a second (a whoosh per turn) with a little ratchet on each. 1 s, six
    whole turns, so it loops on the beat."""
    rng = random.Random(6150)
    seconds = 1.0
    turns = 6
    out = base.silence(seconds)
    period = seconds / turns
    for turn in range(turns):
        at = turn * period
        whoosh = base.bandpass(base.noise(rng, period * 1.2), lambda t: 700.0 + 900.0 * math.sin(math.pi * min(1.0, t / (period * 1.2))), 1.6)
        shaped = [v * math.sin(math.pi * min(1.0, (i / RATE) / (period * 1.2))) ** 2 for i, v in enumerate(whoosh)]
        mix_wrap(out, shaped, at, 1.0)
        mix_wrap(out, base.decay(base.tone(0.03, 1900.0 + 40.0 * (turn % 2), "square"), 220.0), at + period * 0.5, 0.08)
    return out


def foot_pop() -> list[float]:
    """The mower takes a foot clean off (it's a cartoon): a cork POP and the
    slide whistle going up as it sails away."""
    rng = random.Random(6160)
    out = base.silence(0.9)
    base.mix_into(out, base.decay(base.highpass(base.noise(rng, 0.02), 1500.0), 300.0), 0.0, 0.9)
    base.mix_into(out, base.decay(base.tone(0.12, base.glide(720.0, 380.0, 0.05)), 45.0), 0.0, 1.0)
    base.mix_into(out, base.decay(base.tone(0.12, 1440.0), 60.0), 0.0, 0.25)
    base.mix_into(out, slide_whistle(0.62, 560.0, 1700.0, 0.8), 0.07, 0.6)
    return out


# ---------------------------------------------------------------- props

def ladder_clack() -> list[float]:
    """An aluminum ladder set against the gutter: the top clacks onto the
    gutter, the feet settle a beat later, and the rungs rattle."""
    rng = random.Random(6200)
    out = base.silence(0.45)
    base.mix_into(out, metal([830.0, 1980.0, 3420.0, 5100.0], [0.05, 0.03, 0.018, 0.01], [1.0, 0.6, 0.35, 0.2], 0.35, rng), 0.0, 1.0)
    base.mix_into(out, metal([610.0, 1460.0, 2780.0], [0.04, 0.025, 0.012], [0.8, 0.45, 0.25], 0.3, rng), 0.085, 0.55)
    base.mix_into(out, g.crackle(rng, 0.2, lambda t: 500.0 * math.exp(-t / 0.05), lambda t: 0.03,
                                 band=(2500.0, 7000.0), tau=(1e-3, 4e-3)), 0.01, 1.0)
    base.mix_into(out, base.decay(base.lowpass(base.noise(rng, 0.06), 600.0), 60.0), 0.09, 0.4)
    return out


def ladder_crash() -> list[float]:
    """A set-up ladder knocked over: it hits the ground with a big aluminum
    CLANG, bounces, clatters and rattles to a stop."""
    rng = random.Random(6210)
    out = base.silence(1.25)
    hits = ((0.0, 1.0), (0.17, 0.55), (0.29, 0.35), (0.37, 0.2), (0.43, 0.12))
    for at, weight in hits:
        f = rng.uniform(480.0, 560.0)
        clang = metal([f, f * 2.56, f * 5.1, f * 7.9, f * 11.2], [0.18, 0.12, 0.08, 0.05, 0.03], [1.0, 0.7, 0.45, 0.25, 0.12], 0.9, rng)
        base.mix_into(out, clang, at, weight)
        base.mix_into(out, base.decay(base.lowpass(base.noise(rng, 0.08), 900.0), 45.0), at, 0.6 * weight)
    base.mix_into(out, g.crackle(rng, 0.7, lambda t: 380.0 * math.exp(-t / 0.25), lambda t: 0.035,
                                 band=(2000.0, 7000.0), tau=(1e-3, 6e-3)), 0.05, 1.0)
    return out


def hose_click() -> list[float]:
    """A hose coupling snapping onto a spigot or Chefty's tank: a plastic click
    and the water rushing in behind it."""
    rng = random.Random(6220)
    out = base.silence(0.38)
    base.mix_into(out, g.modal_click([2900.0, 5300.0, 8100.0], [0.006, 0.004, 0.002], [1.0, 0.5, 0.25], 0.05), 0.0, 1.0)
    base.mix_into(out, g.modal_click([2500.0, 4800.0], [0.005, 0.003], [0.7, 0.3], 0.05), 0.035, 0.7)
    rush = base.highpass(base.noise(rng, 0.3), 1800.0)
    base.mix_into(out, [v * min(1.0, (i / RATE) / 0.08) * math.exp(-(i / RATE) / 0.12) for i, v in enumerate(rush)], 0.05, 0.35)
    return out


def bag_plop() -> list[float]:
    """A full leaf bag dropped in the wheelbarrow: a hollow THUNK of the metal
    tub, the bag's plastic crinkle, the leaves inside shifting."""
    rng = random.Random(6230)
    out = base.silence(0.55)
    base.mix_into(out, metal([175.0, 410.0, 770.0, 1240.0], [0.12, 0.08, 0.05, 0.03], [1.0, 0.55, 0.3, 0.15], 0.5, rng), 0.0, 1.0)
    base.mix_into(out, base.blip(0.2, 140.0, 80.0, 18.0), 0.0, 0.6)
    base.mix_into(out, g.crackle(rng, 0.35, lambda t: 700.0 * math.exp(-t / 0.08), lambda t: 0.05,
                                 band=(1500.0, 7000.0), crumple_share=0.35), 0.005, 1.0)
    return out


def pickup_light() -> list[float]:
    """Something light off the ground: a quick hand-on-handle tick and a little
    swish up."""
    rng = random.Random(6240)
    out = base.silence(0.24)
    base.mix_into(out, g.modal_click([1300.0, 2900.0], [0.008, 0.004], [1.0, 0.4], 0.05), 0.0, 1.0)
    swish = base.bandpass(base.noise(rng, 0.16), lambda t: 900.0 + 2400.0 * min(1.0, t / 0.14), 1.5)
    base.mix_into(out, base.envelope(swish, 0.04, 0.08), 0.01, 0.45)
    return out


def pickup_heavy() -> list[float]:
    """Something heavy off the ground: a low knock as it leaves the grass, a
    scrape, and whatever's in or on it rattling."""
    rng = random.Random(6250)
    out = base.silence(0.4)
    base.mix_into(out, g.modal_click([120.0, 290.0, 610.0], [0.05, 0.03, 0.015], [1.0, 0.5, 0.2], 0.3), 0.0, 1.0)
    scrape = base.bandpass(base.noise(rng, 0.2), lambda t: 700.0 + 900.0 * min(1.0, t / 0.2), 1.0)
    base.mix_into(out, base.envelope(scrape, 0.02, 0.1), 0.02, 0.45)
    base.mix_into(out, g.crackle(rng, 0.25, lambda t: 260.0 * math.exp(-t / 0.08), lambda t: 0.04,
                                 band=(1800.0, 6000.0), tau=(1e-3, 3e-3)), 0.05, 1.0)
    return out


def sign_pull() -> list[float]:
    """A TurfMasters sign yanked out of the lawn: SCHLORP (the stake sucking
    free of wet dirt, pitch rising), a pop, and clods pattering down."""
    rng = random.Random(6260)
    out = base.silence(0.6)
    suck = base.bandpass(base.lowpass(base.noise(rng, 0.28), 1800.0), lambda t: 180.0 + 900.0 * (t / 0.28) ** 1.6, 5.0)
    base.mix_into(out, base.envelope(suck, 0.05, 0.03), 0.0, 1.0)
    base.mix_into(out, base.decay(base.tone(0.1, base.glide(560.0, 300.0, 0.04)), 50.0), 0.27, 0.8)
    base.mix_into(out, base.decay(base.highpass(base.noise(rng, 0.015), 1200.0), 300.0), 0.27, 0.5)
    base.mix_into(out, g.crackle(rng, 0.3, lambda t: 300.0 * math.exp(-t / 0.1), lambda t: 0.05,
                                 band=(500.0, 2500.0), crumple_share=0.5), 0.3, 1.0)
    return out


# ---------------------------------------------------------------- task work at the spot

def litter_crinkle(variant: int) -> list[float]:
    """Picking up litter: a wrapper or a cup crumpled in a fist (a can's tink
    on the second variant)."""
    rng = random.Random(6300 + variant)
    out = base.silence(0.32)
    base.mix_into(out, g.crackle(rng, 0.3, lambda t: 1600.0 * math.exp(-t / 0.09) * g.smoothstep(t / 0.015),
                                 lambda t: 0.06, band=(1400.0, 8000.0), crumple_share=0.35), 0.0, 1.0)
    if variant == 2:
        base.mix_into(out, metal([2350.0, 5620.0, 9100.0], [0.06, 0.03, 0.015], [1.0, 0.5, 0.2], 0.25, rng), 0.0, 0.25)
    return out


def weed_pluck(variant: int) -> list[float]:
    """A weed pulled: roots tearing, a 'thwip' as it comes free, dirt sprinkling."""
    rng = random.Random(6310 + variant)
    out = base.silence(0.4)
    tear = g.stick_slip(rng, 0.12, lambda t: 0.4 + 4.0 * t, tines=6, f=(500.0, 1400.0), tau=(1e-3, 3e-3), base=60.0, gain=220.0)
    base.mix_into(out, tear, 0.0, 1.0)
    base.mix_into(out, pluck_up(0.12, 330.0 + 30.0 * variant, 820.0, 30.0), 0.11, 0.7)
    base.mix_into(out, g.crackle(rng, 0.22, lambda t: 400.0 * math.exp(-t / 0.08), lambda t: 0.04,
                                 band=(600.0, 3500.0), crumple_share=0.4), 0.14, 1.0)
    return out


def gutter_gloop(variant: int) -> list[float]:
    """A handful of gutter goop: a wet GLORP (a resonant squelch rising and
    falling), and a drip off the end."""
    rng = random.Random(6320 + variant)
    out = base.silence(0.5)
    peak = 0.12 + 0.03 * variant
    center = lambda t: 260.0 + 700.0 * math.sin(math.pi * min(1.0, t / (peak * 2.0)))
    glorp = base.bandpass(base.lowpass(base.noise(rng, 0.3), 2500.0), center, 5.0)
    wobble = [v * (0.6 + 0.4 * math.sin(TAU * 23.0 * i / RATE)) for i, v in enumerate(glorp)]
    base.mix_into(out, base.envelope(wobble, 0.02, 0.08), 0.0, 1.0)
    base.mix_into(out, base.blip(0.1, 150.0, 90.0, 30.0), 0.0, 0.4)
    base.mix_into(out, pluck_up(0.07, 700.0, 1300.0, 70.0), 0.33 + 0.04 * variant, 0.35)
    return out


def squeegee(variant: int) -> list[float]:
    """A wet window wiped clean: the rubber blade's squeak rising across the
    glass, with the water swishing ahead of it."""
    rng = random.Random(6330 + variant)
    seconds = 0.36 + 0.04 * variant
    out = base.silence(seconds + 0.08)
    start = 820.0 + 90.0 * variant
    squeak = base.tone(seconds, base.glide(start, start * 1.45, seconds), "saw", (19.0, 0.03))
    squeak = base.bandpass(squeak, lambda t: 1500.0 + 900.0 * t / seconds, 3.5)
    shape = lambda t: math.sin(math.pi * min(1.0, t / seconds)) ** 0.7
    base.mix_into(out, [v * shape(i / RATE) for i, v in enumerate(squeak)], 0.0, 0.8)
    swish = base.bandpass(base.noise(rng, seconds), 3000.0, 0.9)
    base.mix_into(out, [v * shape(i / RATE) for i, v in enumerate(swish)], 0.0, 0.35)
    return out


def snip(variant: int) -> list[float]:
    """Hedge shears: two quick blades meeting (shink-shink) and a few clippings
    pattering into the hedge."""
    rng = random.Random(6340 + variant)
    out = base.silence(0.32)
    for at, weight in ((0.0, 1.0), (0.05 + 0.01 * variant, 0.75)):
        f = rng.uniform(3000.0, 3500.0)
        base.mix_into(out, metal([f, f * 1.57, f * 2.31], [0.014, 0.009, 0.006], [1.0, 0.6, 0.35], 0.1, rng), at, weight)
        base.mix_into(out, base.decay(base.highpass(base.noise(rng, 0.02), 4000.0), 250.0), at, 0.4 * weight)
    base.mix_into(out, g.crackle(rng, 0.2, lambda t: 300.0 * math.exp(-t / 0.07), lambda t: 0.03,
                                 band=(1800.0, 6000.0), crumple_share=0.2), 0.08, 1.0)
    return out


def splash_small(variant: int) -> list[float]:
    """The pool net dipping in and lifting out: a soft bloop, a little splash
    and drips."""
    rng = random.Random(6350 + variant)
    out = base.silence(0.5)
    base.mix_into(out, pluck_up(0.12, 380.0 + 40.0 * variant, 950.0, 28.0), 0.0, 0.9)
    base.mix_into(out, base.envelope(base.decay(base.highpass(base.noise(rng, 0.2), 1800.0), 14.0), 0.005, 0.1), 0.02, 0.45)
    droplets(rng, out, 0.12, 0.3, 9, 0.22)
    return out


# ---------------------------------------------------------------- the neighborhood

def crickets_loop() -> list[float]:
    """Night on the street: three crickets, each chirping in its own rhythm
    (trains of short pulses near 4.5 kHz), over the faintest high hiss. 6 s;
    every chirp that runs past the end comes back at the start."""
    rng = random.Random(6400)
    seconds = 6.0
    out = base.silence(seconds)
    crickets = ((4420.0, 0.62, 3, 1.0), (4710.0, 0.83, 4, 0.7), (4180.0, 1.17, 2, 0.5))
    for freq, every, pulses, gain in crickets:
        t = rng.uniform(0.0, every)
        while t < seconds:
            for pulse in range(pulses):
                chirp = base.envelope(base.tone(0.012, freq * rng.uniform(0.995, 1.005)), 0.002, 0.004)
                mix_wrap(out, chirp, t + pulse * 0.024, gain * rng.uniform(0.75, 1.0))
            t += every * rng.uniform(0.93, 1.07)
    # The hiss is noise: its own tail crossfaded into its head, so it wraps too.
    hiss = make_wrap(base.lowpass(base.highpass(base.noise(rng, seconds + 0.2), 3000.0), 7000.0), 0.2)
    for index, value in enumerate(hiss[:len(out)]):
        out[index] += value * 0.02
    return out


def owl(variant: int) -> list[float]:
    """An owl a few yards over: hoo, hoo-hoo, hoooo (the last one bending down)."""
    rng = random.Random(6410 + variant)
    pattern = ((0.0, 0.32), (0.55, 0.16), (0.76, 0.16), (1.02, 0.6)) if variant == 1 else ((0.0, 0.4), (0.6, 0.55))
    out = base.silence(1.8)
    pitch = 380.0 + 25.0 * variant
    for index, (at, length) in enumerate(pattern):
        last = index == len(pattern) - 1
        hoot = base.tone(length, base.glide(pitch * 1.03, pitch * (0.88 if last else 0.97), length), "sine", (5.0, 0.006))
        breath = base.bandpass(base.noise(rng, length), pitch * 2.0, 3.0)
        voiced = base.envelope([h + 0.12 * b for h, b in zip(hoot, breath)], 0.05, length * 0.5)
        base.mix_into(out, voiced, at, 1.0)
    return out


def store_hum_loop() -> list[float]:
    """Homie Depot through its sliding doors: the lights' 120 Hz buzz with its
    overtones, the HVAC breathing under it. 4 s, whole cycles of every tone."""
    rng = random.Random(6420)
    seconds = 4.0
    n = int(seconds * RATE)
    out = [0.0] * n
    for freq, amp in ((120.0, 1.0), (240.0, 0.5), (360.0, 0.3), (600.0, 0.12), (1080.0, 0.05)):
        # A slow beat on the buzz, 0.5 Hz, so it breathes (2 whole periods in 4 s).
        for index in range(n):
            t = index / RATE
            out[index] += amp * math.sin(TAU * freq * t) * (0.85 + 0.15 * math.sin(TAU * 0.5 * t))
    air = base.lowpass(base.noise(rng, seconds + 0.3), 700.0)
    air = make_wrap(air, 0.3)
    for index in range(n):
        out[index] = out[index] * 0.06 + air[index] * 0.9
    return out


def make_wrap(samples: list[float], fade_seconds: float) -> list[float]:
    """Crossfade a noise bed's tail into its head (make_loops.seamless)."""
    fade = int(fade_seconds * RATE)
    body = samples[: len(samples) - fade]
    tail = samples[len(samples) - fade:]
    for index in range(fade):
        mix = index / fade
        body[index] = body[index] * math.sqrt(mix) + tail[index] * math.sqrt(1.0 - mix)
    return body


def pa_chime(variant: int) -> list[float]:
    """The store PA: ding-dong, then Marty's voice through a tin speaker (a
    muffled babble nobody can make out), and a click as it shuts off."""
    rng = random.Random(6430 + variant)
    out = base.silence(2.9)
    for at, freq in ((0.0, 659.3), (0.42, 523.3)):
        bell = g.modal_click([freq, freq * 2.0, freq * 2.76, freq * 5.4], [0.45, 0.25, 0.15, 0.06], [1.0, 0.35, 0.25, 0.08], 1.2)
        base.mix_into(out, bell, at, 0.8)
    speech = base.silence(1.5)
    at = 0.0
    pitch = 150.0 + 18.0 * variant
    while at < 1.35:
        length = rng.uniform(0.07, 0.17)
        vowel = base.vowel(rng.choice(("a", "e", "o", "uh", "i")), length, base.glide(pitch * rng.uniform(0.95, 1.15), pitch * rng.uniform(0.85, 1.05), length), (6.0, 0.02))
        base.mix_into(speech, vowel, at, rng.uniform(0.6, 1.0))
        at += length + rng.uniform(0.0, 0.05)
    tin = base.bandpass(speech, 1300.0, 0.9)
    tin = [math.tanh(2.5 * v) for v in tin]
    base.mix_into(out, tin, 1.05, 1.6)
    base.mix_into(out, base.decay(base.highpass(base.noise(rng, 0.02), 2000.0), 200.0), 2.55, 0.15)
    return out


def cart_rattle(variant: int) -> list[float]:
    """A shopping cart pushed across the lot: wheels rumbling, the wire basket
    rattling over every crack, fading off (and nested into the corral with a
    clank on the second variant)."""
    rng = random.Random(6440 + variant)
    seconds = 1.9
    out = base.silence(seconds + 0.4)
    swell = lambda t: math.sin(math.pi * min(1.0, t / seconds)) ** 0.8
    rumble = g.onepole_lp(g.brown(rng, seconds, 0.995), 260.0)
    base.mix_into(out, [v * swell(i / RATE) * 0.25 for i, v in enumerate(rumble)], 0.0, 1.0)
    rattle = g.crackle(rng, seconds, lambda t: 70.0 * swell(t), lambda t: 0.06 * swell(t),
                       band=(1800.0, 5500.0), tau=(2e-3, 8e-3), cluster=(2, 5), gap=(4e-3, 1.4e-2))
    base.mix_into(out, rattle, 0.0, 1.0)
    # The wheels thump over the seams in the asphalt.
    t = 0.1
    while t < seconds - 0.1:
        base.mix_into(out, base.blip(0.06, 160.0, 110.0, 50.0), t, 0.25 * swell(t))
        t += rng.uniform(0.28, 0.42)
    if variant == 2:
        base.mix_into(out, metal([690.0, 1530.0, 2970.0], [0.12, 0.07, 0.04], [1.0, 0.5, 0.3], 0.5, rng), seconds - 0.15, 0.5)
    return out


def distant_mower() -> list[float]:
    """A neighbor mowing a few yards over: an engine's putter heard through
    houses (no highs), getting nearer and farther as it turns a row. 7 s."""
    rng = random.Random(6450)
    seconds = 7.0
    out = base.silence(seconds)
    t = 0.0
    rate = 24.0
    while t < seconds:
        pop = base.decay(base.lowpass(base.noise(rng, 0.03), 700.0), 150.0)
        base.mix_into(out, pop, t, 0.7 + rng.uniform(-0.12, 0.12))
        t += 1.0 / (rate * rng.uniform(0.95, 1.05) * (1.0 + 0.04 * math.sin(TAU * 0.3 * t)))
    body = base.lowpass(base.tone(seconds, lambda x: 98.0 * (1.0 + 0.03 * math.sin(TAU * 0.3 * x)), "square"), 450.0)
    base.mix_into(out, body, 0.0, 0.2)
    rows = lambda x: (0.55 + 0.45 * math.sin(TAU * x / 4.6 - 1.2)) * min(1.0, x / 0.8, (seconds - x) / 1.2)
    return base.lowpass([v * max(0.0, rows(i / RATE)) for i, v in enumerate(out)], 1200.0)


# ---------------------------------------------------------------- the table

# id -> (builder, variants or 0 for one file, RMS dBFS, loop). The RMS targets
# put each against the mix (docs/GAME.md "Foley"): impacts near the bonk
# (-20), handling sounds under a footstep's crunch, the neighborhood far under
# the work.
SOUNDS = {
    "paint_splat": (paint_splat, 0, -19.0, False),
    "splash": (splash, 0, -19.0, False),
    "land_thump": (land_thump, 2, -18.0, False),
    "grab_yoink": (grab_yoink, 0, -20.0, False),
    "throw_big": (throw_big, 0, -21.0, False),
    "punch_windup": (punch_windup, 0, -25.0, True),
    "foot_pop": (foot_pop, 0, -19.0, False),
    "ladder_clack": (ladder_clack, 0, -20.0, False),
    "ladder_crash": (ladder_crash, 0, -19.0, False),
    "hose_click": (hose_click, 0, -24.0, False),
    "bag_plop": (bag_plop, 0, -20.0, False),
    "pickup_light": (pickup_light, 0, -27.0, False),
    "pickup_heavy": (pickup_heavy, 0, -24.0, False),
    "sign_pull": (sign_pull, 0, -21.0, False),
    "litter_crinkle": (litter_crinkle, 3, -25.0, False),
    "weed_pluck": (weed_pluck, 3, -24.0, False),
    "gutter_gloop": (gutter_gloop, 2, -23.0, False),
    "squeegee": (squeegee, 2, -25.0, False),
    "snip": (snip, 3, -25.0, False),
    "splash_small": (splash_small, 2, -24.0, False),
    "crickets_loop": (crickets_loop, 0, -31.0, True),
    "owl": (owl, 2, -24.0, False),
    "store_hum_loop": (store_hum_loop, 0, -27.0, True),
    "pa_chime": (pa_chime, 2, -23.0, False),
    "cart_rattle": (cart_rattle, 2, -25.0, False),
    "distant_mower": (distant_mower, 0, -22.0, False),
}


def write_one(name: str, samples: list[float], rms_dbfs: float, loop: bool) -> None:
    path = write_loop(name, samples, rms_dbfs) if loop else g.write_rms(name, samples, rms_dbfs)
    print(f"wrote assets/audio/sfx/{path.name}")


if __name__ == "__main__":
    wanted = sys.argv[1:] or list(SOUNDS)
    for sound_name in wanted:
        build, variants, rms, loop = SOUNDS[sound_name]
        if variants:
            for variant in range(1, variants + 1):
                write_one(f"{sound_name}_{variant}", build(variant), rms, loop)
        else:
            write_one(sound_name, build(), rms, loop)
