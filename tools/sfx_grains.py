#!/usr/bin/env python3
"""Physically motivated sound primitives for the rake and the leaves (gap R1,
chunk raking:5; docs/ART.md "Rake and leaf sounds"). Stdlib only, so it runs
anywhere tools/make_sfx.py does. tools/sfx_leaves.py builds the recipes from
these; nothing here knows about game ids.

The models, and why:
  modal_click   A struck object rings at its own modes, each dying at its own
                rate: a sum of exponentially damped sines starting at zero
                displacement (a strike is a velocity impulse). A steel tine, a
                soil knock, a bag membrane.
  poisson_times Independent little events (one leaf cracking, one tine catching)
                arrive as a Poisson process whose rate follows what drives them
                (the rake's speed). Non-homogeneous, by thinning.
  crackle       Dry leaves crumpling: the crumpling-noise literature (Houle and
                Sethna 1996, Kramer and Lobkovsky 1996) finds a stream of short
                clicks whose energies follow a power law. Each event is a cluster
                of 1-6 clicks a few ms apart (one fold snapping in steps), each
                click a damped resonance of the leaf (a thin plate: a second
                partial 1.6-2.3x up), with Pareto amplitudes. 'crumple_share' of
                the events are larger, slower, lower folds (noise grains).
  stick_slip    A tine dragged over soil and grass catches, bends, and lets go:
                quasi-periodic releases per tine, more often the faster it drags,
                each one ringing the tine. The release excites higher modes the
                faster it slips, so the scrape's pitch rides the speed and falls
                as the stroke slows.
  brown         Soil and grass under a dragged tine: leaky-integrated noise (most
                energy low), shaped by speed. It is what puts weight under 300 Hz.
  speed_curve   One stroke's speed over time (plant, push, lift, with a hand's
                unevenness and the odd hitch where the tines snag): every layer
                of a stroke is driven by the same curve so they move together.
  write_rms     Loudness is set by RMS (the ear's sense of level), not by peak,
                and peaks are soft-clipped by tanh under a -1 dBFS ceiling.

There is no rising swept band-pass anywhere: that was the old 'rake' (a synth
swoosh that rose from 500 to 4000 Hz and sounded like nothing in a yard).
"""
import math
import pathlib
import random
import struct
import wave

RATE = 44100
TAU = 2.0 * math.pi
OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "audio" / "sfx"


# ---------------------------------------------------------------- small helpers

def silence(sec: float) -> list[float]:
    return [0.0] * max(1, int(sec * RATE))


def mix(target: list[float], source: list[float], at: float = 0.0, gain: float = 1.0) -> list[float]:
    """Adds source into target starting at 'at' seconds (clipped to target's length)."""
    start = int(at * RATE)
    end = min(len(target), start + len(source))
    for index in range(max(0, start), end):
        target[index] += source[index - start] * gain
    return target


def loguniform(rng: random.Random, low: float, high: float) -> float:
    return math.exp(rng.uniform(math.log(low), math.log(high)))


def onepole_lp(samples: list[float], cutoff) -> list[float]:
    """A one-pole low-pass. cutoff is Hz or a function of time (s) -> Hz."""
    out = []
    state = 0.0
    fixed = not callable(cutoff)
    alpha = 1.0 - math.exp(-TAU * cutoff / RATE) if fixed else 0.0
    for index, value in enumerate(samples):
        if not fixed:
            alpha = 1.0 - math.exp(-TAU * max(20.0, cutoff(index / RATE)) / RATE)
        state += alpha * (value - state)
        out.append(state)
    return out


def onepole_hp(samples: list[float], cutoff: float) -> list[float]:
    low = onepole_lp(samples, cutoff)
    return [a - b for a, b in zip(samples, low)]


