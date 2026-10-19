extends Node

## Authority: host for membership, zones, and the registry. Each peer owns its movement.
## ENet session for M1. Steam lobby methods exist and report that Steam play is not available yet.

signal state_changed(new_state: State)
signal player_joined(peer_id: int)
signal player_left(peer_id: int)
signal session_ended(reason: String)
signal player_zone_changed(peer_id: int, zone: Zone)
signal ready_changed(peer_id: int, is_ready: bool)
signal speaking_changed(peer_id: int, is_speaking: bool)

enum Transport { ENET, STEAM }
enum State { OFFLINE, CONNECTING, LOBBY, IN_SESSION }
enum Zone { STORE, LOT, BORDER, TRANSIT }
enum VoiceMode { PUSH_TO_TALK, VOICE_ACTIVATION }

const CHANNEL_COUNT: int = 3
## ENet's throttle window for round-trip measurements, in milliseconds (ENet's default).
const ENET_THROTTLE_INTERVAL_MS: int = 5000
const _CommandLineScript = preload("res://net/command_line.gd")
const _ClockSyncScript = preload("res://net/clock_sync.gd")
const _LinkPeerScript = preload("res://net/dev/link_peer.gd")

var _state: State = State.OFFLINE
var _transport: Transport = Transport.ENET
var _hosting: bool = false
var _args: _CommandLineScript = _CommandLineScript.new()
var _local_name: String = ""
var _players: Dictionary = {}
var _clock: _ClockSyncScript = _ClockSyncScript.new()
var _ping_wait: float = 1.0
var _steam: Node
var _voice: Node


func _ready() -> void:
	_args = _CommandLineScript.new()
	_args.read()
	if _args.player_name != "":
		_local_name = _args.player_name
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	var telemetry := preload("res://net/telemetry.gd").new()
	telemetry.name = "Telemetry"
	add_child(telemetry)
	_steam = preload("res://net/steam_bridge.gd").new()
	_steam.name = "SteamBridge"
	add_child(_steam)
	_steam.call("setup", _args.no_steam)
	# Every peer gets the same Voice node path, which voice RPCs rely on.
	_voice = preload("res://net/voice/voice.gd").new()
	_voice.name = "Voice"
	add_child(_voice)
	if _args.smoke_test:
		_args.host = true
	if _args.host:
		var host_error := host(Transport.ENET)
		if host_error != OK:
			push_error("[Net] failed to host: %s" % error_string(host_error))
	elif _args.join_address != "":
		var join_error := join_enet(_args.join_address, _args.port)
		if join_error != OK:
			push_error("[Net] failed to join: %s" % error_string(join_error))
	if is_automated():
		var smoke := preload("res://net/smoke_test.gd").new()
		smoke.name = "SmokeTest"
		add_child(smoke)
	if _args.wants_dev_tools():
		var dev := preload("res://net/dev/dev_tools.gd").new()
		dev.name = "DevTools"
		add_child(dev)


func _process(delta: float) -> void:
	if _state == State.OFFLINE or _hosting:
		return
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_ping_wait += delta
	if _ping_wait < 1.0:
		return
	_ping_wait = 0.0
	_rpc_clock_ping.rpc_id(1, _clock.local_seconds())


## Start listening. Steam hosting is refused until lobbies exist.
func host(transport: Transport) -> Error:
	if transport == Transport.STEAM:
		if _steam == null or not bool(_steam.get("available")):
			push_warning("[Net] %s" % steam_unavailable_reason())
			return ERR_UNAVAILABLE
		_transport = Transport.STEAM
		_set_state(State.CONNECTING)
		_steam.call("create_friends_lobby")
		return OK
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(_args.port, Constants.MAX_PLAYERS - 1, CHANNEL_COUNT)
	if error != OK:
		push_error("[Net] create_server failed: %s" % error_string(error))
		return error
	multiplayer.multiplayer_peer = _maybe_wrap(peer)
	_transport = Transport.ENET
	_hosting = true
	_clock.start()
	_set_state(State.IN_SESSION)
	_add_player(local_peer_id(), _resolved_name(local_peer_id()), 0, _initial_zone())
	print("[Net] hosting on port %d" % _args.port)
	return OK


