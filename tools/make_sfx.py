#!/usr/bin/env python3
"""Synthesize the game's sounds into assets/audio/sfx/.

The audio direction is goofy cartoon (docs/ART.md, "Audio"): pomfs, swooshes,
honks, brass stabs, slide whistles, and characters who make silly noises and
babble gibberish instead of talking. Everything is generated here from tones,
noise, and a small formant voice synthesizer, so every file is a project
original: nothing downloaded, nothing AI-generated. Seeds are fixed, so
re-running writes identical files. Frequent sounds come in numbered variants
(step_1.wav ...) that audio/sfx.gd picks between.

Usage: python3 tools/make_sfx.py              write everything
       python3 tools/make_sfx.py vo_oof babble write only those
"""
import math
import pathlib
import random
import struct
import sys
import wave

# The rake and leaf sounds (gap R1, raking:5) live in their own recipe file.
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import sfx_leaves  # noqa: E402

RATE = 44100
OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "audio" / "sfx"
TAU = 2.0 * math.pi


# ---------------------------------------------------------------- building blocks

def silence(seconds: float) -> list[float]:
    return [0.0] * int(seconds * RATE)


def mix_into(target: list[float], source: list[float], at_seconds: float, gain: float = 1.0) -> None:
    start = int(at_seconds * RATE)
    for index, value in enumerate(source):
        if 0 <= start + index < len(target):
            target[start + index] += value * gain


def noise(rng: random.Random, seconds: float) -> list[float]:
    return [rng.uniform(-1.0, 1.0) for _ in range(int(seconds * RATE))]


def lowpass(samples: list[float], cutoff: float) -> list[float]:
    alpha = 1.0 - math.exp(-TAU * cutoff / RATE)
    out, state = [], 0.0
    for value in samples:
        state += alpha * (value - state)
        out.append(state)
    return out


def highpass(samples: list[float], cutoff: float) -> list[float]:
    return [value - smooth for value, smooth in zip(samples, lowpass(samples, cutoff))]


def bandpass(samples: list[float], center, q: float = 1.0) -> list[float]:
    """RBJ biquad band-pass. center is a number or a function of time in seconds."""
    out = []
    x1 = x2 = y1 = y2 = 0.0
    fixed = not callable(center)
    if fixed:
        coefficients = _bandpass_coefficients(center, q)
    for index, x in enumerate(samples):
        if not fixed:
            coefficients = _bandpass_coefficients(center(index / RATE), q)
        b0, b2, a0, a1, a2 = coefficients
        y = (b0 * x + b2 * x2 - a1 * y1 - a2 * y2) / a0
        out.append(y)
        x2, x1, y2, y1 = x1, x, y1, y
    return out


def _bandpass_coefficients(center: float, q: float) -> tuple:
    w = TAU * min(center, RATE * 0.45) / RATE
    alpha = math.sin(w) / (2.0 * q)
    return alpha, -alpha, 1.0 + alpha, -2.0 * math.cos(w), 1.0 - alpha


def envelope(samples: list[float], attack: float, release: float) -> list[float]:
    length = len(samples)
    attack_n = max(1, int(attack * RATE))
    release_n = max(1, int(release * RATE))
    out = []
    for index, value in enumerate(samples):
        gain = min(1.0, index / attack_n, (length - index) / release_n)
        out.append(value * max(0.0, gain))
    return out


def decay(samples: list[float], rate: float) -> list[float]:
    return [value * math.exp(-rate * index / RATE) for index, value in enumerate(samples)]


def tone(seconds: float, freq, shape: str = "sine", vibrato: tuple = (0.0, 0.0)) -> list[float]:
    """An oscillator. freq is Hz or a function of time. vibrato is (rate Hz, depth as a fraction)."""
    out, phase = [], 0.0
    for index in range(int(seconds * RATE)):
        t = index / RATE
        f = freq(t) if callable(freq) else freq
        if vibrato[0] > 0.0:
            f *= 1.0 + vibrato[1] * math.sin(TAU * vibrato[0] * t)
        phase = (phase + f / RATE) % 1.0
        if shape == "saw":
            out.append(2.0 * phase - 1.0)
        elif shape == "square":
            out.append(1.0 if phase < 0.5 else -1.0)
        elif shape == "triangle":
            out.append(4.0 * abs(phase - 0.5) - 1.0)
        else:
            out.append(math.sin(TAU * phase))
    return out


def glide(start: float, end: float, seconds: float, curve: float = 1.0):
    """A pitch that slides from start to end over seconds, then holds."""
    return lambda t: start + (end - start) * min(1.0, t / seconds) ** curve


def blip(seconds: float, start_hz: float, end_hz: float, decay_rate: float) -> list[float]:
    """A cartoon pomf: a sine that drops in pitch and dies."""
    return decay(tone(seconds, glide(start_hz, end_hz, seconds * 0.6)), decay_rate)


# ---------------------------------------------------------------- the voice

# Formants (Hz) for each vowel: the resonances that make an "a" sound like "a".
VOWELS = {
    "a": (800, 1200, 2700),
    "e": (480, 1900, 2600),
    "i": (320, 2300, 3000),
    "o": (480, 820, 2600),
    "u": (340, 720, 2400),
    "uh": (620, 1150, 2600),
}


def vowel(name: str, seconds: float, pitch, vibrato: tuple = (6.0, 0.02)) -> list[float]:
    """A sung vowel: a buzzy source shaped by the vowel's three formants."""
    source = tone(seconds, pitch, "saw", vibrato)
    f1, f2, f3 = VOWELS[name]
    voiced = [a + 0.55 * b + 0.25 * c for a, b, c in zip(
        bandpass(source, f1, 6.0), bandpass(source, f2, 8.0), bandpass(source, f3, 9.0))]
    return envelope(voiced, 0.012, min(0.04, seconds * 0.4))


def breath(rng: random.Random, seconds: float, center: float) -> list[float]:
    """An h or f: shaped breath noise."""
    return envelope(bandpass(noise(rng, seconds), center, 0.8), 0.01, seconds * 0.6)


def voice_line(parts: list, seconds: float) -> list[float]:
    out = silence(seconds)
    for at, samples, gain in parts:
        mix_into(out, samples, at, gain)
    return out


def vo_ah() -> list[float]:
    """'Ah?' Confused, rising."""
    return voice_line([(0.0, vowel("a", 0.32, glide(210, 330, 0.3, 1.6)), 1.0)], 0.34)


