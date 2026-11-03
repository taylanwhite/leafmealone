#!/usr/bin/env python3
"""The UI, store, phone and day sounds (gap-specs/audio.json chunk 5), made the
same way as everything in tools/make_sfx.py (its building blocks, fixed seeds, the
same writer), into assets/audio/sfx/. A file of its own, like tools/sfx_r2_*.py,
so the other audio chunks' recipes don't collide with these in make_sfx.py.

Buttons and panels (audio/ui_sounds.gd plays them on every button):
  ui_click      a button: a small wooden 'tok'
  ui_hover      the pointer over a button: a tiny dry tick, barely there
  ui_back       a Close or an X: the 'tok' answered by a lower one, 'tok-tuk'
  ui_tab        a tab or a toggle: a paper flick and a light tick
  ui_deny       a greyed-out button clicked anyway: a dull rubbery 'bup-bup'
The store and money:
  store_bell    a shop's window opening: the bells on the shop door
  coin          a '+$' popping up: one small coin's ping, where it happened
  receipt       the payout card: a little printer's 'brrrt', then the tear
  cash_grab     the homeowner's cash taken: a snatch and the bills fluttering
  pin           a job picked on the board: a thumbtack pushed into cork
The phone:
  phone_open    a quick swish up out of the pocket and a two-note chime
  phone_close   a swish down and a padded pocket thump
  phone_buzz    a text: a rattly double vibration on a hard surface
  text_pop      a text while the phone is out: a bubble 'bloop'
  text_bad      TurfMasters poached someone: a two-note droop
  phone_take    a job taken from Texts: a confirming swish and a bright 'bling'
The day:
  quiet_chime   9 PM: two soft, distant bongs
  closing_yawn  2 AM: a sleepy muted horn yawning down the scale
  cot_creak     someone lying down on a cot: canvas and springs creaking
  task_done     a task on the list reaches done: 'ding-ding'
  heat_whoop    the heat crosses a warning mark: a small cartoon siren
  snore_loop    someone asleep on a cot (a loop): a rattly snore in, a whistle out

Usage: python tools/sfx_ui.py            write them all
       python tools/sfx_ui.py coin pin   write only those
"""
import math
import random
import sys

import make_loops
import make_sfx as k

TAU = k.TAU
RATE = k.RATE


# ---------------------------------------------------------------- building blocks

def bell(seconds: float, freq: float, partials, decay_scale: float = 1.0) -> list[float]:
    """A struck bell: (ratio, gain, decay rate) partials over one fundamental."""
    out = k.silence(seconds)
    for ratio, gain, rate in partials:
        k.mix_into(out, k.decay(k.tone(seconds, freq * ratio), rate * decay_scale), 0.0, gain)
    return out


# A small, bright bell (a shop-door bell, a phone chime, a ding).
SMALL_BELL = [(1.0, 1.0, 7.0), (2.76, 0.35, 14.0), (5.4, 0.12, 26.0)]
# A big, soft bell heard from a way off (a clock tower).
SOFT_BELL = [(1.0, 1.0, 2.2), (2.0, 0.28, 3.4), (2.4, 0.16, 4.0), (3.0, 0.08, 6.0)]


def wood(seconds: float, freq: float, rate: float, rng: random.Random, knock: float = 0.35) -> list[float]:
    """A wooden knock: a sine body that dies fast, with a little noise transient."""
    out = k.decay(k.tone(seconds, k.glide(freq * 1.08, freq, 0.012)), rate)
    hit = k.decay(k.bandpass(k.noise(rng, seconds), freq * 2.6, 2.0), rate * 2.5)
    return [a + knock * b for a, b in zip(out, hit)]


def swish(rng: random.Random, seconds: float, low: float, high: float, q: float = 2.2) -> list[float]:
    """Air: band-passed noise sweeping from low to high Hz (high below low sweeps down)."""
    sweep = k.bandpass(k.noise(rng, seconds), lambda t: low + (high - low) * min(1.0, t / seconds), q)
    return k.envelope(sweep, seconds * 0.25, seconds * 0.6)