## Connect to an ENet host. The session stays CONNECTING until the world arrives.
func join_enet(address: String, port: int = Constants.DEFAULT_PORT) -> Error:
	_args.port = port
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port, CHANNEL_COUNT)
	if error != OK:
		push_error("[Net] create_client failed: %s" % error_string(error))
		return error
	multiplayer.multiplayer_peer = _maybe_wrap(peer)
	_transport = Transport.ENET
	_hosting = false
	_clock.start()
	_set_state(State.CONNECTING)
	print("[Net] joining %s:%d" % [address, port])
	return OK


## Join a Steam lobby by id. The lobby-joined callback finishes the connection.
func join_steam_lobby(lobby_id: int) -> Error:
	if _steam == null or not bool(_steam.get("available")):
		return ERR_UNAVAILABLE
	_transport = Transport.STEAM
	_set_state(State.CONNECTING)
	_steam.call("join_lobby", lobby_id)
	return OK


## Leave the session and return to the menu without a host-left reason.
func leave() -> void:
	_shutdown("")


## Open the Steam overlay invite dialog for the current lobby.
func invite_friends() -> void:
	if _steam != null:
		_steam.call("open_invite_dialog")


## True only after this peer successfully called host().
func is_host() -> bool:
	return _hosting


## Peer id while a multiplayer peer exists, otherwise 0.
func local_peer_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return 0
	return multiplayer.get_unique_id()


## Connected players, including this one, after the handshake.
func peer_ids() -> Array[int]:
	var ids: Array[int] = []
	for key: Variant in _players.keys():
		ids.append(int(key))
	ids.sort()
	return ids


## Display name recorded at hello. Empty if this peer is not in the registry yet.
func player_name(peer_id: int) -> String:
	if not _players.has(peer_id):
		return ""
	return str(_players[peer_id]["name"])


## Steam id, or 0 in ENet sessions.
func player_steam_id(peer_id: int) -> int:
	if not _players.has(peer_id):
		return 0
	return int(_players[peer_id]["steam_id"])


func current_transport() -> Transport:
	return _transport


func current_state() -> State:
	return _state


## Zone last assigned by the host.
func player_zone(peer_id: int) -> Zone:
	if not _players.has(peer_id):
		return _initial_zone()
	return _players[peer_id]["zone"] as Zone


## Peer ids currently in one zone.
func players_in_zone(zone: Zone) -> Array[int]:
	var ids: Array[int] = []
	for peer_id: int in peer_ids():
		if player_zone(peer_id) == zone:
			ids.append(peer_id)
	return ids


## Host only. Update the registry and tell every peer, including the owner, to teleport.
func move_player_to_zone(peer_id: int, zone: Zone, spawn_marker: StringName = &"") -> void:
	if not _hosting:
		push_error("[Net] move_player_to_zone is host only")
		return
	if not _players.has(peer_id):
		return
	_players[peer_id]["zone"] = zone
	_rpc_zone_changed.rpc(peer_id, int(zone), String(spawn_marker))


## Host clock in seconds since the session started. Clients use the ping estimate.
func server_time() -> float:
	return _clock.server_seconds(_hosting)


## Clock offset from the lowest-rtt sample, in seconds. 0 on the host.
func clock_offset_seconds() -> float:
	return _clock.offset_seconds()


## Most recent clock-ping round trip, in seconds.
func clock_rtt_seconds() -> float:
	return _clock.last_rtt_seconds()


## True after at least one clock pong has been folded in.
func has_clock_sample() -> bool:
	return _clock.has_sample()


## Round trip to one peer in milliseconds, or -1 when this transport cannot report it.
func peer_ping_ms(peer_id: int) -> int:
	if peer_id == local_peer_id():
		return 0
	var packet_peer := enet_link(peer_id)
	if packet_peer == null:
		return -1
	return packet_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)


## The ENet link to one peer, or null. A client links only to the host, so
## asking a client about another client returns null instead of an engine error.
func enet_link(peer_id: int) -> ENetPacketPeer:
	var enet := enet_peer()
	if enet == null or enet.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return null
	if not _hosting and peer_id != 1:
		return null
	return enet.get_peer(peer_id)