def vo_eh() -> list[float]:
    """'Eh?' Short and puzzled."""
    return voice_line([(0.0, vowel("e", 0.24, glide(230, 340, 0.22, 2.0)), 1.0)], 0.26)


def vo_huh() -> list[float]:
    rng = random.Random(901)
    return voice_line([
        (0.0, breath(rng, 0.07, 1500.0), 0.5),
        (0.05, vowel("uh", 0.26, glide(200, 310, 0.24, 1.8)), 1.0),
    ], 0.33)


def vo_oof() -> list[float]:
    """'Oof!' Winded: a dropping 'oo' that runs out into an 'f'."""
    rng = random.Random(902)
    return voice_line([
        (0.0, vowel("u", 0.2, glide(300, 170, 0.18)), 1.0),
        (0.17, breath(rng, 0.13, 4500.0), 0.45),
    ], 0.32)


def vo_hup() -> list[float]:
    """'Hup!' A little jump grunt."""
    rng = random.Random(903)
    out = voice_line([
        (0.0, breath(rng, 0.04, 1600.0), 0.5),
        (0.03, vowel("uh", 0.08, glide(290, 340, 0.08)), 1.0),
    ], 0.13)
    return out


def vo_yelp() -> list[float]:
    """'Aah?!' Grabbed by the crew: a startled yelp that shoots up and wobbles."""
    return voice_line([(0.0, vowel("a", 0.42, glide(260, 560, 0.15, 0.7), (9.0, 0.05)), 1.0)], 0.44)


def vo_strain() -> list[float]:
    """'Nnnngh...': straining to hold something up, a closed-mouth hum that climbs and quivers."""
    hum = vowel("u", 0.75, glide(170.0, 260.0, 0.7, 1.4), (11.0, 0.05))
    return envelope(lowpass(hum, 1400.0), 0.06, 0.15)


def vo_heave() -> list[float]:
    """'Hyah!': the grunt of a big throw, a breath and a punchy 'ah' that drops."""
    rng = random.Random(5)
    out = silence(0.4)
    mix_into(out, breath(rng, 0.07, 1800.0), 0.0, 0.5)
    mix_into(out, envelope(vowel("a", 0.26, glide(330.0, 220.0, 0.24), (8.0, 0.02)), 0.02, 0.1), 0.05, 1.0)
    return out


def babble(variant: int) -> list[float]:
    """Gibberish talking: quick syllables hopping between vowels and pitches, 'ewewewew'."""
    rng = random.Random(1000 + variant)
    out = silence(0.95)
    at = 0.0
    base = 300.0 + variant * 12.0
    names = ["e", "u", "i", "a", "o", "e", "u"]
    while at < 0.82:
        length = rng.uniform(0.045, 0.085)
        start = base * rng.choice([0.9, 1.0, 1.1, 1.25, 1.35])
        end = start * rng.uniform(0.85, 1.2)
        mix_into(out, vowel(rng.choice(names), length, glide(start, end, length), (0.0, 0.0)), at, 1.0)
        at += length + rng.uniform(0.0, 0.02)
    return out


# ---------------------------------------------------------------- cartoon effects

def step(variant: int) -> list[float]:
    """A soft cartoon pomf with a tiny leafy scrunch."""
    rng = random.Random(100 + variant)
    out = silence(0.12)
    mix_into(out, blip(0.1, 170.0 + variant * 14.0, 85.0, 32.0), 0.0, 0.9)
    mix_into(out, decay(highpass(noise(rng, 0.04), 3000.0), 90.0), 0.0, 0.35)
    return out


def rake(variant: int) -> list[float]:
    """One stroke as one sound (plant, scrape, light leaves): tools/sfx_leaves.py.
    Written by sfx_leaves.SOUNDS_RMS at its RMS target, not from SOUNDS below."""
    return sfx_leaves.rake_legacy(variant)


def bag(variant: int) -> list[float]:
    """Floomp: leaves stuffed in a bag, and a rubbery squeak as it ties off."""
    rng = random.Random(300 + variant)
    out = silence(0.5)
    mix_into(out, blip(0.22, 320.0, 70.0, 12.0), 0.0, 1.0)
    mix_into(out, envelope(lowpass(noise(rng, 0.18), 700.0), 0.01, 0.12), 0.0, 1.6)
    squeak = tone(0.12, glide(950.0 + variant * 60.0, 1400.0, 0.12), "sine", (30.0, 0.04))
    mix_into(out, envelope(squeak, 0.01, 0.04), 0.3, 0.35)
    return out


def putt_putt(rng: random.Random, seconds: float, start_rate: float, end_rate: float, pitch: float) -> list[float]:
    """A jalopy engine: a run of little pops that speeds up as it drives off."""
    out = silence(seconds)
    t = 0.0
    while t < seconds - 0.1:
        progress = t / seconds
        level = min(1.0, t / 0.2) * min(1.0, (seconds - t) / (seconds * 0.4))
        mix_into(out, blip(0.07, pitch * 1.6, pitch, 45.0), t, 0.8 * level)
        mix_into(out, decay(lowpass(noise(rng, 0.05), 900.0), 60.0), t, 1.2 * level)
        t += 1.0 / (start_rate + (end_rate - start_rate) * progress)
    return out


def horn(notes: list[float], note_seconds: float, gap: float) -> list[float]:
    """A squeaky toy horn: a nasal square wave per note."""
    out = silence(len(notes) * (note_seconds + gap))
    for index, freq in enumerate(notes):
        honk = bandpass(tone(note_seconds, freq, "square", (14.0, 0.01)), freq * 2.2, 1.4)
        mix_into(out, envelope(honk, 0.01, 0.03), index * (note_seconds + gap), 1.0)
    return out


def truck() -> list[float]:
    """Chefty: meep meep, then putt-putt-putt off down the road."""
    rng = random.Random(400)
    out = silence(2.6)
    mix_into(out, horn([660.0, 660.0], 0.11, 0.06), 0.0, 0.5)
    mix_into(out, putt_putt(rng, 2.2, 6.0, 15.0, 90.0), 0.35, 1.0)
    return out


def van() -> list[float]:
    """The crew van: a door bonk, a low honk-honk, and a grumpier putt-putt."""
    rng = random.Random(500)
    out = silence(2.9)
    mix_into(out, blip(0.2, 240.0, 60.0, 18.0), 0.0, 0.9)
    mix_into(out, horn([233.0, 196.0], 0.16, 0.05), 0.15, 0.6)
    mix_into(out, putt_putt(rng, 2.3, 4.5, 11.0, 65.0), 0.55, 1.0)
    return out


