#!/bin/bash
# Run a whole multiplayer session with bots and check it, no hands needed.
# One host and N-1 clients on this Mac, all driven by --bot and talking with the
# --voice-test tone, with a simulated bad connection. The last client joins late, as NETCODE.md asks. Every peer
# writes a report, and tools/soak_report.py decides pass, fail, or inconclusive.
#
#   tools/soak.sh                 8 players, 60 s, 150 ms, 2% loss, headless
#   tools/soak.sh -n 2 -s 30      2 players for 30 s
#   tools/soak.sh -w 2            first 2 peers get windows and take screenshots
#   tools/soak.sh -l 0 -p 0       perfect connection
#   tools/soak.sh -a              real macOS audio driver (muted), so voice
#                                 playback gaps are measured, not just delivery
#   tools/soak.sh -e 15           everyone starts on the lot and stays, and the
#                                 host starts a run event at 15 s: checks the
#                                 cues on every peer, then captures and returns
#   tools/soak.sh -V              no voice. The test tone is uncompressed, about
#                                 32 KB/s per speaker, so use -V to measure bandwidth
#
# Exit code: 0 pass, 1 fail, 2 inconclusive (machine too busy to judge).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
PYTHON="${PYTHON:-python3}"
PLAYERS=8
SECONDS_TO_RUN=60
LAG_MS=150
LOSS_PERCENT=2
WINDOWED=0
PORT=7791
OUT=""
VOICE=(--voice-test)
AUDIO=()
EVENT_AT=-1

while getopts "n:s:l:p:w:P:o:Vae:" option; do
	case "$option" in
		n) PLAYERS="$OPTARG" ;;
		s) SECONDS_TO_RUN="$OPTARG" ;;
		l) LAG_MS="$OPTARG" ;;
		p) LOSS_PERCENT="$OPTARG" ;;
		w) WINDOWED="$OPTARG" ;;
		P) PORT="$OPTARG" ;;
		o) OUT="$OPTARG" ;;
		V) VOICE=() ;;
		a) AUDIO=(--audio-driver CoreAudio) ;;
		e) EVENT_AT="$OPTARG" ;;
		*) sed -n '2,22p' "$0" >&2; exit 64 ;;
	esac
done

if [ -z "$OUT" ]; then
	OUT="$ROOT/build/soak/$(date +%Y%m%d-%H%M%S)"
fi
mkdir -p "$OUT/shots"

# The late joiner arrives a third of the way in. Everyone stops together,
# and the host stops last so clients never see "Host left" before reporting.
LATE_AT=$((SECONDS_TO_RUN / 3))
END_AT=$((SECONDS_TO_RUN + 5))
PIDS=()

launch() {
	local index="$1" role="$2" start_at="$3" name
	local display=(--headless)
	local extra=()
	if [ "$index" -eq 0 ]; then name="Host"; else name="Bot$index"; fi
	if [ "$index" -lt "$WINDOWED" ]; then
		# On top, because macOS stops drawing a covered window and nothing gets captured.
		display=(--always-on-top --resolution 640x360 --position "$((40 + index * 660)),80")
		extra=(--screenshot="$OUT/shots" --screenshot-every=5)
	fi
	local run_for=$((END_AT - start_at))
	if [ "$role" = "--host" ]; then run_for=$((END_AT + 5 - start_at)); fi
	local network=()
	if [ "$role" = "--host" ]; then network=(--host); else network=(--join=127.0.0.1); fi
	if [ "$EVENT_AT" != "-1" ]; then
		network+=(--bot-stay)
		if [ "$role" = "--host" ]; then network+=(--start-zone=lot --run-event-at="$EVENT_AT"); fi
	fi
	"$GODOT" "${display[@]}" ${AUDIO[@]+"${AUDIO[@]}"} --path "$ROOT" -- \
		"${network[@]}" --port="$PORT" --name="$name" --no-steam --bot --mute-audio \
		--sim-lag="$LAG_MS" --sim-loss="$LOSS_PERCENT" ${VOICE[@]+"${VOICE[@]}"} \
		--measure="$OUT/$name.json" --run-seconds="$run_for" \
		${extra[@]+"${extra[@]}"} > "$OUT/$name.log" 2>&1 &
	PIDS+=($!)
}

echo "soak: $PLAYERS players, ${SECONDS_TO_RUN}s, ${LAG_MS}ms, ${LOSS_PERCENT}% loss -> $OUT"
launch 0 --host 0
sleep 3
elapsed=3
for ((index = 1; index < PLAYERS; index++)); do
	if [ "$index" -eq $((PLAYERS - 1)) ] && [ "$PLAYERS" -gt 2 ]; then
		sleep $((LATE_AT > elapsed ? LATE_AT - elapsed : 0))
		elapsed=$((LATE_AT > elapsed ? LATE_AT : elapsed))
	fi
	launch "$index" --join "$elapsed"
	sleep 1
	elapsed=$((elapsed + 1))
done

for pid in "${PIDS[@]}"; do
	wait "$pid" || true
done

"$PYTHON" "$ROOT/tools/soak_report.py" "$OUT" "$PLAYERS" "$LAG_MS" "$LOSS_PERCENT" "$EVENT_AT"