def biquad_bp(samples: list[float], center: float, q: float) -> list[float]:
    """RBJ band-pass (constant 0 dB peak) at a fixed centre."""
    w = TAU * min(center, RATE * 0.45) / RATE
    alpha = math.sin(w) / (2.0 * q)
    b0, b2, a0, a1, a2 = alpha, -alpha, 1.0 + alpha, -2.0 * math.cos(w), 1.0 - alpha
    out = []
    x1 = x2 = y1 = y2 = 0.0
    for x in samples:
        y = (b0 * x + b2 * x2 - a1 * y1 - a2 * y2) / a0
        out.append(y)
        x2, x1, y2, y1 = x1, x, y1, y
    return out


def dc_block(samples: list[float], cutoff: float = 20.0) -> list[float]:
    """y[n] = x[n] - x[n-1] + R y[n-1]: removes DC and drift under cutoff Hz."""
    r = math.exp(-TAU * cutoff / RATE)
    out = []
    x1 = y1 = 0.0
    for x in samples:
        y = x - x1 + r * y1
        out.append(y)
        x1, y1 = x, y
    return out


def fade(samples: list[float], attack: float, release: float) -> list[float]:
    """Short raised-cosine edges, so no file starts or ends on a step."""
    n = len(samples)
    a = max(1, int(attack * RATE))
    r = max(1, int(release * RATE))
    out = list(samples)
    for index in range(min(a, n)):
        out[index] *= 0.5 - 0.5 * math.cos(math.pi * index / a)
    for index in range(min(r, n)):
        out[n - 1 - index] *= 0.5 - 0.5 * math.cos(math.pi * index / r)
    return out


def smoothstep(x: float) -> float:
    x = max(0.0, min(1.0, x))
    return x * x * (3.0 - 2.0 * x)


# ---------------------------------------------------------------- the models

def modal_click(freqs, taus, amps, sec: float, phase_jitter: random.Random | None = None) -> list[float]:
    """Exponentially damped sines (one per mode) from zero displacement: a strike.
    freqs Hz, taus seconds (time to 1/e), amps linear."""
    n = max(1, int(sec * RATE))
    out = [0.0] * n
    for f, tau, amp in zip(freqs, taus, amps):
        if f >= RATE * 0.48:
            continue
        w = TAU * f / RATE
        k = math.exp(-1.0 / (tau * RATE))
        # Damped sine by recurrence: y[i] = 2 r cos(w) y[i-1] - r^2 y[i-2].
        c = 2.0 * k * math.cos(w)
        k2 = k * k
        # y[0] = 0, y[1] = amp sin(w) k: amp k^i sin(w i) from there on.
        y2 = 0.0
        y1 = amp * math.sin(w) * k
        last = min(n, int(tau * RATE * 9.0) + 2)
        if n > 1:
            out[1] += y1
        for index in range(2, last):
            y = c * y1 - k2 * y2
            out[index] += y
            y2, y1 = y1, y
    return out


def poisson_times(rng: random.Random, sec: float, rate_fn, jitter: float = 0.0) -> list[float]:
    """Event times of a non-homogeneous Poisson process (thinning). rate_fn(t)
    is events per second; jitter (s) nudges each time by up to +-jitter."""
    peak = max(rate_fn(i * sec / 256.0) for i in range(257))
    if peak <= 0.0:
        return []
    peak *= 1.05
    out = []
    t = 0.0
    while True:
        t += rng.expovariate(peak)
        if t >= sec:
            break
        if rng.random() * peak <= rate_fn(t):
            out.append(min(sec, max(0.0, t + rng.uniform(-jitter, jitter))) if jitter else t)
    return out


def _click_into(out: list[float], at: int, f: float, tau: float, amp: float, partial: float) -> None:
    """One leaf click added at sample 'at': a damped resonance and its partial."""
    n = len(out)
    for freq, t_, a in ((f, tau, amp), (f * partial, tau * 0.55, amp * 0.45)):
        if freq >= RATE * 0.47:
            continue
        w = TAU * freq / RATE
        k = math.exp(-1.0 / (t_ * RATE))
        c = 2.0 * k * math.cos(w)
        k2 = k * k
        y2 = 0.0
        y1 = a * math.sin(w) * k
        last = min(n, at + int(t_ * RATE * 8.0) + 2)
        if at + 1 < n:
            out[at + 1] += y1
        for index in range(at + 2, last):
            y = c * y1 - k2 * y2
            out[index] += y
            y2, y1 = y1, y