def van_honk() -> list[float]:
    """The crew van's horn alone, for the pull-up (net/run_events/van_arrival.gd):
    the same low honk-honk as van(), with no door bonk, played while it drives."""
    out = silence(0.5)
    mix_into(out, horn([233.0, 196.0], 0.16, 0.05), 0.0, 0.6)
    return out


def truck_horn() -> list[float]:
    """Chefty's horn (the drivable one): a short 'bwah' and a long 'BWAAH', a
    nasal, slightly flat two-tone like a delivery truck that's seen things."""
    out = silence(0.75)
    for start, seconds, freq, gain in [(0.0, 0.13, 311.0, 0.75), (0.17, 0.5, 415.0, 1.0)]:
        raw = tone(seconds, glide(freq * 0.97, freq, seconds * 0.4), "square", (9.0, 0.012))
        nasal = [a + 0.5 * b for a, b in zip(bandpass(raw, freq * 2.0, 1.3), bandpass(raw, freq * 4.1, 2.0))]
        mix_into(out, envelope(nasal, 0.012, 0.05), start, gain)
    return out


def door_slam() -> list[float]:
    """Chefty's door: a hollow 'bonk' and a padded 'thunk' as the latch catches."""
    rng = random.Random(610)
    out = silence(0.45)
    mix_into(out, blip(0.16, 320.0, 140.0, 22.0), 0.0, 0.8)
    mix_into(out, decay(lowpass(noise(rng, 0.12), 500.0), 35.0), 0.0, 0.9)
    mix_into(out, blip(0.12, 150.0, 70.0, 30.0), 0.09, 1.0)
    mix_into(out, decay(highpass(noise(rng, 0.03), 2500.0), 120.0), 0.09, 0.25)
    return out


def skid() -> list[float]:
    """Tires squealing as Chefty sheds speed or slides: a wobbly rubbery whistle
    that sags in pitch over a hiss. A one-shot (critic C12: audio's `skid`);
    chefty_drive.gd fires it again while a drift lasts."""
    rng = random.Random(72)
    seconds = 0.7
    squeal = bandpass(tone(seconds, glide(1380.0, 1120.0, seconds), "triangle", (11.0, 0.03)), 1250.0, 2.0)
    hiss = bandpass(noise(rng, seconds), 2600.0, 1.5)
    return envelope([a * 0.8 + b * 0.35 for a, b in zip(squeal, hiss)], 0.02, 0.3)


def van_brake() -> list[float]:
    """The Courtesy Shuttle's brakes as it pulls up: a rubbery bite you hear land
    (a short bright chirp at full level from the first few ms), then a squeal that
    sags in pitch as the van sheds speed, over a hiss, fading as it stops. Louder
    and longer than Chefty's drift `skid`, and carries farther (sound_bank.gd): the
    van's own engine buried the skid it used to borrow (R2c van review)."""
    rng = random.Random(91)
    seconds = 1.05
    out = silence(seconds)
    bite = envelope(bandpass(noise(rng, 0.08), 3000.0, 1.2), 0.002, 0.06)
    mix_into(out, bite, 0.0, 0.9)
    squeal = bandpass(tone(seconds, glide(1520.0, 1050.0, seconds), "triangle", (13.0, 0.035)), 1300.0, 1.6)
    hiss = bandpass(noise(rng, seconds), 2800.0, 1.4)
    mix_into(out, envelope([a + b * 0.4 for a, b in zip(squeal, hiss)], 0.006, 0.4), 0.0, 1.0)
    return out


def brass(seconds: float, freq, vibrato: tuple = (5.5, 0.012)) -> list[float]:
    """A cartoon trombone: a saw shaped to sound like a brass 'bwah'."""
    raw = tone(seconds, freq, "saw", vibrato)
    shaped = [a + 0.6 * b for a, b in zip(bandpass(raw, 550.0, 1.2), bandpass(raw, 1300.0, 1.5))]
    return envelope(shaped, 0.03, 0.08)


def warning() -> list[float]:
    """'Uh-oh': two trombone notes, the second sliding down and wobbling."""
    out = silence(1.3)
    mix_into(out, brass(0.32, 196.0), 0.0, 1.0)
    mix_into(out, brass(0.85, glide(165.0, 138.0, 0.7), (6.0, 0.03)), 0.36, 1.0)
    return out


def radio() -> list[float]:
    """A walkie-talkie: squelch click, a chipmunk babbling through it, squelch tail."""
    rng = random.Random(600)
    out = silence(1.3)
    click = decay(bandpass(noise(rng, 0.02), 2500.0, 1.4), 400.0)
    mix_into(out, click, 0.0, 0.8)
    chatter = babble(9)
    # Up an octave and squeezed through a small speaker.
    fast = [chatter[min(len(chatter) - 1, int(index * 1.6))] for index in range(int(len(chatter) / 1.6))]
    squeezed = bandpass(bandpass(fast, 1500.0, 0.9), 1500.0, 0.9)
    mix_into(out, squeezed, 0.05, 2.5)
    mix_into(out, [v * 0.06 for v in bandpass(noise(rng, 0.6), 2400.0, 0.6)], 0.05, 1.0)
    mix_into(out, envelope(highpass(noise(rng, 0.2), 1500.0), 0.005, 0.15), 0.68, 0.35)
    mix_into(out, click, 0.9, 0.6)
    return out


def arrive() -> list[float]:
    """'Dun dun DUNNN': the crew is here."""
    out = silence(1.7)
    for at, freq, length in ((0.0, 131.0, 0.16), (0.22, 131.0, 0.16), (0.44, 156.0, 1.1)):
        stab = brass(length, freq, (6.0, 0.02 if length > 0.5 else 0.0))
        low = brass(length, freq / 2.0)
        mix_into(out, [a + 0.6 * b for a, b in zip(stab, low)], at, 1.0)
    return out


def tick() -> list[float]:
    """A cartoon clock tock: a hollow wood block."""
    out = decay(tone(0.1, 900.0, "triangle"), 55.0)
    return [value + 0.4 * other for value, other in zip(out, decay(tone(0.1, 1800.0), 90.0))]


def clear() -> list[float]:
    """All clear: a slide whistle up and a sparkly ding."""
    out = silence(1.2)
    whistle = tone(0.5, glide(500.0, 1500.0, 0.48, 1.2), "sine", (7.0, 0.01))
    mix_into(out, envelope(whistle, 0.03, 0.06), 0.0, 0.8)
    for index, freq in enumerate((1568.0, 2093.0)):
        ding = decay(tone(0.6, freq), 6.0)
        mix_into(out, [a + 0.3 * b for a, b in zip(ding, decay(tone(0.6, freq * 2.7), 12.0))], 0.5 + index * 0.08, 0.35)
    return out