## The ENet peer under any development wrapper, or null on other transports.
func enet_peer() -> ENetMultiplayerPeer:
	var peer := multiplayer.multiplayer_peer
	if peer is _LinkPeerScript:
		peer = (peer as _LinkPeerScript).inner
	return peer as ENetMultiplayerPeer


## Bytes received and sent since the session started, or (-1, -1) when not counted.
## Counting needs the development wrapper, which --measure or --sim-lag turns on.
func bandwidth_totals() -> Vector2i:
	var link := multiplayer.multiplayer_peer as _LinkPeerScript
	if link == null:
		return Vector2i(-1, -1)
	return Vector2i(link.bytes_in, link.bytes_out)


## Simulated round trip added by --sim-lag, in milliseconds.
func simulated_lag_ms() -> int:
	return _args.sim_lag_ms


## Parsed command-line flags, for the development tools in net/dev/.
func dev_options() -> RefCounted:
	return _args


## Name used for a menu host or join. Ignored once the handshake has been sent.
func set_local_name(value: String) -> void:
	_local_name = value.strip_edges()


## Client request used by the debug zone gates.
func request_zone_move(zone: Zone) -> void:
	if _state == State.OFFLINE:
		return
	if _hosting:
		_apply_zone_request(local_peer_id(), zone)
	else:
		_rpc_request_zone.rpc_id(1, int(zone))


## Mark this peer ready. Stored for M2; the M1 menu does not show it.
func set_ready(value: bool) -> void:
	var peer_id := local_peer_id()
	if peer_id == 0:
		return
	if _hosting:
		_apply_ready(peer_id, value)
	else:
		_rpc_set_ready.rpc_id(1, value)


func is_player_ready(peer_id: int) -> bool:
	if not _players.has(peer_id):
		return false
	return bool(_players[peer_id]["ready"])


## Push-to-talk sends only while push_to_talk is held. Voice activation sends
## whenever Steam hears speech.
func set_voice_mode(mode: VoiceMode) -> void:
	_voice.call("set_mode", int(mode))


func voice_mode() -> VoiceMode:
	return int(_voice.call("mode")) as VoiceMode


## True in Steam sessions, and with --voice-test. ENet sessions have no voice otherwise.
func voice_available() -> bool:
	return bool(_voice.call("is_available"))


## Play a remote player's voice through this player, normally the
## AudioStreamPlayer3D on their head. Net sets its stream and starts it.
func attach_voice_output(peer_id: int, player: AudioStreamPlayer3D) -> void:
	_voice.call("attach_output", peer_id, player)


func is_player_speaking(peer_id: int) -> bool:
	return bool(_voice.call("is_speaking", peer_id))


## Local only: how loud this player hears another, 1.0 is normal.
func set_player_volume(peer_id: int, volume_linear: float) -> void:
	_voice.call("set_volume", peer_id, volume_linear)


func player_volume(peer_id: int) -> float:
	return float(_voice.call("volume", peer_id))


## Local only: stop hearing another player.
func set_player_muted(peer_id: int, muted: bool) -> void:
	_voice.call("set_muted", peer_id, muted)


func is_player_muted(peer_id: int) -> bool:
	return bool(_voice.call("is_muted", peer_id))


## True for the headless smoke host and the smoke client.
func is_automated() -> bool:
	return _args.smoke_test or _args.smoke_client


func is_smoke_host() -> bool:
	return _args.smoke_test


func is_smoke_client() -> bool:
	return _args.smoke_client


## Port from --port, or the default.
func listen_port() -> int:
	return _args.port


## Host start zone from --start-zone.
func start_zone() -> Zone:
	return _initial_zone()


## --lot value. 0 means the world may choose the test lot.
func requested_lot() -> int:
	return _args.lot


## True when steamInitEx succeeded.
func steam_available() -> bool:
	return _steam != null and bool(_steam.get("available"))


## Why the Steam host button is disabled, or empty when Steam is ready.
func steam_unavailable_reason() -> String:
	if _steam == null:
		return "Steam is not running"
	return str(_steam.get("unavailable_reason"))


## Host only. Leave the lobby screen and spawn the world.
func start_session() -> void:
	if not _hosting or _state != State.LOBBY:
		return
	_set_state(State.IN_SESSION)


