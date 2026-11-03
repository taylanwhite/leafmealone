#!/usr/bin/env python3
"""The rake and leaf sounds (gap R1, chunk raking:5): recipes built from
tools/sfx_grains.py, and SOUNDS_RMS, the table tools/make_sfx.py writes them
from. docs/ART.md "Rake and leaf sounds" has the layers and the triggers
(audio/leaf_audio.gd plays them from the leaf field's stroke events).

Every recipe is one physical event driven by one speed curve, so its layers
move together: the plant is tines and soil taking a hit, the scrape is tines
stick-slipping over the ground, the leaf layers are dry leaves crackling in
proportion to how fast and how many are shoved. Seeds are fixed (re-running
writes identical files), and each variant is its own stroke (its own speed
curve, snags and grains), so repeats never sound like one file.

Kept out of make_sfx.py's SOUNDS dict on purpose: that dict is edited by many
chunks; this file is only the leaves'. Usage (through make_sfx.py):
  python tools/make_sfx.py rake_plant rake_scrape   only those
  python tools/make_sfx.py                          everything
Measure with: python tools/rake_audio_check.py [--png] [--preview]
"""
import math
import random

import sfx_grains as g

RATE = g.RATE


def _rng(seed: int, variant: int) -> random.Random:
    return random.Random(seed * 1000 + variant)


def _const(value: float):
    return lambda _t: value


# ---------------------------------------------------------------- the rake

def _knock(rng: random.Random, sec: float, weight: float, knock_f: float) -> list[float]:
    """The soil knock: the head's mass on soft ground, a low mode dead in ~15 ms
    and a puff of low-passed noise."""
    out = g.modal_click([knock_f, knock_f * 2.3], [rng.uniform(0.012, 0.018), 0.006], [0.3 * weight, 0.1 * weight], sec)
    thud = g.onepole_lp([v * math.exp(-i / (0.008 * RATE)) for i, v in enumerate(g.brown(rng, 0.05))], 380.0)
    return g.mix(out, thud, 0.0, 0.14 * weight)


def _contact(rng: random.Random, sec: float, weight: float, frame_f: float) -> list[float]:
    """The tines' side of one contact: the frame's clack, and the tines landing
    over a few ms, each a thin steel strip ringing high and briefly."""
    out = g.silence(sec)
    g.mix(out, g.modal_click([frame_f, frame_f * 2.71, frame_f * 5.2], [0.006, 0.003, 0.0013], [0.55, 0.35, 0.2], sec), 0.0, weight)
    for _ in range(rng.randint(9, 14)):
        f = g.loguniform(rng, 1900.0, 4200.0)
        at = abs(rng.gauss(0.0, 0.002))
        g.mix(out, g.modal_click([f, f * 2.9], [rng.uniform(0.002, 0.005), 0.0012], [rng.uniform(0.06, 0.14), 0.05], 0.05),
              at, weight)
    return out


# Each plant variant is a different way a head meets the ground, so no two share
# an envelope: (second contact s or 0, its weight, skid s, crunch tail s, twig s or 0).
PLANT_KINDS = {
    1: (0.0, 0.0, 0.0, 0.02, 0.0, 0.085),     # clean: the head lands flat
    2: (0.03, 0.85, 0.0, 0.025, 0.0, 0.085),  # heel, then the toe rocks down
    3: (0.1, 0.6, 0.085, 0.025, 0.0, 0.07),   # it skids a hand's width, then digs in
    4: (0.055, 0.7, 0.0, 0.02, 0.0, 0.085),   # lands on its heel, the toe slaps down late
    5: (0.065, 0.45, 0.0, 0.1, 0.0, 0.12),    # into deep litter, the springy head bounces once
    6: (0.0, 0.0, 0.0, 0.025, 0.1, 0.085),    # a twig under the tines snaps
}
# The share of a plant's energy in its soil knock (most of it under 300 Hz):
# the layers are balanced to it so a plant always has its weight.
PLANT_KNOCK_SHARE = 0.25


