#!/usr/bin/env python3
"""Read the reports from a tools/soak.sh run and decide pass, fail, or inconclusive.

Usage: soak_report.py <run dir> <players> <simulated lag ms> [simulated loss percent]
Writes summary.json in the run dir. Exit code 0 pass, 1 fail, 2 inconclusive.

The hitch rate decides pass or fail. The max gap column is for reading only: a
bot pinned against a fence also stops sending new positions and shows up there.

Hitches and lost voice packets are judged on the network's share only. Every peer
logs its stalls (frames over 50 ms, loading included) in host time, each hitch with
when it ended, and each run of lost voice packets with the send times either side
(net/dev/probe.gd). One that lines up with a stall on its way (for a hitch the
mover, the host relaying, or the receiver; for voice the peer it was due at or the
host relaying it) is the machine's, not the network's: a peer that isn't reading
lets its socket's receive buffer overflow, and a peer that isn't running sends no
updates. Those are counted and printed apart (+stall, v loss). A busy machine's
stalls also land near the network's own problems by chance, so each peer's odds of
that are measured and the network's share is scaled back up by them (h odds, v
odds); a check that fails with odds over half is inconclusive. A peer whose ENet
throttle limit ever fell fails. A peer that exits non-zero fails, even
after writing its report. docs/DECISIONS.md, 2026-11-03 "The bot soaks' flakes",
has the measurements.
"""
import json
import pathlib
import sys

# A remote player may hitch on at most this share of position updates.
MAX_HITCH_RATE = 0.02
# A stall this long or longer on the way can explain a hitch (an update gap over
# NetSmoother's 100 ms delay needs only a 50 ms frame on top of the 33 ms sync).
HITCH_STALL_SECONDS = 0.05
# A stall this long or longer can explain lost voice packets. A bare ENet socket
# lost 0 of 273 packets to 400 ms stalls at 150 KB/s (more than the soak's busiest
# peer receives) and 50 of 273 to an 800 ms one (DECISIONS.md), so only a stall
# past the longest that measured clean excuses anything.
VOICE_STALL_SECONDS = 0.4
# Slack around a stall for frame timing, in seconds.
STALL_SLACK_SECONDS = 0.1
# On a busy machine a stall lands near many of the network's own hitches and lost
# packets too, and the stall rule excuses them by chance (a 50 ms frame on any of
# three peers inside a 0.4 s window). So each peer's odds of that are measured
# by putting a made-up problem at EXCUSE_SAMPLES moments spread over its session,
# and the network's share is scaled back up by them: judged / (1 - odds). Odds
# over MAX_EXCUSE_ODDS leave too little unexcused to scale from, so a check that
# fails then is inconclusive instead.
EXCUSE_SAMPLES = 2000
MAX_EXCUSE_ODDS = 0.5
# The made-up problems' size: a hitch's update gap (the median in the 2026-11-03
# soaks was 0.11-0.13 s, just over NetSmoother's 100 ms delay), and the send times
# either side of a run of lost voice packets (median 0.04-0.046 s, one lost packet).
TYPICAL_HITCH_GAP_SECONDS = 0.12
TYPICAL_VOICE_GAP_SECONDS = 0.04
# Long frames per peer per minute above which the round trip, voice latency and
# playback, and run-event cue checks can't be blamed on the network.
BUSY_LONG_FRAMES_PER_MINUTE = 20
# ENet's throttle should stay full. 32 is ENetPacketPeer.PACKET_THROTTLE_SCALE.
FULL_THROTTLE = 32
# Measured round trip may exceed the simulated one by this much (frame and poll delay).
RTT_SLACK_MS = 60
# Voice packet loss allowed on top of what the simulated loss explains.
VOICE_LOSS_SLACK = 0.01
# Sender-to-receiver voice delay allowed beyond the simulated round trip, which
# covers the two half-trips through the host. Excludes the playback buffer.
VOICE_LATENCY_SLACK_MS = 100
# Playback gaps allowed beyond lost packets, each of which leaves a gap.
VOICE_UNDERRUN_SLACK = 0.02
# How late a run event cue may show beyond the network delay, in milliseconds.
CUE_SLACK_MS = 100
# Annex B (R2 chunk 6): a caught bot that reached it this long before the run ended
# must be home again (the soak's day, ANNEX_CAP_SECONDS_SOAK 50, plus closing's way out
# and the trip home, with slack), and this share of visits must end before closing.
ANNEX_DAY_SECONDS = 80
ANNEX_BEFORE_CLOSING_SHARE = 0.8