def bonk(variant: int) -> list[float]:
    """A cartoon bonk on the head: a hollow wooden knock that boings down."""
    out = silence(0.45)
    base = (620.0, 540.0)[variant - 1]
    knock = decay(tone(0.35, glide(base, base * 0.55, 0.25), "triangle"), 14.0)
    mix_into(out, knock, 0.0, 0.9)
    mix_into(out, decay(tone(0.35, glide(base * 2.4, base * 1.2, 0.2)), 22.0), 0.0, 0.35)
    rng = random.Random(40 + variant)
    mix_into(out, decay(highpass(noise(rng, 0.05), 2500.0), 60.0), 0.0, 0.4)
    return out


def thud() -> list[float]:
    """Something heavy lands on someone: a big low pomf, a wobble, and a rattle."""
    out = silence(0.9)
    mix_into(out, blip(0.6, 160.0, 55.0, 6.0), 0.0, 1.0)
    wobble = decay(tone(0.6, 90.0, "sine", (11.0, 0.25)), 5.0)
    mix_into(out, wobble, 0.05, 0.5)
    rng = random.Random(9)
    mix_into(out, decay(bandpass(noise(rng, 0.3), 900.0, 2.0), 12.0), 0.02, 0.3)
    return out


def whoosh() -> list[float]:
    """A throw: a quick airy swoosh that rises and falls."""
    rng = random.Random(77)
    swoosh = bandpass(noise(rng, 0.32), lambda t: 500.0 + 2600.0 * math.sin(math.pi * min(1.0, t / 0.3)), 2.0)
    return envelope(swoosh, 0.05, 0.2)


def dizzy() -> list[float]:
    """Seeing stars: three little birdie tweets circling."""
    out = silence(1.3)
    for index in range(3):
        chirp = decay(tone(0.18, glide(2200.0 + index * 150.0, 3200.0 + index * 150.0, 0.12)), 18.0)
        mix_into(out, chirp, 0.1 + index * 0.35, 0.7)
        mix_into(out, decay(tone(0.12, glide(3000.0, 2400.0, 0.1)), 25.0), 0.22 + index * 0.35, 0.5)
    return out


def pullcord() -> list[float]:
    """A mower's pull cord: a quick rising zip and a rattle."""
    rng = random.Random(21)
    zip_ = bandpass(noise(rng, 0.28), lambda t: 600.0 + 3000.0 * min(1.0, t / 0.25), 3.0)
    out = envelope(zip_, 0.01, 0.06)
    mix_into(out, decay(bandpass(noise(rng, 0.15), 300.0, 2.0), 20.0), 0.2, 0.6)
    return out


def mower_start() -> list[float]:
    """The mower catches: a few sputtering pops, then a buzzy little engine."""
    rng = random.Random(22)
    out = putt_putt(rng, 1.1, 5.0, 22.0, 70.0)
    hum = decay(tone(1.1, 95.0, "square", (17.0, 0.04)), 0.6)
    mix_into(out, lowpass(hum, 900.0), 0.35, 0.35)
    return out


def chop() -> list[float]:
    """The mower blade hits something: a sharp whack and a rattling skitter."""
    rng = random.Random(31)
    out = silence(0.5)
    mix_into(out, decay(highpass(noise(rng, 0.08), 1500.0), 45.0), 0.0, 1.0)
    mix_into(out, blip(0.2, 420.0, 180.0, 18.0), 0.0, 0.7)
    for hit in range(4):
        mix_into(out, decay(bandpass(noise(rng, 0.05), 2400.0 - hit * 300.0, 4.0), 50.0), 0.08 + hit * 0.07, 0.5 - hit * 0.08)
    return out


def grind() -> list[float]:
    """Something hard in the mower: a horrible scraping grind that chokes to a stop."""
    rng = random.Random(32)
    rasp = bandpass(noise(rng, 0.9), lambda t: 900.0 - 500.0 * min(1.0, t / 0.8), 6.0)
    buzz = tone(0.9, lambda t: 130.0 - 90.0 * min(1.0, t / 0.8), "square")
    out = [a * 0.8 + b * 0.35 for a, b in zip(rasp, buzz)]
    return envelope(out, 0.01, 0.25)


def sputter() -> list[float]:
    """Out of gas: the engine's putt-putt slows, coughs, and dies with a sad little 'ptoo'."""
    rng = random.Random(71)
    out = silence(1.5)
    t = 0.0
    seconds = 1.05
    while t < seconds:
        progress = t / seconds
        pitch = 88.0 - 30.0 * progress
        level = 1.0 - 0.45 * progress
        mix_into(out, blip(0.08, pitch * 1.6, pitch, 40.0), t, 0.8 * level)
        mix_into(out, decay(lowpass(noise(rng, 0.06), 800.0), 55.0), t, 1.1 * level)
        # Each pop comes later than the last: 13 a second down to 3.
        t += 1.0 / (13.0 - 10.0 * progress)
    # 'Ptoo': a puff of air and a tiny drooping toot.
    mix_into(out, envelope(bandpass(noise(rng, 0.09), 1800.0, 1.2), 0.004, 0.06), seconds + 0.12, 0.7)
    toot = envelope(tone(0.22, glide(330.0, 190.0, 0.2), "triangle"), 0.01, 0.12)
    mix_into(out, toot, seconds + 0.16, 0.45)
    return out


def glug() -> list[float]:
    """Gas going in: a few hollow glugs, each bubble rising, over a slosh."""
    rng = random.Random(72)
    out = silence(0.75)
    for index in range(4):
        bubble = decay(tone(0.09, glide(170.0 + index * 25.0, 430.0 + index * 30.0, 0.07)), 30.0)
        mix_into(out, bubble, 0.04 + index * 0.14 + rng.uniform(-0.015, 0.015), 0.9)
    mix_into(out, envelope(lowpass(noise(rng, 0.65), 500.0), 0.05, 0.25), 0.02, 0.5)
    return out


