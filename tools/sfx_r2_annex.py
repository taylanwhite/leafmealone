#!/usr/bin/env python3
"""Satellite Annex B's sounds (R2 chunk 5; docs/GAME.md "Satellite Annex B").

Built from tools/make_sfx.py's oscillators, noise and filters (import make_sfx
as base) and written by its write(), so every file is a project original. Seeds
are fixed: re-running writes identical files. Usage, from the repo root:
    python tools/sfx_r2_annex.py                 every sound here
    python tools/sfx_r2_annex.py desk_bell       just that one
The ids are registered in audio/sound_bank.gd under '# ---- R2:5'.

Office slapstick, never anybody's background (docs/ART.md, "Audio"): rubber
stamps, desk bells, blinds, a turnstile, a thermal printer, a party horn.
"""
import math
import random
import sys

import make_sfx as base

RATE = base.RATE
TAU = base.TAU


def _thump(seconds: float, start_hz: float, end_hz: float, fall: float, decay_rate: float) -> list:
    """A low body hit: a sine whose pitch falls fast, then dies."""
    out = []
    phase = 0.0
    for index in range(int(seconds * RATE)):
        t = index / RATE
        f = end_hz + (start_hz - end_hz) * math.exp(-t * fall)
        phase += TAU * f / RATE
        out.append(math.sin(phase) * math.exp(-t * decay_rate))
    return out


def _partials(seconds: float, root: float, parts: list) -> list:
    """A struck bar or bell: (ratio, gain, decay per second) partials."""
    out = base.silence(seconds)
    for ratio, gain, rate in parts:
        f = root * ratio
        for index in range(len(out)):
            t = index / RATE
            out[index] += gain * math.sin(TAU * f * t) * math.exp(-rate * t)
    return out


def _click(rng: random.Random, seconds: float, center: float, q: float, rate: float) -> list:
    return base.decay(base.bandpass(base.noise(rng, seconds), center, q), rate)


def stamp_kachunk(variant: int) -> list:
    """KA-CHUNK: the handle's clack, then the rubber block meets the pad and the
    desk under it. Three takes: a crisp one, a heavy one, a quick one."""
    rng = random.Random(5100 + variant)
    out = base.silence(0.42)
    gap = (0.055, 0.07, 0.045)[variant - 1]
    pitch = (1.0, 0.86, 1.1)[variant - 1]
    # R2c annex: the hit is sample 0. It is played on the frame the block meets
    # the pad, and the CHUNK used to come `gap` after a soft KA (46-82 ms late in
    # the recordings). Now the block, the felt and the desk land first with the
    # handle's clack on top, and the handle's spring snaps back (the KA) after.
    clack = _click(rng, 0.03, 2100.0 * pitch, 2.5, 160.0)
    chunk = _thump(0.32, 150.0 * pitch, 52.0 * pitch, 32.0, 14.0)
    felt = base.lowpass(base.decay(base.noise(rng, 0.2), 30.0), 900.0)
    knock = base.decay(base.tone(0.12, 310.0 * pitch, "triangle"), 38.0)
    base.mix_into(out, chunk, 0.0, 1.0)
    base.mix_into(out, felt, 0.0, 0.7)
    base.mix_into(out, knock, 0.0, 0.35)
    base.mix_into(out, clack, 0.0, 0.5)
    base.mix_into(out, base.decay(base.tone(0.03, 1750.0 * pitch, "triangle"), 140.0), gap, 0.22)
    base.mix_into(out, _click(rng, 0.02, 2600.0 * pitch, 3.0, 220.0), gap, 0.3)
    return base.envelope(out, 0.0008, 0.05)


def stamp_smudge() -> list:
    """Ink rubbed off a box: a rubbery drag that squeaks as it goes."""
    rng = random.Random(5110)
    seconds = 0.55
    drag = base.bandpass(base.noise(rng, seconds), lambda t: 700.0 - 380.0 * t / seconds, 3.0)
    stick = [0.55 + 0.45 * math.sin(TAU * 34.0 * index / RATE) ** 2 for index in range(len(drag))]
    squeak = base.tone(seconds, lambda t: 1250.0 - 420.0 * t / seconds, "sine", (31.0, 0.04))
    out = [d * s * 1.2 + 0.18 * q * s for d, s, q in zip(drag, stick, squeak)]
    return base.envelope(out, 0.03, 0.12)


def desk_bell() -> list:
    """The desk bell: a palm on the plunger, a bright ding that rings a while."""
    rng = random.Random(5120)
    out = _partials(1.4, 2350.0, [(1.0, 1.0, 3.2), (2.71, 0.38, 6.0), (5.18, 0.14, 11.0), (0.5, 0.08, 5.0)])
    base.mix_into(out, _click(rng, 0.01, 4200.0, 2.0, 600.0), 0.0, 0.5)
    return base.envelope(out, 0.001, 0.3)


