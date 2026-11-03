#!/usr/bin/env python3
"""Synthesize the game's music into build/audio/wav/<id>.wav (stereo, 44.1 kHz).

tools/encode_ogg.py turns those into assets/audio/music/<id>.ogg, and
tools/audio_check.py measures them (an agent can't listen; it reads numbers
and a PNG). Like tools/make_sfx.py, everything is made here from oscillators,
noise and a plucked-string model, so every cue is a project original. Seeds are
fixed: re-running writes identical files.

The sound is Schedule I's goofy, laid-back cartoon groove: jazzy 7th and 9th
chords, nylon plucks, marimba, electric piano, brushes, and comic leads (kazoo,
whistling, slide whistle, muted trumpet, tuba). Musical guardrail
(docs/ART.md, "Audio"): no Latin-American or regional genre signifiers anywhere
(no mariachi trumpets, bossa, salsa, cumbia, ranchera, guiro- or maraca-led
grooves). The NICE BOYS cues mock bureaucracy: typewriters, rubber stamps,
keystone-cop tuba, police whistles.

How a song is written (see SONGS at the bottom):
  Song(id, bpm, key, seed, sections={name: Section(...)}, form=[names], loop_from="A")
  Section(bars, chords=[one string per bar, "Cmaj9" or "Dm9 G13" for two halves], parts=[...])
Parts (every pattern is 16 steps a bar, spaces and | ignored; a list cycles over bars):
  drum(inst, "x...o...X..."):   x hit, X accent, o ghost, . rest
  bass(inst, "R---5-.p"):       R root (or the slash bass), 3 5 7 8 chord tones,
                                f the fifth below, p/q a half step under/over the
                                next chord's root, - hold, . rest
  comp(inst, "x-----.x"):       the whole chord voiced near `center`, - hold
  arp(inst, "1.3.5.3."):        chord tones by slot: 1 root 2 third 3 fifth
                                4 seventh (or 6th) 5 ninth 6 octave 7 tenth 8 twelfth
  melody(inst, "E5:2 G5:1 r:1 ~A5:4!"): note:steps, r a rest, ~ glides from the
                                last note, ! accent, , soft
  hits(inst, [("bar:step", "F2", steps, velocity), ...]): one-off notes
  slide([("bar:step", hz or note), ...]): a slide whistle through those points
Every part takes gain, pan (-1..1), verb (reverb send) and only=[bars of the section].

Usage: python tools/make_music.py                     every song
       python tools/make_music.py rake_it_easy        only that one
       python tools/make_music.py rake_it_easy --preview          22.05 kHz mono, build/audio/preview/
       python tools/make_music.py rake_it_easy --section B        just section B (a preview)
       python tools/make_music.py --list
"""
import argparse
import array
import json
import math
import pathlib
import random
import sys
import time
import wave
import zlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import make_sfx as s  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
BUILD = ROOT / "build" / "audio"
WAV_DIR = BUILD / "wav"
PREVIEW_DIR = BUILD / "preview"
TAU = 2.0 * math.pi

RATE = 44100
## Loudness targets (docs/ART.md, "Audio"): loops sit at this RMS, nothing peaks over the ceiling.
TARGET_RMS_DBFS = -19.0
CEILING_DBFS = -1.0
## Stingers sit a little over the music they duck (at most this RMS), and never
## peak over this.
STINGER_RMS_DBFS = -18.0
STINGER_PEAK_DBFS = -1.5
## Seconds rendered past a loop's end; the ring-out is folded back onto the loop start.
TAIL_SECONDS = 3.0
## Loops are a whole number of frames at this rate (Godot Movie Maker's fixed fps
## in tools/encode_ogg.py; 50 divides 44100 and 22050).
FRAME_RATE = 50
## The intro's own ring-out fades over this many seconds into the loop start.
PRE_FADE_SECONDS = 0.04


def set_rate(rate: int) -> None:
    global RATE
    RATE = rate
    s.RATE = rate


# ---------------------------------------------------------------- pitch and chords

NOTE_INDEX = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi_of(name: str) -> int:
    """'C4' is 60, 'Bb3' 58, 'F#5' 78."""
    pc = NOTE_INDEX[name[0].upper()]
    rest = name[1:]
    while rest and rest[0] in "#b":
        pc += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    return 12 * (int(rest) + 1) + pc


def hz(midi: float) -> float:
    return 440.0 * 2.0 ** ((midi - 69.0) / 12.0)


def pitch_class(name: str) -> tuple[int, str]:
    pc = NOTE_INDEX[name[0].upper()]
    rest = name[1:]
    while rest and rest[0] in "#b":
        pc += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    return pc % 12, rest


# quality: (third, fifth, seventh or None, ninth or None, extra tones)
QUALITIES = {
    "": (4, 7, None, None, ()),
    "m": (3, 7, None, None, ()),
    "maj7": (4, 7, 11, None, ()),
    "maj9": (4, 7, 11, 14, ()),
    "7": (4, 7, 10, None, ()),
    "9": (4, 7, 10, 14, ()),
    "13": (4, 7, 10, 14, (21,)),
    "7b9": (4, 7, 10, 13, ()),
    "m7": (3, 7, 10, None, ()),
    "m9": (3, 7, 10, 14, ()),
    "m11": (3, 7, 10, 14, (17,)),
    "6": (4, 7, 9, None, ()),
    "m6": (3, 7, 9, None, ()),
    "69": (4, 7, 9, 14, ()),
    "sus4": (5, 7, None, None, ()),
    "7sus4": (5, 7, 10, None, ()),
    "9sus4": (5, 7, 10, 14, ()),
    "dim": (3, 6, None, None, ()),
    "dim7": (3, 6, 9, None, ()),
    "m7b5": (3, 6, 10, None, ()),
    "aug": (4, 8, None, None, ()),
    "add9": (4, 7, None, 14, ()),
    "5": (7, 7, None, None, ()),
}


class Chord:
    def __init__(self, name: str):
        self.name = name
        head, _, slash = name.partition("/")
        self.root, quality = pitch_class(head)
        if quality not in QUALITIES:
            raise ValueError("unknown chord quality in %r" % name)
        self.third, self.fifth, self.seventh, self.ninth, self.extra = QUALITIES[quality]
        self.bass = pitch_class(slash)[0] if slash else self.root

    def slot(self, digit: str) -> int:
        """A chord tone by arp slot, as semitones over the root."""
        seventh = self.seventh if self.seventh is not None else 12
        ninth = self.ninth if self.ninth is not None else 12 + self.third
        return {"1": 0, "2": self.third, "3": self.fifth, "4": seventh, "5": ninth,
                "6": 12, "7": 12 + self.third, "8": 12 + self.fifth}[digit]

    def voicing(self) -> list[int]:
        """Semitones over the root for a comp hit: a jazzy rootless-ish voicing."""
        if self.seventh is None:
            tones = [0, self.third, self.fifth] + ([self.ninth] if self.ninth else [])
        elif self.extra:
            tones = [self.third, self.seventh, self.ninth or 14] + list(self.extra)
        elif self.ninth is not None:
            tones = [self.third, self.fifth, self.seventh, self.ninth]
        else:
            tones = [0, self.third, self.fifth, self.seventh]
        return sorted(set(tones))


def nearest(pc: int, low: int) -> int:
    """The midi note of pitch class pc in [low, low + 11]."""
    return low + (pc - low) % 12


# ---------------------------------------------------------------- small DSP

def silence(seconds: float) -> list[float]:
    return [0.0] * max(0, int(seconds * RATE))


def one_pole_lp(samples: list[float], cutoff: float) -> list[float]:
    alpha = 1.0 - math.exp(-TAU * min(cutoff, RATE * 0.45) / RATE)
    out, state = [0.0] * len(samples), 0.0
    for i, v in enumerate(samples):
        state += alpha * (v - state)
        out[i] = state
    return out


def one_pole_hp(samples: list[float], cutoff: float) -> list[float]:
    low = one_pole_lp(samples, cutoff)
    return [a - b for a, b in zip(samples, low)]


def biquad_bp(samples: list[float], center: float, q: float) -> list[float]:
    w = TAU * min(center, RATE * 0.45) / RATE
    alpha = math.sin(w) / (2.0 * q)
    a0 = 1.0 + alpha
    b0, b2, a1, a2 = alpha / a0, -alpha / a0, -2.0 * math.cos(w) / a0, (1.0 - alpha) / a0
    out = [0.0] * len(samples)
    x1 = x2 = y1 = y2 = 0.0
    for i, x in enumerate(samples):
        y = b0 * x + b2 * x2 - a1 * y1 - a2 * y2
        out[i] = y
        x2, x1, y2, y1 = x1, x, y1, y
    return out