def register() -> list[float]:
    """The register on a confirmed buy: a mechanical 'ka' clack of keys, then a bright bell 'ching' ringing out."""
    rng = random.Random(81)
    out = silence(0.95)
    mix_into(out, decay(bandpass(noise(rng, 0.05), 2200.0, 2.0), 90.0), 0.0, 0.9)
    mix_into(out, decay(tone(0.06, 180.0, "square"), 60.0), 0.0, 0.35)
    mix_into(out, decay(bandpass(noise(rng, 0.04), 3200.0, 2.5), 110.0), 0.045, 0.5)
    # Two slightly sour bell partials and a shimmer, so it reads 'cash', not 'doorbell'.
    for freq, gain in ((2093.0, 0.6), (2650.0, 0.42), (4186.0, 0.18)):
        mix_into(out, decay(tone(0.8, freq), 6.0), 0.08, gain)
    return out


def cash_drawer() -> list[float]:
    """The cash drawer slammed shut: a rattling slide, a wooden thunk, and coins jumping in their trays."""
    rng = random.Random(82)
    out = silence(0.6)
    mix_into(out, envelope(bandpass(noise(rng, 0.16), 1500.0, 1.5), 0.02, 0.05), 0.0, 0.5)
    slam = lowpass(decay(tone(0.25, glide(140.0, 70.0, 0.2), "triangle"), 18.0), 700.0)
    mix_into(out, slam, 0.16, 1.0)
    mix_into(out, decay(lowpass(noise(rng, 0.05), 1200.0), 80.0), 0.16, 0.7)
    for index in range(5):
        coin = decay(tone(0.08, rng.uniform(3200.0, 5200.0)), 45.0)
        mix_into(out, coin, 0.19 + index * 0.035 + rng.uniform(0.0, 0.015), 0.25)
    return out


def ui_tick() -> list[float]:
    """The Settings window's slider step: a tiny wooden pip."""
    out = blip(0.04, 1800.0, 1400.0, 90.0)
    return [value + 0.3 * other for value, other in zip(out, decay(tone(0.04, 3600.0, "triangle"), 140.0))]


def ui_pop() -> list[float]:
    """A tab or button press: a soft cartoon pop with a little puff of air."""
    out = silence(0.12)
    mix_into(out, blip(0.08, 500.0, 900.0, 40.0), 0.0, 0.9)
    rng = random.Random(61)
    mix_into(out, decay(bandpass(noise(rng, 0.05), 1400.0, 1.5), 70.0), 0.0, 0.35)
    return out


def ui_stamp() -> list[float]:
    """A key binding accepted: a rubber stamp's thunk on a desk, and the paper rustling."""
    out = silence(0.32)
    rng = random.Random(62)
    thud_ = lowpass(decay(tone(0.22, glide(120.0, 85.0, 0.15), "triangle"), 22.0), 600.0)
    mix_into(out, thud_, 0.0, 1.0)
    mix_into(out, decay(lowpass(noise(rng, 0.03), 900.0), 120.0), 0.0, 0.6)
    mix_into(out, envelope(highpass(noise(rng, 0.06), 3000.0), 0.01, 0.04), 0.07, 0.3)
    return out


# ---------------------------------------------------------------- the hotbar (ui/hotbar_hud.gd, player/pockets.gd)

def slot_tick() -> list[float]:
    """Picking a pocket: a soft plastic tick, like a cheap toolbox latch."""
    out = decay(tone(0.08, 1400.0, "triangle"), 60.0)
    tick_ = decay(tone(0.08, 2800.0), 160.0)
    return [a + 0.35 * b for a, b in zip(out, tick_)]


def pocket() -> list[float]:
    """Something going into a pocket: a cloth 'fwump' and a tiny zip as it settles."""
    rng = random.Random(81)
    out = silence(0.2)
    mix_into(out, envelope(lowpass(noise(rng, 0.14), 520.0), 0.012, 0.09), 0.0, 1.6)
    mix_into(out, blip(0.1, 210.0, 120.0, 30.0), 0.0, 0.35)
    zip_ = bandpass(noise(rng, 0.05), lambda t: 2200.0 + 2400.0 * min(1.0, t / 0.05), 4.0)
    mix_into(out, envelope(zip_, 0.004, 0.02), 0.11, 0.22)
    return out


def draw() -> list[float]:
    """Drawing a tool from a pocket: a rising 'shwip' of fabric and a little metal 'tink'."""
    rng = random.Random(82)
    out = silence(0.32)
    shwip = bandpass(noise(rng, 0.15), lambda t: 700.0 + 3800.0 * (t / 0.15) ** 1.3, 2.4)
    mix_into(out, envelope(shwip, 0.03, 0.06), 0.0, 1.0)
    tink = decay(tone(0.18, 2200.0), 28.0)
    ring = decay(tone(0.18, 2200.0 * 2.76), 45.0)
    mix_into(out, [a + 0.3 * b for a, b in zip(tink, ring)], 0.13, 0.45)
    return out


def jangle() -> list[float]:
    """Full pockets on the move: three loose metallic tinks, never quite in time."""
    rng = random.Random(83)
    out = silence(0.32)
    for index in range(3):
        freq = rng.uniform(2600.0, 4200.0)
        hit = decay(tone(0.1, freq), rng.uniform(35.0, 55.0))
        ring = decay(tone(0.1, freq * 1.51), 70.0)
        at = index * 0.065 + rng.uniform(0.0, 0.02)
        mix_into(out, [a + 0.4 * b for a, b in zip(hit, ring)], at, 0.8 - index * 0.15)
    return out


# Name -> (builder, number of variants or 0 for one file, peak level 0..1).
SOUNDS = {
    "step": (step, 4, 0.3),
    "rake": (rake, 3, 0.5),
    "bag": (bag, 2, 0.7),
    "truck": (truck, 0, 0.75),
    "van": (van, 0, 0.8),
    "van_honk": (van_honk, 0, 0.7),
    "warning": (warning, 0, 0.75),
    "radio": (radio, 0, 0.65),
    "arrive": (arrive, 0, 0.85),
    "tick": (tick, 0, 0.45),
    "clear": (clear, 0, 0.6),
    "vo_ah": (vo_ah, 0, 0.7),
    "vo_eh": (vo_eh, 0, 0.7),
    "vo_huh": (vo_huh, 0, 0.7),
    "vo_oof": (vo_oof, 0, 0.75),
    "vo_hup": (vo_hup, 0, 0.55),
    "vo_yelp": (vo_yelp, 0, 0.8),
    "babble": (babble, 5, 0.6),
    "bonk": (bonk, 2, 0.75),
    "thud": (thud, 0, 0.85),
    "whoosh": (whoosh, 0, 0.5),
    "dizzy": (dizzy, 0, 0.5),
    "vo_strain": (vo_strain, 0, 0.65),
    "vo_heave": (vo_heave, 0, 0.75),
    "pullcord": (pullcord, 0, 0.6),
    "mower_start": (mower_start, 0, 0.6),
    "chop": (chop, 0, 0.75),
    "grind": (grind, 0, 0.7),
    "sputter": (sputter, 0, 0.65),
    "glug": (glug, 0, 0.55),
    # ---- shops (chunk 4): the register on a confirmed buy, the keeper's cash drawer.
    "register": (register, 0, 0.6),
    "cash_drawer": (cash_drawer, 0, 0.6),
    "ui_tick": (ui_tick, 0, 0.35),
    "ui_pop": (ui_pop, 0, 0.45),
    "ui_stamp": (ui_stamp, 0, 0.7),
    # ---- driving (Chefty, net/components/chefty_drive.gd)
    "truck_horn": (truck_horn, 0, 0.75),
    "door_slam": (door_slam, 0, 0.7),
    "skid": (skid, 0, 0.45),
    # ---- R2c van: the Courtesy Shuttle's own brakes (net/run_events/shuttle.gd)
    "van_brake": (van_brake, 0, 0.8),
    # ---- hotbar (player/pockets.gd)
    "slot_tick": (slot_tick, 0, 0.3),
    "pocket": (pocket, 0, 0.5),
    "draw": (draw, 0, 0.5),
    "jangle": (jangle, 0, 0.3),
}