def rake_plant(variant: int) -> list[float]:
    """The head hits the litter: a dull soil knock, the tines' dry 'tk', and
    the first leaves crunching under them. PLANT_KINDS varies how it lands."""
    rng = _rng(71, variant)
    sec = 0.14
    second, second_weight, skid, crunch, twig, crunch_amp = PLANT_KINDS[(variant - 1) % len(PLANT_KINDS) + 1]
    knock_f = rng.uniform(95.0, 150.0)
    frame_f = rng.uniform(850.0, 1250.0)
    knock = _knock(rng, sec, 1.0, knock_f)
    out = _contact(rng, sec, 1.0, frame_f)
    if second > 0.0:
        g.mix(knock, _knock(rng, sec - second, second_weight, knock_f * 1.08), second)
        g.mix(out, _contact(rng, sec - second, second_weight, frame_f * 1.04), second)
    if skid > 0.0:
        drag = g.speed_curve(plant=0.006, pull=skid, lift=0.012, wobble=0.2, rng=rng, end_speed=0.5)
        g.mix(out, g.stick_slip(rng, sec, drag, tines=10, base=30.0, gain=220.0, fall=0.3), 0.004, 0.8)
    # Leaves under the tines: a crackle that dies with the impact (never louder than it).
    g.mix(out, g.crackle(rng, sec, lambda t: 1000.0 * math.exp(-t / crunch), _const(crunch_amp),
                         band=(1500.0, 7000.0), crumple_share=0.2 if crunch > 0.05 else 0.05, amp_cap=6.0), 0.001)
    if twig > 0.0:
        snap_f = rng.uniform(1400.0, 2200.0)
        g.mix(out, g.modal_click([snap_f, snap_f * 2.4, snap_f * 4.1], [0.005, 0.0025, 0.001], [0.65, 0.3, 0.15], 0.05), twig)
    return _balanced(out, knock, PLANT_KNOCK_SHARE)


# Each scrape variant is its own stroke: (plant s, push s, where in the push it
# is fastest, how slow it ends, snags).
SCRAPE_KINDS = (
    (0.02, 0.22, 0.0, 0.12, 1),     # a hard shove that dies off
    (0.02, 0.24, 0.15, 0.35, 2),    # steady, snagging twice
    (0.015, 0.18, 0.3, 0.2, 1),     # builds, then gives
    (0.025, 0.23, 0.0, 0.3, 4),     # choppy over lumpy ground
    (0.02, 0.15, 0.0, 0.1, 2),      # short and stopped by the load
    (0.025, 0.22, 0.0, 0.3, 3),     # snagging all the way
    (0.03, 0.17, 0.0, 0.35, 2),     # a short push that keeps its speed
    (0.015, 0.26, 0.0, 0.15, 3),    # long, catching on thatch
)


def rake_scrape(variant: int) -> list[float]:
    """The drive: a dozen tines stick-slipping over grass and soil, each release
    ringing its tine. Fast at first, slowing as leaves load the head, so the
    scritch falls in pitch and thins; under it the soil and grass rumble that
    the head drags (energy below 300 Hz). A snag or two where a tine catches."""
    rng = _rng(72, variant)
    sec = 0.30
    # Each variant is its own stroke: where it is fastest, how much it slows, where it snags.
    plant, pull, peak_at, end_speed, hitches = SCRAPE_KINDS[(variant - 1) % len(SCRAPE_KINDS)]
    speed = g.speed_curve(plant=plant, pull=pull, lift=0.035, wobble=rng.uniform(0.06, 0.16), rng=rng,
                          end_speed=end_speed, hitches=hitches, hitch_depth=rng.uniform(0.6, 0.95), peak_at=peak_at)
    out = g.stick_slip(rng, sec, speed, tines=12, f=(1700.0 * rng.uniform(0.92, 1.08), 3400.0 * rng.uniform(0.92, 1.08)),
                       tau=(0.0015, 0.004), base=40.0, gain=160.0, fall=0.4, regularity=0.5)
    # Grass blades flicking past the tines: soft broadband, louder the faster.
    hiss = g.onepole_hp([rng.uniform(-1.0, 1.0) for _ in range(len(out))], 3500.0)
    g.mix(out, [v * speed(i / RATE) ** 2 for i, v in enumerate(hiss)], 0.0, 0.035)
    # A few twigs under the tines.
    g.mix(out, g.crackle(rng, sec, lambda t: 30.0 * speed(t), _const(0.08), band=(1200.0, 5000.0), cluster=(1, 3)))
    # The ground: brown rumble whose power follows the drag power (friction
    # force x speed, so amplitude ~ sqrt(speed)), and the head bumping over
    # clods and roots (low knocks of the whole rake, more often and harder the
    # faster it goes): the lumpy weight under the scritch.
    rumble = g.onepole_lp(g.brown(rng, sec, 0.997), 260.0)
    level = g.rms_of(rumble) or 1.0
    ground = [v / level * speed(i / RATE) ** 0.5 * 0.09 for i, v in enumerate(rumble)]
    g.mix(ground, g.crackle(rng, sec, lambda t: 40.0 * speed(t), lambda t: 0.28 * min(1.0, speed(t)), band=(70.0, 190.0),
                            tau=(0.006, 0.014), alpha=3.0, cluster=(1, 2), gap=(0.004, 0.012), partial=(2.0, 2.6)))
    return _balanced(out, ground, SCRAPE_GROUND_SHARE)