def adsr(n: int, attack: float, hold_n: int, release: float, decay_rate: float = 0.0, sustain: float = 1.0) -> list[float]:
    """An amplitude envelope n samples long: attack, an exponential settle toward
    sustain at decay_rate, held until hold_n, then a release."""
    a_n = max(1, int(attack * RATE))
    r_n = max(1, int(release * RATE))
    env = [0.0] * n
    level = 0.0
    for i in range(n):
        t = i / RATE
        if i < a_n:
            level = i / a_n
        elif decay_rate > 0.0:
            level = sustain + (1.0 - sustain) * math.exp(-decay_rate * (t - attack))
        else:
            level = 1.0
        if i >= hold_n:
            level *= max(0.0, 1.0 - (i - hold_n) / r_n)
        env[i] = level
    return env


def apply(samples: list[float], env: list[float]) -> list[float]:
    return [a * b for a, b in zip(samples, env)]


def karplus(freq: float, seconds: float, rng: random.Random, loss: float, bright: float, pick: float = 0.5) -> list[float]:
    """A plucked string. loss near 1 rings long; bright 0..1 is the pick's tone."""
    period = max(2, int(round(RATE / freq)))
    noise = [rng.uniform(-1.0, 1.0) for _ in range(period)]
    # Pluck position: a comb on the excitation thins the harmonics like plucking mid-string.
    offset = max(1, int(period * pick))
    buf = [noise[i] - 0.5 * noise[(i - offset) % period] for i in range(period)]
    buf = one_pole_lp(buf + buf, 1500.0 + 9000.0 * bright)[period:]
    n = int(seconds * RATE)
    out = [0.0] * n
    last = 0.0
    for i in range(n):
        j = i % period
        v = buf[j]
        out[i] = v
        buf[j] = loss * (0.5 * (v + last))
        last = v
    return out


def osc(freq_fn, seconds: float, shape: str = "sine", duty: float = 0.5) -> list[float]:
    """An oscillator; freq_fn is Hz or a function of the sample index."""
    n = int(seconds * RATE)
    out = [0.0] * n
    phase = 0.0
    fixed = not callable(freq_fn)
    inc = (freq_fn / RATE) if fixed else 0.0
    for i in range(n):
        if not fixed:
            inc = freq_fn(i) / RATE
        phase += inc
        phase -= int(phase)
        if shape == "sine":
            out[i] = math.sin(TAU * phase)
        elif shape == "saw":
            out[i] = 2.0 * phase - 1.0
        elif shape == "square":
            out[i] = 1.0 if phase < duty else -1.0
        else:  # triangle
            out[i] = 4.0 * abs(phase - 0.5) - 1.0
    return out


def vibrato_fn(freq: float, rate: float, depth: float, delay: float = 0.0, scoop: float = 0.0, scoop_s: float = 0.04,
               glide_from: float | None = None, glide_s: float = 0.08):
    delay_n = delay * RATE

    def fn(i: int) -> float:
        t = i / RATE
        f = freq
        if glide_from is not None and t < glide_s:
            k = t / glide_s
            f = glide_from * (freq / glide_from) ** (k * k * (3.0 - 2.0 * k))
        elif scoop and t < scoop_s:
            f *= 1.0 - scoop * (1.0 - t / scoop_s)
        if i > delay_n:
            ramp = min(1.0, (i - delay_n) / (0.2 * RATE))
            f *= 1.0 + depth * ramp * math.sin(TAU * rate * t)
        return f
    return fn


def partials(freq: float, seconds: float, table: list[tuple[float, float, float]]) -> list[float]:
    """Sum of decaying sines: (ratio, amplitude, decay per second)."""
    n = int(seconds * RATE)
    out = [0.0] * n
    nyquist = RATE * 0.45
    for ratio, amp, rate in table:
        f = freq * ratio
        if f >= nyquist:
            continue
        w = TAU * f / RATE
        k = math.exp(-rate / RATE)
        g = amp
        for i in range(n):
            out[i] += g * math.sin(w * i)
            g *= k
    return out


def noise(rng: random.Random, seconds: float) -> list[float]:
    return [rng.uniform(-1.0, 1.0) for _ in range(int(seconds * RATE))]


def expdecay(samples: list[float], rate: float) -> list[float]:
    k = math.exp(-rate / RATE)
    g = 1.0
    out = [0.0] * len(samples)
    for i, v in enumerate(samples):
        out[i] = v * g
        g *= k
    return out


def mix(target: list[float], source: list[float], at: int, gain: float = 1.0) -> None:
    end = min(len(target), at + len(source))
    if at < 0 or end <= at:
        return
    target[at:end] = [a + b * gain for a, b in zip(target[at:end], source)]


# ---------------------------------------------------------------- the instruments
# Each takes (freq, hold seconds, velocity 0..1, rng, glide_from Hz or None) and
# returns mono samples that may ring past the hold.

def i_nylon(f, hold, vel, rng, glide=None):
    seconds = min(max(hold, 0.2) + 0.9, 3.2)
    out = karplus(f, seconds, rng, 0.9965, 0.25 + 0.35 * vel, 0.3)
    out = one_pole_lp(out, 2200.0 + 2500.0 * vel)
    return apply(out, adsr(len(out), 0.002, int((hold + 0.6) * RATE), 0.25))


def i_banjo(f, hold, vel, rng, glide=None):
    seconds = min(max(hold, 0.15) + 0.5, 1.6)
    out = karplus(f, seconds, rng, 0.985, 0.85, 0.12)
    body = biquad_bp(out, 1100.0, 1.5)
    out = [a + 0.6 * b for a, b in zip(out, body)]
    return apply(out, adsr(len(out), 0.001, int((hold + 0.3) * RATE), 0.15))


def i_marimba(f, hold, vel, rng, glide=None):
    seconds = min(1.6, 0.5 + 300.0 / f)
    rate = 2.5 + f / 350.0
    out = partials(f, seconds, [(1.0, 1.0, rate), (3.93, 0.35 * vel, rate * 3.5), (9.2, 0.08 * vel, rate * 8.0)])
    click = expdecay(one_pole_lp(noise(rng, 0.01), 3000.0), 400.0)
    mix(out, click, 0, 0.25 * vel)
    return apply(out, adsr(len(out), 0.0015, len(out), 0.01))


def i_vibes(f, hold, vel, rng, glide=None):
    seconds = max(hold, 0.3) + 1.2
    out = partials(f, seconds, [(1.0, 1.0, 1.1), (4.0, 0.22 * vel, 6.0), (10.0, 0.05, 14.0)])
    trem = [1.0 - 0.3 * (0.5 + 0.5 * math.sin(TAU * 5.2 * i / RATE)) for i in range(len(out))]
    out = apply(out, trem)
    return apply(out, adsr(len(out), 0.002, int((hold + 0.5) * RATE), 0.4))


def i_glock(f, hold, vel, rng, glide=None):
    out = partials(f, 1.6, [(1.0, 1.0, 2.6), (2.76, 0.35, 7.0), (5.4, 0.12, 16.0)])
    return apply(out, adsr(len(out), 0.001, len(out), 0.01))


def i_music_box(f, hold, vel, rng, glide=None):
    out = partials(f, 1.8, [(1.0, 1.0, 2.2), (2.0, 0.18, 5.0), (5.33, 0.22 * vel, 18.0), (8.9, 0.06, 30.0)])
    tick = expdecay(one_pole_hp(noise(rng, 0.006), 4000.0), 900.0)
    mix(out, tick, 0, 0.12)
    return apply(out, adsr(len(out), 0.0008, len(out), 0.01))


def i_ep(f, hold, vel, rng, glide=None):
    """A Rhodes-ish electric piano: a 1:1 FM body whose brightness decays, and a tine ping."""
    seconds = max(hold, 0.15) + 0.6
    n = int(seconds * RATE)
    out = [0.0] * n
    w = TAU * f / RATE
    w_tine = TAU * f * 14.0 / RATE
    index0 = 0.7 + 1.3 * vel
    tine_on = f * 14.0 < RATE * 0.45
    body_decay = math.exp(-(1.0 + f / 900.0) / RATE)
    index_decay = math.exp(-4.5 / RATE)
    tine_decay = math.exp(-35.0 / RATE)
    g, idx, tg = 1.0, index0, 0.12 * vel
    for i in range(n):
        v = math.sin(w * i + (idx + 0.12) * math.sin(w * i))
        if tine_on:
            v += tg * math.sin(w_tine * i)
            tg *= tine_decay
        out[i] = v * g
        g = g * body_decay if g > 0.35 else g * (1.0 - 0.15 / RATE)
        idx *= index_decay
    return apply(out, adsr(n, 0.002, int(hold * RATE), 0.28))