# ---- bags: throw into Chefty (props/truck_bed_load.gd)
def bed_thump() -> list[float]:
    """A stuffed leaf bag landing in Chefty's bed: a soft heavy pomf, the leaves
    inside crunching down a beat after, and a faint hollow knock from the truck."""
    rng = random.Random(512)
    out = silence(0.55)
    mix_into(out, blip(0.32, 150.0, 58.0, 9.0), 0.0, 1.0)
    mix_into(out, envelope(lowpass(noise(rng, 0.12), 500.0), 0.004, 0.09), 0.0, 1.2)
    for index in range(7):
        grain = envelope(bandpass(noise(rng, 0.03), rng.uniform(2200.0, 4200.0), 2.0), 0.002, 0.02)
        mix_into(out, grain, 0.02 + index * 0.018 + rng.uniform(0.0, 0.01), 0.35 - index * 0.03)
    mix_into(out, decay(tone(0.2, 235.0, "triangle"), 26.0), 0.005, 0.22)
    return out


SOUNDS["bed_thump"] = (bed_thump, 0, 0.8)


# ---- shops: Rusty's (chunk 5)
def haggle_hmm() -> list[float]:
    """Rusty mulls a haggle over: a low closed-mouth hum that sinks, sits, and
    tips up into a question at the end, "hmmmm... hm?", with a breath through
    the nose before it. Low and slow: he's the babble set pitched 0.75."""
    rng = random.Random(530)
    out = silence(1.15)
    mix_into(out, breath(rng, 0.09, 900.0), 0.0, 0.25)

    def pitch(t: float) -> float:
        # Down from 150 Hz into a long 118 Hz hum, then a rise on the last beat.
        if t < 0.55:
            return 150.0 - 32.0 * min(t / 0.25, 1.0)
        if t < 0.75:
            return 118.0
        return 118.0 + 70.0 * ((t - 0.75) / 0.3) ** 1.6

    hum = tone(1.05, pitch, "saw", (5.0, 0.012))
    # A closed mouth: nasal, mostly the low formant, the rest damped.
    nasal = [a + 0.25 * b for a, b in zip(bandpass(hum, 250.0, 3.0), bandpass(hum, 2200.0, 6.0))]
    shaped = envelope(lowpass(nasal, 1400.0), 0.06, 0.12)
    # A small dip in the middle: two thoughts, not one.
    for index in range(len(shaped)):
        t = index / RATE
        if 0.62 < t < 0.72:
            shaped[index] *= 0.45 + 0.55 * abs(t - 0.67) / 0.05
    mix_into(out, shaped, 0.05, 1.0)
    return out


SOUNDS["haggle_hmm"] = (haggle_hmm, 0, 0.7)

# ---- shops chunk 6: snacks (player/snack_eater.gd) and the Snak-o-Matic (props/vending_machine.gd)
def munch(variant: int) -> list[float]:
    """A bite: a crisp crunch of bun or bread, the teeth's little click, and a
    closed-mouth 'mm' under it. Short, so three of them land on three bites."""
    rng = random.Random(1300 + variant)
    out = silence(0.32)
    crunch = bandpass(noise(rng, 0.09), 2600.0 + variant * 300.0, 1.4)
    mix_into(out, decay(crunch, 32.0), 0.0, 1.0)
    for index in range(4):
        grain = envelope(bandpass(noise(rng, 0.025), rng.uniform(1800.0, 3800.0), 3.0), 0.002, 0.015)
        mix_into(out, grain, 0.03 + index * 0.025 + rng.uniform(0.0, 0.012), 0.55 - index * 0.1)
    mix_into(out, decay(tone(0.03, 1900.0, "triangle"), 160.0), 0.0, 0.25)
    nom = lowpass(vowel("u", 0.16, glide(170.0 + variant * 10.0, 150.0, 0.14), (0.0, 0.0)), 700.0)
    mix_into(out, envelope(nom, 0.02, 0.08), 0.05, 0.55)
    return out


def slurp() -> list[float]:
    """A long noisy slurp through the lid, bubbling as it climbs, then a
    satisfied 'ahhh' off the lip."""
    rng = random.Random(1310)
    out = silence(1.5)
    seconds = 0.88
    suck = bandpass(noise(rng, seconds), lambda t: 700.0 + 1900.0 * (t / seconds) ** 0.8, 3.5)
    bubbles = [0.55 + 0.45 * math.sin(TAU * (19.0 + 9.0 * index / RATE) * index / RATE) for index in range(len(suck))]
    mix_into(out, envelope([a * b for a, b in zip(suck, bubbles)], 0.05, 0.08), 0.0, 1.0)
    ahh = vowel("a", 0.42, glide(250.0, 175.0, 0.4, 0.8), (5.0, 0.02))
    mix_into(out, envelope(ahh, 0.03, 0.2), seconds + 0.06, 0.75)
    mix_into(out, breath(rng, 0.3, 1200.0), seconds + 0.06, 0.35)
    return out


