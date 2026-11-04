#!/usr/bin/env python3
"""Synthesize the neighborhoods' own sounds (art chunk 9; docs/GAME.md "What
each neighborhood sounds like") into assets/audio/sfx/, with make_sfx.py's
oscillators, sfx_grains.py's physical models and sfx_foley.py's loop writer.

audio/ambience.gd plays them around the local player, by the hood the yard or
the town street is in (lot meta hood_style, TownMap.region_of):
  Mansion Hill      fountain_loop (at every tiered fountain, group ambient_emitters)
  Lakeside          lake_lap_loop (along the shore) and a goofy loon out on the water
  Maple Row         wind_chime on the porches
  Dandelion Acres   screen_door slapping shut, and a chained dog's dog_yip
  Oak Hollow        sprinkler_tick_loop at every lawn's sprinkler (7-9:30 AM, the
                    Approved Watering Window) and a neighbor's disapproving hoa_whistle
door_whoosh (Homie Depot's doors) lives in tools/sfx_store.py.

The sprinkler loop is timed to the sprinkler's head (props/sprinkler_jet.gd):
SPRINKLER_TICKS ticks SPRINKLER_TICK s apart as it steps across its arc, then
the fast ratchet back over SPRINKLER_RETURN s. They are Constants.SPRINKLER_*;
keep both in step (--art-test checks the file's length against them).

Cartoony, like everything else (docs/ART.md "Audio"): bloops, boings and
warbles, not field recordings. Tones and noise only, fixed seeds, identical
files on every run. Loops are built to wrap (whatever runs past the end lands
at the start).

Usage: python tools/sfx_hood.py              write all of them
       python tools/sfx_hood.py loon         write only that
"""
import math
import random
import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import make_sfx as base  # noqa: E402
import sfx_grains as g  # noqa: E402
import sfx_foley as foley  # noqa: E402

RATE = base.RATE
TAU = base.TAU

# Constants.SPRINKLER_TICK_SECONDS, SPRINKLER_TICKS, SPRINKLER_RETURN_SECONDS.
SPRINKLER_TICK = 0.2
SPRINKLER_TICKS = 20
SPRINKLER_RETURN = 1.2


# ---------------------------------------------------------------- helpers

def wrapped_noise(rng: random.Random, seconds: float, fade: float = 0.25) -> list[float]:
    """White noise exactly seconds long whose tail is crossfaded into its head."""
    return foley.make_wrap(base.noise(rng, seconds + fade), fade)


def plip(freq: float, seconds: float = 0.07) -> list[float]:
    """A water bloop: a sine that jumps up in pitch as the bubble closes."""
    return base.decay(base.tone(seconds, base.glide(freq, freq * 2.3, seconds * 0.7, 0.6)), 40.0)


# ---------------------------------------------------------------- the loops

def fountain_loop() -> list[float]:
    """Mansion Hill's tiered fountain: water pouring off each rim into the basin
    below (a bed of splashing noise that swells and settles), and the bubbly
    bloops of drops landing all over it. 4 s."""
    rng = random.Random(9100)
    seconds = 4.0
    n = int(seconds * RATE)
    out = [0.0] * n
    # The pour: noise through a soft band, breathing at 0.5 and 1.25 Hz (whole cycles).
    pour = base.bandpass(wrapped_noise(rng, seconds), 1100.0, 0.7)
    air = base.highpass(wrapped_noise(rng, seconds), 3500.0)
    for index in range(n):
        t = index / RATE
        swell = 0.8 + 0.12 * math.sin(TAU * 0.5 * t) + 0.08 * math.sin(TAU * 1.25 * t + 1.0)
        out[index] = pour[index] * 0.55 * swell + air[index] * 0.06
    # Drops: plenty, cartoon-bright, wrapped round the seam.
    for _ in range(150):
        at = rng.uniform(0.0, seconds)
        foley.mix_wrap(out, plip(g.loguniform(rng, 500.0, 1700.0), rng.uniform(0.04, 0.08)), at, rng.uniform(0.1, 0.32))
    return out