def i_organ(f, hold, vel, rng, glide=None):
    seconds = max(hold, 0.1) + 0.08
    n = int(seconds * RATE)
    out = [0.0] * n
    bars = [(0.5, 0.45), (1.0, 1.0), (2.0, 0.6), (3.0, 0.4), (4.0, 0.25), (6.0, 0.12)]
    ws = [(TAU * f * r / RATE, a) for r, a in bars if f * r < RATE * 0.45]
    trem_w = TAU * 6.4 / RATE
    for i in range(n):
        v = 0.0
        for w, a in ws:
            v += a * math.sin(w * i)
        out[i] = v * (1.0 - 0.14 * (0.5 + 0.5 * math.sin(trem_w * i)))
    click = expdecay(one_pole_hp(noise(rng, 0.008), 2000.0), 500.0)
    mix(out, click, 0, 0.25)
    return apply(out, adsr(n, 0.006, int(hold * RATE), 0.06))


def i_clav(f, hold, vel, rng, glide=None):
    seconds = max(hold, 0.08) + 0.06
    raw = osc(f, seconds, "square", 0.18)
    n = len(raw)
    out = [0.0] * n
    state = 0.0
    for i, v in enumerate(raw):
        cutoff = 700.0 + 4200.0 * math.exp(-i / (0.05 * RATE)) * (0.5 + 0.5 * vel)
        alpha = 1.0 - math.exp(-TAU * cutoff / RATE)
        state += alpha * (v - state)
        out[i] = state
    out = one_pole_hp(out, 250.0)
    return apply(out, adsr(n, 0.001, int(hold * RATE), 0.03, 5.0, 0.4))


def i_pizz(f, hold, vel, rng, glide=None):
    out = karplus(f, 0.55, rng, 0.975, 0.3, 0.45)
    body = biquad_bp(out, 450.0, 1.2)
    out = one_pole_lp([a + 0.5 * b for a, b in zip(out, body)], 2200.0)
    return apply(out, adsr(len(out), 0.002, len(out) - int(0.05 * RATE), 0.05))


def i_pulse(f, hold, vel, rng, glide=None):
    fn = vibrato_fn(f, 5.5, 0.012, delay=0.18, glide_from=glide, glide_s=0.05)
    out = osc(fn, max(hold, 0.06) + 0.03, "square", 0.25)
    return apply(out, adsr(len(out), 0.001, int(hold * RATE), 0.03, 3.0, 0.7))


def i_triangle(f, hold, vel, rng, glide=None):
    raw = osc(f, max(hold, 0.06) + 0.02, "triangle")
    out = [round(v * 7.5) / 7.5 for v in raw]  # 4-bit steps, like the chip
    return apply(out, adsr(len(out), 0.001, int(hold * RATE), 0.02))


def i_upright(f, hold, vel, rng, glide=None):
    seconds = min(max(hold, 0.15) + 0.35, 2.5)
    out = karplus(f, seconds, rng, 0.997, 0.15, 0.25)
    out = one_pole_lp(out, 700.0 + 500.0 * vel)
    thump = expdecay(osc(f, seconds, "sine"), 3.0)
    out = [a * 1.3 + 0.7 * b for a, b in zip(out, thump)]
    return apply(out, adsr(len(out), 0.004, int((hold + 0.05) * RATE), 0.08, 1.6, 0.45))


def i_synth_bass(f, hold, vel, rng, glide=None):
    seconds = max(hold, 0.08) + 0.05
    saw = osc(f, seconds, "saw")
    sub = osc(f * 0.5, seconds, "square")
    n = len(saw)
    out = [0.0] * n
    state = 0.0
    for i in range(n):
        cutoff = 280.0 + 2000.0 * vel * math.exp(-i / (0.07 * RATE))
        alpha = 1.0 - math.exp(-TAU * cutoff / RATE)
        state += alpha * ((saw[i] + 0.5 * sub[i]) - state)
        out[i] = state
    return apply(out, adsr(n, 0.002, int(hold * RATE), 0.04, 4.0, 0.7))


def _brass(f, hold, vel, rng, glide, bright: float, vib: float):
    seconds = max(hold, 0.1) + 0.1
    fn = vibrato_fn(f, 5.3, vib, delay=0.15, scoop=0.03, glide_from=glide)
    raw = osc(fn, seconds, "saw")
    n = len(raw)
    out = [0.0] * n
    state = 0.0
    attack_n = 0.05 * RATE
    for i, v in enumerate(raw):
        swell = min(1.0, i / attack_n)
        cutoff = f * (1.5 + bright * swell * (0.6 + 0.4 * vel))
        alpha = 1.0 - math.exp(-TAU * min(cutoff, RATE * 0.4) / RATE)
        state += alpha * (v - state)
        out[i] = state
    return apply(out, adsr(n, 0.03, int(hold * RATE), 0.08))


def i_tuba(f, hold, vel, rng, glide=None):
    return _brass(f, hold, vel, rng, glide, 4.0, 0.006)


def i_brass(f, hold, vel, rng, glide=None):
    """A brass section stab (for the NICE BOYS cues)."""
    return _brass(f, hold, vel, rng, glide, 9.0, 0.004)


def i_muted_trumpet(f, hold, vel, rng, glide=None):
    """A harmon-muted trumpet: a nasal, buzzy saw with a 'wah' on each attack."""
    seconds = max(hold, 0.1) + 0.12
    fn = vibrato_fn(f, 5.6, 0.009, delay=0.14, scoop=0.025, glide_from=glide)
    raw = osc(fn, seconds, "saw")
    n = len(raw)
    wah = s.bandpass(raw, lambda t: 800.0 + 900.0 * min(1.0, t / 0.12), 2.5)
    nasal = biquad_bp(raw, 2400.0, 4.0)
    body = one_pole_lp(raw, 1400.0)
    out = [a * 1.4 + b * 0.6 + c * 0.25 for a, b, c in zip(wah, nasal, body)]
    return apply(out, adsr(n, 0.025, int(hold * RATE), 0.09))


def i_kazoo(f, hold, vel, rng, glide=None):
    """A kazoo: a hummed saw buzzing through a membrane, nasal 'u' formants."""
    seconds = max(hold, 0.08) + 0.06
    fn = vibrato_fn(f, 6.0, 0.016, delay=0.1, scoop=0.04, glide_from=glide)
    raw = osc(fn, seconds, "saw")
    buzz = [math.tanh(2.8 * v) for v in raw]
    n = len(buzz)
    rasp = [v * (0.5 + 0.5 * b) for v, b in zip(noise(rng, seconds), buzz)]
    f1 = biquad_bp(buzz, 520.0, 4.0)
    f2 = biquad_bp(buzz, 1350.0, 5.0)
    f3 = biquad_bp(buzz, 2900.0, 6.0)
    hiss = biquad_bp(rasp, 3200.0, 1.2)
    out = [a + 0.8 * b + 0.35 * c + 0.12 * d for a, b, c, d in zip(f1, f2, f3, hiss)]
    return apply(out, adsr(n, 0.02, int(hold * RATE), 0.05))


def i_whistle(f, hold, vel, rng, glide=None):
    """Somebody whistling: a nearly pure tone with a breathy edge and a lazy vibrato."""
    seconds = max(hold, 0.08) + 0.08
    fn = vibrato_fn(f, 5.0, 0.007, delay=0.2, scoop=0.035, scoop_s=0.05, glide_from=glide)
    out = osc(fn, seconds, "sine")
    air = biquad_bp(noise(rng, seconds), f, 6.0)
    out = [a + 0.18 * b for a, b in zip(out, air)]
    return apply(out, adsr(len(out), 0.03, int(hold * RATE), 0.07))


def i_choir(f, hold, vel, rng, glide=None):
    """Choir 'ooh': three slightly detuned voices through an 'oo' vowel."""
    seconds = max(hold, 0.2) + 0.3
    voices = [osc(vibrato_fn(f * d, 4.8 + k * 0.4, 0.008), seconds, "saw") for k, d in enumerate((1.0, 1.004, 0.996))]
    raw = [a + b + c for a, b, c in zip(*voices)]
    out = [a + 0.5 * b + 0.15 * c for a, b, c in zip(biquad_bp(raw, 350.0, 4.0), biquad_bp(raw, 750.0, 5.0), biquad_bp(raw, 2400.0, 6.0))]
    return apply(out, adsr(len(out), 0.14, int(hold * RATE), 0.28))


def i_slide_whistle(f, hold, vel, rng, glide=None):
    """A slide whistle note; with ~ it slides all the way from the last note."""
    seconds = max(hold, 0.08) + 0.05
    fn = vibrato_fn(f, 6.5, 0.01, delay=0.05, glide_from=glide, glide_s=max(0.05, hold * 0.8))
    out = osc(fn, seconds, "sine")
    air = biquad_bp(noise(rng, seconds), f * 1.0, 3.0)
    out = [a + 0.12 * b for a, b in zip(out, air)]
    return apply(out, adsr(len(out), 0.015, int(hold * RATE), 0.04))