def vend_clunk() -> list[float]:
    """A snack hitting the bottom of the machine: a hollow sheet-metal clunk,
    a ring that dies fast, and a rattle in the flap."""
    rng = random.Random(1320)
    out = silence(0.7)
    body = lowpass(decay(tone(0.4, glide(118.0, 72.0, 0.12), "triangle"), 14.0), 900.0)
    mix_into(out, body, 0.0, 1.0)
    for freq, gain in ((387.0, 0.4), (1013.0, 0.22), (1690.0, 0.12)):
        mix_into(out, decay(tone(0.5, freq), 18.0), 0.0, gain)
    mix_into(out, decay(lowpass(noise(rng, 0.06), 1500.0), 70.0), 0.0, 0.8)
    for index in range(3):
        mix_into(out, decay(bandpass(noise(rng, 0.03), 2400.0, 3.0), 90.0), 0.08 + index * 0.05 + rng.uniform(0.0, 0.015), 0.3 - index * 0.07)
    return out


def vend_eat() -> list[float]:
    """The machine keeps your money: the sad trombone, 'wah, wah, wah, waaahhh'."""
    out = silence(2.1)
    notes = ((0.0, 0.3, 233.1), (0.36, 0.3, 220.0), (0.72, 0.3, 207.7))
    for at, length, freq in notes:
        mix_into(out, brass(length, glide(freq * 1.02, freq, 0.06)), at, 0.9)
    mix_into(out, brass(1.15, glide(196.0, 174.6, 1.0), (6.5, 0.045)), 1.08, 1.0)
    return out


def vo_yawn() -> list[float]:
    """The Turbo crash: a huge yawn, 'haaaAAaawmm', rising, then sagging off."""
    rng = random.Random(1330)
    out = silence(1.5)
    mix_into(out, breath(rng, 0.2, 900.0), 0.0, 0.45)
    pitch = lambda t: 190.0 + 120.0 * math.sin(math.pi * min(1.0, t / 0.6)) - 70.0 * max(0.0, t - 0.6)
    mix_into(out, envelope(vowel("a", 1.05, pitch, (4.0, 0.02)), 0.12, 0.35), 0.1, 1.0)
    mix_into(out, envelope(lowpass(vowel("u", 0.25, glide(150.0, 120.0, 0.2), (0.0, 0.0)), 600.0), 0.03, 0.15), 1.1, 0.6)
    return out


def vo_burp() -> list[float]:
    """Queasy: one deep, rippling burp."""
    rng = random.Random(1340)
    seconds = 0.5
    croak = vowel("o", seconds, glide(105.0, 82.0, seconds), (0.0, 0.0))
    ripple = [value * (0.6 + 0.4 * math.sin(TAU * 31.0 * index / RATE)) for index, value in enumerate(croak)]
    out = envelope(lowpass(ripple, 1300.0), 0.02, 0.18)
    mix_into(out, decay(lowpass(noise(rng, 0.06), 600.0), 40.0), 0.0, 0.4)
    return out


# ---------------------------------------------------------------- driving C3: crashes

def _clang(rng: random.Random, seconds: float, base: float) -> list[float]:
    """A sheet of metal hit: a few inharmonic partials ringing out over a crack."""
    out = silence(seconds)
    for ratio, gain, rate in [(1.0, 0.7, 9.0), (2.76, 0.45, 12.0), (5.4, 0.3, 16.0), (8.93, 0.18, 22.0)]:
        mix_into(out, decay(tone(seconds, base * ratio, "sine", (5.0, 0.004)), rate), 0.0, gain)
    mix_into(out, decay(highpass(noise(rng, 0.08), 1800.0), 50.0), 0.0, 0.6)
    return out


def crash() -> list[float]:
    """Chefty hits something: a fender's clang, a rubbery boing as the bumper
    bounces, and a short slide whistle down as everyone's stomach drops."""
    rng = random.Random(3101)
    out = silence(1.3)
    mix_into(out, decay(lowpass(noise(rng, 0.25), 700.0), 18.0), 0.0, 0.8)
    mix_into(out, _clang(rng, 0.9, 210.0), 0.0, 0.85)
    boing = decay(tone(0.6, lambda t: 140.0 + 60.0 * math.sin(TAU * 9.0 * t) * math.exp(-5.0 * t), "triangle"), 4.5)
    mix_into(out, boing, 0.06, 0.55)
    whistle = tone(0.4, glide(1450.0, 700.0, 0.38, 1.4), "sine", (8.0, 0.015))
    mix_into(out, envelope(whistle, 0.02, 0.08), 0.32, 0.35)
    return out


def crash_big() -> list[float]:
    """A big one: a deep crunch with rattling bits, a long slide whistle all the
    way down, and a car alarm's two-tone warble that gives up halfway through."""
    rng = random.Random(3102)
    out = silence(2.5)
    mix_into(out, blip(0.5, 120.0, 38.0, 6.0), 0.0, 1.0)
    mix_into(out, decay(lowpass(noise(rng, 0.5), 500.0), 7.0), 0.0, 0.9)
    mix_into(out, _clang(rng, 1.0, 180.0), 0.02, 0.7)
    for index in range(7):
        rattle = decay(bandpass(noise(rng, 0.06), 2400.0 + rng.uniform(-500.0, 900.0), 3.0), 60.0)
        mix_into(out, rattle, 0.12 + index * 0.07 + rng.uniform(0.0, 0.03), 0.35)
    whistle = tone(0.9, glide(1700.0, 320.0, 0.85, 1.1), "sine", (6.0, 0.02))
    mix_into(out, envelope(whistle, 0.03, 0.12), 0.35, 0.4)
    # The car alarm: whoop-whoop, then it sags and quits.
    alarm_seconds = 1.0
    alarm = tone(alarm_seconds, lambda t: (880.0 if int(t * 7.0) % 2 == 0 else 660.0) * (1.0 - 0.25 * max(0.0, t - 0.6)), "square")
    alarm = bandpass(alarm, 1500.0, 1.2)
    mix_into(out, envelope(alarm, 0.02, 0.3), 1.3, 0.22)
    return out


def bag_spill() -> list[float]:
    """Bags tumbling out of the bed: pomf, pomf-pomf, with a dry leafy rustle."""
    rng = random.Random(3103)
    out = silence(0.9)
    for start, pitch, gain in [(0.0, 150.0, 1.0), (0.17, 125.0, 0.85), (0.27, 165.0, 0.75), (0.48, 110.0, 0.6)]:
        mix_into(out, blip(0.22, pitch, pitch * 0.45, 14.0), start, gain)
        mix_into(out, decay(lowpass(noise(rng, 0.12), 900.0), 25.0), start, 0.5 * gain)
        mix_into(out, decay(bandpass(noise(rng, 0.2), 3200.0, 1.5), 14.0), start + 0.01, 0.18 * gain)
    return out


