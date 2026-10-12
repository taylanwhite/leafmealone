extends Node

## Authority: host decides pass or fail. The client only reports what it can see.
## Covers connection, handshake, player replication, and a host-ordered zone move.

const TIMEOUT_SECONDS: float = 20.0

var _started_msec: int = 0
var _child_pid: int = -1
var _client_id: int = 0
var _saw_players: bool = false
var _moved: bool = false
var _reported_players: bool = false
var _leaf_phase: String = ""
var _watching_leaf: bool = false
var _leaf_at: Vector3 = Vector3.ZERO
var _leaf_expected: int = -1
var _watching_prop: bool = false
var _prop_at: Vector3 = Vector3.ZERO


func _ready() -> void:
	_started_msec = Time.get_ticks_msec()
	if Net.is_smoke_host():
		_launch_client()


func _process(_delta: float) -> void:
	if _elapsed() > TIMEOUT_SECONDS:
		_finish(false, "timed out")
		return
	if Net.is_smoke_host():
		_host_leaf_step()
	if Net.is_smoke_client():
		_client_process()


func _on_zone_changed(peer_id: int, zone: Net.Zone) -> void:
	if peer_id != Net.local_peer_id() or zone != Net.Zone.LOT:
		return
	var body := _find_player(peer_id)
	if body == null or body.global_position.x < 500.0:
		return
	_rpc_status.rpc_id(1, "zone_moved", 0.0)


func _launch_client() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	var arguments := PackedStringArray([
		"--headless",
		"--path",
		project_path,
		"--",
		"--join=127.0.0.1",
		"--port=%d" % Net.listen_port(),
		"--smoke-client",
		"--name=SmokeClient",
	])
	_child_pid = OS.create_process(OS.get_executable_path(), arguments)
	if _child_pid <= 0:
		_finish(false, "could not launch the smoke client")


func _client_process() -> void:
	if not _reported_players and _player_count() >= 2:
		_reported_players = true
		Net.player_zone_changed.connect(_on_zone_changed)
		_rpc_status.rpc_id(1, "players_visible", 0.0)
	if _watching_leaf:
		var field := get_tree().get_first_node_in_group("leaf_field")
		if field != null and Net.has_clock_sample() and int(field.call("sample_world", _leaf_at)) == _leaf_expected:
			_watching_leaf = false
			_rpc_status.rpc_id(1, "leaf_match", Net.server_time())
	if _watching_prop:
		var gnome := get_tree().root.find_child("Gnome", true, false) as Node3D
		if gnome != null and gnome.global_position.distance_to(_prop_at) < 1.0:
			_watching_prop = false
			_rpc_status.rpc_id(1, "prop_match", Net.server_time())


func _host_leaf_step() -> void:
	if _leaf_phase != "poke":
		return
	var body := _find_player(1)
	var field := get_tree().get_first_node_in_group("leaf_field")
	if body == null or field == null:
		return
	_leaf_phase = "wait"
	field.call("request_collect", body.global_position, 1.2)
	var sampled := int(field.call("sample_world", body.global_position))
	_rpc_leaf_target.rpc_id(_client_id, body.global_position, sampled)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_leaf_target(at: Vector3, expected: int) -> void:
	if not Net.is_smoke_client():
		return
	_leaf_at = at
	_leaf_expected = expected
	_watching_leaf = true


@rpc("any_peer", "call_remote", "reliable")
func _rpc_prop_target(at: Vector3) -> void:
	if not Net.is_smoke_client():
		return
	_prop_at = at
	_watching_prop = true


@rpc("any_peer", "call_remote", "reliable")
func _rpc_status(stage: String, client_time: float) -> void:
	if not Net.is_smoke_host():
		return
	_client_id = multiplayer.get_remote_sender_id()
	if stage == "players_visible" and not _saw_players:
		_saw_players = true
		if _player_count() < 2:
			_finish(false, "host cannot see both players")
			return
		Net.move_player_to_zone(_client_id, Net.Zone.LOT)
		_moved = true
	elif stage == "zone_moved" and _moved and _leaf_phase == "":
		Net.move_player_to_zone(1, Net.Zone.LOT)
		_leaf_phase = "poke"
	elif stage == "leaf_match" and _leaf_phase == "wait":
		if absf(client_time - Net.server_time()) > 0.05:
			_finish(false, "clock off by %.3f s" % absf(client_time - Net.server_time()))
			return
		var gnome := get_tree().root.find_child("Gnome", true, false) as Node3D
		if gnome == null:
			_finish(false, "gnome missing")
			return
		gnome.global_position += Vector3(2.0, 0.5, 0.0)
		_leaf_phase = "prop"
		_rpc_prop_target.rpc_id(_client_id, gnome.global_position)
	elif stage == "prop_match" and _leaf_phase == "prop":
		_finish(true, "")


func _player_count() -> int:
	return get_tree().get_nodes_in_group("players").size()


func _find_player(peer_id: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node as Node3D
	return null


func _elapsed() -> float:
	return float(Time.get_ticks_msec() - _started_msec) / 1000.0


func _finish(ok: bool, reason: String) -> void:
	set_process(false)
	if _child_pid > 0:
		var kill_error := OS.kill(_child_pid)
		if kill_error != OK:
			push_warning("[Smoke] could not kill client pid %d: %s" % [_child_pid, error_string(kill_error)])
	if ok:
		print("[Smoke] passed")
		get_tree().quit(0)
	else:
		push_error("[Smoke] failed: %s" % reason)
		print("[Smoke] failed: %s" % reason)
		get_tree().quit(1)
