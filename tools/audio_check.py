#!/usr/bin/env python3
"""Measure the game's audio, for agents who can't listen (and as a sanity check
for Taylan's ears). Stdlib only.

For each build/audio/wav/<id>.wav from tools/make_music.py (with the .json
sidecar it writes next to it) it reports:
  length against bars * 4 * 60 / bpm, peak dBFS, RMS dBFS overall and per
  section, clipped samples, DC offset, silences over 1.5 s inside a loop, the
  loop seam (the jump from the last sample to the loop start against the local
  slope, and the RMS of the last 20 ms against the first 20 ms after the loop
  start), stereo correlation, and energy in 8 octave bands.
With --sfx (or by default when no ids are given) it also checks every WAV in
assets/audio/sfx/: length, peak, clipping, DC, and the seam of the *_loop files.

Violations (the exit code is 1 if any):
  loops     RMS outside -19 +-3 dBFS, peak over -1 dBFS, any clipped sample,
            |DC| over 0.01, a silence over 1.5 s, a length off by over 2 ms,
            a seam jump over 4x the local slope (and over 0.02), a seam RMS
            step outside the range of the loop's own bar lines (+-3 dB),
            stereo correlation under 0
  stingers  peak over -1 dBFS, clipped samples, |DC| over 0.01, longer than 6 s,
            RMS outside -30..-14 dBFS
  sfx       clipped samples, an empty or silent file
--png writes build/audio/png/<id>.png: the waveform envelope (peak and RMS)
with section and loop markers over an 8-band energy strip, for the Read tool.

Usage: python tools/audio_check.py                 every music WAV and every SFX
       python tools/audio_check.py rake_it_easy --png
       python tools/audio_check.py --sfx            only the SFX
"""
import argparse
import cmath
import json
import math
import pathlib
import struct
import sys
import wave
import zlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
WAV_DIR = ROOT / "build" / "audio" / "wav"
PNG_DIR = ROOT / "build" / "audio" / "png"
SFX_DIR = ROOT / "assets" / "audio" / "sfx"

TARGET_RMS = -19.0
RMS_TOLERANCE = 3.0
CEILING = -1.0
SILENCE_DBFS = -60.0
SILENCE_SECONDS = 1.5
SEAM_SECONDS = 0.02
SEAM_RMS_STEP_DB = 9.0
BAR_LINE_MARGIN_DB = 3.0
STINGER_MAX_SECONDS = 6.0
STINGER_RMS = (-30.0, -14.0)
BANDS = [63, 125, 250, 500, 1000, 2000, 4000, 8000]


def db(value: float) -> float:
    return 20.0 * math.log10(max(1e-9, value))