# The share of a scrape's energy in the ground under it (mostly under 300 Hz).
SCRAPE_GROUND_SHARE = 0.2


def _balanced(top: list[float], bottom: list[float], share: float) -> list[float]:
    """top + bottom, with bottom scaled to 'share' of the energy: how a recipe
    keeps its weight however its random grains fall."""
    e_top = sum(v * v for v in top) or 1e-12
    e_bottom = sum(v * v for v in bottom) or 1e-12
    return g.mix(top, bottom, 0.0, math.sqrt(share / (1.0 - share) * e_top / e_bottom))


def rake_empty(variant: int) -> list[float]:
    """Tines over bare grass: a quiet swish of blades flicking, a faint
    scratch where they touch soil, and nothing crackling."""
    rng = _rng(73, variant)
    sec = 0.18
    # Variants: one brush; a steady one; a choppy one; two quick dabs (the head skips).
    pull, peak_at, end_speed, hitches = ((0.12, 0.0, 0.2, 1), (0.1, 0.4, 0.45, 2),
                                         (0.13, 0.15, 0.5, 3), (0.045, 0.0, 0.3, 0))[(variant - 1) % 4]
    first = g.speed_curve(plant=0.02, pull=pull, lift=0.03, wobble=0.12, rng=rng, end_speed=end_speed,
                          hitches=hitches, hitch_depth=rng.uniform(0.4, 0.8), peak_at=peak_at)
    skip = 0.085 if variant % 4 == 0 else 0.0
    dab = g.speed_curve(plant=0.015, pull=0.04, lift=0.025, wobble=0.12, rng=rng, end_speed=0.3)

    def speed(t: float) -> float:
        return max(first(t), 0.8 * dab(t - skip)) if skip > 0.0 else first(t)
    swish = g.biquad_bp([rng.uniform(-1.0, 1.0) for _ in range(int(sec * RATE))], rng.uniform(2600.0, 3600.0), 0.7)
    out = [v * speed(i / RATE) ** 2 for i, v in enumerate(swish)]
    g.mix(out, g.stick_slip(rng, sec, speed, tines=8, f=(1800.0, 3200.0), base=10.0, gain=60.0, fall=0.25), 0.0, 0.5)
    rumble = g.onepole_lp(g.brown(rng, sec, 0.997), 240.0)
    level = g.rms_of(rumble) or 1.0
    g.mix(out, [v / level * speed(i / RATE) ** 1.5 for i, v in enumerate(rumble)], 0.0, 0.06)
    return out


# ---------------------------------------------------------------- the leaves

# tier: (seconds, rate at full speed /s, amplitude, band, crumple share, body, pull, Pareto alpha)
LEAF_TIERS = {
    "light": (0.30, 420.0, 0.11, (1900.0, 8500.0), 0.08, 0.0, 0.2, 1.7),
    "med": (0.42, 900.0, 0.13, (1400.0, 7500.0), 0.16, 0.035, 0.26, 1.65),
    "heavy": (0.55, 1000.0, 0.15, (1000.0, 6800.0), 0.26, 0.025, 0.32, 1.4),
}