def _grain_into(out: list[float], at: int, rng: random.Random, tau: float, amp: float, cutoff: float) -> None:
    """A noise grain (a big fold giving way): low-passed noise dying over tau."""
    n = len(out)
    alpha = 1.0 - math.exp(-TAU * cutoff / RATE)
    state = 0.0
    last = min(n, at + int(tau * RATE * 6.0))
    norm = 1.0 / max(0.05, math.sqrt(alpha))
    for index in range(at, last):
        state += alpha * (rng.uniform(-1.0, 1.0) - state)
        out[index] += amp * norm * 0.6 * state * math.exp(-(index - at) / (tau * RATE))


def crackle(rng: random.Random, sec: float, rate_fn, amp_fn, band=(1500.0, 7500.0),
            tau=(4e-4, 2.5e-3), alpha: float = 1.7, cluster=(1, 6), gap=(1e-3, 7e-3),
            partial=(1.6, 2.3), crumple_share: float = 0.0, amp_cap: float = 25.0) -> list[float]:
    """Dry leaves crumpling: Poisson events of click clusters with Pareto(alpha)
    amplitudes (capped at amp_cap times the median)."""
    out = [0.0] * max(1, int(sec * RATE))
    for t in poisson_times(rng, sec, rate_fn):
        base = amp_fn(t) * min(amp_cap, rng.paretovariate(alpha) - 1.0 + 0.15)
        if base <= 0.0:
            continue
        if crumple_share > 0.0 and rng.random() < crumple_share:
            # A bigger fold: slower, lower, a little noisy.
            _grain_into(out, int(t * RATE), rng, rng.uniform(2.5e-3, 7e-3), base * 0.8,
                        loguniform(rng, band[0] * 0.5, band[0] * 1.6))
            continue
        clicks = rng.randint(cluster[0], cluster[1])
        at = t
        amp = base
        for _ in range(clicks):
            if at >= sec:
                break
            _click_into(out, int(at * RATE), loguniform(rng, band[0], band[1]),
                        rng.uniform(tau[0], tau[1]), amp * rng.choice((1.0, -1.0)),
                        rng.uniform(partial[0], partial[1]))
            at += rng.uniform(gap[0], gap[1])
            amp *= rng.uniform(0.3, 0.95)
    return out


def stick_slip(rng: random.Random, sec: float, speed_fn, tines: int = 10, f=(1700.0, 3400.0),
               tau=(1.5e-3, 4e-3), base: float = 40.0, gain: float = 160.0, fall: float = 0.15,
               regularity: float = 0.4) -> list[float]:
    """Tines dragged over the ground. Each tine has its own ring (spread over f)
    and releases at base + gain * speed per second, quasi-periodically
    (regularity 0 = Poisson, 1 = a clock). Each release's strength follows the
    speed, and its pitch drops by up to 'fall' as the tine slows."""
    out = [0.0] * max(1, int(sec * RATE))
    for tine in range(tines):
        f0 = loguniform(rng, f[0], f[1])
        t = rng.uniform(0.0, 0.01)
        while t < sec:
            s = max(0.0, speed_fn(t))
            rate = base * min(1.0, s * 4.0) + gain * s
            if rate <= 1.0:
                t += 0.004
                continue
            mean = 1.0 / rate
            spread = (1.0 - regularity) * mean
            interval = max(2e-4, mean + rng.uniform(-spread, spread) if regularity > 0 else rng.expovariate(rate))
            amp = s * rng.uniform(0.45, 1.25) * (1.0 / math.sqrt(tines))
            freq = f0 * (1.0 - fall + fall * min(1.0, s)) * rng.uniform(0.97, 1.03)
            _click_into(out, int(t * RATE), freq, rng.uniform(tau[0], tau[1]), amp * rng.choice((1.0, -1.0)),
                        rng.uniform(2.6, 3.2))
            t += interval
    return out


