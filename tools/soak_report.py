#!/usr/bin/env python3
"""Read the reports from a tools/soak.sh run and decide pass, fail, or inconclusive.

Usage: soak_report.py <run dir> <players> <simulated lag ms>
Writes summary.json in the run dir. Exit code 0 pass, 1 fail, 2 inconclusive.

The hitch rate decides pass or fail. The max gap column is for reading only: a
bot pinned against a fence also stops sending new positions and shows up there.
"""
import json
import pathlib
import sys

# A remote player may hitch on at most this share of position updates.
MAX_HITCH_RATE = 0.02
# Long frames per peer per minute above which hitches can't be blamed on the network.
BUSY_LONG_FRAMES_PER_MINUTE = 20
# ENet's throttle should stay full. 32 is ENetPacketPeer.PACKET_THROTTLE_SCALE.
FULL_THROTTLE = 32
# Measured round trip may exceed the simulated one by this much (frame and poll delay).
RTT_SLACK_MS = 60


def main() -> int:
    run_dir = pathlib.Path(sys.argv[1])
    players = int(sys.argv[2])
    lag_ms = int(sys.argv[3])
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

    for name, report in reports.items():
        minutes = max(report["session_seconds"], 1.0) / 60.0
        smoother = report["smoother"]
        samples = max(int(smoother["samples"]), 1)
        hitch_rate = int(smoother["hitches"]) / samples
        long_per_minute = report["long_frames"] / minutes
        rows.append((name, report, hitch_rate, long_per_minute))
        if report["state"] != "IN_SESSION":
            failures.append(f"{name}: ended in state {report['state']}")
        if report["players_seen_max"] < players:
            failures.append(f"{name}: saw at most {report['players_seen_max']} of {players} players")
        throttle = report["enet_throttle_min"]
        if 0 <= throttle < FULL_THROTTLE:
            failures.append(f"{name}: ENet throttle fell to {throttle} of {FULL_THROTTLE}, so movement was dropped")
        if not report["is_host"] and lag_ms > 0 and report["rtt_ms_median"] >= 0:
            if not lag_ms * 0.8 <= report["rtt_ms_median"] <= lag_ms + RTT_SLACK_MS:
                message = f"{name}: round trip {report['rtt_ms_median']:.0f} ms, expected about {lag_ms} ms"
                # Slow frames on either end delay the clock ping and pong too.
                if long_per_minute > BUSY_LONG_FRAMES_PER_MINUTE or host_busy:
                    busy.append(f"{message}, but frames were slow on this peer or the host")
                else:
                    failures.append(message)
        if hitch_rate > MAX_HITCH_RATE:
            message = f"{name}: remote players hitched on {hitch_rate:.1%} of updates (limit {MAX_HITCH_RATE:.0%})"
            if long_per_minute > BUSY_LONG_FRAMES_PER_MINUTE:
                busy.append(f"{message}, but this peer had {long_per_minute:.0f} long frames a minute")
            else:
                failures.append(message)

    print()
    print(f"{'peer':<6} {'rtt ms':>7} {'KB/s in':>8} {'KB/s out':>9} {'hitch':>6} {'max gap':>8} {'snaps':>5} {'long/min':>8} {'fps':>4}")
    for name, report, hitch_rate, long_per_minute in sorted(rows, key=lambda row: (not row[1]["is_host"], row[0])):
        rtt = report["rtt_ms_median"]
        print(f"{name:<6} {rtt if rtt >= 0 else 0:>7.0f} {report['bytes_in_per_second'] / 1024:>8.1f} "
              f"{report['bytes_out_per_second'] / 1024:>9.1f} {hitch_rate:>6.1%} "
              f"{report['smoother']['max_gap_ms']:>6.0f}ms {report['smoother']['snaps']:>5} "
              f"{long_per_minute:>8.0f} {report['fps_median']:>4.0f}")
    print()

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