def _leaves(tier: str, variant: int, seed: int) -> list[float]:
    """Leaves shoved by the tines: crackle at a rate that follows the stroke's
    speed (more leaves, more breaks), then the leaves that flew pattering down
    as the stroke ends. Heavier tiers have more, larger, lower folds and the
    soft body of a mass of leaves sliding over each other."""
    sec, rate, amp, band, crumple, body, pull, alpha = LEAF_TIERS[tier]
    rng = _rng(seed, variant)
    speed = g.speed_curve(plant=rng.uniform(0.015, 0.035), pull=pull * rng.uniform(0.85, 1.1), lift=0.04,
                          wobble=rng.uniform(0.1, 0.2), rng=rng, end_speed=rng.uniform(0.25, 0.45),
                          hitches=rng.randint(1, 3), hitch_depth=rng.uniform(0.4, 0.8), peak_at=rng.uniform(0.0, 0.3))
    tail_at = speed.total * rng.uniform(0.75, 0.95)

    def rate_fn(t: float) -> float:
        # During the push, the shove; after it, the flown leaves landing.
        landing = 0.18 * rate * math.exp(-max(0.0, t - tail_at) / 0.07) if t > tail_at else 0.0
        return rate * speed(t) ** 1.3 + landing

    def amp_fn(t: float) -> float:
        return amp * (0.55 + 0.45 * min(1.0, speed(t))) * (1.0 if t < tail_at else 0.6)

    out = g.crackle(rng, sec, rate_fn, amp_fn, band=band, crumple_share=crumple, cluster=(1, 6), alpha=alpha)
    if body > 0.0:
        sliding = g.onepole_lp(g.onepole_hp([rng.uniform(-1.0, 1.0) for _ in range(len(out))], 300.0), 1400.0)
        level = g.rms_of(sliding) or 1.0
        g.mix(out, [v / level * speed(i / RATE) ** 2 for i, v in enumerate(sliding)], 0.0, body)
    return out


def rake_leaves_light(variant: int) -> list[float]:
    return _leaves("light", variant, 74)


def rake_leaves_med(variant: int) -> list[float]:
    return _leaves("med", variant, 75)


def rake_leaves_heavy(variant: int) -> list[float]:
    return _leaves("heavy", variant, 86)


def leaf_flick(variant: int) -> list[float]:
    """The wrist flicks the head up at the end of the drive: a short 'fwip' of
    leaves and tines through the air (aerodynamic noise, louder and brighter
    the faster: amplitude ~ v^3, cutoff ~ v) and the last leaves peeling off
    the tines."""
    rng = _rng(77, variant)
    sec = 0.22
    # Variants: a clean flick, a late one, a double shake, a lazy one.
    start, pull, shake = ((0.0, 0.07, 0.0), (0.05, 0.06, 0.0), (0.0, 0.04, 0.1), (0.02, 0.12, 0.0))[(variant - 1) % 4]
    first = g.speed_curve(plant=rng.uniform(0.012, 0.02), pull=pull, lift=0.04, wobble=0.05, rng=rng, end_speed=0.2)
    second = g.speed_curve(plant=0.012, pull=0.04, lift=0.03, wobble=0.05, rng=rng, end_speed=0.2)

    def speed(t: float) -> float:
        s = first(t - start)
        if shake > 0.0:
            s = max(s, 0.95 * second(t - start - shake))
        return s

    air = g.onepole_lp(g.onepole_hp([rng.uniform(-1.0, 1.0) for _ in range(int(sec * RATE))], 500.0),
                       lambda t: 700.0 + 3600.0 * speed(t))
    level = g.rms_of(air) or 1.0
    out = [v / level * speed(i / RATE) ** 3 * 0.35 for i, v in enumerate(air)]
    peel = start + first.total
    g.mix(out, g.crackle(rng, sec, lambda t: 500.0 * speed(t) + (60.0 * math.exp(-(t - peel) / 0.04) if t > peel else 0.0),
                         lambda t: 0.10 if t < peel else 0.06, band=(1800.0, 8000.0), cluster=(1, 4)))
    return out