## Called by SteamBridge after host_with_lobby succeeds.
func complete_steam_host(persona: String, steam_id: int) -> void:
	_transport = Transport.STEAM
	_hosting = true
	_clock.start()
	if persona != "":
		_local_name = persona
	_add_player(local_peer_id(), _resolved_name(local_peer_id()), steam_id, _initial_zone())
	_set_state(State.LOBBY)
	print("[Net] Steam lobby hosted")


## Called by SteamBridge after connect_to_lobby succeeds.
func complete_steam_join() -> void:
	_transport = Transport.STEAM
	_hosting = false
	_clock.start()
	_set_state(State.LOBBY)


## Called by SteamBridge when lobby setup fails.
func abandon_steam_lobby() -> void:
	_shutdown("Steam lobby failed")


## Called by the session when a replicated or local world is in the tree.
func notify_world_arrived() -> void:
	if _state == State.CONNECTING or _state == State.LOBBY:
		_set_state(State.IN_SESSION)


func _maybe_wrap(peer: MultiplayerPeer) -> MultiplayerPeer:
	if not _args.wants_link_peer():
		return peer
	print("[Net] link peer on: %d ms simulated round trip, %.1f%% loss" % [_args.sim_lag_ms, _args.sim_loss_percent])
	return _LinkPeerScript.new(peer, _args.sim_lag_ms, _args.sim_loss_percent / 100.0)


func _set_state(next_state: State) -> void:
	if _state == next_state:
		return
	_state = next_state
	state_changed.emit(next_state)


func _initial_zone() -> Zone:
	match _args.start_zone:
		"lot":
			return Zone.LOT
		"border":
			return Zone.BORDER
		"transit":
			return Zone.TRANSIT
		_:
			return Zone.STORE


func _resolved_name(peer_id: int) -> String:
	if _local_name != "":
		return _local_name
	return "Player %d" % peer_id


func _add_player(peer_id: int, display_name: String, steam_id: int, zone: Zone) -> void:
	if _players.has(peer_id):
		return
	_players[peer_id] = {
		"peer_id": peer_id,
		"name": display_name,
		"steam_id": steam_id,
		"zone": zone,
		"ready": false,
	}
	print("[Net] peer %d joined as %s" % [peer_id, display_name])
	player_joined.emit(peer_id)


func _registry_payload() -> Array:
	var payload: Array = []
	for peer_id: int in peer_ids():
		payload.append((_players[peer_id] as Dictionary).duplicate())
	return payload


func _replace_registry(payload: Array) -> void:
	_players.clear()
	for entry: Variant in payload:
		var record := entry as Dictionary
		var peer_id := int(record["peer_id"])
		record["zone"] = (int(record["zone"]) as Zone)
		_players[peer_id] = record
		player_joined.emit(peer_id)


func _apply_zone_request(peer_id: int, zone: Zone) -> void:
	if not _players.has(peer_id):
		return
	if zone != Zone.STORE and zone != Zone.LOT and zone != Zone.BORDER:
		return
	move_player_to_zone(peer_id, zone)


func _apply_ready(peer_id: int, value: bool) -> void:
	if not _players.has(peer_id):
		return
	_players[peer_id]["ready"] = value
	_rpc_ready_changed.rpc(peer_id, value)


func _teleport_owner(peer_id: int, zone: Zone, spawn_marker: String) -> void:
	if peer_id != local_peer_id():
		return
	var world := get_tree().get_first_node_in_group("world")
	if world == null or not world.has_method("get_spawn_transform"):
		return
	var at: Transform3D = world.call("get_spawn_transform", zone, StringName(spawn_marker), peer_id)
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name != str(peer_id) or not node.has_method("apply_network_teleport"):
			continue
		node.call("apply_network_teleport", at)
		return


func _shutdown(reason: String) -> void:
	_hosting = false
	_players.clear()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	_set_state(State.OFFLINE)
	if reason != "":
		print("[Net] session ended: %s" % reason)
		session_ended.emit(reason)


func _on_peer_connected(peer_id: int) -> void:
	# Handshake, not this signal, is what publishes a player.
	print("[Net] transport connected %d" % peer_id)
	_open_throttle(peer_id)


