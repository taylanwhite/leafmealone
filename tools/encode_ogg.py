#!/usr/bin/env python3
"""Encode the music WAVs from tools/make_music.py into assets/audio/music/<id>.ogg.

Routes, tried in this order (the first that is available wins):
  soundfile  the Python soundfile package (needs numpy), if it is importable
  ffmpeg     ffmpeg with libvorbis on PATH
  oggenc     oggenc (vorbis-tools) on PATH
  godot      Godot 4.7.2's Movie Maker: it plays the WAV through the OGV writer
             (Theora + Vorbis), and this script copies the Vorbis logical stream's
             Ogg pages, unchanged, out of the .ogv into a plain .ogg.
  wav        with --wav-fallback, the WAV itself is copied into assets/audio/music/
             (docs/DECISIONS.md says when that would be allowed).
This machine has no ffmpeg, oggenc or soundfile, so the godot route is the one
that runs here (docs/DECISIONS.md, "Audio: the music pipeline").

Every route writes the same layout, so a track's loop point is always its intro
plus Constants.MUSIC_ENCODE_LEAD_SECONDS (one Movie Maker frame, 0.02 s):
  the .ogg holds the song, then one more frame (882 samples) of the loop's own
  start (for a stinger, silence). Movie Maker records whole frames, and Godot
  plays an Ogg to its last packet (it ignores an end-trimming granule), so a
  loop can't end mid-frame. make_music.py makes every loop a whole number of
  frames long; Godot's playback starts L samples late (L = 66 here), so the
  .ogg is L samples of silence, the song, then 882 - L samples of the loop
  start. Playing to the end and jumping to intro + 882 samples lands exactly
  where the song continues, whatever L is.

--verify plays each encoded .ogg back through Godot (Movie Maker into an AVI with
PCM audio), lines it up against the source WAV, and reports the latency, the
length Godot reports, and how well the first pass, the seam and the second pass
match (SNR in dB; Vorbis is lossy, so about 20 dB or more means aligned, and
under 5 dB means it isn't). --measure-lead reports Godot's playback latency L
with a click track.

Usage: python tools/encode_ogg.py                    every WAV in build/audio/wav
       python tools/encode_ogg.py rake_it_easy        only that id
       python tools/encode_ogg.py --route=godot --quality=0.35 --verify rake_it_easy
       python tools/encode_ogg.py --measure-lead
Env GODOT overrides the Godot executable.
"""
import argparse
import importlib.util
import json
import math
import os
import pathlib
import shutil
import struct
import subprocess
import sys
import wave

ROOT = pathlib.Path(__file__).resolve().parent.parent
BUILD = ROOT / "build" / "audio"
WAV_DIR = BUILD / "wav"
OGV_DIR = BUILD / "ogv"
CHECK_DIR = BUILD / "check"
RENDER = BUILD / "render"
OUT_DIR = ROOT / "assets" / "audio" / "music"
CONSTANTS = ROOT / "core" / "constants.gd"
FPS = 50
RATE = 44100
FRAME = RATE // FPS
DEFAULT_QUALITY = 0.35
## Under this SNR (dB) a verify comparison counts as misaligned.
VERIFY_MIN_SNR_DB = 12.0


# ---------------------------------------------------------------- helpers

def log(text: str) -> None:
    print(text, flush=True)


def encode_lead_seconds() -> float:
    """Constants.MUSIC_ENCODE_LEAD_SECONDS: how far past the intro a loop goes back to."""
    for line in CONSTANTS.read_text(encoding="utf-8").splitlines():
        if line.startswith("const MUSIC_ENCODE_LEAD_SECONDS"):
            return float(line.split("=")[1].split("#")[0])
    raise SystemExit("encode_ogg: no MUSIC_ENCODE_LEAD_SECONDS in core/constants.gd")


def sidecar(track_id: str) -> dict:
    """What tools/make_music.py wrote about the track (loop start, stinger or not)."""
    path = WAV_DIR / (track_id + ".json")
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}


def godot_exe() -> str:
    if os.environ.get("GODOT"):
        return os.environ["GODOT"]
    home = pathlib.Path(os.environ.get("USERPROFILE", str(pathlib.Path.home())))
    for name in ("Godot_v4.7.2-stable_win64_console.exe", "Godot_v4.7.2-stable_win64.exe"):
        candidate = home / "Tools" / "Godot" / name
        if candidate.exists():
            return str(candidate)
    for name in ("godot", "godot4"):
        found = shutil.which(name)
        if found:
            return found
    raise SystemExit("encode_ogg: no Godot found (set GODOT)")