def lake_lap_loop() -> list[float]:
    """Lakeside's shore: little waves slopping against the sand and the dock
    posts (a low slosh that rises and draws back), a hollow knock under a dock
    now and then, and a plip or two. 8 s, four laps with their own timing."""
    rng = random.Random(9110)
    seconds = 8.0
    n = int(seconds * RATE)
    out = [0.0] * n
    bed = base.lowpass(wrapped_noise(rng, seconds, 0.4), 260.0)
    for index in range(n):
        out[index] = bed[index] * 0.25
    for at in (0.3, 2.2, 4.3, 6.1):
        length = rng.uniform(1.3, 1.7)
        slosh = base.noise(rng, length)
        # A lap: the wash comes up the sand (brighter as it breaks), then draws back.
        shaped = base.bandpass(slosh, lambda t, L=length: 380.0 + 900.0 * math.sin(math.pi * min(1.0, t / L)) ** 2, 0.8)
        envelope = []
        for index, value in enumerate(shaped):
            t = index / RATE
            rise = min(1.0, t / (length * 0.3))
            fall = max(0.0, 1.0 - max(0.0, t - length * 0.3) / (length * 0.7))
            envelope.append(value * rise * fall ** 1.6)
        foley.mix_wrap(out, envelope, at + rng.uniform(-0.1, 0.1), 0.9)
        # The water hitting a post: a hollow wooden knock and a bloop.
        if rng.random() < 0.7:
            knock = g.modal_click([180.0, 410.0, 760.0], [0.06, 0.03, 0.015], [1.0, 0.4, 0.2], 0.25)
            foley.mix_wrap(out, knock, at + length * 0.35, 0.22)
        foley.mix_wrap(out, plip(rng.uniform(420.0, 700.0), 0.09), at + length * 0.5, 0.12)
    return out


def sprinkler_tick_loop() -> list[float]:
    """Oak Hollow's impact sprinklers, every lawn's in step: the arm smacking the
    jet tick... tick... tick as the head steps across its arc, the spray's hiss
    stuttering at each smack, then the ratchet's fast brrrrrt back to the start.
    SPRINKLER_TICKS * SPRINKLER_TICK + SPRINKLER_RETURN s; the first tick at 0."""
    rng = random.Random(9120)
    seconds = SPRINKLER_TICKS * SPRINKLER_TICK + SPRINKLER_RETURN
    n = int(round(seconds * RATE))
    out = [0.0] * n
    # The spray: bright hiss, briefly choked each time the arm breaks the jet.
    hiss = base.bandpass(foley.make_wrap(base.noise(rng, seconds + 0.2), 0.2), 5200.0, 0.8)
    hits = [k * SPRINKLER_TICK for k in range(SPRINKLER_TICKS)]
    for index in range(n):
        t = index / RATE
        choke = 1.0
        for hit in hits:
            d = t - hit
            if 0.0 <= d < 0.09:
                choke = min(choke, 0.35 + 0.65 * d / 0.09)
        out[index] = hiss[index % len(hiss)] * 0.12 * choke
    # The arm: a sharp plastic-and-brass tick, a hair different every time.
    for hit in hits:
        tick = base.envelope(base.bandpass(base.noise(rng, 0.018), rng.uniform(2700.0, 3100.0), 2.2), 0.0005, 0.014)
        ring = g.modal_click([2250.0, 3900.0], [0.012, 0.006], [1.0, 0.35], 0.05)
        foley.mix_wrap(out, tick, hit, 1.0)
        foley.mix_wrap(out, ring, hit, 0.35)
    # The ratchet back: fast, smaller clicks.
    t = SPRINKLER_TICKS * SPRINKLER_TICK + 0.05
    end = seconds - 0.06
    while t < end:
        click = base.envelope(base.bandpass(base.noise(rng, 0.008), rng.uniform(3600.0, 4200.0), 2.5), 0.0005, 0.006)
        foley.mix_wrap(out, click, t, 0.42)
        t += rng.uniform(0.04, 0.05)
    return out


# ---------------------------------------------------------------- one-shots