def buzz(rng: random.Random, seconds: float) -> list[float]:
    """A phone's vibration motor against a table: a low motor hum chopped by its
    off-centre weight, and the case rattling."""
    out = []
    motor = k.tone(seconds, 165.0, "square")
    rattle = k.bandpass(k.noise(rng, seconds), 900.0, 1.2)
    for index in range(len(motor)):
        t = index / RATE
        wobble = 0.55 + 0.45 * math.sin(TAU * 31.0 * t)
        out.append((0.6 * motor[index] + 0.9 * rattle[index]) * wobble)
    return k.envelope(k.lowpass(out, 2400.0), 0.008, 0.03)


# ---------------------------------------------------------------- buttons

def ui_click() -> list[float]:
    """A button: a small wooden 'tok', dry, gone in 60 ms."""
    rng = random.Random(7101)
    out = k.silence(0.07)
    k.mix_into(out, wood(0.07, 980.0, 75.0, rng), 0.0, 1.0)
    return out


def ui_hover() -> list[float]:
    """The pointer over a button: the tiniest dry tick."""
    rng = random.Random(7102)
    out = k.silence(0.03)
    k.mix_into(out, k.decay(k.tone(0.03, 2700.0, "triangle"), 220.0), 0.0, 0.7)
    k.mix_into(out, k.decay(k.highpass(k.noise(rng, 0.01), 4000.0), 400.0), 0.0, 0.3)
    return out


def ui_back() -> list[float]:
    """A Close or an X: 'tok-tuk', the second lower, like putting something down."""
    rng = random.Random(7103)
    out = k.silence(0.15)
    k.mix_into(out, wood(0.07, 900.0, 80.0, rng), 0.0, 0.8)
    k.mix_into(out, wood(0.08, 610.0, 65.0, rng), 0.055, 1.0)
    return out


def ui_tab() -> list[float]:
    """A tab or toggle: a quick paper flick and a light tick on top."""
    rng = random.Random(7104)
    out = k.silence(0.09)
    flick = k.envelope(k.bandpass(k.noise(rng, 0.05), k.glide(1800.0, 3400.0, 0.05), 2.0), 0.004, 0.03)
    k.mix_into(out, flick, 0.0, 0.7)
    k.mix_into(out, wood(0.05, 1500.0, 110.0, rng, 0.2), 0.003, 0.6)
    return out


def ui_deny() -> list[float]:
    """Nope: two dull rubbery 'bup's, low and muted, the second lower."""
    out = k.silence(0.22)
    for at, freq in ((0.0, 210.0), (0.1, 165.0)):
        bup = k.lowpass(k.decay(k.tone(0.1, k.glide(freq * 1.15, freq, 0.03), "square"), 32.0), 700.0)
        k.mix_into(out, k.envelope(bup, 0.004, 0.03), at, 1.0)
    return out


# ---------------------------------------------------------------- the store and money

def store_bell() -> list[float]:
    """The bells on a shop door as it swings: three little bells, one a hair late,
    then a softer second shake as the door settles."""
    rng = random.Random(7201)
    out = k.silence(1.1)
    for index, freq in enumerate((2637.0, 3136.0, 2349.0)):
        k.mix_into(out, bell(0.9, freq * rng.uniform(0.995, 1.005), SMALL_BELL), index * 0.028 + rng.uniform(0.0, 0.008), 0.6)
    for index, freq in enumerate((3136.0, 2637.0)):
        k.mix_into(out, bell(0.7, freq, SMALL_BELL, 1.3), 0.24 + index * 0.035, 0.25)
    # The clapper's tap on the first one.
    k.mix_into(out, k.decay(k.highpass(k.noise(rng, 0.01), 3500.0), 500.0), 0.0, 0.4)
    return out