def office_ding() -> list:
    """A window opens: one soft vibraphone 'bing' from the counter's lamp."""
    out = _partials(0.9, 1318.5, [(1.0, 1.0, 4.0), (4.0, 0.18, 9.0), (2.0, 0.08, 6.0)])
    trem = [1.0 - 0.18 * (0.5 + 0.5 * math.sin(TAU * 5.5 * index / RATE)) for index in range(len(out))]
    out = [a * b for a, b in zip(out, trem)]
    return base.envelope(out, 0.004, 0.25)


def blinds_rattle() -> list:
    """Venetian blinds yanked: the cord's zip and forty slats clattering in turn."""
    rng = random.Random(5130)
    seconds = 0.6
    out = base.silence(seconds)
    cord = base.bandpass(base.noise(rng, 0.45), lambda t: 1800.0 + 2600.0 * t / 0.45, 4.0)
    base.mix_into(out, base.envelope(cord, 0.02, 0.15), 0.0, 0.35)
    at = 0.01
    while at < seconds - 0.04:
        base.mix_into(out, _click(rng, 0.02, rng.uniform(2800.0, 4800.0), 3.0, 260.0), at, rng.uniform(0.35, 0.8))
        at += rng.uniform(0.008, 0.022)
    return base.envelope(out, 0.002, 0.08)


def shutter_roll() -> list:
    """A roller shutter coming down: a rumbling roll with the slats' tick, a clang at the bottom."""
    rng = random.Random(5140)
    seconds = 1.0
    roll = base.lowpass(base.noise(rng, 0.8), 380.0)
    ticks = [math.sin(TAU * 26.0 * index / RATE) ** 16 for index in range(len(roll))]
    out = base.silence(seconds)
    base.mix_into(out, [r * (0.6 + 0.8 * k) for r, k in zip(roll, ticks)], 0.0, 1.4)
    base.mix_into(out, _partials(0.25, 410.0, [(1.0, 0.6, 18.0), (2.3, 0.3, 26.0)]), 0.78, 0.8)
    return base.envelope(out, 0.05, 0.1)


def turnstile_clack() -> list:
    """The turnstile turns: a ratchet's three quick clacks and the arm settling."""
    rng = random.Random(5150)
    out = base.silence(0.38)
    for step, at in enumerate((0.0, 0.045, 0.09)):
        base.mix_into(out, _click(rng, 0.03, 2600.0 - step * 200.0, 4.0, 190.0), at, 0.9)
        base.mix_into(out, base.decay(base.tone(0.04, 1450.0, "square"), 160.0), at, 0.12)
    base.mix_into(out, _partials(0.25, 620.0, [(1.0, 0.5, 22.0), (2.7, 0.2, 35.0)]), 0.13, 0.6)
    return base.envelope(out, 0.001, 0.05)


def turnstile_clunk() -> list:
    """The turnstile won't turn: a dull locked thunk and a rattle of the arm."""
    rng = random.Random(5160)
    out = base.silence(0.45)
    base.mix_into(out, _thump(0.3, 240.0, 110.0, 30.0, 20.0), 0.0, 1.0)
    base.mix_into(out, base.lowpass(base.decay(base.noise(rng, 0.1), 45.0), 1500.0), 0.0, 0.5)
    for at in (0.06, 0.1, 0.13):
        base.mix_into(out, _click(rng, 0.02, 1900.0, 3.0, 220.0), at, 0.35)
    return base.envelope(out, 0.001, 0.08)


def door_chime() -> list:
    """The glass doors part: the shop door's two-note 'ding-dong'."""
    out = base.silence(1.3)
    base.mix_into(out, _partials(0.8, 659.25, [(1.0, 1.0, 3.0), (2.0, 0.25, 5.0), (3.01, 0.08, 8.0)]), 0.0, 0.8)
    base.mix_into(out, _partials(1.0, 523.25, [(1.0, 1.0, 2.6), (2.0, 0.25, 4.5), (3.01, 0.08, 7.0)]), 0.32, 0.85)
    return base.envelope(out, 0.002, 0.3)


def pen_squeak() -> list:
    """A felt marker on paper: two quick squeaky strokes."""
    rng = random.Random(5170)
    out = base.silence(0.5)
    for at, length, pitch in ((0.0, 0.16, 2900.0), (0.21, 0.22, 3300.0)):
        squeak = base.tone(length, lambda t, p=pitch: p - 600.0 * t, "sine", (47.0, 0.05))
        scratch = base.bandpass(base.noise(rng, length), pitch * 0.8, 2.0)
        stroke = [0.35 * a + 0.8 * b for a, b in zip(squeak, scratch)]
        base.mix_into(out, base.envelope(stroke, 0.015, 0.04), at, 1.0)
    return out