def loon(variant: int) -> list[float]:
    """A loon out on the lake, but a goofy one: the long wail rising "ooo-WAAH-
    ooo" with a wobble, then (variant 2) the yodel's tremolo going off like a
    cartoon laugh, "hoo-hoo-hoo-hoo"."""
    rng = random.Random(9200 + variant)
    out = base.silence(3.2)
    pitch = 540.0 + 30.0 * variant
    wail = 1.5
    contour = lambda t: pitch * (1.0 + 0.62 * math.sin(math.pi * min(1.0, t / wail)) ** 1.4 - 0.08 * t / wail)
    voice = base.tone(wail, contour, "sine", (5.5, 0.012))
    over = base.tone(wail, lambda t: contour(t) * 2.0, "sine")
    breath = base.bandpass(base.noise(rng, wail), pitch * 2.2, 2.0)
    shaped = base.envelope([a + 0.16 * b + 0.05 * c for a, b, c in zip(voice, over, breath)], 0.12, 0.35)
    base.mix_into(out, shaped, 0.0, 1.0)
    if variant == 2:
        # The yodel: eight quick warbles on a wobbling pitch.
        at = 1.65
        for index in range(8):
            f = pitch * (1.45 if index % 2 == 0 else 1.2) * (1.0 - 0.015 * index)
            hoot = base.envelope(base.tone(0.11, base.glide(f * 0.94, f, 0.04), "sine", (9.0, 0.02)), 0.012, 0.05)
            base.mix_into(out, hoot, at, 0.75 - 0.04 * index)
            at += 0.13
    else:
        # A second, shorter wail, answered from farther off.
        echo = base.envelope(base.tone(0.8, lambda t: pitch * (1.0 + 0.45 * math.sin(math.pi * min(1.0, t / 0.8))), "sine", (5.0, 0.01)), 0.1, 0.3)
        base.mix_into(out, base.lowpass(echo, 1800.0), 1.8, 0.35)
    return out


def wind_chime(variant: int) -> list[float]:
    """Porch wind chimes on Maple Row: the breeze knocks the clapper into three
    to six tubes in a little tumble, each a bell partial set ringing out."""
    rng = random.Random(9300 + variant)
    out = base.silence(3.0)
    # A pentatonic set: C6 D6 E6 G6 A6 C7, every porch tuned the same.
    notes = [1046.5, 1174.7, 1318.5, 1568.0, 1760.0, 2093.0]
    at = 0.0
    for _ in range(rng.randint(3, 6)):
        f = rng.choice(notes)
        # A tube's modes (free-free bar ratios 1 : 2.76 : 5.40), the high ones short.
        strike = g.modal_click([f, f * 2.76, f * 5.4], [1.1, 0.35, 0.12], [1.0, 0.32, 0.12], 2.0)
        base.mix_into(out, strike, at, rng.uniform(0.45, 1.0))
        at += rng.uniform(0.09, 0.32)
    return out


def screen_door(variant: int) -> list[float]:
    """A Dandelion Acres screen door: the spring's creak as somebody lets it
    go, the frame's flat wooden SLAP, and its little rattle bouncing in the
    jamb (twice, on variant 2: it never catches the first time)."""
    rng = random.Random(9400 + variant)
    out = base.silence(1.3)
    # The creak: a rough, stick-slipping squeal sliding up.
    creak_len = 0.32 + 0.06 * variant
    rasp = base.tone(creak_len, base.glide(240.0, 420.0, creak_len), "saw", (31.0, 0.08))
    creak = base.envelope(base.bandpass(rasp, lambda t: 1300.0 + 1100.0 * t / creak_len, 3.5), 0.03, 0.06)
    base.mix_into(out, creak, 0.0, 0.5)
    slap_at = creak_len + 0.04
    bounces = (slap_at, slap_at + 0.16) if variant == 2 else (slap_at,)
    for index, at in enumerate(bounces):
        gain = 1.0 if index == 0 else 0.45
        thwack = base.envelope(base.lowpass(base.noise(rng, 0.06), 1400.0), 0.0008, 0.05)
        body = g.modal_click([210.0, 540.0, 1150.0], [0.05, 0.025, 0.012], [1.0, 0.5, 0.25], 0.2)
        base.mix_into(out, thwack, at, 1.2 * gain)
        base.mix_into(out, body, at, 0.8 * gain)
    # The screen and its latch rattling after.
    last = bounces[-1]
    for index in range(6):
        click = base.envelope(base.bandpass(base.noise(rng, 0.012), rng.uniform(1800.0, 2600.0), 2.0), 0.0005, 0.01)
        base.mix_into(out, click, last + 0.05 + index * 0.035 + rng.uniform(0.0, 0.01), 0.3 * (1.0 - index / 6.0))
    return out


