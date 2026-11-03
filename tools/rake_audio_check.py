#!/usr/bin/env python3
"""Measure the rake and leaf sounds (gap R1, chunk raking:5), for agents who
can't listen. Stdlib only; reads and FFTs with tools/audio_check.py. Run it
after tools/make_sfx.py writes the files (it reads assets/audio/sfx/).

Every id in tools/sfx_leaves.py's SOUNDS_RMS is checked (exit 1 on a violation):
  all ids       every variant exists, is no longer than its max seconds, sits
                within +-1.5 dB of its RMS target, never clips, and no two
                variants share a loudness envelope (Pearson correlation of the
                10 ms RMS envelopes <= 0.8), so repeats don't sound like one file
  leaf tiers    rake_leaves_*: crackle, not hiss: sample kurtosis >= 10 and at
                least 8 one-millisecond transients (a 1 ms frame 9 dB over the
                median of its +-10 ms neighbourhood)
  rake_plant    an impact: the peak is inside the first 5 ms
  plant, scrape weight: at least 8% of the energy under 300 Hz
  rake_scrape   the scrape falls in pitch: the spectral centroid of its last
                third is below that of its first third
  the bag       (R1b) bag_open, each beat of bag_stuff and bag_tie, at their
                short-term peaks (50 ms RMS) plus the game's trims
                (Constants.LEAF_SFX_MIX_DB), land within BAG_EVEN_DB of each other
--png         a spectrogram per id (every variant stacked, log frequency 40 Hz
              to 18 kHz, 2.5 ms columns) into build/r1/audio/<id>.png, plus the
              previews below, for the Read tool
--preview     composites of how the game layers them (audio/leaf_audio.gd's
              timings and trims), into build/r1/audio/preview_*.wav for Taylan's ears:
              one full swing on a fresh carpet, three swings held, a swing on
              bare grass, a heavy shove into a pile, the bag sequence
These are measurements, not taste: Taylan listening is the acceptance gate.

Usage: python tools/rake_audio_check.py
       python tools/rake_audio_check.py --png --preview
       python tools/rake_audio_check.py rake_scrape --png
"""
import argparse
import math
import pathlib
import struct
import sys
import wave

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import audio_check as ac  # noqa: E402
import sfx_leaves  # noqa: E402

ROOT = ac.ROOT
SFX_DIR = ac.SFX_DIR
OUT_DIR = ROOT / "build" / "r1" / "audio"

RMS_TOLERANCE_DB = 1.5
ENVELOPE_CORRELATION_MAX = 0.8
LEAF_KURTOSIS_MIN = 10.0
LEAF_TRANSIENTS_MIN = 8
TRANSIENT_DB = 9.0
PLANT_PEAK_MS = 5.0
LOW_SHARE_MIN = 0.08
LOW_SHARE_HZ = 300.0
LEAF_TIERS = ("rake_leaves_light", "rake_leaves_med", "rake_leaves_heavy")
BAG_EVEN_DB = 3.0


def load(name: str) -> tuple[list[float], int, int]:
    chans, rate, clipped = ac.read(SFX_DIR / (name + ".wav"))
    return ac.mono_of(chans), rate, clipped


def kurtosis(x: list[float]) -> float:
    n = len(x)
    mean = sum(x) / n
    m2 = sum((v - mean) ** 2 for v in x) / n
    m4 = sum((v - mean) ** 4 for v in x) / n
    return m4 / (m2 * m2) if m2 > 0 else 0.0


def frames_rms(x: list[float], size: int) -> list[float]:
    return [ac.rms(x[i:i + size]) for i in range(0, len(x) - size + 1, size)]