SOUNDS["crash"] = (crash, 0, 0.85)
SOUNDS["crash_big"] = (crash_big, 0, 0.9)
SOUNDS["bag_spill"] = (bag_spill, 0, 0.75)
SOUNDS["munch"] = (munch, 3, 0.8)
SOUNDS["slurp"] = (slurp, 0, 0.55)
SOUNDS["vend_clunk"] = (vend_clunk, 0, 0.75)
SOUNDS["vend_eat"] = (vend_eat, 0, 0.6)
SOUNDS["vo_yawn"] = (vo_yawn, 0, 0.65)
SOUNDS["vo_burp"] = (vo_burp, 0, 0.7)


# ---- shops chunk 7: cosmetics (player/cartoon_body.gd, net/components/chefty_paint.gd)
def hat_on() -> list[float]:
    """A new hat landing on a head: a soft cloth fwump (felt pushing air), a
    little pop of the crown settling, and a tiny tap of the brim."""
    rng = random.Random(1400)
    out = silence(0.36)
    fwump = lowpass(noise(rng, 0.14), 520.0)
    mix_into(out, envelope(fwump, 0.008, 0.11), 0.0, 1.0)
    mix_into(out, decay(tone(0.12, glide(180.0, 110.0, 0.09), "sine"), 30.0), 0.0, 0.7)
    pop = decay(blip(0.05, 900.0, 520.0, 60.0), 50.0)
    mix_into(out, pop, 0.03, 0.35)
    mix_into(out, decay(bandpass(noise(rng, 0.02), 2600.0, 2.5), 120.0), 0.06, 0.18)
    return out


def spray_can() -> list[float]:
    """Chefty's new paint: a rattle can shaken (the ball clacking three times),
    then a long airy hiss that swells and trails off."""
    rng = random.Random(1410)
    out = silence(1.35)
    for index in range(3):
        clack = decay(bandpass(noise(rng, 0.03), 3200.0 + index * 150.0, 4.0), 110.0)
        mix_into(out, clack, index * 0.085, 0.75)
        mix_into(out, decay(tone(0.04, 2100.0 + index * 90.0, "triangle"), 140.0), index * 0.085, 0.25)
    seconds = 0.95
    hiss = highpass(bandpass(noise(rng, seconds), lambda t: 5200.0 - 900.0 * (t / seconds), 0.9), 2500.0)
    mix_into(out, envelope(hiss, 0.06, 0.4), 0.3, 0.9)
    return out


SOUNDS["hat_on"] = (hat_on, 0, 0.7)
SOUNDS["spray_can"] = (spray_can, 0, 0.6)


# ---- fx-yard: the town's edge gives (net/components/chefty_crash.gd)
def sawhorse_tip(variant: int) -> list[float]:
    """A ROAD CLOSED sawhorse knocked over: the board's hollow wooden whack on
    the bumper, a clatter of legs as it goes over, and two bounces on the road."""
    rng = random.Random(1500 + variant)
    out = silence(0.85)
    base = (310.0, 360.0)[variant - 1]
    # The whack: a hollow plank knock over a short crack.
    mix_into(out, decay(tone(0.3, glide(base, base * 0.8, 0.2), "triangle"), 18.0), 0.0, 0.9)
    mix_into(out, decay(tone(0.3, base * 2.7), 30.0), 0.0, 0.3)
    mix_into(out, decay(highpass(noise(rng, 0.04), 2000.0), 70.0), 0.0, 0.55)
    # Legs clattering, then the board slapping the road twice, smaller each time.
    for index in range(4):
        start = 0.14 + index * 0.06 + rng.uniform(0.0, 0.025)
        knock = decay(tone(0.12, base * rng.uniform(1.3, 1.9), "triangle"), 45.0)
        mix_into(out, knock, start, 0.35)
        mix_into(out, decay(bandpass(noise(rng, 0.05), 1800.0, 2.0), 60.0), start, 0.25)
    for start, gain in [(0.42, 0.7), (0.6, 0.4)]:
        mix_into(out, decay(lowpass(noise(rng, 0.12), 600.0), 30.0), start, gain)
        mix_into(out, decay(tone(0.15, base * 0.6, "triangle"), 30.0), start, gain * 0.6)
    return out


def hedge_plow(variant: int) -> list[float]:
    """Chefty's nose into the hedgerow: a big leafy whoomph, twigs snapping in
    it, and the leaves hissing as they settle."""
    rng = random.Random(1510 + variant)
    seconds = 0.75
    out = silence(seconds)
    body = lowpass(noise(rng, 0.35), 420.0)
    mix_into(out, envelope(body, 0.015, 0.25), 0.0, 1.0)
    rustle = bandpass(noise(rng, seconds), lambda t: 2600.0 + 1200.0 * math.sin(TAU * 3.0 * t), 1.4)
    mix_into(out, decay(envelope(rustle, 0.01, 0.3), 3.5), 0.0, 0.6)
    for index in range(3 + variant):
        snap = decay(highpass(noise(rng, 0.02), 3000.0), 140.0)
        mix_into(out, snap, 0.03 + rng.uniform(0.0, 0.3), 0.5)
        mix_into(out, decay(tone(0.04, rng.uniform(1100.0, 1700.0), "triangle"), 90.0), 0.03 + rng.uniform(0.0, 0.3), 0.2)
    return out


SOUNDS["sawhorse_tip"] = (sawhorse_tip, 2, 0.8)
SOUNDS["hedge_plow"] = (hedge_plow, 3, 0.75)


def write(name: str, samples: list[float], peak_level: float) -> None:
    path = OUT / f"{name}.wav"
    peak = max(1e-6, max(abs(value) for value in samples))
    scale = peak_level / peak
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v * scale)) * 32767)) for v in samples))
    print(f"wrote assets/audio/sfx/{path.name}")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    wanted = sys.argv[1:] or list(SOUNDS) + list(sfx_leaves.SOUNDS_RMS)
    # The rake and leaf ids (and 'rake' itself) are written at an RMS target by sfx_leaves.
    sfx_leaves.write_all([name for name in wanted if name in sfx_leaves.SOUNDS_RMS])
    for sound_name in wanted:
        if sound_name in sfx_leaves.SOUNDS_RMS:
            continue
        build, variants, level = SOUNDS[sound_name]
        if variants:
            for variant in range(1, variants + 1):
                write(f"{sound_name}_{variant}", build(variant), level)
        else:
            write(sound_name, build(), level)
