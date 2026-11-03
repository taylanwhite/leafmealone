#!/usr/bin/env python3
"""The tense half of the soundtrack (audio chunk 4b), a song book for tools/make_music.py.

make_music.py calls register(module, SONGS) before it renders, so these songs,
and the few instruments and drums only they use, render and list exactly like
the ones written in make_music.py itself:
    python tools/make_music.py hot_yard nice_boys_chase --preview
It lives in its own file so the calm songs (chunk 4a) and these never edit the
same lines.

Loops: hot_yard ("Hot Yard"), nice_boys_incoming ("Paperwork Incoming"),
nice_boys_chase ("The NICE BOYS") and escape_run ("Clean Getaway", the
escape/end-sequence cue: Border Return today, the Field Office escape later;
the music director's "crossing" mood is an alias of its "escape" mood).
Stingers: st_rank_up, st_season, st_morning, st_new_client, st_job_paid,
st_busted, st_made_it.

Musical guardrail (docs/ART.md, "Audio"): no Latin-American or regional genre
signifiers. Tension here is funk, keystone-cop slapstick and arcade chiptune;
the NICE BOYS' cues mock bureaucracy (typewriters, rubber stamps, a tuba, police
whistles), never anybody's background.
"""
import math

TAU = 2.0 * math.pi

# Set by register(): the make_music module itself (when it runs as __main__ this
# is that module, so its RATE, which --preview changes, is the one we read).
m = None


# ---------------------------------------------------------------- instruments

def i_xylo(f, hold, vel, rng, glide=None):
    """A xylophone: hard mallets on rosewood, a bright 3x partial and a short ring."""
    seconds = min(0.9, 0.35 + 200.0 / f)
    rate = 6.0 + f / 260.0
    out = m.partials(f, seconds, [(1.0, 1.0, rate), (3.0, 0.45 * vel, rate * 2.2), (6.2, 0.12 * vel, rate * 4.5)])
    click = m.expdecay(m.one_pole_hp(m.noise(rng, 0.008), 2500.0), 600.0)
    m.mix(out, click, 0, 0.3 * vel)
    return m.apply(out, m.adsr(len(out), 0.001, len(out), 0.01))


def i_trombone(f, hold, vel, rng, glide=None):
    """A plunger-muted trombone: every note opens 'wah', and a long one wobbles (the sad trombone)."""
    seconds = max(hold, 0.1) + 0.18
    long_note = hold > 0.6
    fn = m.vibrato_fn(f, 4.6 if long_note else 5.4, 0.032 if long_note else 0.006,
                      delay=0.22 if long_note else 0.12, scoop=0.03, glide_from=glide)
    raw = m.osc(fn, seconds, "saw")
    wah = m.s.bandpass(raw, lambda t: 380.0 + 1100.0 * min(1.0, t / 0.18), 2.0)
    body = m.one_pole_lp(raw, 900.0)
    out = [a * 1.3 + b * 0.5 for a, b in zip(wah, body)]
    return m.apply(out, m.adsr(len(out), 0.03, int(hold * m.RATE), 0.14))


def i_boing(f, hold, vel, rng, glide=None):
    """A cartoon spring: the pitch wobbles hard and settles while it dies away."""
    seconds = 0.75
    rate = m.RATE

    def fn(i: int) -> float:
        t = i / rate
        return f * (1.0 + 0.42 * math.exp(-5.0 * t) * math.sin(TAU * 13.0 * t)) * (1.0 - 0.12 * min(1.0, t / 0.75))
    body = m.osc(fn, seconds, "triangle")
    ring = m.osc(lambda i: 2.0 * fn(i), seconds, "sine")
    out = [a + 0.25 * b for a, b in zip(body, ring)]
    return m.apply(m.expdecay(out, 4.0), m.adsr(len(out), 0.002, len(out) - int(0.05 * rate), 0.05))


def i_bell(f, hold, vel, rng, glide=None):
    """A doorbell chime: a struck bar with a long, slightly inharmonic ring."""
    out = m.partials(f, 2.2, [(1.0, 1.0, 1.5), (2.0, 0.32, 2.8), (2.76, 0.22, 4.4), (5.4, 0.07, 9.0)])
    strike = m.expdecay(m.one_pole_hp(m.noise(rng, 0.006), 3000.0), 900.0)
    m.mix(out, strike, 0, 0.15)
    return m.apply(out, m.adsr(len(out), 0.001, len(out), 0.01))


# ---------------------------------------------------------------- drums

def _held_noise(rng, seconds: float, hold_n: int) -> list:
    """Chip noise: a random level held for hold_n samples, like a game console's noise channel."""
    out = []
    level = 0.0
    for i in range(int(seconds * m.RATE)):
        if i % hold_n == 0:
            level = 1.0 if rng.random() < 0.5 else -1.0
        out.append(level)
    return out


