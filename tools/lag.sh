#!/bin/bash
# Add or remove localhost latency for the ENet dev port.
# 75 ms each way is about 150 ms round trip, plus 2 percent packet loss.
set -euo pipefail

PORT="${PORT:-7777}"
ANCHOR="leafmealone"
PIPE="1"

usage() {
	echo "usage: tools/lag.sh on|off" >&2
	exit 1
}

turn_on() {
	sudo dnctl pipe "$PIPE" config delay 75ms plr 0.02
	sudo pfctl -a "$ANCHOR" -f - <<EOF
dummynet in proto udp from any to 127.0.0.1 port $PORT pipe $PIPE
dummynet out proto udp from 127.0.0.1 port $PORT to any pipe $PIPE
EOF
	sudo pfctl -E || true
	echo "lag on: 150ms round trip, 2% loss, udp port $PORT"
}

turn_off() {
	sudo pfctl -a "$ANCHOR" -F all || true
	sudo dnctl -q pipe delete "$PIPE" || true
	echo "lag off"
}

case "${1:-}" in
	on) turn_on ;;
	off) turn_off ;;
	*) usage ;;
esac