def coin() -> list[float]:
    """One small coin: a bright ping with a sour overtone, so it reads 'money', not 'bell'."""
    rng = random.Random(7202)
    out = k.silence(0.32)
    k.mix_into(out, bell(0.3, 3520.0, [(1.0, 1.0, 16.0), (1.48, 0.55, 22.0), (2.9, 0.15, 40.0)]), 0.0, 1.0)
    k.mix_into(out, k.decay(k.highpass(k.noise(rng, 0.008), 5000.0), 700.0), 0.0, 0.5)
    return out


def receipt() -> list[float]:
    """The payout card: a little thermal printer's 'brrrt' (the feed's stepper
    chattering), then the paper torn off with a 'shrrk'."""
    rng = random.Random(7203)
    out = k.silence(0.78)
    feed = 0.42
    motor = k.tone(feed, 92.0, "square")
    chatter = k.lowpass(k.bandpass(k.noise(rng, feed), 1900.0, 2.2), 2600.0)
    brrrt = []
    for index in range(len(motor)):
        t = index / RATE
        step = 1.0 if (t * 48.0) % 1.0 < 0.55 else 0.25
        brrrt.append((0.45 * motor[index] + 1.4 * chatter[index]) * step)
    k.mix_into(out, k.envelope(k.lowpass(brrrt, 2800.0), 0.004, 0.03), 0.0, 0.8)
    tear = k.envelope(k.highpass(k.noise(rng, 0.13), 2200.0), 0.004, 0.06)
    crackle = [v * (1.0 if rng.random() < 0.35 else 0.3) for v in tear]
    k.mix_into(out, crackle, feed + 0.07, 0.9)
    return out


def cash_grab() -> list[float]:
    """Cash taken: a quick 'fwip' as it's snatched, then the bills fluttering."""
    rng = random.Random(7204)
    out = k.silence(0.55)
    snatch = k.bandpass(k.noise(rng, 0.09), k.glide(900.0, 3200.0, 0.09), 1.8)
    k.mix_into(out, k.envelope(snatch, 0.004, 0.06), 0.0, 0.9)
    at = 0.07
    for index in range(7):
        flap = k.envelope(k.bandpass(k.noise(rng, 0.03), rng.uniform(1800.0, 3400.0), 1.6), 0.003, 0.02)
        k.mix_into(out, flap, at, 0.75 - index * 0.07)
        at += rng.uniform(0.032, 0.05)
    return out


def pin() -> list[float]:
    """A thumbtack pushed into cork: a tiny metal 'tik' and a soft 'thup' under it."""
    rng = random.Random(7205)
    out = k.silence(0.14)
    k.mix_into(out, k.decay(k.tone(0.05, 4200.0, "triangle"), 160.0), 0.0, 0.5)
    k.mix_into(out, k.decay(k.highpass(k.noise(rng, 0.01), 3000.0), 600.0), 0.0, 0.4)
    k.mix_into(out, k.lowpass(k.decay(k.tone(0.1, k.glide(260.0, 170.0, 0.05)), 45.0), 900.0), 0.012, 1.0)
    k.mix_into(out, k.decay(k.lowpass(k.noise(rng, 0.04), 800.0), 80.0), 0.012, 0.5)
    return out


# ---------------------------------------------------------------- the phone

def phone_open() -> list[float]:
    """Out of the pocket: a quick swish up and a two-note chime, on the first frame."""
    rng = random.Random(7301)
    out = k.silence(0.42)
    k.mix_into(out, swish(rng, 0.08, 700.0, 3600.0), 0.0, 0.55)
    k.mix_into(out, bell(0.25, 1318.5, SMALL_BELL, 1.4), 0.0, 0.5)
    k.mix_into(out, bell(0.34, 1975.5, SMALL_BELL, 1.2), 0.075, 0.6)
    return out