def main() -> int:
    run_dir = pathlib.Path(sys.argv[1])
    players = int(sys.argv[2])
    lag_ms = int(sys.argv[3])
    loss_percent = float(sys.argv[4]) if len(sys.argv) > 4 else 2.0
    event_at = float(sys.argv[5]) if len(sys.argv) > 5 else -1.0
    failures: list[str] = []
    busy: list[str] = []
    warnings: list[str] = []
    rows = []

    reports = {}
    for path in sorted(run_dir.glob("*.json")):
        if path.name == "summary.json":
            continue
        reports[path.stem] = json.loads(path.read_text())
    expected = ["Host"] + [f"Bot{i}" for i in range(1, players)]
    for name in expected:
        if name not in reports:
            failures.append(f"{name}: no report (crashed, never joined, or never finished)")
    # tools/soak.sh writes each Godot's exit status. A crash after the report was
    # written (on the way out) still fails: players quit too. 139 is bash's SIGSEGV,
    # what an access violation (0xC0000005) looks like through Git Bash.
    exit_path = run_dir / "exit_codes.txt"
    if exit_path.exists():
        for line in exit_path.read_text().split("\n"):
            parts = line.split()
            if len(parts) == 2 and parts[1] != "0":
                when = "while quitting, after its report" if parts[0] in reports else "before its report"
                failures.append(f"{parts[0]}: exited with status {parts[1]} {when}")

    for name in expected:
        log_path = run_dir / f"{name}.log"
        if not log_path.exists():
            continue
        errors = [line.strip() for line in log_path.read_text(errors="replace").splitlines()
                  if line.startswith("ERROR:") or line.startswith("SCRIPT ERROR:")]
        # A leak reported as the process quits doesn't affect play. Note it, don't fail on it.
        at_exit = [line for line in errors if "still in use at exit" in line]
        errors = [line for line in errors if line not in at_exit]
        if errors:
            failures.append(f"{name}: {len(errors)} engine errors, first: {errors[0]}")
        if at_exit:
            warnings.append(f"{name}: {at_exit[0]}")

    def long_frames_per_minute(report: dict) -> float:
        return report["long_frames"] / (max(report["session_seconds"], 1.0) / 60.0)

    host_busy = "Host" in reports and long_frames_per_minute(reports["Host"]) > BUSY_LONG_FRAMES_PER_MINUTE

    # Peer id -> name, and each peer's stalls in host time.
    names = {int(report["peer_id"]): name for name, report in reports.items()}
    stalls = {name: report.get("stalls", []) for name, report in reports.items()}
    one_way = lag_ms / 2000.0

    def stalled(name: str, start: float, end: float, shortest: float) -> bool:
        """True if the peer had a stall at least `shortest` long overlapping [start, end]."""
        return any(s_end - s_start >= shortest and s_start < end and s_end > start
                   for s_start, s_end in stalls.get(name, []))

    def voice_gap_stalled(receiver: str, sent_from: float, sent_to: float, sender: str) -> bool:
        # The lost packets left the sender between sent_from and sent_to (host time).
        # They were due at the host one hop later and at a client two hops later
        # (one, from the host). If the peer they were due at wasn't reading for a
        # while then, its socket's buffer overflowed.
        relayed = receiver != "Host" and sender != "Host"
        hops = 2 if relayed else 1
        due_from = sent_from + hops * one_way - STALL_SLACK_SECONDS
        due_to = sent_to + hops * one_way + STALL_SLACK_SECONDS
        if stalled(receiver, due_from, due_to, VOICE_STALL_SECONDS):
            return True
        return relayed and stalled("Host", due_from - one_way, due_to - one_way, VOICE_STALL_SECONDS)

    def hitch_stalled(receiver: str, at: float, gap: float, mover: str) -> bool:
        # The receiver's own long frame, or no updates from a mover (or the host
        # relaying them) that wasn't running a hop or two before.
        if stalled(receiver, at - gap, at, HITCH_STALL_SECONDS):
            return True
        early = at - gap - 2 * one_way - STALL_SLACK_SECONDS
        return any(stalled(peer, early, at, HITCH_STALL_SECONDS) for peer in {mover, "Host"} if peer != receiver)

    def excuse_odds(name: str, excused) -> float:
        """How likely the stall rule is to excuse a problem that has nothing to do with
        a stall: the share of EXCUSE_SAMPLES evenly spread moments in this peer's
        session that `excused(at, other)` lets off, the other peer taking turns."""
        report = reports[name]
        since = float(report.get("session_started_at", -1.0))
        session = float(report["session_seconds"])
        others = [other for other in expected if other != name and other in reports]
        if since < 0 or not others:
            return 0.0
        hits = sum(1 for i in range(EXCUSE_SAMPLES)
                   if excused(since + session * (i + 0.5) / EXCUSE_SAMPLES, others[i % len(others)]))
        return hits / EXCUSE_SAMPLES

    def percent(value: float) -> str:
        """A share for printing; ? when the stalls left nothing to judge from."""
        return "?" if value == float("inf") else f"{value:.1%}"

    def network_estimate(judged: float, odds: float) -> float:
        """The network's share, allowing for the network's own problems the stall rule
        excused by chance: on a busy machine a stall lands near many of them."""
        if judged <= 0.0:
            return 0.0
        return judged / (1.0 - odds) if odds < 1.0 else float("inf")

    for name, report in reports.items():
        minutes = max(report["session_seconds"], 1.0) / 60.0
        smoother = report["smoother"]
        samples = max(int(smoother["samples"]), 1)
        hitch_log = smoother.get("hitch_log", [])
        stall_hitches = sum(1 for at, gap, mover in hitch_log
                            if hitch_stalled(name, at, gap, names.get(int(mover), "?")))
        hitch_odds = excuse_odds(name, lambda at, mover: hitch_stalled(name, at, TYPICAL_HITCH_GAP_SECONDS, mover))
        hitch_rate = network_estimate((int(smoother["hitches"]) - stall_hitches) / samples, hitch_odds)
        report["_stall_hitches"] = stall_hitches
        report["_hitch_odds"] = hitch_odds
        long_per_minute = report["long_frames"] / minutes
        rows.append((name, report, hitch_rate, long_per_minute))
        if report["state"] != "IN_SESSION":
            failures.append(f"{name}: ended in state {report['state']}")
        if report["players_seen_max"] < players:
            failures.append(f"{name}: saw at most {report['players_seen_max']} of {players} players")
        throttle = report["enet_throttle_min"]
        if 0 <= throttle < FULL_THROTTLE:
            failures.append(f"{name}: ENet throttle fell to {throttle} of {FULL_THROTTLE}, so movement was dropped")
        # The limit caps the throttle. Net.host()'s bandwidth_limit(0, 0) keeps it full;
        # without that call it fell to 1-5 of 32 a second after each client joined.
        limit = int(report.get("enet_throttle_limit_min", -1))
        if 0 <= limit < FULL_THROTTLE:
            failures.append(f"{name}: ENet throttle limit fell to {limit} of {FULL_THROTTLE}, "
                            f"so its unreliable traffic (movement, voice) was dropped")
        if not report["is_host"] and lag_ms > 0 and report["rtt_ms_median"] >= 0:
            if not lag_ms * 0.8 <= report["rtt_ms_median"] <= lag_ms + RTT_SLACK_MS:
                message = f"{name}: round trip {report['rtt_ms_median']:.0f} ms, expected about {lag_ms} ms"
                # Slow frames on either end delay the clock ping and pong too.
                if long_per_minute > BUSY_LONG_FRAMES_PER_MINUTE or host_busy:
                    busy.append(f"{message}, but frames were slow on this peer or the host")
                else:
                    failures.append(message)
        voice = report.get("voice") or {}
        if voice:
            peer_busy = long_per_minute > BUSY_LONG_FRAMES_PER_MINUTE or host_busy
            if voice["heard_from"] < players - 1:
                failures.append(f"{name}: heard voice from {voice['heard_from']} of {players - 1} other players")
            if voice["decode_failures"] > 0:
                failures.append(f"{name}: {voice['decode_failures']} voice packets failed to decode")
            # Voice from another client crosses two lossy hops through the host.
            loss_limit = 2.5 * loss_percent / 100.0 + VOICE_LOSS_SLACK
            # Runs of packets lost while this peer or the host wasn't reading are the
            # machine's (the soak's late joiner loses one while it loads the yard).
            stall_lost = sum(int(missing) for sent_from, sent_to, sender, missing in voice.get("gap_log", [])
                             if voice_gap_stalled(name, sent_from, sent_to, names.get(int(sender), "?")))
            lost = int(voice["lost_packets"])
            voice_odds = excuse_odds(name, lambda at, sender: voice_gap_stalled(
                name, at - TYPICAL_VOICE_GAP_SECONDS, at, sender))
            net_lost = min(network_estimate(lost - stall_lost, voice_odds), lost)
            net_rate = net_lost / max(int(voice["received_packets"]) + net_lost, 1)
            voice["net_loss_rate"] = net_rate
            voice["stall_lost"] = stall_lost
            voice["excuse_odds"] = voice_odds
            if net_rate > loss_limit:
                message = (f"{name}: lost {net_rate:.1%} of voice packets to the network (limit {loss_limit:.1%}; "
                           f"{lost} lost, {stall_lost} of them while it or the host stalled)")
                if voice_odds > MAX_EXCUSE_ODDS:
                    busy.append(f"{message}, but a stall lined up with {voice_odds:.0%} of moments, too many to tell")
                else:
                    failures.append(message)
            # The Dummy driver used by headless runs doesn't play in real time,
            # so playback gaps only mean something with a real driver (-a).
            if report.get("audio_driver", "Dummy") != "Dummy":
                underrun_rate = voice["underruns"] / max(voice["received_packets"], 1)
                underrun_limit = loss_limit + VOICE_UNDERRUN_SLACK
                if underrun_rate > underrun_limit:
                    message = f"{name}: voice playback ran dry on {underrun_rate:.1%} of packets (limit {underrun_limit:.1%})"
                    (busy if peer_busy else failures).append(message)
            latency = voice["latency_ms_median"]
            if latency >= 0 and latency > lag_ms + VOICE_LATENCY_SLACK_MS:
                message = f"{name}: voice arrived {latency:.0f} ms after it was sent (limit {lag_ms + VOICE_LATENCY_SLACK_MS} ms)"
                (busy if peer_busy else failures).append(message)
        if event_at >= 0:
            cues = report.get("run_cues", [])
            seen = {cue["phase"] for cue in cues}
            for phase, label in ((1, "warning"), (2, "arrival")):
                if phase not in seen:
                    failures.append(f"{name}: never showed the run event {label} cue")
            late = max((cue["late_ms"] for cue in cues), default=0.0)
            # The phase change is one reliable message from the host, which a loss can delay by a resend.
            late_limit = lag_ms * 1.5 + CUE_SLACK_MS
            if late > late_limit:
                message = f"{name}: a run event cue showed {late:.0f} ms late (limit {late_limit:.0f} ms)"
                (busy if long_per_minute > BUSY_LONG_FRAMES_PER_MINUTE or host_busy else failures).append(message)
        if hitch_rate > MAX_HITCH_RATE:
            message = (f"{name}: remote players hitched on {percent(hitch_rate)} of updates over the network "
                       f"(limit {MAX_HITCH_RATE:.0%}; {report['_stall_hitches']} more came with a stall)")
            if hitch_odds > MAX_EXCUSE_ODDS:
                busy.append(f"{message}, but a stall lined up with {hitch_odds:.0%} of moments, too many to tell")
            else:
                failures.append(message)

    print()
    # hitch and v net are the network's share, which the checks judge, scaled up by
    # the odds (h odds, v odds) that a stall excused one of the network's by chance;
    # +stall and v loss add what came with a stall, and stall s is time in frames over 50 ms.
    print(f"{'peer':<6} {'rtt ms':>7} {'KB/s in':>8} {'KB/s out':>9} {'hitch':>6} {'+stall':>6} {'h odds':>6} {'max gap':>8} "
          f"{'snaps':>5} {'long/min':>8} {'stall s':>7} {'fps':>4} {'voice ms':>8} {'v net':>6} {'v loss':>6} "
          f"{'v odds':>6} {'heard':>5}")
    for name, report, hitch_rate, long_per_minute in sorted(rows, key=lambda row: (not row[1]["is_host"], row[0])):
        rtt = report["rtt_ms_median"]
        voice = report.get("voice") or {}
        voice_cells = (f"{voice['latency_ms_median']:>8.0f} {voice.get('net_loss_rate', voice['loss_rate']):>6.1%} "
                       f"{voice['loss_rate']:>6.1%} {voice.get('excuse_odds', 0.0):>6.0%} {voice['heard_from']:>5}"
                       if voice else f"{'-':>8} {'-':>6} {'-':>6} {'-':>6} {'-':>5}")
        since = float(report.get("session_started_at", -1.0))
        stall_seconds = sum(end - start for start, end in stalls.get(name, []) if since >= 0 and end > since)
        stall_hitch_rate = report["_stall_hitches"] / max(int(report["smoother"]["samples"]), 1)
        print(f"{name:<6} {rtt if rtt >= 0 else 0:>7.0f} {report['bytes_in_per_second'] / 1024:>8.1f} "
              f"{report['bytes_out_per_second'] / 1024:>9.1f} {percent(hitch_rate):>6} {stall_hitch_rate:>6.1%} "
              f"{report['_hitch_odds']:>6.0%} {report['smoother']['max_gap_ms']:>6.0f}ms {report['smoother']['snaps']:>5} "
              f"{long_per_minute:>8.0f} {stall_seconds:>7.1f} {report['fps_median']:>4.0f} {voice_cells}")
    print()

    annex_line = ""
    if event_at >= 0:
        captured = [name for name, report in reports.items() if "BORDER" in report.get("zones", [])]
        returned = [name for name, report in reports.items()
                    if "BORDER" in report.get("zones", [])
                    and any(zone in ("LOT", "STORE", "TOWN") for zone in report["zones"][report["zones"].index("BORDER"):])]
        hides = reports.get("Host", {}).get("hide_spots", {})
        visits = reports.get("Host", {}).get("annex", {}).get("stats", {}).get("visits", [])
        before_closing = [visit for visit in visits if not visit.get("closing")]
        annex_line = (f"run event: {len(captured)} captured, {len(returned)} back from Annex B "
              f"({len(before_closing)} of {len(visits)} out before closing), "
              f"{hides.get('entered', 0)} hid, {hides.get('pulled_out', 0)} pulled out of hiding")
    # Annex B (R2 chunk 6): every caught bot gets home, unless the run ended before
    # the Annex could have let it out; most do their paperwork before closing.
    if event_at >= 0:
        for name in captured:
            if name in returned:
                continue
            report = reports[name]
            first = float(report.get("annex", {}).get("first_at_s", -1.0))
            if first >= 0 and report["session_seconds"] - first > ANNEX_DAY_SECONDS:
                failures.append(f"{name}: went to Annex B {report['session_seconds'] - first:.0f} s before the end and never came back")
        if visits and len(before_closing) / len(visits) < ANNEX_BEFORE_CLOSING_SHARE:
            failures.append(f"only {len(before_closing)} of {len(visits)} caught bots finished their paperwork before closing "
                            f"(at least {ANNEX_BEFORE_CLOSING_SHARE:.0%})")
    if failures:
        verdict, code = "FAIL", 1
    elif busy:
        verdict, code = "INCONCLUSIVE", 2
    else:
        verdict, code = "PASS", 0
    for line in failures:
        print(f"  fail: {line}")
    for line in busy:
        print(f"  busy: {line}")
    for line in warnings:
        print(f"  note: {line}")
    if annex_line:
        print(annex_line)
    # Bots work the job on the lot (net/dev/bot_job.gd). Informational, not a pass/fail check.
    work = reports.get("Host", {}).get("lot_work")
    if work:
        print(f"lot work: {work['truck_bags']} bags worth ${work['truck_value']} in Chefty, "
              f"{work['loose_bags']} lying around, {work['cleaned_fraction'] * 100:.0f}% clean")
    shots = sorted((run_dir / "shots").glob("*.png")) if (run_dir / "shots").exists() else []
    print(f"soak {verdict}: {len(reports)} reports, {len(shots)} screenshots in {run_dir}")

    (run_dir / "summary.json").write_text(json.dumps({
        "verdict": verdict,
        "players": players,
        "simulated_lag_ms": lag_ms,
        "failures": failures,
        "busy": busy,
        "warnings": warnings,
        "screenshots": [shot.name for shot in shots],
    }, indent=2))
    return code


if __name__ == "__main__":
    sys.exit(main())