def i_gong(f, hold, vel, rng, glide=None):
    seconds = 3.5
    n = int(seconds * RATE)
    out = [0.0] * n
    table = [(1.0, 1.0, 0.7), (1.47, 0.6, 0.9), (2.09, 0.45, 1.3), (2.56, 0.3, 1.6), (3.2, 0.22, 2.2), (4.1, 0.12, 3.0)]
    for ratio, amp, rate in table:
        w = TAU * f * ratio / RATE
        k = math.exp(-rate / RATE)
        g = amp
        phase = 0.0
        for i in range(n):
            # The pitch sags a hair as it rings.
            phase += w * (1.0 - 0.015 * min(1.0, i / RATE))
            out[i] += g * math.sin(phase)
            g *= k
    swell = adsr(n, 0.06, n, 0.01)
    mallet = expdecay(one_pole_lp(noise(rng, 0.03), 600.0), 80.0)
    mix(out, mallet, 0, 0.6)
    return apply(out, swell)


INSTRUMENTS = {
    "nylon": i_nylon, "banjo": i_banjo, "marimba": i_marimba, "vibes": i_vibes, "glock": i_glock,
    "music_box": i_music_box, "ep": i_ep, "organ": i_organ, "clav": i_clav, "pizz": i_pizz,
    "pulse": i_pulse, "triangle": i_triangle, "upright": i_upright, "synth_bass": i_synth_bass,
    "tuba": i_tuba, "brass": i_brass, "muted_trumpet": i_muted_trumpet, "kazoo": i_kazoo,
    "whistle": i_whistle, "choir": i_choir, "slide_whistle": i_slide_whistle, "gong": i_gong,
}


# ---------------------------------------------------------------- the drums
# Each takes (velocity, rng) and returns mono samples.

def d_kick(vel, rng):
    n = int(0.38 * RATE)
    out = [0.0] * n
    phase = 0.0
    for i in range(n):
        t = i / RATE
        phase += TAU * (46.0 + 110.0 * math.exp(-t * 28.0)) / RATE
        out[i] = math.sin(phase) * math.exp(-t * 8.5)
    mix(out, expdecay(one_pole_lp(noise(rng, 0.004), 4000.0), 800.0), 0, 0.3)
    return out


def d_snare(vel, rng):
    body = expdecay(osc(190.0, 0.25, "triangle"), 22.0)
    rattle = expdecay(one_pole_hp(noise(rng, 0.25), 1200.0), 15.0)
    return [0.7 * a + 0.8 * b for a, b in zip(body, rattle)]


def d_brush(vel, rng):
    swish = biquad_bp(noise(rng, 0.24), 3200.0, 0.7)
    return apply(swish, adsr(len(swish), 0.006, len(swish), 0.01, 11.0, 0.0))


def d_sweep(vel, rng):
    swish = s.bandpass(noise(rng, 0.5), lambda t: 2200.0 + 2400.0 * t / 0.5, 0.8)
    return apply(swish, adsr(len(swish), 0.18, int(0.3 * RATE), 0.2))


def d_hat(vel, rng):
    return expdecay(one_pole_hp(one_pole_hp(noise(rng, 0.08), 7000.0), 7000.0), 48.0)


def d_hat_open(vel, rng):
    return expdecay(one_pole_hp(one_pole_hp(noise(rng, 0.45), 6500.0), 6500.0), 7.0)


def d_shaker(vel, rng):
    grains = one_pole_hp(one_pole_hp(noise(rng, 0.12), 5000.0), 5000.0)
    return apply(grains, adsr(len(grains), 0.014, len(grains), 0.01, 32.0, 0.0))


def d_clap(vel, rng):
    out = silence(0.26)
    for k, at in enumerate((0.0, 0.009, 0.019)):
        burst = expdecay(biquad_bp(noise(rng, 0.03 if k < 2 else 0.22), 1300.0, 1.1), 130.0 if k < 2 else 16.0)
        mix(out, burst, int(at * RATE), 1.0)
    return out


def d_rim(vel, rng):
    out = expdecay(osc(1700.0, 0.07, "triangle"), 60.0)
    mix(out, expdecay(biquad_bp(noise(rng, 0.03), 3000.0, 2.0), 90.0), 0, 0.6)
    return out


def d_snap(vel, rng):
    """A finger snap: a tight papery crack."""
    out = expdecay(biquad_bp(noise(rng, 0.09), 2700.0, 1.6), 75.0)
    mix(out, expdecay(one_pole_hp(noise(rng, 0.004), 5000.0), 900.0), 0, 0.7)
    return out


def d_cowbell(vel, rng):
    a = osc(562.0, 0.35, "square")
    b = osc(845.0, 0.35, "square")
    return expdecay(biquad_bp([x + y for x, y in zip(a, b)], 720.0, 1.6), 11.0)


def d_woodblock(vel, rng):
    out = expdecay(osc(1150.0, 0.12, "triangle"), 42.0)
    mix(out, expdecay(osc(2400.0, 0.12), 70.0), 0, 0.35)
    return out


def d_tambourine(vel, rng):
    out = silence(0.28)
    for at in (0.0, 0.012, 0.026):
        mix(out, expdecay(one_pole_hp(noise(rng, 0.2), 6000.0), 30.0), int(at * RATE), 0.6)
    mix(out, partials(5200.0, 0.25, [(1.0, 0.25, 22.0), (1.37, 0.2, 26.0)]), 0, 1.0)
    return out


def _tom(start: float, end: float, rng) -> list[float]:
    n = int(0.42 * RATE)
    out = [0.0] * n
    phase = 0.0
    for i in range(n):
        t = i / RATE
        phase += TAU * (end + (start - end) * math.exp(-t * 18.0)) / RATE
        out[i] = math.sin(phase) * math.exp(-t * 7.0)
    mix(out, expdecay(one_pole_lp(noise(rng, 0.02), 2500.0), 120.0), 0, 0.25)
    return out


def d_tom_hi(vel, rng):
    return _tom(230.0, 160.0, rng)


def d_tom_lo(vel, rng):
    return _tom(150.0, 100.0, rng)


def d_crash(vel, rng):
    out = expdecay(one_pole_hp(noise(rng, 2.0), 4000.0), 2.2)
    mix(out, expdecay(biquad_bp(noise(rng, 2.0), 9000.0, 1.0), 3.0), 0, 0.5)
    return apply(out, adsr(len(out), 0.002, len(out) - int(0.2 * RATE), 0.2))


def d_typewriter(vel, rng):
    """One typewriter key: a sharp click and a mechanical clack."""
    out = expdecay(one_pole_hp(noise(rng, 0.004), 3000.0), 1200.0) + [0.0] * int(0.06 * RATE)
    mix(out, expdecay(biquad_bp(noise(rng, 0.03), 950.0 * rng.uniform(0.9, 1.1), 3.0), 120.0), int(0.004 * RATE), 0.9)
    return out


def d_type_bell(vel, rng):
    """The typewriter's end-of-line ding."""
    return partials(2650.0, 0.9, [(1.0, 1.0, 5.0), (2.4, 0.2, 12.0)])


def d_rubber_stamp(vel, rng):
    """'Ka-CHUNK': a stamp's handle clacks, then the stamp thumps the desk."""
    out = silence(0.36)
    mix(out, expdecay(osc(1800.0, 0.03, "triangle"), 120.0), 0, 0.5)
    thump = [0.0] * int(0.3 * RATE)
    phase = 0.0
    for i in range(len(thump)):
        t = i / RATE
        phase += TAU * (60.0 + 80.0 * math.exp(-t * 30.0)) / RATE
        thump[i] = math.sin(phase) * math.exp(-t * 16.0)
    mix(thump, expdecay(one_pole_lp(noise(rng, 0.08), 900.0), 40.0), 0, 0.7)
    mix(out, thump, int(0.06 * RATE), 1.0)
    return out


def d_police_whistle(vel, rng):
    """A pea whistle: two close tones, trilled by the rattling pea."""
    seconds = 0.38
    a = osc(2150.0, seconds)
    b = osc(2330.0, seconds)
    trill = [0.35 + 0.65 * (0.5 + 0.5 * math.sin(TAU * 27.0 * i / RATE)) for i in range(len(a))]
    out = [(x + 0.7 * y) * t for x, y, t in zip(a, b, trill)]
    air = biquad_bp(noise(rng, seconds), 2300.0, 2.0)
    out = [v + 0.2 * w for v, w in zip(out, air)]
    return apply(out, adsr(len(out), 0.01, int(0.3 * RATE), 0.06))


DRUMS = {
    "kick": d_kick, "snare": d_snare, "brush": d_brush, "sweep": d_sweep, "hat": d_hat,
    "hat_open": d_hat_open, "shaker": d_shaker, "clap": d_clap, "rim": d_rim, "snap": d_snap,
    "cowbell": d_cowbell, "woodblock": d_woodblock, "tambourine": d_tambourine, "tom_hi": d_tom_hi,
    "tom_lo": d_tom_lo, "crash": d_crash, "typewriter": d_typewriter, "type_bell": d_type_bell,
    "rubber_stamp": d_rubber_stamp, "police_whistle": d_police_whistle,
}