def hand_scoop(variant: int) -> list[float]:
    """Two hands gathering leaves: a softer, lower crumple (palms muffle the
    snaps and fold the leaves in bigger pieces) as the hands squeeze and let go,
    over the swish of sleeves and gloves."""
    rng = _rng(78, variant)
    sec = 0.25
    squeeze = g.speed_curve(plant=rng.uniform(0.04, 0.07), pull=rng.uniform(0.08, 0.11), lift=0.07,
                            wobble=0.12, rng=rng, end_speed=0.6, hitches=1, hitch_depth=0.4)
    out = g.crackle(rng, sec, lambda t: 1100.0 * squeeze(t) ** 1.2, lambda t: 0.12 * (0.5 + 0.5 * squeeze(t)),
                    band=(900.0, 5200.0), crumple_share=0.35, cluster=(1, 5), tau=(6e-4, 3e-3))
    cloth = g.onepole_lp([rng.uniform(-1.0, 1.0) for _ in range(len(out))], 1100.0)
    level = g.rms_of(cloth) or 1.0
    g.mix(out, [v / level * squeeze(i / RATE) ** 2 for i, v in enumerate(cloth)], 0.0, 0.05)
    return out


# ---------------------------------------------------------------- bags

def bag_open(variant: int) -> list[float]:
    """A lawn bag snapped open: thin plastic film crinkling (stiff, light: very
    short, very bright clicks in bigger clusters), the 'fwap' of the film
    catching air, and the bag's own low membrane thump as it fills."""
    rng = _rng(79, variant)
    sec = 0.25
    snap_at = rng.uniform(0.07, 0.1)
    shake = g.speed_curve(plant=0.03, pull=snap_at - 0.03 + 0.06, lift=0.08, wobble=0.25, rng=rng,
                          end_speed=0.5, hitches=2, hitch_depth=0.5)
    out = g.crackle(rng, sec, lambda t: 1300.0 * shake(t), lambda t: 0.09, band=(2600.0, 11000.0),
                    tau=(2e-4, 1.1e-3), partial=(2.4, 3.1), cluster=(2, 9), gap=(5e-4, 4e-3))
    # The fwap: a burst of air pushed by the film, low-passed.
    air = g.onepole_lp([rng.uniform(-1.0, 1.0) for _ in range(int(0.08 * RATE))], 900.0)
    level = g.rms_of(air) or 1.0
    g.mix(out, [v / level * math.exp(-i / (0.018 * RATE)) for i, v in enumerate(air)], snap_at, 0.22)
    membrane = rng.uniform(80.0, 115.0)
    g.mix(out, g.modal_click([membrane, membrane * 1.6], [0.035, 0.015], [0.5, 0.2], 0.15), snap_at)
    return out


def bag_stuff(variant: int) -> list[float]:
    """Leaves crammed into the bag in two shoves: each a crunchy compression
    (dense, low crumple: many leaves breaking at once) and a whump as the
    shove hits the bag's bottom (a membrane mode that rises a little as the bag
    fills and tightens)."""
    rng = _rng(80, variant)
    sec = 0.60
    out = g.silence(sec)
    shoves = (rng.uniform(0.0, 0.02), rng.uniform(0.24, 0.3))
    membrane = rng.uniform(75.0, 100.0)
    for index, at in enumerate(shoves):
        push = g.speed_curve(plant=0.03, pull=rng.uniform(0.12, 0.16), lift=0.06, wobble=0.15, rng=rng,
                             end_speed=0.4, hitches=1, hitch_depth=0.5)
        length = push.total + 0.08
        g.mix(out, g.crackle(rng, length, lambda t, p=push: 1900.0 * p(t) ** 1.2, lambda t: 0.12,
                             band=(800.0, 6500.0), crumple_share=0.4, cluster=(2, 6)), at)
        f = membrane * (1.0 + 0.15 * index)
        g.mix(out, g.modal_click([f, f * 1.7, f * 2.6], [0.05, 0.02, 0.01], [0.75, 0.3, 0.12], 0.25), at + 0.035)
        thump = g.onepole_lp([v * math.exp(-i / (0.025 * RATE)) for i, v in enumerate(g.brown(rng, 0.12))], 320.0)
        g.mix(out, thump, at + 0.035, 0.6)
    return out


