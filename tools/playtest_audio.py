#!/usr/bin/env python3
"""Draw a playtest recording's sound on the same time axis as its frames, so an
agent can see whether a sound lines up with the motion (docs/PLAYTEST.md).

Reads <rec dir>/events.json, audio.wav and filmstrip.png written by
net/dev/recorder.gd, and writes:
  audio.png  the filmstrip (thumbnails at their game time), the waveform (peak
             and RMS), 8 octave bands, every sound the game asked for (yellow,
             with its id), the other events (cyan) and the flags (red: pops,
             camera snaps and freezes), over a frame-number axis and a seconds
             axis that match the contact sheet's stamps
  sync.json  for each sound the game asked for: when it was asked for, when the
             mix first got louder after that (its onset), and the lag in ms
The x axis is GAME time. The audio is real time; when the machine ran the fixed
step slower than real time (realtime_ratio under 1) each frame's wall-clock
stamp maps the audio onto game time.

Stdlib only; reuses tools/audio_check.py's WAV reader, FFT bands and PNG canvas.
Usage: python tools/playtest_audio.py build/play/rec_rake
"""
import json
import math
import pathlib
import struct
import sys
import zlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import audio_check as ac  # noqa: E402

# How a sound's onset is found: the RMS envelope in HOP-second steps first rises
# ONSET_DB over the quietest level of the BASELINE seconds before the request,
# within WINDOW seconds after it (and EARLY before, for sounds started a tick early).
HOP = 0.005
BASELINE = 0.06
ONSET_DB = 6.0
FLOOR_DB = -55.0
WINDOW = 0.3
EARLY = 0.05
BAND_FFT = 1024
# The change graph's full height: this much mean colour difference between frames.
CHANGE_FULL = 0.15

YELLOW = (250, 210, 60)
CYAN = (90, 220, 245)
RED = (255, 70, 60)
GRAY = (150, 150, 160)
WHITE = (235, 235, 235)


def read_png(path: pathlib.Path):
    """(width, height, rows of RGB bytes) for an 8-bit RGB or RGBA PNG."""
    data = path.read_bytes()
    pos, idat, width, height, ctype = 8, b"", 0, 0, 2
    while pos < len(data):
        size = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + size]
        if kind == b"IHDR":
            width, height, depth, ctype = struct.unpack(">IIBB", body[:10])
            if depth != 8 or ctype not in (2, 6):
                raise ValueError("unsupported PNG (depth %d, color type %d)" % (depth, ctype))
        elif kind == b"IDAT":
            idat += body
        pos += 12 + size
    bpp = 3 if ctype == 2 else 4
    raw = zlib.decompress(idat)
    stride = width * bpp
    rows, prev = [], bytearray(stride)
    for y in range(height):
        f = raw[y * (stride + 1)]
        line = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if f == 1:
                line[i] = (line[i] + a) & 255
            elif f == 2:
                line[i] = (line[i] + b) & 255
            elif f == 3:
                line[i] = (line[i] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else (b if pb <= pc else c))) & 255
        rows.append(bytes(line) if bpp == 3 else bytes(v for k, v in enumerate(line) if k % 4 != 3))
        prev = line
    return width, height, rows


def wall_of(frames: list, t: float) -> float:
    """The wall-clock second at game time t, from the frames' stamps."""
    if not frames:
        return t
    if t <= frames[0]["t"]:
        return frames[0]["wall"] - (frames[0]["t"] - t)
    for a, b in zip(frames, frames[1:]):
        if a["t"] <= t <= b["t"]:
            span = b["t"] - a["t"]
            k = (t - a["t"]) / span if span > 0 else 0.0
            return a["wall"] + k * (b["wall"] - a["wall"])
    last = frames[-1]
    return last["wall"] + (t - last["t"])


def game_of(frames: list, wall: float) -> float:
    if not frames:
        return wall
    for a, b in zip(frames, frames[1:]):
        if a["wall"] <= wall <= b["wall"]:
            span = b["wall"] - a["wall"]
            k = (wall - a["wall"]) / span if span > 0 else 0.0
            return a["t"] + k * (b["t"] - a["t"])
    if wall < frames[0]["wall"]:
        return frames[0]["t"] - (frames[0]["wall"] - wall)
    return frames[-1]["t"] + (wall - frames[-1]["wall"])


def envelope_db(mono: list, rate: int) -> list:
    hop = max(1, int(HOP * rate))
    out = []
    for start in range(0, len(mono), hop):
        out.append(ac.db(ac.rms(mono[start:start + hop]) * math.sqrt(2.0)))
    return out