def dog_yip(variant: int) -> list[float]:
    """The little dog on a chain two lots down: two or three high, nasal yips
    (a pitched "yap" through its own formants), and on variant 3 the chain
    jingling as it hits the end of it."""
    rng = random.Random(9500 + variant)
    out = base.silence(1.3)
    yips = 3 if variant == 1 else 2
    at = 0.0
    pitch = 760.0 + 60.0 * variant
    for index in range(yips):
        length = rng.uniform(0.09, 0.13)
        f = pitch * rng.uniform(0.95, 1.08)
        source = base.tone(length, base.glide(f * 1.25, f * 0.8, length), "saw")
        voiced = [a + 0.6 * b for a, b in zip(base.bandpass(source, 1500.0, 4.0), base.bandpass(source, 2700.0, 5.0))]
        bark = base.envelope(voiced, 0.004, length * 0.6)
        base.mix_into(out, bark, at, 1.0 - 0.1 * index)
        base.mix_into(out, base.envelope(base.bandpass(base.noise(rng, 0.03), 3200.0, 1.5), 0.002, 0.02), at, 0.12)
        at += length + rng.uniform(0.08, 0.14)
    if variant == 3:
        for index in range(7):
            link = g.modal_click([3400.0 + rng.uniform(-300, 300), 5200.0], [0.02, 0.01], [1.0, 0.4], 0.06)
            base.mix_into(out, link, at + 0.02 + index * 0.028 + rng.uniform(0.0, 0.012), 0.28)
    return out


def hoa_whistle(variant: int) -> list[float]:
    """Somebody in Oak Hollow has noticed something: a long, falling, deeply
    disappointed whistle, "fweeeee-ooo", and (variant 2) a tsk-tsk after it."""
    rng = random.Random(9600 + variant)
    out = base.silence(1.6)
    high = 2350.0 - 80.0 * variant
    first = 0.42
    fall = 0.48
    whistle = base.tone(first, base.glide(high * 0.97, high, 0.08), "sine", (6.0, 0.006))
    down = base.tone(fall, base.glide(high * 0.92, high * 0.6, fall, 0.8), "sine", (5.0, 0.01))
    breath = base.bandpass(base.noise(rng, first + fall), high, 3.0)
    base.mix_into(out, base.envelope(whistle, 0.03, 0.04), 0.0, 1.0)
    base.mix_into(out, base.envelope(down, 0.02, 0.2), first + 0.03, 0.9)
    base.mix_into(out, base.envelope(breath, 0.05, 0.2), 0.0, 0.05)
    if variant == 2:
        for at in (1.08, 1.27):
            tsk = base.envelope(base.bandpass(base.noise(rng, 0.03), 3600.0, 2.0), 0.001, 0.025)
            base.mix_into(out, tsk, at, 0.55)
    return out


# ---------------------------------------------------------------- the table

# id -> (builder, variants or 0 for one file, RMS dBFS, loop). The neighborhood
# sits far under the work, like the crickets (-31) and the store's hum (-27).
SOUNDS = {
    "fountain_loop": (fountain_loop, 0, -27.0, True),
    "lake_lap_loop": (lake_lap_loop, 0, -28.0, True),
    "sprinkler_tick_loop": (sprinkler_tick_loop, 0, -28.0, True),
    "loon": (loon, 2, -23.0, False),
    "wind_chime": (wind_chime, 3, -26.0, False),
    "screen_door": (screen_door, 2, -22.0, False),
    "dog_yip": (dog_yip, 3, -23.0, False),
    "hoa_whistle": (hoa_whistle, 2, -24.0, False),
}


if __name__ == "__main__":
    wanted = sys.argv[1:] or list(SOUNDS)
    for sound_name in wanted:
        build, variants, rms, loop = SOUNDS[sound_name]
        if variants:
            for variant in range(1, variants + 1):
                foley.write_one(f"{sound_name}_{variant}", build(variant), rms, loop)
        else:
            foley.write_one(sound_name, build(), rms, loop)