def read_wav(path: pathlib.Path) -> tuple[bytes, int, int, int]:
    """(frames as bytes, frame count, channels, rate); 16-bit only."""
    with wave.open(str(path), "rb") as handle:
        if handle.getsampwidth() != 2:
            raise RuntimeError("%s is not 16-bit" % path.name)
        frames = handle.getnframes()
        return handle.readframes(frames), frames, handle.getnchannels(), handle.getframerate()


def write_wav(path: pathlib.Path, data: bytes, channels: int, rate: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(channels)
        handle.setsampwidth(2)
        handle.setframerate(rate)
        handle.writeframes(data)


def pcm_to_mono(data: bytes, channels: int, width: int) -> list[float]:
    if width == 2:
        values = struct.unpack("<%dh" % (len(data) // 2), data)
        scale = 1.0 / 32768.0
    elif width == 4:
        values = struct.unpack("<%di" % (len(data) // 4), data)
        scale = 1.0 / 2147483648.0
    elif width == 3:
        values = [int.from_bytes(data[i:i + 3], "little", signed=True) for i in range(0, len(data) - 2, 3)]
        scale = 1.0 / 8388608.0
    else:
        raise ValueError("unsupported sample width %d" % width)
    if channels == 1:
        return [v * scale for v in values]
    return [sum(values[i:i + channels]) * scale / channels for i in range(0, len(values) - channels + 1, channels)]


def read_wav_mono(path: pathlib.Path) -> list[float]:
    data, _frames, channels, _rate = read_wav(path)
    return pcm_to_mono(data, channels, 2)


# ---------------------------------------------------------------- Ogg pages

def parse_pages(data: bytes) -> list[dict]:
    pages, at = [], 0
    while at < len(data):
        if data[at:at + 4] != b"OggS":
            found = data.find(b"OggS", at + 1)
            if found < 0:
                break
            at = found
            continue
        header_type = data[at + 5]
        granule, serial = struct.unpack_from("<qI", data, at + 6)
        segments = data[at + 26]
        body = sum(data[at + 27:at + 27 + segments])
        end = at + 27 + segments + body
        pages.append({"type": header_type, "granule": granule, "serial": serial,
                      "payload": data[at + 27 + segments:end], "raw": data[at:end]})
        at = end
    return pages


def vorbis_stream(ogv: bytes) -> tuple[bytes, dict]:
    """The Vorbis logical stream of an Ogg container (an .ogv), pages unchanged."""
    pages = parse_pages(ogv)
    serial = next((p["serial"] for p in pages if p["type"] & 0x02 and p["payload"][:7] == b"\x01vorbis"), None)
    if serial is None:
        raise RuntimeError("no Vorbis stream in the .ogv (did Movie Maker record audio?)")
    ours = [p for p in pages if p["serial"] == serial]
    header = ours[0]["payload"]
    stats = {
        "pages": len(ours), "channels": header[11], "rate": struct.unpack_from("<I", header, 12)[0],
        "samples": max((p["granule"] for p in ours if p["granule"] >= 0), default=0),
        "eos": bool(ours[-1]["type"] & 0x04),
    }
    return b"".join(p["raw"] for p in ours), stats


# ---------------------------------------------------------------- the Godot route

def write_render_project(quality: float) -> None:
    """A throwaway project, so none of the game's autoloads (Net, Steam, ...) start."""
    (RENDER / "tools" / "audio").mkdir(parents=True, exist_ok=True)
    (BUILD / ".gdignore").write_text("", encoding="utf-8")
    project = "\n".join([
        "config_version=5", "",
        "[application]", "",
        'config/name="Leaf Me Alone OGG render"',
        'run/main_scene="res://tools/audio/ogg_render.tscn"', "",
        "[display]", "",
        "window/size/viewport_width=64",
        "window/size/viewport_height=64", "",
        "[editor]", "",
        "movie_writer/mix_rate=%d" % RATE,
        "movie_writer/speaker_mode=0",
        "movie_writer/ogv/audio_quality=%s" % quality,
        "movie_writer/ogv/encoding_speed=4", "",
        "[rendering]", "",
        'renderer/rendering_method="gl_compatibility"', "",
    ])
    (RENDER / "project.godot").write_text(project, encoding="utf-8")
    for name in ("ogg_render.gd", "ogg_render.tscn"):
        shutil.copyfile(ROOT / "tools" / "audio" / name, RENDER / "tools" / "audio" / name)


def run_movie(movie: pathlib.Path, user_args: list[str]) -> str:
    movie.parent.mkdir(parents=True, exist_ok=True)
    if movie.exists():
        movie.unlink()
    command = [
        godot_exe(), "--path", str(RENDER), "--write-movie", str(movie), "--fixed-fps", str(FPS),
        "--resolution", "64x64", "--disable-vsync", "--audio-driver", "Dummy",
        "res://tools/audio/ogg_render.tscn", "--", *user_args,
    ]
    result = subprocess.run(command, capture_output=True, text=True, timeout=900)
    output = (result.stdout or "") + (result.stderr or "")
    if not movie.exists() or movie.stat().st_size == 0:
        raise RuntimeError("Movie Maker wrote nothing (exit %d):\n%s" % (result.returncode, output[-3000:]))
    return output


def encoder_input(track_id: str, wav: pathlib.Path) -> tuple[pathlib.Path, int, int]:
    """The WAV the encoder plays: the song plus one frame of what comes after its
    end (the loop start, or silence for a stinger). Returns (path, frames to record,
    song samples)."""
    data, frames, channels, rate = read_wav(wav)
    if rate != RATE:
        raise RuntimeError("%s is %d Hz; music is %d Hz" % (wav.name, rate, RATE))
    meta = sidecar(track_id)
    width = 2 * channels
    if meta.get("loop", False):
        if frames % FRAME:
            raise RuntimeError("%s is %d samples, not a whole number of %d-sample frames "
                               "(make_music.py frame-aligns loops; re-render it)" % (wav.name, frames, FRAME))
        start = int(round(meta.get("loop_start_seconds", 0.0) * RATE))
        after = data[start * width:(start + FRAME) * width]
    else:
        pad = (-frames) % FRAME
        data += bytes(pad * width)
        frames += pad
        after = bytes(FRAME * width)
    path = OGV_DIR / (track_id + "_input.wav")
    write_wav(path, data + after, channels, rate)
    return path, frames // FRAME + 1, frames


def encode_godot(track_id: str, wav: pathlib.Path, out: pathlib.Path, quality: float) -> dict:
    write_render_project(quality)
    source, frames, _song = encoder_input(track_id, wav)
    ogv = OGV_DIR / (track_id + ".ogv")
    run_movie(ogv, ["--wav=" + str(source.resolve()), "--frames=%d" % frames])
    data, stats = vorbis_stream(ogv.read_bytes())
    if stats["samples"] != frames * FRAME:
        raise RuntimeError("Movie Maker recorded %d samples, expected %d" % (stats["samples"], frames * FRAME))
    out.write_bytes(data)
    return stats


# ---------------------------------------------------------------- other routes

def encode_external(route: str, track_id: str, wav: pathlib.Path, out: pathlib.Path, quality: float) -> dict:
    """The same layout through a real encoder: the song, then one frame of what
    follows it. With no latency in front, the jump back to intro + one frame lands
    right after that frame, so the loop point is the same as the Godot route's."""
    shifted, frames, _song = encoder_input(track_id, wav)
    if route == "soundfile":
        import numpy  # noqa: F401  (soundfile needs it)
        import soundfile
        samples, sample_rate = soundfile.read(str(shifted))
        try:
            # libsndfile's Vorbis "compression level" runs the other way from quality.
            soundfile.write(str(out), samples, sample_rate, format="OGG", subtype="VORBIS",
                            compression_level=max(0.0, min(1.0, 1.0 - quality)))
        except TypeError:
            print("encode_ogg: this soundfile (< 0.11) has no compression_level; --quality %.2f is ignored "
                  "and libsndfile's default Vorbis quality is used" % quality)
            soundfile.write(str(out), samples, sample_rate, format="OGG", subtype="VORBIS")
    elif route == "ffmpeg":
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(shifted), "-c:a", "libvorbis",
                        "-q:a", "%.1f" % (quality * 10.0), str(out)], check=True)
    else:
        subprocess.run(["oggenc", "-Q", "-q", "%.1f" % (quality * 10.0), "-o", str(out), str(shifted)], check=True)
    return {"samples": frames * FRAME}


def available_route() -> str:
    if importlib.util.find_spec("soundfile") and importlib.util.find_spec("numpy"):
        return "soundfile"
    if shutil.which("ffmpeg"):
        return "ffmpeg"
    if shutil.which("oggenc"):
        return "oggenc"
    return "godot"


# ---------------------------------------------------------------- verification

def read_avi_audio(path: pathlib.Path) -> list[float]:
    """The PCM audio of a Movie Maker AVI (MJPEG video + PCM audio), as mono floats."""
    data = path.read_bytes()
    channels, width = 2, 2
    at = data.find(b"strf")
    while at >= 0:
        size = struct.unpack_from("<I", data, at + 4)[0]
        if size in (16, 18, 40):
            fmt, ch, _rate, _bps, _align, bits = struct.unpack_from("<HHIIHH", data, at + 8)
            if fmt in (1, 3, 0xFFFE):
                channels, width = ch, bits // 8
                break
        at = data.find(b"strf", at + 4)
    chunks = []
    at = data.find(b"movi")
    while True:
        at = data.find(b"01wb", at)
        if at < 0:
            break
        size = struct.unpack_from("<I", data, at + 4)[0]
        chunks.append(data[at + 8:at + 8 + size])
        at += 8 + size + (size & 1)
    return pcm_to_mono(b"".join(chunks), channels, width)


def onset(samples: list[float], threshold: float = 0.02) -> int:
    return next((i for i, v in enumerate(samples) if abs(v) > threshold), 0)


def best_offset(reference: list[float], test: list[float], guess: int, radius: int, start: int, length: int) -> int:
    """The offset (test index - reference index) that best lines the two up near guess."""
    best, best_score = guess, -1e18
    ref = reference[start:start + length]
    for offset in range(guess - radius, guess + radius + 1):
        if start + offset < 0:
            continue
        seg = test[start + offset:start + offset + length]
        if len(seg) < len(ref):
            continue
        score = sum(a * b for a, b in zip(ref, seg))
        if score > best_score:
            best, best_score = offset, score
    return best


def snr_db(reference: list[float], test: list[float]) -> float:
    signal = sum(v * v for v in reference) or 1e-12
    error = sum((a - b) ** 2 for a, b in zip(reference, test)) or 1e-12
    return round(10.0 * math.log10(signal / error), 1)


def godot_play(source: pathlib.Path, name: str, frames: int, loop_offset: float | None = None) -> tuple[list[float], str]:
    write_render_project(DEFAULT_QUALITY)
    avi = CHECK_DIR / (name + ".avi")
    args = ["--frames=%d" % frames, ("--ogg=" if source.suffix == ".ogg" else "--wav=") + str(source.resolve())]
    if loop_offset is not None:
        args.append("--loop-offset=%.6f" % loop_offset)
    output = run_movie(avi, args)
    return read_avi_audio(avi), output


def verify(track_id: str, wav: pathlib.Path, ogg: pathlib.Path) -> dict:
    """Play the .ogg back through Godot (looped as the game will) and line it up against the WAV."""
    source = read_wav_mono(wav)
    n = len(source)
    meta = sidecar(track_id)
    loop = bool(meta.get("loop"))
    loop_start = int(round(meta.get("loop_start_seconds", 0.0) * RATE))
    lead_seconds = encode_lead_seconds()
    lead = int(lead_seconds * RATE)  # Godot truncates a seek time to a sample, so this does too
    first = onset(source)
    # The plain WAV through the same path gives Godot's playback latency alone.
    played, _ = godot_play(wav, track_id + "_wav", min(n // FRAME, 4 * FPS))
    play_lag = best_offset(source, played, onset(played) - first, 64, max(0, first - 256), 4096)
    frames = (2 * n - loop_start) // FRAME + 2 * FPS if loop else n // FRAME + FPS
    loop_offset = meta.get("loop_start_seconds", 0.0) + lead_seconds
    decoded, output = godot_play(ogg, track_id + "_ogg", frames, loop_offset if loop else None)
    lag = best_offset(source, decoded, onset(decoded) - first, 96, max(0, first - 256), 4096)
    report = {"playback_latency": play_lag, "encode_latency": lag - play_lag}
    for line in output.splitlines():
        if line.startswith("[OggRender] length"):
            report["godot_length"] = float(line.split()[2])
    window = min(RATE, n // 4)
    mid = n // 2
    report["snr_pass1_db"] = snr_db(source[mid:mid + window], decoded[mid + lag:mid + lag + window])
    if loop:
        # The stream ends one frame after the song; Godot then jumps to loop_start + lead,
        # which holds source[loop_start + lead - encode_latency].
        encode_lag = lag - play_lag
        wrap = play_lag + n + FRAME
        resume = loop_start + lead - encode_lag
        seam = int(0.05 * RATE)
        # Up to the wrap: the song's end, then the frame of loop start the encode carries.
        extended = source + source[loop_start:loop_start + FRAME]
        before = extended[n + FRAME - encode_lag - seam:n + FRAME - encode_lag]
        report["snr_seam_db"] = snr_db(before + source[resume:resume + seam], decoded[wrap - seam:wrap + seam])
        report["snr_pass2_db"] = snr_db(source[resume + RATE:resume + RATE + window], decoded[wrap + RATE:wrap + RATE + window])
        report["ok"] = min(report["snr_pass1_db"], report["snr_seam_db"], report["snr_pass2_db"]) >= VERIFY_MIN_SNR_DB
    else:
        report["ok"] = report["snr_pass1_db"] >= VERIFY_MIN_SNR_DB
    return report


def measure_lead() -> None:
    """Godot's playback latency, from a click track played through Movie Maker."""
    WAV_DIR.mkdir(parents=True, exist_ok=True)
    probe = OGV_DIR / "_latency_probe.wav"
    samples = [0.0] * (6 * RATE)
    for beat in range(12):
        start = int(beat * 0.5 * RATE)
        for i in range(400):
            samples[start + i] += 0.6 * math.sin(2.0 * math.pi * 1000.0 * i / RATE) * math.exp(-i / 120.0)
    write_wav(probe, b"".join(struct.pack("<hh", int(v * 32767), int(v * 32767)) for v in samples), 2, RATE)
    played, _ = godot_play(probe, "_latency_probe", 4 * FPS)
    latency = best_offset(samples, played, onset(played) - onset(samples), 64, 0, 4096)
    log("Godot's playback latency: %d samples (%.4f s). Constants.MUSIC_ENCODE_LEAD_SECONDS stays one frame "
        "(%d samples) as long as this is under a frame." % (latency, latency / RATE, FRAME))


# ---------------------------------------------------------------- main

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("ids", nargs="*")
    parser.add_argument("--route", default="auto", choices=["auto", "soundfile", "ffmpeg", "oggenc", "godot"])
    parser.add_argument("--quality", type=float, default=DEFAULT_QUALITY, help="Vorbis VBR quality, -0.1 to 1.0")
    parser.add_argument("--wav-fallback", action="store_true", help="copy the WAV into assets/audio/music instead")
    parser.add_argument("--verify", action="store_true", help="decode through Godot and check the latency and the loop")
    parser.add_argument("--measure-lead", action="store_true")
    options = parser.parse_args()
    if options.measure_lead:
        measure_lead()
        return 0
    ids = options.ids or sorted(p.stem for p in WAV_DIR.glob("*.wav") if not p.stem.startswith("_"))
    if not ids:
        log("encode_ogg: nothing in build/audio/wav (run tools/make_music.py first)")
        return 1
    if int(encode_lead_seconds() * RATE) != FRAME:
        log("encode_ogg: Constants.MUSIC_ENCODE_LEAD_SECONDS should be one frame (%g s)" % (FRAME / RATE))
        return 1
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    route = available_route() if options.route == "auto" else options.route
    failures = 0
    for track_id in ids:
        wav = WAV_DIR / (track_id + ".wav")
        if not wav.exists():
            log("%s: missing %s" % (track_id, wav))
            failures += 1
            continue
        if options.wav_fallback:
            out = OUT_DIR / (track_id + ".wav")
            shutil.copyfile(wav, out)
            log("%s: route wav-fallback  %s  %.1f KB" % (track_id, out.relative_to(ROOT).as_posix(), out.stat().st_size / 1024))
            continue
        out = OUT_DIR / (track_id + ".ogg")
        if route == "godot":
            stats = encode_godot(track_id, wav, out, options.quality)
        else:
            stats = encode_external(route, track_id, wav, out, options.quality)
        log("%s: route %s  %s  %.1f KB  %.4f s in the stream" % (
            track_id, route, out.relative_to(ROOT).as_posix(), out.stat().st_size / 1024, stats["samples"] / RATE))
        if options.verify:
            report = verify(track_id, wav, out)
            log("  verify: %s" % report)
            failures += 0 if report["ok"] else 1
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