# Each tie variant is its own pair of hands: (gather s, twist s, twist turns, cinches).
TIE_KINDS = (
    (0.09, 0.12, 2, 1),    # gather the neck, two turns, pull it tight
    (0.06, 0.08, 1, 2),    # a quick twist and a double tug
    (0.12, 0.14, 3, 1),    # a slow gather, three turns, one hard yank
)


def bag_tie(variant: int) -> list[float]:
    """The full bag tied off (R1b): no thump (the stuffing's whumps are the bag's
    weight; a third would double them). The hands bunch the neck, so the thin
    film crinkles (bag_open's bright, tiny clicks, fewer and softer: less film
    moving); the neck is twisted, film sliding on film in short squeaks, each
    turn a burst of stick-slip at a plastic's low ring rising as the twist
    tightens; then the cinch: the tie pulled tight is a dry 'tk' of film under
    tension and a small knock of the bag's neck against the full bag."""
    rng = _rng(87, variant)
    sec = 0.36
    gather, twist, turns, cinches = TIE_KINDS[(variant - 1) % len(TIE_KINDS)]
    out = g.silence(sec)
    bunch = g.speed_curve(plant=0.02, pull=gather - 0.02, lift=0.03, wobble=0.2, rng=rng, end_speed=0.4, hitches=1)
    g.mix(out, g.crackle(rng, gather + 0.04, lambda t: 900.0 * bunch(t), lambda t: 0.06, band=(2800.0, 10000.0),
                         tau=(2e-4, 9e-4), partial=(2.4, 3.1), cluster=(2, 7), gap=(4e-4, 3e-3)))
    turn_len = twist / turns
    for k in range(turns):
        at = gather + k * turn_len
        spin = g.speed_curve(plant=0.012, pull=turn_len * 0.6, lift=turn_len * 0.3, wobble=0.15, rng=rng,
                             end_speed=0.5, hitches=1, hitch_depth=0.7)
        # Tighter each turn: the film grips harder, so the squeak rings higher.
        lift = 1.0 + 0.18 * k
        g.mix(out, g.stick_slip(rng, turn_len + 0.02, spin, tines=4, f=(700.0 * lift, 1500.0 * lift),
                                tau=(2e-3, 5e-3), base=30.0, gain=220.0, fall=0.25, regularity=0.6), at, 0.9)
    end = gather + twist
    for c in range(cinches):
        at = end + c * rng.uniform(0.05, 0.07)
        weight = 1.0 if c == cinches - 1 else 0.6
        snap = rng.uniform(1900.0, 2700.0)
        g.mix(out, g.modal_click([snap, snap * 2.3, snap * 3.7], [0.004, 0.002, 0.001], [0.5, 0.25, 0.12], 0.04), at, weight)
        knock = rng.uniform(150.0, 210.0)
        g.mix(out, g.modal_click([knock, knock * 1.9], [0.012, 0.006], [0.35, 0.1], 0.08), at + 0.003, weight)
    return out


# ---------------------------------------------------------------- landing, kicking, stepping

def leaf_settle(variant: int) -> list[float]:
    """Leaves landing on leaves: a soft patter, each leaf a light, duller tap
    (it lands flat on a soft bed: lower, longer rings, gentler amplitudes)."""
    rng = _rng(81, variant)
    sec = 0.35
    start = rng.uniform(140.0, 220.0)
    fall = rng.uniform(0.08, 0.14)
    out = g.crackle(rng, sec, lambda t: start * math.exp(-t / fall), lambda t: 0.1, band=(700.0, 3600.0),
                    tau=(1e-3, 4e-3), alpha=2.6, cluster=(1, 2), partial=(1.5, 2.0))
    brush = g.onepole_lp([rng.uniform(-1.0, 1.0) for _ in range(len(out))], 2400.0)
    level = g.rms_of(brush) or 1.0
    g.mix(out, [v / level * math.exp(-i / (0.09 * RATE)) for i, v in enumerate(brush)], 0.0, 0.02)
    return out


