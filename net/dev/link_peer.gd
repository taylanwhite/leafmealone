extends MultiplayerPeerExtension

## Authority: local. Wraps the real transport peer for development builds.
## Counts bytes in both directions, and can simulate a bad connection on
## incoming packets: half the round trip as delay on each peer, plus loss.
## Unreliable packets are dropped. Reliable packets cannot be dropped without
## breaking the transport's promise, so a "lost" one arrives one extra round
## trip late and holds back the packets behind it on that channel, which is
## what a real resend does.

var inner: MultiplayerPeer
var one_way_seconds: float = 0.0
var loss: float = 0.0
var bytes_in: int = 0
var bytes_out: int = 0
var packets_dropped: int = 0

var _pending: Array[Dictionary] = []
var _ready_packets: Array[Dictionary] = []
var _channel_release: Dictionary = {}
var _events: Array[Dictionary] = []
## Peers the inner peer has dropped. Peer ids are not reused within a session.
var _gone: Dictionary = {}
var _target: int = 0
var _rng := RandomNumberGenerator.new()


func _init(wrapped: MultiplayerPeer, round_trip_ms: int, loss_fraction: float) -> void:
	inner = wrapped
	one_way_seconds = maxf(0.0, float(round_trip_ms) / 2000.0)
	loss = clampf(loss_fraction, 0.0, 1.0)
	_rng.randomize()
	inner.peer_connected.connect(_on_inner_connected)
	inner.peer_disconnected.connect(_on_inner_disconnected)


func _poll() -> void:
	inner.poll()
	# Pass on connection changes only after the inner peer has finished its poll.
	# Re-emitting from inside it let game code broadcast to a half-removed peer.
	var events := _events.duplicate()
	_events.clear()
	for event: Dictionary in events:
		if bool(event["connected"]):
			peer_connected.emit(int(event["peer"]))
		else:
			peer_disconnected.emit(int(event["peer"]))
	var now := _now()
	while inner.get_available_packet_count() > 0:
		var from_peer := inner.get_packet_peer()
		var channel := inner.get_packet_channel()
		var mode := inner.get_packet_mode()
		var data := inner.get_packet()
		bytes_in += data.size()
		var release := now + one_way_seconds
		if mode == TRANSFER_MODE_RELIABLE:
			if loss > 0.0 and _rng.randf() < loss:
				release += one_way_seconds * 2.0
			var key := "%d:%d" % [from_peer, channel]
			release = maxf(release, float(_channel_release.get(key, 0.0)))
			_channel_release[key] = release
		elif loss > 0.0 and _rng.randf() < loss:
			packets_dropped += 1
			continue
		_pending.append({"peer": from_peer, "channel": channel, "mode": mode, "data": data, "at": release})
	var index := 0
	while index < _pending.size():
		if float(_pending[index]["at"]) <= now:
			_ready_packets.append(_pending[index])
			_pending.remove_at(index)
		else:
			index += 1


func _get_available_packet_count() -> int:
	return _ready_packets.size()


func _get_packet_script() -> PackedByteArray:
	if _ready_packets.is_empty():
		return PackedByteArray()
	var packet: Dictionary = _ready_packets.pop_front()
	return packet["data"]


func _put_packet_script(buffer: PackedByteArray) -> Error:
	# Several peers can drop in one inner poll. While the game handles the first,
	# the others are gone from the inner peer but not yet announced, so skip them.
	if _gone.has(_target):
		return OK
	bytes_out += buffer.size()
	return inner.put_packet(buffer)


func _get_packet_peer() -> int:
	return 0 if _ready_packets.is_empty() else int(_ready_packets[0]["peer"])


func _get_packet_channel() -> int:
	return 0 if _ready_packets.is_empty() else int(_ready_packets[0]["channel"])


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	if _ready_packets.is_empty():
		return TRANSFER_MODE_RELIABLE
	return _ready_packets[0]["mode"] as MultiplayerPeer.TransferMode


func _get_max_packet_size() -> int:
	return 1 << 24


func _set_transfer_channel(channel: int) -> void:
	inner.transfer_channel = channel


func _get_transfer_channel() -> int:
	return inner.transfer_channel


func _set_transfer_mode(mode: MultiplayerPeer.TransferMode) -> void:
	inner.transfer_mode = mode


func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return inner.transfer_mode


func _set_target_peer(peer: int) -> void:
	_target = peer
	inner.set_target_peer(peer)


func _get_unique_id() -> int:
	return inner.get_unique_id()


func _is_server() -> bool:
	return inner.get_unique_id() == 1


func _is_server_relay_supported() -> bool:
	return inner.is_server_relay_supported()


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return inner.get_connection_status()


func _set_refuse_new_connections(enable: bool) -> void:
	inner.refuse_new_connections = enable


func _is_refusing_new_connections() -> bool:
	return inner.refuse_new_connections


func _disconnect_peer(peer: int, force: bool) -> void:
	inner.disconnect_peer(peer, force)


func _close() -> void:
	# The inner peer's signals hold this wrapper, so drop them or neither is freed.
	if inner.peer_connected.is_connected(_on_inner_connected):
		inner.peer_connected.disconnect(_on_inner_connected)
	if inner.peer_disconnected.is_connected(_on_inner_disconnected):
		inner.peer_disconnected.disconnect(_on_inner_disconnected)
	inner.close()
	_pending.clear()
	_ready_packets.clear()


func _on_inner_connected(peer_id: int) -> void:
	_events.append({"peer": peer_id, "connected": true})


func _on_inner_disconnected(peer_id: int) -> void:
	var from_other := func(packet: Dictionary) -> bool: return int(packet["peer"]) != peer_id
	_pending.assign(_pending.filter(from_other))
	_ready_packets.assign(_ready_packets.filter(from_other))
	_gone[peer_id] = true
	_events.append({"peer": peer_id, "connected": false})


func _now() -> float:
	return float(Time.get_ticks_usec()) / 1000000.0