# Where each instrument sits by default: (pan, reverb send).
PLACEMENT = {
    "kick": (0.0, 0.02), "snare": (0.05, 0.12), "brush": (0.1, 0.15), "sweep": (0.1, 0.15),
    "hat": (0.3, 0.05), "hat_open": (0.3, 0.08), "shaker": (0.4, 0.08), "snap": (-0.2, 0.2),
    "upright": (0.0, 0.04), "synth_bass": (0.0, 0.02), "tuba": (-0.1, 0.08),
}


# ---------------------------------------------------------------- the note cache

class NoteCache:
    """Renders each distinct (instrument, pitch, length, velocity) once."""

    def __init__(self, seed: int):
        self.seed = seed
        self.store: dict = {}
        self.hits = 0

    def get(self, inst: str, midi: float | None, hold: float, vel: float, glide_midi: float | None = None, variant: int = 0) -> list[float]:
        vel_bucket = round(max(0.05, min(1.25, vel)) * 8.0) / 8.0
        hold_key = round(hold, 3)
        key = (inst, midi, hold_key, vel_bucket, glide_midi, variant)
        found = self.store.get(key)
        if found is not None:
            self.hits += 1
            return found
        rng = random.Random(zlib.crc32(repr((self.seed, key)).encode()))
        if inst in DRUMS:
            samples = DRUMS[inst](vel_bucket, rng)
        else:
            samples = INSTRUMENTS[inst](hz(midi), hold_key, vel_bucket, rng, hz(glide_midi) if glide_midi is not None else None)
        peak = max(1e-9, max(abs(v) for v in samples))
        samples = [v / peak * vel_bucket for v in samples]
        self.store[key] = samples
        return samples


# ---------------------------------------------------------------- the song DSL

def _steps(pattern) -> list[str]:
    """A pattern (string or list) as a list of 16-step bars."""
    items = pattern if isinstance(pattern, (list, tuple)) else [pattern]
    bars = []
    for item in items:
        clean = "".join(c for c in item if c not in " |")
        if len(clean) % 16:
            raise ValueError("pattern %r is %d steps, not a multiple of 16" % (item, len(clean)))
        bars.extend(clean[i:i + 16] for i in range(0, len(clean), 16))
    return bars


def _pos(text: str) -> tuple[int, float]:
    bar, _, step = text.partition(":")
    return int(bar), float(step or 0)


class Part:
    kind = "part"

    def __init__(self, inst: str, gain: float = 1.0, pan: float | None = None, verb: float | None = None, only=None):
        if inst not in INSTRUMENTS and inst not in DRUMS:
            raise ValueError("unknown instrument %r" % inst)
        default_pan, default_verb = PLACEMENT.get(inst, (0.0, 0.18))
        self.inst = inst
        self.gain = gain
        self.pan = default_pan if pan is None else pan
        self.verb = default_verb if verb is None else verb
        self.only = set(only) if only is not None else None

    def plays(self, bar: int) -> bool:
        return self.only is None or bar in self.only

    def events(self, section: "Section") -> list[tuple]:
        """(bar, step, midi or None, hold steps, velocity, glide_midi) for each note."""
        raise NotImplementedError


class drum(Part):
    def __init__(self, inst, pattern, **kw):
        super().__init__(inst, **kw)
        self.bars = _steps(pattern)

    def events(self, section):
        out = []
        for bar in range(section.bars):
            if not self.plays(bar):
                continue
            for step, c in enumerate(self.bars[bar % len(self.bars)]):
                vel = {"x": 0.85, "X": 1.0, "o": 0.45}.get(c)
                if vel:
                    out.append((bar, step, None, 1, vel, None))
        return out


def _holds(bar_steps: str, step: int) -> int:
    hold = 1
    while step + hold < len(bar_steps) and bar_steps[step + hold] == "-":
        hold += 1
    return hold


class bass(Part):
    def __init__(self, inst, pattern, low: int = 33, **kw):
        super().__init__(inst, **kw)
        self.bars = _steps(pattern)
        self.low = low

    def events(self, section):
        out = []
        for bar in range(section.bars):
            if not self.plays(bar):
                continue
            steps = self.bars[bar % len(self.bars)]
            for step, c in enumerate(steps):
                if c in ".-":
                    continue
                chord = section.chord_at(bar, step)
                root = nearest(chord.bass if c == "R" else chord.root, self.low)
                if c == "R":
                    midi = root
                elif c in "3578":
                    midi = root + {"3": chord.third, "5": chord.fifth, "7": chord.seventh or 10, "8": 12}[c]
                elif c == "f":
                    midi = root - 5
                elif c in "pq":
                    nxt = nearest(section.next_chord(bar, step).bass, self.low)
                    midi = nxt - 1 if c == "p" else nxt + 1
                else:
                    raise ValueError("bass token %r" % c)
                vel = 0.95 if step % 4 == 0 else 0.8
                out.append((bar, step, midi, _holds(steps, step), vel, None))
        return out


class comp(Part):
    def __init__(self, inst, pattern, center: int = 62, **kw):
        super().__init__(inst, **kw)
        self.bars = _steps(pattern)
        self.center = center

    def events(self, section):
        out = []
        last_mean = float(self.center)
        for bar in range(section.bars):
            if not self.plays(bar):
                continue
            steps = self.bars[bar % len(self.bars)]
            for step, c in enumerate(steps):
                if c not in "xX":
                    continue
                chord = section.chord_at(bar, step)
                notes = self._voice(chord, 0.5 * last_mean + 0.5 * self.center)
                last_mean = sum(notes) / len(notes)
                hold = _holds(steps, step)
                for k, midi in enumerate(notes):
                    out.append((bar, step + 0.06 * k, midi, hold, 0.75 if c == "x" else 0.95, None))
        return out

    @staticmethod
    def _voice(chord: Chord, center: float) -> list[int]:
        tones = chord.voicing()
        best, best_score = None, 1e9
        for inversion in range(len(tones)):
            shape = sorted(t + (12 if k < inversion else 0) for k, t in enumerate(tones))
            for octave in range(2, 7):
                notes = [12 * octave + chord.root + t for t in shape]
                mean = sum(notes) / len(notes)
                score = abs(mean - center) + 0.3 * (notes[-1] - notes[0])
                if score < best_score:
                    best, best_score = notes, score
        return best


class arp(Part):
    def __init__(self, inst, pattern, low: int = 47, **kw):
        super().__init__(inst, **kw)
        self.bars = _steps(pattern)
        self.low = low

    def events(self, section):
        out = []
        for bar in range(section.bars):
            if not self.plays(bar):
                continue
            steps = self.bars[bar % len(self.bars)]
            for step, c in enumerate(steps):
                if not c.isdigit():
                    continue
                chord = section.chord_at(bar, step)
                midi = nearest(chord.root, self.low) + chord.slot(c)
                vel = 0.85 if step % 4 == 0 else (0.7 if step % 2 == 0 else 0.6)
                out.append((bar, step, midi, _holds(steps, step), vel, None))
        return out


class melody(Part):
    def __init__(self, inst, notes: str, shift: int = 0, **kw):
        super().__init__(inst, **kw)
        self.tokens = notes.replace("|", " ").split()
        self.shift = shift

    def events(self, section):
        out = []
        at = 0
        last = None
        for token in self.tokens:
            name, _, length = token.partition(":")
            vel = 0.8
            while length and length[-1] in "!,":
                vel = 1.0 if length[-1] == "!" else 0.55
                length = length[:-1]
            steps = int(length or 1)
            glide = name.startswith("~")
            name = name.lstrip("~")
            if name != "r":
                midi = midi_of(name) + self.shift
                bar, step = divmod(at, 16)
                if self.plays(bar):
                    out.append((bar, step, midi, steps, vel, last if glide else None))
                last = midi
            at += steps
        if at != section.bars * 16:
            print("  note: a %s melody is %d steps in a %d-step section" % (self.inst, at, section.bars * 16))
        return out


class hits(Part):
    def __init__(self, inst, notes: list, **kw):
        super().__init__(inst, **kw)
        self.notes = notes

    def events(self, section):
        out = []
        for where, name, steps, vel in self.notes:
            bar, step = _pos(where)
            midi = None if name is None else (midi_of(name) if isinstance(name, str) else name)
            out.append((bar, step, midi, steps, vel, None))
        return out


class slide(Part):
    """A slide whistle through a list of ("bar:step", Hz or note) points, as one breath."""

    def __init__(self, points: list, **kw):
        super().__init__("slide_whistle", **kw)
        self.points = points

    def render(self, song: "Song", start_seconds: float) -> tuple[float, list[float]]:
        times = []
        for where, pitch in self.points:
            bar, step = _pos(where)
            freq = hz(midi_of(pitch)) if isinstance(pitch, str) else float(pitch)
            times.append((song.step_seconds * (bar * 16 + step), freq))
        t0, t1 = times[0][0], times[-1][0]
        seconds = t1 - t0 + 0.06
        rng = random.Random(song.seed + 77)

        def fn(i: int) -> float:
            t = t0 + i / RATE
            for (ta, fa), (tb, fb) in zip(times, times[1:]):
                if t <= tb:
                    k = 0.0 if tb == ta else (t - ta) / (tb - ta)
                    k = k * k * (3.0 - 2.0 * k)
                    return fa * (fb / fa) ** k * (1.0 + 0.008 * math.sin(TAU * 6.5 * t))
            return times[-1][1]
        tone_ = osc(fn, seconds, "sine")
        air = biquad_bp(noise(rng, seconds), 1200.0, 0.8)
        out = apply([a + 0.06 * b for a, b in zip(tone_, air)], adsr(len(tone_), 0.02, len(tone_) - int(0.05 * RATE), 0.05))
        return start_seconds + t0, out


