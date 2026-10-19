#!/bin/bash
# Add or remove localhost latency for the ENet dev port (macOS dummynet).
# 75 ms each way is about 150 ms round trip, plus 2 percent loss per packet.
#
# The rules go into the main pf ruleset, not an anchor. An anchor only runs
# when /etc/pf.conf references it, and that file doesn't. "off" puts
# /etc/pf.conf back exactly as it was.
set -euo pipefail

PORT="${PORT:-7777}"
PIPE="1"
PF_CONF="/etc/pf.conf"

usage() {
	echo "usage: tools/lag.sh on|off" >&2
	exit 1
}

turn_on() {
	local rules
	rules="$(mktemp)"
	{
		cat "$PF_CONF"
		cat <<EOF
dummynet in proto udp from any to 127.0.0.1 port $PORT pipe $PIPE
dummynet out proto udp from 127.0.0.1 port $PORT to any pipe $PIPE
EOF
	} > "$rules"
	sudo dnctl pipe "$PIPE" config delay 75ms plr 0.02
	sudo pfctl -f "$rules"
	rm -f "$rules"
	sudo pfctl -E >/dev/null 2>&1 || true
	echo "lag on: 150ms round trip, 2% loss per packet, udp port $PORT"
}

turn_off() {
	sudo pfctl -f "$PF_CONF"
	sudo dnctl -q pipe delete "$PIPE" || true
	echo "lag off"
}

case "${1:-}" in
	on) turn_on ;;
	off) turn_off ;;
	*) usage ;;
esac