def phone_close() -> list[float]:
    """Back in the pocket: a short swish down and a padded thump."""
    rng = random.Random(7302)
    out = k.silence(0.22)
    down = k.bandpass(k.noise(rng, 0.05), k.glide(3000.0, 900.0, 0.05), 2.2)
    k.mix_into(out, k.envelope(down, 0.003, 0.03), 0.0, 0.45)
    k.mix_into(out, k.envelope(k.lowpass(k.noise(rng, 0.12), 380.0), 0.004, 0.08), 0.02, 1.6)
    k.mix_into(out, k.blip(0.1, 190.0, 110.0, 35.0), 0.02, 0.5)
    return out


def phone_buzz() -> list[float]:
    """A text: bzzt-bzzt, two rattly vibrations on a hard surface."""
    rng = random.Random(7303)
    out = k.silence(0.5)
    k.mix_into(out, buzz(rng, 0.17), 0.0, 1.0)
    k.mix_into(out, buzz(rng, 0.17), 0.26, 1.0)
    return out


def text_pop() -> list[float]:
    """A text while the phone is out: a bubble 'bloop' with a smaller one after it."""
    out = k.silence(0.2)
    k.mix_into(out, k.decay(k.tone(0.12, k.glide(420.0, 1150.0, 0.06)), 28.0), 0.0, 1.0)
    k.mix_into(out, k.decay(k.tone(0.08, k.glide(700.0, 1600.0, 0.04)), 40.0), 0.07, 0.4)
    return out


def text_bad() -> list[float]:
    """Bad news: two soft notes that droop, the second sagging flat."""
    out = k.silence(0.6)
    first = k.envelope(k.lowpass(k.tone(0.18, 784.0, "triangle"), 2200.0), 0.006, 0.06)
    second = k.envelope(k.lowpass(k.tone(0.38, k.glide(587.0, 520.0, 0.36, 1.6), "triangle", (6.0, 0.012)), 2000.0), 0.006, 0.2)
    k.mix_into(out, first, 0.0, 0.8)
    k.mix_into(out, second, 0.17, 0.9)
    return out


def phone_take() -> list[float]:
    """A job taken: a confirming swish and a bright rising 'bling'."""
    rng = random.Random(7304)
    out = k.silence(0.45)
    k.mix_into(out, swish(rng, 0.09, 1200.0, 4200.0), 0.0, 0.5)
    k.mix_into(out, bell(0.2, 1568.0, SMALL_BELL, 1.4), 0.0, 0.5)
    k.mix_into(out, bell(0.38, 2093.0, SMALL_BELL, 1.1), 0.06, 0.7)
    return out


# ---------------------------------------------------------------- the day

def quiet_chime() -> list[float]:
    """9 PM: two soft bongs, as if from a clock tower a few streets away."""
    out = k.silence(2.4)
    for at, freq in ((0.0, 392.0), (0.75, 311.1)):
        strike = bell(1.6, freq, SOFT_BELL)
        k.mix_into(out, k.lowpass(k.envelope(strike, 0.012, 0.4), 1800.0), at, 1.0)
    return out


def closing_yawn() -> list[float]:
    """2 AM: a muted horn yawning, 'waaaa-oohm', climbing a little, then sagging
    down and trailing off with a wobble, like the whole town nodding off."""
    out = k.silence(1.6)
    pitch = lambda t: 233.0 * (1.0 + 0.12 * min(1.0, t / 0.35)) if t < 0.35 else 261.0 * (1.0 - 0.38 * min(1.0, (t - 0.35) / 1.0) ** 1.3)
    horn = k.brass(1.45, pitch, (4.5, 0.02))
    k.mix_into(out, k.lowpass(k.envelope(horn, 0.12, 0.5), 1400.0), 0.0, 1.0)
    return out


def cot_creak() -> list[float]:
    """Someone lying down on a cot: the canvas taking the weight and two springy creaks."""
    rng = random.Random(7401)
    out = k.silence(0.6)
    k.mix_into(out, k.envelope(k.lowpass(k.noise(rng, 0.16), 420.0), 0.01, 0.1), 0.0, 1.2)
    for at, start, end, seconds in ((0.06, 520.0, 690.0, 0.2), (0.3, 640.0, 470.0, 0.22)):
        raw = k.tone(seconds, k.glide(start, end, seconds), "saw", (23.0, 0.06))
        creak = k.envelope(k.bandpass(raw, 1100.0, 3.0), 0.02, 0.06)
        k.mix_into(out, creak, at, 0.7)
    return out