def receipt_print() -> list:
    """A thermal till printing a burst of lines: a buzzy hiss per line, the feed between."""
    rng = random.Random(5180)
    out = base.silence(1.2)
    at = 0.0
    for line in range(5):
        length = rng.uniform(0.11, 0.16)
        buzz = base.bandpass(base.noise(rng, length), 3800.0, 1.4)
        pulse = [0.5 + 0.5 * math.copysign(1.0, math.sin(TAU * 140.0 * index / RATE)) for index in range(len(buzz))]
        base.mix_into(out, base.envelope([a * b for a, b in zip(buzz, pulse)], 0.004, 0.01), at, 0.9)
        feed = base.decay(base.tone(0.06, 210.0, "square"), 50.0)
        base.mix_into(out, base.lowpass(feed, 900.0), at + length + 0.01, 0.35)
        at += length + 0.09
    return base.envelope(out, 0.002, 0.05)


def punch_card() -> list:
    """The greeter's hole punch: a spring creak, then a crisp 'chik' through the card."""
    rng = random.Random(5190)
    out = base.silence(0.32)
    base.mix_into(out, base.envelope(base.tone(0.1, lambda t: 900.0 + 900.0 * t / 0.1, "triangle", (60.0, 0.03)), 0.01, 0.03), 0.0, 0.18)
    base.mix_into(out, _click(rng, 0.04, 3300.0, 2.5, 140.0), 0.1, 1.0)
    base.mix_into(out, _thump(0.1, 600.0, 300.0, 40.0, 50.0), 0.1, 0.35)
    return base.envelope(out, 0.002, 0.05)


def copier_beep() -> list:
    """The copier's jam alarm: beep-beep, tinny and smug."""
    out = base.silence(0.42)
    for at in (0.0, 0.2):
        beep = base.lowpass(base.tone(0.12, 2050.0, "square"), 5000.0)
        base.mix_into(out, base.envelope(beep, 0.004, 0.01), at, 0.6)
    return out


def clerk_snore() -> list:
    """An asleep clerk: a long rattling inhale, a little whistle going out."""
    rng = random.Random(5200)
    out = base.silence(2.1)
    seconds = 1.1
    growl = base.tone(seconds, lambda t: 85.0 + 25.0 * t / seconds, "saw")
    flutter = [0.45 + 0.55 * max(0.0, math.sin(TAU * 27.0 * index / RATE)) for index in range(len(growl))]
    air = base.bandpass(base.noise(rng, seconds), 700.0, 0.8)
    rattle = base.lowpass([g * f for g, f in zip(growl, flutter)], 1100.0)
    inhale = [r * 0.9 + 0.3 * a for r, a in zip(rattle, air)]
    base.mix_into(out, base.envelope(inhale, 0.35, 0.2), 0.0, 1.0)
    whistle = base.tone(0.55, lambda t: 1100.0 - 420.0 * t / 0.55, "sine", (6.0, 0.02))
    breath = base.bandpass(base.noise(rng, 0.55), 1500.0, 1.0)
    base.mix_into(out, base.envelope([0.35 * a + 0.25 * b for a, b in zip(whistle, breath)], 0.08, 0.2), 1.25, 1.0)
    return out


def party_toot() -> list:
    """APPROVED, NICELY: a party horn blown once, the paper curl unrolling with it."""
    rng = random.Random(5210)
    seconds = 0.75
    honk = base.tone(seconds, lambda t: 620.0 + 140.0 * min(1.0, t / 0.08) + 25.0 * math.sin(TAU * 7.0 * t), "saw")
    nasal = [0.8 * a + 0.5 * b for a, b in zip(base.bandpass(honk, 1200.0, 2.5), base.bandpass(honk, 2600.0, 3.0))]
    crinkle = base.bandpass(base.noise(rng, seconds), 5000.0, 1.5)
    crinkle = [c * (0.5 + 0.5 * math.sin(TAU * 13.0 * index / RATE)) for index, c in enumerate(crinkle)]
    out = [a + 0.15 * b for a, b in zip(nasal, crinkle)]
    return base.envelope(out, 0.03, 0.18)


def closing_bell() -> list:
    """Closing time: the office's electric bell, a hammer buzzing on a gong for a second."""
    out = base.silence(1.6)
    ring = _partials(1.25, 1850.0, [(1.0, 1.0, 1.2), (2.43, 0.4, 2.5), (4.1, 0.15, 4.0)])
    hammer = [0.55 + 0.45 * abs(math.sin(TAU * 19.0 * index / RATE)) for index in range(len(ring))]
    base.mix_into(out, [a * b for a, b in zip(ring, hammer)], 0.0, 1.0)
    base.mix_into(out, _partials(0.6, 1850.0, [(1.0, 0.6, 4.0), (2.43, 0.2, 7.0)]), 1.0, 0.8)
    return base.envelope(out, 0.002, 0.3)