class Section:
    def __init__(self, bars: int, chords: list[str], parts: list[Part]):
        self.bars = bars
        self.chord_bars = [[Chord(name) for name in entry.split()] for entry in chords]
        if len(self.chord_bars) != bars:
            raise ValueError("a %d-bar section with %d bars of chords" % (bars, len(self.chord_bars)))
        self.parts = parts
        # The chord the form plays right after this section (render() sets it
        # before each pass); None means the section wraps onto its own start.
        self.following: Chord | None = None

    def chord_at(self, bar: int, step: float) -> Chord:
        names = self.chord_bars[bar % self.bars]
        return names[min(len(names) - 1, int(step * len(names) / 16))]

    def next_chord(self, bar: int, step: float) -> Chord:
        names = self.chord_bars[bar % self.bars]
        index = int(step * len(names) / 16)
        if index + 1 < len(names):
            return names[index + 1]
        if bar % self.bars == self.bars - 1 and self.following is not None:
            return self.following
        return self.chord_bars[(bar + 1) % self.bars][0]


class Song:
    def __init__(self, song_id: str, title: str, bpm: float, key: str, seed: int, sections: dict, form: list,
                 loop_from: str | None = "A", swing: float = 0.0, swing_unit: int = 16, stinger: bool = False,
                 stinger_tail: float = 0.6, humanize: float = 0.004):
        self.id = song_id
        self.title = title
        self.bpm = bpm
        self.key = key
        self.seed = seed
        self.sections = sections
        self.form = form
        self.loop_from = loop_from
        self.swing = swing
        self.swing_unit = swing_unit
        self.stinger = stinger
        self.stinger_tail = stinger_tail
        self.humanize = humanize
        self.step_seconds = 60.0 / bpm / 4.0
        if not stinger:
            # A loop is a whole number of 20 ms frames long (tools/encode_ogg.py
            # explains why): the tempo moves by a few thousandths of a bpm at most.
            steps = self.bars * 16
            self.step_seconds = round(steps * self.step_seconds * FRAME_RATE) / FRAME_RATE / steps

    @property
    def bpm_exact(self) -> float:
        return 60.0 / (self.step_seconds * 4.0)

    @property
    def bars(self) -> int:
        return sum(self.sections[name].bars for name in self.form)

    def intro_bars(self) -> int:
        if self.stinger or self.loop_from is None:
            return 0
        bars = 0
        for name in self.form:
            if name == self.loop_from:
                return bars
            bars += self.sections[name].bars
        raise ValueError("%s: loop_from %r is not in the form" % (self.id, self.loop_from))

    def swing_offset(self, step: float) -> float:
        if not self.swing:
            return 0.0
        whole = int(step)
        if self.swing_unit == 8:
            within = whole % 4
            return self.swing * self.step_seconds * {0: 0.0, 1: 0.5, 2: 1.0, 3: 0.5}[within] * 2.0
        return self.swing * self.step_seconds if whole % 2 == 1 else 0.0


# ---------------------------------------------------------------- mixing

class Bus:
    def __init__(self, n: int, pan: float, verb: float):
        self.samples = [0.0] * n
        self.pan = pan
        self.verb = verb
        self.first = n
        self.last = 0

    def add(self, source: list[float], at: int, gain: float) -> None:
        if at >= len(self.samples):
            return
        at = max(0, at)
        mix(self.samples, source, at, gain)
        self.first = min(self.first, at)
        self.last = max(self.last, min(len(self.samples), at + len(source)))


def comb(x: list[float], delay: int, feedback: float) -> list[float]:
    """y[n] = x[n] + g y[n-D], a block of D samples at a time."""
    y = list(x)
    n = len(y)
    for start in range(delay, n, delay):
        end = min(start + delay, n)
        y[start:end] = [a + feedback * b for a, b in zip(y[start:end], y[start - delay:end - delay])]
    return y


def allpass(x: list[float], delay: int, g: float) -> list[float]:
    """y[n] = -g x[n] + x[n-D] + g y[n-D]."""
    y = [-g * v for v in x]
    n = len(y)
    for start in range(delay, n, delay):
        end = min(start + delay, n)
        y[start:end] = [a + xd + g * yd for a, xd, yd in zip(y[start:end], x[start - delay:end - delay], y[start - delay:end - delay])]
    return y


def reverb(send: list[float]) -> tuple[list[float], list[float]]:
    """A Schroeder reverb: four combs and two allpasses a side, a small warm room."""
    scale = RATE / 44100.0
    wet = one_pole_lp(one_pole_hp(send, 180.0), 5000.0)
    sides = []
    for spread in (0, 23):
        total = [0.0] * len(wet)
        for delay in (1116, 1188, 1277, 1356):
            d = int((delay + spread) * scale)
            total = [a + b for a, b in zip(total, comb(wet, d, 0.82))]
        for delay in (556, 341):
            total = allpass(total, int((delay + spread) * scale), 0.5)
        sides.append(one_pole_lp(total, 4200.0))
    return sides[0], sides[1]


def db(value: float) -> float:
    return 20.0 * math.log10(max(1e-9, value))


def rms(samples: list[float]) -> float:
    return math.sqrt(sum(v * v for v in samples) / max(1, len(samples)))


def limit(left: list[float], right: list[float], ceiling: float) -> int:
    """A block peak limiter: the gain dips one block ahead of each peak and recovers
    over about 80 ms. Returns how many blocks it touched."""
    block = 64
    n = len(left)
    count = (n + block - 1) // block
    need = []
    for b in range(count):
        lo, hi = b * block, min(n, (b + 1) * block)
        peak = max(max(map(abs, left[lo:hi])), max(map(abs, right[lo:hi])))
        need.append(min(1.0, ceiling / peak) if peak > 0 else 1.0)
    gains = [min(need[max(0, b - 1):b + 2]) for b in range(count)]
    release = 1.0 - math.exp(-block / (RATE * 0.08))
    touched = 0
    for b in range(1, count):
        recovered = gains[b - 1] + (1.0 - gains[b - 1]) * release
        gains[b] = min(gains[b], recovered)
    for b in range(count):
        g0 = gains[b]
        g1 = gains[b + 1] if b + 1 < count else g0
        if g0 >= 1.0 and g1 >= 1.0:
            continue
        touched += 1
        lo, hi = b * block, min(n, (b + 1) * block)
        span = hi - lo
        ramp = [g0 + (g1 - g0) * k / span for k in range(span)]
        left[lo:hi] = [v * g for v, g in zip(left[lo:hi], ramp)]
        right[lo:hi] = [v * g for v, g in zip(right[lo:hi], ramp)]
    for side in (left, right):
        side[:] = [max(-ceiling, min(ceiling, v)) for v in side]
    return touched


# ---------------------------------------------------------------- rendering

def mixdown(buses: dict, n: int) -> tuple[list[float], list[float]]:
    """Pan every bus into stereo and add the reverb."""
    left = [0.0] * n
    right = [0.0] * n
    send = [0.0] * n
    for bus in buses.values():
        if bus.last <= bus.first:
            continue
        lo, hi = bus.first, bus.last
        angle = (max(-1.0, min(1.0, bus.pan)) + 1.0) * math.pi / 4.0
        gl, gr = math.cos(angle), math.sin(angle)
        src = bus.samples[lo:hi]
        left[lo:hi] = [a + b * gl for a, b in zip(left[lo:hi], src)]
        right[lo:hi] = [a + b * gr for a, b in zip(right[lo:hi], src)]
        if bus.verb > 0.0:
            send[lo:hi] = [a + b * bus.verb for a, b in zip(send[lo:hi], src)]
    wet_l, wet_r = reverb(send)
    left = [a + b * 0.55 for a, b in zip(left, wet_l)]
    right = [a + b * 0.55 for a, b in zip(right, wet_r)]
    return left, right