def read(path: pathlib.Path) -> tuple[list[list[float]], int, int]:
    """(channels as float lists, rate, clipped sample count)."""
    with wave.open(str(path), "rb") as handle:
        channels, width, rate, frames = handle.getnchannels(), handle.getsampwidth(), handle.getframerate(), handle.getnframes()
        data = handle.readframes(frames)
    if width != 2:
        raise ValueError("%s: %d-byte samples (expected 16-bit)" % (path.name, width))
    values = struct.unpack("<%dh" % (len(data) // 2), data)
    clipped = sum(1 for v in values if v >= 32767 or v <= -32768)
    out = [[v / 32768.0 for v in values[c::channels]] for c in range(channels)]
    return out, rate, clipped


def rms(samples: list[float]) -> float:
    return math.sqrt(sum(v * v for v in samples) / max(1, len(samples)))


def mono_of(chans: list[list[float]]) -> list[float]:
    if len(chans) == 1:
        return chans[0]
    return [0.5 * (a + b) for a, b in zip(chans[0], chans[1])]


def longest_silence(mono: list[float], rate: int, start: int) -> float:
    window = int(0.05 * rate)
    run = best = 0
    threshold = 10.0 ** (SILENCE_DBFS / 20.0)
    for at in range(start, len(mono) - window + 1, window):
        if rms(mono[at:at + window]) < threshold:
            run += 1
            best = max(best, run)
        else:
            run = 0
    return best * window / rate


def seam(chans: list[list[float]], rate: int, loop_start: int) -> dict:
    """How the end runs into the loop start."""
    jump = slope = 0.0
    for side in chans:
        jump = max(jump, abs(side[-1] - side[loop_start]))
        tail = side[-64:]
        slope = max(slope, sum(abs(b - a) for a, b in zip(tail, tail[1:])) / max(1, len(tail) - 1))
    n = int(SEAM_SECONDS * rate)
    end_rms = rms(mono_of([side[-n:] for side in chans]))
    start_rms = rms(mono_of([side[loop_start:loop_start + n] for side in chans]))
    return {"jump": round(jump, 4), "slope": round(slope, 4), "rms_step_db": round(db(end_rms) - db(start_rms), 2)}


def bar_line_steps(chans: list[list[float]], rate: int, loop_start: int, meta: dict) -> list[float]:
    """The RMS step (dB, last 20 ms of a bar against the first 20 ms of the next)
    at every bar line inside the loop."""
    bpm = meta.get("bpm_exact") or meta.get("bpm")
    if not bpm:
        return []
    bar = 4 * 60.0 / bpm * rate
    n = int(SEAM_SECONDS * rate)
    length = len(chans[0])
    out = []
    k = 1
    while loop_start + k * bar + n < length:
        at = int(round(loop_start + k * bar))
        before = rms(mono_of([side[at - n:at] for side in chans]))
        after = rms(mono_of([side[at:at + n] for side in chans]))
        out.append(db(before) - db(after))
        k += 1
    return out


def correlation(chans: list[list[float]]) -> float:
    if len(chans) < 2:
        return 1.0
    left, right = chans
    lr = sum(a * b for a, b in zip(left, right))
    ll = sum(a * a for a in left)
    rr = sum(b * b for b in right)
    return lr / math.sqrt(max(1e-12, ll * rr))


def fft(values: list[complex]) -> list[complex]:
    """In-place iterative radix-2 FFT (len must be a power of two)."""
    n = len(values)
    j = 0
    for i in range(1, n):
        bit = n >> 1
        while j & bit:
            j ^= bit
            bit >>= 1
        j |= bit
        if i < j:
            values[i], values[j] = values[j], values[i]
    size = 2
    while size <= n:
        step = cmath.exp(-2j * math.pi / size)
        half = size // 2
        for start in range(0, n, size):
            w = 1.0
            for k in range(start, start + half):
                a = values[k]
                b = values[k + half] * w
                values[k] = a + b
                values[k + half] = a - b
                w *= step
        size *= 2
    return values


HANN = {}


def band_levels(mono: list[float], rate: int, at: int, size: int = 2048) -> list[float]:
    """dB of energy in each octave band around BANDS, from one Hann-windowed FFT."""
    window = HANN.get(size)
    if window is None:
        window = HANN[size] = [0.5 - 0.5 * math.cos(2.0 * math.pi * k / (size - 1)) for k in range(size)]
    chunk = mono[at:at + size]
    if len(chunk) < size:
        chunk = chunk + [0.0] * (size - len(chunk))
    spectrum = fft([complex(v * w) for v, w in zip(chunk, window)])
    levels = []
    for center in BANDS:
        lo = max(1, int(center / math.sqrt(2.0) * size / rate))
        hi = min(size // 2, max(lo + 1, int(center * math.sqrt(2.0) * size / rate)))
        energy = sum(abs(spectrum[k]) ** 2 for k in range(lo, hi)) / (size * size / 4.0)
        levels.append(10.0 * math.log10(max(1e-12, energy)))
    return levels


# ---------------------------------------------------------------- the PNG

FONT = {
    "A": "010101111101101", "B": "110101110101110", "C": "011100100100011", "D": "110101101101110",
    "E": "111100110100111", "F": "111100110100100", "G": "011100101101011", "H": "101101111101101",
    "I": "111010010010111", "J": "001001001101010", "K": "101101110101101", "L": "100100100100111",
    "M": "101111111101101", "N": "110101101101101", "O": "010101101101010", "P": "110101110100100",
    "Q": "010101101110011", "R": "110101110101101", "S": "011100010001110", "T": "111010010010010",
    "U": "101101101101111", "V": "101101101101010", "W": "101101111111101", "X": "101101010101101",
    "Y": "101101010010010", "Z": "111001010100111", "0": "111101101101111", "1": "010110010010111",
    "2": "110001010100111", "3": "110001010001110", "4": "101101111001001", "5": "111100110001110",
    "6": "011100111101111", "7": "111001010010010", "8": "111101111101111", "9": "111101111001110",
    " ": "000000000000000", ".": "000000000000010", "-": "000000111000000", ":": "000010000010000",
    "_": "000000000000111", "/": "001001010100100", "%": "101001010100101", "+": "000010111010000",
    "=": "000111000111000", "(": "010100100100010", ")": "010001001001010", ",": "000000000010100",
    "!": "010010010000010",
}


class Canvas:
    def __init__(self, width: int, height: int, color=(18, 20, 26)):
        self.w, self.h = width, height
        self.px = bytearray(bytes(color) * (width * height))

    def set(self, x: int, y: int, color) -> None:
        if 0 <= x < self.w and 0 <= y < self.h:
            i = 3 * (y * self.w + x)
            self.px[i:i + 3] = bytes(color)

    def vline(self, x: int, y0: int, y1: int, color) -> None:
        for y in range(min(y0, y1), max(y0, y1) + 1):
            self.set(x, y, color)

    def hline(self, x0: int, x1: int, y: int, color) -> None:
        for x in range(x0, x1 + 1):
            self.set(x, y, color)

    def text(self, x: int, y: int, text: str, color, scale: int = 1) -> None:
        for ch in text.upper():
            glyph = FONT.get(ch, FONT[" "])
            for row in range(5):
                for col in range(3):
                    if glyph[row * 3 + col] == "1":
                        for dy in range(scale):
                            for dx in range(scale):
                                self.set(x + col * scale + dx, y + row * scale + dy, color)
            x += 4 * scale

    def save(self, path: pathlib.Path) -> None:
        raw = b"".join(b"\x00" + bytes(self.px[3 * y * self.w:3 * (y + 1) * self.w]) for y in range(self.h))

        def chunk(kind: bytes, data: bytes) -> bytes:
            return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
        png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", self.w, self.h, 8, 2, 0, 0, 0))
        png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(png)


def heat(level: float) -> tuple[int, int, int]:
    """-70 dB dark blue up to -10 dB pale yellow."""
    k = max(0.0, min(1.0, (level + 70.0) / 60.0))
    stops = [(0.0, (20, 24, 48)), (0.35, (40, 70, 160)), (0.6, (60, 170, 150)), (0.8, (230, 190, 70)), (1.0, (255, 250, 210))]
    for (ka, ca), (kb, cb) in zip(stops, stops[1:]):
        if k <= kb:
            t = (k - ka) / (kb - ka)
            return tuple(int(a + (b - a) * t) for a, b in zip(ca, cb))
    return stops[-1][1]


def draw_png(track_id: str, chans: list[list[float]], rate: int, meta: dict, report: dict, path: pathlib.Path) -> None:
    margin, width = 36, 1200
    wave_top, wave_h = 34, 180
    strip_top = wave_top + wave_h + 18
    row_h = 12
    canvas = Canvas(margin + width + 8, strip_top + row_h * len(BANDS) + 44)
    mono = mono_of(chans)
    n = len(mono)
    per = max(1, n // width)
    mid = wave_top + wave_h // 2
    half = wave_h // 2 - 2
    canvas.text(4, 4, "%s  %.2fS  RMS %.1f  PEAK %.1f  %s" % (
        track_id, n / rate, report["rms_dbfs"], report["peak_dbfs"],
        ("%g BPM  %d BARS" % (meta.get("bpm", 0), meta.get("bars", 0))) if meta else ""), (230, 230, 230), 2)
    ceiling_px = int(half * 10.0 ** (CEILING / 20.0))
    target_px = int(half * 10.0 ** (TARGET_RMS / 20.0) * math.sqrt(2.0))
    for x in range(margin, margin + width):
        canvas.set(x, mid - ceiling_px, (90, 40, 40))
        canvas.set(x, mid + ceiling_px, (90, 40, 40))
        if x % 4 == 0:
            canvas.set(x, mid - target_px, (60, 90, 60))
            canvas.set(x, mid + target_px, (60, 90, 60))
    canvas.hline(margin, margin + width - 1, mid, (50, 54, 64))
    for col in range(width):
        chunk = mono[col * per:(col + 1) * per]
        if not chunk:
            break
        lo, hi = min(chunk), max(chunk)
        level = rms(chunk) * math.sqrt(2.0)
        canvas.vline(margin + col, mid - int(hi * half), mid - int(lo * half), (110, 150, 200))
        canvas.vline(margin + col, mid - int(level * half), mid + int(level * half), (190, 220, 255))
    # The band strip, one column per 3 pixels.
    for col in range(0, width, 3):
        at = min(n - 1, col * per)
        for b, level in enumerate(band_levels(mono, rate, at)):
            color = heat(level)
            y0 = strip_top + (len(BANDS) - 1 - b) * row_h
            for dx in range(3):
                for dy in range(row_h - 1):
                    canvas.set(margin + col + dx, y0 + dy, color)
    for b, center in enumerate(BANDS):
        label = ("%dK" % (center // 1000)) if center >= 1000 else str(center)
        canvas.text(2, strip_top + (len(BANDS) - 1 - b) * row_h + 3, label, (170, 170, 170))
    canvas.text(2, wave_top + 2, "WAVE", (170, 170, 170))
    # Section and loop markers, with each section's RMS under the strip.
    seconds = n / rate
    bottom = strip_top + row_h * len(BANDS)
    for k, section in enumerate(meta.get("sections", [])):
        x = margin + int(section["start"] / seconds * width) if seconds else margin
        canvas.vline(x, wave_top - 2, bottom + 2, (240, 160, 60))
        canvas.text(x + 3, wave_top - 9, section["name"], (240, 180, 90))
        rms_text = "%.0f" % report["section_rms"][k] if k < len(report["section_rms"]) else ""
        canvas.text(x + 3, bottom + 6 + (k % 2) * 8, "%s %s" % (section["name"], rms_text), (200, 200, 200))
    loop_start = meta.get("loop_start_seconds", 0.0)
    if meta.get("loop") and seconds:
        x = margin + int(loop_start / seconds * width)
        canvas.vline(x, wave_top - 4, bottom + 4, (120, 255, 140))
        canvas.text(x + 3, wave_top + wave_h - 8, "LOOP", (120, 255, 140))
    canvas.text(margin, bottom + 30, "PEAK ENVELOPE BLUE, RMS PALE, RED -1 DBFS, GREEN -19 DBFS RMS; BANDS -70 TO -10 DB", (140, 140, 140))
    canvas.save(path)


# ---------------------------------------------------------------- checks

def check_music(path: pathlib.Path, want_png: bool) -> list[str]:
    track_id = path.stem
    sidecar = path.with_suffix(".json")
    meta = json.loads(sidecar.read_text(encoding="utf-8")) if sidecar.exists() else {}
    chans, rate, clipped = read(path)
    mono = mono_of(chans)
    n = len(mono)
    seconds = n / rate
    peak = max(max(map(abs, side)) for side in chans)
    level = math.sqrt(sum(rms(side) ** 2 for side in chans) / len(chans))
    dc = max(abs(sum(side) / max(1, len(side))) for side in chans)
    stinger = bool(meta.get("stinger"))
    loop = bool(meta.get("loop")) and not stinger
    section_rms, sections_out = [], {}
    marks = meta.get("sections", [])
    for k, section in enumerate(marks):
        start = int(section["start"] * rate)
        end = int(marks[k + 1]["start"] * rate) if k + 1 < len(marks) else n
        value = db(math.sqrt(sum(rms(side[start:end]) ** 2 for side in chans) / len(chans)))
        section_rms.append(value)
        sections_out[section["name"] + ("@%d" % k)] = round(value, 1)
    loop_start = int(round(meta.get("loop_start_seconds", 0.0) * rate))
    report = {
        "seconds": round(seconds, 4), "peak_dbfs": round(db(peak), 2), "rms_dbfs": round(db(level), 2),
        "clipped": clipped, "dc": round(dc, 5), "correlation": round(correlation(chans), 3),
        "sections": sections_out, "section_rms": section_rms,
    }
    bpm = meta.get("bpm_exact") or meta.get("bpm")
    expected = meta.get("bars", 0) * 4 * 60.0 / bpm if bpm else None
    if expected is not None and loop and abs(seconds - meta.get("bars", 0) * 240.0 / meta["bpm"]) > 0.6:
        violations_early = ["length %.2f s is far from %d bars at %g bpm" % (seconds, meta["bars"], meta["bpm"])]
    else:
        violations_early = []
    violations = violations_early
    if expected is not None:
        report["expected_seconds"] = round(expected, 4)
    if loop and rate % 50 == 0 and n % (rate // 50):
        violations.append("%d samples is not a whole number of 20 ms frames (tools/encode_ogg.py needs that)" % n)
    if loop:
        report["longest_silence"] = round(longest_silence(mono, rate, loop_start), 2)
        report["seam"] = seam(chans, rate, loop_start)
        if abs(db(level) - TARGET_RMS) > RMS_TOLERANCE:
            violations.append("RMS %.1f dBFS is outside %g +-%g" % (db(level), TARGET_RMS, RMS_TOLERANCE))
        if expected is not None and abs(seconds - expected) > 0.002:
            violations.append("length %.4f s, expected %.4f s" % (seconds, expected))
        if report["longest_silence"] > SILENCE_SECONDS:
            violations.append("a %.1f s silence inside the loop" % report["longest_silence"])
        sm = report["seam"]
        if sm["jump"] > max(0.02, 4.0 * sm["slope"]):
            violations.append("seam jump %.3f against a local slope of %.3f" % (sm["jump"], sm["slope"]))
        # The seam is a bar line, and a downbeat is louder than the end of a bar:
        # it must look like the loop's other bar lines, give or take a few dB.
        steps = bar_line_steps(chans, rate, loop_start, meta)
        if steps:
            low, high = min(steps) - BAR_LINE_MARGIN_DB, max(steps) + BAR_LINE_MARGIN_DB
            sm["bar_lines_db"] = [round(min(steps), 1), round(max(steps), 1)]
            if not low <= sm["rms_step_db"] <= high:
                violations.append("seam RMS step %.1f dB, while the loop's bar lines step %.1f..%.1f dB" % (
                    sm["rms_step_db"], min(steps), max(steps)))
        elif abs(sm["rms_step_db"]) > SEAM_RMS_STEP_DB:
            violations.append("seam RMS step %.1f dB" % sm["rms_step_db"])
        if len(chans) == 2 and report["correlation"] < 0.0:
            violations.append("stereo correlation %.2f (out of phase)" % report["correlation"])
    else:
        if seconds > STINGER_MAX_SECONDS:
            violations.append("a %.2f s stinger (at most %g)" % (seconds, STINGER_MAX_SECONDS))
        if not STINGER_RMS[0] <= db(level) <= STINGER_RMS[1]:
            violations.append("stinger RMS %.1f dBFS outside %g..%g" % (db(level), *STINGER_RMS))
    if db(peak) > CEILING + 0.01:
        violations.append("peak %.2f dBFS over %g" % (db(peak), CEILING))
    if clipped:
        violations.append("%d clipped samples" % clipped)
    if dc > 0.01:
        violations.append("DC offset %.4f" % dc)
    # Average band energy over the whole file.
    step = max(2048, n // 120)
    totals = [0.0] * len(BANDS)
    count = 0
    for at in range(0, max(1, n - 2048), step):
        for b, value in enumerate(band_levels(mono, rate, at)):
            totals[b] += 10.0 ** (value / 10.0)
        count += 1
    report["bands_db"] = {str(c): round(10.0 * math.log10(max(1e-12, t / max(1, count))), 1) for c, t in zip(BANDS, totals)}
    print("%s (%s): %s" % (track_id, "stinger" if stinger else "loop", json.dumps({k: v for k, v in report.items() if k != "section_rms"})))
    for violation in violations:
        print("  VIOLATION %s: %s" % (track_id, violation))
    if want_png:
        png = PNG_DIR / (track_id + ".png")
        draw_png(track_id, chans, rate, meta, report, png)
        print("  png %s" % png.relative_to(ROOT).as_posix())
    return violations


def check_sfx() -> list[str]:
    violations = []
    paths = sorted(SFX_DIR.glob("*.wav"))
    worst_peak, worst_dc = ("", -200.0), ("", 0.0)
    for path in paths:
        chans, rate, clipped = read(path)
        n = len(chans[0])
        peak = max(max(map(abs, side)) for side in chans) if n else 0.0
        dc = max(abs(sum(side) / max(1, n)) for side in chans) if n else 0.0
        notes = []
        if n == 0 or peak < 1e-4:
            violations.append("%s is empty or silent" % path.name)
        if clipped > 0:
            violations.append("%s has %d clipped samples" % (path.name, clipped))
        if path.stem.endswith("_loop") and n:
            sm = seam(chans, rate, 0)
            notes.append("seam %s" % sm)
        if db(peak) > worst_peak[1]:
            worst_peak = (path.name, db(peak))
        if dc > worst_dc[1]:
            worst_dc = (path.name, dc)
        if notes:
            print("sfx %s: %.2f s, peak %.1f dBFS, %s" % (path.name, n / rate, db(peak), "; ".join(notes)))
    print("sfx: %d files; loudest peak %s %.1f dBFS; largest DC %s %.4f" % (len(paths), worst_peak[0], worst_peak[1], worst_dc[0], worst_dc[1]))
    for violation in violations:
        print("  VIOLATION sfx: %s" % violation)
    return violations


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("ids", nargs="*")
    parser.add_argument("--png", action="store_true")
    parser.add_argument("--sfx", action="store_true", help="check assets/audio/sfx (the default with no ids)")
    options = parser.parse_args()
    violations = []
    if options.ids:
        paths = [WAV_DIR / (i + ".wav") for i in options.ids]
    elif options.sfx:
        paths = []
    else:
        paths = sorted(p for p in WAV_DIR.glob("*.wav") if not p.stem.startswith("_"))
    for path in paths:
        if not path.exists():
            violations.append("%s is missing (run tools/make_music.py)" % path.name)
            print("  VIOLATION %s" % violations[-1])
            continue
        violations += check_music(path, options.png)
    if options.sfx or not options.ids:
        violations += check_sfx()
    print("audio_check: %d violation(s)" % len(violations))
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main())