def pile_whump(variant: int) -> list[float]:
    """Leaves landing on a deep pile: a soft 'whump' (the pile is a big, lossy
    spring: a low mode that dies in ~50 ms and a puff of low-passed air) and a
    crackle as the top of the pile gives."""
    rng = _rng(82, variant)
    sec = 0.30
    out = g.silence(sec)
    # Variants: one clump; a clump and then the rest; a slow sink into the pile.
    kinds = ((((0.0, 1.0),), 0.05), (((0.0, 0.7), (0.07, 1.0)), 0.04), (((0.03, 0.8),), 0.14))
    hits, crackle_tau = kinds[(variant - 1) % len(kinds)]
    f = rng.uniform(58.0, 85.0)
    for at, weight in hits:
        g.mix(out, g.modal_click([f, f * 2.1], [0.05, 0.02], [0.9, 0.25], sec - at), at, weight)
        puff = g.onepole_lp([v * math.exp(-i / (0.045 * RATE)) for i, v in enumerate(g.brown(rng, 0.2, 0.99))], 380.0)
        g.mix(out, puff, at, 0.35 * weight)
    g.mix(out, g.crackle(rng, sec, lambda t: 1200.0 * math.exp(-t / crackle_tau), lambda t: 0.06, band=(900.0, 5500.0),
                         crumple_share=0.3), 0.004)
    return out


def leaf_kick(variant: int) -> list[float]:
    """A foot ploughing through leaves (or a pile thrown up): the swish of the
    leaf mass parting, a burst of crackle, and the scattered leaves landing."""
    rng = _rng(83, variant)
    sec = 0.30
    speed = g.speed_curve(plant=rng.uniform(0.02, 0.04), pull=rng.uniform(0.09, 0.12), lift=0.05, wobble=0.12,
                          rng=rng, end_speed=0.4, hitches=1)
    swish = g.onepole_lp(g.onepole_hp([rng.uniform(-1.0, 1.0) for _ in range(int(sec * RATE))], 250.0),
                         lambda t: 600.0 + 2200.0 * speed(t))
    level = g.rms_of(swish) or 1.0
    out = [v / level * speed(i / RATE) ** 2 * 0.06 for i, v in enumerate(swish)]
    tail = speed.total
    g.mix(out, g.crackle(rng, sec, lambda t: 1300.0 * speed(t) ** 1.2 + (90.0 * math.exp(-(t - tail) / 0.06) if t > tail else 0.0),
                         lambda t: 0.12 if t < tail else 0.06, band=(1100.0, 7000.0), crumple_share=0.2))
    return out


def _step(variant: int, seed: int, deep: float) -> list[float]:
    """A foot sinking into leaves: the heel compresses the bed (a crunch that
    rises fast and dies), the toe rolls through (a smaller crunch), and the
    ground under takes the weight (a low thump, softer the deeper the bed: a
    pile cushions the foot, so it is mostly crunch)."""
    rng = _rng(seed, variant)
    sec = 0.35
    out = g.silence(sec)
    # Variants: heel-toe; a slow step (late toe); flat-footed (one long crunch); a scuff.
    toe_at, toe_weight, heel_tau, scuff = ((0.1, 1.0, 0.03, 0.0), (0.21, 1.3, 0.025, 0.0),
                                           (0.0, 0.0, 0.08, 0.0), (0.07, 0.5, 0.02, 0.2))[(variant - 1) % 4]
    f = rng.uniform(95.0, 130.0) * (1.0 - 0.3 * deep)
    g.mix(out, g.modal_click([f, f * 2.2], [0.02 + 0.02 * deep, 0.008], [0.5 - 0.25 * deep, 0.12], 0.2))
    tau = heel_tau + 0.02 * deep
    g.mix(out, g.crackle(rng, sec, lambda t: 2200.0 * math.exp(-t / tau) * g.smoothstep(t / 0.01),
                         lambda t: 0.12, band=(1000.0 - 300.0 * deep, 6500.0), crumple_share=0.25 + 0.2 * deep))
    if toe_weight > 0.0:
        g.mix(out, g.crackle(rng, sec - toe_at, lambda t: 1300.0 * math.exp(-t / 0.03), lambda t: 0.08 * toe_weight,
                             band=(1200.0, 6500.0), crumple_share=0.2), toe_at + 0.02 * deep)
    if scuff > 0.0:
        drag = g.speed_curve(plant=0.02, pull=scuff, lift=0.03, wobble=0.2, rng=rng, end_speed=0.3, hitches=1)
        g.mix(out, g.crackle(rng, sec - 0.05, lambda t: 900.0 * drag(t), lambda t: 0.08, band=(1100.0, 6000.0)), 0.05)
    return out