def d_kick_seam(vel, rng):
    """make_music's kick with its click faded in over 1.5 ms: these loops go back
    to a downbeat kick, and a click starting at full level is a jump at the seam."""
    out = m.d_kick(vel, rng)
    ramp = int(0.0015 * m.RATE)
    for i in range(min(ramp, len(out))):
        out[i] *= i / ramp
    return out


def d_chip_kick(vel, rng):
    """A chip kick: a square wave dropping fast from 150 Hz, in 4-bit steps."""
    rate = m.RATE
    n = int(0.17 * rate)
    out = [0.0] * n
    phase = 0.0
    for i in range(n):
        t = i / rate
        phase += (45.0 + 105.0 * math.exp(-t * 40.0)) / rate
        phase -= int(phase)
        v = (1.0 if phase < 0.5 else -1.0) * math.exp(-t * 16.0)
        out[i] = round(v * 7.5) / 7.5
    return out


def d_chip_snare(vel, rng):
    """A chip snare: coarse held noise over a short square blip."""
    rate = m.RATE
    noise_ = m.expdecay(_held_noise(rng, 0.16, max(1, rate // 9000)), 26.0)
    blip = m.expdecay(m.osc(lambda i: 260.0 - 80.0 * min(1.0, i / (0.04 * rate)), 0.16, "square"), 40.0)
    return [a * 0.8 + b * 0.35 for a, b in zip(noise_, blip)]


def d_chip_hat(vel, rng):
    """A chip hat: fine held noise, gone in 40 ms."""
    return m.expdecay(m.one_pole_hp(_held_noise(rng, 0.05, 2), 5000.0), 90.0)


def d_kaching(vel, rng):
    """A cash register: the keys' 'ka' clack and drawer thunk, then the bell's 'ching'."""
    out = m.silence(1.0)
    m.mix(out, m.expdecay(m.biquad_bp(m.noise(rng, 0.05), 2200.0, 2.0), 90.0), 0, 0.9)
    m.mix(out, m.expdecay(m.osc(180.0, 0.06, "square"), 60.0), 0, 0.3)
    m.mix(out, m.expdecay(m.one_pole_lp(m.noise(rng, 0.06), 900.0), 70.0), int(0.05 * m.RATE), 0.6)
    ching = m.partials(2093.0, 0.85, [(1.0, 0.6, 5.5), (1.266, 0.42, 6.5), (2.0, 0.18, 9.0)])
    m.mix(out, ching, int(0.08 * m.RATE), 1.0)
    return out


INSTRUMENTS = {"xylo": i_xylo, "trombone": i_trombone, "boing": i_boing, "bell": i_bell}
DRUMS = {"kick_seam": d_kick_seam, "chip_kick": d_chip_kick, "chip_snare": d_chip_snare, "chip_hat": d_chip_hat, "kaching": d_kaching}
PLACEMENT = {
    "kick_seam": (0.0, 0.02), "chip_kick": (0.0, 0.02), "chip_snare": (0.05, 0.08), "chip_hat": (0.25, 0.04),
    "kaching": (0.1, 0.15), "triangle": (0.0, 0.03),
}


# ---------------------------------------------------------------- the loops

def _siren(bar: int = 7) -> object:
    """Hot Yard's slide-whistle 'siren' over the last bar of a section: wee-ooo, wee-ooo."""
    b = "%d:" % bar
    return m.slide([(b + "0", 760.0), (b + "3", 1180.0), (b + "5", 1180.0), (b + "8", 760.0),
                    (b + "11", 1180.0), (b + "13", 1180.0), (b + "16", 700.0)], gain=0.14, pan=0.25, verb=0.3)


def hot_yard():
    """On the yard when the heat is up and no raid is on yet. E minor funk at
    116 bpm: clavinet, synth bass, open hats, trumpet stabs, a muted-trumpet
    line in B, and a slide-whistle 'siren' fill at the end of every 8 bars, so
    the yard sounds like it knows it's being watched. 48 bars (about 99 s)."""
    drum, bass, comp, melody = m.drum, m.bass, m.comp, m.melody
    a_chords = ["Em9", "Em9", "A9", "A9", "Em9", "Em9", "Cmaj7", "B7b9"]
    b_chords = ["Cmaj7", "B7b9", "Em9", "A9", "Cmaj7", "B7b9", "Em9", "F#m7b5 B7b9"]
    clav_a = "x.xx..x..x.x.x.."
    clav_b = "x..x..x.x..x..x."
    bass_a = "R-..R.8.R-.5.7.8"
    bass_b = "R-.R..5.R-.8.5.p"
    kick_a = "x..x..x...x..x.."
    snare_a = "....x..o.o..x..o"
    hat_a = "x.x.x...x.x.x..."
    hat_open = "......x.......x."
    line = ("B4:2 D5:2 E5:4 r:2 D5:1 E5:1 G5:4 | F#5:3 D#5:1 B4:4 r:4 A4:2 B4:2 | "
            "E5:2 G5:2 B5:4 A5:2 G5:2 E5:4 | F#5:2 E5:2 C#5:4 r:4 E5:2 F#5:2 | "
            "G5:4 E5:2 B4:2 r:2 E5:1 G5:1 B5:4 | A5:2 F#5:2 D#5:4 r:4 B4:4 | "
            "E5:6 G5:2 F#5:2 E5:2 D5:2 B4:2 | A4:4 C5:4 B4:4 r:4")

    def groove(clav, bass_pattern, crash=False):
        parts = [
            comp("clav", clav, center=64, gain=0.42, pan=-0.25, verb=0.1),
            bass("synth_bass", bass_pattern, low=28, gain=0.72),
            drum("kick_seam", kick_a, gain=0.62),
            drum("snare", snare_a, gain=0.42),
            drum("hat", hat_a, gain=0.2),
            drum("hat_open", hat_open, gain=0.14),
            comp("organ", "x---------------", center=60, gain=0.1, pan=0.3, verb=0.2),
        ]
        if crash:
            parts.append(drum("crash", "x...............", gain=0.16, only=[0]))
        return parts

    stabs = [
        comp("brass", "..............x.", center=69, gain=0.5, pan=0.15, only=[1, 3, 5]),
        comp("brass", "x.....x...x.....", center=69, gain=0.55, pan=0.15, only=[7]),
    ]
    sections = {
        "intro": m.Section(4, ["Em9", "Em9", "Em9", "B7b9"], [
            bass("synth_bass", bass_a, low=28, gain=0.72),
            comp("clav", clav_a, center=64, gain=0.42, pan=-0.25, only=[1, 2, 3]),
            drum("hat", "x.x.x.x.x.x.x.x.", gain=0.2),
            drum("kick_seam", kick_a, gain=0.62, only=[2, 3]),
            drum("snare", snare_a, gain=0.42, only=[2, 3]),
            drum("tom_hi", "............x.x.", gain=0.3, only=[3]),
            drum("tom_lo", ".............x.x", gain=0.35, only=[3]),
            comp("brass", "..............x.", center=69, gain=0.5, pan=0.15, only=[3]),
        ]),
        "A": m.Section(8, a_chords, groove(clav_a, bass_a) + stabs + [_siren()]),
        "B": m.Section(8, b_chords, groove(clav_b, bass_b, crash=True) + [
            melody("muted_trumpet", line, gain=0.5, pan=0.12, verb=0.22),
            comp("brass", "x.....x...x.....", center=69, gain=0.5, pan=0.15, only=[7]),
            _siren(),
        ]),
        "A2": m.Section(8, a_chords, groove(clav_a, bass_a) + stabs + [
            drum("cowbell", "..x...x...x...x.", gain=0.12, pan=-0.4),
            _siren(),
        ]),
        "breakdown": m.Section(8, ["Em9", "Em9", "Em9", "Em9", "A9", "A9", "Cmaj7", "B7b9"], [
            bass("synth_bass", bass_a, low=28, gain=0.78),
            drum("kick_seam", "x.....x...x.....", gain=0.75),
            drum("clap", "....x.......x...", gain=0.4),
            drum("hat", hat_a, gain=0.16, only=[2, 3, 4, 5, 6, 7]),
            comp("clav", clav_a, center=64, gain=0.4, pan=-0.25, only=[4, 5, 6, 7]),
            comp("brass", "x...............", center=69, gain=0.45, pan=0.15, only=[3]),
            _siren(),
        ]),
        "B2": m.Section(8, b_chords, groove(clav_b, bass_b, crash=True) + [
            melody("muted_trumpet", line, gain=0.48, pan=0.12, verb=0.22),
            melody("brass", line, shift=-12, gain=0.2, pan=-0.1, verb=0.15),
            comp("brass", "x.....x...x.....", center=69, gain=0.5, pan=0.15, only=[7]),
            _siren(),
        ]),
        "turn": m.Section(4, ["Em9", "A9", "Cmaj7", "B7b9"], groove(clav_a, bass_a)[:6] + [
            drum("tom_hi", "........x.x.....", gain=0.3, only=[3]),
            drum("tom_lo", "............x.x.", gain=0.35, only=[3]),
            comp("brass", "x.....x.....x...", center=69, gain=0.55, pan=0.15, only=[3]),
        ]),
    }
    return m.Song("hot_yard", "Hot Yard", 116.0, "E minor", 4401, sections,
                  ["intro", "A", "B", "A2", "breakdown", "B2", "turn"], loop_from="A", swing=0.08)


def nice_boys_incoming():
    """'Paperwork Incoming': the raid's 8-second warning. D minor at 128 bpm, a
    15 s loop with no intro: typewriter 16ths, rubber stamps on 1 and 3, a tuba
    ostinato and a brass line climbing a half step a bar. Every bar sits on D
    and the last on A7, so a cut into The NICE BOYS (also D minor) lands
    anywhere."""
    drum, bass, melody = m.drum, m.bass, m.melody
    climb = "D4:16, Eb4:16, E4:16 F4:16 F#4:16 G4:16! G#4:16! A4:16!"
    sections = {
        "A": m.Section(8, ["Dm", "Dm", "Dm7", "Dm7", "Bb/D", "Bb/D", "A7", "A7"], [
            drum("typewriter", "xoxoxoxoXoxoxoxo", gain=0.46, pan=0.3, verb=0.08),
            drum("type_bell", "..............x.", gain=0.22, pan=0.35, only=[3, 7]),
            drum("rubber_stamp", "x.......x.......", gain=0.75, pan=-0.05, verb=0.1),
            drum("kick_seam", "x.......x.......", gain=0.55),
            drum("snare", "....x.......x...", gain=0.28, only=[0, 1, 2, 3, 4, 5, 6]),
            drum("snare", "x.x.x.x.xxxxxxxx", gain=0.32, only=[7]),
            drum("hat", "..x...x...x...x.", gain=0.14),
            bass("tuba", "R-.RR-..5-.5R-..", low=33, gain=0.85),
            melody("brass", climb, gain=0.42, pan=0.12, verb=0.2),
            melody("brass", climb, shift=-12, gain=0.26, pan=-0.12, verb=0.15),
        ]),
    }
    return m.Song("nice_boys_incoming", "Paperwork Incoming", 128.0, "D minor", 4402, sections, ["A"], loop_from="A")


def nice_boys_chase():
    """'The NICE BOYS': the chase. A keystone-cop march at 152 bpm in D minor
    that runs off to F major for a brass tune: tuba oom-pah, a march snare,
    xylophone runs, brass stabs, police-whistle toots and rubber stamps, then a
    half-time 'hide!' section of tiptoeing pizzicato and clock ticks for
    diving into a pile. 64 bars (about 101 s)."""
    drum, bass, comp, melody, arp, hits = m.drum, m.bass, m.comp, m.melody, m.arp, m.hits
    a_chords = ["Dm", "Dm", "A7", "A7", "Dm", "Dm", "E7", "A7", "Dm", "Dm", "Gm", "Gm", "Dm", "A7", "Dm", "A7"]
    b_chords = ["F", "C7", "F", "C7", "Bb", "F", "G7", "C7"]
    run = ("D5:1 E5:1 F5:1 G5:1 A5:2 A5:2 Bb5:1 A5:1 G5:1 F5:1 E5:2 D5:2 | "
           "A5:2 r:2 A5:2 r:2 F5:1 G5:1 A5:1 Bb5:1 A5:4 | "
           "C#5:1 D5:1 E5:1 F5:1 G5:2 G5:2 A5:1 G5:1 F5:1 E5:1 C#5:2 A4:2 | "
           "E5:2 r:2 E5:2 r:2 C#5:1 D5:1 E5:1 G5:1 A5:4 | "
           "D5:1 E5:1 F5:1 G5:1 A5:2 A5:2 Bb5:1 A5:1 G5:1 F5:1 E5:2 D5:2 | "
           "F5:1 A5:1 D6:2 r:2 D6:1 C6:1 Bb5:1 A5:1 G5:1 F5:1 E5:1 D5:1 r:2 | "
           "E5:1 G#5:1 B5:1 D6:1 E6:2 r:2 D6:1 B5:1 G#5:1 E5:1 D5:4 | "
           "C#6:2 r:2 A5:2 r:2 E5:2 r:2 A4:4 | "
           "D5:1 E5:1 F5:1 G5:1 A5:2 A5:2 Bb5:1 A5:1 G5:1 F5:1 E5:2 D5:2 | "
           "A5:2 r:2 A5:2 r:2 F5:1 G5:1 A5:1 Bb5:1 A5:4 | "
           "G5:1 A5:1 Bb5:1 C6:1 D6:2 D6:2 C6:1 Bb5:1 A5:1 G5:1 A5:2 G5:2 | "
           "Bb5:2 r:2 Bb5:2 r:2 G5:1 A5:1 Bb5:1 C6:1 D6:4 | "
           "A5:1 G5:1 F5:1 E5:1 D5:2 F5:2 A5:2 D6:2 r:4 | "
           "C#6:1 B5:1 A5:1 G5:1 E5:2 G5:2 C#5:2 E5:2 r:4 | "
           "D6:2 r:2 A5:2 r:2 F5:2 r:2 D5:4 | "
           "E5:1 F5:1 G5:1 A5:1 Bb5:1 A5:1 G5:1 F5:1 E5:1 D5:1 C#5:1 B4:1 A4:4")
    tune = ("A4:2 C5:2 F5:4 E5:2 F5:2 G5:4 | A5:4 G5:2 E5:2 C5:4 r:4 | "
            "F5:2 A5:2 C6:4 A5:2 F5:2 C5:4 | Bb4:2 C5:2 E5:4 G5:4 r:4 | "
            "D5:2 F5:2 Bb5:4 A5:2 G5:2 F5:4 | C5:2 F5:2 A5:4 G5:2 F5:2 A5:4 | "
            "B4:2 D5:2 F5:4 G5:2 A5:2 B5:4 | C6:4 Bb5:2 G5:2 E5:4 C5:4")
    oom = "R.......5......."
    march = "....x.......x..."
    march_roll = "....x.......xoxo"

    def keystone(whistles=None):
        parts = [
            melody("xylo", run, gain=0.55, pan=0.2, verb=0.14),
            melody("marimba", run, shift=-12, gain=0.18, pan=-0.2, verb=0.12),
            bass("tuba", oom, low=33, gain=0.85),
            comp("brass", "....x.......x...", center=62, gain=0.26, pan=-0.15, verb=0.12),
            drum("kick_seam", "x.......x.......", gain=0.7),
            drum("snare", [march, march, march, march_roll], gain=0.42),
            drum("hat", "x.x.x.x.x.x.x.x.", gain=0.1),
            comp("brass", "x.......x.x.....", center=67, gain=0.5, pan=0.15, only=[3, 7, 11, 15]),
            drum("police_whistle", "........x...x...", gain=0.32, pan=0.35, verb=0.2, only=[7, 15]),
            drum("crash", "x...............", gain=0.16, only=[0]),
        ]
        if whistles:
            parts.append(drum("police_whistle", "x...x...........", gain=0.34, pan=-0.3, verb=0.2, only=whistles))
        return parts

    def brass_tune(extra):
        return [
            melody("brass", tune, gain=0.5, pan=0.1, verb=0.2),
            arp("xylo", "1.3.5.3.1.3.5.3.", low=72, gain=0.2, pan=-0.3),
            bass("tuba", oom, low=33, gain=0.85),
            comp("ep", "....x.......x...", center=62, gain=0.3, pan=-0.2),
            drum("kick_seam", "x.......x.......", gain=0.7),
            drum("snare", [march, march, march, march_roll], gain=0.42),
            drum("hat", "x.x.x.x.x.x.x.x.", gain=0.1),
            drum("crash", "x...............", gain=0.16, only=[0]),
        ] + extra

    sections = {
        "intro": m.Section(4, ["Dm", "Dm", "Dm", "A7"], [
            drum("rubber_stamp", "x.......x.......", gain=0.8, only=[0]),
            drum("police_whistle", "....x...x.......", gain=0.36, pan=0.3, verb=0.2, only=[0]),
            drum("snare", ["................", "....x.......x...", "....x...x.x.x.x.", "xoxoxoxoxxxxxxxx"], gain=0.42),
            bass("tuba", oom, low=33, gain=0.85, only=[1, 2, 3]),
            drum("kick_seam", "x.......x.......", gain=0.7, only=[1, 2, 3]),
            comp("brass", "............x...", center=67, gain=0.55, pan=0.15, only=[3]),
        ]),
        "A": m.Section(16, a_chords, keystone()),
        "B": m.Section(8, b_chords, brass_tune([])),
        "hide": m.Section(8, ["Dm", "Dm", "Bb", "A7", "Dm", "Dm", "Gm", "A7"], [
            arp("pizz", "1...2...3...2...", low=50, gain=0.6, pan=-0.15, verb=0.2),
            bass("tuba", "R-------........", low=33, gain=0.55),
            drum("woodblock", "x.......x.......", gain=0.3, pan=0.3),
            drum("typewriter", "....x.......x...", gain=0.2, pan=-0.3),
            drum("kick_seam", "x...............", gain=0.5),
            drum("snare", "x.x.x.x.xxxxxxxx", gain=0.38, only=[7]),
        ]),
        "A2": m.Section(16, a_chords, keystone(whistles=[0, 8]) + [
            hits("kazoo", [("15:12", "D3", 3, 1.0)], gain=0.4, pan=-0.2, verb=0.15),
        ]),
        "B2": m.Section(8, b_chords, brass_tune([melody("glock", tune, shift=12, gain=0.14, pan=0.3, verb=0.25)])),
        "turn": m.Section(4, ["Dm", "Gm", "E7", "A7"], [
            drum("rubber_stamp", "x...............", gain=0.75),
            drum("snare", ["x.x.x.x.x.x.x.x.", "x.x.x.x.x.x.x.x.", "x.x.x.x.x.x.x.x.", "xoxoxoxoxxxxxxxx"], gain=0.4),
            bass("tuba", "R.......R.......", low=33, gain=0.85),
            drum("kick_seam", "x.......x.......", gain=0.7),
            comp("brass", "....x.......x...", center=62, gain=0.26, pan=-0.15, only=[0, 1, 2]),
            comp("brass", "x...x...x-------", center=67, gain=0.55, pan=0.15, only=[3]),
            drum("type_bell", "............x...", gain=0.22, pan=0.35, only=[2]),
        ]),
    }
    return m.Song("nice_boys_chase", "The NICE BOYS", 152.0, "D minor / F major", 4403, sections,
                  ["intro", "A", "B", "hide", "A2", "B2", "turn"], loop_from="A")


def escape_run():
    """'Clean Getaway': the escape and end-sequence cue (Border Return's lanes
    today, the NICE BOYS' Field Office escape later). C major chiptune at 144
    bpm, an arcade bounce of pulse leads, triangle bass and chip noise drums,
    with office supplies in the bridge (typewriter, a rubber stamp, the
    carriage-return ding), so it fits a desk-to-desk escape as well as a road.
    40 bars (about 67 s)."""
    drum, bass, melody, arp, slide = m.drum, m.bass, m.melody, m.arp, m.slide
    a_chords = ["C", "Am", "F", "G", "C", "Am", "Dm7", "G7"]
    b_chords = ["F", "G", "Em7", "Am", "Dm7", "G7", "C", "C7"]
    lead_a = ("E5:2 G5:2 C6:2 G5:2 E5:2 G5:2 C6:4 | B5:2 A5:2 E5:2 C5:2 A4:4 r:4 | "
              "F5:2 A5:2 C6:2 A5:2 F5:2 A5:2 C6:4 | D6:2 B5:2 G5:2 D5:2 B4:4 r:4 | "
              "E5:1 F5:1 G5:2 E5:1 F5:1 G5:2 C6:2 B5:2 C6:4 | A5:2 G5:2 E5:2 G5:2 A5:4 C6:4 | "
              "D6:2 C6:2 A5:2 F5:2 D5:2 F5:2 A5:4 | G5:2 F5:2 D5:2 B4:2 G4:4 r:4")
    lead_b = ("C5:4 F5:4 A5:4 G5:2 F5:2 | D5:4 G5:4 B5:4 A5:2 G5:2 | E5:4 G5:4 B5:4 D6:4 | "
              "C6:6 B5:2 A5:8 | F5:2 E5:2 F5:2 A5:2 D6:4 C6:4 | B5:2 A5:2 B5:2 D6:2 G6:8 | "
              "E6:2 D6:2 C6:2 G5:2 E5:2 G5:2 C6:4 | Bb5:4 G5:4 E5:4 C5:4")
    office = ("A5:1 r:1 A5:1 r:1 C6:2 A5:2 G5:4 E5:4 | F5:1 r:1 F5:1 r:1 A5:2 F5:2 E5:4 C5:4 | "
              "E5:1 r:1 E5:1 r:1 G5:2 E5:2 D5:4 C5:4 | D5:2 G5:2 B5:2 D6:2 B5:4 r:4 | "
              "A5:1 r:1 A5:1 r:1 C6:2 A5:2 G5:4 E5:4 | F5:1 r:1 F5:1 r:1 A5:2 F5:2 E5:4 C5:4 | "
              "D5:1 r:1 F5:1 r:1 A5:2 C6:2 D6:4 F6:4 | G6:2 F6:2 D6:2 B5:2 G5:4 r:4")
    run_up = ("C5:1 D5:1 E5:1 F5:1 G5:1 A5:1 B5:1 C6:1 A5:4 F5:4 | D5:1 E5:1 F5:1 G5:1 A5:1 B5:1 C6:1 D6:1 B5:4 G5:4 | "
              "C6:2 A5:2 E5:2 A5:2 C6:2 A5:2 F5:4 | B4:2 D5:2 F5:2 G5:2 B5:2 D6:2 F6:2 G6:2")
    bounce = "R.8.R.8.R.8.5.8."
    kick = "x.....x...x....."
    snare = "....x.......x..."
    hat = "x.x.x.x.x.x.x.x."

    def chip(lead, extra):
        return [
            melody("pulse", lead, gain=0.42, pan=0.12, verb=0.12),
            arp("pulse", "1.3.5.6.5.3.1.3.", low=60, gain=0.16, pan=-0.35, verb=0.08),
            bass("triangle", bounce, low=36, gain=0.8),
            drum("chip_kick", kick, gain=0.75),
            drum("chip_snare", snare, gain=0.42),
            drum("chip_hat", hat, gain=0.16),
        ] + extra

    sections = {
        "intro": m.Section(4, ["C", "C", "F", "G7"], [
            arp("pulse", "1.2.3.6.3.2.1.2.", low=60, gain=0.36, pan=0.1, verb=0.1),
            bass("triangle", bounce, low=36, gain=0.8, only=[2, 3]),
            drum("chip_kick", kick, gain=0.75, only=[2, 3]),
            drum("chip_hat", hat, gain=0.16, only=[1, 2, 3]),
            drum("chip_snare", ["................", "................", snare, "x.x.x.x.xxxxxxxx"], gain=0.42),
        ]),
        "A": m.Section(8, a_chords, chip(lead_a, [])),
        "B": m.Section(8, b_chords, chip(lead_b, [
            slide([("7:8", 520.0), ("7:15", 1650.0)], gain=0.22, pan=-0.2, verb=0.25),
        ])),
        "A2": m.Section(8, a_chords, chip(lead_a, [
            melody("pulse", lead_a, shift=-12, gain=0.16, pan=-0.2, verb=0.1),
            drum("type_bell", "..............x.", gain=0.2, pan=0.35, only=[7]),
        ])),
        "bridge": m.Section(8, ["Am", "F", "C", "G", "Am", "F", "Dm7", "G7"], [
            melody("pulse", office, gain=0.4, pan=0.12, verb=0.12),
            bass("triangle", "R-..R-..5-..5-..", low=36, gain=0.6),
            drum("typewriter", "xoxoxoxoxoxoxoxo", gain=0.24, pan=0.3, verb=0.06),
            drum("rubber_stamp", "x...............", gain=0.6, only=[0, 4]),
            drum("type_bell", "............x...", gain=0.22, pan=0.35, only=[7]),
            drum("chip_kick", "x.......x.......", gain=0.7),
            drum("chip_snare", "....x.......x...", gain=0.36),
        ]),
        "out": m.Section(4, ["F", "G", "Am F", "G7"], [
            melody("pulse", run_up, gain=0.42, pan=0.12, verb=0.12),
            bass("triangle", bounce, low=36, gain=0.8),
            drum("chip_kick", "x.x.x.x.x.x.x.x.", gain=0.7),
            drum("chip_snare", ["....x.......x...", "....x.......x...", "....x...x...x.x.", "x.x.x.x.xxxxxxxx"], gain=0.42),
            drum("chip_hat", hat, gain=0.16),
        ]),
    }
    return m.Song("escape_run", "Clean Getaway", 144.0, "C major", 4404, sections,
                  ["intro", "A", "B", "A2", "bridge", "out"], loop_from="A")


# ---------------------------------------------------------------- the stingers

def _stinger(song_id, title, bpm, key, seed, chord, parts, tail):
    return m.Song(song_id, title, bpm, key, seed, {"S": m.Section(1, [chord], parts)}, ["S"],
                  loop_from=None, stinger=True, stinger_tail=tail)


def st_rank_up():
    """'Promoted!': the crew ranked up. A brass da-da-da-DAAA, a crash and a timpani hit, and a kazoo trill."""
    return _stinger("st_rank_up", "Promoted!", 100.0, "C major", 4501, "C", [
        m.melody("brass", "G4:1 C5:1 E5:1 G5:10! r:3", gain=0.6, pan=0.1, verb=0.25),
        m.comp("brass", "...x---------...", center=60, gain=0.4, pan=-0.15, verb=0.25),
        m.drum("snare", "xxx.............", gain=0.35),
        m.drum("crash", "...x............", gain=0.3),
        m.drum("tom_lo", "...x............", gain=0.55),
        m.melody("kazoo", "r:10 C6:1 D6:1 C6:1 D6:1 C6:1 E6:1!", gain=0.32, pan=-0.2, verb=0.2),
    ], 1.0)


def st_season():
    """'New Season': a chime run up to the top, a music-box echo, a warm chord under it."""
    return _stinger("st_season", "New Season", 96.0, "C major", 4502, "Cmaj9", [
        m.melody("vibes", "C5:1 E5:1 G5:1 B5:1 D6:1 E6:1 G6:1 B6:1 C7:8", gain=0.5, pan=0.15, verb=0.35),
        m.melody("music_box", "r:8 E6:2 G6:2 C7:4", gain=0.3, pan=-0.2, verb=0.35),
        m.comp("ep", "x---------------", center=62, gain=0.25, pan=-0.1, verb=0.3),
        m.comp("choir", "........x-------", center=60, gain=0.1, verb=0.4),
    ], 1.2)


def st_morning():
    """'Rise and Rake': the summary card closes. A kazoo rooster, a boing, a bright strum."""
    return _stinger("st_morning", "Rise and Rake", 110.0, "C major", 4503, "C69", [
        m.melody("kazoo", "G4:1 C5:1 E5:1 ~G5:5! ~D5:3 r:5", gain=0.55, pan=0.1, verb=0.2),
        m.hits("boing", [("0:12", "C5", 2, 0.9)], gain=0.5, pan=-0.15, verb=0.15),
        m.comp("nylon", "............x---", center=60, gain=0.4, pan=-0.25, verb=0.2),
        m.drum("shaker", "............x.x.", gain=0.2),
    ], 0.9)


def st_new_client():
    """'New Client': a referral, a lead or a client won back. The doorbell's ding-dong, then a marimba run."""
    return _stinger("st_new_client", "New Client", 100.0, "C major", 4504, "Cmaj9", [
        m.hits("bell", [("0:0", "E5", 4, 0.9), ("0:4", "C5", 8, 0.85)], gain=0.55, pan=0.1, verb=0.3),
        m.melody("marimba", "r:9 C5:1 D5:1 E5:1 G5:1 A5:1 C6:2!", gain=0.55, pan=-0.15, verb=0.18),
        m.comp("ep", ".........x------", center=62, gain=0.25, pan=0.2, verb=0.25),
    ], 0.96)


def st_job_paid():
    """'Paid': the payout receipt. Ka-ching, a happy horn bwaaap, and a sprinkle of coins."""
    coins = [("0:9", "C7", 1, 0.5), ("0:9.5", "G6", 1, 0.45), ("0:10", "E7", 1, 0.4), ("0:11", "C7", 1, 0.45),
             ("0:11.5", "G7", 1, 0.35), ("0:12.5", "E7", 1, 0.35), ("0:13.5", "C8", 1, 0.3)]
    return _stinger("st_job_paid", "Paid", 120.0, "C major", 4505, "C6", [
        m.drum("kaching", "x...............", gain=0.7, verb=0.15),
        m.melody("brass", "r:3 C4:1 ~G4:7! r:5", gain=0.55, pan=0.1, verb=0.2),
        m.melody("tuba", "r:3 C3:1 ~G3:7 r:5", gain=0.4, pan=-0.1, verb=0.1),
        m.hits("glock", coins, gain=0.3, pan=0.3, verb=0.3),
        m.comp("ep", "...x------------", center=64, gain=0.2, pan=-0.2, verb=0.25),
    ], 0.9)


def st_busted():
    """'Busted': the NICE BOYS' van takes you. A sad trombone wah-wah-wah-waaah, a tuba
    under the last one, and the rubber stamp that processes you."""
    return _stinger("st_busted", "Busted", 92.0, "G minor", 4506, "Gm", [
        m.melody("trombone", "Bb3:3 A3:3 Ab3:3 G3:7", gain=0.65, pan=0.05, verb=0.2),
        m.hits("tuba", [("0:9", "G2", 7, 0.6)], gain=0.4, pan=-0.1, verb=0.1),
        m.drum("rubber_stamp", "...............x", gain=0.6, pan=-0.1, verb=0.15),
    ], 1.1)


def st_made_it():
    """'Made It Back': you're out (Border Return's exit today, any escape later).
    A chip fanfare and a slide whistle all the way up."""
    return _stinger("st_made_it", "Made It Back", 132.0, "C major", 4507, "C", [
        m.melody("pulse", "C5:1 E5:1 G5:1 C6:1 r:1 G5:1 C6:6! r:4", gain=0.5, pan=0.1, verb=0.15),
        m.arp("pulse", "......1.3.5.6...", low=60, gain=0.2, pan=-0.3, verb=0.1),
        m.bass("triangle", "R.....R-----....", low=36, gain=0.8),
        m.drum("chip_kick", "x.....x.........", gain=0.7),
        m.drum("chip_snare", "x.x.x.x.........", gain=0.4),
        m.slide([("0:8", 520.0), ("0:14", 1760.0)], gain=0.3, pan=-0.15, verb=0.25),
    ], 0.8)


SONG_BUILDERS = (hot_yard, nice_boys_incoming, nice_boys_chase, escape_run,
                 st_rank_up, st_season, st_morning, st_new_client, st_job_paid, st_busted, st_made_it)


def register(module, songs: dict) -> None:
    """Add this book's instruments, drums and songs to make_music (module)."""
    global m
    m = module
    module.INSTRUMENTS.update(INSTRUMENTS)
    module.DRUMS.update(DRUMS)
    for name, placement in PLACEMENT.items():
        module.PLACEMENT.setdefault(name, placement)
    for builder in SONG_BUILDERS:
        song = builder()
        songs[song.id] = song