def render(song: Song, only_section: str | None = None, mono: bool = False) -> dict:
    form = [only_section] if only_section else song.form
    started = time.time()
    song_seconds = sum(song.sections[name].bars for name in form) * 16 * song.step_seconds
    tail = song.stinger_tail if song.stinger else TAIL_SECONDS
    n = int(round(song_seconds * RATE)) + int(tail * RATE)
    loop_start = song.intro_bars() * 16 * song.step_seconds if not only_section else 0.0
    ls = int(round(loop_start * RATE))
    # The intro is mixed on its own and faded out just before the loop start, so
    # what follows the loop start is only the loop's own sound (plus the end's
    # ring-out folded onto it): then the jump from the end back to A is seamless.
    loop_index = form.index(song.loop_from) if ls > 0 else 0
    cache = NoteCache(song.seed)
    body: dict = {}
    pre: dict = {}
    human = random.Random(song.seed)
    section_marks = []
    at_bars = 0
    for index, name in enumerate(form):
        section = song.sections[name]
        section_start = at_bars * 16 * song.step_seconds
        section_marks.append({"name": name, "start": round(section_start, 6), "bars": section.bars})
        buses, length = (pre, ls) if index < loop_index else (body, n)
        # Approach notes on a section's last bar aim at what the form plays next:
        # the next section, or for the last one the loop_from section (the seam).
        # A one-section preview and a stinger just wrap onto their own start.
        following = None
        if index + 1 < len(form):
            following = song.sections[form[index + 1]].chord_bars[0][0]
        elif not only_section and not song.stinger and song.loop_from is not None:
            following = song.sections[song.loop_from].chord_bars[0][0]
        section.following = following
        for part in section.parts:
            # Parts that share an instrument and placement share a bus.
            key = (part.inst, part.pan, part.verb)
            bus = buses.get(key)
            if bus is None:
                bus = buses[key] = Bus(length, part.pan, part.verb)
            if isinstance(part, slide):
                at, samples = part.render(song, section_start)
                bus.add(samples, int(at * RATE), part.gain)
                continue
            for bar, step, midi, hold_steps, vel, glide in part.events(section):
                t = section_start + (bar * 16 + step) * song.step_seconds + song.swing_offset(step)
                # Laid back: notes only ever land a hair late, never ahead of the grid
                # (so nothing in the loop starts before the loop start).
                if part.inst not in ("kick",):
                    t += human.uniform(0.0, song.humanize)
                vel *= 1.0 + human.uniform(-0.06, 0.06)
                hold = hold_steps * song.step_seconds
                variant = (bar + int(step)) % 2 if part.inst in DRUMS else 0
                samples = cache.get(part.inst, midi, hold, vel, glide, variant)
                bus.add(samples, int(round(t * RATE)), part.gain)
        at_bars += section.bars
    left, right = mixdown(body, n)
    if pre:
        pre_left, pre_right = mixdown(pre, ls)
        fade = min(ls, int(PRE_FADE_SECONDS * RATE))
        for side, into in ((pre_left, left), (pre_right, right)):
            for k in range(fade):
                side[ls - fade + k] *= 1.0 - (k + 1) / fade
            into[:ls] = [a + b for a, b in zip(into[:ls], side)]
    left = one_pole_hp(left, 25.0)
    right = one_pole_hp(right, 25.0)
    body_n = int(round(song_seconds * RATE))
    if song.stinger:
        fade = int(0.3 * RATE)
        for side in (left, right):
            for k in range(fade):
                side[n - fade + k] *= 1.0 - k / fade
    else:
        # Fold the ring-out past the end back onto the loop start, so the seam is seamless.
        ls = int(round(loop_start * RATE))
        for side in (left, right):
            spill = side[body_n:]
            side[ls:ls + len(spill)] = [a + b for a, b in zip(side[ls:ls + len(spill)], spill)]
            del side[body_n:]
    if mono:
        left = right = [0.5 * (a + b) for a, b in zip(left, right)]
        right = list(left)
    ceiling = 10.0 ** (CEILING_DBFS / 20.0)
    if song.stinger:
        peak = max(max(map(abs, left)), max(map(abs, right)))
        level = math.sqrt(0.5 * (rms(left) ** 2 + rms(right) ** 2))
        gain = min(10.0 ** (STINGER_PEAK_DBFS / 20.0) / max(1e-9, peak), 10.0 ** (STINGER_RMS_DBFS / 20.0) / max(1e-9, level))
        left = [v * gain for v in left]
        right = [v * gain for v in right]
        touched = limit(left, right, ceiling)
    else:
        touched = 0
        for _ in range(3):
            level = math.sqrt(0.5 * (rms(left) ** 2 + rms(right) ** 2))
            gain = 10.0 ** (TARGET_RMS_DBFS / 20.0) / max(1e-9, level)
            if abs(db(gain)) < 0.05:
                break
            left = [v * gain for v in left]
            right = [v * gain for v in right]
            touched = limit(left, right, ceiling)
    level = math.sqrt(0.5 * (rms(left) ** 2 + rms(right) ** 2))
    return {
        "left": left, "right": right, "seconds": song_seconds, "loop_start": loop_start, "sections": section_marks,
        "rms_dbfs": round(db(level), 2), "limited_blocks": touched, "notes_cached": len(cache.store),
        "cache_hits": cache.hits, "render_seconds": round(time.time() - started, 1),
    }


def write_wav(path: pathlib.Path, left: list[float], right: list[float], channels: int, seed: int) -> None:
    rng = random.Random(seed)
    scale = 32767.0

    def to_int(side):
        # TPDF dither of one LSB.
        return array.array("h", [int(max(-32767.0, min(32767.0, round(v * scale + rng.random() - rng.random())))) for v in side])
    path.parent.mkdir(parents=True, exist_ok=True)
    if channels == 1:
        data = to_int(left)
    else:
        lw, rw = to_int(left), to_int(right)
        data = array.array("h", bytes(4 * len(lw)))
        data[0::2] = lw
        data[1::2] = rw
    if sys.byteorder != "little":
        data.byteswap()
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(channels)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(data.tobytes())


def build(song: Song, preview: bool = False, section: str | None = None) -> pathlib.Path:
    set_rate(22050 if preview or section else 44100)
    result = render(song, section, mono=preview or bool(section))
    if preview or section:
        path = PREVIEW_DIR / ("%s%s.wav" % (song.id, "_" + section if section else ""))
        channels = 1
    else:
        path = WAV_DIR / (song.id + ".wav")
        channels = 2
    write_wav(path, result["left"], result["right"], channels, song.seed)
    sidecar = {
        "id": song.id, "title": song.title, "bpm": song.bpm, "bpm_exact": song.bpm_exact, "key": song.key, "bars": song.bars if not section else song.sections[section].bars,
        "intro_bars": song.intro_bars() if not section else 0, "loop": not song.stinger, "stinger": song.stinger,
        "seconds": round(result["seconds"], 6), "loop_start_seconds": round(result["loop_start"], 6),
        "file_seconds": round(len(result["left"]) / RATE, 6), "rate": RATE, "sections": result["sections"],
        "rms_dbfs": result["rms_dbfs"],
    }
    path.with_suffix(".json").write_text(json.dumps(sidecar, indent=1), encoding="utf-8")
    print("wrote %s  %.2f s, %d bars at %g bpm, RMS %.1f dBFS, limiter on %d blocks, %d notes (%d reused), %.0f s to render" % (
        path.relative_to(ROOT).as_posix(), len(result["left"]) / RATE, sidecar["bars"], song.bpm, result["rms_dbfs"],
        result["limited_blocks"], result["notes_cached"], result["cache_hits"], result["render_seconds"]))
    return path


# ---------------------------------------------------------------- the songs