def step_leaves_deep(variant: int) -> list[float]:
    return _step(variant, 84, 0.4)


def step_leaves_pile(variant: int) -> list[float]:
    return _step(variant, 85, 1.0)


# ---------------------------------------------------------------- the kept 'rake' id

def rake_legacy(variant: int) -> list[float]:
    """The old id 'rake', kept for whatever plays one stroke as one sound
    (audio:6's TASK_SOUNDS clear_roof: 'rake'): a plant, the scrape 15 ms
    later, and a light layer of leaves. 0.45 s."""
    out = g.silence(0.45)
    g.mix(out, rake_plant((1, 4, 5)[variant - 1]), 0.0, 1.0)
    g.mix(out, rake_scrape((2, 6, 5)[variant - 1]), 0.015, 0.8)
    g.mix(out, rake_leaves_light(variant + 3), 0.01, 0.9)
    return out


# id: (builder, variants, RMS dBFS, max seconds): gap-specs/raking.json contract C6.
SOUNDS_RMS = {
    "rake_plant": (rake_plant, 6, -24.0, 0.14),
    "rake_scrape": (rake_scrape, 8, -27.0, 0.30),
    "rake_empty": (rake_empty, 4, -32.0, 0.18),
    "rake_leaves_light": (rake_leaves_light, 6, -26.0, 0.30),
    "rake_leaves_med": (rake_leaves_med, 6, -23.0, 0.42),
    "rake_leaves_heavy": (rake_leaves_heavy, 6, -20.0, 0.55),
    "leaf_flick": (leaf_flick, 4, -27.0, 0.22),
    "hand_scoop": (hand_scoop, 4, -28.0, 0.25),
    "bag_open": (bag_open, 3, -24.0, 0.25),
    "bag_stuff": (bag_stuff, 4, -21.0, 0.60),
    "bag_tie": (bag_tie, 3, -27.0, 0.36),
    "leaf_settle": (leaf_settle, 6, -31.0, 0.35),
    "pile_whump": (pile_whump, 3, -24.0, 0.30),
    "leaf_kick": (leaf_kick, 4, -27.0, 0.30),
    "step_leaves_deep": (step_leaves_deep, 4, -29.0, 0.35),
    "step_leaves_pile": (step_leaves_pile, 4, -29.0, 0.35),
    "rake": (rake_legacy, 3, -25.0, 0.45),
}


def build(sound_id: str, variant: int) -> list[float]:
    """The samples of one variant (1-based), before loudness: what write_all writes."""
    builder, _variants, _rms, max_seconds = SOUNDS_RMS[sound_id]
    samples = builder(variant)
    return samples[:int(max_seconds * RATE)]


def write_all(wanted: list[str] | None = None) -> list[str]:
    """Writes every id in SOUNDS_RMS (or only the wanted ones) to assets/audio/sfx."""
    written = []
    for sound_id, (_builder, variants, rms_dbfs, _max) in SOUNDS_RMS.items():
        if wanted is not None and sound_id not in wanted:
            continue
        for variant in range(1, variants + 1):
            path = g.write_rms(f"{sound_id}_{variant}", build(sound_id, variant), rms_dbfs)
            written.append(path.name)
            print(f"wrote assets/audio/sfx/{path.name}")
    return written