## ENet drops unreliable packets when round trips vary and recovers over many
## seconds. Movement is unreliable, so a loading hiccup on join made remote
## players stutter for about 20 seconds. Our traffic is small, so the throttle
## goes straight to full and never drops. Steam peers are not affected.
func _open_throttle(peer_id: int) -> void:
	var packet_peer := enet_link(peer_id)
	if packet_peer == null:
		return
	packet_peer.throttle_configure(ENET_THROTTLE_INTERVAL_MS, ENetPacketPeer.PACKET_THROTTLE_SCALE, 0)


func _on_peer_disconnected(peer_id: int) -> void:
	if not _hosting or not _players.has(peer_id):
		return
	_players.erase(peer_id)
	_rpc_player_removed.rpc(peer_id)
	print("[Net] peer %d left" % peer_id)
	player_left.emit(peer_id)


func _on_connected_to_server() -> void:
	var display_name := _local_name
	if _transport == Transport.STEAM and _steam != null:
		var persona := str(_steam.call("persona_name"))
		if persona != "":
			display_name = persona
	_rpc_hello.rpc_id(1, Constants.BUILD_VERSION, display_name)


func _on_connection_failed() -> void:
	_shutdown("Connection failed")


func _on_server_disconnected() -> void:
	_shutdown("Host left")


@rpc("any_peer", "call_remote", "reliable")
func _rpc_hello(build_version: String, display_name: String) -> void:
	if not _hosting:
		return
	var sender := multiplayer.get_remote_sender_id()
	if build_version != Constants.BUILD_VERSION:
		_rpc_rejected.rpc_id(sender, "Version mismatch")
		multiplayer.multiplayer_peer.disconnect_peer(sender)
		return
	var resolved := display_name if display_name != "" else "Player %d" % sender
	var steam_id := 0
	if _steam != null:
		steam_id = int(_steam.call("steam_id_for_peer", sender))
	_add_player(sender, resolved, steam_id, _initial_zone())
	_rpc_welcome.rpc_id(sender, _registry_payload())
	_rpc_player_added.rpc(sender, resolved, steam_id, int(_initial_zone()))


@rpc("authority", "call_remote", "reliable")
func _rpc_rejected(reason: String) -> void:
	_shutdown(reason)


@rpc("authority", "call_remote", "reliable")
func _rpc_welcome(payload: Array) -> void:
	_replace_registry(payload)


@rpc("authority", "call_remote", "reliable")
func _rpc_player_added(peer_id: int, display_name: String, steam_id: int, zone_value: int) -> void:
	_add_player(peer_id, display_name, steam_id, zone_value as Zone)


@rpc("authority", "call_remote", "reliable")
func _rpc_player_removed(peer_id: int) -> void:
	if not _players.has(peer_id):
		return
	_players.erase(peer_id)
	player_left.emit(peer_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_zone(zone_value: int) -> void:
	if not _hosting:
		return
	_apply_zone_request(multiplayer.get_remote_sender_id(), zone_value as Zone)


@rpc("authority", "call_local", "reliable")
func _rpc_zone_changed(peer_id: int, zone_value: int, spawn_marker: String) -> void:
	var zone := zone_value as Zone
	if _players.has(peer_id):
		_players[peer_id]["zone"] = zone
	# TRANSIT means the ride is carrying them. Do not teleport them to a spawn.
	if zone != Zone.TRANSIT:
		_teleport_owner(peer_id, zone, spawn_marker)
	player_zone_changed.emit(peer_id, zone)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_ready(value: bool) -> void:
	if not _hosting:
		return
	_apply_ready(multiplayer.get_remote_sender_id(), value)


@rpc("authority", "call_local", "reliable")
func _rpc_ready_changed(peer_id: int, value: bool) -> void:
	if _players.has(peer_id):
		_players[peer_id]["ready"] = value
	ready_changed.emit(peer_id, value)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _rpc_clock_ping(sent_local_seconds: float) -> void:
	if not _hosting:
		return
	_rpc_clock_pong.rpc_id(multiplayer.get_remote_sender_id(), sent_local_seconds, server_time())


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _rpc_clock_pong(sent_local_seconds: float, host_seconds: float) -> void:
	_clock.note_sample(sent_local_seconds, host_seconds, _clock.local_seconds())