def rake_it_easy() -> Song:
    """Work hours on the yard, 7 AM to 5 PM. Laid back: nylon arpeggios and EP
    chords, a marimba hook in B, a whistled counter-line, a bass-and-fingersnap
    breakdown, a muted-trumpet bridge. 100 bpm, C major, 54 bars (129.6 s)."""
    kick_a = "x.....x...x....."
    brush_a = "....x.......x..."
    ghost = "..o....o..o...o."
    shaker = "o.x.o.x.o.x.o.x."
    arp_a = "1.3.4.3.6.4.3.2."
    arp_b = "1...3.4.6...4.3."
    ep_a = "x-----.x---....."
    bass_a = "R---..5.R-..5-.p"
    bass_b = "R---3---5---p---"
    a_chords = ["Cmaj9", "Am9", "Dm9", "G13", "Em7", "A7", "Dm9", "G13"]
    b_chords = ["Fmaj9", "Em7", "Dm9", "Cmaj9", "Fmaj9", "E7", "Am9", "D9 G13"]
    hook = ("A5:2 C6:2 E6:2 C6:2 A5:2 G5:2 A5:4 | G5:2 B5:2 D6:2 B5:2 G5:2 E5:2 G5:4 | "
            "F5:2 A5:2 C6:2 A5:2 F5:2 E5:2 F5:4 | E5:2 G5:2 B5:2 D6:6 r:4 | "
            "A5:2 C6:2 E6:2 C6:2 A5:2 G5:2 A5:4 | G#5:2 B5:2 D6:2 B5:2 G#5:2 E5:2 G#5:4 | "
            "C6:2 B5:2 A5:2 G5:2 E5:4 r:2 C5:2 | D5:2 F#5:2 A5:2 C6:2 B5:2 A5:2 G5:4")
    counter = ("r:4 E6:6 D6:2 C6:4 | B5:8 A5:4 G5:4 | A5:6 F5:2 A5:4 C6:4 | B5:12 r:4 | "
               "r:4 G6:6 E6:2 D6:4 | C#6:8 E6:4 G6:4 | F6:6 E6:2 D6:4 C6:4 | B5:8 r:8")
    b2_whistle = ("E6:8 C6:8 | D6:8 B5:8 | C6:8 A5:8 | G5:12 r:4 | E6:8 C6:8 | D6:8 B5:8 | "
                  "C6:6 B5:2 A5:8 | F#5:8 ~G5:8")
    trumpet = ("r:2 A4:2 C5:2 E5:6 D5:2 C5:2 | Ab4:8 F4:4 D5:4 | G4:2 B4:2 D5:2 E5:6 r:4 | "
               "C#5:4 E5:4 G5:4 E5:4 | F5:6 E5:2 D5:4 A4:4 | Ab4:6 C5:2 D5:4 C5:4 | "
               "A4:4 C5:4 F5:4 E5:4 | D5:12 r:4")
    sections = {
        "intro": Section(4, ["Fmaj7", "G13", "Em7 A7", "Dm9 G13"], [
            arp("nylon", arp_a, gain=0.55, pan=-0.3, verb=0.22),
            drum("shaker", shaker, gain=0.24, only=[2, 3]),
            bass("upright", ["R-------........", "R-------........", "R---....5-..3-.p", "R---..5.R---5-.p"], gain=0.8, only=[2, 3]),
            comp("ep", "..............x-", gain=0.3, pan=0.3, only=[3]),
            drum("brush", "............x.xx", gain=0.35, only=[3]),
        ]),
        "A": Section(8, a_chords, [
            arp("nylon", arp_a, gain=0.5, pan=-0.3, verb=0.2),
            comp("ep", ep_a, gain=0.36, pan=0.3, verb=0.2),
            bass("upright", bass_a, gain=0.85),
            drum("kick", kick_a, gain=0.8),
            drum("brush", brush_a, gain=0.45),
            drum("brush", ghost, gain=0.18),
            drum("shaker", shaker, gain=0.24),
        ]),
        "B": Section(8, b_chords, [
            melody("marimba", hook, gain=0.62, pan=0.2, verb=0.16),
            arp("nylon", arp_b, gain=0.4, pan=-0.35),
            comp("ep", "x-------x-------", gain=0.3, pan=0.3),
            bass("upright", bass_b, gain=0.85),
            drum("kick", "x.......x.x.....", gain=0.8),
            drum("brush", brush_a, gain=0.45),
            drum("hat", "..x...x...x...x.", gain=0.22),
            drum("shaker", shaker, gain=0.2),
            drum("crash", "x...............", gain=0.18, only=[0]),
        ]),
        "A2": Section(8, a_chords, [
            melody("whistle", counter, gain=0.26, pan=-0.12, verb=0.3),
            arp("nylon", arp_a, gain=0.48, pan=-0.3, verb=0.2),
            comp("ep", ep_a, gain=0.34, pan=0.3, verb=0.2),
            bass("upright", bass_a, gain=0.85),
            drum("kick", kick_a, gain=0.8),
            drum("brush", brush_a, gain=0.45),
            drum("brush", ghost, gain=0.18),
            drum("shaker", shaker, gain=0.24),
        ]),
        "breakdown": Section(8, ["Dm9", "G13", "Dm9", "G13", "Em7", "A7", "Dm9", "G7sus4 G7"], [
            bass("upright", "R-.5R-.3.8-.5-.p", gain=0.95),
            drum("snap", "....x.......x...", gain=0.55),
            drum("kick", "x...............", gain=0.55),
            drum("hat", "..x...x...x...x.", gain=0.1, only=[4, 5, 6, 7]),
            comp("ep", "......x-....x---", gain=0.3, pan=0.3, only=[4, 5, 6, 7]),
            arp("nylon", arp_b, gain=0.36, pan=-0.35, only=[6, 7]),
        ]),
        "bridge": Section(8, ["Fmaj7", "Fm6", "Em7", "A7", "Dm9", "Fm6", "Dm7", "G13"], [
            melody("muted_trumpet", trumpet, gain=0.5, pan=0.12, verb=0.28),
            comp("ep", "x-------.x------", gain=0.34, pan=-0.25),
            bass("upright", "R-----5-R---5-.p", gain=0.85),
            drum("kick", "x.........x.....", gain=0.7),
            drum("rim", "....x.......x...", gain=0.25),
            drum("brush", ghost, gain=0.2),
            drum("crash", "x...............", gain=0.15, only=[0]),
        ]),
        "B2": Section(8, b_chords, [
            melody("marimba", hook, gain=0.6, pan=0.2, verb=0.16),
            melody("whistle", b2_whistle, gain=0.2, pan=-0.15, verb=0.3),
            comp("ep", "x-------x-------", gain=0.3, pan=0.3),
            bass("upright", bass_b, gain=0.85),
            drum("kick", "x.......x.x.....", gain=0.8),
            drum("brush", brush_a, gain=0.45),
            drum("hat", "..x...x...x...x.", gain=0.22),
            drum("shaker", shaker, gain=0.2),
            drum("crash", "x...............", gain=0.18, only=[0]),
        ]),
        "turn": Section(2, ["Dm9", "G13"], [
            arp("nylon", arp_a, gain=0.48, pan=-0.3),
            comp("ep", "x---..x-x---..x-", gain=0.32, pan=0.3),
            bass("upright", bass_b, gain=0.85),
            drum("kick", ["x.....x...x.....", "x.......x......."], gain=0.8),
            drum("brush", ["....x.......x...", "....x...x.o.x.xx"], gain=0.45),
            drum("tom_hi", "................" "........x.x.....", gain=0.3),
            drum("tom_lo", "................" "............x.x.", gain=0.35),
        ]),
    }
    return Song("rake_it_easy", "Rake It Easy", 100.0, "C major", 4101, sections,
                ["intro", "A", "B", "A2", "breakdown", "bridge", "B2", "turn"], loop_from="A", swing=0.12)


def st_day_end() -> Song:
    """'Clock Out': the day summary card. A music-box lullaby, a yawning slide
    whistle and a soft gong. 4 s plus a short ring-out."""
    lullaby = "C6:1 A5:1 F5:1 A5:1 G5:2 E5:2 F5:4 r:4"
    sections = {
        "S": Section(1, ["Fmaj7"], [
            melody("music_box", lullaby, gain=0.6, pan=0.15, verb=0.35),
            comp("ep", "x---------------", center=60, gain=0.22, pan=-0.2, verb=0.3),
            comp("choir", "x---------------", center=57, gain=0.12, verb=0.4),
            slide([("0:7", 520.0), ("0:9", 880.0), ("0:10.5", 930.0), ("0:12.5", 420.0)], gain=0.35, pan=-0.1, verb=0.3),
            hits("gong", [("0:12", "F2", 4, 0.7)], gain=0.9, verb=0.45),
        ]),
    }
    return Song("st_day_end", "Clock Out", 60.0, "F major", 4201, sections, ["S"], loop_from=None, stinger=True,
                stinger_tail=0.6)


SONGS = {song.id: song for song in (rake_it_easy(), st_day_end())}


## Song books in their own modules (tools/<name>.py, each with register(module, songs)),
## so chunks composing at the same time never edit the same lines here.
SONG_BOOKS = ("music_tension",)


def load_song_books() -> None:
    for book in SONG_BOOKS:
        __import__(book).register(sys.modules[__name__], SONGS)


def main() -> int:
    load_song_books()
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("ids", nargs="*")
    parser.add_argument("--preview", action="store_true", help="22.05 kHz mono into build/audio/preview/")
    parser.add_argument("--section", help="render one section only (a preview)")
    parser.add_argument("--list", action="store_true")
    options = parser.parse_args()
    if options.list:
        for song in SONGS.values():
            print("%-22s %-22s %5g bpm  %3d bars  %6.1f s  form %s" % (
                song.id, song.title, song.bpm, song.bars, song.bars * 16 * song.step_seconds, " ".join(song.form)))
        return 0
    wanted = options.ids or list(SONGS)
    for song_id in wanted:
        if song_id not in SONGS:
            print("make_music: no song %r (try --list)" % song_id)
            return 1
    WAV_DIR.mkdir(parents=True, exist_ok=True)
    (BUILD / ".gdignore").write_text("", encoding="utf-8")
    for song_id in wanted:
        song = SONGS[song_id]
        if options.section and options.section not in song.sections:
            print("make_music: %s has no section %r (%s)" % (song_id, options.section, ", ".join(song.sections)))
            return 1
        build(song, options.preview, options.section)
    return 0


if __name__ == "__main__":
    sys.exit(main())