def transients(x: list[float], rate: int) -> int:
    """1 ms frames whose energy is TRANSIENT_DB over the median of their +-10 ms
    neighbourhood, counted once per onset."""
    size = max(1, rate // 1000)
    energy = [v * v for v in frames_rms(x, size)]
    floor = (max(energy) if energy else 0.0) * 1e-6
    count = 0
    above_before = False
    ratio = 10.0 ** (TRANSIENT_DB / 10.0)
    for i, e in enumerate(energy):
        hood = sorted(energy[max(0, i - 10):i + 11])
        median = hood[len(hood) // 2]
        above = e > ratio * max(median, floor)
        if above and not above_before:
            count += 1
        above_before = above
    return count


def loudness_peaks(x: list[float], rate: int) -> list[float]:
    """The short-term level (dB) of each beat of a sound: the RMS of 50 ms windows
    every 10 ms, and the peaks of that curve at least 120 ms apart and within
    12 dB of the loudest, loudest first. What an ear calls 'how loud each hit is',
    near enough to compare sounds that follow each other."""
    size, hop = int(0.05 * rate), int(0.01 * rate)
    curve = [ac.db(ac.rms(x[i:i + size])) for i in range(0, max(1, len(x) - size + 1), hop)]
    if not curve:
        return []
    top = max(curve)
    peaks = []
    for i, v in enumerate(curve):
        if v < top - 12.0:
            continue
        if v >= max(curve[max(0, i - 12):i + 13]):
            if all(abs(i - j) >= 12 for j, _ in peaks):
                peaks.append((i, v))
    return [v for _, v in sorted(peaks, key=lambda p: -p[1])]


def mix_db() -> dict:
    """Constants.LEAF_SFX_MIX_DB from core/constants.gd: each id's trim in the game."""
    text = (ROOT / "core" / "constants.gd").read_text(encoding="utf-8")
    start = text.index("const LEAF_SFX_MIX_DB")
    body = text[text.index("{", start):text.index("}", start)]
    out = {}
    for part in body.replace("\n", " ").split(","):
        if ":" in part:
            key, value = part.split(":", 1)
            out[key.strip().strip('{"\t ')] = float(value.strip())
    return out


def bag_beats() -> list[str]:
    """The bag sequence even (R1b): open, each shove of the stuffing, and the tie,
    at their game trims, within BAG_EVEN_DB of each other (variant averages)."""
    trims = mix_db()
    levels = {}
    for sound_id, beats in (("bag_open", 1), ("bag_stuff", 2), ("bag_tie", 1)):
        _builder, variants, _target, _max = sfx_leaves.SOUNDS_RMS[sound_id]
        per = []
        for variant in range(1, variants + 1):
            x, rate, _clipped = load("%s_%d" % (sound_id, variant))
            per.append(sorted(loudness_peaks(x, rate)[:beats]))
        for beat in range(beats):
            name = sound_id if beats == 1 else "%s beat %d" % (sound_id, beat + 1)
            values = [p[beat] for p in per if len(p) > beat]
            levels[name] = sum(values) / max(1, len(values)) + trims.get(sound_id, 0.0)
    print("bag beats (50 ms peak + trim): " + ", ".join("%s %.1f" % (k, v) for k, v in levels.items()))
    spread = max(levels.values()) - min(levels.values())
    if spread > BAG_EVEN_DB:
        return ["the bag's beats spread %.1f dB (over %.0f): %s" % (spread, BAG_EVEN_DB, levels)]
    return []


def power_spectrum(x: list[float], size: int = 4096) -> list[float]:
    """Summed Hann-windowed power per bin over the file (hop size/2). Half a
    window of zeros goes in front, so the overlapping windows weigh every sample
    the same (an impact at t = 0 isn't lost in the first window's rising edge)."""
    window = [0.5 - 0.5 * math.cos(2.0 * math.pi * k / size) for k in range(size)]
    total = [0.0] * (size // 2)
    padded = [0.0] * (size // 2) + x + [0.0] * size
    for at in range(0, len(x) + size // 2, size // 2):
        chunk = padded[at:at + size]
        spectrum = ac.fft([complex(v * w) for v, w in zip(chunk, window)])
        for k in range(size // 2):
            total[k] += abs(spectrum[k]) ** 2
    return total


def low_share(x: list[float], rate: int) -> float:
    size = 4096
    spectrum = power_spectrum(x, size)
    cut = int(LOW_SHARE_HZ * size / rate)
    # Ignore DC and the sub-20 Hz bins.
    lo = max(1, int(20.0 * size / rate))
    whole = sum(spectrum[lo:]) or 1e-12
    return sum(spectrum[lo:cut]) / whole


def centroid_track(x: list[float], rate: int, size: int = 1024, hop: int = 256) -> list[tuple[float, float]]:
    """(energy, centroid Hz) per frame, each frame centred on its time."""
    window = [0.5 - 0.5 * math.cos(2.0 * math.pi * k / (size - 1)) for k in range(size)]
    out = []
    padded = [0.0] * (size // 2) + x + [0.0] * size
    for at in range(0, len(x), hop):
        spectrum = ac.fft([complex(v * w) for v, w in zip(padded[at:at + size], window)])
        power = [abs(spectrum[k]) ** 2 for k in range(1, size // 2)]
        e = sum(power)
        c = sum((k + 1) * rate / size * p for k, p in enumerate(power)) / e if e > 0 else 0.0
        out.append((e, c))
    return out


def centroid_fall(x: list[float], rate: int) -> tuple[float, float]:
    """Energy-weighted centroid of the first and last thirds of the active part."""
    track = centroid_track(x, rate)
    top = max(e for e, _ in track) if track else 0.0
    active = [(e, c) for e, c in track if e > top * 1e-4]
    if len(active) < 3:
        return 0.0, 0.0
    third = max(1, len(active) // 3)

    def weighted(part):
        total = sum(e for e, _ in part) or 1e-12
        return sum(e * c for e, c in part) / total
    return weighted(active[:third]), weighted(active[-third:])


def correlation(a: list[float], b: list[float]) -> float:
    n = min(len(a), len(b))
    if n < 3:
        return 0.0
    a, b = a[:n], b[:n]
    ma, mb = sum(a) / n, sum(b) / n
    cov = sum((p - ma) * (q - mb) for p, q in zip(a, b))
    va = sum((p - ma) ** 2 for p in a)
    vb = sum((q - mb) ** 2 for q in b)
    return cov / math.sqrt(va * vb) if va > 0 and vb > 0 else 0.0


# ---------------------------------------------------------------- spectrograms

def spectrogram_rows(x: list[float], rate: int, seconds: float, columns: int, rows: int,
                     size: int = 1024) -> list[list[float]]:
    """dB per (column, row): columns over 0..seconds, rows log-spaced 40 Hz..18 kHz."""
    window = [0.5 - 0.5 * math.cos(2.0 * math.pi * k / (size - 1)) for k in range(size)]
    lo, hi = math.log(40.0), math.log(18000.0)
    edges = [math.exp(lo + (hi - lo) * r / rows) for r in range(rows + 1)]
    padded = [0.0] * (size // 2) + x + [0.0] * size
    out = []
    for col in range(columns):
        at = int(col * seconds / columns * rate)
        spectrum = ac.fft([complex(v * w) for v, w in zip(padded[at:at + size], window)])
        power = [abs(spectrum[k]) ** 2 / (size * size / 4.0) for k in range(size // 2)]
        column = []
        for r in range(rows):
            k0 = int(edges[r] * size / rate)
            k1 = max(k0 + 1, int(edges[r + 1] * size / rate))
            e = sum(power[k0:min(k1, len(power))]) / max(1, k1 - k0)
            column.append(10.0 * math.log10(max(1e-14, e)))
        out.append(column)
    return out


def draw_spectrograms(title: str, tracks: list[tuple[str, list[float]]], rate: int, seconds: float,
                      path: pathlib.Path, marks: list[tuple[float, str]] = ()) -> None:
    margin, col_px, columns, rows = 44, 3, int(seconds / 0.0025), 96
    wave_h = 30
    lane = rows + wave_h + 16
    canvas = ac.Canvas(margin + columns * col_px + 10, 26 + lane * len(tracks) + 18)
    canvas.text(4, 4, title, (230, 230, 230), 2)
    for index, (label, x) in enumerate(tracks):
        top = 24 + index * lane
        canvas.text(4, top, label, (200, 200, 200))
        # The waveform envelope over the lane.
        per = max(1, int(seconds * rate / columns))
        mid = top + 8 + wave_h // 2
        for col in range(columns):
            chunk = x[col * per:(col + 1) * per]
            if not chunk:
                continue
            peak = max(abs(v) for v in chunk)
            h = int(min(1.0, peak) * (wave_h // 2))
            for dx in range(col_px):
                canvas.vline(margin + col * col_px + dx, mid - h, mid + h, (110, 150, 200))
        grid = spectrogram_rows(x, rate, seconds, columns, rows)
        spec_top = top + 10 + wave_h
        for col, column in enumerate(grid):
            for r, level in enumerate(column):
                color = ac.heat(level + 10.0)
                y = spec_top + rows - 1 - r
                for dx in range(col_px):
                    canvas.set(margin + col * col_px + dx, y, color)
        for hz, label_hz in ((100.0, "100"), (300.0, "300"), (1000.0, "1K"), (3000.0, "3K"), (10000.0, "10K")):
            r = int(rows * (math.log(hz) - math.log(40.0)) / (math.log(18000.0) - math.log(40.0)))
            canvas.text(margin - 22, spec_top + rows - 1 - r - 2, label_hz, (150, 150, 150))
            canvas.hline(margin - 3, margin - 1, spec_top + rows - 1 - r, (150, 150, 150))
        for at, label_mark in marks:
            xm = margin + int(at / seconds * columns) * col_px
            canvas.vline(xm, top + 8, spec_top + rows, (240, 160, 60))
            if index == 0:
                canvas.text(xm + 2, top + 8, label_mark, (240, 180, 90))
    bottom = 26 + lane * len(tracks)
    canvas.text(margin, bottom, "%.2f S WIDE, 2.5 MS COLUMNS; LOG FREQ 40 HZ TO 18 KHZ" % seconds, (140, 140, 140))
    canvas.save(path)


# ---------------------------------------------------------------- previews

def _place(out: list[float], x: list[float], at: float, db: float, rate: int, pitch: float = 1.0) -> None:
    gain = 10.0 ** (db / 20.0)
    if pitch != 1.0:
        x = [x[min(len(x) - 1, int(i * pitch))] for i in range(int(len(x) / pitch))]
    start = int(at * rate)
    for i, v in enumerate(x):
        if 0 <= start + i < len(out):
            out[start + i] += v * gain


def previews(rate: int) -> dict[str, tuple[list[float], list[tuple[float, str]]]]:
    """How audio/leaf_audio.gd layers one swing (0.6 s: bites at 0.12 and 0.30 s,
    the plant at the first bite, the scrape over the drive from it, the flick at
    the drive's end, 0.42 s) and a bag, at the game's trims (LEAF_SFX_MIX_DB),
    using variant 1, 2, 3 ... as the shuffle bag would."""
    trims = mix_db()

    def clip(name: str) -> list[float]:
        return load(name)[0]

    def put(out: list[float], name: str, at: float, db: float = 0.0) -> None:
        _place(out, clip(name), at, db + trims.get(name.rsplit("_", 1)[0], 0.0), rate)

    out = {}
    tempo = 0.6
    bite_a, bite_b = 0.2 * tempo, 0.5 * tempo
    flick = 0.7 * tempo
    # One swing on a fresh carpet (a medium shove per bite).
    swing = [0.0] * int(1.0 * rate)
    put(swing, "rake_plant_1", bite_a)
    put(swing, "rake_scrape_1", bite_a)
    put(swing, "rake_leaves_med_1", bite_a, -3.0)
    put(swing, "rake_leaves_med_2", bite_b, -3.0)
    put(swing, "leaf_flick_1", flick)
    put(swing, "leaf_settle_1", flick + 0.25, -6.0)
    out["preview_swing"] = (swing, [(bite_a, "A"), (bite_b, "B"), (flick, "FLICK")])
    # Three swings held.
    held = [0.0] * int(2.2 * rate)
    marks = []
    for k in range(3):
        t0 = k * tempo
        put(held, "rake_plant_%d" % (k + 1), t0 + bite_a)
        put(held, "rake_scrape_%d" % (k + 1), t0 + bite_a)
        put(held, "rake_leaves_med_%d" % (2 * k + 1), t0 + bite_a, -2.0)
        put(held, "rake_leaves_med_%d" % (2 * k + 2), t0 + bite_b, -2.0)
        put(held, "leaf_flick_%d" % (k + 1), t0 + flick)
        put(held, "leaf_settle_%d" % (k + 1), t0 + flick + 0.25, -6.0)
        marks.append((t0 + bite_a, "A%d" % (k + 1)))
    out["preview_held"] = (held, marks)
    # Bare grass: plant and the empty swish, nothing flies.
    bare = [0.0] * int(0.8 * rate)
    put(bare, "rake_plant_2", bite_a)
    put(bare, "rake_empty_1", bite_a)
    out["preview_bare"] = (bare, [(bite_a, "A")])
    # A heavy shove into a pile, and the whump of it landing.
    pile = [0.0] * int(1.1 * rate)
    put(pile, "rake_plant_3", bite_a)
    put(pile, "rake_scrape_4", bite_a)
    put(pile, "rake_leaves_heavy_1", bite_a)
    put(pile, "rake_leaves_heavy_2", bite_b)
    put(pile, "leaf_flick_2", flick)
    put(pile, "pile_whump_1", flick + 0.2)
    out["preview_pile"] = (pile, [(bite_a, "A"), (bite_b, "B"), (flick + 0.2, "WHUMP")])
    # The bag: open now, stuff at +0.15, the tie at +0.7 (Constants.BAG_*_DELAY).
    bag = [0.0] * int(1.2 * rate)
    put(bag, "bag_open_1", 0.0)
    put(bag, "bag_stuff_1", 0.15)
    put(bag, "bag_tie_1", 0.7)
    out["preview_bag"] = (bag, [(0.0, "OPEN"), (0.15, "STUFF"), (0.7, "TIE")])
    return out


def write_wav(path: pathlib.Path, x: list[float], rate: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    peak = max(1e-9, max(abs(v) for v in x))
    scale = min(1.0, 0.89 / peak)
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(rate)
        handle.writeframes(b"".join(struct.pack("<h", int(round(v * scale * 32767))) for v in x))


# ---------------------------------------------------------------- the checks

def check_id(sound_id: str, want_png: bool) -> list[str]:
    _builder, variants, target, max_seconds = sfx_leaves.SOUNDS_RMS[sound_id]
    violations = []
    tracks = []
    envelopes = []
    rate = 44100
    for variant in range(1, variants + 1):
        name = "%s_%d" % (sound_id, variant)
        if not (SFX_DIR / (name + ".wav")).exists():
            violations.append("%s is missing (run tools/make_sfx.py %s)" % (name, sound_id))
            continue
        x, rate, clipped = load(name)
        seconds = len(x) / rate
        level = ac.db(ac.rms(x))
        peak = ac.db(max(abs(v) for v in x))
        beats = loudness_peaks(x, rate)
        notes = ["%.3f s" % seconds, "RMS %.1f" % level, "peak %.1f" % peak,
                 "50 ms peak %.1f" % (beats[0] if beats else -99.0)]
        if seconds > max_seconds + 1e-4:
            violations.append("%s is %.3f s, over its %.2f s" % (name, seconds, max_seconds))
        if abs(level - target) > RMS_TOLERANCE_DB:
            violations.append("%s RMS %.1f dBFS, target %.1f +-%.1f" % (name, level, target, RMS_TOLERANCE_DB))
        if clipped:
            violations.append("%s has %d clipped samples" % (name, clipped))
        if sound_id in LEAF_TIERS:
            k = kurtosis(x)
            n = transients(x, rate)
            notes += ["kurtosis %.1f" % k, "transients %d" % n]
            if k < LEAF_KURTOSIS_MIN:
                violations.append("%s kurtosis %.1f < %.0f (hiss, not crackle)" % (name, k, LEAF_KURTOSIS_MIN))
            if n < LEAF_TRANSIENTS_MIN:
                violations.append("%s has %d transients < %d" % (name, n, LEAF_TRANSIENTS_MIN))
        if sound_id == "rake_plant":
            at_ms = max(range(len(x)), key=lambda i: abs(x[i])) / rate * 1000.0
            notes.append("peak at %.1f ms" % at_ms)
            if at_ms > PLANT_PEAK_MS:
                violations.append("%s peaks at %.1f ms (an impact peaks in %g)" % (name, at_ms, PLANT_PEAK_MS))
        if sound_id in ("rake_plant", "rake_scrape"):
            share = low_share(x, rate)
            notes.append("under 300 Hz %.0f%%" % (100.0 * share))
            if share < LOW_SHARE_MIN:
                violations.append("%s has %.1f%% of its energy under 300 Hz (< %.0f%%)" % (name, 100.0 * share, 100.0 * LOW_SHARE_MIN))
        if sound_id == "rake_scrape":
            first, last = centroid_fall(x, rate)
            notes.append("centroid %.0f -> %.0f Hz" % (first, last))
            if not last < first:
                violations.append("%s centroid rises %.0f -> %.0f Hz (the scrape must fall)" % (name, first, last))
        print("%s: %s" % (name, ", ".join(notes)))
        envelopes.append((name, frames_rms(x, rate // 100)))
        tracks.append((name, x))
    worst = 0.0
    for i in range(len(envelopes)):
        for j in range(i + 1, len(envelopes)):
            c = correlation(envelopes[i][1], envelopes[j][1])
            worst = max(worst, c)
            if c > ENVELOPE_CORRELATION_MAX:
                violations.append("%s and %s share an envelope (r = %.2f > %.1f)" % (envelopes[i][0], envelopes[j][0], c, ENVELOPE_CORRELATION_MAX))
    if len(envelopes) > 1:
        print("%s: worst variant envelope correlation %.2f" % (sound_id, worst))
    if want_png and tracks:
        path = OUT_DIR / (sound_id + ".png")
        draw_spectrograms(sound_id.upper(), tracks, rate, max_seconds, path)
        print("  png %s" % path.relative_to(ROOT).as_posix())
    for violation in violations:
        print("  VIOLATION %s" % violation)
    return violations


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("ids", nargs="*")
    parser.add_argument("--png", action="store_true")
    parser.add_argument("--preview", action="store_true")
    options = parser.parse_args()
    wanted = options.ids or list(sfx_leaves.SOUNDS_RMS)
    violations = []
    for sound_id in wanted:
        if sound_id not in sfx_leaves.SOUNDS_RMS:
            violations.append("%s is not in tools/sfx_leaves.py SOUNDS_RMS" % sound_id)
            continue
        violations += check_id(sound_id, options.png)
    if all(sound_id in wanted for sound_id in ("bag_open", "bag_stuff", "bag_tie")):
        violations += bag_beats()
    if options.preview or (options.png and not options.ids):
        for name, (x, marks) in previews(44100).items():
            wav = OUT_DIR / (name + ".wav")
            write_wav(wav, x, 44100)
            print("preview %s (%.2f s)" % (wav.relative_to(ROOT).as_posix(), len(x) / 44100.0))
            if options.png:
                draw_spectrograms(name.upper(), [(name, x)], 44100, len(x) / 44100.0, OUT_DIR / (name + ".png"), marks)
    print("rake_audio_check: %d violation(s)" % len(violations))
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main())
