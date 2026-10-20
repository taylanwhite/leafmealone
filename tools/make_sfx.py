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
    """A big swoosh up, with a scritchy leaf shuffle."""
    rng = random.Random(200 + variant)
    length = 0.36 + variant * 0.03
    swoosh = bandpass(noise(rng, length), lambda t: 500.0 + 3500.0 * (t / length) ** 1.4, 2.5)
    out = envelope(swoosh, 0.05, 0.12)
    for burst_at in (0.08, 0.2):
        mix_into(out, envelope(highpass(noise(rng, 0.05), 2500.0), 0.005, 0.03), burst_at + variant * 0.01, 0.25)
    return out


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


# Name -> (builder, number of variants or 0 for one file, peak level 0..1).
SOUNDS = {
    "step": (step, 4, 0.3),
    "rake": (rake, 3, 0.5),
    "bag": (bag, 2, 0.7),
    "truck": (truck, 0, 0.75),
    "van": (van, 0, 0.8),
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
}


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
    wanted = sys.argv[1:] or list(SOUNDS)
    for sound_name in wanted:
        build, variants, level = SOUNDS[sound_name]
        if variants:
            for variant in range(1, variants + 1):
                write(f"{sound_name}_{variant}", build(variant), level)
        else:
            write(sound_name, build(), level)