def brown(rng: random.Random, sec: float, leak: float = 0.995) -> list[float]:
    """Leaky-integrated white noise, normalised to unit RMS."""
    out = []
    state = 0.0
    for _ in range(max(1, int(sec * RATE))):
        state = state * leak + rng.uniform(-1.0, 1.0)
        out.append(state)
    mean = sum(out) / len(out)
    out = [v - mean for v in out]
    level = math.sqrt(sum(v * v for v in out) / len(out)) or 1.0
    return [v / level for v in out]


def speed_curve(plant: float = 0.025, pull: float = 0.24, lift: float = 0.05, wobble: float = 0.08,
                rng: random.Random | None = None, end_speed: float = 0.35, hitches: int = 0,
                hitch_depth: float = 0.35, peak_at: float = 0.0):
    """A stroke's speed (0..~1.1) as a function of time: a smoothstep rise over
    'plant', then the push, slowing toward end_speed as the load builds (peak_at
    > 0 moves the fastest point into the push), then 'lift' back to rest. A hand
    is uneven ('wobble', a 5-9 Hz tremor) and tines snag ('hitches': brief dips
    and the jump after). rng makes each variant its own stroke."""
    rng = rng or random.Random(0)
    w_rate = rng.uniform(5.0, 9.0)
    w_phase = rng.uniform(0.0, TAU)
    snags = [(rng.uniform(plant + 0.15 * pull, plant + 0.85 * pull), rng.uniform(0.012, 0.03),
              rng.uniform(0.6, 1.0) * hitch_depth) for _ in range(hitches)]
    total = plant + pull + lift

    def fn(t: float) -> float:
        if t < 0.0 or t > total:
            return 0.0
        if t < plant:
            s = smoothstep(t / plant)
        elif t < plant + pull:
            x = (t - plant) / pull
            if peak_at > 0.0 and x < peak_at:
                # Still accelerating: the push hasn't got the load moving yet.
                s = 0.5 + 0.5 * smoothstep(x / peak_at)
            else:
                y = (x - peak_at) / max(1e-6, 1.0 - peak_at)
                s = 1.0 - (1.0 - end_speed) * (y ** 1.3)
        else:
            s = end_speed * (1.0 - smoothstep((t - plant - pull) / lift))
        s *= 1.0 + wobble * math.sin(TAU * w_rate * t + w_phase)
        for at, width, depth in snags:
            d = (t - at) / width
            # A snag: the tines stall, then spring loose a touch faster.
            s *= 1.0 - depth * math.exp(-d * d) + 0.8 * depth * math.exp(-(d - 1.5) ** 2)
        return max(0.0, s)

    fn.total = total
    return fn


# ---------------------------------------------------------------- writing

def rms_of(samples: list[float]) -> float:
    return math.sqrt(sum(v * v for v in samples) / max(1, len(samples)))


def normalise_rms(samples: list[float], rms_dbfs: float, ceiling: float = 0.89) -> list[float]:
    """DC-blocked, scaled to rms_dbfs RMS, peaks soft-clipped (tanh) under ceiling.
    The clip lowers the RMS a touch, so it is rescaled and clipped again. The DC
    blocker is a 20 Hz high-pass, not a mean subtraction (which would leave the
    silent tail sitting at an offset and the fade-out stepping it to zero: a click)."""
    out = dc_block(samples)
    out = fade(out, 0.0005, 0.004)
    target = 10.0 ** (rms_dbfs / 20.0)
    for _ in range(4):
        level = rms_of(out) or 1e-9
        out = [v * target / level for v in out]
        out = [ceiling * math.tanh(v / ceiling) for v in out]
    return out


def write_rms(name: str, samples: list[float], rms_dbfs: float, ceiling: float = 0.89,
              out_dir: pathlib.Path | None = None) -> pathlib.Path:
    """Writes <name>.wav (mono, 16-bit, 44.1 kHz) at rms_dbfs RMS."""
    directory = out_dir or OUT
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / f"{name}.wav"
    data = normalise_rms(samples, rms_dbfs, ceiling)
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(b"".join(struct.pack("<h", int(round(max(-1.0, min(1.0, v)) * 32767))) for v in data))
    return path