def onset(env: list, rate_hops: float, wall: float):
    """The wall second the mix first rises ONSET_DB over the baseline after wall, or None."""
    i0 = int((wall - EARLY) * rate_hops)
    base_from = max(0, int((wall - BASELINE) * rate_hops))
    base_to = max(base_from + 1, int(wall * rate_hops))
    if base_from >= len(env):
        return None
    base = min(env[base_from:min(base_to, len(env))] or [FLOOR_DB])
    for i in range(max(0, i0), min(len(env), int((wall + WINDOW) * rate_hops))):
        if env[i] >= max(base + ONSET_DB, FLOOR_DB):
            return i / rate_hops
    return None


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    rec = pathlib.Path(sys.argv[1])
    log = json.loads((rec / "events.json").read_text(encoding="utf-8"))
    frames = log.get("frames", [])
    film = log.get("film", {})
    margin, width = int(film.get("margin", 36)), int(film.get("width", 2000))
    seconds = max(float(film.get("seconds", 0.0)), 0.001)
    events = log.get("events", [])

    def x_of(t: float) -> int:
        return margin + int(round(t / seconds * width))

    film_rows = None
    film_path = rec / "filmstrip.png"
    if film_path.exists():
        try:
            film_rows = read_png(film_path)
        except Exception as error:  # a bad strip shouldn't stop the audio
            print("filmstrip: %s" % error)
    wav = rec / "audio.wav"
    mono, rate = [], 44100
    if wav.exists():
        chans, rate, _clipped = ac.read(wav)
        mono = ac.mono_of(chans)

    film_h = film_rows[1] if film_rows else 0
    top = 26
    wave_top = top + film_h + 8
    wave_h = 140
    band_top = wave_top + wave_h + 6
    row_h = 12
    change_top = band_top + row_h * len(ac.BANDS) + 6
    change_h = 44
    lanes_top = change_top + change_h + 6
    lane_h = 12
    lanes = 7
    axis_top = lanes_top + lanes * lane_h + 4
    total_h = axis_top + 46
    canvas = ac.Canvas(margin + width + 8, total_h)

    spacing = log.get("spacing", {})
    canvas.text(4, 4, "%s  %d FRAMES AT %.0f FPS  %.2fS  SPACING %s  REALTIME %.2f  %s" % (
        log.get("label", rec.name), len(frames), float(log.get("fps", 0)), seconds,
        "EVEN" if spacing.get("even") else "UNEVEN %.3f-%.3f" % (spacing.get("min", 0), spacing.get("max", 0)),
        float(log.get("realtime_ratio", 1.0)), "FIXED STEP" if log.get("fixed_step") else "NO FIXED STEP"), WHITE, 2)

    if film_rows:
        fw, fh, rows = film_rows
        for y, row in enumerate(rows):
            for x in range(min(fw, canvas.w)):
                canvas.set(x, top + y, (row[3 * x], row[3 * x + 1], row[3 * x + 2]))

    # Waveform and bands, one column per pixel, mapped from game time to the wall clock.
    mid = wave_top + wave_h // 2
    half = wave_h // 2 - 2
    canvas.hline(margin, margin + width - 1, mid, (50, 54, 64))
    canvas.text(2, wave_top + 2, "WAVE", GRAY)
    if mono:
        for col in range(width):
            t0 = col / width * seconds
            t1 = (col + 1) / width * seconds
            a = max(0, int(wall_of(frames, t0) * rate))
            b = min(len(mono), max(a + 1, int(wall_of(frames, t1) * rate)))
            chunk = mono[a:b]
            if not chunk:
                continue
            lo, hi = min(chunk), max(chunk)
            level = ac.rms(chunk) * math.sqrt(2.0)
            canvas.vline(margin + col, mid - int(hi * half), mid - int(lo * half), (110, 150, 200))
            canvas.vline(margin + col, mid - int(level * half), mid + int(level * half), (190, 220, 255))
        for col in range(0, width, 3):
            at = int(wall_of(frames, col / width * seconds) * rate)
            if at >= len(mono):
                break
            for band, level in enumerate(ac.band_levels(mono, rate, max(0, at - BAND_FFT // 2), BAND_FFT)):
                color = ac.heat(level)
                y0 = band_top + (len(ac.BANDS) - 1 - band) * row_h
                for dx in range(3):
                    for dy in range(row_h - 1):
                        canvas.set(margin + col + dx, y0 + dy, color)
    else:
        canvas.text(margin + 8, mid - 4, "NO AUDIO RECORDED (HEADLESS, OR NO AUDIO DEVICE)", RED, 2)
    for band, center in enumerate(ac.BANDS):
        label = ("%dK" % (center // 1000)) if center >= 1000 else str(center)
        canvas.text(2, band_top + (len(ac.BANDS) - 1 - band) * row_h + 3, label, GRAY)

    # How much of the picture changed since the frame before (recorder.gd's
    # "change"): gray for the whole frame, orange for its lower third. Spikes
    # with nothing behind them are pops.
    canvas.text(2, change_top + 2, "CHG", GRAY)
    canvas.hline(margin, margin + width - 1, change_top + change_h, (50, 54, 64))
    for frame in frames:
        x = x_of(float(frame["t"]))
        whole = min(1.0, float(frame.get("change", 0.0)) / CHANGE_FULL)
        low = min(1.0, float(frame.get("change_low", 0.0)) / CHANGE_FULL)
        for dx in (-1, 0, 1):
            canvas.vline(x + dx, change_top + change_h - int(whole * change_h), change_top + change_h, (130, 130, 145))
        canvas.vline(x + 2, change_top + change_h - int(low * change_h), change_top + change_h, (255, 150, 60))
    # Sounds asked for: yellow lines through the wave and bands, ids in three staggered lanes.
    env = envelope_db(mono, rate) if mono else []
    hops = 1.0 / HOP
    sync = []
    lane_of = {}
    for k, event in enumerate(e for e in events if e.get("kind") == "sfx"):
        t = float(event["t"])
        x = x_of(t)
        for y in range(wave_top, change_top + change_h):
            if y % 2 == 0:
                canvas.set(x, y, YELLOW)
        lane = k % 3
        canvas.vline(x, lanes_top + lane * lane_h, lanes_top + lane * lane_h + lane_h - 2, YELLOW)
        canvas.text(x + 2, lanes_top + lane * lane_h + 3, str(event.get("id", "")), YELLOW)
        entry = {"t": t, "id": event.get("id", "")}
        if env:
            wall = wall_of(frames, t)
            found = onset(env, hops, wall)
            if found is None:
                entry["onset"] = None
                entry["note"] = "no onset found within %.0f ms (quiet, far away, or masked)" % (WINDOW * 1000)
            else:
                entry["onset"] = round(game_of(frames, found), 4)
                entry["lag_ms"] = round((found - wall) * 1000.0, 1)
                ox = x_of(game_of(frames, found))
                canvas.vline(ox, wave_top, wave_top + 8, (255, 140, 40))
        sync.append(entry)
    # Every other event in the next lanes (inputs and chunk updates are left out: too many).
    other = [e for e in events if e.get("kind") not in ("sfx", "sfx_at", "look", "chunk_changed", "record_start", "record_stop", "input")]
    for k, event in enumerate(other):
        kind = event.get("kind", "")
        color = RED if kind in ("pop", "cam_snap", "cam_frozen", "view_frozen") else CYAN
        lane = 3 + (k % 3)
        x = x_of(float(event["t"]))
        label = kind
        for key in ("phase", "zone", "who", "to", "kind", "count", "status"):
            if key in event and key != "kind":
                label += " " + str(event[key])
                break
        canvas.vline(x, lanes_top + lane * lane_h, lanes_top + lane * lane_h + lane_h - 2, color)
        canvas.text(x + 2, lanes_top + lane * lane_h + 3, label[:40], color)
        if color == RED:
            for y in range(wave_top, change_top + change_h):
                if y % 3 == 0:
                    canvas.set(x, y, RED)
    # Presses and releases in the last lane.
    for event in events:
        if event.get("kind") == "input" and "action" in event:
            x = x_of(float(event["t"]))
            lane = 6
            canvas.vline(x, lanes_top + lane * lane_h, lanes_top + lane * lane_h + lane_h - 2, WHITE if event.get("pressed") else GRAY)
            canvas.text(x + 2, lanes_top + lane * lane_h + 3, ("+" if event.get("pressed") else "-") + str(event["action"])[:14], WHITE if event.get("pressed") else GRAY)
    canvas.text(2, lanes_top + 3, "SFX", YELLOW)
    canvas.text(2, lanes_top + 3 * lane_h + 3, "EVT", CYAN)
    canvas.text(2, lanes_top + 6 * lane_h + 3, "KEY", WHITE)

    # Frame ticks matching the sheet's #NNN stamps, then seconds.
    step = 1
    if frames:
        px_per_frame = width / max(1, len(frames))
        while step * px_per_frame < 22:
            step += 1
    for frame in frames:
        x = x_of(float(frame["t"]))
        canvas.vline(x, axis_top, axis_top + 3, GRAY)
        if frame["n"] % step == 0:
            canvas.vline(x, axis_top, axis_top + 6, WHITE)
            canvas.text(x - 6, axis_top + 9, "%d" % frame["n"], WHITE)
    canvas.text(2, axis_top + 9, "#", WHITE)
    tick = 0.5 if seconds <= 12 else (1.0 if seconds <= 40 else 5.0)
    t = 0.0
    while t <= seconds + 1e-6:
        x = x_of(t)
        canvas.vline(x, axis_top + 18, axis_top + 24, GRAY)
        canvas.text(x - 6, axis_top + 27, "%.1fS" % t, GRAY)
        t += tick
    canvas.text(margin, axis_top + 38, "X IS GAME TIME. YELLOW: SOUND ASKED FOR (ORANGE TICK: ITS ONSET IN THE MIX). CYAN: EVENTS. RED: POP, CAMERA SNAP, CAMERA OR VIEW FROZEN. GRAY/ORANGE BARS: PICTURE CHANGE (WHOLE/LOWER THIRD).", GRAY)
    canvas.save(rec / "audio.png")
    (rec / "sync.json").write_text(json.dumps({"sounds": sync}, indent=1), encoding="utf-8")
    lags = [s["lag_ms"] for s in sync if s.get("lag_ms") is not None]
    print("audio.png: %d sounds asked for, %d onsets found%s" % (
        len(sync), len(lags), (", lag %.0f to %.0f ms" % (min(lags), max(lags))) if lags else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