def task_done() -> list[float]:
    """A task on the list done: a bright 'ding-ding', up a third."""
    out = k.silence(0.7)
    k.mix_into(out, bell(0.5, 1046.5, SMALL_BELL, 0.9), 0.0, 0.8)
    k.mix_into(out, bell(0.6, 1318.5, SMALL_BELL, 0.8), 0.11, 1.0)
    return out


def heat_whoop() -> list[float]:
    """The heat crossing a mark: a small cartoon siren, 'whoo-oop', up and back down once."""
    out = k.silence(0.55)
    rise = lambda t: 620.0 + 560.0 * math.sin(math.pi * min(1.0, t / 0.48)) ** 0.8
    siren = k.lowpass(k.tone(0.5, rise, "triangle"), 2600.0)
    k.mix_into(out, k.envelope(siren, 0.015, 0.12), 0.0, 1.0)
    return out


def snore_loop() -> list[float]:
    """Asleep on a cot (a loop): a rattly snore in, a soft whistle out, a pause."""
    rng = random.Random(7402)
    cycle = 3.4
    out = k.silence(cycle + 0.3)
    inhale = 1.25
    snore = []
    raw = k.lowpass(k.noise(rng, inhale), 650.0)
    for index, value in enumerate(raw):
        t = index / RATE
        flutter = 0.45 + 0.55 * abs(math.sin(math.pi * 27.0 * t))
        swell = math.sin(math.pi * t / inhale) ** 0.7
        snore.append(value * flutter * swell)
    k.mix_into(out, snore, 0.1, 1.6)
    k.mix_into(out, k.envelope(k.tone(inhale, 86.0, "saw"), 0.4, 0.4), 0.1, 0.06)
    exhale = k.envelope(k.tone(0.9, k.glide(880.0, 640.0, 0.9), "sine", (5.0, 0.02)), 0.25, 0.4)
    breath = k.envelope(k.bandpass(k.noise(rng, 0.9), 1300.0, 1.2), 0.2, 0.4)
    k.mix_into(out, [a * 0.25 + b * 0.35 for a, b in zip(exhale, breath)], 1.55, 1.0)
    return make_loops.seamless(out, 0.3)


# Name -> (builder, peak level 0..1). Levels are set against the existing UI
# sounds (ui_pop 0.45, register 0.6, tick 0.45) by RMS, so nothing jumps out.
SOUNDS = {
    "ui_click": (ui_click, 0.4),
    "ui_hover": (ui_hover, 0.22),
    "ui_back": (ui_back, 0.4),
    "ui_tab": (ui_tab, 0.35),
    "ui_deny": (ui_deny, 0.24),
    "store_bell": (store_bell, 0.45),
    "coin": (coin, 0.45),
    "receipt": (receipt, 0.4),
    "cash_grab": (cash_grab, 0.5),
    "pin": (pin, 0.45),
    "phone_open": (phone_open, 0.4),
    "phone_close": (phone_close, 0.45),
    "phone_buzz": (phone_buzz, 0.32),
    "text_pop": (text_pop, 0.4),
    "text_bad": (text_bad, 0.24),
    "phone_take": (phone_take, 0.45),
    "quiet_chime": (quiet_chime, 0.3),
    "closing_yawn": (closing_yawn, 0.33),
    "cot_creak": (cot_creak, 0.45),
    "task_done": (task_done, 0.45),
    "heat_whoop": (heat_whoop, 0.22),
    "snore_loop": (snore_loop, 0.4),
}


if __name__ == "__main__":
    k.OUT.mkdir(parents=True, exist_ok=True)
    for sound_name in sys.argv[1:] or list(SOUNDS):
        build, level = SOUNDS[sound_name]
        k.write(sound_name, build(), level)