def lights_off_clunk() -> list:
    """A breaker thrown: a heavy CLUNK, and the tubes' hum dying with a tink."""
    rng = random.Random(5220)
    out = base.silence(0.7)
    base.mix_into(out, _thump(0.3, 180.0, 70.0, 26.0, 16.0), 0.0, 1.0)
    base.mix_into(out, base.lowpass(base.decay(base.noise(rng, 0.15), 40.0), 1200.0), 0.0, 0.6)
    hum = base.tone(0.6, lambda t: 120.0 - 40.0 * t / 0.6, "saw")
    base.mix_into(out, base.decay(base.lowpass(hum, 600.0), 7.0), 0.02, 0.18)
    base.mix_into(out, _partials(0.2, 3100.0, [(1.0, 1.0, 25.0)]), 0.12, 0.12)
    return base.envelope(out, 0.001, 0.1)


def office_phone() -> list:
    """A desk phone ringing in the back office: two warbling trills through a wall."""
    out = base.silence(1.6)
    for at in (0.0, 0.45):
        ring = base.tone(0.38, 1150.0, "sine")
        warble = [0.5 + 0.5 * math.copysign(1.0, math.sin(TAU * 20.0 * index / RATE)) for index in range(len(ring))]
        bell = [a * w for a, w in zip(ring, warble)]
        bell = [a + 0.5 * b for a, b in zip(bell, base.tone(0.38, 1380.0, "sine"))]
        base.mix_into(out, base.lowpass(base.envelope(bell, 0.01, 0.03), 2200.0), at, 1.0)
    return out


def typewriter_bed() -> list:
    """The office through a wall: three typists at their own pace, a carriage
    return now and then, a hum. Eight seconds that loop with no seam (every hit
    wraps round the end)."""
    rng = random.Random(5230)
    seconds = 8.0
    length = int(seconds * RATE)
    out = [0.0] * length

    def put(source: list, at: float, gain: float) -> None:
        start = int(at * RATE)
        for index, value in enumerate(source):
            out[(start + index) % length] += value * gain

    for typist, (rate, pitch, gain) in enumerate(((7.5, 1.0, 0.5), (5.0, 0.85, 0.35), (9.0, 1.15, 0.25))):
        at = rng.uniform(0.0, 0.5)
        while at < seconds:
            key = base.decay(base.bandpass(base.noise(rng, 0.03), 1900.0 * pitch * rng.uniform(0.9, 1.1), 3.0), 220.0)
            clack = base.decay(base.lowpass(base.noise(rng, 0.05), 900.0 * pitch), 90.0)
            put(key, at, gain)
            put(clack, at + 0.004, gain * 0.7)
            # A burst of words, then a pause to think.
            at += rng.uniform(0.6, 1.4) / rate if rng.random() < 0.85 else rng.uniform(0.5, 1.2)
        ding = _partials(0.7, 2650.0, [(1.0, 1.0, 6.0), (2.4, 0.2, 12.0)])
        put(ding, rng.uniform(1.0, seconds - 1.0), gain * 0.25)
    hum = base.lowpass(base.noise(rng, seconds), 200.0)
    for index in range(length):
        out[index] += hum[index] * 0.15
    # Heard from the next room: the top end rolled off.
    return base.lowpass(out, 3500.0)


# Name -> (builder, number of variants or 0 for one file, peak level 0..1).
SOUNDS = {
    "stamp_kachunk": (stamp_kachunk, 3, 0.85),
    "stamp_smudge": (stamp_smudge, 0, 0.55),
    "desk_bell": (desk_bell, 0, 0.6),
    "office_ding": (office_ding, 0, 0.45),
    "blinds_rattle": (blinds_rattle, 0, 0.6),
    "shutter_roll": (shutter_roll, 0, 0.6),
    "turnstile_clack": (turnstile_clack, 0, 0.7),
    "turnstile_clunk": (turnstile_clunk, 0, 0.75),
    "door_chime": (door_chime, 0, 0.5),
    "pen_squeak": (pen_squeak, 0, 0.45),
    "receipt_print": (receipt_print, 0, 0.5),
    "punch_card": (punch_card, 0, 0.6),
    "copier_beep": (copier_beep, 0, 0.4),
    "clerk_snore": (clerk_snore, 0, 0.55),
    "party_toot": (party_toot, 0, 0.65),
    "closing_bell": (closing_bell, 0, 0.6),
    "lights_off_clunk": (lights_off_clunk, 0, 0.75),
    "office_phone": (office_phone, 0, 0.4),
    "typewriter_bed": (typewriter_bed, 0, 0.5),
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
